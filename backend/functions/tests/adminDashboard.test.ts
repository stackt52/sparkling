/**
 * Admin dashboard contract (apps/admin `HttpApi`): the work-order board, KPI
 * presets, exception / activity cards, normalised bookings, customer summaries,
 * staff performance, inventory decorations, outlet legal fields, template
 * publish flag, audit actor names, member rows and quotation names.
 */
import { createServer, type Server } from 'node:http';
import { afterAll, afterEach, beforeAll, beforeEach, describe, expect, it, vi } from 'vitest';
import { createApp } from '../src/app.js';
import { setFirebaseAuthForTests, setFirebaseMessagingForTests } from '../src/lib/firebase.js';
import { setSupabaseClient } from '../src/lib/supabase.js';
import { resetRateLimits } from '../src/middleware/rateLimit.js';
import { avgCycleMinutes, formatRandShort, initialsOf, periodRange } from '../src/services/admin.js';
import { invalidateFlags } from '../src/services/flags.js';
import { stockCapacity } from '../src/routes/inventory.js';
import { fakeSupabase, type FakeSupabase } from './helpers/fakeSupabase.js';

const NOW = '2026-09-14T10:00:00.000Z';
const OUTLET_A = 'a0000000-0000-4000-8000-000000000001';
const OUTLET_B = 'a0000000-0000-4000-8000-000000000002';
const SERVICE_1 = 'b0000000-0000-4000-8000-000000000001';
const SERVICE_2 = 'b0000000-0000-4000-8000-000000000002';
const VEH_1 = 'd0000000-0000-4000-8000-000000000001';
const VEH_2 = 'd0000000-0000-4000-8000-000000000002';
const BOOKING_1 = '10000000-0000-4000-8000-000000000001';
const BOOKING_2 = '10000000-0000-4000-8000-000000000002';
const WO_1 = '80000000-0000-4000-8000-000000000001';
const WO_2 = '80000000-0000-4000-8000-000000000002';
const WO_3 = '80000000-0000-4000-8000-000000000003';
const WO_4 = '80000000-0000-4000-8000-000000000004';
const TASK_1 = '90000000-0000-4000-8000-000000000001';
const TASK_2 = '90000000-0000-4000-8000-000000000002';
const TASK_3 = '90000000-0000-4000-8000-000000000003';
const TEMPLATE = 'c0000000-0000-4000-8000-000000000001';
const QUOTE_1 = '70000000-0000-4000-8000-000000000001';
const QUOTE_2 = '70000000-0000-4000-8000-000000000002';
const ITEM_WAX = 'e0000000-0000-4000-8000-000000000001';
const ITEM_TOWEL = 'e0000000-0000-4000-8000-000000000002';
const ITEM_CLOTH = 'e0000000-0000-4000-8000-000000000003';
const BADGE = 'f0000000-0000-4000-8000-000000000001';
const PLAN_GOLD = 'c1000000-0000-4000-8000-000000000001';
const GROUP_GOLD = 'c2000000-0000-4000-8000-000000000001';
const ENT_G1 = 'c3000000-0000-4000-8000-000000000001';
const MEM_1 = 'c4000000-0000-4000-8000-000000000001';

let server: Server;
let base: string;
let db: FakeSupabase;

beforeAll(async () => {
  server = createServer(createApp());
  await new Promise<void>((r) => server.listen(0, r));
  base = `http://127.0.0.1:${(server.address() as { port: number }).port}`;
  setFirebaseAuthForTests({
    verifyIdToken: async (token: string) => {
      const users: Record<string, string> = { admin: 'uid_admin', manager: 'uid_manager', finance: 'uid_finance', customer: 'cust_1', tech: 'tech_1' };
      if (users[token]) return { uid: users[token], email: `${token}@example.com` };
      throw new Error('bad token');
    },
    setCustomUserClaims: async () => undefined,
  } as any);
  setFirebaseMessagingForTests({ sendEachForMulticast: async ({ tokens }: { tokens: string[] }) => ({ successCount: tokens.length, failureCount: 0, responses: tokens.map(() => ({ success: true })) }) } as any);
});
afterAll(() => server.close());
afterEach(() => vi.useRealTimers());

beforeEach(() => {
  vi.useFakeTimers({ now: new Date(NOW), toFake: ['Date'] });
  db = fakeSupabase();
  const p = (id: string, role: string, full_name: string, extra: Record<string, unknown> = {}) => ({ id, role, full_name, email: `${id}@example.com`, phone: null, is_active: true, push_opt_in: true, whatsapp_opt_in: true, marketing_opt_in: false, ...extra });
  db.seed('profiles', [
    p('uid_admin', 'admin', 'Ada Admin'),
    p('uid_manager', 'manager', 'Musa Manager'),
    p('uid_finance', 'finance', 'Fikile Finance'),
    p('tech_1', 'technician', 'Pieter Marais'),
    p('cust_1', 'customer', 'Naledi Mokoena', { phone: '+27831112222', marketing_opt_in: true }),
    p('cust_2', 'customer', 'Sipho Dlamini', { phone: '+27821234567' }),
  ]);
  db.seed('staff_outlets', [{ profile_id: 'uid_manager', outlet_id: OUTLET_A, is_primary: true }, { profile_id: 'tech_1', outlet_id: OUTLET_A, is_primary: true }]);
  db.seed('staff_skills', [{ profile_id: 'tech_1', skill: 'wash' }]);
  db.seed('staff_availability', [{ profile_id: 'tech_1', status: 'available', capacity: 3 }]);
  db.seed('feature_flags', [{ key: 'whatsapp_enabled', enabled: false, description: 'WhatsApp sends' }, { key: 'auto_assignment', enabled: false }]);
  db.seed('outlets', [
    { id: OUTLET_A, code: 'SAN', name: 'Sparkling Sandton', timezone: 'Africa/Johannesburg', is_active: true, slot_minutes: 30, bay_count: 3 },
    { id: OUTLET_B, code: 'ROS', name: 'Sparkling Rosebank', timezone: 'Africa/Johannesburg', is_active: true, slot_minutes: 30, bay_count: 2 },
  ]);
  db.seed('services', [
    { id: SERVICE_1, code: 'FULL', name: 'Full Valet', category: 'car_wash', duration_minutes: 60, is_active: true, checklist_template_id: TEMPLATE, points_per_rand: 0.1 },
    { id: SERVICE_2, code: 'PANEL', name: 'Panel beating', category: 'auto_body', duration_minutes: 240, is_active: true, is_quote_based: true, pricing_mode: 'by_quote' },
  ]);
  db.seed('vehicles', [
    { id: VEH_1, customer_id: 'cust_1', registration_no: 'KL 45 MN GP', make: 'Toyota', model: 'Corolla', source: 'manual', disc_verified: false, is_active: true },
    { id: VEH_2, customer_id: 'cust_2', registration_no: 'CA 123 456', make: 'VW', model: 'Polo', source: 'manual', disc_verified: false, is_active: true },
  ]);
  db.seed('checklist_templates', [{ id: TEMPLATE, name: 'Valet', category: 'car_wash', version: 2, status: 'published', outlet_id: null, steps: [{ key: 'prewash', title: 'Pre-wash', type: 'confirm' }, { key: 'exterior', title: 'Exterior', type: 'confirm' }, { key: 'interior', title: 'Interior', type: 'confirm' }], created_by: 'uid_admin', created_at: '2026-01-01T00:00:00.000Z' }]);
  db.seed('bookings', [
    { id: BOOKING_1, ref: 'SPK-2026-0001', customer_id: 'cust_1', vehicle_id: VEH_1, outlet_id: OUTLET_A, service_id: SERVICE_1, status: 'in_service', slot_start: '2026-09-14T08:00:00.000Z', slot_end: '2026-09-14T09:00:00.000Z', price_cents: 15000, discount_cents: 0, total_cents: 15000, points_pending: 15, walk_in: true, created_by: 'tech_1', addon_service_ids: [], addons_cents: 0 },
    { id: BOOKING_2, ref: 'SPK-2026-0002', customer_id: 'cust_2', vehicle_id: VEH_2, outlet_id: OUTLET_B, service_id: SERVICE_1, status: 'completed', slot_start: '2026-09-14T07:00:00.000Z', slot_end: '2026-09-14T08:00:00.000Z', price_cents: 15000, discount_cents: 0, total_cents: 15000, points_pending: 15, walk_in: false, created_by: 'cust_2', addon_service_ids: [], addons_cents: 0 },
  ]);
  db.seed('quotations', [
    { id: QUOTE_1, ref: 'QT-2026-0001', customer_id: 'cust_2', vehicle_id: VEH_2, outlet_id: OUTLET_B, category: 'Dent', description: 'Rear door dent', status: 'accepted', amount_cents: 250000, line_items: [{ label: 'Dent', amount_cents: 250000 }], assessor_id: 'uid_manager', valid_until: '2026-10-01', quoted_at: '2026-09-14T09:00:00.000Z', created_at: '2026-09-14T08:30:00.000Z' },
    { id: QUOTE_2, ref: 'QT-2026-0002', customer_id: 'cust_1', vehicle_id: VEH_1, outlet_id: OUTLET_A, category: 'Scratch', description: 'Scratched bumper', status: 'requested', amount_cents: null, line_items: [], assessor_id: null, created_at: '2026-09-14T09:30:00.000Z' },
  ]);
  const wo = (id: string, ref: string, extra: Record<string, unknown>) => ({ id, ref, vehicle_id: VEH_1, customer_id: 'cust_1', service_id: SERVICE_1, checklist_template_id: TEMPLATE, template_version: 2, bay: null, assignee_id: null, eta_at: null, started_at: null, blocked_reason: null, completed_at: null, verified_at: null, verified_by: null, due_at: null, created_at: '2026-09-14T08:00:00.000Z', updated_at: '2026-09-14T08:00:00.000Z', ...extra });
  db.seed('work_orders', [
    wo(WO_1, 'WO-2026-0001', { outlet_id: OUTLET_A, booking_id: BOOKING_1, quotation_id: null, status: 'in_progress', priority: 1, bay: 'Bay 2', assignee_id: 'tech_1', started_at: '2026-09-14T08:05:00.000Z', eta_at: '2026-09-14T09:00:00.000Z', due_at: '2026-09-15T09:00:00.000Z' }),
    wo(WO_2, 'WO-2026-0002', { outlet_id: OUTLET_B, booking_id: null, quotation_id: QUOTE_1, vehicle_id: VEH_2, customer_id: 'cust_2', service_id: SERVICE_2, checklist_template_id: null, status: 'blocked', priority: 2, blocked_reason: 'Waiting for paint', updated_at: '2026-09-14T09:40:00.000Z' }),
    wo(WO_3, 'WO-2026-0003', { outlet_id: OUTLET_A, booking_id: null, quotation_id: null, status: 'verified', priority: 3, assignee_id: 'tech_1', started_at: '2026-09-14T06:00:00.000Z', completed_at: '2026-09-14T06:30:00.000Z', verified_at: '2026-09-14T06:35:00.000Z', due_at: '2026-09-14T07:00:00.000Z', updated_at: '2026-09-14T06:35:00.000Z' }),
    wo(WO_4, 'WO-2026-0004', { outlet_id: OUTLET_A, booking_id: null, quotation_id: null, status: 'verified', priority: 2, completed_at: '2026-09-04T06:30:00.000Z', verified_at: '2026-09-04T06:35:00.000Z', created_at: '2026-09-04T06:00:00.000Z', updated_at: '2026-09-04T06:35:00.000Z' }),
  ]);
  db.seed('tasks', [
    { id: TASK_1, work_order_id: WO_1, outlet_id: OUTLET_A, title: 'Full Valet · KL 45 MN GP', seq: 1, assignee_id: 'tech_1', status: 'in_progress', priority: 1, started_at: '2026-09-14T08:05:00.000Z', elapsed_seconds: 0 },
    { id: TASK_2, work_order_id: WO_2, outlet_id: OUTLET_B, title: 'Panel beating', seq: 1, assignee_id: null, status: 'blocked', priority: 2, elapsed_seconds: 0 },
    { id: TASK_3, work_order_id: WO_3, outlet_id: OUTLET_A, title: 'Full Valet', seq: 1, assignee_id: 'tech_1', status: 'verified', priority: 3, started_at: '2026-09-14T06:00:00.000Z', completed_at: '2026-09-14T06:30:00.000Z', elapsed_seconds: 1800 },
  ]);
  db.seed('task_events', [
    { task_id: TASK_1, work_order_id: WO_1, actor_id: 'uid_manager', event: 'assigned', from_status: 'queued', to_status: 'assigned', reason: 'Skill match', metadata: {}, created_at: '2026-09-14T08:01:00.000Z' },
    { task_id: TASK_1, work_order_id: WO_1, actor_id: 'tech_1', event: 'transition', from_status: 'assigned', to_status: 'in_progress', reason: null, metadata: {}, created_at: '2026-09-14T08:05:00.000Z' },
  ]);
  db.seed('checklist_step_results', [
    { work_order_id: WO_1, step_key: 'prewash', status: 'done' },
    { work_order_id: WO_1, step_key: 'exterior', status: 'done' },
    { work_order_id: WO_1, step_key: 'interior', status: 'pending' },
    { work_order_id: WO_3, step_key: 'prewash', status: 'done' },
  ]);
  db.seed('payments', [
    { id: '60000000-0000-4000-8000-000000000001', booking_id: BOOKING_1, customer_id: 'cust_1', provider: 'pos', method: 'cash', amount_cents: 15000, currency: 'ZAR', status: 'successful', receipt_no: 'RCP-70001', idempotency_key: 'k1', verified_at: '2026-09-14T08:10:00.000Z', created_at: '2026-09-14T08:10:00.000Z', updated_at: '2026-09-14T08:10:00.000Z' },
    { id: '60000000-0000-4000-8000-000000000002', booking_id: BOOKING_2, customer_id: 'cust_2', provider: 'sandbox', amount_cents: 15000, currency: 'ZAR', status: 'failed', receipt_no: null, idempotency_key: 'k2', failure_reason: 'card_declined', created_at: '2026-09-14T07:30:00.000Z', updated_at: '2026-09-14T07:30:00.000Z' },
  ]);
  db.seed('inventory_items', [
    { id: ITEM_WAX, outlet_id: OUTLET_A, sku: 'WAX', name: 'Wax', unit: 'L', on_hand: 2, reorder_threshold: 5, pack_size: 4, is_active: true },
    { id: ITEM_TOWEL, outlet_id: OUTLET_B, sku: 'TOWEL', name: 'Towel', unit: 'unit', on_hand: 0, reorder_threshold: 10, pack_size: null, is_active: true },
    { id: ITEM_CLOTH, outlet_id: OUTLET_A, sku: 'CLOTH', name: 'Cloth', unit: 'unit', on_hand: 40, reorder_threshold: 10, pack_size: 10, is_active: true },
  ]);
  db.seed('inventory_alerts', [
    { item_id: ITEM_WAX, outlet_id: OUTLET_A, level: 'low', status: 'open', created_at: '2026-09-13T10:00:00.000Z' },
    { item_id: ITEM_TOWEL, outlet_id: OUTLET_B, level: 'out', status: 'open', created_at: '2026-09-14T09:00:00.000Z' },
  ]);
  db.seed('inventory_movements', [{ item_id: ITEM_TOWEL, delta: -2, reason: 'usage', work_order_id: WO_2, client_op_id: 'mv-1', created_at: '2026-09-14T09:30:00.000Z' }]);
  db.seed('badges', [{ id: BADGE, code: 'speed_demon', name: 'Speed demon', icon: 'bolt', colour: '#FFB300' }]);
  db.seed('staff_badges', [{ staff_id: 'tech_1', badge_id: BADGE, awarded_at: '2026-09-01T00:00:00.000Z' }]);
  db.seed('staff_points_ledger', [
    { staff_id: 'tech_1', outlet_id: OUTLET_A, delta: 25, event_type: 'task_completed', idempotency_key: 'sp1', created_at: '2026-09-14T06:35:00.000Z' },
    { staff_id: 'tech_1', outlet_id: OUTLET_A, delta: 40, event_type: 'task_completed', idempotency_key: 'sp2', created_at: '2026-08-25T06:35:00.000Z' },
  ]);
  db.seed('loyalty_accounts', [{ customer_id: 'cust_1', tier: 'gold', balance_points: 120, lifetime_points: 400 }]);
  db.seed('loyalty_ledger', [{ customer_id: 'cust_1', delta: 15, type: 'earn', idempotency_key: 'l1', created_at: '2026-09-14T06:40:00.000Z' }]);
  db.seed('audit_events', [{ actor_id: 'uid_manager', actor_role: 'manager', action: 'task.assign', entity_type: 'task', entity_id: TASK_1, outlet_id: OUTLET_A, outcome: 'ok', created_at: '2026-09-14T08:01:00.000Z' }]);
  db.seed('membership_plans', [{ id: PLAN_GOLD, code: 'gold', tier: 'gold', name: 'Gold', monthly_fee_cents: 29500, discount_pct: '10.00', discount_scope: 'other_services', sort_order: 10, is_active: true }]);
  db.seed('membership_plan_groups', [{ id: GROUP_GOLD, plan_id: PLAN_GOLD, code: 'washes', name: 'Monthly washes', selection: 'choose_one', sort_order: 10 }]);
  db.seed('membership_plan_entitlements', [{ id: ENT_G1, group_id: GROUP_GOLD, code: 'G1', label: '4 × Full Valet', quantity: 4, period: 'month', sort_order: 10 }]);
  db.seed('membership_entitlement_services', [{ entitlement_id: ENT_G1, service_id: SERVICE_1, is_primary: true }]);
  db.seed('memberships', [{ id: MEM_1, ref: 'MEM-2026-0001', customer_id: 'cust_1', plan_id: PLAN_GOLD, status: 'active', started_at: '2026-06-10T09:00:00.000Z', current_period_start: '2026-09-10T09:00:00.000Z', current_period_end: '2026-10-10T09:00:00.000Z', cancel_at_period_end: false, next_plan_id: null, payment_method: 'cash', client_op_id: 'mem-1', created_by: 'tech_1', created_at: '2026-06-10T09:00:00.000Z' }]);
  db.seed('membership_selections', [{ membership_id: MEM_1, group_id: GROUP_GOLD, entitlement_id: ENT_G1 }]);
  db.seed('membership_usage', [{ membership_id: MEM_1, entitlement_id: ENT_G1, booking_id: BOOKING_1, quantity: 1, period_start: '2026-09-10T09:00:00.000Z', period_end: '2026-10-10T09:00:00.000Z', idempotency_key: 'use-1', created_by: null }]);
  setSupabaseClient(db as any);
  invalidateFlags();
  resetRateLimits();
});

async function call(path: string, token: string, init: RequestInit = {}) {
  const res = await fetch(`${base}${path}`, { ...init, headers: { Authorization: `Bearer ${token}`, 'Content-Type': 'application/json', ...(init.headers ?? {}) } });
  const text = await res.text();
  let body: any = text;
  try { body = JSON.parse(text); } catch { /* text */ }
  return { status: res.status, body };
}
const get = (path: string, token: string) => call(path, token);
const send = (method: string, path: string, token: string, body: unknown) => call(path, token, { method, body: JSON.stringify(body) });

describe('helpers', () => {
  it('derives calendar preset ranges, initials, cycle averages and rand labels', () => {
    expect(periodRange('today', new Date(NOW))).toEqual({ from: '2026-09-14T00:00:00.000Z', to: NOW });
    expect(periodRange('week', new Date(NOW)).from).toBe('2026-09-14T00:00:00.000Z'); // 14 Sep 2026 is a Monday
    expect(periodRange('week', new Date('2026-09-16T12:00:00.000Z')).from).toBe('2026-09-14T00:00:00.000Z');
    expect(periodRange('month', new Date(NOW)).from).toBe('2026-09-01T00:00:00.000Z');
    expect(initialsOf('Pieter van der Merwe')).toBe('PV');
    expect(avgCycleMinutes([{ elapsed_seconds: 1800 }, { started_at: '2026-09-14T06:00:00.000Z', completed_at: '2026-09-14T06:40:00.000Z' }])).toBe(35);
    expect(avgCycleMinutes([])).toBeNull();
    expect(formatRandShort(1234567)).toBe('R 12 346');
    expect(stockCapacity({ on_hand: 2, reorder_threshold: 5, pack_size: 4 })).toBe(21);
    expect(stockCapacity({ on_hand: 100, reorder_threshold: 5, pack_size: null })).toBe(100);
  });
});

describe('GET /admin/work-orders', () => {
  it('returns the board shape: names, refs, progress, task id and audit trail', async () => {
    const r = await get('/v1/admin/work-orders', 'admin');
    expect(r.status).toBe(200);
    expect(r.body.data.map((w: any) => w.ref)).toEqual(['WO-2026-0001', 'WO-2026-0002', 'WO-2026-0003']); // WO-4 finished 10 days ago
    const w1 = r.body.data[0];
    expect(w1).toMatchObject({
      id: WO_1,
      outlet: { id: OUTLET_A, name: 'Sparkling Sandton' },
      booking_ref: 'SPK-2026-0001',
      quotation_ref: null,
      customer_name: 'Naledi Mokoena',
      vehicle: { registration_no: 'KL 45 MN GP', make: 'Toyota', model: 'Corolla' },
      service: { name: 'Full Valet', category: 'car_wash' },
      status: 'in_progress',
      priority: 1,
      bay: 'Bay 2',
      assignee_id: 'tech_1',
      assignee_name: 'Pieter Marais',
      steps_done: 2,
      step_count: 3,
      progress_pct: 67,
      task_id: TASK_1,
      task_status: 'in_progress',
    });
    expect(w1.events).toHaveLength(2);
    expect(w1.events[0]).toMatchObject({ event: 'assigned', actor_name: 'Musa Manager', from_status: 'queued', to_status: 'assigned', reason: 'Skill match' });
    const w2 = r.body.data[1];
    expect(w2).toMatchObject({ quotation_ref: 'QT-2026-0001', booking_ref: null, customer_name: 'Sipho Dlamini', blocked_reason: 'Waiting for paint', step_count: 0, steps_done: 0, task_id: TASK_2 });
  });

  it('scopes managers to their outlets, honours status filters and roles', async () => {
    const mine = await get('/v1/admin/work-orders', 'manager');
    expect(mine.body.data.map((w: any) => w.ref)).toEqual(['WO-2026-0001', 'WO-2026-0003']);
    const verified = await get('/v1/admin/work-orders?status=verified', 'admin');
    expect(verified.body.data.map((w: any) => w.ref).sort()).toEqual(['WO-2026-0003', 'WO-2026-0004']);
    expect((await get('/v1/admin/work-orders?status=bogus', 'admin')).status).toBe(400);
    expect((await get('/v1/admin/work-orders', 'finance')).status).toBe(200);
    expect((await get('/v1/admin/work-orders', 'customer')).status).toBe(403);
    expect((await get(`/v1/admin/work-orders?outlet_id=${OUTLET_B}`, 'manager')).status).toBe(403);
  });

  it('serves a single work order with the same shape and outlet scope', async () => {
    const r = await get(`/v1/admin/work-orders/${WO_2}`, 'admin');
    expect(r.status).toBe(200);
    expect(r.body.work_order).toMatchObject({ ref: 'WO-2026-0002', customer_name: 'Sipho Dlamini', outlet: { name: 'Sparkling Rosebank' } });
    expect((await get(`/v1/admin/work-orders/${WO_2}`, 'manager')).status).toBe(403);
    expect((await get('/v1/admin/work-orders/80000000-0000-4000-8000-0000000000ff', 'admin')).status).toBe(404);
  });
});

describe('GET /admin/kpis', () => {
  it('accepts the dashboard period presets and returns the card fields', async () => {
    const r = await get('/v1/admin/kpis?period=today', 'finance');
    expect(r.status).toBe(200);
    expect(r.body).toMatchObject({
      period: 'today',
      range: { from: '2026-09-14T00:00:00.000Z', to: NOW },
      revenue_cents: 15000,
      revenue_compare_label: 'vs R 0 yesterday',
      bookings_count: 2,
      bookings_completed: 1,
      bookings_in_service: 1,
      on_time_pct: 100,
      active_work_orders: 2,
      completed_today: 1,
      avg_cycle_minutes: 30,
      quotes_total: 2,
      quotes_accepted: 1,
      exceptions_count: 4,
      exceptions_breakdown: { blocked: 1, overdue: 0, low_stock: 2, failed_payments: 1 },
      services_count: 2,
      outlets_count: 2,
      active_members: 1,
      membership_mrr_cents: 29500,
    });
    expect(typeof r.body.cycle_delta_minutes).toBe('number');
    expect(r.body.bookings_by_hour.every((h: any) => typeof h.future === 'boolean' && typeof h.hour === 'number')).toBe(true);
    expect(r.body.bookings_by_hour.reduce((n: number, h: any) => n + h.car_wash + h.auto_body, 0)).toBe(2);
    expect(r.body.top_staff[0]).toMatchObject({ staff_id: 'tech_1', name: 'Pieter Marais', initials: 'PM', points: 25, rank: 1, tier: 'gold' });
    expect(r.body.revenue_by_outlet.map((o: any) => o.name)).toEqual(['Sparkling Sandton', 'Sparkling Rosebank']);
  });

  it('still takes explicit from/to and rejects bad presets or ranges', async () => {
    const r = await get('/v1/admin/kpis?from=2026-09-01T00:00:00Z&to=2026-09-14T00:00:00Z', 'admin');
    expect(r.status).toBe(200);
    expect(r.body.period).toBe('custom');
    expect((await get('/v1/admin/kpis?period=year', 'admin')).status).toBe(400);
    expect((await get('/v1/admin/kpis?from=2026-09-14T00:00:00Z&to=2026-09-01T00:00:00Z', 'admin')).status).toBe(400);
  });
});

describe('GET /admin/exceptions and /admin/activity', () => {
  it('returns card rows with id, kind, severity tone, subtitle and icon (finance may read)', async () => {
    const r = await get('/v1/admin/exceptions', 'finance');
    expect(r.status).toBe(200);
    const byKind = Object.fromEntries(r.body.data.map((e: any) => [e.kind, e]));
    expect(Object.keys(byKind).sort()).toEqual(['blocked', 'failed_payment', 'low_stock', 'out_of_stock']);
    expect(byKind.blocked).toMatchObject({ id: `blocked:${WO_2}`, type: 'blocked', severity: 'error', priority: 'high', title: 'WO-2026-0002 blocked', subtitle: 'Waiting for paint', icon: 'block', link: { type: 'work_order', id: WO_2 }, created_at: '2026-09-14T09:40:00.000Z' });
    expect(byKind.low_stock).toMatchObject({ severity: 'warning', icon: 'inventory_2', link: { type: 'inventory_item', id: ITEM_WAX } });
    expect(byKind.out_of_stock).toMatchObject({ severity: 'error', link: { type: 'inventory_item', id: ITEM_TOWEL } });
    expect(byKind.failed_payment).toMatchObject({ severity: 'warning', icon: 'credit_card_off', subtitle: 'R 150 · card_declined' });
    expect(r.body.data[0].severity).toBe('error');
    const scoped = await get('/v1/admin/exceptions', 'manager');
    expect(scoped.body.data.map((e: any) => e.kind)).toEqual(['low_stock']);
  });

  it('decorates the live feed with kind, subtitle, icon and tone', async () => {
    const r = await get('/v1/admin/activity?limit=10', 'finance');
    expect(r.status).toBe(200);
    for (const a of r.body.data) {
      expect(a).toMatchObject({ id: expect.any(String), at: expect.any(String), title: expect.any(String), subtitle: expect.any(String), icon: expect.any(String) });
      expect(['completed', 'payment', 'quote', 'stock', 'loyalty', 'assigned', 'blocked']).toContain(a.kind);
      expect(['success', 'primary', 'warning', 'error', 'neutral']).toContain(a.tone);
    }
    const kinds = r.body.data.map((a: any) => a.kind);
    expect(kinds).toContain('assigned');
    expect(kinds).toContain('stock');
    expect(kinds).toContain('loyalty');
    expect(r.body.data.find((a: any) => a.type === 'inventory_alert' && a.link?.id === ITEM_TOWEL)?.tone).toBe('error');
  });
});

describe('GET /admin/bookings', () => {
  it('returns one work_order summary, the latest payment and the walk-in creator per booking', async () => {
    const r = await get('/v1/admin/bookings?date=2026-09-14', 'admin');
    expect(r.status).toBe(200);
    expect(r.body.data).toHaveLength(2);
    const b1 = r.body.data.find((b: any) => b.id === BOOKING_1);
    expect(b1.work_order).toMatchObject({ id: WO_1, ref: 'WO-2026-0001', status: 'in_progress', stage: 3, stage_count: 3, progress_pct: 67, bay: 'Bay 2', assignee_id: 'tech_1' });
    expect(b1.payment).toMatchObject({ status: 'successful', receipt_no: 'RCP-70001', amount_cents: 15000, method: 'cash' });
    expect(b1).toMatchObject({ walk_in: true, created_by_name: 'Pieter Marais', price_label: 'R 150' });
    const b2 = r.body.data.find((b: any) => b.id === BOOKING_2);
    expect(b2.work_order).toBeNull();
    expect(b2.payment).toMatchObject({ status: 'failed' });
    expect(b2.created_by_name).toBeNull();
  });

  it('searches by ref, customer name or number plate and filters by status', async () => {
    expect((await get('/v1/admin/bookings?search=KL%2045', 'admin')).body.data.map((b: any) => b.ref)).toEqual(['SPK-2026-0001']);
    expect((await get('/v1/admin/bookings?search=Sipho', 'admin')).body.data.map((b: any) => b.ref)).toEqual(['SPK-2026-0002']);
    expect((await get('/v1/admin/bookings?search=0002', 'admin')).body.data.map((b: any) => b.ref)).toEqual(['SPK-2026-0002']);
    expect((await get('/v1/admin/bookings?status=completed', 'admin')).body.data.map((b: any) => b.ref)).toEqual(['SPK-2026-0002']);
    expect((await get('/v1/admin/bookings', 'manager')).body.data.map((b: any) => b.ref)).toEqual(['SPK-2026-0001']);
  });
});

describe('GET /admin/customers', () => {
  it('lists customers with vehicle/booking counts and the loyalty + plan summary; plate search works', async () => {
    const r = await get('/v1/admin/customers', 'finance');
    expect(r.status).toBe(200);
    const naledi = r.body.data.find((c: any) => c.id === 'cust_1');
    expect(naledi).toMatchObject({ full_name: 'Naledi Mokoena', vehicle_count: 1, booking_count: 1, whatsapp_opt_in: true, marketing_opt_in: true });
    expect(naledi.loyalty).toMatchObject({ tier: 'gold', balance_points: 120, lifetime_points: 400, plan_code: 'gold', plan_name: 'Gold', included_remaining: 3 });
    expect(r.body.data.find((c: any) => c.id === 'cust_2').loyalty).toBeNull();
    expect((await get('/v1/admin/customers?search=KL%2045', 'admin')).body.data.map((c: any) => c.id)).toEqual(['cust_1']);
    expect((await get('/v1/admin/customers?search=sipho', 'admin')).body.data.map((c: any) => c.id)).toEqual(['cust_2']);
    expect(db.rows('audit_events').some((a) => a.action === 'customer.search')).toBe(true);
  });

  it('returns the 360 envelope with counts, loyalty and membership', async () => {
    const r = await get('/v1/admin/customers/cust_1', 'manager');
    expect(r.status).toBe(200);
    expect(r.body.customer).toMatchObject({ id: 'cust_1', full_name: 'Naledi Mokoena' });
    expect(r.body).toMatchObject({ vehicle_count: 1, booking_count: 1 });
    expect(r.body.loyalty).toMatchObject({ tier: 'gold', plan_code: 'gold', included_remaining: 3 });
    expect(r.body.vehicles).toHaveLength(1);
    expect(r.body.bookings).toHaveLength(1);
    expect(r.body.membership.plan.code).toBe('gold');
    expect(r.body.membership.allowances[0]).toMatchObject({ entitlement_code: 'G1', used: 1, remaining: 3 });
    expect((await get('/v1/admin/customers/nobody', 'admin')).status).toBe(404);
  });
});

describe('GET /admin/staff/performance', () => {
  it('accepts period=today and returns rank, period points, lifetime points, outlet and badges', async () => {
    const r = await get('/v1/admin/staff/performance?period=today', 'admin');
    expect(r.status).toBe(200);
    expect(r.body.from).toBe('2026-09-14T00:00:00.000Z');
    const tech = r.body.data.find((s: any) => s.staff_id === 'tech_1');
    expect(tech).toMatchObject({ name: 'Pieter Marais', outlet_name: 'Sparkling Sandton', tasks_completed: 1, tasks_verified: 1, avg_cycle_minutes: 30, checklist_compliance_pct: 100, points: 65, points_period: 25, rank: 1, delta: 0 });
    expect(tech.badges).toEqual([{ code: 'speed_demon', name: 'Speed demon', icon: 'bolt', colour: '#FFB300', earned_at: '2026-09-01T00:00:00.000Z' }]);
    expect(r.body.data.map((s: any) => s.rank)).toEqual([1, 2, 3, 4]);
    expect((await get('/v1/admin/staff/performance?period=decade', 'admin')).status).toBe(400);
  });
});

describe('GET /admin/inventory', () => {
  it('decorates items with outlet_name, capacity and blocking work orders and parses alerts_first=false', async () => {
    const first = await get('/v1/admin/inventory', 'finance');
    expect(first.status).toBe(200);
    expect(first.body.data.map((i: any) => i.name)).toEqual(['Towel', 'Wax', 'Cloth']);
    const towel = first.body.data[0];
    expect(towel).toMatchObject({ outlet_name: 'Sparkling Rosebank', capacity: 40, blocking_work_orders: 1, alert: { level: 'out', status: 'open' } });
    expect(first.body.data[1]).toMatchObject({ name: 'Wax', capacity: 21, blocking_work_orders: 0 });
    const byName = await get('/v1/admin/inventory?alerts_first=false', 'admin');
    expect(byName.body.data.map((i: any) => i.name)).toEqual(['Cloth', 'Towel', 'Wax']);
    expect((await get(`/v1/admin/inventory?outlet_id=${OUTLET_A}`, 'manager')).body.data.map((i: any) => i.name)).toEqual(['Wax', 'Cloth']);
  });
});

describe('outlets, templates, audit, memberships, quotations', () => {
  it('stores the legal / banking identity and treats blank e-mail as null', async () => {
    const created = await send('POST', '/v1/admin/outlets', 'admin', { code: 'pta', name: 'Sparkling Pretoria', email: '', phone: '', legal_name: 'Sparkling PTA (Pty) Ltd', vat_number: '4123456789', bank_details: { financial_institution: 'FNB', account_number: '62012345678', branch_code: '' } });
    expect(created.status).toBe(201);
    expect(created.body.outlet).toMatchObject({ code: 'PTA', email: null, phone: null, legal_name: 'Sparkling PTA (Pty) Ltd', vat_number: '4123456789', bank_details: { financial_institution: 'FNB', account_number: '62012345678', branch_code: null } });
    const patched = await send('PATCH', `/v1/admin/outlets/${created.body.outlet.id}`, 'admin', { trading_as: 'Sparkling Pretoria', email: 'pta@sparkling.co.za' });
    expect(patched.status).toBe(200);
    expect(patched.body.outlet).toMatchObject({ trading_as: 'Sparkling Pretoria', email: 'pta@sparkling.co.za', legal_name: 'Sparkling PTA (Pty) Ltd' });
    expect((await send('POST', '/v1/admin/outlets', 'admin', { code: 'BAD', name: 'Bad mail', email: 'nope' })).status).toBe(400);
  });

  it('honours the publish flag when versioning a template', async () => {
    const steps = [{ key: 'prewash', title: 'Pre-wash', type: 'confirm', required: true }];
    const draft = await send('PUT', `/v1/admin/templates/${TEMPLATE}`, 'admin', { name: 'Valet', category: 'car_wash', steps, publish: false });
    expect(draft.status).toBe(201);
    expect(draft.body.template).toMatchObject({ status: 'draft', version: 3 });
    expect(db.rows('checklist_templates').find((t) => t.id === TEMPLATE)?.status).toBe('published');
    const published = await send('PUT', `/v1/admin/templates/${TEMPLATE}`, 'admin', { name: 'Valet', category: 'car_wash', steps, publish: true });
    expect(published.body.template).toMatchObject({ status: 'published', version: 4 });
    expect(db.rows('checklist_templates').find((t) => t.id === TEMPLATE)?.status).toBe('archived');
    expect(db.rows('services').find((s) => s.id === SERVICE_1)?.checklist_template_id).toBe(published.body.template.id);
  });

  it('adds actor names to audit rows; finance reads everything, managers only their outlets', async () => {
    const r = await get('/v1/admin/audit', 'finance');
    expect(r.status).toBe(200);
    expect(r.body.data[0]).toMatchObject({ action: 'task.assign', actor_id: 'uid_manager', actor_name: 'Musa Manager', actor_role: 'manager' });
    const scoped = await get('/v1/admin/audit?entity_type=task', 'manager');
    expect(scoped.body.data).toHaveLength(1);
    expect((await get('/v1/admin/audit?actor_id=nobody', 'admin')).body.data).toHaveLength(0);
  });

  it('member rows carry selections and monthly used / remaining', async () => {
    const r = await get('/v1/admin/memberships', 'finance');
    expect(r.status).toBe(200);
    expect(r.body.data).toHaveLength(1);
    expect(r.body.data[0]).toMatchObject({ membership: { id: MEM_1, ref: 'MEM-2026-0001' }, customer: { id: 'cust_1', full_name: 'Naledi Mokoena' }, plan: { code: 'gold', tier: 'gold', monthly_fee_cents: 29500 }, selections: { washes: 'G1' }, used: 1, remaining: 3, open_invoice: null });
  });

  it('presents quotations with customer / assessor names and the work order ref', async () => {
    const r = await get(`/v1/quotations/${QUOTE_1}`, 'admin');
    expect(r.status).toBe(200);
    expect(r.body).toMatchObject({ ref: 'QT-2026-0001', customer_name: 'Sipho Dlamini', assessor_name: 'Musa Manager', work_order_ref: 'WO-2026-0002', work_order: { id: WO_2, ref: 'WO-2026-0002', status: 'blocked' } });
    expect(r.body.items).toEqual([{ label: 'Dent', amount_cents: 250000 }]);
    const list = await get('/v1/quotations?limit=200', 'admin');
    expect(list.body.data).toHaveLength(2);
    expect(list.body.data[0]).toHaveProperty('customer_name');
    expect(list.body.data[0]).toHaveProperty('assessor_name');
  });

  it('quoting stores items_note and answers with the presented quotation', async () => {
    const r = await send('POST', `/v1/quotations/${QUOTE_2}/quote`, 'manager', { amount_cents: 120000, line_items: [{ label: 'Bumper scratch', amount_cents: 120000 }], valid_until: '2026-10-01', items_note: 'Courtesy wash included' });
    expect(r.status).toBe(200);
    expect(r.body.quotation).toMatchObject({ status: 'quoted', amount_cents: 120000, items_note: 'Courtesy wash included', customer_name: 'Naledi Mokoena', assessor_name: 'Musa Manager', work_order_ref: null });
    expect(db.rows('quotations').find((q) => q.id === QUOTE_2)?.items_note).toBe('Courtesy wash included');
  });
});
