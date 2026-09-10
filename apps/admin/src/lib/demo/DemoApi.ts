/**
 * In-memory implementation of AdminApi for NEXT_PUBLIC_DEMO_MODE=true.
 * Mutations work (and are audited) and a synthetic "live" tick nudges the
 * dataset every few seconds so the dashboard feels real.
 */
import { buildCsv } from '../csv';
import { ApiRequestError, type AdminApi, type AuditFilters, type BookingFilters, type LiveEvent, type NotificationFilters, type OutletScoped, type QuotationFilters, type ReportFilters, type TeamMember, type WorkOrderFilters } from '../api';
import type {
  ActivityItem, AuditEvent, Booking, BookingDetail, ChecklistTemplate, CustomerDetail, CustomerSummary, ExceptionItem, FeatureFlag,
  IntegrationStatus, InventoryItem, Kpis, LoyaltyConfig, LoyaltyConfigResponse, LoyaltyRules, LoyaltyTierConfig, NotificationRow, Outlet, OutletService,
  Page, Payment, Period, QuoteLineItem, Quotation, ReportKind, ReportSummary, Service, SessionResponse, StaffPerformanceRow, StaffUser,
  TimelineStage, UserRole, WorkOrder, WorkStatus,
} from '../types';
import {
  AUDIT, BADGES, DEMO_PROFILES, FLAGS, INVENTORY, LEDGER, LOYALTY_ACCOUNTS, LOYALTY_CONFIGS, NOTIFICATIONS, OUTLETS, OUTLET_SERVICES, PAYMENTS,
  QUOTATIONS, SEED_BOOKINGS, SERVICES, STAFF_BADGES, TEMPLATES, TEN, VEHICLES, WORK_ORDERS, daysAgo, generateExtraBookings, nowIso, rel,
  outletName, outletShort, profileById, profileName, rng, serviceById, vehicleById, type RawBooking,
} from './data';

const clone = <T,>(v: T): T => JSON.parse(JSON.stringify(v)) as T;
const delay = (ms = 120) => new Promise<void>((r) => setTimeout(r, ms));
let seq = 1;
const nextId = (p: string) => `${p}-${Date.now().toString(36)}-${(seq++).toString(36)}`;

const ALLOWED: Record<WorkStatus, WorkStatus[]> = {
  queued: ['assigned', 'cancelled'],
  assigned: ['in_progress', 'queued', 'cancelled'],
  in_progress: ['blocked', 'completed'],
  blocked: ['in_progress', 'cancelled'],
  completed: ['verified', 'in_progress'],
  verified: [],
  cancelled: [],
};

export class DemoApi implements AdminApi {
  readonly mode = 'demo' as const;
  private actorId = 'seed_admin';
  private profiles = clone(DEMO_PROFILES);
  private outlets = clone(OUTLETS);
  private services = clone(SERVICES);
  private outletServices = clone(OUTLET_SERVICES);
  private templates = clone(TEMPLATES);
  private bookings: RawBooking[] = [...clone(SEED_BOOKINGS), ...generateExtraBookings()];
  private quotations = clone(QUOTATIONS);
  private workOrders = clone(WORK_ORDERS);
  private payments = clone(PAYMENTS);
  private inventory = clone(INVENTORY);
  private loyalty = clone(LOYALTY_CONFIGS);
  private ledger = clone(LEDGER);
  private flags = clone(FLAGS);
  private audit = clone(AUDIT);
  private notifications = clone(NOTIFICATIONS);
  private activityLog: ActivityItem[] = [];
  private listeners = new Set<(e: LiveEvent) => void>();
  private timer: ReturnType<typeof setInterval> | null = null;
  private tick = 0;

  constructor() {
    this.recomputeAlerts();
    this.seedActivity();
  }

  setActor(id: string) {
    this.actorId = id;
  }

  /* ------------------------------------------------------------ helpers */
  private actor() {
    return this.profiles.find((p) => p.id === this.actorId) ?? this.profiles[0];
  }
  private requireRole(...roles: UserRole[]) {
    if (!roles.includes(this.actor().role)) {
      throw new ApiRequestError(403, { code: 'forbidden', message: `This action requires role ${roles.join(' or ')}`, correlation_id: nextId('corr') });
    }
  }
  private log(action: string, entity_type: string, entity_id: string | null, before: unknown, after: unknown, outlet_id: string | null = null) {
    const a = this.actor();
    this.audit.unshift({ id: nextId('au'), actor_id: a.id, actor_name: a.full_name, actor_role: a.role, action, entity_type, entity_id, outlet_id, before, after, correlation_id: nextId('corr'), outcome: 'ok', created_at: nowIso() });
  }
  private emit(table: string) {
    const e = { table, at: nowIso() };
    this.listeners.forEach((l) => l(e));
  }
  private scoped<T extends { outlet_id: string }>(rows: T[], outletId?: string | null): T[] {
    return outletId ? rows.filter((r) => r.outlet_id === outletId) : rows;
  }
  private pushActivity(item: Omit<ActivityItem, 'id' | 'at'>) {
    this.activityLog.unshift({ id: nextId('act'), at: nowIso(), ...item });
    this.activityLog = this.activityLog.slice(0, 40);
  }
  private seedActivity() {
    const seed: (Omit<ActivityItem, 'id'> & { outlet?: string })[] = [
      { kind: 'completed', title: 'SPK-2026-0088 completed · Full Valet', subtitle: `Sandton · verified by Johan B.`, icon: 'check_circle', tone: 'success', at: rel(-5) },
      { kind: 'payment', title: 'R 240 payment verified · SPK-2026-0088', subtitle: 'Webhook confirmed · signature ok', icon: 'payments', tone: 'primary', at: rel(-50) },
      { kind: 'quote', title: 'Quote QT-2026-0038 accepted · R 2 100', subtitle: 'Converted to WO-2026-4818', icon: 'request_quote', tone: 'warning', at: rel(-130) },
      { kind: 'stock', title: 'Low stock: microfibre towels', subtitle: 'Rosebank · threshold 10', icon: 'notification_important', tone: 'error', at: rel(-25) },
      { kind: 'loyalty', title: '+120 pts posted · N. Mokoena', subtitle: 'Idempotent ledger entry · booking:…0005:earn', icon: 'loyalty', tone: 'primary', at: rel(-70) },
      { kind: 'blocked', title: 'WO-2026-4823 blocked', subtitle: 'Out of interior shampoo · Bay 3', icon: 'block', tone: 'error', at: rel(-24) },
      { kind: 'assigned', title: 'WO-2026-4821 assigned to Pieter v.d.M.', subtitle: 'Auto-assign: skill match, lowest load', icon: 'assignment_ind', tone: 'neutral', at: rel(-40) },
    ];
    this.activityLog = seed.map((s) => ({ id: nextId('act'), ...s })).sort((a, b) => b.at.localeCompare(a.at));
  }

  private recomputeAlerts() {
    for (const item of this.inventory) {
      const blocking = this.workOrders.filter((w) => w.status === 'blocked' && w.outlet.id === item.outlet_id && (w.blocked_reason ?? '').toLowerCase().includes(item.name.split(' ')[0].toLowerCase())).length;
      item.blocking_work_orders = blocking;
      if (item.on_hand <= 0) item.alert = item.alert?.level === 'out' ? item.alert : { id: nextId('al'), level: 'out', status: 'open', created_at: rel(-15) };
      else if (item.on_hand <= item.reorder_threshold) item.alert = item.alert?.level === 'low' ? item.alert : { id: nextId('al'), level: 'low', status: 'open', created_at: rel(-25) };
      else item.alert = null;
    }
  }

  private expandBooking(b: RawBooking): Booking {
    const s = serviceById(b.service_id);
    const v = vehicleById(b.vehicle_id);
    const c = profileById(b.customer_id);
    const w = this.workOrders.find((x) => x.booking_ref === b.ref) ?? null;
    const p = this.payments.find((x) => x.booking_ref === b.ref) ?? null;
    return {
      id: b.id, ref: b.ref, customer_id: b.customer_id, status: b.status, slot_start: b.slot_start, slot_end: b.slot_end, price_cents: b.price_cents,
      discount_cents: b.discount_cents, total_cents: b.total_cents, discount_label: b.discount_label, points_pending: b.points_pending, notes: b.notes,
      cancel_reason: b.cancel_reason, created_at: b.created_at, quotation_id: b.quotation_id,
      outlet: { id: b.outlet_id, name: outletName(b.outlet_id) },
      service: { id: s.id, name: s.name, category: s.category, duration_minutes: s.duration_minutes },
      vehicle: { id: v.id, registration_no: v.registration_no, make: v.make, model: v.model },
      customer: { id: b.customer_id, full_name: c?.full_name ?? 'Customer', email: c?.email ?? null, phone: c?.phone ?? null },
      work_order: w ? { id: w.id, ref: w.ref, status: w.status, stage: w.steps_done, stage_count: w.step_count, progress_pct: Math.round((w.steps_done / Math.max(1, w.step_count)) * 100), assignee_id: w.assignee_id, assignee_name: w.assignee_name, bay: w.bay, eta_at: w.eta_at, blocked_reason: w.blocked_reason } : null,
      payment: p ? { id: p.id, status: p.status, receipt_no: p.receipt_no, amount_cents: p.amount_cents } : null,
    };
  }

  private periodRange(period: Period): { from: Date; to: Date } {
    const to = new Date();
    const from = new Date(TEN);
    from.setHours(0, 0, 0, 0);
    if (period === 'week') from.setDate(from.getDate() - ((from.getDay() + 6) % 7));
    if (period === 'month') from.setDate(1);
    return { from, to };
  }

  /* ------------------------------------------------------------ auth */
  async session(): Promise<SessionResponse> {
    await delay();
    const a = this.actor();
    return { profile: { ...a, outlet_ids: a.outlet_ids }, claims_updated: false };
  }

  /* ------------------------------------------------------------ ops */
  async kpis(p: OutletScoped & { period: Period }): Promise<Kpis> {
    await delay();
    const todayBookings = this.scoped(this.bookings, p.outlet_id).filter((b) => b.slot_start.slice(0, 10) === TEN.toISOString().slice(0, 10) || new Date(b.slot_start).toDateString() === TEN.toDateString());
    const nowMs = Date.now();
    const rev = todayBookings.filter((b) => b.status === 'completed' || b.status === 'in_service').reduce((s, b) => s + b.total_cents, 0);
    const hours = Array.from({ length: 10 }, (_, i) => 7 + i);
    const currentHour = new Date().getHours();
    const bookings_by_hour = hours.map((h) => {
      const rows = todayBookings.filter((b) => new Date(b.slot_start).getHours() === h && b.status !== 'cancelled');
      return { hour: h, car_wash: rows.filter((b) => serviceById(b.service_id).category === 'car_wash').length, auto_body: rows.filter((b) => serviceById(b.service_id).category === 'auto_body').length, future: h > currentHour };
    });
    const outletsInScope = p.outlet_id ? this.outlets.filter((o) => o.id === p.outlet_id) : this.outlets;
    const r = rng(77 + (p.period === 'week' ? 1 : p.period === 'month' ? 2 : 0));
    const mult = p.period === 'today' ? 1 : p.period === 'week' ? 5.2 : 21.5;
    const revenue_by_outlet = outletsInScope.map((o) => {
      const base = todayBookings.filter((b) => b.outlet_id === o.id && (b.status === 'completed' || b.status === 'in_service')).reduce((s, b) => s + b.total_cents, 0);
      return { outlet_id: o.id, name: outletShort(o.id), revenue_cents: Math.round(base * mult * (0.9 + r() * 0.2)) };
    }).sort((a, b) => b.revenue_cents - a.revenue_cents);
    const wos = this.workOrders.filter((w) => !p.outlet_id || w.outlet.id === p.outlet_id);
    const completed = todayBookings.filter((b) => b.status === 'completed').length;
    const inService = todayBookings.filter((b) => b.status === 'in_service').length;
    const blocked = wos.filter((w) => w.status === 'blocked').length;
    const overdue = wos.filter((w) => w.due_at && new Date(w.due_at).getTime() < nowMs && !['completed', 'verified', 'cancelled'].includes(w.status)).length;
    const stock = this.scoped(this.inventory, p.outlet_id).filter((i) => i.alert).length;
    const failed = this.payments.filter((x) => x.status === 'failed').length;
    const perf = this.staffPoints(p.outlet_id, p.period);
    const quotes = this.quotations.filter((q) => !p.outlet_id || q.outlet.id === p.outlet_id);
    const accepted = quotes.filter((q) => ['accepted', 'converted'].includes(q.status)).length;
    const count = Math.round(todayBookings.filter((b) => b.status !== 'cancelled').length * mult);
    return {
      period: p.period,
      revenue_cents: Math.round(rev * mult),
      revenue_trend_pct: p.period === 'today' ? 12 : p.period === 'week' ? 8 : 5,
      revenue_compare_label: p.period === 'today' ? `vs ${this.fmtR(Math.round(rev * 0.89))} last ${new Date().toLocaleDateString('en-ZA', { weekday: 'long' })}` : `${outletsInScope.length} outlet${outletsInScope.length === 1 ? '' : 's'} · ${count} services`,
      bookings_count: count,
      bookings_completed: Math.round(completed * mult),
      bookings_in_service: inService,
      on_time_pct: 96,
      active_work_orders: wos.filter((w) => ['assigned', 'in_progress', 'blocked'].includes(w.status)).length,
      completed_today: wos.filter((w) => ['completed', 'verified'].includes(w.status)).length + completed,
      avg_cycle_minutes: 42,
      cycle_delta_minutes: -4,
      quotes_accepted: accepted + (p.period === 'today' ? 0 : p.period === 'week' ? 21 : 60),
      quotes_total: quotes.length + (p.period === 'today' ? 0 : p.period === 'week' ? 33 : 96),
      exceptions_count: blocked + overdue + stock + failed,
      exceptions_breakdown: { blocked, overdue, low_stock: stock, failed_payments: failed },
      bookings_by_hour,
      revenue_by_outlet,
      top_staff: perf.slice(0, 3).map((s, i) => ({ staff_id: s.staff_id, name: s.name.split(' ')[0], initials: s.name.split(' ').map((x) => x[0]).slice(0, 2).join(''), points: s.points_period, tier: (['gold', 'silver', 'bronze'] as const)[i] })),
      services_count: count,
      outlets_count: outletsInScope.length,
    };
  }
  private fmtR(c: number) {
    return `R ${Math.round(c / 100).toString().replace(/\B(?=(\d{3})+(?!\d))/g, ' ')}`;
  }

  async exceptions(p: OutletScoped): Promise<ExceptionItem[]> {
    await delay();
    const out: ExceptionItem[] = [];
    const now = Date.now();
    for (const w of this.workOrders.filter((w) => !p.outlet_id || w.outlet.id === p.outlet_id)) {
      if (w.status === 'blocked') {
        const mins = Math.max(1, Math.round((now - new Date(w.events.at(-1)?.created_at ?? w.updated_at).getTime()) / 60000));
        out.push({ id: `ex-b-${w.id}`, kind: 'blocked', title: `${w.ref} blocked ${mins} min`, subtitle: `${w.blocked_reason?.split('—')[0].trim() ?? 'Blocked'} · ${w.bay ?? outletShort(w.outlet.id)}`, severity: 'error', icon: 'block', link: { type: 'work_order', id: w.id }, created_at: w.updated_at });
      } else if (w.due_at && new Date(w.due_at).getTime() < now && !['completed', 'verified', 'cancelled'].includes(w.status)) {
        const mins = Math.round((now - new Date(w.due_at).getTime()) / 60000);
        out.push({ id: `ex-o-${w.id}`, kind: 'overdue', title: `${w.ref} over SLA +${mins} min`, subtitle: `${w.status === 'completed' ? 'Awaiting sign-off' : 'Not started'} · ${w.bay ?? outletShort(w.outlet.id)}`, severity: 'warning', icon: 'schedule', link: { type: 'work_order', id: w.id }, created_at: w.due_at });
      }
    }
    for (const i of this.scoped(this.inventory, p.outlet_id).filter((i) => i.alert)) {
      if (i.alert!.level === 'out') out.push({ id: `ex-s-${i.id}`, kind: 'out_of_stock', title: `${i.name} out`, subtitle: i.blocking_work_orders ? `Blocking ${i.blocking_work_orders} work order${i.blocking_work_orders > 1 ? 's' : ''}` : `${i.outlet_name} · reorder pending`, severity: 'error', icon: 'inventory_2', link: { type: 'inventory_item', id: i.id }, created_at: i.alert!.created_at });
      else out.push({ id: `ex-s-${i.id}`, kind: 'low_stock', title: `${i.name} low · ${i.on_hand} left`, subtitle: `Threshold ${i.reorder_threshold} · ${i.outlet_name}`, severity: 'warning', icon: 'inventory_2', link: { type: 'inventory_item', id: i.id }, created_at: i.alert!.created_at });
    }
    for (const pay of this.payments.filter((x) => x.status === 'failed')) {
      out.push({ id: `ex-p-${pay.id}`, kind: 'failed_payment', title: `Payment failed · ${pay.booking_ref}`, subtitle: `${this.fmtR(pay.amount_cents)} · ${pay.customer_name}`, severity: 'error', icon: 'credit_card_off', link: { type: 'payment', id: pay.id }, created_at: pay.created_at });
    }
    return out;
  }

  async activity(p: OutletScoped & { limit?: number }): Promise<ActivityItem[]> {
    await delay(80);
    return this.activityLog.slice(0, p.limit ?? 8);
  }

  /* ------------------------------------------------------------ bookings */
  async listBookings(f: BookingFilters): Promise<Page<Booking>> {
    await delay();
    const date = f.date ?? TEN.toISOString().slice(0, 10);
    let rows = this.scoped(this.bookings, f.outlet_id).filter((b) => {
      const d = new Date(b.slot_start);
      const local = `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, '0')}-${String(d.getDate()).padStart(2, '0')}`;
      return local === date;
    });
    if (f.status && f.status !== 'all') rows = rows.filter((b) => b.status === f.status);
    if (f.search) {
      const q = f.search.toLowerCase();
      rows = rows.filter((b) => b.ref.toLowerCase().includes(q) || (profileName(b.customer_id) ?? '').toLowerCase().includes(q) || vehicleById(b.vehicle_id).registration_no.toLowerCase().includes(q));
    }
    rows.sort((a, b) => a.slot_start.localeCompare(b.slot_start));
    const limit = f.limit ?? 50;
    const start = f.cursor ? Number(f.cursor) : 0;
    const page = rows.slice(start, start + limit);
    return { data: page.map((b) => this.expandBooking(b)), next_cursor: start + limit < rows.length ? String(start + limit) : null };
  }

  async getBooking(id: string): Promise<BookingDetail> {
    await delay();
    const b = this.bookings.find((x) => x.id === id);
    if (!b) throw new ApiRequestError(404, { code: 'not_found', message: 'Booking not found' });
    const exp = this.expandBooking(b);
    const w = this.workOrders.find((x) => x.booking_ref === b.ref);
    const tpl = this.templates.find((t) => t.id === serviceById(b.service_id).checklist_template_id);
    const timeline: TimelineStage[] = [{ key: 'checked_in', title: 'Checked in', state: w ? 'done' : b.status === 'cancelled' ? 'pending' : 'pending', at: w?.started_at ?? null }];
    if (tpl) {
      tpl.steps.forEach((s, i) => {
        const done = w ? i < w.steps_done : false;
        const current = w ? i === w.steps_done && !['completed', 'verified'].includes(w.status) : false;
        timeline.push({ key: s.key, title: s.title, state: done ? 'done' : current ? (w?.status === 'blocked' ? 'blocked' : 'current') : 'pending', at: done && w?.started_at ? new Date(new Date(w.started_at).getTime() + (i + 1) * 6 * 60000).toISOString() : null, actor: done ? w?.assignee_name : null });
      });
    }
    return { ...exp, timeline };
  }

  async cancelBooking(id: string, reason: string): Promise<Booking> {
    await delay();
    this.requireRole('admin', 'manager');
    const b = this.bookings.find((x) => x.id === id);
    if (!b) throw new ApiRequestError(404, { code: 'not_found', message: 'Booking not found' });
    if (['in_service', 'completed', 'cancelled'].includes(b.status)) throw new ApiRequestError(409, { code: 'invalid_transition', message: `Cannot cancel a booking that is ${b.status.replace('_', ' ')}` });
    const before = b.status;
    b.status = 'cancelled';
    b.cancel_reason = reason;
    this.log('booking.cancel', 'booking', b.id, { status: before }, { status: 'cancelled', reason }, b.outlet_id);
    this.emit('bookings');
    return this.expandBooking(b);
  }

  /* ------------------------------------------------------------ quotations */
  async listQuotations(f: QuotationFilters): Promise<Quotation[]> {
    await delay();
    let rows = this.quotations.filter((q) => !f.outlet_id || q.outlet.id === f.outlet_id);
    if (f.status && f.status !== 'all') rows = rows.filter((q) => q.status === f.status);
    return clone(rows.sort((a, b) => b.created_at.localeCompare(a.created_at)));
  }
  async getQuotation(id: string): Promise<Quotation> {
    await delay();
    const q = this.quotations.find((x) => x.id === id);
    if (!q) throw new ApiRequestError(404, { code: 'not_found', message: 'Quotation not found' });
    return clone(q);
  }
  async submitQuote(id: string, body: { amount_cents: number; line_items: QuoteLineItem[]; valid_until: string }): Promise<Quotation> {
    await delay();
    this.requireRole('supervisor', 'manager', 'admin');
    const q = this.quotations.find((x) => x.id === id);
    if (!q) throw new ApiRequestError(404, { code: 'not_found', message: 'Quotation not found' });
    if (!['requested', 'assessing', 'quoted'].includes(q.status)) throw new ApiRequestError(409, { code: 'invalid_transition', message: `Quotation is ${q.status}` });
    const a = this.actor();
    Object.assign(q, { status: 'quoted', amount_cents: body.amount_cents, line_items: body.line_items, valid_until: body.valid_until, quoted_at: nowIso(), assessor_id: a.id, assessor_name: a.full_name });
    this.log('quotation.quote', 'quotation', q.id, null, { amount_cents: body.amount_cents }, q.outlet.id);
    this.pushActivity({ kind: 'quote', title: `Quote ${q.ref} sent · ${this.fmtR(body.amount_cents)}`, subtitle: `${q.customer_name} notified via push + WhatsApp`, icon: 'request_quote', tone: 'warning' });
    this.emit('quotations');
    return clone(q);
  }
  async convertQuotation(id: string): Promise<Quotation> {
    await delay();
    this.requireRole('supervisor', 'manager', 'admin');
    const q = this.quotations.find((x) => x.id === id);
    if (!q) throw new ApiRequestError(404, { code: 'not_found', message: 'Quotation not found' });
    if (q.status !== 'accepted') throw new ApiRequestError(409, { code: 'invalid_transition', message: 'Only accepted quotations can be converted' });
    const ref = `WO-2026-${4826 + this.workOrders.length - 8}`;
    const v = VEHICLES.find((x) => x.id === q.vehicle.id)!;
    const cat = q.category.toLowerCase();
    const svc = this.services.find((s) => s.category === 'auto_body' && s.name.toLowerCase().includes(cat)) ?? this.services.find((s) => s.category === 'auto_body')!;
    const tpl = this.templates.find((t) => t.id === svc.checklist_template_id)!;
    const w: WorkOrder = { id: nextId('wo'), ref, outlet: q.outlet, booking_ref: null, quotation_ref: q.ref, customer_name: q.customer_name, vehicle: { registration_no: v.registration_no, make: v.make, model: v.model }, service: { name: svc.name, category: 'auto_body' }, status: 'queued', priority: 2, bay: null, assignee_id: null, assignee_name: null, eta_at: null, due_at: daysAgo(-3), started_at: null, blocked_reason: null, steps_done: 0, step_count: tpl.steps.length, task_id: nextId('task'), events: [], updated_at: nowIso() };
    this.workOrders.push(w);
    q.status = 'converted';
    q.work_order_ref = ref;
    this.log('quotation.convert', 'quotation', q.id, { status: 'accepted' }, { status: 'converted', work_order: ref }, q.outlet.id);
    this.pushActivity({ kind: 'quote', title: `Quote ${q.ref} converted · ${this.fmtR(q.amount_cents ?? 0)}`, subtitle: `Work order ${ref} queued`, icon: 'request_quote', tone: 'warning' });
    this.emit('work_orders');
    return clone(q);
  }

  /* ------------------------------------------------------------ work orders */
  async listWorkOrders(f: WorkOrderFilters): Promise<WorkOrder[]> {
    await delay();
    let rows = this.workOrders.filter((w) => !f.outlet_id || w.outlet.id === f.outlet_id);
    if (f.status && f.status !== 'all') rows = rows.filter((w) => w.status === f.status);
    return clone(rows);
  }
  async getWorkOrder(id: string): Promise<WorkOrder> {
    await delay();
    const w = this.workOrders.find((x) => x.id === id || x.ref === id);
    if (!w) throw new ApiRequestError(404, { code: 'not_found', message: 'Work order not found' });
    return clone(w);
  }
  async assignTask(taskId: string, body: { assignee_id: string; reason?: string }): Promise<WorkOrder> {
    await delay();
    this.requireRole('supervisor', 'manager', 'admin');
    const w = this.workOrders.find((x) => x.task_id === taskId);
    if (!w) throw new ApiRequestError(404, { code: 'not_found', message: 'Task not found' });
    const from = w.assignee_id;
    w.assignee_id = body.assignee_id;
    w.assignee_name = profileName(body.assignee_id);
    if (w.status === 'queued') w.status = 'assigned';
    w.events.push({ id: nextId('te'), actor_name: this.actor().full_name, event: 'assigned', from_status: from ? 'assigned' : 'queued', to_status: 'assigned', reason: body.reason ?? null, created_at: nowIso() });
    w.updated_at = nowIso();
    this.log('task.assign', 'task', taskId, { assignee: from }, { assignee: body.assignee_id, reason: body.reason }, w.outlet.id);
    this.pushActivity({ kind: 'assigned', title: `${w.ref} ${from ? 'reassigned' : 'assigned'} to ${w.assignee_name}`, subtitle: body.reason ?? `By ${this.actor().full_name}`, icon: 'assignment_ind', tone: 'neutral' });
    this.emit('work_orders');
    return clone(w);
  }
  async transitionTask(taskId: string, body: { to: WorkStatus; reason?: string }): Promise<WorkOrder> {
    await delay();
    this.requireRole('supervisor', 'manager', 'admin');
    const w = this.workOrders.find((x) => x.task_id === taskId);
    if (!w) throw new ApiRequestError(404, { code: 'not_found', message: 'Task not found' });
    if (!ALLOWED[w.status].includes(body.to)) throw new ApiRequestError(409, { code: 'invalid_transition', message: `Cannot move from ${w.status} to ${body.to}` });
    if (body.to === 'verified' && w.steps_done < w.step_count && !body.reason) throw new ApiRequestError(409, { code: 'invalid_transition', message: 'All required steps must be done, or an override reason recorded (STF-033)' });
    const from = w.status;
    w.status = body.to;
    if (body.to === 'blocked') w.blocked_reason = body.reason ?? 'Blocked';
    if (body.to === 'in_progress') { w.blocked_reason = null; w.started_at = w.started_at ?? nowIso(); }
    if (body.to === 'completed') w.steps_done = Math.max(w.steps_done, w.step_count - 1);
    if (body.to === 'verified') { w.steps_done = w.step_count; const b = this.bookings.find((x) => x.ref === w.booking_ref); if (b) b.status = 'completed'; }
    w.events.push({ id: nextId('te'), actor_name: this.actor().full_name, event: 'transition', from_status: from, to_status: body.to, reason: body.reason ?? null, created_at: nowIso() });
    w.updated_at = nowIso();
    this.log('task.transition', 'task', taskId, { status: from }, { status: body.to, reason: body.reason }, w.outlet.id);
    this.pushActivity({ kind: body.to === 'blocked' ? 'blocked' : body.to === 'verified' ? 'completed' : 'assigned', title: `${w.ref} → ${body.to.replace('_', ' ')}`, subtitle: body.reason ?? `${w.service.name} · ${w.vehicle.registration_no}`, icon: body.to === 'blocked' ? 'block' : body.to === 'verified' ? 'check_circle' : 'sync', tone: body.to === 'blocked' ? 'error' : body.to === 'verified' ? 'success' : 'neutral' });
    this.recomputeAlerts();
    this.emit('work_orders');
    return clone(w);
  }
  async team(p: OutletScoped): Promise<TeamMember[]> {
    await delay(60);
    return this.profiles.filter((x) => ['technician', 'supervisor'].includes(x.role) && x.is_active && (!p.outlet_id || x.outlet_ids.includes(p.outlet_id))).map((x) => ({ id: x.id, name: x.full_name, role: x.role, availability: x.availability ?? 'available', skills: x.skills, active_tasks: this.workOrders.filter((w) => w.assignee_id === x.id && ['assigned', 'in_progress', 'blocked'].includes(w.status)).length, capacity: x.role === 'supervisor' ? 5 : 3 }));
  }

  /* ------------------------------------------------------------ users */
  private toStaff(p: (typeof this.profiles)[number]): StaffUser {
    return { ...p, outlet_names: p.outlet_ids.map(outletShort), skills: p.skills };
  }
  async listUsers(): Promise<StaffUser[]> {
    await delay();
    return this.profiles.filter((p) => p.role !== 'customer').map((p) => this.toStaff(p));
  }
  async inviteUser(body: { email: string; full_name: string; role: UserRole; outlet_ids: string[] }): Promise<StaffUser> {
    await delay();
    this.requireRole('admin');
    if (this.profiles.some((p) => p.email?.toLowerCase() === body.email.toLowerCase())) throw new ApiRequestError(409, { code: 'conflict', message: 'A user with this e-mail already exists' });
    const p = { id: nextId('usr'), role: body.role, full_name: body.full_name, email: body.email, phone: null, avatar_url: null, is_active: true, marketing_opt_in: false, whatsapp_opt_in: true, push_opt_in: true, last_seen_at: null, created_at: nowIso(), outlet_ids: body.outlet_ids, skills: [] as string[], availability: 'available' as const };
    this.profiles.push(p);
    this.log('user.invite', 'profile', p.id, null, { email: body.email, role: body.role, outlet_ids: body.outlet_ids });
    return this.toStaff(p);
  }
  async updateUser(id: string, patch: { role?: UserRole; outlet_ids?: string[]; is_active?: boolean }): Promise<StaffUser> {
    await delay();
    this.requireRole('admin');
    const p = this.profiles.find((x) => x.id === id);
    if (!p) throw new ApiRequestError(404, { code: 'not_found', message: 'User not found' });
    const before = { role: p.role, outlet_ids: p.outlet_ids, is_active: p.is_active };
    Object.assign(p, patch);
    this.log('user.update', 'profile', id, before, patch);
    return this.toStaff(p);
  }

  private staffPoints(outletId: string | null | undefined, period: Period): StaffPerformanceRow[] {
    const base: Record<string, { tasks: number; cycle: number; compliance: number; total: number; week: number; month: number }> = {
      seed_pieter: { tasks: 52, cycle: 38, compliance: 98, total: 1420, week: 190, month: 690 },
      seed_lerato: { tasks: 44, cycle: 41, compliance: 96, total: 1180, week: 160, month: 570 },
      seed_sipho_staff: { tasks: 38, cycle: 55, compliance: 94, total: 975, week: 125, month: 480 },
      seed_thandi: { tasks: 30, cycle: 44, compliance: 91, total: 775, week: 100, month: 380 },
    };
    const rows = Object.entries(base).map(([id, b]) => {
      const p = this.profiles.find((x) => x.id === id)!;
      return { id, p, b };
    }).filter(({ p }) => !outletId || p.outlet_ids.includes(outletId));
    const out = rows.map(({ id, p, b }, i) => ({
      staff_id: id, name: p.full_name, outlet_name: outletShort(p.outlet_ids[0]), tasks_completed: period === 'today' ? Math.round(b.tasks / 12) : period === 'week' ? Math.round(b.tasks / 4) : b.tasks,
      avg_cycle_minutes: b.cycle, checklist_compliance_pct: b.compliance, points: b.total, points_period: period === 'today' ? Math.round(b.week / 5) : period === 'week' ? b.week : b.month, rank: i + 1, delta: [1, -1, 0, 2][i] ?? 0,
      badges: (STAFF_BADGES[id] ?? []).map((sb) => ({ ...BADGES.find((x) => x.code === sb.code)!, earned_at: daysAgo(sb.days) })),
    }));
    return out.sort((a, b) => b.points_period - a.points_period).map((r, i) => ({ ...r, rank: i + 1 }));
  }
  async staffPerformance(p: OutletScoped & { period: Period }): Promise<StaffPerformanceRow[]> {
    await delay();
    return this.staffPoints(p.outlet_id, p.period);
  }

  /* ------------------------------------------------------------ customers */
  private customerSummary(p: (typeof this.profiles)[number]): CustomerSummary {
    return { ...p, vehicle_count: VEHICLES.filter((v) => v.customer_id === p.id).length, booking_count: this.bookings.filter((b) => b.customer_id === p.id).length, loyalty: LOYALTY_ACCOUNTS.find((a) => a.customer_id === p.id) };
  }
  async searchCustomers(search: string): Promise<CustomerSummary[]> {
    await delay();
    this.requireRole('admin', 'manager', 'finance');
    const q = search.trim().toLowerCase();
    return this.profiles.filter((p) => p.role === 'customer' && (!q || p.full_name.toLowerCase().includes(q) || (p.email ?? '').toLowerCase().includes(q) || (p.phone ?? '').includes(q) || VEHICLES.some((v) => v.customer_id === p.id && v.registration_no.toLowerCase().includes(q)))).map((p) => this.customerSummary(p));
  }
  async getCustomer(id: string): Promise<CustomerDetail> {
    await delay();
    this.requireRole('admin', 'manager', 'finance');
    const p = this.profiles.find((x) => x.id === id && x.role === 'customer');
    if (!p) throw new ApiRequestError(404, { code: 'not_found', message: 'Customer not found' });
    this.log('customer.view', 'profile', id, null, { reason: 'admin lookup' });
    return { ...this.customerSummary(p), vehicles: VEHICLES.filter((v) => v.customer_id === id), bookings: this.bookings.filter((b) => b.customer_id === id).sort((a, b) => b.slot_start.localeCompare(a.slot_start)).map((b) => this.expandBooking(b)), ledger: this.ledger.filter((l) => l.customer_id === id).sort((a, b) => b.created_at.localeCompare(a.created_at)) };
  }

  /* ------------------------------------------------------------ catalogue */
  async listOutlets(): Promise<Outlet[]> { await delay(60); return clone(this.outlets); }
  async createOutlet(body: Partial<Outlet>): Promise<Outlet> {
    await delay(); this.requireRole('admin');
    const o: Outlet = { id: nextId('out'), code: body.code ?? 'NEW', name: body.name ?? 'New outlet', address_line: body.address_line ?? null, city: body.city ?? null, province: body.province ?? 'Gauteng', phone: body.phone ?? null, email: body.email ?? null, timezone: 'Africa/Johannesburg', opening_hours: body.opening_hours ?? OUTLETS[0].opening_hours, slot_minutes: body.slot_minutes ?? 30, bay_count: body.bay_count ?? 3, rating: null, is_active: body.is_active ?? true };
    this.outlets.push(o);
    this.outletServices.push(...this.services.map((s) => ({ outlet_id: o.id, service_id: s.id, price_cents: null, is_available: true })));
    this.log('outlet.create', 'outlet', o.id, null, body, o.id);
    return clone(o);
  }
  async updateOutlet(id: string, patch: Partial<Outlet>): Promise<Outlet> {
    await delay(); this.requireRole('admin');
    const o = this.outlets.find((x) => x.id === id);
    if (!o) throw new ApiRequestError(404, { code: 'not_found', message: 'Outlet not found' });
    const before = clone(o);
    Object.assign(o, patch);
    this.log('outlet.update', 'outlet', id, before, patch, id);
    return clone(o);
  }
  async listServices(): Promise<Service[]> { await delay(60); return clone(this.services); }
  async createService(body: Partial<Service>): Promise<Service> {
    await delay(); this.requireRole('admin');
    const s: Service = { id: nextId('svc'), code: body.code ?? 'NEW', name: body.name ?? 'New service', description: body.description ?? null, category: body.category ?? 'car_wash', duration_minutes: body.duration_minutes ?? 30, base_price_cents: body.base_price_cents ?? 0, is_quote_based: body.is_quote_based ?? false, points_per_rand: 0.1, icon: body.icon ?? 'local_car_wash', checklist_template_id: body.checklist_template_id ?? null, is_active: true, sort_order: 200 };
    this.services.push(s);
    this.outletServices.push(...this.outlets.map((o) => ({ outlet_id: o.id, service_id: s.id, price_cents: null, is_available: true })));
    this.log('service.create', 'service', s.id, null, body);
    return clone(s);
  }
  async updateService(id: string, patch: Partial<Service>): Promise<Service> {
    await delay(); this.requireRole('admin');
    const s = this.services.find((x) => x.id === id);
    if (!s) throw new ApiRequestError(404, { code: 'not_found', message: 'Service not found' });
    const before = clone(s);
    Object.assign(s, patch);
    this.log('service.update', 'service', id, before, patch);
    return clone(s);
  }
  async listOutletServices(): Promise<OutletService[]> { await delay(60); return clone(this.outletServices); }
  async setOutletService(outletId: string, serviceId: string, patch: Partial<OutletService>): Promise<OutletService> {
    await delay(); this.requireRole('admin');
    let os = this.outletServices.find((x) => x.outlet_id === outletId && x.service_id === serviceId);
    if (!os) { os = { outlet_id: outletId, service_id: serviceId, price_cents: null, is_available: true }; this.outletServices.push(os); }
    const before = clone(os);
    Object.assign(os, patch);
    this.log('outlet_service.update', 'outlet_service', `${outletId}:${serviceId}`, before, patch, outletId);
    return clone(os);
  }

  /* ------------------------------------------------------------ templates */
  async listTemplates(): Promise<ChecklistTemplate[]> { await delay(60); return clone(this.templates).sort((a, b) => a.name.localeCompare(b.name) || b.version - a.version); }
  async createTemplate(body: Pick<ChecklistTemplate, 'name' | 'category' | 'steps'>): Promise<ChecklistTemplate> {
    await delay(); this.requireRole('admin');
    const t: ChecklistTemplate = { id: nextId('tpl'), ...body, version: 1, status: 'draft', outlet_id: null, created_by: this.actorId, created_at: nowIso() };
    this.templates.push(t);
    this.log('template.create', 'checklist_template', t.id, null, { name: t.name, steps: t.steps.length });
    return clone(t);
  }
  async updateTemplate(id: string, body: Pick<ChecklistTemplate, 'name' | 'category' | 'steps'> & { publish: boolean }): Promise<ChecklistTemplate> {
    await delay(); this.requireRole('admin');
    const t = this.templates.find((x) => x.id === id);
    if (!t) throw new ApiRequestError(404, { code: 'not_found', message: 'Template not found' });
    if (body.publish) {
      // ADM-026: publishing creates a new version; the previous one is archived.
      const siblings = this.templates.filter((x) => x.name === t.name);
      const version = Math.max(...siblings.map((x) => x.version)) + 1;
      siblings.forEach((x) => { if (x.status === 'published') x.status = 'archived'; });
      if (t.status === 'draft') { t.status = 'archived'; }
      const nt: ChecklistTemplate = { id: nextId('tpl'), name: body.name, category: body.category, steps: body.steps, version, status: 'published', outlet_id: t.outlet_id, created_by: this.actorId, created_at: nowIso() };
      this.templates.push(nt);
      this.log('template.publish', 'checklist_template', nt.id, { version: t.version }, { version, steps: nt.steps.length });
      return clone(nt);
    }
    if (t.status !== 'draft') {
      const draft: ChecklistTemplate = { id: nextId('tpl'), name: body.name, category: body.category, steps: body.steps, version: t.version, status: 'draft', outlet_id: t.outlet_id, created_by: this.actorId, created_at: nowIso() };
      this.templates.push(draft);
      this.log('template.draft', 'checklist_template', draft.id, null, { from_version: t.version });
      return clone(draft);
    }
    Object.assign(t, { name: body.name, category: body.category, steps: body.steps });
    this.log('template.update', 'checklist_template', t.id, null, { steps: t.steps.length });
    return clone(t);
  }

  /* ------------------------------------------------------------ loyalty */
  async loyaltyConfig(): Promise<LoyaltyConfigResponse> {
    await delay();
    const published = this.loyalty.find((c) => c.status === 'published')!;
    const draft = this.loyalty.find((c) => c.status === 'draft') ?? null;
    return clone({ published, draft });
  }
  async saveLoyaltyDraft(body: { tiers: LoyaltyTierConfig[]; rules: LoyaltyRules; change_note: string }): Promise<LoyaltyConfig> {
    await delay(); this.requireRole('admin', 'manager');
    let draft = this.loyalty.find((c) => c.status === 'draft');
    const published = this.loyalty.find((c) => c.status === 'published')!;
    if (!draft) {
      draft = { id: nextId('lc'), version: Math.max(...this.loyalty.map((c) => c.version)) + 1, status: 'draft', tiers: body.tiers, rules: body.rules, change_note: body.change_note, created_by: this.actorId, published_by: null, published_at: null, created_at: nowIso() };
      this.loyalty.push(draft);
    } else {
      draft.tiers = body.tiers; draft.rules = body.rules; draft.change_note = body.change_note;
    }
    this.log('loyalty_config.draft', 'loyalty_config', draft.id, { version: published.version }, { version: draft.version, change_note: body.change_note });
    return clone(draft);
  }
  async publishLoyalty(): Promise<LoyaltyConfig> {
    await delay(300); this.requireRole('admin');
    const draft = this.loyalty.find((c) => c.status === 'draft');
    if (!draft) throw new ApiRequestError(409, { code: 'conflict', message: 'There is no draft to publish' });
    const published = this.loyalty.find((c) => c.status === 'published')!;
    published.status = 'archived';
    draft.status = 'published'; draft.published_by = this.actorId; draft.published_at = nowIso();
    this.log('loyalty_config.publish', 'loyalty_config', draft.id, { version: published.version }, { version: draft.version });
    this.pushActivity({ kind: 'loyalty', title: `Loyalty config v${draft.version} published`, subtitle: 'Takes effect server-side within 60 s', icon: 'loyalty', tone: 'primary' });
    this.emit('loyalty_configs');
    return clone(draft);
  }
  async discardLoyalty(): Promise<void> {
    await delay(); this.requireRole('admin', 'manager');
    const draft = this.loyalty.find((c) => c.status === 'draft');
    if (!draft) return;
    this.loyalty = this.loyalty.filter((c) => c.id !== draft.id);
    this.log('loyalty_config.discard', 'loyalty_config', draft.id, { version: draft.version }, null);
  }

  /* ------------------------------------------------------------ inventory */
  async listInventory(p: OutletScoped & { alerts_first?: boolean }): Promise<InventoryItem[]> {
    await delay();
    this.recomputeAlerts();
    const rows = clone(this.scoped(this.inventory, p.outlet_id));
    const rank = (i: InventoryItem) => (i.alert?.level === 'out' ? 0 : i.alert?.level === 'low' ? 1 : 2);
    rows.sort((a, b) => (p.alerts_first === false ? 0 : rank(a) - rank(b)) || a.name.localeCompare(b.name));
    return rows;
  }
  async updateInventoryItem(id: string, patch: { reorder_threshold?: number; name?: string; unit?: string }): Promise<InventoryItem> {
    await delay(); this.requireRole('admin', 'manager');
    const i = this.inventory.find((x) => x.id === id);
    if (!i) throw new ApiRequestError(404, { code: 'not_found', message: 'Item not found' });
    const before = { reorder_threshold: i.reorder_threshold, name: i.name, unit: i.unit };
    Object.assign(i, patch, { updated_at: nowIso() });
    this.recomputeAlerts();
    this.log('inventory.threshold', 'inventory_item', id, before, patch, i.outlet_id);
    this.emit('inventory_alerts');
    return clone(i);
  }
  async addMovement(id: string, body: { delta: number; reason: 'usage' | 'receive' | 'adjust' | 'reorder_request' | 'count'; note?: string }): Promise<InventoryItem> {
    await delay(); this.requireRole('admin', 'manager', 'supervisor');
    const i = this.inventory.find((x) => x.id === id);
    if (!i) throw new ApiRequestError(404, { code: 'not_found', message: 'Item not found' });
    if (i.on_hand + body.delta < 0) throw new ApiRequestError(400, { code: 'validation_error', message: 'Stock cannot go negative (STF-043)' });
    const before = i.on_hand;
    if (body.reason !== 'reorder_request') i.on_hand += body.delta;
    i.updated_at = nowIso();
    this.recomputeAlerts();
    this.log(`inventory.${body.reason}`, 'inventory_item', id, { on_hand: before }, { on_hand: i.on_hand, delta: body.delta, note: body.note }, i.outlet_id);
    this.pushActivity({ kind: 'stock', title: body.reason === 'reorder_request' ? `Reorder requested: ${i.name}` : `${i.name} ${body.delta > 0 ? '+' : ''}${body.delta} ${i.unit}`, subtitle: `${i.outlet_name} · now ${i.on_hand} / threshold ${i.reorder_threshold}`, icon: 'inventory_2', tone: i.alert ? 'error' : 'success' });
    this.emit('inventory_alerts');
    return clone(i);
  }

  /* ------------------------------------------------------------ payments / reports / audit / flags */
  async listPayments(p: OutletScoped): Promise<Payment[]> {
    await delay();
    const refs = new Set(this.scoped(this.bookings, p.outlet_id).map((b) => b.ref));
    return clone(this.payments.filter((x) => !p.outlet_id || (x.booking_ref && refs.has(x.booking_ref))).sort((a, b) => b.created_at.localeCompare(a.created_at)));
  }
  async reportSummary(f: ReportFilters): Promise<ReportSummary> {
    await delay();
    const rows = this.scoped(this.bookings, f.outlet_id).filter((b) => b.slot_start.slice(0, 10) >= f.from && b.slot_start.slice(0, 10) <= f.to);
    const paid = rows.filter((b) => b.status === 'completed' || b.status === 'in_service');
    const revenue = paid.reduce((s, b) => s + b.total_cents, 0);
    const byOutlet = this.outlets.filter((o) => !f.outlet_id || o.id === f.outlet_id).map((o) => ({ name: outletShort(o.id), revenue_cents: paid.filter((b) => b.outlet_id === o.id).reduce((s, b) => s + b.total_cents, 0), bookings: rows.filter((b) => b.outlet_id === o.id).length }));
    const byService = this.services.map((s) => ({ name: s.name, revenue_cents: paid.filter((b) => b.service_id === s.id).reduce((x, b) => x + b.total_cents, 0), count: rows.filter((b) => b.service_id === s.id).length })).filter((x) => x.count > 0).sort((a, b) => b.revenue_cents - a.revenue_cents);
    const q = this.quotations;
    return {
      financial: { revenue_cents: revenue, refunds_cents: 0, payments_successful: this.payments.filter((p) => p.status === 'successful').length, payments_failed: this.payments.filter((p) => p.status === 'failed').length, avg_ticket_cents: paid.length ? Math.round(revenue / paid.length) : 0, by_outlet: byOutlet, by_service: byService },
      operational: { bookings: rows.length, completed: rows.filter((b) => b.status === 'completed').length, cancelled: rows.filter((b) => b.status === 'cancelled').length, on_time_pct: 96, avg_cycle_minutes: 42, checklist_compliance_pct: 95, quotes: { requested: q.length, quoted: q.filter((x) => ['quoted', 'accepted', 'converted', 'declined'].includes(x.status)).length, accepted: q.filter((x) => ['accepted', 'converted'].includes(x.status)).length, converted: q.filter((x) => x.status === 'converted').length } },
    };
  }
  async exportCsv(report: ReportKind, filters: Record<string, string | undefined>): Promise<string> {
    await delay(200);
    this.requireRole('admin', 'manager', 'finance');
    const scope = filters.outlet_id ? outletName(filters.outlet_id) : 'all outlets';
    const meta = { report, generated_by: this.actor().email ?? this.actor().full_name, scope, filters };
    switch (report) {
      case 'bookings': {
        const rows = (await this.listBookings({ outlet_id: filters.outlet_id, date: filters.date, status: (filters.status as BookingFilters['status']) ?? 'all', limit: 500 })).data;
        return buildCsv(meta, ['ref', 'customer', 'vehicle', 'outlet', 'service', 'slot_start', 'status', 'price_cents', 'discount_cents', 'total_cents'], rows.map((b) => ({ ref: b.ref, customer: b.customer.full_name, vehicle: b.vehicle.registration_no, outlet: b.outlet.name, service: b.service.name, slot_start: b.slot_start, status: b.status, price_cents: b.price_cents, discount_cents: b.discount_cents, total_cents: b.total_cents })));
      }
      case 'payments':
        return buildCsv(meta, ['id', 'booking_ref', 'customer', 'provider', 'amount_cents', 'status', 'receipt_no', 'verified_at', 'created_at'], (await this.listPayments({ outlet_id: filters.outlet_id })).map((p) => ({ ...p, customer: p.customer_name })));
      case 'inventory':
        return buildCsv(meta, ['sku', 'name', 'outlet', 'unit', 'on_hand', 'reorder_threshold', 'alert'], (await this.listInventory({ outlet_id: filters.outlet_id })).map((i) => ({ sku: i.sku, name: i.name, outlet: i.outlet_name, unit: i.unit, on_hand: i.on_hand, reorder_threshold: i.reorder_threshold, alert: i.alert?.level ?? '' })));
      case 'staff_performance':
        return buildCsv(meta, ['staff', 'outlet', 'tasks_completed', 'avg_cycle_minutes', 'checklist_compliance_pct', 'points', 'rank'], this.staffPoints(filters.outlet_id, (filters.period as Period) ?? 'week').map((r) => ({ staff: r.name, outlet: r.outlet_name, tasks_completed: r.tasks_completed, avg_cycle_minutes: r.avg_cycle_minutes, checklist_compliance_pct: r.checklist_compliance_pct, points: r.points_period, rank: r.rank })));
      case 'loyalty':
        return buildCsv(meta, ['customer', 'tier', 'balance_points', 'lifetime_points', 'tier_since'], LOYALTY_ACCOUNTS.map((a) => ({ customer: profileName(a.customer_id), tier: a.tier, balance_points: a.balance_points, lifetime_points: a.lifetime_points, tier_since: a.tier_since })));
    }
  }
  async listAudit(f: AuditFilters): Promise<Page<AuditEvent>> {
    await delay();
    this.requireRole('admin', 'manager', 'finance');
    let rows = [...this.audit].sort((a, b) => b.created_at.localeCompare(a.created_at));
    if (f.entity_type) rows = rows.filter((r) => r.entity_type === f.entity_type);
    if (f.action) rows = rows.filter((r) => r.action.startsWith(f.action!));
    if (f.actor) rows = rows.filter((r) => (r.actor_name ?? '').toLowerCase().includes(f.actor!.toLowerCase()));
    const limit = f.limit ?? 25;
    const start = f.cursor ? Number(f.cursor) : 0;
    return { data: clone(rows.slice(start, start + limit)), next_cursor: start + limit < rows.length ? String(start + limit) : null };
  }
  async listFlags(): Promise<FeatureFlag[]> { await delay(60); return clone(this.flags); }
  async updateFlag(key: string, enabled: boolean): Promise<FeatureFlag> {
    await delay(); this.requireRole('admin');
    const f = this.flags.find((x) => x.key === key);
    if (!f) throw new ApiRequestError(404, { code: 'not_found', message: 'Flag not found' });
    const before = f.enabled;
    f.enabled = enabled; f.updated_at = nowIso();
    this.log('flag.update', 'feature_flag', key, { enabled: before }, { enabled });
    return clone(f);
  }
  async integrations(): Promise<IntegrationStatus[]> {
    await delay(60);
    const wa = Boolean(this.flags.find((f) => f.key === 'whatsapp_enabled')?.enabled);
    return [
      { key: 'supabase', name: 'Supabase Postgres + Realtime', status: 'demo', detail: 'Demo mode · in-memory dataset mirrors seed.sql (project uicqczgpiqkczwyssdft when live)', icon: 'database' },
      { key: 'firebase', name: 'Firebase Auth · sparkling-4e89d', status: 'demo', detail: 'Demo session · email/password + Google when NEXT_PUBLIC_DEMO_MODE=false', icon: 'verified_user' },
      { key: 'payments', name: 'Payments provider', status: 'sandbox', detail: 'Sandbox adapter · webhook HMAC verified · no real charges', icon: 'payments' },
      {
        key: 'whatsapp', name: 'WhatsApp Business', status: wa ? 'connected' : 'disabled',
        detail: wa ? 'Twilio Messaging Service · templates approved · status callbacks on' : 'Twilio configured · sending paused (flag whatsapp_enabled off)',
        icon: 'chat', provider: 'twilio', configured: true, messaging_service: 'MGa1b2c3d4e5f67890abcdef12347660', enabled: wa,
      },
    ];
  }

  /* ------------------------------------------------------------ notifications */
  async listNotifications(f: NotificationFilters): Promise<Page<NotificationRow>> {
    await delay();
    this.requireRole('admin', 'manager', 'finance');
    let rows = [...this.notifications].sort((a, b) => b.created_at.localeCompare(a.created_at));
    if (f.status && f.status !== 'all') rows = rows.filter((n) => n.status === f.status);
    if (f.channel && f.channel !== 'all') rows = rows.filter((n) => n.channel === f.channel);
    const limit = f.limit ?? 25;
    const start = f.cursor ? Number(f.cursor) : 0;
    return { data: clone(rows.slice(start, start + limit)), next_cursor: start + limit < rows.length ? String(start + limit) : null };
  }
  async resendNotification(id: string): Promise<NotificationRow> {
    await delay(250);
    this.requireRole('admin', 'manager');
    const n = this.notifications.find((x) => x.id === id);
    if (!n) throw new ApiRequestError(404, { code: 'not_found', message: 'Notification not found' });
    if (n.status === 'delivered') throw new ApiRequestError(409, { code: 'conflict', message: 'This message was already delivered' });
    const before = { status: n.status, provider_status: n.provider_status, provider_error_code: n.provider_error_code, attempts: n.attempts };
    n.status = 'sent';
    n.provider_status = n.channel === 'whatsapp' ? 'sent' : null;
    n.provider_error_code = null;
    n.error = null;
    n.attempts += 1;
    n.sent_at = nowIso();
    n.delivered_at = null;
    if (n.channel === 'whatsapp') n.provider_ref = `SM${nextId('re').replace(/-/g, '').padEnd(32, '0').slice(0, 32)}`;
    this.log('notification.resend', 'notification', n.id, before, { status: 'sent', attempts: n.attempts, template_key: n.template_key });
    this.pushActivity({ kind: 'assigned', title: `${n.template_key} re-sent to ${n.recipient_name ?? n.recipient_id}`, subtitle: `${n.channel === 'whatsapp' ? 'WhatsApp (Twilio)' : n.channel} · attempt ${n.attempts}`, icon: 'forward_to_inbox', tone: 'primary' });
    this.emit('notifications');
    return clone(n);
  }

  /* ------------------------------------------------------------ live tick */
  subscribe(listener: (e: LiveEvent) => void): () => void {
    this.listeners.add(listener);
    if (!this.timer) this.timer = setInterval(() => this.onTick(), 9000);
    return () => {
      this.listeners.delete(listener);
      if (this.listeners.size === 0 && this.timer) { clearInterval(this.timer); this.timer = null; }
    };
  }
  private onTick() {
    this.tick += 1;
    const r = rng(1000 + this.tick);
    const step = this.tick % 4;
    if (step === 0) {
      // progress the in-service work order (WO-2026-4821) a step
      const w = this.workOrders.find((x) => x.ref === 'WO-2026-4821');
      if (w && w.status === 'in_progress' && w.steps_done < w.step_count - 1) {
        w.steps_done += 1; w.updated_at = nowIso();
        this.pushActivity({ kind: 'assigned', title: `${w.ref} step ${w.steps_done}/${w.step_count} done`, subtitle: `${w.assignee_name} · ${w.bay}`, icon: 'task_alt', tone: 'primary' });
        this.emit('work_orders');
      }
    } else if (step === 1) {
      // a confirmed booking whose slot has started moves to in_service
      const b = this.bookings.filter((x) => x.status === 'confirmed' && new Date(x.slot_start).getTime() <= Date.now()).sort((a, c) => a.slot_start.localeCompare(c.slot_start))[0];
      if (b) {
        b.status = 'in_service';
        this.pushActivity({ kind: 'assigned', title: `${b.ref} checked in · ${serviceById(b.service_id).name}`, subtitle: `${outletShort(b.outlet_id)} · ${vehicleById(b.vehicle_id).registration_no}`, icon: 'login', tone: 'neutral' });
        this.emit('bookings');
      }
    } else if (step === 2) {
      // an in-service booking completes and pays
      const b = this.bookings.filter((x) => x.status === 'in_service' && !this.workOrders.some((w) => w.booking_ref === x.ref)).sort((a, c) => a.slot_start.localeCompare(c.slot_start))[0];
      if (b) {
        b.status = 'completed';
        const receipt = `RCP-${70010 + this.payments.length}`;
        this.payments.unshift({ id: nextId('pay'), booking_ref: b.ref, customer_name: profileName(b.customer_id) ?? 'Customer', provider: 'sandbox', amount_cents: b.total_cents, status: 'successful', receipt_no: receipt, verified_at: nowIso(), created_at: nowIso() });
        this.pushActivity({ kind: 'completed', title: `${b.ref} completed · ${serviceById(b.service_id).name}`, subtitle: `${outletShort(b.outlet_id)} · ${vehicleById(b.vehicle_id).registration_no}`, icon: 'check_circle', tone: 'success' });
        this.pushActivity({ kind: 'payment', title: `${this.fmtR(b.total_cents)} payment verified · ${b.ref}`, subtitle: `Webhook confirmed · ${receipt}`, icon: 'payments', tone: 'primary' });
        const pts = Math.round((b.total_cents / 100) * 0.1);
        this.ledger.unshift({ id: nextId('ll'), customer_id: b.customer_id, delta: pts, type: 'earn', reference: b.ref, description: serviceById(b.service_id).name, idempotency_key: `booking:${b.id}:earn`, created_at: nowIso() });
        this.pushActivity({ kind: 'loyalty', title: `+${pts} pts posted · ${(profileName(b.customer_id) ?? 'C').split(' ').map((x, i) => (i === 0 ? x[0] + '.' : x)).join(' ')}`, subtitle: `Idempotent ledger entry · booking:…:earn`, icon: 'loyalty', tone: 'primary' });
        this.emit('payments');
      }
    } else if (r() < 0.5) {
      const i = this.inventory.filter((x) => x.on_hand > x.reorder_threshold + 1)[Math.floor(r() * 5)];
      if (i) { i.on_hand -= 1; i.updated_at = nowIso(); this.recomputeAlerts(); this.emit('inventory_items'); }
    }
  }
}
