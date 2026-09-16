/**
 * In-memory implementation of AdminApi for NEXT_PUBLIC_DEMO_MODE=true.
 * Mutations work (and are audited) and a synthetic "live" tick nudges the
 * dataset every few seconds so the dashboard feels real.
 */
import { buildCsv } from '../csv';
import { ApiRequestError, uuid, type AdminApi, type AuditFilters, type BookingFilters, type LiveEvent, type MembershipFilters, type NotificationFilters, type OutletOfferFilters, type OutletScoped, type QuotationFilters, type ReportFilters, type TeamMember, type WorkOrderFilters } from '../api';
import {
  SERVICE_GROUPS, VAT_RATE, priceLabel, vehicleSizeOf,
  type ActivityItem, type AuditEvent, type AvailabilitySlot, type Booking, type BookingDetail, type ChecklistTemplate, type CreateStaffInput, type CreateStaffResult, type CustomerDetail, type CustomerSummary, type EnrolMembershipInput, type ExceptionItem, type FeatureFlag,
  type IntegrationStatus, type InventoryItem, type Kpis, type LoyaltyConfig, type LoyaltyConfigResponse, type LoyaltyRules, type LoyaltySummary, type LoyaltyTierConfig, type Membership, type MembershipAllowance, type MembershipBenefit,
  type MembershipInvoice, type MembershipPlan, type MembershipPlanInput, type MembershipPricing, type MembershipRow, type MembershipStatus, type MembershipSummary, type NotificationRow, type Outlet, type OutletServiceInput,
  type OutletServiceOffer, type Page, type Payment, type Period, type PlanEntitlement, type PosPayment, type QuoteLineItem, type Quotation, type QuotationAttachment, type RaiseQuotationInput, type RecordMembershipPaymentResult, type RecordPaymentInput, type RenewalRunResult, type ReportKind,
  type Profile, type ReportSummary, type ResetPasswordResult, type Service, type ServiceComponent, type ServiceInput, type SessionResponse, type ShareQuotationResult, type StaffPerformanceRow, type StaffUser, type TimelineStage, type UserRole, type Vehicle, type VehicleInput,
  type VehicleSize, type WalkInBookingInput, type WalkInBookingResult, type WalkInCustomer, type WalkInCustomerInput, type WorkOrder, type WorkStatus,
} from '../types';
import { applyDemoDecision, demoPhotoUrl, demoSeedToken, pdfInputFromQuotation, registerDemoPhoto, registerDemoPublicQuote, syncDemoPublicQuote, withOutletLegal } from './publicQuotes';
import { QUOTE_TERMS } from '../quoteTerms';
import { PHONE_HINT, normalisePhone } from '../phone';
import { buildQuotePdf } from './quotePdf';
import {
  AUDIT, BADGES, DEMO_PROFILES, FLAGS, INVENTORY, LEDGER, LOYALTY_ACCOUNTS, LOYALTY_CONFIGS, NOTIFICATIONS, OUTLETS, OUTLET_COMPONENTS, OUTLET_OFFERS, PAYMENTS,
  QUOTATIONS, SEED_BOOKINGS, SERVICES, STAFF_BADGES, TEMPLATES, TEN, VEHICLES, WORK_ORDERS, daysAgo, effectivePricing, generateExtraBookings, nowIso, rel,
  outletName, outletShort, profileById, profileName, rng, serviceById, vehicleById, type RawBooking,
} from './data';
import type { CatalogueComponent, CatalogueOffer } from './catalogue';
import { ENTITLEMENTS, GROUPS, MEMBERSHIPS, MEMBERSHIP_INVOICES, PLANS, SELECTIONS, USAGE, addMonths, addYears, type RawEntitlement, type RawGroup, type RawPlan, type RawSelection, type RawUsage } from './memberships';

const LIVE_MEMBERSHIP: MembershipStatus[] = ['pending', 'active', 'past_due'];
const COUNTER_METHODS = ['cash', 'card_terminal', 'eft'] as const;

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
  private vehicles: Vehicle[] = clone(VEHICLES);
  private loyaltyAccounts = clone(LOYALTY_ACCOUNTS);
  private outlets = clone(OUTLETS);
  private services: Service[] = clone(SERVICES);
  /** `outlet_services` rows (per-outlet wording, prices, overrides, availability). */
  private outletServices: CatalogueOffer[] = clone(OUTLET_OFFERS);
  /** Outlet-specific `service_components` rows (override the global `Service.components` set). */
  private components: CatalogueComponent[] = clone(OUTLET_COMPONENTS);
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
  /* membership plans (migration 0010) */
  private plans: RawPlan[] = clone(PLANS);
  private groups: RawGroup[] = clone(GROUPS);
  private entitlements: RawEntitlement[] = clone(ENTITLEMENTS);
  private memberships: Membership[] = clone(MEMBERSHIPS);
  private selections: RawSelection[] = clone(SELECTIONS);
  /** Append-only: +1 per redeemed booking, −1 release row on cancel. */
  private usage: RawUsage[] = clone(USAGE);
  private mInvoices: MembershipInvoice[] = clone(MEMBERSHIP_INVOICES);
  private activityLog: ActivityItem[] = [];
  /** Idempotency: client_op_id / idempotency_key → created entity id (ARC-004). */
  private ops = new Map<string, string>();
  private posPayments: PosPayment[] = [];
  private listeners = new Set<(e: LiveEvent) => void>();
  private timer: ReturnType<typeof setInterval> | null = null;
  private tick = 0;
  /** Public quote links: quotation id → token / expiry (the token itself is never listed for staff). */
  private publicTokens = new Map<string, { token: string; expires_at: string }>();
  /** Uploaded damage photos kept in memory (attachment id → file). */
  private photoBlobs = new Map<string, Blob>();
  /** `POST /quotations/:id/share` is rate-limited to 1/min per quotation. */
  private shareTimes = new Map<string, number>();

  constructor() {
    this.recomputeAlerts();
    this.seedActivity();
    // The seed quote QT-2026-0041 has already been shared: its public link is /q/demo-quoted.
    for (const q of this.quotations) {
      const token = demoSeedToken(q.id);
      if (token) {
        this.publicTokens.set(q.id, { token, expires_at: daysAgo(-30) });
        registerDemoPublicQuote(token, q, daysAgo(-30));
      }
    }
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
  private vehicle(id: string): Vehicle {
    return this.vehicles.find((v) => v.id === id) ?? vehicleById(id);
  }
  private profile(id: string) {
    return this.profiles.find((p) => p.id === id) ?? profileById(id);
  }
  private pushActivity(item: Omit<ActivityItem, 'id' | 'at'>) {
    this.activityLog.unshift({ id: nextId('act'), at: nowIso(), ...item });
    this.activityLog = this.activityLog.slice(0, 40);
  }
  private seedActivity() {
    const seed: (Omit<ActivityItem, 'id'> & { outlet?: string })[] = [
      { kind: 'completed', title: 'SPK-2026-0088 completed · Sparkling Wash', subtitle: `Menlyn · verified by Johan B.`, icon: 'check_circle', tone: 'success', at: rel(-5) },
      { kind: 'payment', title: 'R 140 payment verified · SPK-2026-0088', subtitle: 'Webhook confirmed · signature ok', icon: 'payments', tone: 'primary', at: rel(-50) },
      { kind: 'quote', title: 'Quote QT-2026-0038 accepted · R 2 100', subtitle: 'Converted to WO-2026-4818', icon: 'request_quote', tone: 'warning', at: rel(-130) },
      { kind: 'stock', title: 'Low stock: microfibre towels', subtitle: 'Glen Village · threshold 10', icon: 'notification_important', tone: 'error', at: rel(-25) },
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
    const s = this.services.find((x) => x.id === b.service_id) ?? serviceById(b.service_id);
    const v = this.vehicle(b.vehicle_id);
    const c = this.profile(b.customer_id);
    const w = this.workOrders.find((x) => x.booking_ref === b.ref) ?? null;
    const p = this.payments.find((x) => x.booking_ref === b.ref) ?? null;
    const pos = p ? this.posPayments.find((x) => x.id === p.id) : undefined;
    return {
      id: b.id, ref: b.ref, customer_id: b.customer_id, status: b.status, slot_start: b.slot_start, slot_end: b.slot_end, price_cents: b.price_cents,
      discount_cents: b.discount_cents, total_cents: b.total_cents, discount_label: b.discount_label, points_pending: b.points_pending, notes: b.notes,
      cancel_reason: b.cancel_reason, created_at: b.created_at, quotation_id: b.quotation_id,
      walk_in: Boolean(b.walk_in), created_by: b.created_by ?? null, created_by_name: b.created_by ? (this.profile(b.created_by)?.full_name ?? null) : null,
      outlet: { id: b.outlet_id, name: outletName(b.outlet_id) },
      service: { id: s.id, name: s.name, category: s.category, duration_minutes: s.duration_minutes },
      vehicle: { id: v.id, registration_no: v.registration_no, make: v.make, model: v.model },
      customer: { id: b.customer_id, full_name: c?.full_name ?? 'Customer', email: c?.email ?? null, phone: c?.phone ?? null },
      work_order: w ? { id: w.id, ref: w.ref, status: w.status, stage: w.steps_done, stage_count: w.step_count, progress_pct: Math.round((w.steps_done / Math.max(1, w.step_count)) * 100), assignee_id: w.assignee_id, assignee_name: w.assignee_name, bay: w.bay, eta_at: w.eta_at, blocked_reason: w.blocked_reason } : null,
      payment: p ? { id: p.id, status: p.status, receipt_no: p.receipt_no, amount_cents: p.amount_cents, method: pos?.method ?? null, provider: p.provider } : null,
      vehicle_size: b.vehicle_size, pricing_mode: b.pricing_mode, vat_mode: b.vat_mode, addon_service_ids: [...b.addon_service_ids], addons_cents: b.addons_cents, vat_cents: b.vat_cents, price_label: b.price_label,
      membership_id: b.membership_id ?? null, entitlement_id: b.entitlement_id ?? null, membership_benefit: b.membership_benefit ?? null, membership: this.bookingMembership(b),
      addons: b.addon_service_ids.map((id) => {
        const a = this.services.find((x) => x.id === id);
        const os = this.offerRow(b.outlet_id, id);
        return { service_id: id, name: os?.display_name ?? a?.name ?? 'Add-on', price_cents: a ? (effectivePricing(a, os).price_for[b.vehicle_size] ?? 0) : 0 };
      }),
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
      active_members: this.memberships.filter((m) => LIVE_MEMBERSHIP.includes(m.status)).length,
      membership_mrr_cents: this.memberships.filter((m) => m.status === 'active').reduce((sum, m) => sum + this.planOf(m.plan_id).monthly_fee_cents, 0),
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
      rows = rows.filter((b) => b.ref.toLowerCase().includes(q) || (this.profile(b.customer_id)?.full_name ?? '').toLowerCase().includes(q) || this.vehicle(b.vehicle_id).registration_no.toLowerCase().includes(q));
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
    const timeline: TimelineStage[] = [{ key: 'checked_in', title: 'Checked in', state: w ? 'done' : b.status === 'cancelled' ? 'pending' : 'pending', at: w?.started_at ?? w?.updated_at ?? null }];
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
    this.releaseUsage(b);
    this.log('booking.cancel', 'booking', b.id, { status: before }, { status: 'cancelled', reason }, b.outlet_id);
    this.emit('bookings');
    return this.expandBooking(b);
  }

  /* ------------------------------------------------------------ quotations */
  private static origin() {
    return typeof window !== 'undefined' ? window.location.origin : '';
  }
  /** Staff view of a quotation: applies any decision made on the public page, adds `items`, `public_url`, `pdf_url`. */
  private staffQuotation(q: Quotation): Quotation {
    const pub = this.publicTokens.get(q.id);
    if (pub) {
      const before = q.status;
      applyDemoDecision(q, pub.token);
      if (before !== q.status) this.emit('quotations');
    }
    const out = clone(q);
    out.items = out.line_items;
    out.outlet = withOutletLegal(out.outlet, this.outlets.find((o) => o.id === q.outlet.id));
    out.terms = QUOTE_TERMS;
    out.public_url = pub ? `${DemoApi.origin()}/q/${pub.token}` : null;
    out.public_token_expires_at = pub?.expires_at ?? null;
    out.pdf_url = `/v1/quotations/${q.id}/pdf`;
    return out;
  }
  /** Creates (or rotates) the public token for a quotation and registers it with the public demo store. */
  private issuePublicToken(q: Quotation): { token: string; expires_at: string } {
    const token = demoSeedToken(q.id) ?? `demo-${q.ref.toLowerCase().replace(/[^a-z0-9]+/g, '-')}-${uuid().slice(0, 8)}`;
    const entry = { token, expires_at: daysAgo(-30) };
    this.publicTokens.set(q.id, entry);
    registerDemoPublicQuote(token, q, entry.expires_at);
    return entry;
  }
  private static nextQuoteRef(existing: Quotation[]) {
    const max = existing.reduce((m, q) => Math.max(m, Number(q.ref.split('-').pop()) || 0), 0);
    return `QT-2026-${String(max + 1).padStart(4, '0')}`;
  }
  private static normaliseItems(items: QuoteLineItem[]): QuoteLineItem[] {
    return items
      .filter((i) => i.label.trim())
      .map((i) => ({ label: i.label.trim(), description: i.description?.trim() || null, category: i.category || null, service_id: i.service_id || null, amount_cents: Math.max(0, Math.round(i.amount_cents)), quantity: i.quantity ?? 1 }));
  }

  async listQuotations(f: QuotationFilters): Promise<Quotation[]> {
    await delay();
    let rows = this.quotations.map((q) => this.staffQuotation(q)).filter((q) => !f.outlet_id || q.outlet.id === f.outlet_id);
    if (f.status && f.status !== 'all') rows = rows.filter((q) => q.status === f.status);
    return rows.sort((a, b) => b.created_at.localeCompare(a.created_at));
  }
  async getQuotation(id: string): Promise<Quotation> {
    await delay();
    const q = this.quotations.find((x) => x.id === id);
    if (!q) throw new ApiRequestError(404, { code: 'not_found', message: 'Quotation not found' });
    return this.staffQuotation(q);
  }
  async submitQuote(id: string, body: { amount_cents: number; line_items: QuoteLineItem[]; valid_until: string; items_note?: string | null }): Promise<Quotation> {
    await delay();
    this.requireRole('supervisor', 'manager', 'admin');
    const q = this.quotations.find((x) => x.id === id);
    if (!q) throw new ApiRequestError(404, { code: 'not_found', message: 'Quotation not found' });
    if (!['requested', 'assessing', 'quoted'].includes(q.status)) throw new ApiRequestError(409, { code: 'invalid_transition', message: `Quotation is ${q.status}` });
    const a = this.actor();
    const items = DemoApi.normaliseItems(body.line_items);
    Object.assign(q, { status: 'quoted', amount_cents: body.amount_cents, line_items: items, items_note: body.items_note?.trim() || null, valid_until: body.valid_until, quoted_at: nowIso(), assessor_id: a.id, assessor_name: a.full_name });
    if (!this.publicTokens.has(q.id)) this.issuePublicToken(q);
    this.log('quotation.quote', 'quotation', q.id, null, { amount_cents: body.amount_cents }, q.outlet.id);
    this.pushActivity({ kind: 'quote', title: `Quote ${q.ref} sent · ${this.fmtR(body.amount_cents)}`, subtitle: `${q.customer_name} notified via push + WhatsApp`, icon: 'request_quote', tone: 'warning' });
    this.emit('quotations');
    return this.staffQuotation(q);
  }
  async raiseQuotation(input: RaiseQuotationInput): Promise<Quotation> {
    await delay(260);
    this.requireRole('supervisor', 'manager', 'admin');
    const prior = this.ops.get(`quotation:${input.client_op_id}`);
    if (prior) return this.staffQuotation(this.quotations.find((q) => q.id === prior)!);
    const customer = this.profiles.find((p) => p.id === input.customer_id && p.role === 'customer');
    if (!customer) throw new ApiRequestError(404, { code: 'not_found', message: 'Customer not found' });
    const vehicle = this.vehicles.find((v) => v.id === input.vehicle_id && v.customer_id === customer.id);
    if (!vehicle) throw new ApiRequestError(404, { code: 'not_found', message: 'Vehicle not found for this customer' });
    const outlet = this.outlets.find((o) => o.id === input.outlet_id);
    if (!outlet) throw new ApiRequestError(404, { code: 'not_found', message: 'Outlet not found' });
    this.requireOutletAccess(outlet.id);
    const items = DemoApi.normaliseItems(input.items);
    if (!items.length) throw new ApiRequestError(400, { code: 'validation_error', message: 'Add at least one item', details: [{ path: 'items', message: 'Required' }] });
    if (!/^\d{4}-\d{2}-\d{2}$/.test(input.valid_until) || input.valid_until < nowIso().slice(0, 10)) throw new ApiRequestError(400, { code: 'validation_error', message: 'valid_until must be a future date', details: [{ path: 'valid_until', message: 'Invalid' }] });
    const a = this.actor();
    const q: Quotation = {
      id: uuid(), ref: DemoApi.nextQuoteRef(this.quotations), customer_id: customer.id, customer_name: customer.full_name,
      vehicle: { id: vehicle.id, registration_no: vehicle.registration_no, make: vehicle.make, model: vehicle.model, colour: vehicle.colour },
      outlet: { id: outlet.id, name: outlet.name, phone: outlet.phone, address_line: outlet.address_line },
      category: input.category, description: input.description.trim(), status: 'quoted',
      amount_cents: items.reduce((s, i) => s + i.amount_cents * (i.quantity ?? 1), 0), line_items: items, items_note: input.items_note?.trim() || null,
      assessor_id: a.id, assessor_name: a.full_name, valid_until: input.valid_until, quoted_at: nowIso(), decided_at: null, decision_note: null,
      decision_source: null, decision_by_name: null, attachments: [], created_at: nowIso(),
    };
    this.quotations.unshift(q);
    this.ops.set(`quotation:${input.client_op_id}`, q.id);
    const pub = this.issuePublicToken(q);
    this.log('quotation.raise', 'quotation', q.id, null, { ref: q.ref, amount_cents: q.amount_cents, items: items.length, send_to_customer: input.send_to_customer ?? true }, outlet.id);
    if (input.send_to_customer ?? true) {
      const first = customer.full_name.split(' ')[0];
      this.notifications.unshift({ id: nextId('n'), recipient_id: customer.id, recipient_name: customer.full_name, channel: customer.whatsapp_opt_in ? 'whatsapp' : 'push', template_key: 'quote_ready', title: 'Your quotation is ready', body: `Hi ${first}, your Sparkling quotation ${q.ref} for ${this.fmtR(q.amount_cents ?? 0)} is ready. View, accept or decline: ${DemoApi.origin()}/q/${pub.token}`, payload: { type: 'quotation', id: q.id, vars: { first_name: first, public_token: pub.token } }, status: 'sent', provider_status: customer.whatsapp_opt_in ? 'queued' : null, provider_ref: customer.whatsapp_opt_in ? `SM${uuid().replace(/-/g, '').slice(0, 32)}` : null, provider_error_code: null, error: null, attempts: 1, sent_at: nowIso(), delivered_at: null, read_at: null, created_at: nowIso() });
    }
    this.pushActivity({ kind: 'quote', title: `Quote ${q.ref} raised · ${this.fmtR(q.amount_cents ?? 0)}`, subtitle: `${customer.full_name} · ${input.send_to_customer ?? true ? 'link sent on WhatsApp' : 'not sent yet'}`, icon: 'request_quote', tone: 'warning' });
    this.emit('quotations');
    return this.staffQuotation(q);
  }
  async shareQuotation(id: string): Promise<ShareQuotationResult> {
    await delay(220);
    this.requireRole('supervisor', 'manager', 'admin');
    const q = this.quotations.find((x) => x.id === id);
    if (!q) throw new ApiRequestError(404, { code: 'not_found', message: 'Quotation not found' });
    if (!['quoted', 'accepted', 'declined', 'expired'].includes(q.status)) throw new ApiRequestError(409, { code: 'invalid_transition', message: 'Only quoted quotations can be shared' });
    const last = this.shareTimes.get(id) ?? 0;
    if (Date.now() - last < 60_000) throw new ApiRequestError(429, { code: 'rate_limited', message: `Please wait ${Math.ceil((60_000 - (Date.now() - last)) / 1000)} s before re-sending` });
    this.shareTimes.set(id, Date.now());
    const pub = this.issuePublicToken(q);
    const url = `${DemoApi.origin()}/q/${pub.token}`;
    const customer = this.profiles.find((p) => p.id === q.customer_id);
    this.notifications.unshift({ id: nextId('n'), recipient_id: q.customer_id, recipient_name: q.customer_name, channel: customer?.whatsapp_opt_in === false ? 'push' : 'whatsapp', template_key: 'quote_ready', title: 'Your quotation is ready', body: `Hi ${q.customer_name.split(' ')[0]}, your Sparkling quotation ${q.ref} is ready. View, accept or decline: ${url}`, payload: { type: 'quotation', id: q.id, vars: { first_name: q.customer_name.split(' ')[0], public_token: pub.token } }, status: 'sent', provider_status: 'queued', provider_ref: `SM${uuid().replace(/-/g, '').slice(0, 32)}`, provider_error_code: null, error: null, attempts: 1, sent_at: nowIso(), delivered_at: null, read_at: null, created_at: nowIso() });
    this.log('quotation.share', 'quotation', q.id, null, { expires_at: pub.expires_at }, q.outlet.id);
    this.emit('quotations');
    return { public_url: url, expires_at: pub.expires_at };
  }
  async uploadQuotationPhoto(id: string, file: File, caption?: string): Promise<QuotationAttachment> {
    await delay(320);
    this.requireRole('supervisor', 'manager', 'admin');
    const q = this.quotations.find((x) => x.id === id);
    if (!q) throw new ApiRequestError(404, { code: 'not_found', message: 'Quotation not found' });
    if (q.attachments.length >= 10) throw new ApiRequestError(400, { code: 'validation_error', message: 'A quotation can have at most 10 photos' });
    if (!/^image\/(jpeg|png|heic|heif|webp|svg\+xml)$/.test(file.type)) throw new ApiRequestError(400, { code: 'validation_error', message: 'Only JPEG, PNG or HEIC photos are accepted' });
    if (file.size > 10 * 1024 * 1024) throw new ApiRequestError(400, { code: 'validation_error', message: 'Photos must be 10 MB or smaller' });
    let width: number | null = null;
    let height: number | null = null;
    try {
      const bmp = await createImageBitmap(file);
      width = bmp.width;
      height = bmp.height;
      bmp.close();
    } catch {
      /* HEIC etc. — dimensions unknown in the browser */
    }
    const attId = `att-${uuid().slice(0, 8)}`;
    this.photoBlobs.set(attId, file);
    // The public demo page (possibly another tab) has no bearer-token fetch: hand it a data URL.
    try {
      const dataUrl = await new Promise<string>((resolve, reject) => {
        const r = new FileReader();
        r.onload = () => resolve(String(r.result));
        r.onerror = () => reject(r.error);
        r.readAsDataURL(file);
      });
      registerDemoPhoto(attId, dataUrl);
    } catch {
      /* preview unavailable on the public page — falls back to the placeholder */
    }
    const att: QuotationAttachment = { id: attId, kind: 'damage_photo', url: `/v1/quotations/${q.id}/photos/${attId}`, caption: caption?.trim() || null, width, height, mime_type: file.type, size_bytes: file.size, storage_path: `quotations/${q.id}/${attId}.${file.name.split('.').pop() ?? 'jpg'}` };
    q.attachments.push(att);
    syncDemoPublicQuote(q);
    this.log('quotation.photo.add', 'quotation', q.id, null, { attachment_id: attId, size_bytes: file.size }, q.outlet.id);
    this.emit('quotations');
    return clone(att);
  }
  async deleteQuotationPhoto(id: string, attachmentId: string): Promise<void> {
    await delay();
    this.requireRole('supervisor', 'manager', 'admin');
    const q = this.quotations.find((x) => x.id === id);
    if (!q) throw new ApiRequestError(404, { code: 'not_found', message: 'Quotation not found' });
    if (q.decided_at) throw new ApiRequestError(409, { code: 'invalid_transition', message: 'Photos cannot be removed after the customer has decided' });
    q.attachments = q.attachments.filter((a) => a.id !== attachmentId);
    this.photoBlobs.delete(attachmentId);
    syncDemoPublicQuote(q);
    this.log('quotation.photo.remove', 'quotation', q.id, { attachment_id: attachmentId }, null, q.outlet.id);
    this.emit('quotations');
  }
  async fetchQuotationPhoto(id: string, attachmentId: string): Promise<Blob> {
    const q = this.quotations.find((x) => x.id === id);
    const att = q?.attachments.find((a) => a.id === attachmentId);
    if (!q || !att) throw new ApiRequestError(404, { code: 'not_found', message: 'Photo not found' });
    const stored = this.photoBlobs.get(attachmentId);
    if (stored) return stored;
    // Seed attachments point at the placeholder SVGs shipped in /public/demo; uploads from another tab come back as data URLs.
    const res = await fetch(att.url && !att.url.startsWith('/v1/') ? att.url : demoPhotoUrl(attachmentId));
    if (!res.ok) throw new ApiRequestError(res.status, { code: 'not_found', message: 'Photo not found' });
    return res.blob();
  }
  async fetchQuotationPdf(id: string): Promise<Blob> {
    const q = this.quotations.find((x) => x.id === id);
    if (!q) throw new ApiRequestError(404, { code: 'not_found', message: 'Quotation not found' });
    return buildQuotePdf(pdfInputFromQuotation(this.staffQuotation(q), undefined, this.outlets));
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
  /** Strips the demo-only staff fields (outlets, skills, availability) down to the API `Profile` shape. */
  private static toProfile(p: (typeof DEMO_PROFILES)[number]): Profile {
    return {
      id: p.id, role: p.role, full_name: p.full_name, email: p.email, phone: p.phone, avatar_url: p.avatar_url, is_active: p.is_active,
      marketing_opt_in: p.marketing_opt_in, whatsapp_opt_in: p.whatsapp_opt_in, push_opt_in: p.push_opt_in, last_seen_at: p.last_seen_at, created_at: p.created_at,
      must_change_password: p.must_change_password, password_changed_at: p.password_changed_at,
    };
  }
  /** Mirrors `tempPassword()` in backend/functions/src/routes/admin.ts (`Spk-` + 12 url-safe chars). */
  private static tempPassword(): string {
    const alphabet = 'ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz23456789';
    let out = 'Spk-';
    for (let i = 0; i < 12; i += 1) out += alphabet[Math.floor(Math.random() * alphabet.length)];
    return out;
  }
  async inviteUser(body: CreateStaffInput): Promise<CreateStaffResult> {
    await delay();
    this.requireRole('admin');
    if (this.profiles.some((p) => p.email?.toLowerCase() === body.email.toLowerCase())) throw new ApiRequestError(409, { code: 'conflict', message: 'A profile with this e-mail already exists' });
    const phone = DemoApi.optionalPhone(body.phone);
    const p = { id: nextId('usr'), role: body.role, full_name: body.full_name, email: body.email, phone, avatar_url: null, is_active: true, marketing_opt_in: false, whatsapp_opt_in: true, push_opt_in: true, last_seen_at: null, created_at: nowIso(), must_change_password: true, password_changed_at: null, outlet_ids: body.outlet_ids, skills: body.skills ?? ([] as string[]), availability: 'available' as const };
    this.profiles.push(p);
    this.log('user.create', 'profile', p.id, null, { email: body.email, role: body.role, outlet_ids: body.outlet_ids, invite: body.invite ?? 'password' });
    return { profile: DemoApi.toProfile(p), uid: p.id, temporary_password: DemoApi.tempPassword(), invite_link: body.invite === 'link' ? `https://sparkling-4e89d.firebaseapp.com/__/auth/action?mode=resetPassword&oobCode=demo-${p.id}` : null };
  }
  async resetUserPassword(id: string): Promise<ResetPasswordResult> {
    await delay();
    this.requireRole('admin');
    const p = this.profiles.find((x) => x.id === id && x.role !== 'customer');
    if (!p) throw new ApiRequestError(404, { code: 'not_found', message: 'User not found' });
    p.must_change_password = true;
    p.password_changed_at = null;
    this.log('user.reset_password', 'profile', id, null, { refresh_tokens_revoked: true });
    return { profile: DemoApi.toProfile(p), temporary_password: DemoApi.tempPassword() };
  }
  /** The demo session never carries the first-sign-in flag, so this is a no-op that returns the actor. */
  async confirmPasswordChanged(): Promise<Profile> {
    await delay();
    const a = this.actor();
    a.must_change_password = false;
    a.password_changed_at = nowIso();
    return DemoApi.toProfile(a);
  }
  async updateUser(id: string, patch: { role?: UserRole; outlet_ids?: string[]; is_active?: boolean; phone?: string | null }): Promise<StaffUser> {
    await delay();
    this.requireRole('admin');
    const p = this.profiles.find((x) => x.id === id);
    if (!p) throw new ApiRequestError(404, { code: 'not_found', message: 'User not found' });
    const before = { role: p.role, outlet_ids: p.outlet_ids, is_active: p.is_active, phone: p.phone };
    if (patch.phone !== undefined) patch = { ...patch, phone: DemoApi.optionalPhone(patch.phone) };
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
  /** `loyalty` on customer rows: the account plus the live plan (docs/MEMBERSHIPS.md "customer summary"). */
  private loyaltySummary(customerId: string): LoyaltySummary | undefined {
    const acct = this.loyaltyAccounts.find((a) => a.customer_id === customerId);
    if (!acct) return undefined;
    const m = this.liveMembership(customerId);
    const plan = m ? this.planOf(m.plan_id) : null;
    return { ...acct, plan_code: plan?.code ?? null, plan_name: plan?.name ?? null, included_remaining: m ? this.includedRemaining(m) : 0 };
  }
  private customerSummary(p: (typeof this.profiles)[number]): CustomerSummary {
    return { ...p, vehicle_count: this.vehicles.filter((v) => v.customer_id === p.id).length, booking_count: this.bookings.filter((b) => b.customer_id === p.id).length, loyalty: this.loyaltySummary(p.id) };
  }
  async searchCustomers(search: string): Promise<CustomerSummary[]> {
    await delay();
    this.requireRole('admin', 'manager', 'finance');
    const q = search.trim().toLowerCase();
    return this.profiles.filter((p) => p.role === 'customer' && (!q || p.full_name.toLowerCase().includes(q) || (p.email ?? '').toLowerCase().includes(q) || (p.phone ?? '').includes(q) || this.vehicles.some((v) => v.customer_id === p.id && v.registration_no.toLowerCase().includes(q)))).map((p) => this.customerSummary(p));
  }
  async getCustomer(id: string): Promise<CustomerDetail> {
    await delay();
    this.requireRole('admin', 'manager', 'finance');
    const p = this.profiles.find((x) => x.id === id && x.role === 'customer');
    if (!p) throw new ApiRequestError(404, { code: 'not_found', message: 'Customer not found' });
    this.log('customer.view', 'profile', id, null, { reason: 'admin lookup' });
    return { ...this.customerSummary(p), vehicles: clone(this.vehicles.filter((v) => v.customer_id === id)), bookings: this.bookings.filter((b) => b.customer_id === id).sort((a, b) => b.slot_start.localeCompare(a.slot_start)).map((b) => this.expandBooking(b)), ledger: this.ledger.filter((l) => l.customer_id === id).sort((a, b) => b.created_at.localeCompare(a.created_at)), membership: this.summaryFor(id) };
  }


  /* ------------------------------------------------------------ walk-in (STF-010/012) */
  private static digits(s: string | null | undefined) {
    return (s ?? '').replace(/\D/g, '');
  }
  /** Mirrors the API's `phoneSchema`: any valid international number → E.164, otherwise the same 400 the API returns. */
  private static requirePhone(raw: string | null | undefined): string {
    const e164 = normalisePhone(raw);
    if (!e164) throw new ApiRequestError(400, { code: 'validation_error', message: PHONE_HINT, details: [{ path: 'phone', message: PHONE_HINT }] });
    return e164;
  }
  /** Mirrors `optionalPhoneSchema`: empty / null clears the number. */
  private static optionalPhone(raw: string | null | undefined): string | null {
    return raw?.trim() ? DemoApi.requirePhone(raw) : null;
  }
  /** Same-number test that tolerates legacy `+27 83 …` spacing in older rows. */
  private static samePhone(a: string | null | undefined, b: string | null | undefined): boolean {
    if (!a || !b) return false;
    return (normalisePhone(a) ?? DemoApi.digits(a)) === (normalisePhone(b) ?? DemoApi.digits(b));
  }
  private static plateKey(s: string | null | undefined) {
    return (s ?? '').replace(/[^a-z0-9]/gi, '').toUpperCase();
  }
  private publishedLoyalty(): LoyaltyConfig {
    return this.loyalty.find((c) => c.status === 'published')!;
  }
  private walkInCustomer(p: (typeof this.profiles)[number]): WalkInCustomer {
    const acct = this.loyaltySummary(p.id);
    // Tier discounts are 0 since docs/MEMBERSHIPS.md — every discount comes from the plan.
    return {
      id: p.id, full_name: p.full_name, email: p.email, phone: p.phone, marketing_opt_in: p.marketing_opt_in, whatsapp_opt_in: p.whatsapp_opt_in,
      loyalty: acct ? { tier: acct.tier, balance_points: acct.balance_points, discount_pct: 0, plan_code: acct.plan_code, plan_name: acct.plan_name, included_remaining: acct.included_remaining } : null,
      vehicles: this.vehicles.filter((v) => v.customer_id === p.id).map((v) => ({ id: v.id, registration_no: v.registration_no, make: v.make, model: v.model, colour: v.colour, disc_verified: v.disc_verified })),
    };
  }
  private requireStaff() {
    this.requireRole('admin', 'manager', 'supervisor');
  }
  private requireOutletAccess(outletId: string) {
    const a = this.actor();
    if (!this.outlets.some((o) => o.id === outletId)) throw new ApiRequestError(404, { code: 'not_found', message: 'Outlet not found' });
    if (a.role !== 'admin' && !a.outlet_ids.includes(outletId)) throw new ApiRequestError(403, { code: 'forbidden', message: 'outlet_id must be one of your outlets' });
  }

  async searchWalkInCustomers(search: string): Promise<WalkInCustomer[]> {
    await delay();
    this.requireStaff();
    const q = search.trim().toLowerCase();
    if (q.length < 2) throw new ApiRequestError(400, { code: 'validation_error', message: 'search needs at least 2 characters' });
    const digits = DemoApi.digits(q);
    const plate = DemoApi.plateKey(q);
    return this.profiles
      .filter((p) => p.role === 'customer' && (
        p.full_name.toLowerCase().includes(q) || (p.email ?? '').toLowerCase().includes(q)
        || (digits.length >= 3 && DemoApi.digits(p.phone).includes(digits))
        || (plate.length >= 2 && this.vehicles.some((v) => v.customer_id === p.id && DemoApi.plateKey(v.registration_no).includes(plate)))
      ))
      .slice(0, 20)
      .map((p) => this.walkInCustomer(p));
  }

  async createWalkInCustomer(input: WalkInCustomerInput): Promise<WalkInCustomer> {
    await delay(200);
    this.requireStaff();
    const prior = this.ops.get(`customer:${input.client_op_id}`);
    if (prior) return this.walkInCustomer(this.profiles.find((p) => p.id === prior)!);
    const name = input.full_name.trim();
    const email = input.email?.trim() || null;
    if (name.length < 2) throw new ApiRequestError(400, { code: 'validation_error', message: 'Full name is required', details: [{ path: 'full_name', message: 'Required' }] });
    const phone = DemoApi.requirePhone(input.phone);
    const existing = this.profiles.find((p) => p.role === 'customer' && (DemoApi.samePhone(p.phone, phone) || (email && (p.email ?? '').toLowerCase() === email.toLowerCase())));
    if (existing) {
      throw new ApiRequestError(409, { code: 'conflict', message: `${existing.full_name} is already registered with this ${DemoApi.samePhone(existing.phone, phone) ? 'phone number' : 'e-mail'}`, details: { existing_customer: this.walkInCustomer(existing) } });
    }
    const p = { id: `walkin_${uuid()}`, role: 'customer' as UserRole, full_name: name, email, phone, avatar_url: null, is_active: true, marketing_opt_in: Boolean(input.marketing_opt_in), whatsapp_opt_in: input.whatsapp_opt_in ?? true, push_opt_in: false, last_seen_at: null, created_at: nowIso(), must_change_password: false, password_changed_at: null, outlet_ids: [] as string[], skills: [] as string[], availability: undefined };
    this.profiles.push(p);
    this.loyaltyAccounts.push({ customer_id: p.id, tier: 'silver', balance_points: 0, lifetime_points: 0, tier_since: nowIso() });
    this.ops.set(`customer:${input.client_op_id}`, p.id);
    this.log('customer.create', 'profile', p.id, null, { full_name: name, phone, email, walk_in: true });
    this.pushActivity({ kind: 'loyalty', title: `${name} registered as a walk-in`, subtitle: `By ${this.actor().full_name} · Silver tier`, icon: 'person_add', tone: 'neutral' });
    return this.walkInCustomer(p);
  }

  async createCustomerVehicle(customerId: string, input: VehicleInput, force = false): Promise<{ vehicle: Vehicle; duplicate: boolean }> {
    await delay(200);
    this.requireStaff();
    const owner = this.profiles.find((p) => p.id === customerId && p.role === 'customer');
    if (!owner) throw new ApiRequestError(404, { code: 'not_found', message: 'Customer not found' });
    const prior = this.ops.get(`vehicle:${input.client_op_id}`);
    if (prior) return { vehicle: clone(this.vehicles.find((v) => v.id === prior)!), duplicate: true };
    const plate = DemoApi.plateKey(input.registration_no);
    if (plate.length < 4) throw new ApiRequestError(400, { code: 'validation_error', message: 'Registration number looks too short', details: [{ path: 'registration_no', message: 'Invalid' }] });
    const vin = input.vin?.trim().toUpperCase() || null;
    const dup = this.vehicles.find((v) => DemoApi.plateKey(v.registration_no) === plate || (vin && v.vin === vin));
    if (dup && dup.customer_id === customerId) return { vehicle: clone(dup), duplicate: true };
    if (dup && !force) {
      throw new ApiRequestError(409, { code: 'conflict', message: `${dup.registration_no} is already registered to ${this.profile(dup.customer_id)?.full_name ?? 'another customer'}`, details: { existing_vehicle_id: dup.id, existing_vehicle: { id: dup.id, registration_no: dup.registration_no, make: dup.make, model: dup.model } } });
    }
    const v: Vehicle = { id: uuid(), customer_id: customerId, registration_no: input.registration_no.trim().toUpperCase(), vin, make: input.make?.trim() || null, model: input.model?.trim() || null, colour: input.colour?.trim() || null, year: input.year ?? null, disc_expiry: null, source: input.source, disc_verified: input.source === 'scan' };
    this.vehicles.push(v);
    this.ops.set(`vehicle:${input.client_op_id}`, v.id);
    this.log('vehicle.create', 'vehicle', v.id, null, { registration_no: v.registration_no, customer_id: customerId, force });
    return { vehicle: clone(v), duplicate: false };
  }

  /* ---- catalogue resolution (docs/API.md "Catalogue pricing model") ---- */
  private offerRow(outletId: string, serviceId: string): CatalogueOffer | undefined {
    return this.outletServices.find((x) => x.outlet_id === outletId && x.service_id === serviceId);
  }
  /** Resolved composition of a parent: outlet-specific rows override the global default set. */
  private componentsFor(outletId: string | null, s: Service): { rows: ServiceComponent[]; source: 'outlet' | 'global' } {
    const own = outletId ? this.components.filter((c) => c.outlet_id === outletId && c.parent_service_id === s.id) : [];
    if (own.length) return { rows: [...own].sort((a, b) => a.sort_order - b.sort_order).map((c) => ({ child_service_id: c.child_service_id, quantity: c.quantity, sort_order: c.sort_order })), source: 'outlet' };
    return { rows: [...s.components].sort((a, b) => a.sort_order - b.sort_order), source: 'global' };
  }
  /** True when making `parentId` include `children` would loop back to `parentId` (through the resolved graph at the outlet). */
  private wouldCycle(parentId: string, children: string[], outletId: string | null): string | null {
    const seen = new Set<string>();
    const stack: { id: string; path: string[] }[] = children.map((id) => ({ id, path: [parentId, id] }));
    while (stack.length) {
      const { id, path } = stack.pop()!;
      if (id === parentId) return path.map((x) => this.services.find((y) => y.id === x)?.code ?? x).join(' → ');
      if (seen.has(id)) continue;
      seen.add(id);
      const svc = this.services.find((x) => x.id === id);
      if (svc) for (const c of this.componentsFor(outletId, svc).rows) stack.push({ id: c.child_service_id, path: [...path, c.child_service_id] });
    }
    return null;
  }
  private validateComponents(parentId: string, comps: ServiceComponent[], outletId: string | null): ServiceComponent[] {
    const out: ServiceComponent[] = [];
    comps.forEach((c, i) => {
      if (!c || typeof c.child_service_id !== 'string') throw new ApiRequestError(400, { code: 'validation_error', message: 'components[].child_service_id is required', details: [{ path: `components.${i}.child_service_id`, message: 'Required' }] });
      if (c.child_service_id === parentId) throw new ApiRequestError(400, { code: 'validation_error', message: 'A service cannot include itself', details: [{ path: `components.${i}.child_service_id`, message: 'Self reference' }] });
      if (!this.services.some((x) => x.id === c.child_service_id)) throw new ApiRequestError(404, { code: 'not_found', message: 'Component service not found', details: [{ path: `components.${i}.child_service_id`, message: 'Unknown service' }] });
      if (out.some((x) => x.child_service_id === c.child_service_id)) return; // de-duplicate
      const quantity = Math.round(Number(c.quantity ?? 1));
      if (!(quantity > 0)) throw new ApiRequestError(400, { code: 'validation_error', message: 'quantity must be a positive integer', details: [{ path: `components.${i}.quantity`, message: 'Invalid' }] });
      out.push({ child_service_id: c.child_service_id, quantity, sort_order: Number.isFinite(Number(c.sort_order)) ? Number(c.sort_order) : (i + 1) * 10 });
    });
    const cycle = this.wouldCycle(parentId, out.map((c) => c.child_service_id), outletId);
    if (cycle) throw new ApiRequestError(400, { code: 'validation_error', message: `That composition would create a cycle: ${cycle}`, details: [{ path: 'components', message: 'cycle' }] });
    return out;
  }
  /** The outlet's offer with effective prices, size resolution and composition (`GET /outlets/:id/services` row). */
  private resolveOffer(outletId: string, s: Service, os: CatalogueOffer, size?: VehicleSize): OutletServiceOffer {
    const p = effectivePricing(s, os);
    const comp = this.componentsFor(outletId, s);
    const includes = comp.rows.flatMap((c) => {
      const child = this.services.find((x) => x.id === c.child_service_id);
      if (!child) return [];
      const childOs = this.offerRow(outletId, child.id);
      return [{ service_id: child.id, code: child.code, name: childOs?.display_name ?? child.name, quantity: c.quantity }];
    });
    const included_in = this.services.filter((parent) => parent.id !== s.id && this.offerRow(outletId, parent.id) && this.componentsFor(outletId, parent).rows.some((c) => c.child_service_id === s.id)).map((parent) => parent.id);
    const ppr = this.publishedLoyalty().rules.points_per_rand;
    return {
      id: s.id, service_id: s.id, code: s.code, name: os.display_name ?? s.name, service_name: s.name, display_name: os.display_name, description: s.description,
      group_name: s.group_name, category: s.category, duration_minutes: s.duration_minutes, icon: s.icon,
      pricing_mode: p.pricing_mode, vat_mode: p.vat_mode, pricing_mode_override: os.pricing_mode, vat_mode_override: os.vat_mode,
      price_small_cents: os.price_small_cents, price_large_cents: os.price_large_cents, price_general_cents: os.price_general_cents,
      price_from_cents: p.price_from_cents, price_for: p.price_for, ...(size ? { price_cents: p.price_for[size] } : {}),
      is_addon: s.is_addon, addon_group_name: s.addon_group_name, includes, included_in, components_source: comp.source,
      is_available: os.is_available, sort_order: os.sort_order, notes: os.notes,
      // Staff have no tier: the customer's tier discount is applied at booking time (and previewed client-side).
      points_estimate: Math.round(((p.price_from_cents ?? 0) / 100) * ppr), is_quote_based: p.pricing_mode === 'by_quote',
    };
  }
  private offersAt(outletId: string, opts: { size?: VehicleSize; includeUnavailable?: boolean } = {}): OutletServiceOffer[] {
    if (!this.outlets.some((o) => o.id === outletId)) throw new ApiRequestError(404, { code: 'not_found', message: 'Outlet not found' });
    return this.services
      .filter((s) => s.is_active)
      .flatMap((s) => {
        const os = this.offerRow(outletId, s.id);
        if (!os || (!os.is_available && !opts.includeUnavailable)) return [];
        return [this.resolveOffer(outletId, s, os, opts.size)];
      })
      .sort((a, b) => (a.sort_order ?? 9999) - (b.sort_order ?? 9999) || a.name.localeCompare(b.name));
  }
  async listOutletServicesFor(outletId: string, vehicleSize?: VehicleSize): Promise<OutletServiceOffer[]> {
    await delay(80);
    return this.offersAt(outletId, { size: vehicleSize });
  }

  /** Active bookings at the outlet whose interval overlaps [start, end). */
  private overlapping(outletId: string, start: Date, end: Date, ignoreId?: string) {
    return this.bookings.filter((b) => b.outlet_id === outletId && b.id !== ignoreId && !['cancelled', 'completed', 'draft'].includes(b.status) && new Date(b.slot_start) < end && new Date(b.slot_end) > start).length;
  }
  private slotsFor(outletId: string, serviceId: string, dateISO: string): AvailabilitySlot[] {
    const o = this.outlets.find((x) => x.id === outletId);
    const s = this.services.find((x) => x.id === serviceId);
    if (!o || !s) throw new ApiRequestError(404, { code: 'not_found', message: 'Outlet or service not found' });
    const day = new Date(`${dateISO}T00:00:00`);
    if (Number.isNaN(day.getTime())) throw new ApiRequestError(400, { code: 'validation_error', message: 'date must be YYYY-MM-DD' });
    const key = (['sun', 'mon', 'tue', 'wed', 'thu', 'fri', 'sat'] as const)[day.getDay()];
    const hours = o.opening_hours[key];
    if (!hours) return [];
    const [oh, om] = hours[0].split(':').map(Number);
    const [ch, cm] = hours[1].split(':').map(Number);
    const open = new Date(day); open.setHours(oh, om, 0, 0);
    const close = new Date(day); close.setHours(ch, cm, 0, 0);
    const now = Date.now();
    const out: AvailabilitySlot[] = [];
    for (let t = open.getTime(); t + s.duration_minutes * 60000 <= close.getTime(); t += o.slot_minutes * 60000) {
      const start = new Date(t);
      const end = new Date(t + s.duration_minutes * 60000);
      const booked = this.overlapping(outletId, start, end);
      out.push({ slot_start: start.toISOString(), slot_end: end.toISOString(), capacity: o.bay_count, booked, available: t > now && booked < o.bay_count });
    }
    return out;
  }
  async availability(outletId: string, serviceId: string, dateISO: string): Promise<AvailabilitySlot[]> {
    await delay(100);
    return this.slotsFor(outletId, serviceId, dateISO);
  }

  async createWalkInBooking(input: WalkInBookingInput): Promise<WalkInBookingResult> {
    await delay(320);
    this.requireStaff();
    const prior = this.ops.get(`booking:${input.client_op_id}`);
    if (prior) {
      const b = this.bookings.find((x) => x.id === prior)!;
      return { booking: this.expandBooking(b), duplicate: true, ...(input.checkin ? { work_order: this.expandBooking(b).work_order } : {}) };
    }
    this.requireOutletAccess(input.outlet_id);
    const customer = this.profiles.find((p) => p.id === input.customer_id && p.role === 'customer');
    if (!customer) throw new ApiRequestError(404, { code: 'not_found', message: 'Customer not found' });
    const v = this.vehicles.find((x) => x.id === input.vehicle_id);
    if (!v || v.customer_id !== customer.id) throw new ApiRequestError(400, { code: 'validation_error', message: 'Vehicle does not belong to this customer', details: [{ path: 'vehicle_id', message: 'Invalid' }] });
    const o = this.outlets.find((x) => x.id === input.outlet_id)!;
    const s = this.services.find((x) => x.id === input.service_id);
    const os = s ? this.offerRow(o.id, s.id) : undefined;
    if (!s || !s.is_active || !os || !os.is_available) throw new ApiRequestError(404, { code: 'not_found', message: 'Service is not offered at this outlet' });
    // Pricing basis: the vehicle's size class (client may override), "from" price for that size, add-ons of the same group.
    const size: VehicleSize = input.vehicle_size ?? vehicleSizeOf(v);
    const offer = this.resolveOffer(o.id, s, os, size);
    if (offer.pricing_mode === 'by_quote') throw new ApiRequestError(409, { code: 'validation_error', message: `${offer.name} is priced by quotation — raise a quote instead`, details: { reason: 'by_quote', service_id: s.id } });
    const base = offer.price_for[size];
    if (base === null) throw new ApiRequestError(409, { code: 'validation_error', message: `${offer.name} has no ${size} price at ${outletShort(o.id)}`, details: { reason: 'no_price', service_id: s.id, vehicle_size: size } });
    const addonIds = [...new Set(input.addon_service_ids ?? [])];
    const addons = addonIds.map((id, i) => {
      const a = this.services.find((x) => x.id === id);
      const aos = a ? this.offerRow(o.id, a.id) : undefined;
      if (!a || !a.is_active || !aos || !aos.is_available || !a.is_addon || a.addon_group_name !== s.group_name) {
        throw new ApiRequestError(400, { code: 'validation_error', message: `${a?.name ?? id} is not an add-on for ${s.group_name} at this outlet`, details: [{ path: `addon_service_ids.${i}`, message: 'Not an add-on for this service' }] });
      }
      const ao = this.resolveOffer(o.id, a, aos, size);
      const price = ao.price_for[size];
      if (price === null) throw new ApiRequestError(400, { code: 'validation_error', message: `${ao.name} has no price for a ${size} vehicle`, details: [{ path: `addon_service_ids.${i}`, message: 'No price' }] });
      return { id: a.id, price, duration: a.duration_minutes };
    });
    const addons_cents = addons.reduce((sum, a) => sum + a.price, 0);
    const durationMin = s.duration_minutes + addons.reduce((sum, a) => sum + a.duration, 0);

    // Slot: explicit (must be an offered, available slot) or "now" rounded up to the outlet grid (capacity still enforced).
    let start: Date;
    if (input.slot_start) {
      const wanted = new Date(input.slot_start);
      const date = `${wanted.getFullYear()}-${String(wanted.getMonth() + 1).padStart(2, '0')}-${String(wanted.getDate()).padStart(2, '0')}`;
      const slot = this.slotsFor(o.id, s.id, date).find((x) => new Date(x.slot_start).getTime() === wanted.getTime());
      if (!slot) throw new ApiRequestError(409, { code: 'conflict', message: 'Slot is not offered at this outlet/time', details: { slot_start: input.slot_start } });
      if (!slot.available) throw new ApiRequestError(409, { code: 'conflict', message: 'Slot is no longer available', details: { slot_start: input.slot_start, booked: slot.booked, capacity: slot.capacity } });
      start = wanted;
    } else {
      const grid = o.slot_minutes * 60000;
      start = new Date(Math.ceil(Date.now() / grid) * grid);
      const end = new Date(start.getTime() + durationMin * 60000);
      const booked = this.overlapping(o.id, start, end);
      if (booked >= o.bay_count) throw new ApiRequestError(409, { code: 'conflict', message: `All ${o.bay_count} bays are busy for the next slot — pick a later slot`, details: { slot_start: start.toISOString(), booked, capacity: o.bay_count } });
    }
    const end = new Date(start.getTime() + durationMin * 60000);

    // Pricing (docs/MEMBERSHIPS.md): base + add-ons; an included plan wash covers the base (add-ons still
    // charged), otherwise the plan discount by scope; tier discount is 0; then 15 % VAT on top for `excl`
    // prices; `incl` prices are final.
    const acct = this.loyaltyAccounts.find((a) => a.customer_id === customer.id);
    const cfg = this.publishedLoyalty();
    const tierCfg = acct ? cfg.tiers.find((t) => t.tier === acct.tier) : undefined;
    const price = base + addons_cents;
    const mb = this.memberBenefit(customer.id, s, base, addons_cents);
    const discount = mb?.discount ?? 0;
    const vat = offer.vat_mode === 'excl' ? Math.round((price - discount) * VAT_RATE) : 0;
    const total = price - discount + vat;
    const n = 100 + this.bookings.length + 1;
    const ref = `SPK-2026-${String(n).padStart(4, '0')}`;
    const b: RawBooking = {
      id: uuid(), ref, customer_id: customer.id, vehicle_id: v.id, outlet_id: o.id, service_id: s.id,
      slot_start: start.toISOString(), slot_end: end.toISOString(), status: 'confirmed', price_cents: price, discount_cents: discount, vat_cents: vat, total_cents: total,
      discount_label: mb?.label ?? null, points_pending: Math.round((total / 100) * cfg.rules.points_per_rand * (tierCfg?.earn_multiplier ?? 1)),
      notes: input.notes ?? null, cancel_reason: null, created_at: nowIso(), quotation_id: null, walk_in: true, created_by: this.actorId,
      vehicle_size: size, pricing_mode: offer.pricing_mode, vat_mode: offer.vat_mode, addon_service_ids: addonIds, addons_cents, price_label: priceLabel(offer, base, this.fmtR.bind(this)),
      membership_id: mb?.membership.id ?? null, entitlement_id: mb?.entitlement?.id ?? null, membership_benefit: mb?.benefit ?? null,
    };
    this.bookings.push(b);
    this.ops.set(`booking:${input.client_op_id}`, b.id);
    if (mb?.benefit === 'included') this.postUsage(b);
    this.log('booking.create_walk_in', 'booking', b.id, null, { ref, total_cents: total, price_cents: price, discount_cents: discount, discount_label: b.discount_label, membership_benefit: b.membership_benefit ?? null, addons_cents, vat_cents: vat, vehicle_size: size, customer_id: customer.id, slot_start: b.slot_start, status: b.status, walk_in: true, on_behalf: true }, o.id);

    let work_order: WorkOrder | null = null;
    if (input.checkin) {
      const tpl = this.templates.find((t) => t.id === s.checklist_template_id && t.status === 'published') ?? this.templates.find((t) => t.id === s.checklist_template_id);
      const woRef = `WO-2026-${4826 + this.workOrders.length - 8}`;
      work_order = {
        id: nextId('wo'), ref: woRef, outlet: { id: o.id, name: o.name }, booking_ref: ref, quotation_ref: null, customer_name: customer.full_name,
        vehicle: { registration_no: v.registration_no, make: v.make, model: v.model }, service: { name: s.name, category: s.category }, status: 'queued',
        priority: input.checkin.priority ?? 2, bay: input.checkin.bay?.trim() || null, assignee_id: null, assignee_name: null, eta_at: end.toISOString(), due_at: new Date(end.getTime() + 15 * 60000).toISOString(),
        started_at: null, blocked_reason: null, steps_done: 0, step_count: tpl?.steps.length ?? 0, task_id: nextId('task'),
        events: [{ id: nextId('te'), actor_name: this.actor().full_name, event: 'checked_in', from_status: null, to_status: 'queued', reason: input.checkin.bay ? `Checked in at ${input.checkin.bay}` : 'Checked in', created_at: nowIso() }], updated_at: nowIso(),
      };
      this.workOrders.push(work_order);
      b.status = 'in_service';
      this.log('booking.checkin', 'booking', b.id, { status: 'confirmed' }, { status: 'in_service', work_order: woRef, bay: work_order.bay, priority: work_order.priority }, o.id);
      this.emit('work_orders');
    }
    this.pushActivity({ kind: 'assigned', title: `${ref} walk-in · ${s.name}`, subtitle: `${outletShort(o.id)} · ${v.registration_no} · by ${this.actor().full_name}${work_order?.bay ? ` · ${work_order.bay}` : ''}`, icon: 'directions_walk', tone: 'primary' });
    this.emit('bookings');
    const booking = this.expandBooking(b);
    return { booking, duplicate: false, ...(input.checkin ? { work_order: booking.work_order, task: work_order?.task_id ? { id: work_order.task_id, status: work_order.status } : null } : {}) };
  }

  async recordPayment(input: RecordPaymentInput): Promise<PosPayment> {
    await delay(260);
    this.requireStaff();
    const prior = this.ops.get(`payment:${input.idempotency_key}`);
    if (prior) return clone(this.posPayments.find((p) => p.id === prior)!);
    const b = this.bookings.find((x) => x.id === input.booking_id);
    if (!b) throw new ApiRequestError(404, { code: 'not_found', message: 'Booking not found' });
    this.requireOutletAccess(b.outlet_id);
    if (input.amount_cents !== b.total_cents) throw new ApiRequestError(400, { code: 'validation_error', message: `Amount must equal the booking total (${this.fmtR(b.total_cents)})`, details: [{ path: 'amount_cents', message: 'Must equal booking total' }] });
    if (this.payments.some((p) => p.booking_ref === b.ref && p.status === 'successful')) throw new ApiRequestError(409, { code: 'conflict', message: 'This booking is already paid' });
    const receipt = `RCP-${70010 + this.payments.length}`;
    const id = uuid();
    const now = nowIso();
    this.payments.unshift({ id, booking_ref: b.ref, customer_name: this.profile(b.customer_id)?.full_name ?? 'Customer', provider: 'pos', amount_cents: input.amount_cents, status: 'successful', receipt_no: receipt, verified_at: now, created_at: now });
    const pos: PosPayment = { id, booking_id: b.id, method: input.method, provider: 'pos', amount_cents: input.amount_cents, status: 'successful', receipt_no: receipt, provider_ref: input.reference?.trim() || null, verified_at: now, created_at: now };
    this.posPayments.push(pos);
    this.ops.set(`payment:${input.idempotency_key}`, id);
    this.log('payment.record', 'payment', id, null, { booking_ref: b.ref, amount_cents: input.amount_cents, method: input.method, reference: pos.provider_ref, receipt_no: receipt }, b.outlet_id);
    this.pushActivity({ kind: 'payment', title: `${this.fmtR(input.amount_cents)} ${input.method === 'cash' ? 'cash' : 'card'} payment recorded · ${b.ref}`, subtitle: `${receipt} · attested by ${this.actor().full_name}`, icon: 'point_of_sale', tone: 'primary' });
    this.emit('payments');
    return clone(pos);
  }

  /* ------------------------------------------------------------ catalogue */
  async listOutlets(): Promise<Outlet[]> { await delay(60); return clone(this.outlets); }
  async createOutlet(body: Partial<Outlet>): Promise<Outlet> {
    await delay(); this.requireRole('admin');
    const o: Outlet = { id: nextId('out'), code: body.code ?? 'NEW', name: body.name ?? 'New outlet', address_line: body.address_line ?? null, city: body.city ?? null, province: body.province ?? 'Gauteng', phone: body.phone ?? null, email: body.email ?? null, timezone: 'Africa/Johannesburg', opening_hours: body.opening_hours ?? OUTLETS[0].opening_hours, slot_minutes: body.slot_minutes ?? 30, bay_count: body.bay_count ?? 3, rating: null, is_active: body.is_active ?? true, legal_name: body.legal_name ?? null, trading_as: body.trading_as ?? body.name ?? null, company_registration_no: body.company_registration_no ?? null, vat_number: body.vat_number ?? null, registered_office: body.registered_office ?? null, bank_details: body.bank_details ?? null };
    this.outlets.push(o);
    // No services are bound yet: build the catalogue from Outlets → Catalogue ("Add service" / "Copy prices from outlet…").
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

  private static readonly PRICING_MODES = ['from', 'fixed', 'by_quote'] as const;
  private static readonly VAT_MODES = ['incl', 'excl'] as const;
  private static cents(v: unknown, path: string): number | null {
    if (v === null || v === undefined || v === '') return null;
    const n = Number(v);
    if (!Number.isInteger(n) || n < 0) throw new ApiRequestError(400, { code: 'validation_error', message: `${path} must be a non-negative integer (cents)`, details: [{ path, message: 'Invalid' }] });
    return n;
  }
  private static mode<T extends string>(v: unknown, allowed: readonly T[], path: string, nullable: boolean): T | null {
    if (v === null || v === undefined || v === '') {
      if (nullable) return null;
      throw new ApiRequestError(400, { code: 'validation_error', message: `${path} is required`, details: [{ path, message: 'Required' }] });
    }
    if (!allowed.includes(v as T)) throw new ApiRequestError(400, { code: 'validation_error', message: `${path} must be one of ${allowed.join(', ')}`, details: [{ path, message: 'Invalid' }] });
    return v as T;
  }
  /** Keeps the legacy `base_price_cents` / `is_quote_based` mirrors in step (migration 0008). */
  private static syncLegacy(s: Service) {
    s.is_quote_based = s.pricing_mode === 'by_quote';
    s.base_price_cents = s.price_small_cents ?? s.price_general_cents ?? s.base_price_cents ?? 0;
  }
  private applyServiceInput(s: Service, body: ServiceInput, isNew: boolean) {
    if (body.code !== undefined) {
      const code = String(body.code).trim().toUpperCase().replace(/[^A-Z0-9_]+/g, '_');
      if (!code) throw new ApiRequestError(400, { code: 'validation_error', message: 'code is required', details: [{ path: 'code', message: 'Required' }] });
      if (this.services.some((x) => x.id !== s.id && x.code === code)) throw new ApiRequestError(409, { code: 'conflict', message: `A service with code ${code} already exists`, details: { code } });
      s.code = code;
    }
    if (body.name !== undefined) {
      const name = String(body.name).trim();
      if (!name) throw new ApiRequestError(400, { code: 'validation_error', message: 'name is required', details: [{ path: 'name', message: 'Required' }] });
      s.name = name;
    }
    if (body.description !== undefined) s.description = body.description?.trim() || null;
    if (body.category !== undefined) s.category = DemoApi.mode(body.category, ['car_wash', 'auto_body'] as const, 'category', false)!;
    if (body.group_name !== undefined) s.group_name = DemoApi.mode(body.group_name, SERVICE_GROUPS, 'group_name', false)!;
    if (body.duration_minutes !== undefined) { const d = Math.round(Number(body.duration_minutes)); if (!(d > 0)) throw new ApiRequestError(400, { code: 'validation_error', message: 'duration_minutes must be positive', details: [{ path: 'duration_minutes', message: 'Invalid' }] }); s.duration_minutes = d; }
    if (body.pricing_mode !== undefined) s.pricing_mode = DemoApi.mode(body.pricing_mode, DemoApi.PRICING_MODES, 'pricing_mode', false)!;
    if (body.vat_mode !== undefined) s.vat_mode = DemoApi.mode(body.vat_mode, DemoApi.VAT_MODES, 'vat_mode', false)!;
    if (body.price_small_cents !== undefined) s.price_small_cents = DemoApi.cents(body.price_small_cents, 'price_small_cents');
    if (body.price_large_cents !== undefined) s.price_large_cents = DemoApi.cents(body.price_large_cents, 'price_large_cents');
    if (body.price_general_cents !== undefined) s.price_general_cents = DemoApi.cents(body.price_general_cents, 'price_general_cents');
    if (body.is_addon !== undefined) s.is_addon = Boolean(body.is_addon);
    if (body.addon_group_name !== undefined) s.addon_group_name = body.addon_group_name ? DemoApi.mode(body.addon_group_name, SERVICE_GROUPS, 'addon_group_name', true) : null;
    if (s.is_addon && !s.addon_group_name) throw new ApiRequestError(400, { code: 'validation_error', message: 'An add-on needs addon_group_name (the group it attaches to)', details: [{ path: 'addon_group_name', message: 'Required for add-ons' }] });
    if (body.notes !== undefined) s.notes = body.notes?.trim() || null;
    if (body.icon !== undefined) s.icon = body.icon?.trim() || 'local_car_wash';
    if (body.checklist_template_id !== undefined) s.checklist_template_id = body.checklist_template_id || null;
    if (body.is_active !== undefined) s.is_active = Boolean(body.is_active);
    if (body.sort_order !== undefined) s.sort_order = Number(body.sort_order) || s.sort_order;
    if (body.points_per_rand !== undefined) s.points_per_rand = Number(body.points_per_rand) || s.points_per_rand;
    if (body.components !== undefined) s.components = isNew ? this.validateComponents(s.id, body.components.filter((c) => c.child_service_id !== s.id), null) : this.validateComponents(s.id, body.components, null);
    if (s.pricing_mode === 'by_quote') { s.price_small_cents = null; s.price_large_cents = null; s.price_general_cents = null; }
    DemoApi.syncLegacy(s);
  }
  async listServices(): Promise<Service[]> {
    await delay(60);
    return clone([...this.services].sort((a, b) => a.sort_order - b.sort_order || a.name.localeCompare(b.name)));
  }
  async createService(body: ServiceInput): Promise<Service> {
    await delay(); this.requireRole('admin');
    const s: Service = {
      id: uuid(), code: '', name: '', description: null, category: 'car_wash', group_name: 'Car Wash Options', duration_minutes: 30, base_price_cents: 0, is_quote_based: false,
      pricing_mode: 'from', vat_mode: 'incl', price_small_cents: null, price_large_cents: null, price_general_cents: null, is_addon: false, addon_group_name: null, notes: null,
      points_per_rand: 0.1, icon: 'local_car_wash', checklist_template_id: null, is_active: true, sort_order: Math.max(0, ...this.services.map((x) => x.sort_order)) + 10, components: [],
    };
    this.applyServiceInput(s, { code: body.code ?? '', name: body.name ?? '', ...body }, true);
    this.services.push(s);
    this.log('service.create', 'service', s.id, null, { code: s.code, name: s.name, group_name: s.group_name, pricing_mode: s.pricing_mode, components: s.components.length });
    this.emit('services');
    return clone(s);
  }
  async updateService(id: string, patch: ServiceInput): Promise<Service> {
    await delay(); this.requireRole('admin');
    const s = this.services.find((x) => x.id === id);
    if (!s) throw new ApiRequestError(404, { code: 'not_found', message: 'Service not found' });
    const before = clone(s);
    const draft = clone(s);
    this.applyServiceInput(draft, patch, false);
    Object.assign(s, draft);
    this.log('service.update', 'service', id, before, patch);
    this.emit('services');
    return clone(s);
  }

  async listOutletOffers(outletId: string, f: OutletOfferFilters = {}): Promise<OutletServiceOffer[]> {
    await delay(80);
    this.requireRole('admin', 'manager', 'finance', 'supervisor');
    return this.offersAt(outletId, { size: f.vehicleSize, includeUnavailable: f.includeUnavailable ?? true });
  }
  async upsertOutletService(outletId: string, serviceId: string, body: OutletServiceInput): Promise<OutletServiceOffer> {
    await delay(); this.requireRole('admin');
    if (!this.outlets.some((o) => o.id === outletId)) throw new ApiRequestError(404, { code: 'not_found', message: 'Outlet not found' });
    const s = this.services.find((x) => x.id === serviceId);
    if (!s) throw new ApiRequestError(404, { code: 'not_found', message: 'Service not found' });
    const existing = this.offerRow(outletId, serviceId);
    const created = !existing;
    const bind = (): CatalogueOffer => {
      const maxSort = Math.max(0, ...this.outletServices.filter((x) => x.outlet_id === outletId).map((x) => x.sort_order));
      const row: CatalogueOffer = { outlet_id: outletId, service_id: serviceId, display_name: null, price_small_cents: null, price_large_cents: null, price_general_cents: null, pricing_mode: null, vat_mode: null, sort_order: maxSort + 10, notes: null, is_available: true };
      this.outletServices.push(row);
      return row;
    };
    const os: CatalogueOffer = existing ?? bind();
    const before = clone(os);
    if (body.display_name !== undefined) os.display_name = body.display_name?.trim() || null;
    if (body.price_small_cents !== undefined) os.price_small_cents = DemoApi.cents(body.price_small_cents, 'price_small_cents');
    if (body.price_large_cents !== undefined) os.price_large_cents = DemoApi.cents(body.price_large_cents, 'price_large_cents');
    if (body.price_general_cents !== undefined) os.price_general_cents = DemoApi.cents(body.price_general_cents, 'price_general_cents');
    if (body.pricing_mode !== undefined) os.pricing_mode = DemoApi.mode(body.pricing_mode, DemoApi.PRICING_MODES, 'pricing_mode', true);
    if (body.vat_mode !== undefined) os.vat_mode = DemoApi.mode(body.vat_mode, DemoApi.VAT_MODES, 'vat_mode', true);
    if (body.is_available !== undefined) os.is_available = Boolean(body.is_available);
    if (body.sort_order !== undefined && body.sort_order !== null) os.sort_order = Math.round(Number(body.sort_order)) || os.sort_order;
    if (body.notes !== undefined) os.notes = body.notes?.trim() || null;
    let componentsChange: 'global' | number | undefined;
    if (body.components === null) {
      this.components = this.components.filter((c) => !(c.outlet_id === outletId && c.parent_service_id === serviceId));
      componentsChange = 'global';
    } else if (Array.isArray(body.components)) {
      const rows = this.validateComponents(serviceId, body.components, outletId);
      this.components = [...this.components.filter((c) => !(c.outlet_id === outletId && c.parent_service_id === serviceId)), ...rows.map((c) => ({ parent_service_id: serviceId, child_service_id: c.child_service_id, outlet_id: outletId, quantity: c.quantity, sort_order: c.sort_order }))];
      componentsChange = rows.length;
    }
    this.log(created ? 'outlet_service.bind' : 'outlet_service.update', 'outlet_service', `${outletId}:${serviceId}`, created ? null : before, { ...body, ...(componentsChange !== undefined ? { components: componentsChange } : {}) }, outletId);
    this.emit('outlet_services');
    return this.resolveOffer(outletId, s, os);
  }
  async removeOutletService(outletId: string, serviceId: string): Promise<void> {
    await delay(); this.requireRole('admin');
    const os = this.offerRow(outletId, serviceId);
    if (!os) throw new ApiRequestError(404, { code: 'not_found', message: 'Service is not bound to this outlet' });
    this.outletServices = this.outletServices.filter((x) => x !== os);
    this.components = this.components.filter((c) => !(c.outlet_id === outletId && c.parent_service_id === serviceId));
    this.log('outlet_service.unbind', 'outlet_service', `${outletId}:${serviceId}`, os, null, outletId);
    this.emit('outlet_services');
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

  /* ------------------------------------------------------------ memberships (docs/MEMBERSHIPS.md) */
  private planOf(id: string): RawPlan {
    return this.plans.find((p) => p.id === id)!;
  }
  private liveMembership(customerId: string): Membership | undefined {
    return this.memberships.find((m) => m.customer_id === customerId && LIVE_MEMBERSHIP.includes(m.status));
  }
  private entitlementView(e: RawEntitlement): PlanEntitlement {
    return {
      id: e.id, code: e.code, label: e.label, quantity: e.quantity, period: e.period,
      services: e.service_codes.flatMap((code, i) => { const svc = this.services.find((x) => x.code === code); return svc ? [{ id: svc.id, code: svc.code, name: svc.name, is_primary: i === 0 }] : []; }),
    };
  }
  /** `GET /admin/memberships/plans` row: groups → entitlements → services, plus member count and MRR. */
  private planView(p: RawPlan): MembershipPlan {
    const groups = this.groups.filter((g) => g.plan_id === p.id).sort((a, b) => a.sort_order - b.sort_order).map((g) => ({
      id: g.id, code: g.code, name: g.name, selection: g.selection,
      entitlements: this.entitlements.filter((e) => e.group_id === g.id).sort((a, b) => a.sort_order - b.sort_order).map((e) => this.entitlementView(e)),
    }));
    const live = this.memberships.filter((m) => m.plan_id === p.id && LIVE_MEMBERSHIP.includes(m.status));
    return { ...p, groups, member_count: live.length, mrr_cents: live.filter((m) => m.status === 'active').length * p.monthly_fee_cents };
  }
  /** Monthly entitlements use the membership period; annual ones the membership year (anniversary → +1 year). */
  private entitlementPeriod(m: Membership, e: RawEntitlement): { start: string; end: string } {
    if (e.period === 'month') return { start: m.current_period_start, end: m.current_period_end };
    let start = m.started_at;
    while (new Date(addYears(start, 1)).getTime() <= Date.now()) start = addYears(start, 1);
    return { start, end: addYears(start, 1) };
  }
  /** The member's entitlements: the chosen option of each `choose_one` group plus every `all` group entitlement. */
  private selectedEntitlements(m: Membership): RawEntitlement[] {
    return this.groups.filter((g) => g.plan_id === m.plan_id).sort((a, b) => a.sort_order - b.sort_order).flatMap((g) => {
      if (g.selection === 'all') return this.entitlements.filter((e) => e.group_id === g.id);
      const sel = this.selections.find((x) => x.membership_id === m.id && x.group_id === g.id);
      return sel ? this.entitlements.filter((e) => e.id === sel.entitlement_id) : [];
    });
  }
  /** `remaining = quantity − Σ usage` for rows whose `period_start` is the entitlement's current period start. */
  private allowanceOf(m: Membership, e: RawEntitlement): MembershipAllowance {
    const { start, end } = this.entitlementPeriod(m, e);
    const used = this.usage.filter((u) => u.membership_id === m.id && u.entitlement_id === e.id && u.period_start === start).reduce((sum, u) => sum + u.quantity, 0);
    const g = this.groups.find((x) => x.id === e.group_id)!;
    return { entitlement_id: e.id, entitlement_code: e.code, group_code: g.code, label: e.label, quantity: e.quantity, used, remaining: Math.max(0, e.quantity - used), period: e.period, period_start: start, period_end: end };
  }
  private allowancesOf(m: Membership): MembershipAllowance[] {
    return this.selectedEntitlements(m).map((e) => this.allowanceOf(m, e));
  }
  /** Sum of remaining monthly washes (the "washes" group, else every monthly entitlement). */
  private includedRemaining(m: Membership): number {
    if (m.status !== 'active') return 0;
    const all = this.allowancesOf(m).filter((a) => a.period === 'month');
    const washes = all.filter((a) => a.group_code === 'washes');
    return (washes.length ? washes : all).reduce((sum, a) => sum + a.remaining, 0);
  }
  private selectionsMap(m: Membership): Record<string, string> {
    const out: Record<string, string> = {};
    for (const sel of this.selections.filter((x) => x.membership_id === m.id)) {
      const g = this.groups.find((x) => x.id === sel.group_id);
      const e = this.entitlements.find((x) => x.id === sel.entitlement_id);
      if (g && e) out[g.code] = e.code;
    }
    return out;
  }
  private benefitsSummary(plan: RawPlan, allowances: MembershipAllowance[]): string {
    const parts = allowances.map((a) => `${a.remaining} of ${a.quantity} ${a.label.replace(/^\d+\s*×\s*/, '')}${a.period === 'year' ? ' (this year)' : ''} left`);
    if (plan.discount_pct > 0 && plan.discount_scope !== 'none') parts.push(`${plan.discount_pct} % off ${plan.discount_scope === 'other_services' ? 'other services' : plan.discount_scope === 'plan_services' ? 'plan services' : 'all services'}`);
    return parts.join(' · ');
  }
  private openInvoiceOf(m: Membership): MembershipInvoice | null {
    return this.mInvoices.filter((i) => i.membership_id === m.id && i.status === 'pending').sort((a, b) => a.due_at.localeCompare(b.due_at))[0] ?? null;
  }
  /** `GET /staff/customers/:id/membership` / `customer.membership` shape. */
  private summaryFor(customerId: string): MembershipSummary {
    const m = this.liveMembership(customerId);
    const invoices = this.mInvoices.filter((i) => i.customer_id === customerId).sort((a, b) => b.period_start.localeCompare(a.period_start)).slice(0, 12);
    if (!m) return { membership: null, plan: null, selections: {}, allowances: [], open_invoice: null, invoices: clone(invoices), next_renewal_at: null, benefits_summary: '' };
    const plan = this.planOf(m.plan_id);
    const allowances = this.allowancesOf(m);
    return { membership: clone(m), plan: this.planView(plan), selections: this.selectionsMap(m), allowances, open_invoice: clone(this.openInvoiceOf(m)), invoices: clone(invoices), next_renewal_at: m.cancel_at_period_end ? null : m.current_period_end, benefits_summary: this.benefitsSummary(plan, allowances) };
  }
  /** `GET /admin/memberships` row. */
  private memberRow(m: Membership): MembershipRow {
    const c = this.profile(m.customer_id);
    const plan = this.planOf(m.plan_id);
    const allowances = this.allowancesOf(m);
    const monthly = allowances.filter((a) => a.period === 'month');
    return {
      ...clone(m), customer: { id: m.customer_id, full_name: c?.full_name ?? 'Customer', email: c?.email ?? null, phone: c?.phone ?? null },
      plan: { id: plan.id, code: plan.code, name: plan.name, tier: plan.tier, monthly_fee_cents: plan.monthly_fee_cents }, selections: this.selectionsMap(m), allowances,
      used: monthly.reduce((sum, a) => sum + a.used, 0), remaining: monthly.reduce((sum, a) => sum + a.remaining, 0), open_invoice: clone(this.openInvoiceOf(m)),
    };
  }
  /** Trigger `memberships_sync_tier`: the loyalty tier follows the live plan, otherwise silver. */
  private syncTier(customerId: string) {
    const m = this.liveMembership(customerId);
    const tier = m ? this.planOf(m.plan_id).tier : 'silver';
    const acct = this.loyaltyAccounts.find((a) => a.customer_id === customerId);
    if (!acct) { this.loyaltyAccounts.push({ customer_id: customerId, tier, balance_points: 0, lifetime_points: 0, tier_since: nowIso() }); return; }
    if (acct.tier !== tier) { acct.tier = tier; acct.tier_since = nowIso(); }
  }
  /** Pricing rules 2–3: included wash (covers the base) or the plan discount by scope; `past_due` pauses benefits. */
  private memberBenefit(customerId: string, service: Service, base: number, addons_cents: number): { discount: number; label: string | null; benefit: MembershipBenefit | null; membership: Membership; entitlement: RawEntitlement | null; pricing: MembershipPricing } | null {
    const m = this.liveMembership(customerId);
    if (!m || m.status !== 'active') return null;
    const plan = this.planOf(m.plan_id);
    const selected = this.selectedEntitlements(m);
    const covering = selected.find((e) => e.service_codes.includes(service.code));
    const info = (benefit: MembershipBenefit | null, entitlement_code: string | null, remaining_after: number | null, period_end: string | null): MembershipPricing => ({ plan_code: plan.code, plan_name: plan.name, benefit, entitlement_code, remaining_after, period_end });
    if (covering) {
      const a = this.allowanceOf(m, covering);
      if (a.remaining > 0) {
        const after = a.remaining - 1;
        return { discount: base, label: `Included in ${plan.name} · ${after} of ${a.quantity} left`, benefit: 'included', membership: m, entitlement: covering, pricing: info('included', covering.code, after, a.period_end) };
      }
    }
    const planCodes = new Set(this.entitlements.filter((e) => this.groups.some((g) => g.id === e.group_id && g.plan_id === plan.id)).flatMap((e) => e.service_codes));
    const selectedCodes = new Set(selected.flatMap((e) => e.service_codes));
    const applies = plan.discount_scope === 'plan_services' ? selectedCodes.has(service.code) : plan.discount_scope === 'other_services' ? !planCodes.has(service.code) : plan.discount_scope === 'all_services';
    if (!applies || plan.discount_pct <= 0) return { discount: 0, label: null, benefit: null, membership: m, entitlement: null, pricing: info(null, null, null, m.current_period_end) };
    return { discount: Math.round(((base + addons_cents) * plan.discount_pct) / 100), label: `${plan.name} −${plan.discount_pct}%`, benefit: 'discount', membership: m, entitlement: null, pricing: info('discount', null, null, m.current_period_end) };
  }
  private bookingMembership(b: RawBooking): MembershipPricing | null {
    if (!b.membership_id) return null;
    const m = this.memberships.find((x) => x.id === b.membership_id);
    if (!m) return null;
    const plan = this.planOf(m.plan_id);
    const ent = b.entitlement_id ? this.entitlements.find((e) => e.id === b.entitlement_id) : undefined;
    return { plan_code: plan.code, plan_name: plan.name, benefit: b.membership_benefit ?? null, entitlement_code: ent?.code ?? null, remaining_after: ent ? this.allowanceOf(m, ent).remaining : null, period_end: m.current_period_end };
  }
  /** Idempotent +1 usage for a booking that redeemed an entitlement (`booking:<id>:membership`). */
  private postUsage(b: RawBooking) {
    if (!b.membership_id || !b.entitlement_id) return;
    const key = `booking:${b.id}:membership`;
    if (this.usage.some((u) => u.idempotency_key === key)) return;
    const m = this.memberships.find((x) => x.id === b.membership_id);
    const e = this.entitlements.find((x) => x.id === b.entitlement_id);
    if (!m || !e) return;
    const { start, end } = this.entitlementPeriod(m, e);
    this.usage.push({ id: nextId('mu'), membership_id: m.id, entitlement_id: e.id, booking_id: b.id, quantity: 1, period_start: start, period_end: end, idempotency_key: key, created_at: nowIso() });
    this.emit('membership_usage');
  }
  /** Idempotent −1 release row when a redeemed booking is cancelled (`booking:<id>:membership_release`). */
  private releaseUsage(b: RawBooking) {
    if (b.membership_benefit !== 'included' || !b.membership_id || !b.entitlement_id) return;
    const key = `booking:${b.id}:membership_release`;
    if (this.usage.some((u) => u.idempotency_key === key)) return;
    const posted = this.usage.find((u) => u.idempotency_key === `booking:${b.id}:membership`);
    if (!posted) return;
    this.usage.push({ ...posted, id: nextId('mu'), quantity: -1, idempotency_key: key, created_at: nowIso() });
    this.emit('membership_usage');
  }
  private notify(customerId: string, template_key: string, title: string, body: string, payload: Record<string, unknown> = {}) {
    const c = this.profile(customerId);
    this.notifications.unshift({ id: nextId('n'), recipient_id: customerId, recipient_name: c?.full_name ?? null, channel: 'push', template_key, title, body, payload, status: 'sent', provider_status: null, provider_ref: null, provider_error_code: null, error: null, attempts: 1, sent_at: nowIso(), delivered_at: null, read_at: null, created_at: nowIso() });
  }
  private nextMemRef() {
    return `MEM-2026-${String(this.memberships.reduce((mx, m) => Math.max(mx, Number(m.ref.split('-').pop()) || 0), 0) + 1).padStart(4, '0')}`;
  }
  private nextInvRef() {
    return `MINV-2026-${String(this.mInvoices.reduce((mx, i) => Math.max(mx, Number(i.ref.split('-').pop()) || 0), 0) + 1).padStart(4, '0')}`;
  }
  /** Marks an invoice paid (payment row + receipt); a renewal invoice rolls the period and re-activates the membership. */
  private settleInvoice(inv: MembershipInvoice, m: Membership, provider: 'pos' | 'sandbox', method: string, recordedBy: string | null): Payment {
    const now = nowIso();
    const id = uuid();
    const receipt = `RCP-${70010 + this.payments.length}`;
    const pay: Payment = { id, booking_ref: null, membership_invoice_id: inv.id, customer_name: this.profile(m.customer_id)?.full_name ?? 'Customer', provider, amount_cents: inv.amount_cents, status: 'successful', receipt_no: receipt, verified_at: now, created_at: now };
    this.payments.unshift(pay);
    inv.status = 'paid'; inv.paid_at = now; inv.payment_id = id;
    const plan = this.planOf(m.plan_id);
    if (inv.period_start >= m.current_period_end) {
      m.current_period_start = inv.period_start; m.current_period_end = inv.period_end; m.status = 'active';
      this.notify(m.customer_id, 'membership_renewed', `${plan.name} membership renewed`, `Paid ${this.fmtR(inv.amount_cents)}. Your washes have been reset for the month.`, { type: 'membership', id: m.id });
    } else if (m.status === 'pending') {
      m.status = 'active';
    }
    this.syncTier(m.customer_id);
    this.log('membership.invoice.pay', 'membership_invoice', inv.id, { status: 'pending' }, { status: 'paid', method, provider, recorded_by: recordedBy, amount_cents: inv.amount_cents, receipt_no: receipt });
    this.emit('membership_invoices');
    this.emit('payments');
    return pay;
  }

  async membershipPlans(): Promise<MembershipPlan[]> {
    await delay(80);
    this.requireRole('admin', 'manager', 'finance', 'supervisor');
    return [...this.plans].sort((a, b) => a.sort_order - b.sort_order).map((p) => this.planView(p));
  }
  async saveMembershipPlan(code: string, body: MembershipPlanInput): Promise<MembershipPlan> {
    await delay(200);
    this.requireRole('admin', 'manager');
    const p = this.plans.find((x) => x.code === code);
    if (!p) throw new ApiRequestError(404, { code: 'not_found', message: 'Plan not found' });
    const name = String(body.name ?? '').trim();
    if (!name) throw new ApiRequestError(400, { code: 'validation_error', message: 'name is required', details: [{ path: 'name', message: 'Required' }] });
    const fee = Math.round(Number(body.monthly_fee_cents));
    if (!(fee >= 0)) throw new ApiRequestError(400, { code: 'validation_error', message: 'monthly_fee_cents must be a non-negative integer', details: [{ path: 'monthly_fee_cents', message: 'Invalid' }] });
    const pct = Number(body.discount_pct);
    if (!(pct >= 0 && pct <= 100)) throw new ApiRequestError(400, { code: 'validation_error', message: 'discount_pct must be between 0 and 100', details: [{ path: 'discount_pct', message: 'Invalid' }] });
    if (!['plan_services', 'other_services', 'all_services', 'none'].includes(body.discount_scope)) throw new ApiRequestError(400, { code: 'validation_error', message: 'discount_scope is invalid', details: [{ path: 'discount_scope', message: 'Invalid' }] });
    // Full replace of groups / entitlements by code — ids are kept when the code already exists so usage rows stay valid.
    const oldGroups = this.groups.filter((g) => g.plan_id === p.id);
    const oldEnts = this.entitlements.filter((e) => oldGroups.some((g) => g.id === e.group_id));
    const newGroups: RawGroup[] = [];
    const newEnts: RawEntitlement[] = [];
    (body.groups ?? []).forEach((g, gi) => {
      const gcode = String(g.code ?? '').trim().toLowerCase().replace(/[^a-z0-9_]+/g, '_');
      if (!gcode) throw new ApiRequestError(400, { code: 'validation_error', message: 'Every group needs a code', details: [{ path: `groups.${gi}.code`, message: 'Required' }] });
      if (newGroups.some((x) => x.code === gcode)) throw new ApiRequestError(400, { code: 'validation_error', message: `Duplicate group code ${gcode}`, details: [{ path: `groups.${gi}.code`, message: 'Duplicate' }] });
      const prev = oldGroups.find((x) => x.code === gcode);
      const row: RawGroup = { id: prev?.id ?? uuid(), plan_id: p.id, code: gcode, name: String(g.name ?? '').trim() || gcode, selection: g.selection === 'all' ? 'all' : 'choose_one', sort_order: (gi + 1) * 10 };
      newGroups.push(row);
      (g.entitlements ?? []).forEach((e, ei) => {
        const ecode = String(e.code ?? '').trim().toUpperCase().replace(/[^A-Z0-9_]+/g, '_');
        if (!ecode) throw new ApiRequestError(400, { code: 'validation_error', message: 'Every option needs a code', details: [{ path: `groups.${gi}.entitlements.${ei}.code`, message: 'Required' }] });
        if (newEnts.some((x) => x.code === ecode)) throw new ApiRequestError(400, { code: 'validation_error', message: `Duplicate option code ${ecode}`, details: [{ path: `groups.${gi}.entitlements.${ei}.code`, message: 'Duplicate' }] });
        const qty = Math.round(Number(e.quantity));
        if (!(qty > 0)) throw new ApiRequestError(400, { code: 'validation_error', message: `${ecode}: quantity must be a positive integer`, details: [{ path: `groups.${gi}.entitlements.${ei}.quantity`, message: 'Invalid' }] });
        const codes = [...new Set((e.service_codes ?? []).map((c) => String(c).trim().toUpperCase()).filter(Boolean))];
        if (!codes.length) throw new ApiRequestError(400, { code: 'validation_error', message: `${ecode}: pick at least one service`, details: [{ path: `groups.${gi}.entitlements.${ei}.service_codes`, message: 'Required' }] });
        const unknown = codes.find((c) => !this.services.some((sv) => sv.code === c));
        if (unknown) throw new ApiRequestError(404, { code: 'not_found', message: `Unknown service code ${unknown}`, details: [{ path: `groups.${gi}.entitlements.${ei}.service_codes`, message: 'Unknown service' }] });
        const prevE = oldEnts.find((x) => x.code === ecode);
        newEnts.push({ id: prevE?.id ?? uuid(), group_id: row.id, code: ecode, label: String(e.label ?? '').trim() || `${qty} × ${codes[0]}`, quantity: qty, period: e.period === 'year' ? 'year' : 'month', sort_order: (ei + 1) * 10, service_codes: codes });
      });
    });
    const removedWithUsage = oldEnts.find((e) => !newEnts.some((n) => n.id === e.id) && this.usage.some((u) => u.entitlement_id === e.id));
    if (removedWithUsage) throw new ApiRequestError(409, { code: 'conflict', message: `${removedWithUsage.code} has been redeemed by members and cannot be deleted — keep it and stop offering it on new memberships instead`, details: { entitlement_code: removedWithUsage.code } });
    const before = this.planView(p);
    Object.assign(p, { name, tagline: body.tagline?.trim() || null, monthly_fee_cents: fee, discount_pct: pct, discount_scope: body.discount_scope, discount_note: body.discount_note?.trim() || null, is_active: Boolean(body.is_active) });
    this.groups = [...this.groups.filter((g) => g.plan_id !== p.id), ...newGroups];
    this.entitlements = [...this.entitlements.filter((e) => !oldEnts.some((o) => o.id === e.id)), ...newEnts];
    // Selections pointing at removed options are dropped (their entitlement had no usage — see the 409 above).
    this.selections = this.selections.filter((sel) => this.entitlements.some((e) => e.id === sel.entitlement_id) && this.groups.some((g) => g.id === sel.group_id));
    const after = this.planView(p);
    this.log('membership_plan.update', 'membership_plan', p.id, { name: before.name, monthly_fee_cents: before.monthly_fee_cents, discount_pct: before.discount_pct, discount_scope: before.discount_scope, groups: before.groups.length }, { name: after.name, monthly_fee_cents: after.monthly_fee_cents, discount_pct: after.discount_pct, discount_scope: after.discount_scope, groups: after.groups.length, entitlements: newEnts.length, is_active: p.is_active });
    this.pushActivity({ kind: 'loyalty', title: `${p.name} plan updated · ${this.fmtR(p.monthly_fee_cents)} / month`, subtitle: `Fee changes apply from the next invoice · by ${this.actor().full_name}`, icon: 'workspace_premium', tone: 'primary' });
    this.emit('membership_plans');
    return after;
  }
  async listMemberships(f: MembershipFilters): Promise<Page<MembershipRow>> {
    await delay();
    this.requireRole('admin', 'manager', 'finance');
    let rows = [...this.memberships].sort((a, b) => b.created_at.localeCompare(a.created_at));
    if (f.status && f.status !== 'all') rows = rows.filter((m) => m.status === f.status);
    if (f.plan_code) rows = rows.filter((m) => this.planOf(m.plan_id).code === f.plan_code);
    if (f.q) {
      const q = f.q.toLowerCase();
      rows = rows.filter((m) => m.ref.toLowerCase().includes(q) || (this.profile(m.customer_id)?.full_name ?? '').toLowerCase().includes(q) || (this.profile(m.customer_id)?.phone ?? '').includes(q));
    }
    const limit = f.limit ?? 50;
    const start = f.cursor ? Number(f.cursor) : 0;
    return { data: rows.slice(start, start + limit).map((m) => this.memberRow(m)), next_cursor: start + limit < rows.length ? String(start + limit) : null };
  }
  async customerMembership(customerId: string): Promise<MembershipSummary> {
    await delay(80);
    this.requireRole('admin', 'manager', 'finance', 'supervisor');
    if (!this.profiles.some((p) => p.id === customerId && p.role === 'customer')) throw new ApiRequestError(404, { code: 'not_found', message: 'Customer not found' });
    return this.summaryFor(customerId);
  }
  async enrolMembership(customerId: string, body: EnrolMembershipInput): Promise<MembershipSummary> {
    await delay(300);
    this.requireRole('admin', 'manager');
    const prior = this.ops.get(`membership:${body.client_op_id}`);
    if (prior) return this.summaryFor(customerId);
    const customer = this.profiles.find((p) => p.id === customerId && p.role === 'customer');
    if (!customer) throw new ApiRequestError(404, { code: 'not_found', message: 'Customer not found' });
    const existing = this.liveMembership(customerId);
    if (existing) throw new ApiRequestError(409, { code: 'conflict', message: `${customer.full_name} already has a live ${this.planOf(existing.plan_id).name} membership (${existing.ref})`, details: { existing_membership_id: existing.id } });
    const plan = this.plans.find((p) => p.code === body.plan_code && p.is_active);
    if (!plan) throw new ApiRequestError(404, { code: 'not_found', message: 'Plan not found or inactive', details: [{ path: 'plan_code', message: 'Unknown plan' }] });
    if (!COUNTER_METHODS.includes(body.payment_method)) throw new ApiRequestError(400, { code: 'validation_error', message: 'payment_method must be cash, card_terminal or eft', details: [{ path: 'payment_method', message: 'Invalid' }] });
    const now = nowIso();
    const m: Membership = { id: uuid(), ref: this.nextMemRef(), customer_id: customerId, plan_id: plan.id, status: 'active', started_at: now, current_period_start: now, current_period_end: addMonths(now, 1), cancel_at_period_end: false, cancelled_at: null, ended_at: null, next_plan_id: null, payment_method: body.payment_method === 'card_terminal' ? 'card' : body.payment_method, created_by: this.actorId, created_at: now };
    const sels: RawSelection[] = [];
    for (const g of this.groups.filter((x) => x.plan_id === plan.id)) {
      if (g.selection !== 'choose_one') continue;
      const code = body.selections?.[g.code];
      const e = code ? this.entitlements.find((x) => x.group_id === g.id && x.code === code) : undefined;
      if (!e) throw new ApiRequestError(400, { code: 'validation_error', message: `Choose an option for ${g.name}`, details: [{ path: `selections.${g.code}`, message: 'Required' }] });
      sels.push({ membership_id: m.id, group_id: g.id, entitlement_id: e.id });
    }
    this.memberships.push(m);
    this.selections.push(...sels);
    const inv: MembershipInvoice = { id: uuid(), ref: this.nextInvRef(), membership_id: m.id, customer_id: customerId, period_start: m.current_period_start, period_end: m.current_period_end, amount_cents: plan.monthly_fee_cents, status: 'pending', due_at: now, paid_at: null, payment_id: null };
    this.mInvoices.push(inv);
    this.ops.set(`membership:${body.client_op_id}`, m.id);
    const pay = this.settleInvoice(inv, m, 'pos', body.payment_method, this.actorId);
    const summary = this.summaryFor(customerId);
    this.log('membership.enrol', 'membership', m.id, null, { ref: m.ref, customer_id: customerId, plan_code: plan.code, selections: body.selections, payment_method: body.payment_method, amount_cents: inv.amount_cents, receipt_no: pay.receipt_no, on_behalf: true });
    this.notify(customerId, 'membership_activated', `Welcome to Sparkling ${plan.name}`, `Your ${plan.name} membership is active until ${new Date(m.current_period_end).toLocaleDateString('en-ZA', { day: 'numeric', month: 'short' })}. ${summary.benefits_summary}`, { type: 'membership', id: m.id });
    this.pushActivity({ kind: 'loyalty', title: `${customer.full_name} joined ${plan.name} · ${this.fmtR(plan.monthly_fee_cents)}`, subtitle: `${m.ref} · ${body.payment_method.replace('_', ' ')} at the counter · by ${this.actor().full_name}`, icon: 'workspace_premium', tone: 'primary' });
    this.emit('memberships');
    return summary;
  }
  async cancelMembership(id: string, body: { at_period_end: boolean; reason?: string }): Promise<MembershipSummary> {
    await delay(200);
    this.requireRole('admin', 'manager');
    const m = this.memberships.find((x) => x.id === id);
    if (!m) throw new ApiRequestError(404, { code: 'not_found', message: 'Membership not found' });
    if (!LIVE_MEMBERSHIP.includes(m.status)) throw new ApiRequestError(409, { code: 'invalid_transition', message: `Membership is already ${m.status.replace('_', ' ')}` });
    const before = { status: m.status, cancel_at_period_end: m.cancel_at_period_end };
    const plan = this.planOf(m.plan_id);
    m.cancelled_at = nowIso();
    if (body.at_period_end) {
      m.cancel_at_period_end = true;
    } else {
      m.status = 'cancelled';
      m.ended_at = nowIso();
      for (const inv of this.mInvoices.filter((i) => i.membership_id === m.id && i.status === 'pending')) inv.status = 'void';
    }
    this.syncTier(m.customer_id);
    this.log('membership.cancel', 'membership', m.id, before, { status: m.status, cancel_at_period_end: m.cancel_at_period_end, reason: body.reason ?? null });
    this.notify(m.customer_id, 'membership_cancelled', 'Membership cancelled', `Your ${plan.name} membership ends on ${new Date(body.at_period_end ? m.current_period_end : m.ended_at!).toLocaleDateString('en-ZA', { day: 'numeric', month: 'short' })}. You can rejoin any time.`, { type: 'membership', id: m.id });
    this.pushActivity({ kind: 'loyalty', title: `${this.profile(m.customer_id)?.full_name ?? 'Member'} cancelled ${plan.name}`, subtitle: body.at_period_end ? `Benefits continue until the period ends · ${m.ref}` : `Immediate · tier back to Silver · ${m.ref}`, icon: 'cancel', tone: 'warning' });
    this.emit('memberships');
    return this.summaryFor(m.customer_id);
  }
  async recordMembershipPayment(id: string, invoiceId: string, body: { method: 'cash' | 'card_terminal' | 'eft'; client_op_id: string }): Promise<RecordMembershipPaymentResult> {
    await delay(260);
    this.requireRole('admin', 'manager');
    const m = this.memberships.find((x) => x.id === id);
    if (!m) throw new ApiRequestError(404, { code: 'not_found', message: 'Membership not found' });
    const inv = this.mInvoices.find((i) => i.id === invoiceId && i.membership_id === m.id);
    if (!inv) throw new ApiRequestError(404, { code: 'not_found', message: 'Invoice not found' });
    const prior = this.ops.get(`membership_payment:${body.client_op_id}`);
    if (prior) return { invoice: clone(inv), membership: clone(m), duplicate: true };
    if (inv.status !== 'pending') throw new ApiRequestError(409, { code: 'conflict', message: `Invoice ${inv.ref} is ${inv.status}` });
    if (!COUNTER_METHODS.includes(body.method)) throw new ApiRequestError(400, { code: 'validation_error', message: 'method must be cash, card_terminal or eft', details: [{ path: 'method', message: 'Invalid' }] });
    const pay = this.settleInvoice(inv, m, 'pos', body.method, this.actorId);
    this.ops.set(`membership_payment:${body.client_op_id}`, pay.id);
    this.pushActivity({ kind: 'payment', title: `${this.fmtR(inv.amount_cents)} ${body.method.replace('_', ' ')} · ${inv.ref}`, subtitle: `${this.planOf(m.plan_id).name} renewal for ${this.profile(m.customer_id)?.full_name ?? 'member'} · ${pay.receipt_no}`, icon: 'point_of_sale', tone: 'primary' });
    this.emit('memberships');
    return { invoice: clone(inv), membership: clone(m), duplicate: false };
  }
  /** The daily `membershipRenewals` job (02:00 Africa/Johannesburg), on demand. */
  async runMembershipRenewals(): Promise<RenewalRunResult> {
    await delay(400);
    this.requireRole('admin', 'manager');
    const now = Date.now();
    const soon = now + 3 * 24 * 60 * 60_000;
    const out: RenewalRunResult = { expired: 0, invoiced: 0, past_due: 0, renewed: 0 };
    for (const m of this.memberships.filter((x) => LIVE_MEMBERSHIP.includes(x.status))) {
      const plan = this.planOf(m.plan_id);
      const end = new Date(m.current_period_end).getTime();
      // 1. cancel_at_period_end and the period has ended → expired (tier → silver)
      if (m.cancel_at_period_end && end <= now) {
        m.status = 'expired'; m.ended_at = nowIso();
        this.syncTier(m.customer_id);
        out.expired += 1;
        continue;
      }
      // 2. renewal invoice 3 days ahead (idempotent per period start)
      const nextStart = m.current_period_end;
      if (m.status === 'active' && !m.cancel_at_period_end && end <= soon && !this.mInvoices.some((i) => i.membership_id === m.id && i.period_start === nextStart && i.status !== 'void')) {
        const inv: MembershipInvoice = { id: uuid(), ref: this.nextInvRef(), membership_id: m.id, customer_id: m.customer_id, period_start: nextStart, period_end: addMonths(nextStart, 1), amount_cents: plan.monthly_fee_cents, status: 'pending', due_at: nextStart, paid_at: null, payment_id: null };
        this.mInvoices.push(inv);
        this.notify(m.customer_id, 'membership_renewal_due', `${plan.name} membership renewal`, `Your ${plan.name} membership renews on ${new Date(nextStart).toLocaleDateString('en-ZA', { day: 'numeric', month: 'short' })} (${this.fmtR(inv.amount_cents)}).`, { type: 'membership_invoice', id: inv.id });
        out.invoiced += 1;
      }
      const pending = this.openInvoiceOf(m);
      // 4. sandbox card on file → the due renewal is auto-charged so demo renewals roll over
      if (pending && m.payment_method === 'card' && new Date(pending.due_at).getTime() <= now) {
        this.settleInvoice(pending, m, 'sandbox', 'card', null);
        out.renewed += 1;
        continue;
      }
      // 3. period ended and the invoice is unpaid → past_due (benefits paused, tier label kept)
      if (end <= now && pending && m.status !== 'past_due') {
        m.status = 'past_due';
        this.notify(m.customer_id, 'membership_past_due', 'Membership payment due', `Your ${plan.name} benefits are paused until ${this.fmtR(pending.amount_cents)} is paid.`, { type: 'membership_invoice', id: pending.id });
        out.past_due += 1;
      }
    }
    this.log('membership.run_renewals', 'membership', null, null, out);
    this.pushActivity({ kind: 'loyalty', title: `Renewals run · ${out.invoiced} invoiced · ${out.renewed} renewed`, subtitle: `${out.past_due} past due · ${out.expired} expired · by ${this.actor().full_name}`, icon: 'autorenew', tone: 'neutral' });
    this.emit('memberships');
    return out;
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
        return buildCsv(meta, ['customer', 'tier', 'plan', 'balance_points', 'lifetime_points', 'tier_since'], this.loyaltyAccounts.map((a) => ({ customer: profileName(a.customer_id), tier: a.tier, plan: this.loyaltySummary(a.customer_id)?.plan_name ?? '', balance_points: a.balance_points, lifetime_points: a.lifetime_points, tier_since: a.tier_since })));
      case 'memberships':
        return buildCsv(meta, ['ref', 'customer', 'plan', 'status', 'period_start', 'period_end', 'fee_cents', 'used', 'remaining', 'open_invoice'], this.memberships.map((m) => this.memberRow(m)).map((r) => ({ ref: r.ref, customer: r.customer.full_name, plan: r.plan.name, status: r.status, period_start: r.current_period_start, period_end: r.current_period_end, fee_cents: r.plan.monthly_fee_cents, used: r.used, remaining: r.remaining, open_invoice: r.open_invoice?.ref ?? '' })));
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
