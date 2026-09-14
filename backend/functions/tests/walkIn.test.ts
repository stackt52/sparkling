/**
 * Staff — walk-in customers & bookings (STF-010/012, CUS-020..025 on behalf of a customer):
 * customer search, counter registration + claim on sign-up, vehicles for a customer,
 * walk-in bookings (slot rounding, capacity, outlet scope, check-in) and POS payment attestation.
 */
import { createServer, type Server } from 'node:http';
import { afterAll, afterEach, beforeAll, beforeEach, describe, expect, it, vi } from 'vitest';
import { createApp } from '../src/app.js';
import { setFirebaseAuthForTests, setFirebaseMessagingForTests } from '../src/lib/firebase.js';
import { setSupabaseClient } from '../src/lib/supabase.js';
import { resetRateLimits } from '../src/middleware/rateLimit.js';
import { roundUpToSlot } from '../src/services/availability.js';
import { phoneSearchPattern, samePhone } from '../src/services/customers.js';
import { invalidateFlags } from '../src/services/flags.js';
import { fakeSupabase, type FakeSupabase } from './helpers/fakeSupabase.js';

const OUTLET = 'a0000000-0000-4000-8000-000000000001';
const OTHER_OUTLET = 'a0000000-0000-4000-8000-000000000002';
const SERVICE = 'b0000000-0000-4000-8000-000000000001';
const VEH_1 = '20000000-0000-4000-8000-000000000001';
const VEH_2 = '20000000-0000-4000-8000-000000000002';
const BOOKING_PAID = '10000000-0000-4000-8000-000000000001';
const BOOKING_PENDING = '10000000-0000-4000-8000-000000000002';
const TEMPLATE = 'c0000000-0000-4000-8000-000000000001';
const SAST_OFFSET_MS = 2 * 60 * 60_000;

let db: FakeSupabase;
let server: Server;
let base: string;
let receiptSeq = 70000;

/** Mirrors `public.get_available_slots` (migration 0001) for the fake: opening hours 07:00–18:00 SAST. */
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
    const slotStart = cursor;
    const slotEnd = cursor + dur;
    const booked = db.rows('bookings').filter((b) => b.outlet_id === outlet.id && ['pending', 'confirmed', 'in_service'].includes(b.status) && new Date(b.slot_start).getTime() < slotEnd && new Date(b.slot_end).getTime() > slotStart).length;
    out.push({ slot_start: new Date(slotStart).toISOString(), slot_end: new Date(slotEnd).toISOString(), capacity: outlet.bay_count, booked, available: booked < outlet.bay_count && slotStart > Date.now() });
  }
  return out;
}

beforeAll(async () => {
  server = createServer(createApp());
  await new Promise<void>((r) => server.listen(0, r));
  base = `http://127.0.0.1:${(server.address() as { port: number }).port}`;
  setFirebaseAuthForTests({
    verifyIdToken: async (token: string) => {
      const users: Record<string, Record<string, unknown>> = {
        tech: { uid: 'tech_1', email: 'tech@example.com' },
        sup: { uid: 'sup_1', email: 'sup@example.com' },
        other: { uid: 'tech_other', email: 'other@example.com' },
        cust: { uid: 'cust_1', email: 'naledi@example.com' },
        newphone: { uid: 'uid_phone', phone_number: '+27839998888' },
        newrecord: { uid: 'uid_record' },
        newbody: { uid: 'uid_body', email: 'body@example.com' },
        newmail: { uid: 'uid_mail', email: 'walk@example.com', name: 'Walk Mail' },
      };
      if (users[token]) return users[token];
      throw new Error('bad token');
    },
    getUser: async (uid: string) => ({ uid, phoneNumber: uid === 'uid_record' ? '+27 83 999 6666' : null }),
    setCustomUserClaims: async () => undefined,
  } as any);
  setFirebaseMessagingForTests({ sendEachForMulticast: async ({ tokens }: { tokens: string[] }) => ({ successCount: tokens.length, failureCount: 0, responses: tokens.map(() => ({ success: true })) }) } as any);
});
afterAll(() => server.close());

beforeEach(() => {
  receiptSeq = 70000;
  db = fakeSupabase({ rpc: { get_available_slots: slotsRpc, next_receipt_no: () => `RCP-${++receiptSeq}` } });
  db.seed('feature_flags', [{ key: 'auto_assignment', enabled: false }, { key: 'whatsapp_enabled', enabled: false }]);
  db.seed('profiles', [
    { id: 'tech_1', role: 'technician', full_name: 'Pieter', is_active: true, push_opt_in: true, whatsapp_opt_in: true, marketing_opt_in: false },
    { id: 'sup_1', role: 'supervisor', full_name: 'Johan', is_active: true, push_opt_in: true, whatsapp_opt_in: true, marketing_opt_in: false },
    { id: 'tech_other', role: 'technician', full_name: 'Elsewhere', is_active: true, push_opt_in: true, whatsapp_opt_in: true, marketing_opt_in: false },
    { id: 'cust_1', role: 'customer', full_name: 'Naledi Mokoena', email: 'naledi@example.com', phone: '+27 83 111 2222', is_active: true, push_opt_in: true, whatsapp_opt_in: true, marketing_opt_in: true },
    { id: 'cust_2', role: 'customer', full_name: 'Sipho Dlamini', email: 'sipho@example.com', phone: '0821234567', is_active: true, push_opt_in: true, whatsapp_opt_in: false, marketing_opt_in: false },
    { id: 'cust_inactive', role: 'customer', full_name: 'Naledi Gone', email: 'gone@example.com', phone: '+27831112223', is_active: false, push_opt_in: true, whatsapp_opt_in: true, marketing_opt_in: false },
    { id: 'walkin_phone', role: 'customer', full_name: 'Walk In Phone', email: null, phone: '+27839998888', is_active: true, push_opt_in: true, whatsapp_opt_in: true, marketing_opt_in: false },
    { id: 'walkin_record', role: 'customer', full_name: 'Walk In Record', email: null, phone: '+27 83 999 6666', is_active: true, push_opt_in: true, whatsapp_opt_in: true, marketing_opt_in: false },
    { id: 'walkin_body', role: 'customer', full_name: 'Walk In Body', email: null, phone: '+27 83 999 7777', is_active: true, push_opt_in: true, whatsapp_opt_in: true, marketing_opt_in: false },
    { id: 'walkin_mail', role: 'customer', full_name: 'Walk In Mail', email: 'walk@example.com', phone: '+27839995555', is_active: true, push_opt_in: true, whatsapp_opt_in: true, marketing_opt_in: false },
  ]);
  db.seed('staff_outlets', [{ profile_id: 'tech_1', outlet_id: OUTLET }, { profile_id: 'sup_1', outlet_id: OUTLET }, { profile_id: 'tech_other', outlet_id: OTHER_OUTLET }]);
  db.seed('outlets', [
    { id: OUTLET, code: 'SAN', name: 'Sparkling Sandton', timezone: 'Africa/Johannesburg', slot_minutes: 15, bay_count: 2, is_active: true, rating: 4.8 },
    { id: OTHER_OUTLET, code: 'PTA', name: 'Sparkling Pretoria', timezone: 'Africa/Johannesburg', slot_minutes: 30, bay_count: 1, is_active: true, rating: 4.5 },
  ]);
  db.seed('services', [{ id: SERVICE, code: 'FULL', name: 'Full Valet', category: 'car_wash', duration_minutes: 30, base_price_cents: 12000, is_quote_based: false, points_per_rand: 0.1, is_active: true, checklist_template_id: TEMPLATE }]);
  db.seed('outlet_services', [{ outlet_id: OUTLET, service_id: SERVICE, price_cents: null, is_available: true }, { outlet_id: OTHER_OUTLET, service_id: SERVICE, price_cents: null, is_available: true }]);
  db.seed('checklist_templates', [{ id: TEMPLATE, name: 'Valet', category: 'car_wash', version: 1, status: 'published', outlet_id: null, steps: [{ key: 'exterior', title: 'Exterior', type: 'confirm', required: true }] }]);
  db.seed('loyalty_accounts', [{ customer_id: 'cust_1', tier: 'gold', balance_points: 120, lifetime_points: 400 }]);
  db.seed('vehicles', [
    { id: VEH_1, customer_id: 'cust_1', registration_no: 'HR 88 TS GP', make: 'Suzuki', model: 'Swift', colour: 'Red', source: 'manual', disc_verified: false, is_active: true },
    { id: VEH_2, customer_id: 'cust_2', registration_no: 'CA 123 456', make: 'VW', model: 'Polo', colour: null, source: 'manual', disc_verified: false, is_active: true },
  ]);
  db.seed('bookings', [
    { id: BOOKING_PAID, ref: 'SPK-2026-0101', customer_id: 'cust_1', vehicle_id: VEH_1, outlet_id: OUTLET, service_id: SERVICE, status: 'confirmed', slot_start: '2026-09-10T08:00:00.000Z', slot_end: '2026-09-10T08:30:00.000Z', price_cents: 12000, discount_cents: 0, total_cents: 12000, points_pending: 12, walk_in: false },
    { id: BOOKING_PENDING, ref: 'SPK-2026-0102', customer_id: 'cust_2', vehicle_id: VEH_2, outlet_id: OUTLET, service_id: SERVICE, status: 'pending', slot_start: '2026-09-10T09:00:00.000Z', slot_end: '2026-09-10T09:30:00.000Z', price_cents: 12000, discount_cents: 0, total_cents: 12000, points_pending: 12, walk_in: false },
  ]);
  db.seed('notification_templates', [
    { key: 'payment_successful', channel: 'push', title: 'Payment received', body: 'Paid {{amount}} — receipt {{receipt}}.', is_promotional: false, is_active: true },
    { key: 'payment_successful', channel: 'whatsapp', title: null, body: 'Paid {{amount}} — receipt {{receipt}}.', is_promotional: false, is_active: true },
  ]);
  db.seed('device_tokens', [{ profile_id: 'cust_1', token: 'tok_c1', platform: 'android', app: 'customer' }]);
  setSupabaseClient(db as any);
  invalidateFlags();
  resetRateLimits();
});

afterEach(() => {
  vi.useRealTimers();
});

async function call(path: string, token: string, init: RequestInit = {}) {
  const res = await fetch(`${base}${path}`, { ...init, headers: { Authorization: `Bearer ${token}`, 'Content-Type': 'application/json', ...(init.headers ?? {}) } });
  const text = await res.text();
  let body: any = text;
  try { body = JSON.parse(text); } catch { /* keep text */ }
  return { status: res.status, body, headers: res.headers };
}
const post = (path: string, token: string, body: unknown) => call(path, token, { method: 'POST', body: JSON.stringify(body) });
const audits = (action: string) => db.rows('audit_events').filter((a) => a.action === action);

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

describe('phone helpers', () => {
  it('builds formatting-agnostic patterns and compares normalised numbers', () => {
    expect(phoneSearchPattern('083 111 2222')).toBe('%83%111%2222%');
    expect(phoneSearchPattern('+27831112222')).toBe('%83%111%2222%');
    expect(phoneSearchPattern('0831112222')).toBe('%83%111%2222%');
    expect(phoneSearchPattern('83111')).toBe('%83111%');
    expect(phoneSearchPattern('Naledi')).toBeNull();
    expect(samePhone('083 111 2222', '+27831112222')).toBe(true);
    expect(samePhone('083 111 2222', '+27831112223')).toBe(false);
  });

  it('rounds a walk-in start up to the next grid multiple in the outlet timezone (strictly after now)', () => {
    expect(roundUpToSlot(new Date('2026-09-14T08:07:00.000Z'), 15, 'Africa/Johannesburg').toISOString()).toBe('2026-09-14T08:15:00.000Z');
    expect(roundUpToSlot(new Date('2026-09-14T08:15:00.000Z'), 15, 'Africa/Johannesburg').toISOString()).toBe('2026-09-14T08:30:00.000Z');
    expect(roundUpToSlot(new Date('2026-09-14T08:15:00.001Z'), 30, 'Africa/Johannesburg').toISOString()).toBe('2026-09-14T08:30:00.000Z');
    // 45-minute grid anchored on the local day: 10:07 SAST → 10:30 SAST (08:30Z), not 08:15Z.
    expect(roundUpToSlot(new Date('2026-09-14T08:07:00.000Z'), 45, 'Africa/Johannesburg').toISOString()).toBe('2026-09-14T08:30:00.000Z');
  });
});

// ---------------------------------------------------------------------------
// GET /staff/customers
// ---------------------------------------------------------------------------

describe('GET /v1/staff/customers', () => {
  it('finds a customer by local phone formatting (083… → +2783…) with loyalty and vehicles', async () => {
    const r = await call('/v1/staff/customers?search=083%20111%202222', 'tech');
    expect(r.status).toBe(200);
    expect(r.body.data).toHaveLength(1);
    expect(r.body.data[0]).toEqual({
      id: 'cust_1',
      full_name: 'Naledi Mokoena',
      email: 'naledi@example.com',
      phone: '+27 83 111 2222',
      marketing_opt_in: true,
      whatsapp_opt_in: true,
      loyalty: { tier: 'gold', balance_points: 120, discount_pct: 0, plan_code: null, plan_name: null, membership_status: null, included_remaining: 0 },
      vehicles: [{ id: VEH_1, registration_no: 'HR 88 TS GP', make: 'Suzuki', model: 'Swift', colour: 'Red', disc_verified: false }],
    });
    const log = audits('customer.search');
    expect(log).toHaveLength(1);
    expect(log[0].actor_id).toBe('tech_1');
    expect(log[0].after.search).toBe('083 111 2222');
  });

  it('accepts E.164 and unformatted variants and never returns inactive customers', async () => {
    for (const term of ['0831112222', encodeURIComponent('+27831112222'), '27831112222']) {
      const r = await call(`/v1/staff/customers?search=${term}`, 'sup');
      expect(r.status).toBe(200);
      expect(r.body.data.map((c: any) => c.id)).toEqual(['cust_1']);
    }
    const stored = await call('/v1/staff/customers?search=082%20123', 'sup');
    expect(stored.body.data.map((c: any) => c.id)).toEqual(['cust_2']);
    expect(stored.body.data[0].loyalty).toBeNull();
  });

  it('finds customers by plate (normalised, alphanumerics only) and by name/e-mail', async () => {
    const plate = await call('/v1/staff/customers?search=hr88ts', 'tech');
    expect(plate.status).toBe(200);
    expect(plate.body.data.map((c: any) => c.id)).toEqual(['cust_1']);
    const spaced = await call('/v1/staff/customers?search=ca%20123', 'tech');
    expect(spaced.body.data.map((c: any) => c.id)).toEqual(['cust_2']);
    const name = await call('/v1/staff/customers?search=naledi&limit=1', 'tech');
    expect(name.body.data.map((c: any) => c.id)).toEqual(['cust_1']);
    const email = await call('/v1/staff/customers?search=sipho@example', 'tech');
    expect(email.body.data.map((c: any) => c.id)).toEqual(['cust_2']);
  });

  it('validates the query and is staff-only', async () => {
    const short = await call('/v1/staff/customers?search=x', 'tech');
    expect(short.status).toBe(400);
    expect(short.body.error.code).toBe('validation_error');
    const big = await call('/v1/staff/customers?search=naledi&limit=50', 'tech');
    expect(big.status).toBe(400);
    const cust = await call('/v1/staff/customers?search=naledi', 'cust');
    expect(cust.status).toBe(403);
  });
});

// ---------------------------------------------------------------------------
// POST /staff/customers (+ claim on sign-up)
// ---------------------------------------------------------------------------

describe('POST /v1/staff/customers', () => {
  const body = { full_name: 'Thandi Nkosi', phone: '082 999 0000', email: 'Thandi@Example.com', client_op_id: 'op-cust-000001' };

  it('registers a walk-in customer with a walkin_ id, loyalty account and audit row', async () => {
    const r = await post('/v1/staff/customers', 'tech', body);
    expect(r.status).toBe(201);
    const c = r.body.customer;
    expect(c.id).toMatch(/^walkin_[0-9a-f-]{36}$/);
    expect(c).toMatchObject({ full_name: 'Thandi Nkosi', phone: '+27829990000', email: 'thandi@example.com', marketing_opt_in: false, whatsapp_opt_in: true, loyalty: { tier: 'silver', balance_points: 0 }, vehicles: [] });
    const profile = db.rows('profiles').find((p) => p.id === c.id)!;
    expect(profile.role).toBe('customer');
    expect(db.rows('loyalty_accounts').find((a) => a.customer_id === c.id)).toMatchObject({ tier: 'silver', balance_points: 0 });
    const log = audits('customer.create');
    expect(log).toHaveLength(1);
    expect(log[0]).toMatchObject({ actor_id: 'tech_1', entity_id: c.id, outlet_id: OUTLET });
  });

  it('honours opt-ins and the outlet scope', async () => {
    const r = await post('/v1/staff/customers', 'tech', { ...body, marketing_opt_in: true, whatsapp_opt_in: false, outlet_id: OUTLET });
    expect(r.status).toBe(201);
    expect(r.body.customer).toMatchObject({ marketing_opt_in: true, whatsapp_opt_in: false });
    const out = await post('/v1/staff/customers', 'tech', { ...body, client_op_id: 'op-cust-000002', phone: '082 999 0001', email: null, outlet_id: OTHER_OUTLET });
    expect(out.status).toBe(403);
  });

  it('409s with the existing customer when the phone or e-mail is already registered', async () => {
    const byPhone = await post('/v1/staff/customers', 'tech', { ...body, phone: '083-111-2222', email: null });
    expect(byPhone.status).toBe(409);
    expect(byPhone.body.error.code).toBe('conflict');
    expect(byPhone.body.error.details.existing_customer.id).toBe('cust_1');
    expect(byPhone.body.error.details.existing_customer.loyalty).toEqual({ tier: 'gold', balance_points: 120, discount_pct: 0, plan_code: null, plan_name: null, membership_status: null, included_remaining: 0 });
    const byEmail = await post('/v1/staff/customers', 'tech', { ...body, client_op_id: 'op-cust-000003', phone: '082 999 0009', email: 'SIPHO@example.com' });
    expect(byEmail.status).toBe(409);
    expect(byEmail.body.error.details.existing_customer.id).toBe('cust_2');
    expect(db.rows('profiles').filter((p) => p.id.startsWith('walkin_') && p.full_name === 'Thandi Nkosi')).toHaveLength(0);
  });

  it('validates the body (name length, phone format)', async () => {
    const bad = await post('/v1/staff/customers', 'tech', { ...body, phone: '12' });
    expect(bad.status).toBe(400);
    const notPhone = await post('/v1/staff/customers', 'tech', { ...body, phone: 'not-a-number' });
    expect(notPhone.status).toBe(400);
    expect(notPhone.body.error.details[0].path).toBe('phone');
    const short = await post('/v1/staff/customers', 'tech', { ...body, full_name: 'T' });
    expect(short.status).toBe(400);
    const cust = await post('/v1/staff/customers', 'cust', body);
    expect(cust.status).toBe(403);
  });

  it('replays the same client_op_id without creating a second profile', async () => {
    const first = await post('/v1/staff/customers', 'tech', body);
    expect(first.status).toBe(201);
    const again = await post('/v1/staff/customers', 'tech', body);
    expect(again.status).toBe(201);
    expect(again.headers.get('idempotent-replayed')).toBe('true');
    expect(again.body.customer.id).toBe(first.body.customer.id);
    expect(db.rows('profiles').filter((p) => p.full_name === 'Thandi Nkosi')).toHaveLength(1);
  });
});

describe('POST /v1/auth/session claims walk-in profiles', () => {
  it('by the phone on the Firebase token (bookings, vehicles and points carry over via the id rewrite)', async () => {
    const r = await post('/v1/auth/session', 'newphone', { app: 'customer' });
    expect(r.status).toBe(200);
    expect(r.body.profile.id).toBe('uid_phone');
    expect(r.body.profile.full_name).toBe('Walk In Phone');
    expect(r.body.profile.phone).toBe('+27839998888');
    expect(db.rows('profiles').some((p) => p.id === 'walkin_phone')).toBe(false);
  });

  it('by the phone on the Firebase user record when the token has none', async () => {
    const r = await post('/v1/auth/session', 'newrecord', { app: 'customer' });
    expect(r.status).toBe(200);
    expect(r.body.profile.id).toBe('uid_record');
    expect(r.body.profile.full_name).toBe('Walk In Record');
    expect(db.rows('profiles').some((p) => p.id === 'walkin_record')).toBe(false);
  });

  it('by the phone in the body (local format) and adopts the verified e-mail', async () => {
    const r = await post('/v1/auth/session', 'newbody', { app: 'customer', phone: '083 999 7777' });
    expect(r.status).toBe(200);
    expect(r.body.profile.id).toBe('uid_body');
    expect(r.body.profile.email).toBe('body@example.com');
    expect(r.body.profile.full_name).toBe('Walk In Body');
    expect(db.rows('profiles').some((p) => p.id === 'walkin_body')).toBe(false);
  });

  it('by e-mail, like seeded profiles', async () => {
    const r = await post('/v1/auth/session', 'newmail', { app: 'customer' });
    expect(r.status).toBe(200);
    expect(r.body.profile.id).toBe('uid_mail');
    expect(r.body.profile.full_name).toBe('Walk In Mail');
    expect(db.rows('profiles').some((p) => p.id === 'walkin_mail')).toBe(false);
  });
});

// ---------------------------------------------------------------------------
// POST /staff/customers/:id/vehicles
// ---------------------------------------------------------------------------

describe('POST /v1/staff/customers/:id/vehicles', () => {
  it('creates a vehicle owned by the customer; scans with a disc hash are verified', async () => {
    const r = await post(`/v1/staff/customers/cust_1/vehicles`, 'tech', { registration_no: 'KL 45 MN GP', make: 'Toyota', model: 'Corolla', source: 'scan', disc_hash: 'a'.repeat(64), client_op_id: 'op-veh-000001' });
    expect(r.status).toBe(201);
    expect(r.body.vehicle).toMatchObject({ customer_id: 'cust_1', registration_no: 'KL 45 MN GP', source: 'scan', disc_verified: true });
    const log = audits('vehicle.create');
    expect(log).toHaveLength(1);
    expect(log[0]).toMatchObject({ actor_id: 'tech_1', entity_id: r.body.vehicle.id });
    expect(log[0].after).toMatchObject({ customer_id: 'cust_1', on_behalf: true });
    const manual = await post(`/v1/staff/customers/cust_1/vehicles`, 'tech', { registration_no: 'ND 1 GP', source: 'scan' });
    expect(manual.status).toBe(201);
    expect(manual.body.vehicle.disc_verified).toBe(false);
  });

  it('409s on a duplicate plate unless forced; 404 for unknown customers', async () => {
    const dup = await post(`/v1/staff/customers/cust_1/vehicles`, 'tech', { registration_no: 'hr88tsgp' });
    expect(dup.status).toBe(409);
    expect(dup.body.error.code).toBe('conflict');
    expect(dup.body.error.details.existing_vehicle_id).toBe(VEH_1);
    const forced = await post(`/v1/staff/customers/cust_1/vehicles`, 'tech', { registration_no: 'hr88tsgp', colour: 'Blue', force: true });
    expect(forced.status).toBe(200);
    expect(forced.body.vehicle.id).toBe(VEH_1);
    expect(forced.body.vehicle.colour).toBe('Blue');
    const missing = await post(`/v1/staff/customers/nobody/vehicles`, 'tech', { registration_no: 'XX 1 GP' });
    expect(missing.status).toBe(404);
    const staffTarget = await post(`/v1/staff/customers/sup_1/vehicles`, 'tech', { registration_no: 'XX 1 GP' });
    expect(staffTarget.status).toBe(404);
    const cust = await post(`/v1/staff/customers/cust_1/vehicles`, 'cust', { registration_no: 'XX 1 GP' });
    expect(cust.status).toBe(403);
  });
});

// ---------------------------------------------------------------------------
// POST /bookings — walk-ins
// ---------------------------------------------------------------------------

describe('POST /v1/bookings (staff walk-in)', () => {
  const NOW = '2026-09-14T08:07:00.000Z'; // Monday 10:07 SAST
  const walkIn = { vehicle_id: VEH_1, outlet_id: OUTLET, service_id: SERVICE, customer_id: 'cust_1', walk_in: true, client_op_id: 'op-walk-000001' };

  beforeEach(() => {
    vi.useFakeTimers({ now: new Date(NOW), toFake: ['Date'] });
  });

  it('defaults the slot to now rounded up to the outlet grid, starts confirmed and audits', async () => {
    const r = await post('/v1/bookings', 'tech', walkIn);
    expect(r.status).toBe(201);
    const b = r.body.booking;
    expect(b.slot_start).toBe('2026-09-14T08:15:00.000Z');
    expect(b.slot_end).toBe('2026-09-14T08:45:00.000Z');
    expect(b).toMatchObject({ status: 'confirmed', walk_in: true, created_by: 'tech_1', customer_id: 'cust_1', price_cents: 12000, total_cents: 12000, work_order: null });
    expect(r.body.duplicate).toBe(false);
    expect(r.body.work_order).toBeUndefined();
    const log = audits('booking.create_walk_in');
    expect(log).toHaveLength(1);
    expect(log[0]).toMatchObject({ actor_id: 'tech_1', entity_id: b.id, outlet_id: OUTLET });
    expect(audits('booking.create')).toHaveLength(0);
  });

  it('409s when every bay is taken in the next slot', async () => {
    db.seed('bookings', [
      { customer_id: 'cust_2', vehicle_id: VEH_2, outlet_id: OUTLET, service_id: SERVICE, status: 'in_service', slot_start: '2026-09-14T08:00:00.000Z', slot_end: '2026-09-14T08:30:00.000Z', total_cents: 12000 },
      { customer_id: 'cust_2', vehicle_id: VEH_2, outlet_id: OUTLET, service_id: SERVICE, status: 'confirmed', slot_start: '2026-09-14T08:15:00.000Z', slot_end: '2026-09-14T08:45:00.000Z', total_cents: 12000 },
    ]);
    const r = await post('/v1/bookings', 'tech', walkIn);
    expect(r.status).toBe(409);
    expect(r.body.error.code).toBe('conflict');
    expect(r.body.error.details).toMatchObject({ slot_start: '2026-09-14T08:15:00.000Z', booked: 2, capacity: 2 });
  });

  it('409s after closing time', async () => {
    vi.setSystemTime(new Date('2026-09-14T15:50:00.000Z')); // 17:50 SAST, last 30-min slot starts 17:30
    const r = await post('/v1/bookings', 'tech', walkIn);
    expect(r.status).toBe(409);
    expect(r.body.error.code).toBe('conflict');
  });

  it('403s when the outlet is outside the staff member’s scope', async () => {
    const r = await post('/v1/bookings', 'other', walkIn);
    expect(r.status).toBe(403);
    expect(r.body.error.code).toBe('forbidden');
    expect(db.rows('bookings').filter((b) => b.walk_in)).toHaveLength(0);
  });

  it('checkin creates the work order + task immediately and returns the booking with work_order expanded', async () => {
    const r = await post('/v1/bookings', 'sup', { ...walkIn, checkin: { bay: 'Bay 2', priority: 1 } });
    expect(r.status).toBe(201);
    expect(r.body.booking.status).toBe('in_service');
    expect(r.body.booking.work_order).toMatchObject({ status: 'queued', bay: 'Bay 2', stage_count: 1, progress_pct: 0 });
    expect(r.body.work_order).toMatchObject({ booking_id: r.body.booking.id, customer_id: 'cust_1', vehicle_id: VEH_1, priority: 1, bay: 'Bay 2', status: 'queued' });
    expect(r.body.task).toMatchObject({ work_order_id: r.body.work_order.id, status: 'queued', priority: 1 });
    expect(db.rows('bookings').find((b) => b.id === r.body.booking.id)!.status).toBe('in_service');
    expect(audits('booking.create_walk_in')).toHaveLength(1);
    expect(audits('booking.checkin')).toHaveLength(1);
  });

  it('replays the same client_op_id', async () => {
    const first = await post('/v1/bookings', 'tech', walkIn);
    expect(first.status).toBe(201);
    const again = await post('/v1/bookings', 'tech', walkIn);
    expect(again.status).toBe(201);
    expect(again.headers.get('idempotent-replayed')).toBe('true');
    expect(again.body.booking.id).toBe(first.body.booking.id);
    expect(db.rows('bookings').filter((b) => b.walk_in)).toHaveLength(1);
  });

  it('still accepts an explicit slot_start for a walk-in and keeps customer rules unchanged', async () => {
    const explicit = await post('/v1/bookings', 'tech', { ...walkIn, slot_start: '2026-09-14T09:00:00.000Z' });
    expect(explicit.status).toBe(201);
    expect(explicit.body.booking.slot_start).toBe('2026-09-14T09:00:00.000Z');
    expect(explicit.body.booking.status).toBe('confirmed');
    const noCustomer = await post('/v1/bookings', 'tech', { ...walkIn, client_op_id: 'op-walk-000002', customer_id: undefined });
    expect(noCustomer.status).toBe(400);
    const custWalkIn = await post('/v1/bookings', 'cust', { ...walkIn, client_op_id: 'op-walk-000003' });
    expect(custWalkIn.status).toBe(403);
    const custNoSlot = await post('/v1/bookings', 'cust', { vehicle_id: VEH_1, outlet_id: OUTLET, service_id: SERVICE, client_op_id: 'op-walk-000004' });
    expect(custNoSlot.status).toBe(400);
    expect(custNoSlot.body.error.details[0].path).toBe('slot_start');
    const custOk = await post('/v1/bookings', 'cust', { vehicle_id: VEH_1, outlet_id: OUTLET, service_id: SERVICE, slot_start: '2026-09-14T10:00:00.000Z', client_op_id: 'op-walk-000005' });
    expect(custOk.status).toBe(201);
    expect(custOk.body.booking).toMatchObject({ status: 'pending', walk_in: false, created_by: 'cust_1' });
  });
});

// ---------------------------------------------------------------------------
// POST /payments/record
// ---------------------------------------------------------------------------

describe('POST /v1/payments/record', () => {
  const record = { booking_id: BOOKING_PAID, method: 'cash', reference: 'till-7', amount_cents: 12000, idempotency_key: 'pos-000001' };

  it('records a successful POS payment with receipt, event, notification and audit', async () => {
    const r = await post('/v1/payments/record', 'tech', record);
    expect(r.status).toBe(201);
    const p = r.body.payment;
    expect(p).toMatchObject({ booking_id: BOOKING_PAID, customer_id: 'cust_1', provider: 'pos', method: 'cash', provider_ref: 'till-7', amount_cents: 12000, currency: 'ZAR', status: 'successful', receipt_no: 'RCP-70001', recorded_by: 'tech_1', idempotency_key: 'tech_1:pos-000001' });
    expect(p.verified_at).toBeTruthy();
    expect(r.body.duplicate).toBe(false);
    const events = db.rows('payment_events');
    expect(events).toHaveLength(1);
    expect(events[0]).toMatchObject({ payment_id: p.id, provider: 'pos', provider_event_id: 'tech_1:pos-000001', event_type: 'pos.recorded', signature_ok: true });
    expect(events[0].payload).toMatchObject({ actor: 'tech_1', method: 'cash', reference: 'till-7' });
    const log = audits('payment.record');
    expect(log).toHaveLength(1);
    expect(log[0]).toMatchObject({ actor_id: 'tech_1', entity_id: p.id, outlet_id: OUTLET });
    expect(log[0].after).toMatchObject({ method: 'cash', receipt_no: 'RCP-70001', amount_cents: 12000 });
    const notes = db.rows('notifications').filter((n) => n.template_key === 'payment_successful' && n.recipient_id === 'cust_1');
    expect(notes.map((n) => n.channel).sort()).toEqual(['push', 'whatsapp']);
    expect(notes.find((n) => n.channel === 'push')!.status).toBe('sent');
    expect(notes.find((n) => n.channel === 'whatsapp')!.status).toBe('suppressed'); // flag off
    expect(notes[0].body).toContain('RCP-70001');
  });

  it('400s when the amount differs from the booking total', async () => {
    const r = await post('/v1/payments/record', 'tech', { ...record, amount_cents: 11000 });
    expect(r.status).toBe(400);
    expect(r.body.error.code).toBe('validation_error');
    expect(r.body.error.details[0]).toMatchObject({ path: 'amount_cents', expected: 12000, received: 11000 });
    expect(db.rows('payments')).toHaveLength(0);
  });

  it('409s when the booking is already paid, but replays the same idempotency key', async () => {
    const first = await post('/v1/payments/record', 'tech', record);
    expect(first.status).toBe(201);
    const other = await post('/v1/payments/record', 'tech', { ...record, method: 'card_terminal', idempotency_key: 'pos-000002' });
    expect(other.status).toBe(409);
    expect(other.body.error.code).toBe('conflict');
    expect(other.body.error.details.payment.id).toBe(first.body.payment.id);
    const replay = await post('/v1/payments/record', 'tech', record);
    expect(replay.status).toBe(200);
    expect(replay.body.duplicate).toBe(true);
    expect(replay.body.payment.id).toBe(first.body.payment.id);
    expect(db.rows('payments')).toHaveLength(1);
    expect(db.rows('payment_events')).toHaveLength(1);
    expect(audits('payment.record')).toHaveLength(1);
  });

  it('confirms a pending booking and allocates sequential receipt numbers', async () => {
    const a = await post('/v1/payments/record', 'tech', record);
    const b = await post('/v1/payments/record', 'sup', { ...record, booking_id: BOOKING_PENDING, method: 'card_terminal', reference: null, idempotency_key: 'pos-000003' });
    expect(a.body.payment.receipt_no).toBe('RCP-70001');
    expect(b.status).toBe(201);
    expect(b.body.payment).toMatchObject({ receipt_no: 'RCP-70002', method: 'card_terminal', provider_ref: null, recorded_by: 'sup_1' });
    expect(db.rows('bookings').find((x) => x.id === BOOKING_PENDING)!.status).toBe('confirmed');
  });

  it('is outlet-scoped and staff-only, and validates the method', async () => {
    const other = await post('/v1/payments/record', 'other', record);
    expect(other.status).toBe(403);
    const cust = await post('/v1/payments/record', 'cust', record);
    expect(cust.status).toBe(403);
    const bad = await post('/v1/payments/record', 'tech', { ...record, method: 'crypto' });
    expect(bad.status).toBe(400);
    const missing = await post('/v1/payments/record', 'tech', { ...record, booking_id: '10000000-0000-4000-8000-00000000ffff' });
    expect(missing.status).toBe(404);
    expect(db.rows('payments')).toHaveLength(0);
  });
});
