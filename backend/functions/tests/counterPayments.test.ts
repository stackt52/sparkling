/**
 * Payments at check-in and at collection (migration 0022, `payments.stage`).
 *
 * An unpaid booking (or quotation-backed work order) can be settled by outlet staff or a
 * dashboard admin — cash, card terminal or EFT reference — either standalone through
 * `POST /payments/record` (stage inferred) or together with the check-in
 * (`POST /work-orders/:id/checkin`, `POST /bookings/:id/checkin`) and the hand-over
 * (`POST /work-orders/:id/pickup/verify`). The customer can pay an unpaid booking in-app once
 * the car is checked in or ready for collection (`POST /payments/intents`). Keys are never
 * released while a cash-on-collection balance is due.
 */
import { createServer, type Server } from 'node:http';
import { afterAll, beforeAll, beforeEach, describe, expect, it } from 'vitest';
import { createApp } from '../src/app.js';
import { setFirebaseAuthForTests, setFirebaseMessagingForTests } from '../src/lib/firebase.js';
import { setSupabaseClient } from '../src/lib/supabase.js';
import { resetRateLimits } from '../src/middleware/rateLimit.js';
import { invalidateFlags } from '../src/services/flags.js';
import { stageForBooking } from '../src/services/payments.js';
import { transitionTask } from '../src/services/workflow.js';
import { fakeSupabase, type FakeSupabase } from './helpers/fakeSupabase.js';
import { makeCtx } from './helpers/context.js';

const OUTLET = 'a0000000-0000-4000-8000-000000000001';
const OTHER_OUTLET = 'a0000000-0000-4000-8000-000000000002';
const SERVICE = 'b0000000-0000-4000-8000-000000000001';
const BODY_SERVICE = 'b0000000-0000-4000-8000-000000000002';
const TEMPLATE = 'c0000000-0000-4000-8000-000000000002';
const VEH_1 = '20000000-0000-4000-8000-000000000001';
const VEH_2 = '20000000-0000-4000-8000-000000000002';
/** Card booking whose online payment never went through: `pending`, no work order yet. */
const BOOKING_PENDING = '10000000-0000-4000-8000-000000000001';
/** Confirmed card booking (walk-in style, nothing paid) with its work order awaiting check-in. */
const BOOKING_CONFIRMED = '10000000-0000-4000-8000-000000000002';
/** Cash-on-collection booking in service; its work order is complete and ready to be verified. */
const BOOKING_CASH = '10000000-0000-4000-8000-000000000003';
const WO_CONFIRMED = '30000000-0000-4000-8000-000000000002';
const WO_CASH = '30000000-0000-4000-8000-000000000003';
const WO_QUOTE = '30000000-0000-4000-8000-000000000004';
const TASK_CONFIRMED = '40000000-0000-4000-8000-000000000002';
const TASK_CASH = '40000000-0000-4000-8000-000000000003';
const TASK_QUOTE = '40000000-0000-4000-8000-000000000004';
const QUOTE = '70000000-0000-4000-8000-000000000001';

let db: FakeSupabase;
let server: Server;
let base: string;
let receiptSeq = 70000;

beforeAll(async () => {
  server = createServer(createApp());
  await new Promise<void>((r) => server.listen(0, r));
  base = `http://127.0.0.1:${(server.address() as { port: number }).port}`;
  setFirebaseAuthForTests({
    verifyIdToken: async (token: string) => {
      const users: Record<string, string> = { tech: 'tech_1', sup: 'sup_1', adm: 'adm_1', fin: 'fin_1', other: 'tech_other', cust: 'cust_1', cust2: 'cust_2' };
      if (users[token]) return { uid: users[token], email: `${token}@example.com` };
      throw new Error('bad token');
    },
    setCustomUserClaims: async () => undefined,
  } as any);
  setFirebaseMessagingForTests({ sendEachForMulticast: async ({ tokens }: { tokens: string[] }) => ({ successCount: tokens.length, failureCount: 0, responses: tokens.map(() => ({ success: true })) }) } as any);
});
afterAll(() => server.close());

beforeEach(() => {
  receiptSeq = 70000;
  db = fakeSupabase({ rpc: { next_receipt_no: () => `RCP-${++receiptSeq}` } });
  db.seed('feature_flags', [{ key: 'auto_assignment', enabled: false }, { key: 'whatsapp_enabled', enabled: false }, { key: 'payments_sandbox', enabled: true }, { key: 'cash_on_collection', enabled: true }]);
  db.seed('profiles', [
    { id: 'tech_1', role: 'technician', full_name: 'Pieter', is_active: true, push_opt_in: true, whatsapp_opt_in: true, marketing_opt_in: false },
    { id: 'sup_1', role: 'supervisor', full_name: 'Johan', is_active: true, push_opt_in: true, whatsapp_opt_in: true, marketing_opt_in: false },
    { id: 'adm_1', role: 'admin', full_name: 'Ayesha', is_active: true, push_opt_in: true, whatsapp_opt_in: true, marketing_opt_in: false },
    { id: 'fin_1', role: 'finance', full_name: 'Fikile', is_active: true, push_opt_in: true, whatsapp_opt_in: true, marketing_opt_in: false },
    { id: 'tech_other', role: 'technician', full_name: 'Elsewhere', is_active: true, push_opt_in: true, whatsapp_opt_in: true, marketing_opt_in: false },
    { id: 'cust_1', role: 'customer', full_name: 'Naledi Mokoena', phone: '+27831112222', is_active: true, push_opt_in: true, whatsapp_opt_in: true, marketing_opt_in: false },
    { id: 'cust_2', role: 'customer', full_name: 'Sipho Dlamini', is_active: true, push_opt_in: true, whatsapp_opt_in: true, marketing_opt_in: false },
  ]);
  db.seed('staff_outlets', [{ profile_id: 'tech_1', outlet_id: OUTLET }, { profile_id: 'sup_1', outlet_id: OUTLET }, { profile_id: 'tech_other', outlet_id: OTHER_OUTLET }]);
  db.seed('outlets', [{ id: OUTLET, code: 'SAN', name: 'Sparkling Sandton', timezone: 'Africa/Johannesburg', slot_minutes: 15, bay_count: 2, is_active: true }]);
  db.seed('services', [
    { id: SERVICE, code: 'FULL', name: 'Full Valet', category: 'car_wash', duration_minutes: 30, base_price_cents: 12000, is_quote_based: false, is_active: true, checklist_template_id: TEMPLATE },
    { id: BODY_SERVICE, code: 'BODY', name: 'Panel repair', category: 'auto_body', duration_minutes: 240, base_price_cents: 0, is_quote_based: true, is_active: true, checklist_template_id: TEMPLATE },
  ]);
  db.seed('checklist_templates', [{ id: TEMPLATE, name: 'Valet', category: 'car_wash', version: 2, status: 'published', steps: [
    { key: 'exterior', title: 'Exterior', type: 'confirm', required: true },
    { key: 'supervisor', title: 'Supervisor', type: 'supervisor_verify', required: false },
  ] }]);
  db.seed('vehicles', [
    { id: VEH_1, customer_id: 'cust_1', registration_no: 'HR 88 TS GP', make: 'Suzuki', model: 'Swift', is_active: true },
    { id: VEH_2, customer_id: 'cust_2', registration_no: 'CA 123 456', make: 'VW', model: 'Polo', is_active: true },
  ]);
  db.seed('bookings', [
    { id: BOOKING_PENDING, ref: 'SPK-2026-0101', customer_id: 'cust_1', vehicle_id: VEH_1, outlet_id: OUTLET, service_id: SERVICE, status: 'pending', payment_method: 'card', slot_start: '2026-09-10T08:00:00.000Z', slot_end: '2026-09-10T08:30:00.000Z', price_cents: 12000, discount_cents: 0, total_cents: 12000, points_pending: 12 },
    { id: BOOKING_CONFIRMED, ref: 'SPK-2026-0102', customer_id: 'cust_2', vehicle_id: VEH_2, outlet_id: OUTLET, service_id: SERVICE, status: 'confirmed', payment_method: 'card', slot_start: '2026-09-10T09:00:00.000Z', slot_end: '2026-09-10T09:30:00.000Z', price_cents: 12000, discount_cents: 0, total_cents: 12000, points_pending: 12, walk_in: true },
    { id: BOOKING_CASH, ref: 'SPK-2026-0103', customer_id: 'cust_1', vehicle_id: VEH_1, outlet_id: OUTLET, service_id: SERVICE, status: 'in_service', payment_method: 'cash', slot_start: '2026-09-09T08:00:00.000Z', slot_end: '2026-09-09T08:30:00.000Z', price_cents: 15000, discount_cents: 0, total_cents: 15000, points_pending: 15 },
  ]);
  db.seed('quotations', [{ id: QUOTE, ref: 'QT-2026-0042', customer_id: 'cust_2', vehicle_id: VEH_2, outlet_id: OUTLET, status: 'accepted', category: 'Dent', amount_cents: 250000, line_items: [] }]);
  const now = new Date().toISOString();
  db.seed('work_orders', [
    { id: WO_CONFIRMED, ref: 'WO-2026-4802', outlet_id: OUTLET, booking_id: BOOKING_CONFIRMED, vehicle_id: VEH_2, customer_id: 'cust_2', service_id: SERVICE, status: 'queued', priority: 2, bay: null, checklist_template_id: TEMPLATE, template_version: 2, assignee_id: null, checked_in_at: null, checked_in_by: null, collected_at: null, pickup_otp: null },
    { id: WO_CASH, ref: 'WO-2026-4803', outlet_id: OUTLET, booking_id: BOOKING_CASH, vehicle_id: VEH_1, customer_id: 'cust_1', service_id: SERVICE, status: 'completed', priority: 2, bay: 'Bay 1', checklist_template_id: TEMPLATE, template_version: 2, assignee_id: 'tech_1', checked_in_at: now, checked_in_by: 'sup_1', started_at: now, completed_at: now, collected_at: null, pickup_otp: null },
    { id: WO_QUOTE, ref: 'WO-2026-4804', outlet_id: OUTLET, booking_id: null, quotation_id: QUOTE, vehicle_id: VEH_2, customer_id: 'cust_2', service_id: BODY_SERVICE, status: 'queued', priority: 2, bay: null, checklist_template_id: TEMPLATE, template_version: 2, assignee_id: null, checked_in_at: null, checked_in_by: null, collected_at: null, pickup_otp: null },
  ]);
  db.seed('tasks', [
    { id: TASK_CONFIRMED, work_order_id: WO_CONFIRMED, outlet_id: OUTLET, title: 'Full Valet · CA 123 456', seq: 1, assignee_id: null, status: 'queued', priority: 2 },
    { id: TASK_CASH, work_order_id: WO_CASH, outlet_id: OUTLET, title: 'Full Valet · HR 88 TS GP', seq: 1, assignee_id: 'tech_1', status: 'completed', priority: 2, started_at: now, completed_at: now, elapsed_seconds: 600 },
    { id: TASK_QUOTE, work_order_id: WO_QUOTE, outlet_id: OUTLET, title: 'Dent repair · QT-2026-0042', seq: 1, assignee_id: null, status: 'queued', priority: 2 },
  ]);
  db.seed('checklist_step_results', [{ work_order_id: WO_CASH, step_key: 'exterior', status: 'done' }]);
  db.seed('gamification_rules', [{ version: 3, status: 'published', rules: { task_completed: 25 } }]);
  db.seed('notification_templates', [
    { key: 'payment_successful', channel: 'push', title: 'Payment received', body: 'Paid {{amount}} — receipt {{receipt}}.', is_promotional: false, is_active: true },
    { key: 'service_ready', channel: 'push', title: 'Ready', body: 'Your {{vehicle}} is ready at {{outlet}}. Collection OTP {{otp}}.', is_promotional: false, is_active: true },
    { key: 'vehicle_collected', channel: 'push', title: 'Keys collected', body: 'Your {{vehicle}} was collected from {{outlet}} at {{time}}.', is_promotional: false, is_active: true },
    { key: 'booking_confirmed', channel: 'push', title: 'Confirmed', body: '{{ref}} confirmed.', is_promotional: false, is_active: true },
  ]);
  db.seed('device_tokens', [{ profile_id: 'cust_1', token: 'tok_c1', platform: 'android', app: 'customer' }, { profile_id: 'cust_2', token: 'tok_c2', platform: 'android', app: 'customer' }]);
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
const payments = () => db.rows('payments');
const audits = (action: string) => db.rows('audit_events').filter((a) => a.action === action);
const wo = (id: string) => db.rows('work_orders').find((w) => w.id === id)!;
const booking = (id: string) => db.rows('bookings').find((b) => b.id === id)!;

/** Verifies the cash work order so a collection OTP is issued (what the hand-over needs). */
async function issueOtp(): Promise<string> {
  const r = await transitionTask(makeCtx('supervisor', 'sup_1', [OUTLET]), TASK_CASH, { to: 'verified' });
  expect(r.work_order.status).toBe('verified');
  return wo(WO_CASH).pickup_otp as string;
}

describe('stage inference', () => {
  it('follows the booking status', () => {
    expect(stageForBooking({ status: 'pending' })).toBe('booking');
    expect(stageForBooking({ status: 'confirmed' })).toBe('booking');
    expect(stageForBooking({ status: 'in_service' })).toBe('checkin');
    expect(stageForBooking({ status: 'completed' })).toBe('collection');
  });
});

describe('POST /v1/payments/record — methods, stage and who may capture', () => {
  it('records an EFT reference against an in-service booking at stage checkin, by an admin without outlet scope', async () => {
    const r = await post('/v1/payments/record', 'adm', { booking_id: BOOKING_CASH, method: 'eft', reference: 'FNB-77120', amount_cents: 15000, idempotency_key: 'pos-eft-0001' });
    expect(r.status).toBe(201);
    expect(r.body.payment).toMatchObject({ booking_id: BOOKING_CASH, provider: 'pos', method: 'eft', provider_ref: 'FNB-77120', amount_cents: 15000, status: 'successful', receipt_no: 'RCP-70001', recorded_by: 'adm_1', stage: 'checkin' });
    const ev = db.rows('payment_events')[0];
    expect(ev).toMatchObject({ provider: 'pos', event_type: 'pos.recorded' });
    expect(ev.payload).toMatchObject({ actor: 'adm_1', actor_role: 'admin', method: 'eft', reference: 'FNB-77120', stage: 'checkin' });
    const log = audits('payment.record');
    expect(log).toHaveLength(1);
    expect(log[0]).toMatchObject({ actor_id: 'adm_1', actor_role: 'admin', outlet_id: OUTLET });
    expect(log[0].after).toMatchObject({ method: 'eft', reference: 'FNB-77120', receipt_no: 'RCP-70001', stage: 'checkin', captured_by: 'adm_1', captured_by_role: 'admin' });
    const note = db.rows('notifications').find((n) => n.template_key === 'payment_successful')!;
    expect(note).toMatchObject({ recipient_id: 'cust_1', status: 'sent' });
    expect(note.body).toContain('RCP-70001');
  });

  it('infers booking / collection stages and accepts an explicit stage; finance users may record too', async () => {
    const pending = await post('/v1/payments/record', 'fin', { booking_id: BOOKING_PENDING, method: 'card_terminal', reference: '048213', amount_cents: 12000, idempotency_key: 'pos-stage-0001' });
    expect(pending.status).toBe(201);
    expect(pending.body.payment.stage).toBe('booking');
    expect(booking(BOOKING_PENDING).status).toBe('confirmed');

    booking(BOOKING_CASH).status = 'completed';
    const collection = await post('/v1/payments/record', 'tech', { booking_id: BOOKING_CASH, method: 'cash', amount_cents: 15000, idempotency_key: 'pos-stage-0002' });
    expect(collection.status).toBe(201);
    expect(collection.body.payment.stage).toBe('collection');

    const explicit = await post('/v1/payments/record', 'sup', { booking_id: BOOKING_CONFIRMED, method: 'cash', amount_cents: 12000, idempotency_key: 'pos-stage-0003', stage: 'checkin' });
    expect(explicit.status).toBe(201);
    expect(explicit.body.payment.stage).toBe('checkin');
  });

  it('requires a reference for EFT and rejects unknown methods / stages', async () => {
    const noRef = await post('/v1/payments/record', 'tech', { booking_id: BOOKING_CASH, method: 'eft', amount_cents: 15000, idempotency_key: 'pos-eft-0002' });
    expect(noRef.status).toBe(400);
    expect(noRef.body.error.details[0].path).toBe('reference');
    const badMethod = await post('/v1/payments/record', 'tech', { booking_id: BOOKING_CASH, method: 'crypto', amount_cents: 15000, idempotency_key: 'pos-eft-0003' });
    expect(badMethod.status).toBe(400);
    const badStage = await post('/v1/payments/record', 'tech', { booking_id: BOOKING_CASH, method: 'cash', amount_cents: 15000, idempotency_key: 'pos-eft-0004', stage: 'later' });
    expect(badStage.status).toBe(400);
    expect(payments()).toHaveLength(0);
  });

  it('quotation payments infer their stage from the work order', async () => {
    const before = await post('/v1/payments/record', 'tech', { quotation_id: QUOTE, method: 'eft', reference: 'EFT-1', amount_cents: 250000, idempotency_key: 'pos-q-0001' });
    expect(before.status).toBe(201);
    expect(before.body.payment).toMatchObject({ quotation_id: QUOTE, booking_id: null, method: 'eft', stage: 'booking' });
  });
});

describe('POST /v1/work-orders/:id/checkin with payment', () => {
  const payment = { method: 'card_terminal', reference: '048213', amount_cents: 12000, idempotency_key: 'pos-ci-0001' };

  it('records the payment (stage checkin) and checks the car in, in one call', async () => {
    const r = await post(`/v1/work-orders/${WO_CONFIRMED}/checkin`, 'tech', { bay: 'Bay 2', payment });
    expect(r.status).toBe(201);
    expect(r.body.already).toBe(false);
    expect(r.body.work_order).toMatchObject({ id: WO_CONFIRMED, bay: 'Bay 2', checked_in_by: 'tech_1' });
    expect(r.body.work_order.checked_in_at).toBeTruthy();
    expect(r.body.payment).toMatchObject({ booking_id: BOOKING_CONFIRMED, method: 'card_terminal', provider_ref: '048213', amount_cents: 12000, status: 'successful', receipt_no: 'RCP-70001', recorded_by: 'tech_1', stage: 'checkin' });
    expect(payments()).toHaveLength(1);
    const checkin = db.rows('task_events').find((e) => e.event === 'checked_in')!;
    expect(checkin.metadata.payment_id).toBe(r.body.payment.id);
    expect(audits('work_order.check_in')[0].after).toMatchObject({ payment_id: r.body.payment.id, receipt_no: 'RCP-70001' });
    expect(audits('payment.record')).toHaveLength(1);
    // (The `paid` flag on the task feed's `work_order.booking` expansion is computed from these rows for
    // every booking; the fake Supabase does not resolve embedded selects, so it is not asserted here.)
  });

  it('a refused payment (wrong amount) leaves the work order unchecked; a replay with the same key is idempotent', async () => {
    const bad = await post(`/v1/work-orders/${WO_CONFIRMED}/checkin`, 'tech', { payment: { ...payment, amount_cents: 11000 } });
    expect(bad.status).toBe(400);
    expect(bad.body.error.details[0]).toMatchObject({ path: 'amount_cents', expected: 12000 });
    expect(wo(WO_CONFIRMED).checked_in_at ?? null).toBeNull();
    expect(payments()).toHaveLength(0);

    const ok = await post(`/v1/work-orders/${WO_CONFIRMED}/checkin`, 'tech', { payment });
    expect(ok.status).toBe(201);
    const again = await post(`/v1/work-orders/${WO_CONFIRMED}/checkin`, 'tech', { payment });
    expect(again.status).toBe(200);
    expect(again.body.already).toBe(true);
    expect(again.body.payment.id).toBe(ok.body.payment.id);
    expect(payments()).toHaveLength(1);
  });

  it('a second payment for an already paid booking is a 409, even at check-in', async () => {
    await post('/v1/payments/record', 'sup', { booking_id: BOOKING_CONFIRMED, method: 'cash', amount_cents: 12000, idempotency_key: 'pos-ci-0002' });
    const r = await post(`/v1/work-orders/${WO_CONFIRMED}/checkin`, 'tech', { payment });
    expect(r.status).toBe(409);
    expect(r.body.error.code).toBe('conflict');
    expect(wo(WO_CONFIRMED).checked_in_at ?? null).toBeNull();
  });

  it('check-in without a payment is unchanged', async () => {
    const r = await post(`/v1/work-orders/${WO_CONFIRMED}/checkin`, 'tech', {});
    expect(r.status).toBe(201);
    expect(r.body.payment).toBeNull();
    expect(payments()).toHaveLength(0);
    expect(wo(WO_CONFIRMED).checked_in_at).toBeTruthy();
  });

  it('settles a quotation-backed work order at check-in (payment on the quotation, stage checkin, quotation converted)', async () => {
    const r = await post(`/v1/work-orders/${WO_QUOTE}/checkin`, 'adm', { bay: 'Body 1', payment: { method: 'eft', reference: 'EFT-2200', amount_cents: 250000, idempotency_key: 'pos-ciq-0001' } });
    expect(r.status).toBe(201);
    expect(r.body.payment).toMatchObject({ quotation_id: QUOTE, booking_id: null, method: 'eft', provider_ref: 'EFT-2200', amount_cents: 250000, stage: 'checkin', recorded_by: 'adm_1' });
    expect(wo(WO_QUOTE).checked_in_at).toBeTruthy();
    expect(db.rows('quotations')[0].status).toBe('converted');
    const noRef = await post(`/v1/work-orders/${WO_QUOTE}/checkin`, 'adm', { payment: { method: 'eft', amount_cents: 250000, idempotency_key: 'pos-ciq-0002' } });
    expect(noRef.status).toBe(400);
  });

  it('is outlet-scoped like the check-in itself', async () => {
    const r = await post(`/v1/work-orders/${WO_CONFIRMED}/checkin`, 'other', { payment });
    expect(r.status).toBe(403);
    expect(payments()).toHaveLength(0);
    expect((await post(`/v1/work-orders/${WO_CONFIRMED}/checkin`, 'cust', { payment })).status).toBe(403);
  });
});

describe('POST /v1/bookings/:id/checkin with payment', () => {
  it('pays and checks in a pending (unpaid card) booking: confirmed by the payment, then in_service', async () => {
    const r = await post(`/v1/bookings/${BOOKING_PENDING}/checkin`, 'sup', { bay: 'Bay 1', priority: 1, payment: { method: 'cash', amount_cents: 12000, idempotency_key: 'pos-bci-0001' } });
    expect(r.status).toBe(201);
    expect(r.body.booking.status).toBe('in_service');
    expect(r.body.work_order).toMatchObject({ booking_id: BOOKING_PENDING, bay: 'Bay 1', priority: 1, checked_in_by: 'sup_1' });
    expect(r.body.payment).toMatchObject({ booking_id: BOOKING_PENDING, method: 'cash', amount_cents: 12000, status: 'successful', stage: 'checkin', recorded_by: 'sup_1' });
    expect(audits('booking.checkin')[0].after).toMatchObject({ payment_id: r.body.payment.id });
    expect(payments()).toHaveLength(1);
  });

  it('refuses a wrong amount before touching the booking', async () => {
    const r = await post(`/v1/bookings/${BOOKING_PENDING}/checkin`, 'sup', { payment: { method: 'cash', amount_cents: 1, idempotency_key: 'pos-bci-0002' } });
    expect(r.status).toBe(400);
    expect(booking(BOOKING_PENDING).status).toBe('pending');
    expect(db.rows('work_orders').some((w) => w.booking_id === BOOKING_PENDING)).toBe(false);
  });

  it('a dashboard admin can check in and take payment for a confirmed booking', async () => {
    const r = await post(`/v1/bookings/${BOOKING_CONFIRMED}/checkin`, 'adm', { payment: { method: 'card_terminal', reference: 'A1', amount_cents: 12000, idempotency_key: 'pos-bci-0003' } });
    expect(r.status).toBe(200);
    expect(r.body.created).toBe(false);
    expect(r.body.work_order.id).toBe(WO_CONFIRMED);
    expect(r.body.payment).toMatchObject({ recorded_by: 'adm_1', stage: 'checkin' });
    expect(booking(BOOKING_CONFIRMED).status).toBe('in_service');
  });
});

describe('POST /v1/work-orders/:id/pickup/verify with payment (cash on collection)', () => {
  it('still refuses the OTP while the cash balance is due, then records the payment (stage collection) and releases the keys in one call', async () => {
    const otp = await issueOtp();
    const due = await post(`/v1/work-orders/${WO_CASH}/pickup/verify`, 'sup', { otp });
    expect(due.status).toBe(409);
    expect(due.body.error.details).toMatchObject({ reason: 'payment_due', amount_cents: 15000, booking_id: BOOKING_CASH, method: 'cash' });
    expect(wo(WO_CASH).collected_at ?? null).toBeNull();

    const r = await post(`/v1/work-orders/${WO_CASH}/pickup/verify`, 'sup', { otp, payment: { method: 'cash', reference: 'till 2', amount_cents: 15000, idempotency_key: 'pos-hv-0001' } });
    expect(r.status).toBe(200);
    expect(r.body.collected).toBe(true);
    expect(r.body.payment).toMatchObject({ booking_id: BOOKING_CASH, method: 'cash', provider_ref: 'till 2', amount_cents: 15000, status: 'successful', receipt_no: 'RCP-70001', recorded_by: 'sup_1', stage: 'collection' });
    expect(r.body.work_order.pickup_otp).toBeNull();
    expect(wo(WO_CASH).collected_at).toBe(r.body.collected_at);
    const collected = db.rows('task_events').find((e) => e.event === 'collected')!;
    expect(collected.metadata).toMatchObject({ otp_attempts: 1, payment_id: r.body.payment.id });
    expect(audits('work_order.collected')[0].after).toMatchObject({ payment_id: r.body.payment.id, receipt_no: 'RCP-70001' });
    expect(audits('payment.record')[0].after).toMatchObject({ stage: 'collection', captured_by: 'sup_1' });
    expect(db.rows('notifications').filter((n) => n.template_key === 'payment_successful')).toHaveLength(1);
    expect(db.rows('notifications').filter((n) => n.template_key === 'vehicle_collected')).toHaveLength(1);
  });

  it('a wrong OTP after the payment keeps the payment (idempotent replay) and still withholds the keys', async () => {
    const otp = await issueOtp();
    const wrong = otp === '11111' ? '22222' : '11111';
    const payment = { method: 'card_terminal', reference: '9912', amount_cents: 15000, idempotency_key: 'pos-hv-0002' };
    const bad = await post(`/v1/work-orders/${WO_CASH}/pickup/verify`, 'tech', { otp: wrong, payment });
    expect(bad.status).toBe(409);
    expect(bad.body.error.code).toBe('invalid_otp');
    expect(payments()).toHaveLength(1);
    expect(wo(WO_CASH).collected_at ?? null).toBeNull();
    // Retrying with the right OTP and the same payment key does not double-charge.
    const ok = await post(`/v1/work-orders/${WO_CASH}/pickup/verify`, 'tech', { otp, payment });
    expect(ok.status).toBe(200);
    expect(ok.body.payment.id).toBe(payments()[0].id);
    expect(payments()).toHaveLength(1);
    // Paid elsewhere meanwhile → the hand-over without a payment goes through as before.
    expect(audits('payment.record')).toHaveLength(1);
  });

  it('a wrong amount refuses the whole call and the keys stay put', async () => {
    const otp = await issueOtp();
    const r = await post(`/v1/work-orders/${WO_CASH}/pickup/verify`, 'sup', { otp, payment: { method: 'cash', amount_cents: 100, idempotency_key: 'pos-hv-0003' } });
    expect(r.status).toBe(400);
    expect(payments()).toHaveLength(0);
    expect(wo(WO_CASH).collected_at ?? null).toBeNull();
  });
});

describe('customer pays an unpaid booking after check-in (POST /v1/payments/intents)', () => {
  it('creates a sandbox intent for an in-service booking (stage checkin) and confirms it', async () => {
    const r = await post('/v1/payments/intents', 'cust', { booking_id: BOOKING_CASH, idempotency_key: 'cust-intent-0001' });
    expect(r.status).toBe(201);
    expect(r.body.payment).toMatchObject({ booking_id: BOOKING_CASH, status: 'pending', amount_cents: 15000, stage: 'checkin' });
    expect(r.body.client_secret).toBeTruthy();
    const confirm = await post(`/v1/payments/${r.body.payment.id}/sandbox-confirm`, 'cust', { outcome: 'succeeded' });
    expect(confirm.status).toBe(200);
    expect(confirm.body.payment).toMatchObject({ status: 'successful', receipt_no: 'RCP-70001', stage: 'checkin' });
    // Paid in-app: the cash-on-collection balance is settled, so the hand-over no longer needs a counter payment.
    const otp = await issueOtp();
    const released = await post(`/v1/work-orders/${WO_CASH}/pickup/verify`, 'sup', { otp });
    expect(released.status).toBe(200);
    expect(released.body.payment).toBeNull();
  });

  it('records stage collection once the car is ready, and refuses someone else\'s booking', async () => {
    booking(BOOKING_CASH).status = 'completed';
    const r = await post('/v1/payments/intents', 'cust', { booking_id: BOOKING_CASH, idempotency_key: 'cust-intent-0002' });
    expect(r.status).toBe(201);
    expect(r.body.payment.stage).toBe('collection');
    const other = await post('/v1/payments/intents', 'cust2', { booking_id: BOOKING_CASH, idempotency_key: 'cust-intent-0003' });
    expect(other.status).toBe(403);
  });
});

describe('GET /v1/admin/work-orders payment state', () => {
  it('reports amount_due_cents, payment_method and the successful payment per work order', async () => {
    await post('/v1/payments/record', 'adm', { booking_id: BOOKING_CONFIRMED, method: 'eft', reference: 'EFT-9', amount_cents: 12000, idempotency_key: 'pos-adm-0001' });
    const r = await call(`/v1/admin/work-orders?outlet_id=${OUTLET}`, 'adm');
    expect(r.status).toBe(200);
    const byId = new Map(r.body.data.map((w: any) => [w.id, w]));
    expect(byId.get(WO_CONFIRMED)).toMatchObject({ amount_due_cents: 0, payment_method: 'card', payment: { method: 'eft', provider: 'pos', amount_cents: 12000, receipt_no: 'RCP-70001', stage: 'booking' } });
    expect(byId.get(WO_CASH)).toMatchObject({ amount_due_cents: 15000, payment_method: 'cash', payment: null });
    expect(byId.get(WO_QUOTE)).toMatchObject({ amount_due_cents: 250000, payment_method: null, payment: null });
  });
});
