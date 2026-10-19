/**
 * Pay at check-in or on collection (migration 0023, `bookings.pay_at`).
 *
 * A counter booking (`payment_method: 'cash'`, flag `cash_on_collection`) also says when the
 * customer wants to pay: at the counter when the car is dropped off (`checkin`, before the wash)
 * or when it is collected (`collection`, after the wash — the default). Online bookings store
 * `booking`; staff walk-ins are paid as they are checked in. The value travels on every booking
 * shape, the task / work-order booking expansions and the admin work-order rows.
 */
import { createServer, type Server } from 'node:http';
import { afterAll, afterEach, beforeAll, beforeEach, describe, expect, it, vi } from 'vitest';
import { createApp } from '../src/app.js';
import { setFirebaseAuthForTests, setFirebaseMessagingForTests } from '../src/lib/firebase.js';
import { setSupabaseClient } from '../src/lib/supabase.js';
import { resetRateLimits } from '../src/middleware/rateLimit.js';
import { invalidateFlags } from '../src/services/flags.js';
import { fakeSupabase, type FakeSupabase } from './helpers/fakeSupabase.js';

const OUTLET = 'a0000000-0000-4000-8000-000000000001';
const SERVICE = 'b0000000-0000-4000-8000-000000000001';
const TEMPLATE = 'c0000000-0000-4000-8000-000000000001';
const VEH_1 = '20000000-0000-4000-8000-000000000001';
/** A future slot on the 15-minute grid inside opening hours (10:00 SAST). */
const SLOT = '2027-03-10T08:00:00.000Z';
const SAST_OFFSET_MS = 2 * 60 * 60_000;

let db: FakeSupabase;
let server: Server;
let base: string;

/** Mirrors `public.get_available_slots` for the fake: 07:00–18:00 SAST. */
function slotsRpc(args: Record<string, unknown>) {
  const outlet = db.rows('outlets').find((o) => o.id === args.p_outlet);
  const service = db.rows('services').find((s) => s.id === args.p_service);
  if (!outlet || !service) return [];
  const dayStart = new Date(`${args.p_date}T00:00:00.000Z`).getTime() - SAST_OFFSET_MS;
  const open = dayStart + 7 * 60 * 60_000;
  const close = dayStart + 18 * 60 * 60_000;
  const dur = service.duration_minutes * 60_000;
  const out: unknown[] = [];
  for (let cursor = open; cursor + dur <= close; cursor += outlet.slot_minutes * 60_000) {
    const booked = db.rows('bookings').filter((b) => b.outlet_id === outlet.id && ['pending', 'confirmed', 'in_service'].includes(b.status) && new Date(b.slot_start).getTime() < cursor + dur && new Date(b.slot_end).getTime() > cursor).length;
    out.push({ slot_start: new Date(cursor).toISOString(), slot_end: new Date(cursor + dur).toISOString(), capacity: outlet.bay_count, booked, available: booked < outlet.bay_count && cursor > Date.now() });
  }
  return out;
}

beforeAll(async () => {
  server = createServer(createApp());
  await new Promise<void>((r) => server.listen(0, r));
  base = `http://127.0.0.1:${(server.address() as { port: number }).port}`;
  setFirebaseAuthForTests({
    verifyIdToken: async (token: string) => {
      const users: Record<string, string> = { tech: 'tech_1', adm: 'adm_1', cust: 'cust_1' };
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
  db = fakeSupabase({ rpc: { get_available_slots: slotsRpc } });
  db.seed('feature_flags', [{ key: 'auto_assignment', enabled: false }, { key: 'whatsapp_enabled', enabled: false }, { key: 'cash_on_collection', enabled: true }]);
  db.seed('profiles', [
    { id: 'tech_1', role: 'technician', full_name: 'Pieter', is_active: true, push_opt_in: true, whatsapp_opt_in: true, marketing_opt_in: false },
    { id: 'adm_1', role: 'admin', full_name: 'Ayesha', is_active: true, push_opt_in: true, whatsapp_opt_in: true, marketing_opt_in: false },
    { id: 'cust_1', role: 'customer', full_name: 'Naledi Mokoena', email: 'naledi@example.com', phone: '+27 83 111 2222', is_active: true, push_opt_in: true, whatsapp_opt_in: true, marketing_opt_in: false },
  ]);
  db.seed('staff_outlets', [{ profile_id: 'tech_1', outlet_id: OUTLET }]);
  db.seed('outlets', [{ id: OUTLET, code: 'SAN', name: 'Sparkling Sandton', timezone: 'Africa/Johannesburg', slot_minutes: 15, bay_count: 2, is_active: true, rating: 4.8 }]);
  db.seed('services', [{ id: SERVICE, code: 'FULL', name: 'Full Valet', category: 'car_wash', duration_minutes: 30, base_price_cents: 12000, is_quote_based: false, points_per_rand: 0.1, is_active: true, checklist_template_id: TEMPLATE }]);
  db.seed('outlet_services', [{ outlet_id: OUTLET, service_id: SERVICE, price_cents: null, is_available: true }]);
  db.seed('checklist_templates', [{ id: TEMPLATE, name: 'Valet', category: 'car_wash', version: 1, status: 'published', outlet_id: null, steps: [{ key: 'exterior', title: 'Exterior', type: 'confirm', required: true }] }]);
  db.seed('vehicles', [{ id: VEH_1, customer_id: 'cust_1', registration_no: 'HR 88 TS GP', make: 'Suzuki', model: 'Swift', colour: 'Red', source: 'manual', disc_verified: false, is_active: true }]);
  db.seed('notification_templates', [{ key: 'booking_confirmed', channel: 'push', title: 'Confirmed', body: '{{ref}} confirmed.', is_promotional: false, is_active: true }]);
  setSupabaseClient(db as any);
  invalidateFlags();
  resetRateLimits();
});

async function call(path: string, token: string, init: RequestInit = {}) {
  const res = await fetch(`${base}${path}`, { ...init, headers: { Authorization: `Bearer ${token}`, 'Content-Type': 'application/json', ...(init.headers ?? {}) } });
  const text = await res.text();
  let body: any = text;
  try { body = JSON.parse(text); } catch { /* keep text */ }
  return { status: res.status, body };
}
const post = (path: string, token: string, body: unknown) => call(path, token, { method: 'POST', body: JSON.stringify(body) });
const base_ = { vehicle_id: VEH_1, outlet_id: OUTLET, service_id: SERVICE, slot_start: SLOT };

describe('POST /v1/bookings pay_at', () => {
  it('a counter booking paid at check-in is confirmed without a payment and stores pay_at=checkin', async () => {
    const r = await post('/v1/bookings', 'cust', { ...base_, client_op_id: 'op-payat-0001', payment_method: 'cash', pay_at: 'checkin' });
    expect(r.status, JSON.stringify(r.body)).toBe(201);
    expect(r.body.booking).toMatchObject({ status: 'confirmed', payment_method: 'cash', pay_at: 'checkin', total_cents: 12000 });
    expect(db.rows('payments')).toHaveLength(0);
    // Confirmed → its work order is on the board at once (awaiting check-in).
    expect(db.rows('work_orders').filter((w) => w.booking_id === r.body.booking.id)).toHaveLength(1);
    expect(db.rows('audit_events').find((a) => a.action === 'booking.create')?.after).toMatchObject({ payment_method: 'cash', pay_at: 'checkin' });
    const detail = await call(`/v1/bookings/${r.body.booking.id}`, 'cust');
    expect(detail.status).toBe(200);
    expect(detail.body.pay_at).toBe('checkin');
  });

  it('cash without pay_at defaults to collection; card bookings store booking', async () => {
    const cash = await post('/v1/bookings', 'cust', { ...base_, client_op_id: 'op-payat-0002', payment_method: 'cash' });
    expect(cash.status, JSON.stringify(cash.body)).toBe(201);
    expect(cash.body.booking).toMatchObject({ status: 'confirmed', payment_method: 'cash', pay_at: 'collection' });
    const card = await post('/v1/bookings', 'cust', { ...base_, slot_start: '2027-03-10T09:00:00.000Z', client_op_id: 'op-payat-0003', payment_method: 'card' });
    expect(card.status, JSON.stringify(card.body)).toBe(201);
    expect(card.body.booking).toMatchObject({ status: 'pending', payment_method: 'card', pay_at: 'booking' });
  });

  it('pay_at with an online payment method is a 400 and pay_at is validated', async () => {
    const r = await post('/v1/bookings', 'cust', { ...base_, client_op_id: 'op-payat-0004', payment_method: 'card', pay_at: 'checkin' });
    expect(r.status).toBe(400);
    expect(r.body.error.details).toEqual([{ path: 'pay_at', message: 'Requires payment_method cash' }]);
    const bad = await post('/v1/bookings', 'cust', { ...base_, client_op_id: 'op-payat-0005', payment_method: 'cash', pay_at: 'booking' });
    expect(bad.status).toBe(400);
    expect(db.rows('bookings')).toHaveLength(0);
  });

  it('the flag still gates both counter moments', async () => {
    db.rows('feature_flags').find((f) => f.key === 'cash_on_collection')!.enabled = false;
    invalidateFlags();
    const r = await post('/v1/bookings', 'cust', { ...base_, client_op_id: 'op-payat-0006', payment_method: 'cash', pay_at: 'checkin' });
    expect(r.status).toBe(409);
    expect(r.body.error.details).toMatchObject({ reason: 'cash_disabled' });
  });
});

describe('staff walk-ins and the expansions', () => {
  const NOW = '2026-09-14T08:07:00.000Z'; // Monday 10:07 SAST
  beforeEach(() => vi.useFakeTimers({ now: new Date(NOW), toFake: ['Date'] }));

  it('a walk-in paid at the counter now stores checkin; "pay on collection" stores cash + collection with nothing recorded', async () => {
    const now = await post('/v1/bookings', 'tech', { vehicle_id: VEH_1, outlet_id: OUTLET, service_id: SERVICE, customer_id: 'cust_1', walk_in: true, client_op_id: 'op-walk-payat-01' });
    expect(now.status, JSON.stringify(now.body)).toBe(201);
    expect(now.body.booking).toMatchObject({ status: 'confirmed', payment_method: null, pay_at: 'checkin' });
    const later = await post('/v1/bookings', 'tech', { vehicle_id: VEH_1, outlet_id: OUTLET, service_id: SERVICE, customer_id: 'cust_1', walk_in: true, client_op_id: 'op-walk-payat-02', payment_method: 'cash', pay_at: 'collection', checkin: { bay: 'Bay 2' } });
    expect(later.status, JSON.stringify(later.body)).toBe(201);
    expect(later.body.booking).toMatchObject({ status: 'in_service', payment_method: 'cash', pay_at: 'collection' });
    expect(later.body.work_order.bay).toBe('Bay 2');
    expect(db.rows('payments')).toHaveLength(0);

    // Admin rows carry pay_at (the `GET /tasks` and work-order detail booking expansions share the column list;
    // the fake cannot resolve nested selects).
    const admin = await call(`/v1/admin/work-orders?outlet_id=${OUTLET}`, 'adm');
    expect(admin.status, JSON.stringify(admin.body)).toBe(200);
    const row = admin.body.data.find((w: any) => w.id === later.body.work_order.id);
    expect(row).toMatchObject({ amount_due_cents: 12000, payment_method: 'cash', pay_at: 'collection', payment: null });
  });

  it('/sync/batch booking.create_walk_in accepts pay_at', async () => {
    const r = await post('/v1/sync/batch', 'tech', { operations: [{ client_op_id: 'op-sync-payat-01', kind: 'booking.create_walk_in', device_time: NOW, payload: { customer_id: 'cust_1', vehicle_id: VEH_1, outlet_id: OUTLET, service_id: SERVICE, payment_method: 'cash', pay_at: 'collection' } }] });
    expect(r.status, JSON.stringify(r.body)).toBe(200);
    expect(r.body.results[0].status).toBe('applied');
    expect(r.body.results[0].result.booking).toMatchObject({ status: 'confirmed', payment_method: 'cash', pay_at: 'collection' });
  });
});
