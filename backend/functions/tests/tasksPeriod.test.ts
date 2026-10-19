/** `GET /tasks?from&to`: Queue and Done tabs default to today in the staff app; other periods are a range. */
import { createServer, type Server } from 'node:http';
import { afterAll, beforeAll, beforeEach, describe, expect, it } from 'vitest';
import { createApp } from '../src/app.js';
import { setFirebaseAuthForTests } from '../src/lib/firebase.js';
import { setSupabaseClient } from '../src/lib/supabase.js';
import { resetRateLimits } from '../src/middleware/rateLimit.js';
import { invalidateFlags } from '../src/services/flags.js';
import { fakeSupabase, type FakeSupabase } from './helpers/fakeSupabase.js';

const OUTLET = 'a0000000-0000-4000-8000-000000000001';
const DAY = '2026-10-19';
const from = `${DAY}T00:00:00.000Z`;
const to = '2026-10-20T00:00:00.000Z';
const at = (d: string, h: string) => `${d}T${h}:00.000Z`;

let db: FakeSupabase;
let server: Server;
let base: string;

beforeAll(async () => {
  server = createServer(createApp());
  await new Promise<void>((r) => server.listen(0, r));
  base = `http://127.0.0.1:${(server.address() as { port: number }).port}`;
  setFirebaseAuthForTests({
    verifyIdToken: async (token: string) => {
      if (token === 'tech') return { uid: 'tech_1', email: 'tech@example.com' };
      throw new Error('bad token');
    },
    setCustomUserClaims: async () => undefined,
  } as any);
});
afterAll(() => server.close());

function task(id: string, patch: Record<string, unknown>) {
  return { id: `40000000-0000-4000-8000-0000000000${id}`, work_order_id: `30000000-0000-4000-8000-0000000000${id}`, outlet_id: OUTLET, title: `T${id}`, seq: 1, assignee_id: null, priority: 2, due_at: null, started_at: null, completed_at: null, elapsed_seconds: 0, created_at: at('2026-10-01', '08:00'), ...patch };
}

beforeEach(() => {
  db = fakeSupabase();
  db.seed('feature_flags', [{ key: 'auto_assignment', enabled: false }]);
  db.seed('profiles', [{ id: 'tech_1', role: 'technician', full_name: 'Pieter', is_active: true, push_opt_in: true, whatsapp_opt_in: true, marketing_opt_in: false }]);
  db.seed('staff_outlets', [{ profile_id: 'tech_1', outlet_id: OUTLET }]);
  db.seed('tasks', [
    task('01', { status: 'queued', due_at: at(DAY, '10:00') }), // due today
    task('02', { status: 'assigned', due_at: at('2026-10-20', '09:00'), created_at: at(DAY, '08:30') }), // due tomorrow, raised today (quotation conversion)
    task('03', { status: 'in_progress', due_at: at('2026-10-18', '15:00') }), // yesterday's work still open
    task('04', { status: 'queued', due_at: null, created_at: at(DAY, '11:00') }), // walk-in without slot, today
    task('05', { status: 'queued', due_at: null, created_at: at('2026-10-17', '11:00') }), // old unscheduled
    task('06', { status: 'verified', completed_at: at(DAY, '12:00') }),
    task('07', { status: 'completed', completed_at: at('2026-10-18', '12:00') }),
    task('08', { status: 'verified', completed_at: at('2026-10-20', '00:00') }), // boundary: next day
  ]);
  setSupabaseClient(db as any);
  invalidateFlags();
  resetRateLimits();
});

const ids = (body: any) => (body.data as Array<{ id: string }>).map((t) => t.id.slice(-2)).sort();
async function get(query: string) {
  const res = await fetch(`${base}/v1/tasks?${query}`, { headers: { Authorization: 'Bearer tech' } });
  return { status: res.status, body: (await res.json()) as any };
}

describe('GET /tasks period filter', () => {
  it('queue: today = due today or raised today; without a range everything open', async () => {
    const today = await get(`scope=queue&from=${from}&to=${to}`);
    expect(today.status, JSON.stringify(today.body)).toBe(200);
    expect(ids(today.body)).toEqual(['01', '02', '04']);
    expect(today.body).toMatchObject({ scope: 'queue', from, to });
    const all = await get('scope=queue');
    expect(ids(all.body)).toEqual(['01', '02', '03', '04', '05']);
    expect(all.body.from).toBeUndefined();
  });

  it('done: completed within [from, to)', async () => {
    const today = await get(`scope=done&from=${from}&to=${to}`);
    expect(ids(today.body)).toEqual(['06']);
    const week = await get(`scope=done&from=2026-10-13T00:00:00.000Z&to=${to}`);
    expect(ids(week.body)).toEqual(['06', '07']);
    expect(ids((await get('scope=done')).body)).toEqual(['06', '07', '08']);
  });

  it('accepts offsets and rejects half or inverted ranges', async () => {
    const sast = await get(`scope=done&from=${encodeURIComponent(`${DAY}T02:00:00+02:00`)}&to=${encodeURIComponent('2026-10-20T02:00:00+02:00')}`);
    expect(sast.status).toBe(200);
    expect(ids(sast.body)).toEqual(['06']);
    expect((await get(`scope=done&from=${from}`)).status).toBe(400);
    expect((await get(`scope=done&from=${to}&to=${from}`)).status).toBe(400);
    expect((await get('scope=done&from=yesterday&to=today')).status).toBe(400);
  });

  it('mine ignores the range', async () => {
    db.rows('tasks')[2].assignee_id = 'tech_1'; // yesterday's in-progress task
    const mine = await get(`scope=mine&from=${from}&to=${to}`);
    expect(ids(mine.body)).toEqual(['03']);
  });
});
