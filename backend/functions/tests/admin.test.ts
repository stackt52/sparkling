import { createServer, type Server } from 'node:http';
import { afterAll, beforeAll, beforeEach, describe, expect, it } from 'vitest';
import { createApp } from '../src/app.js';
import { setFirebaseAuthForTests } from '../src/lib/firebase.js';
import { setSupabaseClient } from '../src/lib/supabase.js';
import { resetRateLimits } from '../src/middleware/rateLimit.js';
import { SandboxProvider, setPaymentProviderForTests } from '../src/services/payments.js';
import { fakeSupabase, type FakeSupabase } from './helpers/fakeSupabase.js';

const OUTLET_A = 'a0000000-0000-4000-8000-000000000001';
const OUTLET_B = 'a0000000-0000-4000-8000-000000000002';
const SERVICE_1 = 'b0000000-0000-4000-8000-000000000001';
const SERVICE_2 = 'b0000000-0000-4000-8000-000000000002';
const BOOKING_1 = '10000000-0000-4000-8000-000000000001';
const BOOKING_2 = '10000000-0000-4000-8000-000000000002';

let server: Server;
let base: string;
let db: FakeSupabase;
const fbCalls: unknown[][] = [];

beforeAll(async () => {
  server = createServer(createApp());
  await new Promise<void>((r) => server.listen(0, r));
  base = `http://127.0.0.1:${(server.address() as { port: number }).port}`;
  setFirebaseAuthForTests({
    verifyIdToken: async (token: string) => {
      const users: Record<string, string> = { admin: 'uid_admin', manager: 'uid_manager', finance: 'uid_finance', customer: 'uid_customer', fresh: 'uid_fresh', stale: 'uid_fresh' };
      if (users[token]) return { uid: users[token], email: `${token}@example.com`, auth_time: Math.floor(Date.now() / 1000) - (token === 'stale' ? 3600 : 30) };
      throw new Error('bad token');
    },
    setCustomUserClaims: async () => undefined,
    getUserByEmail: async (email: string) => {
      if (email === 'existing@example.com') return { uid: 'uid_existing', email };
      throw new Error('auth/user-not-found');
    },
    createUser: async (u: { email: string }) => { fbCalls.push(['createUser', u]); return { uid: `uid_new_${u.email.split('@')[0]}`, email: u.email }; },
    updateUser: async (uid: string, patch: unknown) => { fbCalls.push(['updateUser', uid, patch]); return { uid }; },
    revokeRefreshTokens: async (uid: string) => { fbCalls.push(['revoke', uid]); },
    generatePasswordResetLink: async () => 'https://example.test/reset',
  } as any);
  setPaymentProviderForTests(new SandboxProvider('s3cret'));
});
afterAll(() => server.close());

beforeEach(() => {
  fbCalls.length = 0;
  db = fakeSupabase();
  db.seed('profiles', [
    { id: 'uid_admin', role: 'admin', full_name: 'Ada Admin', email: 'admin@example.com', is_active: true },
    { id: 'uid_manager', role: 'manager', full_name: 'Musa Manager', email: 'manager@example.com', is_active: true },
    { id: 'uid_finance', role: 'finance', full_name: 'Fikile Finance', email: 'finance@example.com', is_active: true },
    { id: 'uid_customer', role: 'customer', full_name: 'Thabo', email: 'customer@example.com', is_active: true },
    { id: 'uid_fresh', role: 'technician', full_name: 'Fresh Tech', email: 'fresh@example.com', is_active: true, must_change_password: true },
  ]);
  db.seed('staff_outlets', [{ profile_id: 'uid_manager', outlet_id: OUTLET_A, is_primary: true }]);
  db.seed('feature_flags', [{ key: 'whatsapp_enabled', enabled: false }, { key: 'payments_sandbox', enabled: true }]);
  db.seed('outlets', [{ id: OUTLET_A, name: 'Sparkling Sandton', timezone: 'Africa/Johannesburg' }, { id: OUTLET_B, name: 'Sparkling Rosebank', timezone: 'Africa/Johannesburg' }]);
  db.seed('services', [{ id: SERVICE_1, name: 'Full Valet', category: 'car_wash' }, { id: SERVICE_2, name: 'Dent repair', category: 'auto_body' }]);
  db.seed('outlet_services', [
    { outlet_id: OUTLET_A, service_id: SERVICE_1, price_cents: 19800, is_available: true },
    { outlet_id: OUTLET_A, service_id: SERVICE_2, price_cents: null, is_available: false },
    { outlet_id: OUTLET_B, service_id: SERVICE_1, price_cents: null, is_available: true },
  ]);
  db.seed('bookings', [
    { id: BOOKING_1, ref: 'SPK-2026-0001', customer_id: 'uid_customer', outlet_id: OUTLET_A, service_id: SERVICE_1, status: 'completed', slot_start: '2026-09-02T08:00:00.000Z', total_cents: 19800 },
    { id: BOOKING_2, ref: 'SPK-2026-0002', customer_id: 'uid_customer', outlet_id: OUTLET_B, service_id: SERVICE_2, status: 'cancelled', slot_start: '2026-09-03T08:00:00.000Z', total_cents: 50000 },
    { id: '10000000-0000-4000-8000-000000000003', ref: 'SPK-2026-0003', customer_id: 'uid_customer', outlet_id: OUTLET_A, service_id: SERVICE_1, status: 'confirmed', slot_start: '2026-10-01T08:00:00.000Z', total_cents: 19800 },
  ]);
  db.seed('payments', [
    { id: '60000000-0000-4000-8000-000000000001', booking_id: BOOKING_1, customer_id: 'uid_customer', provider: 'sandbox', provider_ref: 'pi_secret_1', amount_cents: 19800, currency: 'ZAR', status: 'successful', receipt_no: 'RCP-70000', idempotency_key: 'k1', verified_at: '2026-09-02T09:00:00.000Z', created_at: '2026-09-02T08:30:00.000Z' },
    { id: '60000000-0000-4000-8000-000000000002', booking_id: BOOKING_2, customer_id: 'uid_customer', provider: 'sandbox', provider_ref: 'pi_secret_2', amount_cents: 50000, currency: 'ZAR', status: 'failed', receipt_no: null, idempotency_key: 'k2', failure_reason: 'card_declined', created_at: '2026-09-03T08:30:00.000Z' },
    { id: '60000000-0000-4000-8000-000000000003', booking_id: BOOKING_1, customer_id: 'uid_customer', provider: 'sandbox', provider_ref: 'pi_secret_3', amount_cents: 1000, currency: 'ZAR', status: 'refunded', receipt_no: 'RCP-70001', idempotency_key: 'k3', created_at: '2026-09-04T08:30:00.000Z' },
    { id: '60000000-0000-4000-8000-000000000004', booking_id: BOOKING_1, customer_id: 'uid_customer', provider: 'sandbox', provider_ref: 'pi_old', amount_cents: 999, currency: 'ZAR', status: 'successful', receipt_no: 'RCP-69999', idempotency_key: 'k0', created_at: '2026-01-01T08:30:00.000Z' },
  ]);
  db.seed('quotations', [
    { id: '70000000-0000-4000-8000-000000000001', outlet_id: OUTLET_A, status: 'requested', created_at: '2026-09-02T10:00:00.000Z' },
    { id: '70000000-0000-4000-8000-000000000002', outlet_id: OUTLET_A, status: 'converted', created_at: '2026-09-02T11:00:00.000Z' },
    { id: '70000000-0000-4000-8000-000000000003', outlet_id: OUTLET_B, status: 'declined', created_at: '2026-09-02T12:00:00.000Z' },
  ]);
  db.seed('work_orders', [{ id: '80000000-0000-4000-8000-000000000001', outlet_id: OUTLET_A, status: 'verified', due_at: '2026-09-02T10:00:00.000Z', completed_at: '2026-09-02T09:30:00.000Z' }]);
  db.seed('tasks', [{ id: '90000000-0000-4000-8000-000000000001', work_order_id: '80000000-0000-4000-8000-000000000001', outlet_id: OUTLET_A, status: 'verified', elapsed_seconds: 2400, completed_at: '2026-09-02T09:30:00.000Z' }]);
  db.seed('checklist_step_results', [{ work_order_id: '80000000-0000-4000-8000-000000000001', step_key: 'wash', status: 'done' }]);
  db.seed('loyalty_ledger', [
    { customer_id: 'uid_customer', delta: 20, type: 'earn', idempotency_key: 'l1', created_at: '2026-09-02T09:30:00.000Z' },
    { customer_id: 'uid_customer', delta: -15, type: 'redeem', idempotency_key: 'l2', created_at: '2026-09-05T09:30:00.000Z' },
  ]);
  db.seed('inventory_items', [
    { outlet_id: OUTLET_A, sku: 'SHAMPOO', name: 'Shampoo', unit: 'L', on_hand: 2, reorder_threshold: 5, is_active: true },
    { outlet_id: OUTLET_A, sku: 'WAX', name: 'Wax', unit: 'unit', on_hand: 20, reorder_threshold: 5, is_active: true },
    { outlet_id: OUTLET_B, sku: 'TOWEL', name: 'Towel', unit: 'unit', on_hand: 0, reorder_threshold: 10, is_active: true },
  ]);
  db.seed('inventory_alerts', [{ item_id: 'x', outlet_id: OUTLET_A, level: 'low', status: 'open' }]);
  db.seed('notifications', [
    { recipient_id: 'uid_customer', channel: 'push', template_key: 't', body: 'b', status: 'sent', created_at: '2026-09-02T09:00:00.000Z' },
    { recipient_id: 'uid_customer', channel: 'push', template_key: 't', body: 'b', status: 'failed', created_at: '2026-09-02T09:00:00.000Z' },
    { recipient_id: 'uid_customer', channel: 'whatsapp', template_key: 't', body: 'b', status: 'suppressed', created_at: '2026-09-02T09:00:00.000Z' },
  ]);
  setSupabaseClient(db as any);
  resetRateLimits();
});

async function post(path: string, token: string, body?: unknown) {
  const res = await fetch(`${base}${path}`, { method: 'POST', headers: { Authorization: `Bearer ${token}`, 'Content-Type': 'application/json' }, body: body === undefined ? undefined : JSON.stringify(body) });
  const text = await res.text();
  let parsed: any = text;
  try { parsed = JSON.parse(text); } catch { /* text */ }
  return { status: res.status, body: parsed };
}

async function get(path: string, token: string) {
  const res = await fetch(`${base}${path}`, { headers: { Authorization: `Bearer ${token}` } });
  const text = await res.text();
  let body: any = text;
  try { body = JSON.parse(text); } catch { /* csv */ }
  return { status: res.status, body };
}

describe('GET /admin/outlet-services', () => {
  it('returns the outlet × service matrix with the four api.ts fields', async () => {
    const r = await get('/v1/admin/outlet-services', 'admin');
    expect(r.status).toBe(200);
    expect(r.body.data).toHaveLength(3);
    expect(r.body.data[0]).toMatchObject({ outlet_id: OUTLET_A, service_id: SERVICE_1, price_cents: 19800, is_available: true });
    expect(r.body.data[1]).toMatchObject({ outlet_id: OUTLET_A, service_id: SERVICE_2, price_cents: null, is_available: false });
  });

  it('narrows to one outlet and enforces outlet scope for managers', async () => {
    const ok = await get(`/v1/admin/outlet-services?outlet_id=${OUTLET_A}`, 'manager');
    expect(ok.status).toBe(200);
    expect(ok.body.data).toHaveLength(2);
    const forbidden = await get(`/v1/admin/outlet-services?outlet_id=${OUTLET_B}`, 'manager');
    expect(forbidden.status).toBe(403);
    expect((await get('/v1/admin/outlet-services', 'customer')).status).toBe(403);
  });
});

describe('GET /admin/payments (ADM-061)', () => {
  it('lists finance-safe rows newest first with status/date filters and pagination', async () => {
    const r = await get('/v1/admin/payments?from=2026-09-01&to=2026-09-30', 'finance');
    expect(r.status).toBe(200);
    expect(r.body.data.map((p: any) => p.id.slice(-1))).toEqual(['3', '2', '1']);
    const row = r.body.data[2];
    expect(row).toMatchObject({ booking_id: BOOKING_1, amount_cents: 19800, currency: 'ZAR', status: 'successful', receipt_no: 'RCP-70000', provider: 'sandbox', customer_id: 'uid_customer' });
    expect(row).toHaveProperty('booking_ref');
    expect(row).toHaveProperty('customer_name');
    expect(row).toHaveProperty('method_brand');
    expect(row).toHaveProperty('method_last4');
    expect(row).not.toHaveProperty('idempotency_key');
    expect(row).not.toHaveProperty('provider_ref');
    expect(row).not.toHaveProperty('method_id');

    const failed = await get('/v1/admin/payments?from=2026-09-01&to=2026-09-30&status=failed', 'admin');
    expect(failed.body.data).toHaveLength(1);
    expect(failed.body.data[0].failure_reason).toBe('card_declined');

    const page1 = await get('/v1/admin/payments?from=2026-09-01&to=2026-09-30&limit=2', 'admin');
    expect(page1.body.data).toHaveLength(2);
    expect(page1.body.next_cursor).toBeTruthy();
    const page2 = await get(`/v1/admin/payments?from=2026-09-01&to=2026-09-30&limit=2&cursor=${page1.body.next_cursor}`, 'admin');
    expect(page2.body.data).toHaveLength(1);
    expect(page2.body.next_cursor).toBeNull();
  });

  it('rejects unknown statuses and non-finance roles', async () => {
    expect((await get('/v1/admin/payments?status=bogus', 'admin')).status).toBe(400);
    expect((await get('/v1/admin/payments', 'customer')).status).toBe(403);
    expect((await get(`/v1/admin/payments?outlet_id=${OUTLET_B}`, 'manager')).status).toBe(403);
  });
});

describe('GET /admin/reports/summary (REP-005)', () => {
  it('rolls up financial + operational figures from the export queries', async () => {
    const r = await get('/v1/admin/reports/summary?from=2026-09-01&to=2026-09-30', 'admin');
    expect(r.status).toBe(200);
    const s = r.body;
    // Calendar dates resolve to local (Africa/Johannesburg) midnights: 1 Sep 00:00 local = 31 Aug 22:00Z; `to` is the next local midnight (exclusive).
    expect(s.range).toEqual({ from: '2026-08-31T22:00:00.000Z', to: '2026-09-30T22:00:00.000Z', outlet_ids: null });
    expect(s.financial).toMatchObject({ revenue_cents: 19800, refunds_cents: 1000, payments_total: 3, payments_successful: 1, payments_failed: 1, avg_ticket_cents: 19800 });
    expect(s.financial.by_status.map((x: any) => x.status).sort()).toEqual(['failed', 'refunded', 'successful']);
    expect(s.financial.by_outlet.map((o: any) => [o.name, o.bookings])).toEqual([['Sparkling Sandton', 1], ['Sparkling Rosebank', 1]]);
    expect(s.operational).toMatchObject({ bookings: 2, completed: 1, cancelled: 1, work_orders_completed: 1, on_time_pct: 100, avg_cycle_minutes: 40, checklist_compliance_pct: 100 });
    expect(s.operational.quotes).toEqual({ requested: 3, quoted: 2, accepted: 1, declined: 1, expired: 0, converted: 1 });
    expect(s.loyalty).toMatchObject({ points_issued: 20, points_redeemed: 15 });
    expect(s.inventory).toMatchObject({ items_active: 3, items_below_threshold: 2, items_out_of_stock: 1, open_alerts: 1 });
    expect(s.notifications).toMatchObject({ total: 3, delivered: 1, failed: 1, suppressed: 1, delivery_rate_pct: 50 });
  });

  it('reconciles with the CSV exports for the same filters', async () => {
    const q = 'from=2026-09-01&to=2026-09-30';
    const summary = (await get(`/v1/admin/reports/summary?${q}`, 'finance')).body;
    const csvRows = (csv: string) => csv.split('\n').filter((l) => l && !l.startsWith('"# ') && !l.startsWith('# ')).length - 1; // minus header
    const payments = await get(`/v1/admin/exports/payments.csv?${q}`, 'finance');
    expect(payments.status).toBe(200);
    expect(csvRows(payments.body)).toBe(summary.financial.payments_total);
    const bookings = await get(`/v1/admin/exports/bookings.csv?${q}`, 'finance');
    expect(csvRows(bookings.body)).toBe(summary.operational.bookings);
  });

  it('scopes managers to their outlets and rejects bad ranges', async () => {
    const r = await get('/v1/admin/reports/summary?from=2026-09-01&to=2026-09-30', 'manager');
    expect(r.status).toBe(200);
    expect(r.body.range.outlet_ids).toEqual([OUTLET_A]);
    expect(r.body.operational.bookings).toBe(1);
    expect(r.body.inventory.items_active).toBe(2);
    expect((await get('/v1/admin/reports/summary?from=2026-09-30&to=2026-09-01', 'manager')).status).toBe(400);
    expect((await get(`/v1/admin/reports/summary?outlet_id=${OUTLET_B}`, 'manager')).status).toBe(403);
  });
});

describe('GET /admin/integrations', () => {
  it('returns the four status cards with their probe fields', async () => {
    const r = await get('/v1/admin/integrations', 'manager');
    expect(r.status).toBe(200);
    const byKey = Object.fromEntries(r.body.data.map((c: any) => [c.key, c]));
    expect(Object.keys(byKey).sort()).toEqual(['firebase', 'payments', 'supabase', 'whatsapp']);
    for (const c of r.body.data) expect(Object.keys(c)).toEqual(expect.arrayContaining(['key', 'name', 'status', 'detail', 'icon']));
    expect(byKey.supabase).toMatchObject({ ok: true, status: 'connected' });
    expect(typeof byKey.supabase.latency_ms).toBe('number');
    expect(byKey.firebase).toMatchObject({ project_id: expect.any(String) });
    expect(byKey.payments).toMatchObject({ provider: 'sandbox', sandbox: true, status: 'sandbox', sandbox_confirm_enabled: true });
    expect(byKey.whatsapp).toMatchObject({ enabled: false, status: 'disabled' });
    expect(JSON.stringify(r.body)).not.toContain('s3cret');
  });

  it('is limited to manager/admin', async () => {
    expect((await get('/v1/admin/integrations', 'finance')).status).toBe(403);
    expect((await get('/v1/admin/integrations', 'customer')).status).toBe(403);
  });
});

describe('staff accounts (ADM-010): create → temporary password → forced change', () => {
  it('creates the Firebase account with a temporary password and flags the profile', async () => {
    const r = await post('/v1/admin/users', 'admin', { email: 'nomsa@example.com', full_name: 'Nomsa Dlamini', role: 'technician', outlet_ids: [OUTLET_A] });
    expect(r.status).toBe(201);
    expect(r.body.temporary_password).toMatch(/^Spk-/);
    expect(r.body.invite_link).toBeNull();
    expect(r.body.profile).toMatchObject({ id: 'uid_new_nomsa', role: 'technician', email: 'nomsa@example.com', must_change_password: true, is_active: true });
    expect(fbCalls[0]).toEqual(['createUser', expect.objectContaining({ email: 'nomsa@example.com', password: r.body.temporary_password })]);
    expect(db.rows('staff_outlets').filter((o) => o.profile_id === 'uid_new_nomsa')).toHaveLength(1);
  });

  it('reuses an existing Firebase user (resets its password) and can add a reset link', async () => {
    const r = await post('/v1/admin/users', 'admin', { email: 'existing@example.com', full_name: 'Ex Isting', role: 'supervisor', outlet_ids: [OUTLET_B], invite: 'link' });
    expect(r.status).toBe(201);
    expect(r.body.profile).toMatchObject({ id: 'uid_existing', must_change_password: true });
    expect(r.body.temporary_password).toMatch(/^Spk-/);
    expect(r.body.invite_link).toBe('https://example.test/reset');
    expect(fbCalls.find((c) => c[0] === 'updateUser')).toEqual(['updateUser', 'uid_existing', expect.objectContaining({ password: r.body.temporary_password })]);
  });

  it('rejects duplicates and non-admins', async () => {
    expect((await post('/v1/admin/users', 'admin', { email: 'manager@example.com', full_name: 'Dup', role: 'technician' })).status).toBe(409);
    expect((await post('/v1/admin/users', 'manager', { email: 'x@example.com', full_name: 'Some One', role: 'technician' })).status).toBe(403);
  });

  it('reset-password issues a new temporary password, revokes sessions and re-flags the profile', async () => {
    db.rows('profiles').find((p) => p.id === 'uid_manager')!.must_change_password = false;
    const r = await post('/v1/admin/users/uid_manager/reset-password', 'admin');
    expect(r.status).toBe(200);
    expect(r.body.temporary_password).toMatch(/^Spk-/);
    expect(r.body.profile).toMatchObject({ id: 'uid_manager', must_change_password: true, password_changed_at: null });
    expect(fbCalls).toEqual([['updateUser', 'uid_manager', { password: r.body.temporary_password, disabled: false }], ['revoke', 'uid_manager']]);
    expect((await post('/v1/admin/users/uid_customer/reset-password', 'admin')).status).toBe(400);
    expect((await post('/v1/admin/users/uid_manager/reset-password', 'manager')).status).toBe(403);
  });

  it('password-changed clears the flag for a fresh session and refuses a stale one', async () => {
    const stale = await post('/v1/auth/password-changed', 'stale');
    expect(stale.status).toBe(409);
    expect(stale.body.error?.details ?? stale.body.details ?? stale.body).toMatchObject({ reason: 'stale_session' });
    const ok = await post('/v1/auth/password-changed', 'fresh');
    expect(ok.status).toBe(200);
    expect(ok.body.profile).toMatchObject({ id: 'uid_fresh', must_change_password: false });
    expect(ok.body.profile.password_changed_at).toBeTruthy();
    expect(db.rows('audit_events').some((a) => a.action === 'auth.password_changed')).toBe(true);
  });
});
