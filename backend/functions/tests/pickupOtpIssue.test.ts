/**
 * Dashboard "Generate collection OTP" (`POST /work-orders/:id/pickup/issue`): a manager / admin / director
 * issues a fresh 5-digit code for a verified, uncollected work order — when the customer never received
 * it, lost it, or the order is locked after five wrong attempts. The old code stops working, the attempt
 * counter restarts, the customer is sent the new code (unless `notify:false`) and the code is returned.
 */
import { createServer, type Server } from 'node:http';
import { afterAll, beforeAll, beforeEach, describe, expect, it } from 'vitest';
import { createApp } from '../src/app.js';
import { setFirebaseAuthForTests, setFirebaseMessagingForTests } from '../src/lib/firebase.js';
import { PICKUP_OTP_PATTERN } from '../src/lib/otp.js';
import { setSupabaseClient } from '../src/lib/supabase.js';
import { resetRateLimits } from '../src/middleware/rateLimit.js';
import { invalidateFlags } from '../src/services/flags.js';
import { PICKUP_OTP_MAX_ATTEMPTS, verifyPickup } from '../src/services/pickup.js';
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
      const users: Record<string, string> = { mgr: 'mgr_1', adm: 'adm_1', sup: 'sup_1', tech: 'tech_1', mgr_other: 'mgr_other', cust: 'cust_1' };
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
    { id: 'mgr_1', role: 'manager', full_name: 'Ayesha', is_active: true, push_opt_in: true, whatsapp_opt_in: true, marketing_opt_in: false },
    { id: 'mgr_other', role: 'manager', full_name: 'Elsewhere', is_active: true, push_opt_in: true, whatsapp_opt_in: true, marketing_opt_in: false },
    { id: 'adm_1', role: 'admin', full_name: 'Admin', is_active: true, push_opt_in: true, whatsapp_opt_in: true, marketing_opt_in: false },
    { id: 'cust_1', role: 'customer', full_name: 'naledi mokoena', phone: '+27831112222', is_active: true, push_opt_in: true, whatsapp_opt_in: true, marketing_opt_in: false },
  ]);
  db.seed('staff_outlets', [{ profile_id: 'sup_1', outlet_id: OUTLET }, { profile_id: 'tech_1', outlet_id: OUTLET }, { profile_id: 'mgr_1', outlet_id: OUTLET }, { profile_id: 'mgr_other', outlet_id: OTHER_OUTLET }]);
  db.seed('outlets', [{ id: OUTLET, name: 'Sparkling Sandton', timezone: 'Africa/Johannesburg' }, { id: OTHER_OUTLET, name: 'Sparkling Pretoria', timezone: 'Africa/Johannesburg' }]);
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
    { key: 'vehicle_collected', channel: 'push', title: 'Keys collected', body: 'Your {{vehicle}} was collected from {{outlet}} at {{time}}.', is_promotional: false, is_active: true },
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
const issue = (token: string, body: unknown = {}) => call(`/v1/work-orders/${WO}/pickup/issue`, token, { method: 'POST', body: JSON.stringify(body) });
const pickupNotifications = () => db.rows('notifications').filter((n) => n.template_key === 'pickup_otp');

describe('POST /v1/work-orders/:id/pickup/issue', () => {
  it('manager generates a fresh code: stored, returned, sent to the customer, event + audit; the old code stops working', async () => {
    const old = await verifyWorkOrder();
    const r = await issue('mgr', { reason: 'Customer never received the WhatsApp' });
    expect(r.status, JSON.stringify(r.body)).toBe(200);
    const { otp, issued_at, notification, retry_after_seconds, work_order } = r.body;
    expect(otp).toMatch(PICKUP_OTP_PATTERN);
    expect(otp).not.toBe(old);
    expect(wo().pickup_otp).toBe(otp);
    expect(wo().pickup_otp_issued_at).toBe(issued_at);
    expect(retry_after_seconds).toBe(60);
    // The work order row itself is still redacted for staff; only the dedicated `otp` field carries the code.
    expect(work_order.pickup_otp).toBeNull();
    expect(notification.map((n: any) => [n.channel, n.status])).toEqual([['push', 'sent']]);
    const sent = pickupNotifications();
    expect(sent).toHaveLength(1);
    expect(sent[0].body).toBe(`Show OTP ${otp} at Sparkling Sandton to collect your Suzuki Swift.`);
    const ev = db.rows('task_events').find((e) => e.event === 'pickup_otp_issued')!;
    expect(ev).toMatchObject({ work_order_id: WO, task_id: TASK, actor_id: 'mgr_1', reason: 'Customer never received the WhatsApp' });
    expect(ev.metadata).toMatchObject({ reissued: true, previous_attempts: 0, notified: true, channels: ['push:sent'] });
    const a = db.rows('audit_events').find((x) => x.action === 'work_order.pickup_otp_issue')!;
    expect(a.after).toMatchObject({ reissued: true, reason: 'Customer never received the WhatsApp', notified: true, revealed_to: 'mgr_1' });

    await expect(verifyPickup(sup(), WO, old)).rejects.toMatchObject({ code: 'invalid_otp' });
    const ok = await verifyPickup(sup(), WO, otp);
    expect(ok.collected_at).toBeTruthy();
    expect(wo().collected_at).toBe(ok.collected_at);
  });

  it('unlocks an order after five wrong attempts: the counter restarts with the new code', async () => {
    const old = await verifyWorkOrder();
    for (let i = 0; i < PICKUP_OTP_MAX_ATTEMPTS; i++) {
      await expect(verifyPickup(sup(), WO, '00000')).rejects.toMatchObject({ code: 'invalid_otp' });
    }
    await expect(verifyPickup(sup(), WO, old)).rejects.toMatchObject({ code: 'conflict', details: { locked: true } });

    const r = await issue('adm', { reason: 'locked' });
    expect(r.status, JSON.stringify(r.body)).toBe(200);
    expect(db.rows('task_events').find((e) => e.event === 'pickup_otp_issued')!.metadata).toMatchObject({ previous_attempts: PICKUP_OTP_MAX_ATTEMPTS });
    // One wrong attempt against the new code is counted from zero again …
    await expect(verifyPickup(sup(), WO, '00000')).rejects.toMatchObject({ code: 'invalid_otp', details: { attempts_remaining: PICKUP_OTP_MAX_ATTEMPTS - 1 } });
    // … and the right new code releases the keys.
    const ok = await verifyPickup(sup(), WO, r.body.otp);
    expect(ok.collected_at).toBeTruthy();
  });

  it('notify:false keeps the code for the counter only', async () => {
    await verifyWorkOrder();
    const r = await issue('mgr', { notify: false });
    expect(r.status).toBe(200);
    expect(r.body.notification).toEqual([]);
    expect(pickupNotifications()).toHaveLength(0);
    expect(db.rows('audit_events').find((x) => x.action === 'work_order.pickup_otp_issue')!.after).toMatchObject({ notified: false });
  });

  it('is manager-and-up, scoped to the outlet, and only for verified, uncollected work', async () => {
    expect((await issue('sup')).status).toBe(403);
    expect((await issue('tech')).status).toBe(403);
    expect((await issue('cust')).status).toBe(403);
    // Not verified yet → 409 (no code to replace / none due yet).
    const early = await issue('mgr');
    expect(early.status).toBe(409);
    expect(early.body.error.details).toMatchObject({ status: 'completed' });
    const otp = await verifyWorkOrder();
    expect((await issue('mgr_other')).status).toBe(403);
    await verifyPickup(sup(), WO, otp);
    const done = await issue('mgr');
    expect(done.status).toBe(409);
    expect(done.body.error.details.collected_at).toBeTruthy();
  });
});
