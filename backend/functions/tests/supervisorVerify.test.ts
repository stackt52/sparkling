/**
 * STF-033 follow-up: when the checklist reaches its `supervisor_verify` step (or the task is completed)
 * the task is flagged for the outlet supervisors — it joins their `GET /tasks?scope=mine` list and they
 * receive a `task_verify_requested` push at once.
 */
import { createServer, type Server } from 'node:http';
import { afterAll, beforeAll, beforeEach, describe, expect, it } from 'vitest';
import { createApp } from '../src/app.js';
import { setFirebaseAuthForTests, setFirebaseMessagingForTests } from '../src/lib/firebase.js';
import { setSupabaseClient } from '../src/lib/supabase.js';
import { resetRateLimits } from '../src/middleware/rateLimit.js';
import { invalidateFlags } from '../src/services/flags.js';
import { fakeSupabase, type FakeSupabase } from './helpers/fakeSupabase.js';

const OUTLET = 'a0000000-0000-4000-8000-000000000001';
const OTHER_OUTLET = 'a0000000-0000-4000-8000-000000000002';
const BOOKING = '10000000-0000-4000-8000-000000000001';
const WO = '30000000-0000-4000-8000-000000000001';
const TASK = '40000000-0000-4000-8000-000000000001';
const TEMPLATE = 'c0000000-0000-4000-8000-000000000002';
const TEMPLATE_NO_SUP = 'c0000000-0000-4000-8000-000000000003';

let db: FakeSupabase;
let server: Server;
let base: string;
let pushes: Array<{ tokens: string[]; title: string; data: Record<string, string> }>;

beforeAll(async () => {
  server = createServer(createApp());
  await new Promise<void>((r) => server.listen(0, r));
  base = `http://127.0.0.1:${(server.address() as { port: number }).port}`;
  setFirebaseAuthForTests({
    verifyIdToken: async (token: string) => {
      const users: Record<string, string> = { sup: 'sup_1', sup2: 'sup_2', tech: 'tech_1', supother: 'sup_other', manager: 'mgr_1' };
      if (users[token]) return { uid: users[token], email: `${token}@example.com` };
      throw new Error('bad token');
    },
    setCustomUserClaims: async () => undefined,
  } as any);
});
afterAll(() => server.close());

beforeEach(() => {
  db = fakeSupabase();
  pushes = [];
  db.seed('feature_flags', [{ key: 'auto_assignment', enabled: false }, { key: 'whatsapp_enabled', enabled: false }]);
  db.seed('profiles', [
    { id: 'tech_1', role: 'technician', full_name: 'Pieter', is_active: true, push_opt_in: true, whatsapp_opt_in: true, marketing_opt_in: false },
    { id: 'sup_1', role: 'supervisor', full_name: 'Johan', is_active: true, push_opt_in: true, whatsapp_opt_in: true, marketing_opt_in: false },
    { id: 'sup_2', role: 'supervisor', full_name: 'Lerato', is_active: true, push_opt_in: true, whatsapp_opt_in: true, marketing_opt_in: false },
    { id: 'sup_gone', role: 'supervisor', full_name: 'Left', is_active: false, push_opt_in: true, whatsapp_opt_in: true, marketing_opt_in: false },
    { id: 'mgr_1', role: 'manager', full_name: 'Manager', is_active: true, push_opt_in: true, whatsapp_opt_in: true, marketing_opt_in: false },
    { id: 'sup_other', role: 'supervisor', full_name: 'Elsewhere', is_active: true, push_opt_in: true, whatsapp_opt_in: true, marketing_opt_in: false },
    { id: 'cust_1', role: 'customer', full_name: 'naledi mokoena', phone: '+27831112222', is_active: true, push_opt_in: true, whatsapp_opt_in: true, marketing_opt_in: false },
  ]);
  db.seed('staff_outlets', [
    { profile_id: 'sup_1', outlet_id: OUTLET },
    { profile_id: 'sup_2', outlet_id: OUTLET },
    { profile_id: 'sup_gone', outlet_id: OUTLET },
    { profile_id: 'mgr_1', outlet_id: OUTLET },
    { profile_id: 'tech_1', outlet_id: OUTLET },
    { profile_id: 'sup_other', outlet_id: OTHER_OUTLET },
  ]);
  db.seed('outlets', [{ id: OUTLET, name: 'Sparkling Sandton', timezone: 'Africa/Johannesburg' }]);
  db.seed('services', [{ id: 'svc_1', name: 'Express Wash', category: 'car_wash', duration_minutes: 20 }]);
  db.seed('vehicles', [{ id: 'veh_1', customer_id: 'cust_1', registration_no: 'HR 88 TS GP', make: 'Suzuki', model: 'Swift', is_active: true }]);
  db.seed('checklist_templates', [
    { id: TEMPLATE, name: 'Express', category: 'car_wash', version: 2, status: 'published', steps: [
      { key: 'exterior', title: 'Exterior', type: 'confirm', required: true },
      { key: 'interior', title: 'Interior', type: 'confirm', required: true },
      { key: 'supervisor', title: 'Supervisor', type: 'supervisor_verify', required: false },
    ] },
    { id: TEMPLATE_NO_SUP, name: 'Quick', category: 'car_wash', version: 1, status: 'published', steps: [
      { key: 'exterior', title: 'Exterior', type: 'confirm', required: true },
    ] },
  ]);
  db.seed('bookings', [{ id: BOOKING, ref: 'SPK-2026-0091', customer_id: 'cust_1', vehicle_id: 'veh_1', outlet_id: OUTLET, service_id: 'svc_1', status: 'in_service', slot_start: '2026-09-09T08:00:00.000Z', slot_end: '2026-09-09T08:20:00.000Z', price_cents: 12000, discount_cents: 0, total_cents: 12000, points_pending: 0 }]);
  db.seed('work_orders', [{ id: WO, ref: 'WO-2026-4821', outlet_id: OUTLET, booking_id: BOOKING, vehicle_id: 'veh_1', customer_id: 'cust_1', service_id: 'svc_1', status: 'in_progress', priority: 2, bay: 'Bay 1', checklist_template_id: TEMPLATE, template_version: 2, assignee_id: 'tech_1', started_at: new Date().toISOString(), checked_in_at: new Date().toISOString(), completed_at: null, due_at: null, pickup_otp: null, collected_at: null }]);
  db.seed('tasks', [{ id: TASK, work_order_id: WO, outlet_id: OUTLET, title: 'Express · HR 88 TS GP', seq: 1, assignee_id: 'tech_1', status: 'in_progress', priority: 2, started_at: new Date().toISOString(), completed_at: null, elapsed_seconds: 60, verification_requested_at: null }]);
  db.seed('checklist_step_results', [{ work_order_id: WO, step_key: 'exterior', status: 'done', client_op_id: 'seed-ext' }]);
  db.seed('gamification_rules', [{ version: 3, status: 'published', rules: { task_completed: 25 } }]);
  db.seed('notification_templates', [
    { key: 'task_verify_requested', channel: 'push', title: 'Verification needed', body: '{{ref}} · {{service}} · bay {{bay}} is ready for your sign-off.', is_promotional: false, is_active: true },
    { key: 'stage_changed', channel: 'push', title: 'Progress update', body: '{{vehicle}}: {{stage}} complete.', is_promotional: false, is_active: true },
    { key: 'service_ready', channel: 'push', title: 'Ready', body: 'Your {{vehicle}} is ready at {{outlet}}. Collection OTP {{otp}}.', is_promotional: false, is_active: true },
  ]);
  db.seed('device_tokens', [
    { profile_id: 'sup_1', token: 'tok_s1', platform: 'android', app: 'staff' },
    { profile_id: 'sup_2', token: 'tok_s2', platform: 'ios', app: 'staff' },
    { profile_id: 'sup_other', token: 'tok_so', platform: 'android', app: 'staff' },
    { profile_id: 'tech_1', token: 'tok_t1', platform: 'android', app: 'staff' },
    { profile_id: 'cust_1', token: 'tok_c1', platform: 'android', app: 'customer' },
  ]);
  setSupabaseClient(db as any);
  invalidateFlags();
  resetRateLimits();
  setFirebaseMessagingForTests({
    sendEachForMulticast: async ({ tokens, notification, data }: { tokens: string[]; notification: { title: string }; data: Record<string, string> }) => {
      pushes.push({ tokens, title: notification.title, data });
      return { successCount: tokens.length, failureCount: 0, responses: tokens.map(() => ({ success: true })) };
    },
  } as any);
});

async function call(path: string, token: string, init: RequestInit = {}) {
  const res = await fetch(`${base}${path}`, { ...init, headers: { Authorization: `Bearer ${token}`, 'Content-Type': 'application/json', ...(init.headers ?? {}) } });
  return { status: res.status, body: (await res.json()) as any };
}
const step = (key: string, token: string, op: string) => call(`/v1/work-orders/${WO}/steps/${key}`, token, { method: 'POST', body: JSON.stringify({ status: 'done', value: true, client_op_id: op }) });
const transition = (to: string, token: string, op: string) => call(`/v1/tasks/${TASK}/transition`, token, { method: 'POST', body: JSON.stringify({ to, client_op_id: op }) });
const verifyPushes = () => pushes.filter((p) => p.data.template === 'task_verify_requested');
const verifyRows = () => db.rows('notifications').filter((n) => n.template_key === 'task_verify_requested');
const task = () => db.rows('tasks').find((t) => t.id === TASK)!;

describe('supervisor verification request', () => {
  it('flags the task and pushes every active outlet supervisor when the timeline reaches the supervisor step', async () => {
    const r = await step('interior', 'tech', 'op-int-1');
    expect(r.status, JSON.stringify(r.body)).toBe(200);
    expect(task().verification_requested_at).toBeTruthy();
    expect(task().status).toBe('in_progress');

    const sent = verifyPushes();
    expect(sent.map((p) => p.tokens).flat().sort()).toEqual(['tok_s1', 'tok_s2']);
    expect(sent[0]).toMatchObject({ title: 'Verification needed', data: { type: 'task', task_id: TASK, work_order_id: WO, booking_id: BOOKING } });
    expect(verifyRows().map((n) => n.recipient_id).sort()).toEqual(['sup_1', 'sup_2']);
    expect(verifyRows()[0]).toMatchObject({ status: 'sent', body: 'WO-2026-4821 · Express Wash · bay Bay 1 is ready for your sign-off.' });
    expect(db.rows('task_events').some((e) => e.event === 'verification_requested' && e.task_id === TASK && e.metadata?.step_key === 'supervisor')).toBe(true);
  });

  it('does not request while an earlier step is still open', async () => {
    db.rows('checklist_step_results').length = 0; // exterior not done yet
    const r = await step('interior', 'tech', 'op-int-2');
    expect(r.status).toBe(200);
    expect(task().verification_requested_at ?? null).toBeNull();
    expect(verifyPushes()).toHaveLength(0);
  });

  it('shows the task on the outlet supervisors\' Mine tab, not on other outlets\' or the technician twice', async () => {
    const before = await call('/v1/tasks?scope=mine', 'sup');
    expect(before.body.data).toHaveLength(0);

    await step('interior', 'tech', 'op-int-3');
    const mine = await call('/v1/tasks?scope=mine', 'sup');
    expect(mine.status).toBe(200);
    expect(mine.body.data.map((t: any) => t.id)).toEqual([TASK]);
    expect(mine.body.data[0]).toMatchObject({ assignee_id: 'tech_1', status: 'in_progress', verification_requested_at: expect.any(String) });

    const other = await call('/v1/tasks?scope=mine', 'supother');
    expect(other.body.data).toHaveLength(0);
    const tech = await call('/v1/tasks?scope=mine', 'tech');
    expect(tech.body.data.map((t: any) => t.id)).toEqual([TASK]);
    const managerMine = await call(`/v1/tasks?scope=mine&outlet_id=${OUTLET}`, 'manager');
    expect(managerMine.body.data.map((t: any) => t.id)).toEqual([TASK]);
  });

  it('is requested once per completion: completing the task after the step does not re-notify, verifying removes it from Mine', async () => {
    await step('interior', 'tech', 'op-int-4');
    const done = await transition('completed', 'tech', 'op-done-4');
    expect(done.status, JSON.stringify(done.body)).toBe(200);
    expect(done.body.side_effects?.verification_requested).toBeUndefined();
    expect(verifyRows()).toHaveLength(2);

    const verified = await transition('verified', 'sup', 'op-ver-4');
    expect(verified.status, JSON.stringify(verified.body)).toBe(200);
    const mine = await call('/v1/tasks?scope=mine', 'sup');
    expect(mine.body.data).toHaveLength(0);
  });

  it('rework clears the flag and a second completion asks again', async () => {
    await step('interior', 'tech', 'op-int-5');
    await transition('completed', 'tech', 'op-done-5');
    const rework = await transition('in_progress', 'tech', 'op-re-5');
    expect(rework.status, JSON.stringify(rework.body)).toBe(200);
    expect(rework.body.task.verification_requested_at ?? null).toBeNull();
    expect((await call('/v1/tasks?scope=mine', 'sup')).body.data).toHaveLength(0);

    const again = await transition('completed', 'tech', 'op-done-5b');
    expect(again.status).toBe(200);
    expect(again.body.task.verification_requested_at).toBeTruthy();
    expect(again.body.side_effects.verification_requested.supervisors_notified.sort()).toEqual(['sup_1', 'sup_2']);
    expect(verifyRows()).toHaveLength(4);
  });

  it('completing a task whose template has no supervisor step still asks for sign-off', async () => {
    db.rows('work_orders')[0].checklist_template_id = TEMPLATE_NO_SUP;
    const done = await transition('completed', 'tech', 'op-done-6');
    expect(done.status, JSON.stringify(done.body)).toBe(200);
    expect(done.body.task.verification_requested_at).toBeTruthy();
    expect(verifyPushes().map((p) => p.tokens).flat().sort()).toEqual(['tok_s1', 'tok_s2']);
  });

  it('a supervisor finishing the last step is not pushed about their own work; the other supervisor is', async () => {
    await step('interior', 'sup', 'op-int-7');
    expect(verifyRows().map((n) => n.recipient_id)).toEqual(['sup_2']);
  });

  it('falls back to the outlet managers when it has no supervisor', async () => {
    db.rows('staff_outlets').splice(0, db.rows('staff_outlets').length, { profile_id: 'mgr_1', outlet_id: OUTLET }, { profile_id: 'tech_1', outlet_id: OUTLET });
    await step('interior', 'tech', 'op-int-8');
    expect(verifyRows().map((n) => n.recipient_id)).toEqual(['mgr_1']);
  });
});
