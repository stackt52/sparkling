import { createServer, type Server } from 'node:http';
import { afterAll, beforeAll, beforeEach, describe, expect, it } from 'vitest';
import { createApp } from '../src/app.js';
import { setFirebaseAuthForTests } from '../src/lib/firebase.js';
import { setSupabaseClient } from '../src/lib/supabase.js';
import { resetRateLimits } from '../src/middleware/rateLimit.js';
import { SandboxProvider, setPaymentProviderForTests } from '../src/services/payments.js';
import { fakeSupabase, type FakeSupabase } from './helpers/fakeSupabase.js';

let server: Server;
let base: string;
let db: FakeSupabase;

beforeAll(async () => {
  server = createServer(createApp());
  await new Promise<void>((r) => server.listen(0, r));
  base = `http://127.0.0.1:${(server.address() as { port: number }).port}`;
  setFirebaseAuthForTests({
    verifyIdToken: async (token: string) => {
      if (token === 'good') return { uid: 'uid_1', email: 'thabo@example.com' };
      if (token === 'new') return { uid: 'uid_new', email: 'naledi@example.com', name: 'Naledi' };
      throw new Error('bad token');
    },
    setCustomUserClaims: async () => undefined,
  } as any);
  setPaymentProviderForTests(new SandboxProvider('s3cret'));
});
afterAll(() => server.close());

beforeEach(() => {
  db = fakeSupabase();
  db.seed('profiles', [
    { id: 'uid_1', role: 'customer', full_name: 'Thabo', email: 'thabo@example.com', is_active: true, push_opt_in: true, whatsapp_opt_in: true, marketing_opt_in: true },
    { id: 'seed_naledi', role: 'customer', full_name: 'Naledi Mokoena', email: 'naledi@example.com', is_active: true, push_opt_in: true, whatsapp_opt_in: true, marketing_opt_in: false },
  ]);
  db.seed('feature_flags', []);
  setSupabaseClient(db as any);
  resetRateLimits();
});

async function call(path: string, init: RequestInit = {}) {
  const res = await fetch(`${base}${path}`, init);
  const text = await res.text();
  let body: any = text;
  try { body = JSON.parse(text); } catch { /* keep text */ }
  return { status: res.status, body, headers: res.headers };
}

describe('app wiring (API-001/004/010)', () => {
  it('GET /v1/health is public', async () => {
    const r = await call('/v1/health');
    expect(r.status).toBe(200);
    expect(r.body.ok).toBe(true);
    expect(typeof r.body.version).toBe('string');
    expect(r.headers.get('x-correlation-id')).toBeTruthy();
  });

  it('returns the error envelope for missing/invalid tokens', async () => {
    const r = await call('/v1/me');
    expect(r.status).toBe(401);
    expect(r.body).toEqual({ error: { code: 'unauthenticated', message: 'Missing bearer token', details: [], correlation_id: expect.any(String) } });
    const bad = await call('/v1/me', { headers: { Authorization: 'Bearer nope' } });
    expect(bad.status).toBe(401);
    expect(bad.body.error.code).toBe('unauthenticated');
  });

  it('404s unknown routes inside the envelope', async () => {
    const r = await call('/v1/nope', { headers: { Authorization: 'Bearer good' } });
    expect(r.status).toBe(404);
    expect(r.body.error.code).toBe('not_found');
  });

  it('validation errors are 400 with details and never leak stacks', async () => {
    const r = await call('/v1/vehicles', { method: 'POST', headers: { Authorization: 'Bearer good', 'Content-Type': 'application/json' }, body: JSON.stringify({ registration_no: 'X' }) });
    expect(r.status).toBe(400);
    expect(r.body.error.code).toBe('validation_error');
    expect(r.body.error.details[0].path).toBe('registration_no');
    expect(JSON.stringify(r.body)).not.toMatch(/at .*\.ts:\d+/);
  });

  it('POST /v1/auth/session claims a seeded profile by e-mail and rewrites its id', async () => {
    const r = await call('/v1/auth/session', { method: 'POST', headers: { Authorization: 'Bearer new', 'Content-Type': 'application/json' }, body: JSON.stringify({ app: 'customer' }) });
    expect(r.status).toBe(200);
    expect(r.body.profile.id).toBe('uid_new');
    expect(r.body.profile.full_name).toBe('Naledi Mokoena');
    expect(r.body.claims_updated).toBe(true);
    expect(db.rows('profiles').some((p) => p.id === 'seed_naledi')).toBe(false);
  });

  it('GET /v1/me returns the profile', async () => {
    const r = await call('/v1/me', { headers: { Authorization: 'Bearer good' } });
    expect(r.status).toBe(200);
    expect(r.body.profile.id).toBe('uid_1');
    expect(r.body.outlets).toEqual([]);
  });

  it('rejects webhook calls with a bad signature and accepts signed ones', async () => {
    const provider = new SandboxProvider('s3cret');
    const raw = JSON.stringify({ id: 'evt_x', type: 'payment.succeeded', payment_id: '60000000-0000-4000-8000-000000000001' });
    const bad = await call('/v1/payments/webhook', { method: 'POST', headers: { 'Content-Type': 'application/json', 'X-Signature': 'nope' }, body: raw });
    expect(bad.status).toBe(401);
    const missing = await call('/v1/payments/webhook', { method: 'POST', headers: { 'Content-Type': 'application/json', 'X-Signature': provider.sign(raw) }, body: raw });
    // signature ok but unknown payment → event recorded, 404
    expect(missing.status).toBe(404);
    expect(db.rows('payment_events')).toHaveLength(1);
  });

  it('customer cannot reach staff routes', async () => {
    const r = await call('/v1/tasks?scope=mine', { headers: { Authorization: 'Bearer good' } });
    expect(r.status).toBe(403);
    expect(r.body.error.code).toBe('forbidden');
  });
});
