import { createServer, type Server } from 'node:http';
import { afterAll, beforeAll, beforeEach, describe, expect, it } from 'vitest';
import { createApp } from '../src/app.js';
import { setFirebaseAuthForTests } from '../src/lib/firebase.js';
import { setSupabaseClient } from '../src/lib/supabase.js';
import { computeTwilioSignature } from '../src/lib/twilioSignature.js';
import { resetRateLimits } from '../src/middleware/rateLimit.js';
import { applyTwilioStatus } from '../src/services/notifications.js';
import { fakeSupabase, type FakeSupabase } from './helpers/fakeSupabase.js';

const TOKEN = 'tok_status_test';
const N1 = '90000000-0000-4000-8000-000000000001';
const N2 = '90000000-0000-4000-8000-000000000002';

let server: Server;
let base: string;
let db: FakeSupabase;
let callbackUrl: string;
const savedToken = process.env.TWILIO_AUTH_TOKEN;
const savedBase = process.env.PUBLIC_API_BASE_URL;

beforeAll(async () => {
  process.env.TWILIO_AUTH_TOKEN = TOKEN;
  delete process.env.PUBLIC_API_BASE_URL;
  server = createServer(createApp());
  await new Promise<void>((r) => server.listen(0, r));
  base = `http://127.0.0.1:${(server.address() as { port: number }).port}`;
  callbackUrl = `${base}/v1/notifications/twilio/status`;
  setFirebaseAuthForTests({ verifyIdToken: async () => { throw new Error('bad token'); } } as any);
});
afterAll(() => {
  server.close();
  if (savedToken === undefined) delete process.env.TWILIO_AUTH_TOKEN;
  else process.env.TWILIO_AUTH_TOKEN = savedToken;
  if (savedBase !== undefined) process.env.PUBLIC_API_BASE_URL = savedBase;
});

beforeEach(() => {
  db = fakeSupabase();
  db.seed('notifications', [
    { id: N1, recipient_id: 'c1', channel: 'whatsapp', template_key: 'quote_ready', body: 'b', status: 'sent', provider_ref: 'SM_one', provider_status: 'queued', attempts: 1, sent_at: '2026-09-09T08:00:00.000Z', delivered_at: null, read_by_recipient_at: null, error: null, provider_error_code: null },
    { id: N2, recipient_id: 'c1', channel: 'whatsapp', template_key: 'service_ready', body: 'b', status: 'sent', provider_ref: 'SM_two', provider_status: 'queued', attempts: 1, sent_at: '2026-09-09T08:00:00.000Z', delivered_at: null, read_by_recipient_at: null, error: null, provider_error_code: null },
  ]);
  setSupabaseClient(db as any);
  resetRateLimits();
});

async function post(params: Record<string, string>, opts: { sign?: boolean | string; url?: string } = {}) {
  const body = new URLSearchParams(params).toString();
  const headers: Record<string, string> = { 'Content-Type': 'application/x-www-form-urlencoded' };
  const sign = opts.sign ?? true;
  if (sign === true) headers['X-Twilio-Signature'] = computeTwilioSignature(TOKEN, opts.url ?? callbackUrl, params);
  else if (typeof sign === 'string') headers['X-Twilio-Signature'] = sign;
  const res = await fetch(callbackUrl, { method: 'POST', headers, body });
  return { status: res.status, body: await res.json() as any };
}

const row = (id: string) => db.rows('notifications').find((n) => n.id === id)!;

describe('POST /notifications/twilio/status (unauthenticated, signed)', () => {
  it('rejects a missing or invalid signature with 403 and changes nothing', async () => {
    expect((await post({ MessageSid: 'SM_one', MessageStatus: 'delivered' }, { sign: false })).status).toBe(403);
    expect((await post({ MessageSid: 'SM_one', MessageStatus: 'delivered' }, { sign: 'bogus' })).status).toBe(403);
    // signed for a different URL (e.g. host mismatch) → invalid
    expect((await post({ MessageSid: 'SM_one', MessageStatus: 'delivered' }, { url: 'https://elsewhere.example/v1/notifications/twilio/status' })).status).toBe(403);
    // tampered params
    const sig = computeTwilioSignature(TOKEN, callbackUrl, { MessageSid: 'SM_one', MessageStatus: 'sent' });
    expect((await post({ MessageSid: 'SM_one', MessageStatus: 'delivered' }, { sign: sig })).status).toBe(403);
    expect(row(N1).status).toBe('sent');
    expect(row(N1).provider_status).toBe('queued');
  });

  it('accepts the configured PUBLIC_API_BASE_URL callback URL even when the host header differs', async () => {
    process.env.PUBLIC_API_BASE_URL = 'https://europe-west1-sparkling-4e89d.cloudfunctions.net/api';
    try {
      const r = await post({ MessageSid: 'SM_one', MessageStatus: 'sent' }, { url: 'https://europe-west1-sparkling-4e89d.cloudfunctions.net/api/v1/notifications/twilio/status' });
      expect(r.status).toBe(200);
      expect(r.body).toMatchObject({ ignored: false, status: 'sent', provider_status: 'sent' });
    } finally {
      delete process.env.PUBLIC_API_BASE_URL;
    }
  });

  it('returns 403 when no auth token is configured', async () => {
    const t = process.env.TWILIO_AUTH_TOKEN;
    delete process.env.TWILIO_AUTH_TOKEN;
    try {
      const r = await post({ MessageSid: 'SM_one', MessageStatus: 'delivered' });
      expect(r.status).toBe(403);
      expect(r.body.error.code).toBe('forbidden');
    } finally {
      process.env.TWILIO_AUTH_TOKEN = t;
    }
  });

  it('maps delivered → delivered (+delivered_at) and is idempotent on replay', async () => {
    const first = await post({ MessageSid: 'SM_one', MessageStatus: 'delivered', AccountSid: 'AC1', From: 'whatsapp:+27600000000', To: 'whatsapp:+27821234567' });
    expect(first.status).toBe(200);
    expect(first.body).toMatchObject({ ignored: false, notification_id: N1, status: 'delivered', provider_status: 'delivered' });
    const r1 = row(N1);
    expect(r1.status).toBe('delivered');
    expect(r1.provider_status).toBe('delivered');
    expect(typeof r1.delivered_at).toBe('string');
    expect(r1.read_by_recipient_at).toBeNull();

    const replay = await post({ MessageSid: 'SM_one', MessageStatus: 'delivered', AccountSid: 'AC1', From: 'whatsapp:+27600000000', To: 'whatsapp:+27821234567' });
    expect(replay.status).toBe(200);
    expect(replay.body).toMatchObject({ ignored: true, reason: 'duplicate', notification_id: N1 });
    expect(row(N1).delivered_at).toBe(r1.delivered_at);

    // out-of-order "sent" after delivered is ignored; a late "failed" never downgrades delivered
    expect((await post({ MessageSid: 'SM_one', MessageStatus: 'sent' })).body).toMatchObject({ ignored: true, reason: 'stale' });
    expect((await post({ MessageSid: 'SM_one', MessageStatus: 'failed', ErrorCode: '63016' })).body).toMatchObject({ ignored: true });
    expect(row(N1).status).toBe('delivered');

    // read → stays delivered, records read_by_recipient_at
    const read = await post({ MessageSid: 'SM_one', MessageStatus: 'read' });
    expect(read.body).toMatchObject({ ignored: false, status: 'delivered', provider_status: 'read' });
    expect(typeof row(N1).read_by_recipient_at).toBe('string');
    expect(row(N1).delivered_at).toBe(r1.delivered_at);
  });

  it('maps failed/undelivered → failed with the Twilio error code and message', async () => {
    const r = await post({ MessageSid: 'SM_two', MessageStatus: 'undelivered', ErrorCode: '63016', ErrorMessage: 'Outside allowed window' });
    expect(r.status).toBe(200);
    expect(r.body).toMatchObject({ ignored: false, status: 'failed', provider_status: 'undelivered' });
    const n = row(N2);
    expect(n.status).toBe('failed');
    expect(n.provider_error_code).toBe('63016');
    expect(n.error).toBe('Twilio 63016: Outside allowed window');
    expect(n.delivered_at).toBeNull();
    // same terminal event again → duplicate
    expect((await post({ MessageSid: 'SM_two', MessageStatus: 'undelivered', ErrorCode: '63016' })).body).toMatchObject({ ignored: true, reason: 'duplicate' });
  });

  it('progresses queued → sending → sent and records sent_at once', async () => {
    db.rows('notifications')[0].sent_at = null;
    db.rows('notifications')[0].status = 'queued';
    expect((await post({ MessageSid: 'SM_one', MessageStatus: 'sending' })).body).toMatchObject({ ignored: false, status: 'queued', provider_status: 'sending' });
    expect(row(N1).sent_at).toBeNull();
    expect((await post({ MessageSid: 'SM_one', MessageStatus: 'sent' })).body).toMatchObject({ ignored: false, status: 'sent' });
    const sentAt = row(N1).sent_at;
    expect(typeof sentAt).toBe('string');
    expect((await post({ MessageSid: 'SM_one', MessageStatus: 'delivered' })).body.status).toBe('delivered');
    expect(row(N1).sent_at).toBe(sentAt);
  });

  it('ignores unknown SIDs, unknown statuses and missing SIDs with 200', async () => {
    expect((await post({ MessageSid: 'SM_nope', MessageStatus: 'delivered' })).body).toEqual({ ignored: true, reason: 'unknown MessageSid' });
    expect((await post({ MessageSid: 'SM_one', MessageStatus: 'teleported' })).body).toMatchObject({ ignored: true });
    expect((await post({ MessageStatus: 'delivered' })).body).toMatchObject({ ignored: true, reason: 'missing MessageSid' });
    expect(row(N1).status).toBe('sent');
  });

  it('applyTwilioStatus accepts SmsStatus as an alias', async () => {
    const out = await applyTwilioStatus({ MessageSid: 'SM_two', SmsStatus: 'delivered' });
    expect(out).toMatchObject({ ignored: false, status: 'delivered' });
  });
});
