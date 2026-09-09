import express from 'express';
import { createServer, type Server } from 'node:http';
import { afterAll, beforeAll, beforeEach, describe, expect, it } from 'vitest';
import { correlation } from '../src/middleware/correlation.js';
import { errorHandler } from '../src/middleware/errors.js';
import { extractIdempotencyKey, idempotency, scopedKey } from '../src/middleware/idempotency.js';
import { setSupabaseClient } from '../src/lib/supabase.js';
import { fakeSupabase, type FakeSupabase } from './helpers/fakeSupabase.js';
import { makeCtx } from './helpers/context.js';

let server: Server;
let base: string;
let db: FakeSupabase;
let hits = 0;

beforeAll(async () => {
  const app = express();
  app.use(correlation);
  app.use(express.json());
  app.use((req, _res, next) => {
    const uid = req.header('X-Test-Uid') ?? 'uid_a';
    req.auth = makeCtx('customer', uid).auth;
    req.ctx = makeCtx('customer', uid);
    next();
  });
  app.use(idempotency);
  app.post('/v1/things', (req, res) => {
    hits += 1;
    res.status(201).json({ id: `thing_${hits}`, echo: req.body });
  });
  app.post('/v1/fail', (_req, res) => {
    hits += 1;
    res.status(500).json({ error: { code: 'internal' } });
  });
  app.use(errorHandler);
  server = createServer(app);
  await new Promise<void>((r) => server.listen(0, r));
  const addr = server.address() as { port: number };
  base = `http://127.0.0.1:${addr.port}`;
});

afterAll(() => server.close());

beforeEach(() => {
  db = fakeSupabase();
  setSupabaseClient(db as any);
  hits = 0;
});

async function post(path: string, body: unknown, headers: Record<string, string> = {}) {
  const res = await fetch(`${base}${path}`, { method: 'POST', headers: { 'Content-Type': 'application/json', ...headers }, body: JSON.stringify(body) });
  return { status: res.status, body: await res.json(), headers: res.headers };
}

describe('idempotency middleware (API-003)', () => {
  it('extracts the key from the header or body.client_op_id', () => {
    expect(extractIdempotencyKey({ header: (n) => (n === 'Idempotency-Key' ? 'abc' : undefined), body: {} })).toBe('abc');
    expect(extractIdempotencyKey({ header: () => undefined, body: { client_op_id: 'op-1' } })).toBe('op-1');
    expect(extractIdempotencyKey({ header: () => undefined, body: {} })).toBeNull();
    expect(scopedKey('u', 'post', '/v1/x', 'k')).toBe('u:POST:/v1/x:k');
  });

  it('replays the first response for the same key, uid, method and path', async () => {
    const first = await post('/v1/things', { a: 1 }, { 'Idempotency-Key': 'key-1' });
    expect(first.status).toBe(201);
    expect(first.body.id).toBe('thing_1');
    await new Promise((r) => setTimeout(r, 10));
    const second = await post('/v1/things', { a: 2 }, { 'Idempotency-Key': 'key-1' });
    expect(second.status).toBe(201);
    expect(second.body).toEqual(first.body);
    expect(second.headers.get('idempotent-replayed')).toBe('true');
    expect(hits).toBe(1);
    expect(db.rows('idempotency_keys')).toHaveLength(1);
  });

  it('uses client_op_id from the body as the key', async () => {
    await post('/v1/things', { client_op_id: 'op-77' });
    await new Promise((r) => setTimeout(r, 10));
    const again = await post('/v1/things', { client_op_id: 'op-77' });
    expect(again.body.id).toBe('thing_1');
    expect(hits).toBe(1);
  });

  it('scopes keys per user', async () => {
    await post('/v1/things', {}, { 'Idempotency-Key': 'shared', 'X-Test-Uid': 'uid_a' });
    await new Promise((r) => setTimeout(r, 10));
    const other = await post('/v1/things', {}, { 'Idempotency-Key': 'shared', 'X-Test-Uid': 'uid_b' });
    expect(other.body.id).toBe('thing_2');
    expect(hits).toBe(2);
  });

  it('does not cache 5xx responses', async () => {
    await post('/v1/fail', {}, { 'Idempotency-Key': 'f1' });
    await new Promise((r) => setTimeout(r, 10));
    await post('/v1/fail', {}, { 'Idempotency-Key': 'f1' });
    expect(hits).toBe(2);
    expect(db.rows('idempotency_keys')).toHaveLength(0);
  });

  it('echoes and generates correlation ids', async () => {
    const r = await post('/v1/things', {}, { 'X-Correlation-Id': 'corr-123' });
    expect(r.headers.get('x-correlation-id')).toBe('corr-123');
    const r2 = await post('/v1/things', {});
    expect(r2.headers.get('x-correlation-id')).toMatch(/^[0-9a-f-]{36}$/);
  });
});
