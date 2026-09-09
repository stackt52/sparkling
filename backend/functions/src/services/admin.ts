/**
 * ADM-010..041 / REP-001..007: KPIs, exceptions, activity feed, exports.
 * Aggregations are done in JS over Supabase queries (no SQL views needed).
 */
import { stringify } from 'csv-stringify/sync';
import { pageResult } from '../lib/refs.js';
import { getSupabase, unwrap } from '../lib/supabase.js';
import type { AuthContext } from '../types.js';

export interface KpiRange {
  from: string;
  to: string;
  outletIds: string[] | null; // null = all
}

function hourOf(iso: string, timezone: string): number {
  const fmt = new Intl.DateTimeFormat('en-GB', { timeZone: timezone, hour: '2-digit', hour12: false });
  return Number(fmt.format(new Date(iso)));
}

export function todayRangeUtc(now = new Date()): { from: string; to: string } {
  const start = new Date(Date.UTC(now.getUTCFullYear(), now.getUTCMonth(), now.getUTCDate()));
  const end = new Date(start.getTime() + 86400_000);
  return { from: start.toISOString(), to: end.toISOString() };
}

export function previousRange(from: string, to: string): { from: string; to: string } {
  const f = new Date(from).getTime();
  const t = new Date(to).getTime();
  const span = Math.max(1, t - f);
  return { from: new Date(f - span).toISOString(), to: new Date(f).toISOString() };
}

export function trendPct(current: number, previous: number): number | null {
  if (previous === 0) return current === 0 ? 0 : null;
  return Math.round(((current - previous) / previous) * 1000) / 10;
}

export async function computeKpis(range: KpiRange) {
  const db = getSupabase();
  const prev = previousRange(range.from, range.to);
  const today = todayRangeUtc();

  const scope = <T>(q: T): T => (range.outletIds ? (q as any).in('outlet_id', range.outletIds) : q);

  const paymentsSel = 'id, amount_cents, status, verified_at, booking:bookings!inner(outlet_id, service_id)';
  const [curPay, prevPay, bookingsToday, activeWos, completedToday, alerts, failedPays, staffPts, outlets, services] = await Promise.all([
    db.from('payments').select(paymentsSel).eq('status', 'successful').gte('verified_at', range.from).lt('verified_at', range.to),
    db.from('payments').select(paymentsSel).eq('status', 'successful').gte('verified_at', prev.from).lt('verified_at', prev.to),
    scope(db.from('bookings').select('id, slot_start, status, outlet_id, service_id, total_cents').gte('slot_start', today.from).lt('slot_start', today.to)),
    scope(db.from('work_orders').select('id, status, due_at, outlet_id').in('status', ['queued', 'assigned', 'in_progress', 'blocked'])),
    scope(db.from('work_orders').select('id').in('status', ['completed', 'verified']).gte('updated_at', today.from).lt('updated_at', today.to)),
    scope(db.from('inventory_alerts').select('id').neq('status', 'resolved')),
    db.from('payments').select('id, booking:bookings!inner(outlet_id)').eq('status', 'failed').gte('updated_at', range.from).lt('updated_at', range.to),
    scope(db.from('staff_points_ledger').select('staff_id, delta, outlet_id').gte('created_at', range.from).lt('created_at', range.to)),
    db.from('outlets').select('id, name, timezone'),
    db.from('services').select('id, category'),
  ]);

  const inScope = (outletId: string | null | undefined) => !range.outletIds || (outletId ? range.outletIds.includes(outletId) : false);
  const sumRevenue = (rows: Array<any>) => rows.filter((p) => inScope(p.booking?.outlet_id)).reduce((a, p) => a + Number(p.amount_cents), 0);
  const revenue = sumRevenue(unwrap<any[]>(curPay, 'payments'));
  const prevRevenue = sumRevenue(unwrap<any[]>(prevPay, 'payments'));

  const outletRows = unwrap<Array<{ id: string; name: string; timezone: string }>>(outlets, 'outlets');
  const tz = new Map(outletRows.map((o) => [o.id, o.timezone]));
  const categoryOf = new Map(unwrap<Array<{ id: string; category: string }>>(services, 'services').map((s) => [s.id, s.category]));

  const byHour = new Map<number, { car_wash: number; auto_body: number }>();
  for (const b of unwrap<any[]>(bookingsToday, 'bookings')) {
    if (b.status === 'cancelled') continue;
    const h = hourOf(b.slot_start, tz.get(b.outlet_id) ?? 'Africa/Johannesburg');
    const cur = byHour.get(h) ?? { car_wash: 0, auto_body: 0 };
    const cat = categoryOf.get(b.service_id) === 'auto_body' ? 'auto_body' : 'car_wash';
    cur[cat] += 1;
    byHour.set(h, cur);
  }
  const bookings_by_hour = [...byHour.entries()].sort((a, b) => a[0] - b[0]).map(([hour, v]) => ({ hour, ...v }));

  const revenueByOutlet = new Map<string, number>();
  for (const p of unwrap<any[]>(curPay, 'payments')) {
    const oid = p.booking?.outlet_id;
    if (!inScope(oid)) continue;
    revenueByOutlet.set(oid, (revenueByOutlet.get(oid) ?? 0) + Number(p.amount_cents));
  }
  const revenue_by_outlet = outletRows
    .filter((o) => inScope(o.id))
    .map((o) => ({ outlet_id: o.id, name: o.name, revenue_cents: revenueByOutlet.get(o.id) ?? 0 }))
    .sort((a, b) => b.revenue_cents - a.revenue_cents);

  const pts = new Map<string, number>();
  for (const r of unwrap<any[]>(staffPts, 'staff points')) pts.set(r.staff_id, (pts.get(r.staff_id) ?? 0) + Number(r.delta));
  const topIds = [...pts.entries()].sort((a, b) => b[1] - a[1]).slice(0, 5);
  const names = topIds.length ? unwrap<Array<{ id: string; full_name: string }>>(await db.from('profiles').select('id, full_name').in('id', topIds.map((t) => t[0])), 'profiles') : [];
  const nameMap = new Map(names.map((n) => [n.id, n.full_name]));
  const top_staff = topIds.map(([staff_id, points], i) => ({ staff_id, name: nameMap.get(staff_id) ?? staff_id, points, rank: i + 1 }));

  const wos = unwrap<any[]>(activeWos, 'work orders');
  const now = Date.now();
  const overdue = wos.filter((w) => w.due_at && new Date(w.due_at).getTime() < now).length;
  const blocked = wos.filter((w) => w.status === 'blocked').length;
  const failed = unwrap<any[]>(failedPays, 'failed payments').filter((p) => inScope(p.booking?.outlet_id)).length;
  const exceptions_count = blocked + overdue + unwrap<any[]>(alerts, 'alerts').length + failed;

  return {
    range: { from: range.from, to: range.to },
    revenue_cents: revenue,
    revenue_previous_cents: prevRevenue,
    revenue_trend_pct: trendPct(revenue, prevRevenue),
    bookings_today: unwrap<any[]>(bookingsToday, 'bookings').filter((b) => b.status !== 'cancelled').length,
    active_work_orders: wos.length,
    completed_today: unwrap<any[]>(completedToday, 'completed').length,
    exceptions_count,
    exceptions_breakdown: { blocked, overdue, stock_alerts: unwrap<any[]>(alerts, 'alerts').length, failed_payments: failed },
    bookings_by_hour,
    revenue_by_outlet,
    top_staff,
  };
}

export interface ExceptionItem {
  type: 'blocked' | 'overdue' | 'low_stock' | 'out_of_stock' | 'failed_payment';
  severity: 'high' | 'medium' | 'low';
  title: string;
  detail: string | null;
  outlet_id: string | null;
  at: string | null;
  link: { type: string; id: string };
}

export async function computeExceptions(outletIds: string[] | null): Promise<ExceptionItem[]> {
  const db = getSupabase();
  const scope = <T>(q: T): T => (outletIds ? (q as any).in('outlet_id', outletIds) : q);
  const [wos, alerts, pays] = await Promise.all([
    scope(db.from('work_orders').select('id, ref, status, due_at, blocked_reason, outlet_id, updated_at, vehicle:vehicles(registration_no)').in('status', ['queued', 'assigned', 'in_progress', 'blocked'])),
    scope(db.from('inventory_alerts').select('id, level, outlet_id, created_at, item:inventory_items(id, name, on_hand, reorder_threshold)').neq('status', 'resolved')),
    db.from('payments').select('id, amount_cents, failure_reason, updated_at, booking:bookings!inner(ref, outlet_id)').eq('status', 'failed').gte('updated_at', new Date(Date.now() - 7 * 86400_000).toISOString()),
  ]);
  const out: ExceptionItem[] = [];
  const now = Date.now();
  for (const w of unwrap<any[]>(wos, 'work orders')) {
    if (w.status === 'blocked') out.push({ type: 'blocked', severity: 'high', title: `${w.ref} blocked`, detail: w.blocked_reason, outlet_id: w.outlet_id, at: w.updated_at, link: { type: 'work_order', id: w.id } });
    else if (w.due_at && new Date(w.due_at).getTime() < now) out.push({ type: 'overdue', severity: 'medium', title: `${w.ref} overdue SLA`, detail: w.vehicle?.registration_no ?? null, outlet_id: w.outlet_id, at: w.due_at, link: { type: 'work_order', id: w.id } });
  }
  for (const a of unwrap<any[]>(alerts, 'alerts')) {
    out.push({
      type: a.level === 'out' ? 'out_of_stock' : 'low_stock',
      severity: a.level === 'out' ? 'high' : 'low',
      title: `${a.item?.name ?? 'Item'} ${a.level === 'out' ? 'out of stock' : 'low'}`,
      detail: a.item ? `${Number(a.item.on_hand)}/${Number(a.item.reorder_threshold)}` : null,
      outlet_id: a.outlet_id,
      at: a.created_at,
      link: { type: 'inventory_item', id: a.item?.id ?? a.id },
    });
  }
  for (const p of unwrap<any[]>(pays, 'payments')) {
    if (outletIds && !outletIds.includes(p.booking?.outlet_id)) continue;
    out.push({ type: 'failed_payment', severity: 'medium', title: `Payment failed · ${p.booking?.ref ?? ''}`, detail: p.failure_reason, outlet_id: p.booking?.outlet_id ?? null, at: p.updated_at, link: { type: 'payment', id: p.id } });
  }
  const sev = { high: 0, medium: 1, low: 2 };
  return out.sort((a, b) => sev[a.severity] - sev[b.severity] || (b.at ?? '').localeCompare(a.at ?? ''));
}

export interface ActivityItem {
  id: string;
  type: 'task_event' | 'payment_event' | 'loyalty' | 'inventory_alert';
  at: string;
  title: string;
  detail: string | null;
  outlet_id: string | null;
  link: { type: string; id: string } | null;
}

export async function computeActivity(outletIds: string[] | null, limit: number): Promise<ActivityItem[]> {
  const db = getSupabase();
  const [events, payEvents, ledger, alerts] = await Promise.all([
    db.from('task_events').select('id, event, from_status, to_status, reason, created_at, actor:profiles!task_events_actor_id_fkey(full_name), work_order:work_orders!inner(id, ref, outlet_id)').order('created_at', { ascending: false }).limit(limit * 2),
    db.from('payment_events').select('id, event_type, received_at, payment:payments!inner(id, amount_cents, booking:bookings(ref, outlet_id))').order('received_at', { ascending: false }).limit(limit),
    db.from('loyalty_ledger').select('id, delta, type, reference, description, created_at, customer:profiles!loyalty_ledger_customer_id_fkey(full_name)').order('created_at', { ascending: false }).limit(limit),
    db.from('inventory_alerts').select('id, level, created_at, outlet_id, item:inventory_items(id, name)').order('created_at', { ascending: false }).limit(limit),
  ]);
  const items: ActivityItem[] = [];
  const inScope = (oid: string | null | undefined) => !outletIds || (oid ? outletIds.includes(oid) : false);
  for (const e of ((events.data ?? []) as any[])) {
    if (!inScope(e.work_order?.outlet_id)) continue;
    const title = e.event === 'assigned' ? `${e.work_order?.ref} assigned` : e.event === 'override' ? `${e.work_order?.ref} override recorded` : e.event.startsWith('step') ? `${e.work_order?.ref} ${e.event.replace('_', ' ')}` : `${e.work_order?.ref} ${e.from_status ?? ''} → ${e.to_status ?? ''}`;
    items.push({ id: e.id, type: 'task_event', at: e.created_at, title, detail: [e.actor?.full_name, e.reason].filter(Boolean).join(' · ') || null, outlet_id: e.work_order?.outlet_id ?? null, link: { type: 'work_order', id: e.work_order?.id } });
  }
  for (const p of ((payEvents.data ?? []) as any[])) {
    if (!inScope(p.payment?.booking?.outlet_id)) continue;
    items.push({ id: p.id, type: 'payment_event', at: p.received_at, title: `${p.event_type} · ${p.payment?.booking?.ref ?? ''}`, detail: p.payment ? `R ${(Number(p.payment.amount_cents) / 100).toFixed(2)}` : null, outlet_id: p.payment?.booking?.outlet_id ?? null, link: p.payment ? { type: 'payment', id: p.payment.id } : null });
  }
  if (!outletIds) {
    for (const l of ((ledger.data ?? []) as any[])) {
      items.push({ id: l.id, type: 'loyalty', at: l.created_at, title: `${l.delta > 0 ? '+' : ''}${l.delta} pts ${l.type} · ${l.customer?.full_name ?? ''}`, detail: [l.reference, l.description].filter(Boolean).join(' · ') || null, outlet_id: null, link: null });
    }
  }
  for (const a of ((alerts.data ?? []) as any[])) {
    if (!inScope(a.outlet_id)) continue;
    items.push({ id: a.id, type: 'inventory_alert', at: a.created_at, title: `${a.item?.name ?? 'Item'} ${a.level === 'out' ? 'out of stock' : 'low stock'}`, detail: null, outlet_id: a.outlet_id, link: a.item ? { type: 'inventory_item', id: a.item.id } : null });
  }
  return items.sort((a, b) => b.at.localeCompare(a.at)).slice(0, limit);
}

// ---------------------------------------------------------------------------
// Report data sources (REP-001..007). The CSV exports and the summary endpoint
// read through the same fetchers so their totals reconcile (REP-005).
// ---------------------------------------------------------------------------

export type ReportName = 'bookings' | 'payments' | 'inventory' | 'staff_performance' | 'loyalty';
export const REPORTS: ReportName[] = ['bookings', 'payments', 'inventory', 'staff_performance', 'loyalty'];

export interface ReportRange {
  from: string;
  to: string;
  outletIds: string[] | null; // null = all
}

const inScopeOf = (outletIds: string[] | null) => (outletId: string | null | undefined) => !outletIds || (outletId ? outletIds.includes(outletId) : false);

/** Bookings whose slot starts inside the range (outlet-scoped in SQL). */
export async function fetchBookingRows(r: ReportRange): Promise<any[]> {
  const db = getSupabase();
  let q = db
    .from('bookings')
    .select('id, ref, status, slot_start, slot_end, outlet_id, service_id, customer_id, price_cents, discount_cents, total_cents, points_pending, created_at, outlet:outlets(name), service:services(name, category), customer:profiles!bookings_customer_id_fkey(full_name), vehicle:vehicles(registration_no)')
    .gte('slot_start', r.from)
    .lte('slot_start', r.to)
    .order('slot_start');
  if (r.outletIds) q = q.in('outlet_id', r.outletIds);
  return unwrap<any[]>(await q, 'bookings');
}

/**
 * Payments created inside the range, joined with booking ref/outlet/service,
 * customer name and tokenised method brand/last4 (never the token). Outlet
 * scope is applied on the booking's outlet after the fetch.
 */
export async function fetchPaymentRows(r: ReportRange, statuses?: string[]): Promise<any[]> {
  const db = getSupabase();
  let q = db
    .from('payments')
    .select('id, booking_id, quotation_id, customer_id, status, amount_cents, currency, receipt_no, provider, provider_ref, failure_reason, verified_at, created_at, updated_at, booking:bookings(ref, outlet_id, service_id, outlet:outlets(name)), customer:profiles!payments_customer_id_fkey(full_name), method:payment_methods(brand, last4)')
    .gte('created_at', r.from)
    .lte('created_at', r.to)
    .order('created_at');
  if (statuses?.length) q = q.in('status', statuses);
  const rows = unwrap<any[]>(await q, 'payments');
  const inScope = inScopeOf(r.outletIds);
  return rows.filter((p) => inScope(p.booking?.outlet_id));
}

export async function fetchInventoryRows(outletIds: string[] | null): Promise<any[]> {
  const db = getSupabase();
  let q = db.from('inventory_items').select('id, outlet_id, sku, name, unit, on_hand, reorder_threshold, pack_size, is_active, updated_at, outlet:outlets(name)').order('name');
  if (outletIds) q = q.in('outlet_id', outletIds);
  return unwrap<any[]>(await q, 'inventory');
}

/** Loyalty ledger rows in the range (platform-wide: the ledger has no outlet). */
export async function fetchLedgerRows(from: string, to: string): Promise<any[]> {
  const db = getSupabase();
  return unwrap<any[]>(
    await db.from('loyalty_ledger').select('id, delta, type, source_type, reference, description, created_at, expires_at, customer:profiles!loyalty_ledger_customer_id_fkey(id, full_name)').gte('created_at', from).lte('created_at', to).order('created_at'),
    'ledger',
  );
}

export function csvWithMetadata(meta: Record<string, unknown>, columns: string[], rows: Array<Record<string, unknown>>): string {
  const metaLines = Object.entries(meta).map(([k, v]) => [`# ${k}`, typeof v === 'string' ? v : JSON.stringify(v)]);
  const head = stringify(metaLines);
  const table = stringify(rows, { header: true, columns });
  return `${head}\n${table}`;
}

export const PAYMENT_CSV_COLUMNS = ['id', 'booking_ref', 'outlet', 'customer', 'status', 'amount_cents', 'currency', 'receipt_no', 'provider', 'provider_ref', 'method_brand', 'method_last4', 'verified_at', 'created_at', 'failure_reason'];

export async function buildReport(report: ReportName, auth: AuthContext, filters: { outlet_id?: string; from?: string; to?: string }, outletIds: string[] | null) {
  const scopeLabel = auth.role === 'admin' || auth.role === 'finance' ? (filters.outlet_id ? `outlet:${filters.outlet_id}` : 'all outlets') : `outlets:${(outletIds ?? []).join('|')}`;
  const meta = { generated_at: new Date().toISOString(), generated_by: auth.uid, role: auth.role, report, filters: { ...filters }, scope: scopeLabel };
  const from = filters.from ?? new Date(Date.now() - 30 * 86400_000).toISOString();
  const to = filters.to ?? new Date().toISOString();
  const range: ReportRange = { from, to, outletIds };

  switch (report) {
    case 'bookings': {
      const rows = await fetchBookingRows(range);
      const columns = ['ref', 'status', 'slot_start', 'slot_end', 'outlet', 'service', 'category', 'customer', 'registration_no', 'price_cents', 'discount_cents', 'total_cents', 'points_pending'];
      return csvWithMetadata(meta, columns, rows.map((b) => ({ ...b, outlet: b.outlet?.name, service: b.service?.name, category: b.service?.category, customer: b.customer?.full_name, registration_no: b.vehicle?.registration_no })));
    }
    case 'payments': {
      const rows = await fetchPaymentRows(range);
      return csvWithMetadata(meta, PAYMENT_CSV_COLUMNS, rows.map((p) => ({ ...p, booking_ref: p.booking?.ref, outlet: p.booking?.outlet?.name, customer: p.customer?.full_name, method_brand: p.method?.brand, method_last4: p.method?.last4 })));
    }
    case 'inventory': {
      const rows = await fetchInventoryRows(outletIds);
      const columns = ['sku', 'name', 'outlet', 'unit', 'on_hand', 'reorder_threshold', 'pack_size', 'is_active', 'updated_at'];
      return csvWithMetadata(meta, columns, rows.map((i) => ({ ...i, outlet: i.outlet?.name })));
    }
    case 'staff_performance': {
      const perf = await staffPerformance(outletIds, from, to);
      const columns = ['staff_id', 'name', 'role', 'tasks_completed', 'tasks_verified', 'avg_cycle_minutes', 'checklist_compliance_pct', 'points'];
      return csvWithMetadata(meta, columns, perf as unknown as Array<Record<string, unknown>>);
    }
    case 'loyalty': {
      const rows = await fetchLedgerRows(from, to);
      const columns = ['id', 'customer_id', 'customer', 'delta', 'type', 'source_type', 'reference', 'description', 'created_at', 'expires_at'];
      return csvWithMetadata(meta, columns, rows.map((l) => ({ ...l, customer_id: l.customer?.id, customer: l.customer?.full_name })));
    }
  }
}

// ---------------------------------------------------------------------------
// Admin payments list (ADM-061): finance-safe projection of the same rows the
// payments CSV exports — no provider tokens, idempotency keys or raw payloads.
// ---------------------------------------------------------------------------

export interface AdminPaymentRow {
  id: string;
  booking_id: string | null;
  booking_ref: string | null;
  outlet_id: string | null;
  outlet_name: string | null;
  customer_id: string;
  customer_name: string;
  provider: string;
  method_brand: string | null;
  method_last4: string | null;
  amount_cents: number;
  currency: string;
  status: string;
  receipt_no: string | null;
  failure_reason: string | null;
  verified_at: string | null;
  created_at: string;
}

export function toAdminPaymentRow(p: any): AdminPaymentRow {
  return {
    id: p.id,
    booking_id: p.booking_id ?? null,
    booking_ref: p.booking?.ref ?? null,
    outlet_id: p.booking?.outlet_id ?? null,
    outlet_name: p.booking?.outlet?.name ?? null,
    customer_id: p.customer_id,
    customer_name: p.customer?.full_name ?? '',
    provider: p.provider,
    method_brand: p.method?.brand ?? null,
    method_last4: p.method?.last4 ?? null,
    amount_cents: Number(p.amount_cents),
    currency: p.currency ?? 'ZAR',
    status: p.status,
    receipt_no: p.receipt_no ?? null,
    failure_reason: p.failure_reason ?? null,
    verified_at: p.verified_at ?? null,
    created_at: p.created_at,
  };
}

/** Newest first; offset pagination over the scoped set (outlet scope needs the booking join). */
export async function listAdminPayments(range: ReportRange, statuses: string[] | undefined, limit: number, offset: number): Promise<{ data: AdminPaymentRow[]; next_cursor: string | null }> {
  const rows = (await fetchPaymentRows(range, statuses)).sort((a, b) => String(b.created_at).localeCompare(String(a.created_at)));
  return pageResult(rows.slice(offset, offset + limit + 1).map(toAdminPaymentRow), limit, offset);
}

// ---------------------------------------------------------------------------
// Report summary (REP-005): financial + operational rollup over the same rows
// the CSV exports return for the same filters.
// ---------------------------------------------------------------------------

const pct = (num: number, den: number): number => (den > 0 ? Math.round((num / den) * 1000) / 10 : 0);
const round1 = (n: number): number => Math.round(n * 10) / 10;

export async function computeSummary(range: ReportRange) {
  const db = getSupabase();
  const scope = <T>(q: T): T => (range.outletIds ? (q as any).in('outlet_id', range.outletIds) : q);
  const [bookings, payments, inventory, ledger, quotations, workOrders, tasks, notifications, alerts, outlets, services] = await Promise.all([
    fetchBookingRows(range),
    fetchPaymentRows(range),
    fetchInventoryRows(range.outletIds),
    fetchLedgerRows(range.from, range.to),
    scope(db.from('quotations').select('id, status, outlet_id, created_at').gte('created_at', range.from).lte('created_at', range.to)),
    scope(db.from('work_orders').select('id, status, outlet_id, due_at, started_at, completed_at, verified_at').in('status', ['completed', 'verified']).gte('completed_at', range.from).lte('completed_at', range.to)),
    scope(db.from('tasks').select('id, work_order_id, status, started_at, completed_at, elapsed_seconds, outlet_id').in('status', ['completed', 'verified']).gte('completed_at', range.from).lte('completed_at', range.to)),
    db.from('notifications').select('id, status, channel').gte('created_at', range.from).lte('created_at', range.to),
    scope(db.from('inventory_alerts').select('id, level, outlet_id').neq('status', 'resolved')),
    db.from('outlets').select('id, name'),
    db.from('services').select('id, name, category'),
  ]);

  const outletRows = unwrap<Array<{ id: string; name: string }>>(outlets, 'outlets');
  const serviceRows = unwrap<Array<{ id: string; name: string; category: string }>>(services, 'services');
  const inScope = inScopeOf(range.outletIds);

  // --- financial (payments rows == payments CSV rows) ----------------------
  const successful = payments.filter((p) => p.status === 'successful');
  const revenue_cents = successful.reduce((a, p) => a + Number(p.amount_cents), 0);
  const refunds_cents = payments.filter((p) => p.status === 'refunded').reduce((a, p) => a + Number(p.amount_cents), 0);
  const byStatus = new Map<string, { count: number; amount_cents: number }>();
  for (const p of payments) {
    const cur = byStatus.get(p.status) ?? { count: 0, amount_cents: 0 };
    cur.count += 1;
    cur.amount_cents += Number(p.amount_cents);
    byStatus.set(p.status, cur);
  }
  const by_status = [...byStatus.entries()].map(([status, v]) => ({ status, ...v })).sort((a, b) => b.amount_cents - a.amount_cents);

  const revenueByOutlet = new Map<string, number>();
  const revenueByService = new Map<string, number>();
  for (const p of successful) {
    const oid = p.booking?.outlet_id;
    if (oid) revenueByOutlet.set(oid, (revenueByOutlet.get(oid) ?? 0) + Number(p.amount_cents));
    const sid = p.booking?.service_id;
    if (sid) revenueByService.set(sid, (revenueByService.get(sid) ?? 0) + Number(p.amount_cents));
  }
  const bookingsByOutlet = new Map<string, number>();
  const bookingsByService = new Map<string, number>();
  for (const b of bookings) {
    bookingsByOutlet.set(b.outlet_id, (bookingsByOutlet.get(b.outlet_id) ?? 0) + 1);
    bookingsByService.set(b.service_id, (bookingsByService.get(b.service_id) ?? 0) + 1);
  }
  const by_outlet = outletRows
    .filter((o) => inScope(o.id))
    .map((o) => ({ outlet_id: o.id, name: o.name, revenue_cents: revenueByOutlet.get(o.id) ?? 0, bookings: bookingsByOutlet.get(o.id) ?? 0 }))
    .sort((a, b) => b.revenue_cents - a.revenue_cents || b.bookings - a.bookings);
  const by_service = serviceRows
    .map((s) => ({ service_id: s.id, name: s.name, category: s.category, revenue_cents: revenueByService.get(s.id) ?? 0, count: bookingsByService.get(s.id) ?? 0 }))
    .filter((s) => s.count > 0 || s.revenue_cents > 0)
    .sort((a, b) => b.revenue_cents - a.revenue_cents || b.count - a.count);

  // --- operational (bookings rows == bookings CSV rows) --------------------
  const countStatus = (rows: any[], status: string) => rows.filter((r) => r.status === status).length;
  const quoteRows = unwrap<any[]>(quotations, 'quotations');
  const quoted = quoteRows.filter((q) => ['quoted', 'accepted', 'declined', 'expired', 'converted'].includes(q.status)).length;
  const accepted = quoteRows.filter((q) => ['accepted', 'converted'].includes(q.status)).length;

  const woRows = unwrap<any[]>(workOrders, 'work orders');
  const withDue = woRows.filter((w) => w.due_at && w.completed_at);
  const onTime = withDue.filter((w) => new Date(w.completed_at).getTime() <= new Date(w.due_at).getTime()).length;

  const taskRows = unwrap<any[]>(tasks, 'tasks');
  const cycles: number[] = [];
  for (const t of taskRows) {
    if (t.elapsed_seconds) cycles.push(t.elapsed_seconds / 60);
    else if (t.started_at && t.completed_at) cycles.push((new Date(t.completed_at).getTime() - new Date(t.started_at).getTime()) / 60000);
  }
  const woIds = [...new Set(taskRows.map((t) => t.work_order_id))];
  const results = woIds.length ? unwrap<any[]>(await db.from('checklist_step_results').select('work_order_id, status').in('work_order_id', woIds), 'results') : [];
  const nonCompliant = new Set(results.filter((r) => r.status === 'blocked' || r.status === 'skipped').map((r) => r.work_order_id));
  const compliant = woIds.filter((id) => !nonCompliant.has(id)).length;

  // --- loyalty / inventory / notifications --------------------------------
  const points_issued = ledger.filter((l) => Number(l.delta) > 0).reduce((a, l) => a + Number(l.delta), 0);
  const points_redeemed = ledger.filter((l) => l.type === 'redeem').reduce((a, l) => a + Math.abs(Number(l.delta)), 0);
  const points_expired = ledger.filter((l) => l.type === 'expire').reduce((a, l) => a + Math.abs(Number(l.delta)), 0);
  const activeItems = inventory.filter((i) => i.is_active !== false);
  const below = activeItems.filter((i) => Number(i.on_hand) <= Number(i.reorder_threshold));
  const alertRows = unwrap<any[]>(alerts, 'alerts');
  const noteRows = unwrap<any[]>(notifications, 'notifications');
  const delivered = noteRows.filter((n) => n.status === 'sent' || n.status === 'delivered').length;
  const suppressed = noteRows.filter((n) => n.status === 'suppressed').length;
  const failed = noteRows.filter((n) => n.status === 'failed').length;
  const attempted = noteRows.length - suppressed;

  return {
    range: { from: range.from, to: range.to, outlet_ids: range.outletIds },
    financial: {
      revenue_cents,
      refunds_cents,
      payments_total: payments.length,
      payments_successful: successful.length,
      payments_failed: countStatus(payments, 'failed'),
      avg_ticket_cents: successful.length ? Math.round(revenue_cents / successful.length) : 0,
      by_status,
      by_outlet,
      by_service,
    },
    operational: {
      bookings: bookings.length,
      created: bookings.length,
      pending: countStatus(bookings, 'pending'),
      confirmed: countStatus(bookings, 'confirmed'),
      in_service: countStatus(bookings, 'in_service'),
      completed: countStatus(bookings, 'completed'),
      cancelled: countStatus(bookings, 'cancelled'),
      work_orders_completed: woRows.length,
      on_time_pct: pct(onTime, withDue.length),
      avg_cycle_minutes: cycles.length ? round1(cycles.reduce((a, b) => a + b, 0) / cycles.length) : 0,
      checklist_compliance_pct: pct(compliant, woIds.length),
      quotes: {
        requested: quoteRows.length,
        quoted,
        accepted,
        declined: countStatus(quoteRows, 'declined'),
        expired: countStatus(quoteRows, 'expired'),
        converted: countStatus(quoteRows, 'converted'),
      },
    },
    loyalty: { points_issued, points_redeemed, points_expired, ledger_entries: ledger.length, outlet_scoped: false },
    inventory: {
      items_active: activeItems.length,
      items_below_threshold: below.length,
      items_out_of_stock: below.filter((i) => Number(i.on_hand) <= 0).length,
      open_alerts: alertRows.length,
    },
    notifications: {
      total: noteRows.length,
      delivered,
      failed,
      suppressed,
      delivery_rate_pct: pct(delivered, attempted),
      outlet_scoped: false,
    },
  };
}

export interface StaffPerformanceRow {
  staff_id: string;
  name: string;
  role: string;
  tasks_completed: number;
  tasks_verified: number;
  avg_cycle_minutes: number | null;
  checklist_compliance_pct: number | null;
  points: number;
}

export async function staffPerformance(outletIds: string[] | null, from: string, to: string): Promise<StaffPerformanceRow[]> {
  const db = getSupabase();
  const scope = <T>(q: T): T => (outletIds ? (q as any).in('outlet_id', outletIds) : q);
  const [tasks, pts, staff] = await Promise.all([
    scope(db.from('tasks').select('id, assignee_id, status, started_at, completed_at, elapsed_seconds, work_order_id, outlet_id').in('status', ['completed', 'verified']).gte('completed_at', from).lte('completed_at', to)),
    scope(db.from('staff_points_ledger').select('staff_id, delta').gte('created_at', from).lte('created_at', to)),
    outletIds ? db.from('staff_outlets').select('profile_id, profiles!inner(id, full_name, role)').in('outlet_id', outletIds) : db.from('profiles').select('id, full_name, role').neq('role', 'customer'),
  ]);
  const taskRows = unwrap<any[]>(tasks, 'tasks');
  const woIds = taskRows.map((t) => t.work_order_id);
  const results = woIds.length ? unwrap<any[]>(await db.from('checklist_step_results').select('work_order_id, status').in('work_order_id', woIds), 'results') : [];
  const blockedWo = new Set(results.filter((r) => r.status === 'blocked' || r.status === 'skipped').map((r) => r.work_order_id));
  const people = new Map<string, { name: string; role: string }>();
  for (const s of unwrap<any[]>(staff, 'staff')) {
    const p = s.profiles ?? s;
    if (p && p.role !== 'customer') people.set(p.id, { name: p.full_name, role: p.role });
  }
  const acc = new Map<string, { completed: number; verified: number; cycle: number[]; compliant: number }>();
  for (const t of taskRows) {
    if (!t.assignee_id) continue;
    const a = acc.get(t.assignee_id) ?? { completed: 0, verified: 0, cycle: [], compliant: 0 };
    a.completed++;
    if (t.status === 'verified') a.verified++;
    if (t.elapsed_seconds) a.cycle.push(t.elapsed_seconds / 60);
    else if (t.started_at && t.completed_at) a.cycle.push((new Date(t.completed_at).getTime() - new Date(t.started_at).getTime()) / 60000);
    if (!blockedWo.has(t.work_order_id)) a.compliant++;
    acc.set(t.assignee_id, a);
  }
  const points = new Map<string, number>();
  for (const p of unwrap<any[]>(pts, 'points')) points.set(p.staff_id, (points.get(p.staff_id) ?? 0) + Number(p.delta));
  return [...people.entries()]
    .map(([id, p]) => {
      const a = acc.get(id);
      return {
        staff_id: id,
        name: p.name,
        role: p.role,
        tasks_completed: a?.completed ?? 0,
        tasks_verified: a?.verified ?? 0,
        avg_cycle_minutes: a && a.cycle.length ? Math.round((a.cycle.reduce((x, y) => x + y, 0) / a.cycle.length) * 10) / 10 : null,
        checklist_compliance_pct: a && a.completed ? Math.round((a.compliant / a.completed) * 100) : null,
        points: points.get(id) ?? 0,
      };
    })
    .sort((a, b) => b.points - a.points || b.tasks_completed - a.tasks_completed);
}
