import { createServer, type Server } from 'node:http';
import { afterAll, beforeAll, beforeEach, describe, expect, it } from 'vitest';
import { createApp } from '../src/app.js';
import { setFirebaseAuthForTests, setFirebaseMessagingForTests } from '../src/lib/firebase.js';
import { generatePickupOtp, otpMatches, PICKUP_OTP_PATTERN } from '../src/lib/otp.js';
import { setSupabaseClient } from '../src/lib/supabase.js';
import { ApiError } from '../src/middleware/errors.js';
import { resetRateLimits } from '../src/middleware/rateLimit.js';
import { invalidateFlags } from '../src/services/flags.js';
import { canSeePickupOtp, PICKUP_OTP_MAX_ATTEMPTS, resendPickupOtp, verifyPickup } from '../src/services/pickup.js';
import { transitionTask } from '../src/services/workflow.js';
import { fakeSupabase, type FakeSupabase } from './helpers/fakeSupabase.js';
import { makeCtx } from './helpers/context.js';

const OUTLET = 'a0000000-0000-4000-8000-000000000001';
const OTHER_OUTLET = 'a0000000-0000-4000-8000-000000000002';
const BOOKING = '10000000-0000-4000-8000-000000000001';
const WO = '30000000-0000-4000-8000-000000000001';
const TASK = '40000000-0000-4000-8000-000000000001';
const TEMPLATE = 'c0000000-0000-4000-8000-000000000002';

let db: FakeSupabase;
let server: Server;
let base: string;

beforeAll(async () => {
  server = createServer(createApp());
  await new Promise<void>((r) => server.listen(0, r));
  base = `http://127.0.0.1:${(server.address() as { port: number }).port}`;
  setFirebaseAuthForTests({
    verifyIdToken: async (token: string) => {
      const users: Record<string, string> = { cust: 'cust_1', sup: 'sup_1', tech: 'tech_1', other: 'cust_2' };
      if (users[token]) return { uid: users[token], email: `${token}@example.com` };
      throw new Error('bad token');
    },
    setCustomUserClaims: async () => undefined,
  } as any);
});
afterAll(() => server.close());

beforeEach(() => {
  db = fakeSupabase();
  db.seed('feature_flags', [{ key: 'auto_assignment', enabled: false }, { key: 'whatsapp_enabled', enabled: false }]);
  db.seed('profiles', [
    { id: 'tech_1', role: 'technician', full_name: 'Pieter', is_active: true, push_opt_in: true, whatsapp_opt_in: true, marketing_opt_in: false },
    { id: 'sup_1', role: 'supervisor', full_name: 'Johan', is_active: true, push_opt_in: true, whatsapp_opt_in: true, marketing_opt_in: false },
    { id: 'sup_other', role: 'supervisor', full_name: 'Elsewhere', is_active: true, push_opt_in: true, whatsapp_opt_in: true, marketing_opt_in: false },
    { id: 'cust_1', role: 'customer', full_name: 'naledi mokoena', phone: '+27831112222', is_active: true, push_opt_in: true, whatsapp_opt_in: true, marketing_opt_in: false },
    { id: 'cust_2', role: 'customer', full_name: 'Someone Else', is_active: true, push_opt_in: true, whatsapp_opt_in: true, marketing_opt_in: false },
  ]);
  db.seed('staff_outlets', [{ profile_id: 'sup_1', outlet_id: OUTLET }, { profile_id: 'tech_1', outlet_id: OUTLET }, { profile_id: 'sup_other', outlet_id: OTHER_OUTLET }]);
  db.seed('outlets', [{ id: OUTLET, name: 'Sparkling Sandton', timezone: 'Africa/Johannesburg' }]);
  db.seed('services', [{ id: 'svc_1', name: 'Express Wash', category: 'car_wash', duration_minutes: 20 }]);
  db.seed('vehicles', [{ id: 'veh_1', customer_id: 'cust_1', registration_no: 'HR 88 TS GP', make: 'Suzuki', model: 'Swift', is_active: true }]);
  db.seed('checklist_templates', [{ id: TEMPLATE, name: 'Express', category: 'car_wash', version: 2, status: 'published', steps: [
    { key: 'exterior', title: 'Exterior', type: 'confirm', required: true },
    { key: 'supervisor', title: 'Supervisor', type: 'supervisor_verify', required: false },
  ] }]);
  db.seed('bookings', [{ id: BOOKING, ref: 'SPK-2026-0091', customer_id: 'cust_1', vehicle_id: 'veh_1', outlet_id: OUTLET, service_id: 'svc_1', status: 'in_service', slot_start: '2026-09-09T08:00:00.000Z', slot_end: '2026-09-09T08:20:00.000Z', price_cents: 12000, discount_cents: 0, total_cents: 12000, points_pending: 0 }]);
  db.seed('work_orders', [{ id: WO, ref: 'WO-2026-4821', outlet_id: OUTLET, booking_id: BOOKING, vehicle_id: 'veh_1', customer_id: 'cust_1', service_id: 'svc_1', status: 'completed', priority: 2, bay: 'Bay 1', checklist_template_id: TEMPLATE, template_version: 2, assignee_id: 'tech_1', started_at: new Date().toISOString(), completed_at: new Date().toISOString(), due_at: null, pickup_otp: null, pickup_otp_issued_at: null, pickup_otp_verified_at: null, pickup_otp_verified_by: null, collected_at: null }]);
  db.seed('tasks', [{ id: TASK, work_order_id: WO, outlet_id: OUTLET, title: 'Express · HR 88 TS GP', seq: 1, assignee_id: 'tech_1', status: 'completed', priority: 2, started_at: new Date().toISOString(), completed_at: new Date().toISOString(), elapsed_seconds: 600 }]);
  db.seed('checklist_step_results', [{ work_order_id: WO, step_key: 'exterior', status: 'done' }]);
  db.seed('gamification_rules', [{ version: 3, status: 'published', rules: { task_completed: 25 } }]);
  db.seed('notification_templates', [
    { key: 'service_ready', channel: 'push', title: 'Ready', body: 'Your {{vehicle}} is ready at {{outlet}}. Collection OTP {{otp}}.', is_promotional: false, is_active: true },
    { key: 'pickup_otp', channel: 'push', title: 'Collection OTP', body: 'Show OTP {{otp}} at {{outlet}} to collect your {{vehicle}}.', is_promotional: false, is_active: true },
  ]);
  db.seed('device_tokens', [{ profile_id: 'cust_1', token: 'tok_c1', platform: 'android', app: 'customer' }]);
  setSupabaseClient(db as any);
  invalidateFlags();
  resetRateLimits();
  setFirebaseMessagingForTests({ sendEachForMulticast: async ({ tokens }: { tokens: string[] }) => ({ successCount: tokens.length, failureCount: 0, responses: tokens.map(() => ({ success: true })) }) } as any);
});

const sup = () => makeCtx('supervisor', 'sup_1', [OUTLET]);
const wo = () => db.rows('work_orders').find((w) => w.id === WO)!;

async function verifyWorkOrder(): Promise<string> {
  const r = await transitionTask(sup(), TASK, { to: 'verified' });
  expect(r.work_order.status).toBe('verified');
  return wo().pickup_otp as string;
}

async function call(path: string, token: string, init: RequestInit = {}) {
  const res = await fetch(`${base}${path}`, { ...init, headers: { Authorization: `Bearer ${token}`, 'Content-Type': 'application/json', ...(init.headers ?? {}) } });
  return { status: res.status, body: await res.json() as any };
}

describe('OTP generation', () => {
  it('produces cryptographically random 5-digit codes in 10000–99999', () => {
    const seen = new Set<string>();
    for (let i = 0; i < 300; i++) {
      const otp = generatePickupOtp();
      expect(otp).toMatch(PICKUP_OTP_PATTERN);
      expect(Number(otp)).toBeGreaterThanOrEqual(10000);
      expect(Number(otp)).toBeLessThanOrEqual(99999);
      seen.add(otp);
    }
    expect(seen.size).toBeGreaterThan(50);
  });
  it('compares OTPs safely', () => {
    expect(otpMatches('12345', '12345')).toBe(true);
    expect(otpMatches('12345', ' 12345 ')).toBe(true);
    expect(otpMatches('12345', '12346')).toBe(false);
    expect(otpMatches('12345', '1234')).toBe(false);
    expect(otpMatches(null, '12345')).toBe(false);
    expect(otpMatches('12345', '')).toBe(false);
  });
});

describe('verify → collection OTP issue (replicates legacy car pick-up)', () => {
  it('stores a 5-digit OTP on the work order, includes it in service_ready, never returns it to staff', async () => {
    const r = await transitionTask(sup(), TASK, { to: 'verified' });
    const w = wo();
    expect(w.pickup_otp).toMatch(PICKUP_OTP_PATTERN);
    expect(typeof w.pickup_otp_issued_at).toBe('string');
    expect(w.collected_at).toBeNull();
    expect(r.side_effects?.pickup_otp_issued).toBe(true);
    expect(r.side_effects?.booking_status).toBe('completed');
    expect((r.work_order as any).pickup_otp).toBeNull();
    expect(JSON.stringify(r)).not.toContain(w.pickup_otp);

    const n = db.rows('notifications').find((x) => x.template_key === 'service_ready')!;
    expect(n.body).toBe(`Your Suzuki Swift is ready at Sparkling Sandton. Collection OTP ${w.pickup_otp}.`);
    expect(n.payload.vars.otp).toBe(w.pickup_otp);
    expect(n.status).toBe('sent');
  });
});

describe('verifyPickup (staff hand-over)', () => {
  it('rejects before an OTP is issued', async () => {
    await expect(verifyPickup(sup(), WO, '12345')).rejects.toMatchObject({ code: 'conflict' });
  });

  it('409 invalid_otp with attempts_remaining, locks after 5 failures, records task_events + audit', async () => {
    const otp = await verifyWorkOrder();
    const wrong = otp === '11111' ? '22222' : '11111';
    for (let attempt = 1; attempt <= PICKUP_OTP_MAX_ATTEMPTS; attempt++) {
      const err = await verifyPickup(sup(), WO, wrong).catch((e) => e as ApiError);
      expect(err).toBeInstanceOf(ApiError);
      expect((err as ApiError).code).toBe('invalid_otp');
      expect((err as ApiError).status).toBe(409);
      expect((err as ApiError).details).toEqual({ attempts_remaining: PICKUP_OTP_MAX_ATTEMPTS - attempt, locked: attempt === PICKUP_OTP_MAX_ATTEMPTS });
    }
    const failures = db.rows('task_events').filter((e) => e.event === 'pickup_otp_failed');
    expect(failures).toHaveLength(5);
    expect(failures.map((e) => e.metadata.attempt)).toEqual([1, 2, 3, 4, 5]);
    expect(failures[4].metadata.attempts_remaining).toBe(0);
    expect(db.rows('audit_events').filter((a) => a.action === 'work_order.pickup_otp_failed')).toHaveLength(5);

    // locked: even the right OTP is refused now
    await expect(verifyPickup(sup(), WO, otp)).rejects.toMatchObject({ code: 'conflict', details: { locked: true, attempts: 5 } });
    expect(db.rows('task_events').filter((e) => e.event === 'pickup_otp_failed')).toHaveLength(5);
    expect(wo().collected_at).toBeNull();
  });

  it('marks the vehicle collected on the right OTP; booking stays completed; second verify conflicts', async () => {
    const otp = await verifyWorkOrder();
    const before = db.rows('bookings')[0].status;
    expect(before).toBe('completed');
    const out = await verifyPickup(sup(), WO, ` ${otp} `);
    expect(typeof out.collected_at).toBe('string');
    expect(out.work_order.pickup_otp).toBeNull(); // redacted for staff
    const w = wo();
    expect(w.collected_at).toBe(out.collected_at);
    expect(w.pickup_otp_verified_at).toBe(out.collected_at);
    expect(w.pickup_otp_verified_by).toBe('sup_1');
    expect(w.status).toBe('verified');
    expect(db.rows('bookings')[0].status).toBe('completed');
    const ev = db.rows('task_events').find((e) => e.event === 'collected')!;
    expect(ev).toMatchObject({ work_order_id: WO, task_id: TASK, actor_id: 'sup_1', metadata: { otp_attempts: 1 } });
    expect(db.rows('audit_events').some((a) => a.action === 'work_order.collected' && a.entity_id === WO)).toBe(true);

    await expect(verifyPickup(sup(), WO, otp)).rejects.toMatchObject({ code: 'conflict', details: { collected_at: out.collected_at } });
  });

  it('is restricted to staff of the outlet', async () => {
    const otp = await verifyWorkOrder();
    await expect(verifyPickup(makeCtx('supervisor', 'sup_other', [OTHER_OUTLET]), WO, otp)).rejects.toMatchObject({ code: 'forbidden' });
    await expect(verifyPickup(sup(), '30000000-0000-4000-8000-00000000dead', otp)).rejects.toMatchObject({ code: 'not_found' });
  });
});

describe('resendPickupOtp', () => {
  it('re-sends the same OTP via the pickup_otp template, rate-limited to once a minute', async () => {
    const otp = await verifyWorkOrder();
    // issued seconds ago → too soon
    await expect(resendPickupOtp(sup(), WO)).rejects.toMatchObject({ code: 'rate_limited' });

    wo().pickup_otp_issued_at = new Date(Date.now() - 120_000).toISOString();
    const out = await resendPickupOtp(sup(), WO);
    expect(out.notification.map((n) => [n.channel, n.status])).toEqual([['push', 'sent']]);
    expect(out.work_order.pickup_otp).toBeNull();
    expect(wo().pickup_otp).toBe(otp); // unchanged
    const n = db.rows('notifications').find((x) => x.template_key === 'pickup_otp')!;
    expect(n.body).toBe(`Show OTP ${otp} at Sparkling Sandton to collect your Suzuki Swift.`);
    expect(db.rows('task_events').filter((e) => e.event === 'pickup_otp_resent')).toHaveLength(1);
    expect(db.rows('audit_events').some((a) => a.action === 'work_order.pickup_otp_resend')).toBe(true);

    await expect(resendPickupOtp(sup(), WO)).rejects.toMatchObject({ code: 'rate_limited' });
  });

  it('refuses once collected or before issue', async () => {
    await expect(resendPickupOtp(sup(), WO)).rejects.toMatchObject({ code: 'conflict' });
    const otp = await verifyWorkOrder();
    await verifyPickup(sup(), WO, otp);
    await expect(resendPickupOtp(sup(), WO)).rejects.toMatchObject({ code: 'conflict' });
  });
});

describe('OTP visibility over the API', () => {
  it('canSeePickupOtp: owning customer only, while completed/verified and uncollected', () => {
    const w = { customer_id: 'cust_1', status: 'verified' as const, collected_at: null, pickup_otp: '12345' };
    expect(canSeePickupOtp(makeCtx('customer', 'cust_1').auth, w)).toBe(true);
    expect(canSeePickupOtp(makeCtx('customer', 'cust_1').auth, w, 'completed')).toBe(true);
    expect(canSeePickupOtp(makeCtx('customer', 'cust_1').auth, w, 'in_service')).toBe(false);
    expect(canSeePickupOtp(makeCtx('customer', 'cust_2').auth, w)).toBe(false);
    expect(canSeePickupOtp(makeCtx('supervisor', 'sup_1', [OUTLET]).auth, w)).toBe(false);
    expect(canSeePickupOtp(makeCtx('admin', 'adm').auth, w)).toBe(false);
    expect(canSeePickupOtp(makeCtx('customer', 'cust_1').auth, { ...w, collected_at: 'x' })).toBe(false);
    expect(canSeePickupOtp(makeCtx('customer', 'cust_1').auth, { ...w, status: 'in_progress' })).toBe(false);
  });

  it('GET /bookings/:id shows pickup_otp to the owning customer only while completed and uncollected; staff see collected_at only', async () => {
    const before = await call(`/v1/bookings/${BOOKING}`, 'cust');
    expect(before.status).toBe(200);
    expect(before.body.work_order.pickup_otp).toBeUndefined();

    const otp = await verifyWorkOrder();
    const mine = await call(`/v1/bookings/${BOOKING}`, 'cust');
    expect(mine.status).toBe(200);
    expect(mine.body.status).toBe('completed');
    expect(mine.body.work_order.pickup_otp).toBe(otp);
    expect(mine.body.work_order.collected_at).toBeNull();

    const staff = await call(`/v1/bookings/${BOOKING}`, 'sup');
    expect(staff.status).toBe(200);
    expect(staff.body.work_order.pickup_otp).toBeUndefined();
    expect(JSON.stringify(staff.body)).not.toContain(otp);
    expect(staff.body.work_order.collected_at).toBeNull();
    expect(staff.body.work_order.pickup_otp_verified_at).toBeNull();

    expect((await call(`/v1/bookings/${BOOKING}`, 'other')).status).toBe(403);

    // hand-over through the API
    const bad = await call(`/v1/work-orders/${WO}/pickup/verify`, 'sup', { method: 'POST', body: JSON.stringify({ otp: otp === '11111' ? '22222' : '11111' }) });
    expect(bad.status).toBe(409);
    expect(bad.body.error.code).toBe('invalid_otp');
    expect(bad.body.error.details.attempts_remaining).toBe(4);
    expect((await call(`/v1/work-orders/${WO}/pickup/verify`, 'sup', { method: 'POST', body: JSON.stringify({ otp: 'abc' }) })).status).toBe(400);
    expect((await call(`/v1/work-orders/${WO}/pickup/verify`, 'cust', { method: 'POST', body: JSON.stringify({ otp }) })).status).toBe(403);
    const ok = await call(`/v1/work-orders/${WO}/pickup/verify`, 'sup', { method: 'POST', body: JSON.stringify({ otp: Number(otp) }) });
    expect(ok.status).toBe(200);
    expect(ok.body.collected).toBe(true);
    expect(ok.body.work_order.pickup_otp).toBeNull();

    const after = await call(`/v1/bookings/${BOOKING}`, 'cust');
    expect(after.body.work_order.pickup_otp).toBeUndefined();
    expect(after.body.work_order.collected_at).toBe(ok.body.collected_at);
    const staffAfter = await call(`/v1/bookings/${BOOKING}`, 'sup');
    expect(staffAfter.body.work_order.collected_at).toBe(ok.body.collected_at);
    expect(staffAfter.body.work_order.pickup_otp_verified_at).toBe(ok.body.collected_at);
  });

  it('GET /work-orders/:id redacts the OTP for staff and shows it to the customer while verified and uncollected', async () => {
    const otp = await verifyWorkOrder();
    const staff = await call(`/v1/work-orders/${WO}`, 'tech');
    expect(staff.status).toBe(200);
    expect(staff.body.work_order.pickup_otp).toBeNull();
    expect(JSON.stringify(staff.body)).not.toContain(otp);
    const mine = await call(`/v1/work-orders/${WO}`, 'cust');
    expect(mine.body.work_order.pickup_otp).toBe(otp);

    const resendTooSoon = await call(`/v1/work-orders/${WO}/pickup/resend`, 'tech', { method: 'POST' });
    expect(resendTooSoon.status).toBe(429);
    wo().pickup_otp_issued_at = new Date(Date.now() - 120_000).toISOString();
    const resend = await call(`/v1/work-orders/${WO}/pickup/resend`, 'tech', { method: 'POST' });
    expect(resend.status).toBe(200);
    expect(resend.body.work_order.pickup_otp).toBeNull();
    expect(resend.body.notification).toEqual([{ channel: 'push', status: 'sent', id: expect.any(String) }]);

    await verifyPickup(sup(), WO, otp);
    const collected = await call(`/v1/work-orders/${WO}`, 'cust');
    expect(collected.body.work_order.pickup_otp).toBeNull();
    expect(collected.body.work_order.collected_at).toBeTruthy();
  });
});
