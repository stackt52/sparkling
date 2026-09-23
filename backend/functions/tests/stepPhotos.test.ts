import { createServer, type Server } from 'node:http';
import { afterAll, beforeAll, beforeEach, describe, expect, it } from 'vitest';
import { createApp } from '../src/app.js';
import { setFirebaseAuthForTests, setFirebaseMessagingForTests } from '../src/lib/firebase.js';
import { setSupabaseClient } from '../src/lib/supabase.js';
import { setObjectStorageForTests } from '../src/lib/storage.js';
import { MemoryObjectStorage } from './helpers/fakeStorage.js';
import { resetRateLimits } from '../src/middleware/rateLimit.js';
import { invalidateFlags } from '../src/services/flags.js';
import { fakeSupabase, type FakeSupabase } from './helpers/fakeSupabase.js';

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
      const users: Record<string, string> = { cust: 'cust_1', sup: 'sup_1', tech: 'tech_1', other: 'cust_2', supother: 'sup_other' };
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





const PNG_1x1 = Buffer.from('iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNkYPhfDwAChwGA60e6kgAAAABJRU5ErkJggg==', 'base64');
let storage: MemoryObjectStorage;

async function callRaw(path: string, token: string, init: RequestInit = {}) {
  const res = await fetch(`${base}${path}`, { ...init, headers: { Authorization: `Bearer ${token}`, ...(init.headers ?? {}) } });
  const buf = Buffer.from(await res.arrayBuffer());
  let body: any = buf;
  try { body = JSON.parse(buf.toString('utf8')); } catch { /* binary */ }
  return { status: res.status, body, headers: res.headers };
}
async function upload(workOrderId: string, token: string, bytes: Buffer, stepKey?: string) {
  const fd = new FormData();
  fd.append('photo', new Blob([bytes], { type: 'image/png' }), 'step.png');
  if (stepKey) fd.append('step_key', stepKey);
  return callRaw(`/v1/work-orders/${workOrderId}/photos`, token, { method: 'POST', body: fd });
}
function stepKeyOf(): string {
  const t = db.rows('checklist_templates')[0] as { steps: Array<{ key: string; type?: string }> };
  return (t.steps.find((s) => s.type === 'photo') ?? t.steps[0]).key;
}

describe('checklist step photos', () => {
  beforeEach(() => {
    storage = new MemoryObjectStorage();
    setObjectStorageForTests(storage);
  });
  afterAll(() => setObjectStorageForTests(null));

  it('uploads a photo for the work order, then the step is submitted with its attachment id', async () => {
    const key = stepKeyOf();
    const up = await upload(WO, 'tech', PNG_1x1, key);
    expect(up.status).toBe(201);
    expect(up.body.attachment).toMatchObject({ kind: 'step_photo', step_key: key, mime_type: 'image/png', width: 1, height: 1, url: expect.stringMatching(new RegExp(`/v1/work-orders/${WO}/photos/`)) });
    const attId = up.body.attachment.id as string;
    expect(db.rows('attachments').find((a) => a.id === attId)).toMatchObject({ entity_type: 'checklist_step', entity_id: WO, uploaded_by: 'tech_1' });
    expect(storage.objects.size).toBe(1);

    const step = await callRaw(`/v1/work-orders/${WO}/steps/${key}`, 'tech', { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({ status: 'done', attachment_id: attId, client_op_id: 'op-step-photo-1' }) });
    expect(step.status, JSON.stringify(step.body)).toBe(200);
    expect(db.rows('checklist_step_results').find((r) => r.work_order_id === WO && r.step_key === key)).toMatchObject({ status: 'done', attachment_id: attId });

    const img = await callRaw(`/v1/work-orders/${WO}/photos/${attId}`, 'sup');
    expect(img.status).toBe(200);
    expect(img.headers.get('content-type')).toBe('image/png');
    expect(Buffer.isBuffer(img.body) ? img.body.length : 0).toBe(PNG_1x1.length);
  });

  it('rejects unknown attachment ids, non-images and other outlets', async () => {
    const key = stepKeyOf();
    const bogus = await callRaw(`/v1/work-orders/${WO}/steps/${key}`, 'tech', { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({ status: 'done', attachment_id: '5a0f1c2d-3e4b-4a6c-8d8e-9f0100000000', client_op_id: 'op-step-photo-2' }) });
    expect(bogus.status).toBe(400);
    expect((bogus.body.error?.message ?? '') as string).toMatch(/upload the photo/);
    const notImage = await upload(WO, 'tech', Buffer.from('not an image'), key);
    expect(notImage.status).toBe(400);
    const foreign = await upload(WO, 'supother', PNG_1x1, key);
    expect(foreign.status).toBe(403);
    const customer = await upload(WO, 'cust', PNG_1x1, key);
    expect(customer.status).toBe(403);
  });
});
