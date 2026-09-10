import { afterEach, describe, expect, it, vi } from 'vitest';
import { computeTwilioSignature, validateTwilioSignature } from '../src/lib/twilioSignature.js';
import {
  describeTwilioError,
  FREEFORM_WARNING,
  getWhatsAppAdapter,
  isE164,
  maskPhone,
  normalisePhone,
  NoopWhatsAppAdapter,
  SandboxWhatsAppAdapter,
  TwilioWhatsAppAdapter,
  twilioStatusCallbackUrl,
} from '../src/lib/whatsapp.js';
import { mapTwilioStatus } from '../src/services/notifications.js';

const SID = 'ACtest00000000000000000000000000';
const TOKEN = 'tok_test';
const MSG = 'MG4d8b6037dc3b183f43b2622307271660';

type Call = { url: string; init: RequestInit; params: URLSearchParams };

function fakeFetch(responses: Array<{ status: number; json?: unknown } | Error>) {
  const calls: Call[] = [];
  const impl = vi.fn(async (url: string | URL, init?: RequestInit) => {
    const body = String(init?.body ?? '');
    calls.push({ url: String(url), init: init ?? {}, params: new URLSearchParams(body) });
    const next = responses.shift();
    if (!next) throw new Error('no more fake responses');
    if (next instanceof Error) throw next;
    return new Response(JSON.stringify(next.json ?? {}), { status: next.status, headers: { 'Content-Type': 'application/json' } });
  });
  return { impl: impl as unknown as typeof fetch, calls };
}

function adapter(fetchImpl: typeof fetch, extra: Partial<ConstructorParameters<typeof TwilioWhatsAppAdapter>[0]> = {}) {
  return new TwilioWhatsAppAdapter({ accountSid: SID, authToken: TOKEN, messagingServiceSid: MSG, fetchImpl, timeoutMs: 2000, ...extra });
}

describe('phone normalisation (E.164)', () => {
  it('normalises South African local numbers and strips formatting', () => {
    expect(normalisePhone('082 123 4567')).toBe('+27821234567');
    expect(normalisePhone('0821234567')).toBe('+27821234567');
    expect(normalisePhone('+27 82 123-4567')).toBe('+27821234567');
    expect(normalisePhone('27821234567')).toBe('+27821234567');
    expect(normalisePhone('0027821234567')).toBe('+27821234567');
    expect(normalisePhone('whatsapp:+27821234567')).toBe('+27821234567');
    expect(normalisePhone('(011) 555-0101')).toBe('+27115550101');
    expect(normalisePhone('+14155552671')).toBe('+14155552671');
  });
  it('rejects numbers that are not E.164 after normalisation', () => {
    expect(normalisePhone('')).toBeNull();
    expect(normalisePhone(null)).toBeNull();
    expect(normalisePhone('12345')).toBeNull();
    expect(normalisePhone('+0821234567')).toBeNull();
    expect(normalisePhone('+2782123456789012')).toBeNull();
    expect(normalisePhone('hello')).toBeNull();
    expect(isE164('+27821234567')).toBe(true);
    expect(isE164('0821234567')).toBe(false);
  });
  it('masks phones in logs', () => {
    expect(maskPhone('+27821234567')).toBe('+********567');
  });
});

describe('TwilioWhatsAppAdapter request shape', () => {
  it('posts a form-encoded template message via the Messaging Service with Basic auth', async () => {
    const { impl, calls } = fakeFetch([{ status: 201, json: { sid: 'SM123', status: 'queued' } }]);
    const r = await adapter(impl).send({
      to: '082 123 4567',
      body: 'Hi Thabo, your quotation QT-1 is ready.',
      contentSid: 'HX011c7f1b31697f8e21d36ff6b4d02b06',
      contentVariables: { '1': 'Thabo', '2': 'q-1' },
      statusCallback: 'https://api.example.com/v1/notifications/twilio/status',
      meta: { template: 'quote_ready' },
    });
    expect(r).toEqual({ provider_ref: 'SM123', status: 'sent', provider_status: 'queued', warning: undefined });
    expect(calls).toHaveLength(1);
    const c = calls[0];
    expect(c.url).toBe(`https://api.twilio.com/2010-04-01/Accounts/${SID}/Messages.json`);
    expect(c.init.method).toBe('POST');
    const headers = c.init.headers as Record<string, string>;
    expect(headers['Content-Type']).toBe('application/x-www-form-urlencoded');
    expect(headers.Authorization).toBe(`Basic ${Buffer.from(`${SID}:${TOKEN}`).toString('base64')}`);
    expect(c.params.get('To')).toBe('whatsapp:+27821234567');
    expect(c.params.get('MessagingServiceSid')).toBe(MSG);
    expect(c.params.get('From')).toBeNull();
    expect(c.params.get('ContentSid')).toBe('HX011c7f1b31697f8e21d36ff6b4d02b06');
    expect(JSON.parse(c.params.get('ContentVariables')!)).toEqual({ '1': 'Thabo', '2': 'q-1' });
    expect(c.params.get('Body')).toBeNull();
    expect(c.params.get('StatusCallback')).toBe('https://api.example.com/v1/notifications/twilio/status');
  });

  it('sends a free-form Body (with a session warning) when no Content SID is given, and uses From without a messaging service', async () => {
    const { impl, calls } = fakeFetch([{ status: 201, json: { sid: 'SM456', status: 'accepted' } }]);
    const r = await adapter(impl, { messagingServiceSid: null, from: '+27600000000' }).send({ to: '+27821234567', body: 'Free text' });
    expect(r.status).toBe('sent');
    expect(r.provider_ref).toBe('SM456');
    expect(r.warning).toBe(FREEFORM_WARNING);
    expect(calls[0].params.get('Body')).toBe('Free text');
    expect(calls[0].params.get('ContentSid')).toBeNull();
    expect(calls[0].params.get('From')).toBe('whatsapp:+27600000000');
    expect(calls[0].params.get('MessagingServiceSid')).toBeNull();
    expect(calls[0].params.get('StatusCallback')).toBeNull();
  });

  it('fails locally on an invalid number without calling Twilio', async () => {
    const { impl, calls } = fakeFetch([]);
    const r = await adapter(impl).send({ to: '12345', body: 'x' });
    expect(r.status).toBe('failed');
    expect(r.provider_error_code).toBe('21211');
    expect(calls).toHaveLength(0);
  });

  it('fails when credentials or sender are missing', async () => {
    const { impl, calls } = fakeFetch([]);
    expect((await adapter(impl, { authToken: '' }).send({ to: '+27821234567', body: 'x' })).provider_error_code).toBe('not_configured');
    expect((await adapter(impl, { messagingServiceSid: null }).send({ to: '+27821234567', body: 'x' })).provider_error_code).toBe('not_configured');
    expect(calls).toHaveLength(0);
  });
});

describe('TwilioWhatsAppAdapter error mapping and retries (INT-007)', () => {
  it.each([
    ['63016', 'Outside the 24-hour customer session'],
    ['21211', 'Invalid destination phone number'],
    ['63003', 'has not opted in'],
  ])('maps 4xx code %s to a failed result with a friendly message (no retry)', async (code, text) => {
    const { impl, calls } = fakeFetch([{ status: 400, json: { code: Number(code), message: 'provider text', more_info: 'https://www.twilio.com/docs/errors/' + code, status: 400 } }]);
    const r = await adapter(impl).send({ to: '+27821234567', body: 'x', contentSid: 'HX1', contentVariables: {} });
    expect(r.status).toBe('failed');
    expect(r.provider_ref).toBeNull();
    expect(r.provider_error_code).toBe(code);
    expect(r.error).toContain(text);
    expect(r.error).toContain('provider text');
    expect(calls).toHaveLength(1);
  });

  it('describes unknown codes with the provider message', () => {
    expect(describeTwilioError(99999, 'Weird')).toBe('Weird (99999)');
    expect(describeTwilioError(null, null)).toBe('Twilio request failed');
    expect(describeTwilioError('20003')).toContain('authentication failed');
  });

  it('retries once on 5xx and succeeds', async () => {
    const { impl, calls } = fakeFetch([{ status: 503, json: { code: 20503, message: 'Service unavailable' } }, { status: 201, json: { sid: 'SM789', status: 'queued' } }]);
    const r = await adapter(impl).send({ to: '+27821234567', body: 'x' });
    expect(r.status).toBe('sent');
    expect(r.provider_ref).toBe('SM789');
    expect(calls).toHaveLength(2);
    expect(calls[0].params.toString()).toBe(calls[1].params.toString());
  });

  it('gives up after the retry budget on persistent 5xx', async () => {
    const { impl, calls } = fakeFetch([{ status: 500, json: { code: 20500, message: 'boom' } }, { status: 502, json: {} }]);
    const r = await adapter(impl).send({ to: '+27821234567', body: 'x' });
    expect(r.status).toBe('failed');
    expect(r.provider_error_code).toBe('502');
    expect(calls).toHaveLength(2);
  });

  it('retries once on a network error / timeout', async () => {
    const { impl, calls } = fakeFetch([new Error('ECONNRESET'), { status: 201, json: { sid: 'SM1', status: 'queued' } }]);
    const r = await adapter(impl).send({ to: '+27821234567', body: 'x' });
    expect(r.status).toBe('sent');
    expect(calls).toHaveLength(2);

    const abort = Object.assign(new Error('aborted'), { name: 'AbortError' });
    const twice = fakeFetch([abort, abort]);
    const t = await adapter(twice.impl).send({ to: '+27821234567', body: 'x' });
    expect(t.status).toBe('failed');
    expect(t.provider_error_code).toBe('timeout');
    expect(t.error).toContain('timed out');
  });

  it('treats a 2xx without a SID as transient', async () => {
    const { impl, calls } = fakeFetch([{ status: 200, json: {} }, { status: 201, json: { sid: 'SM2' } }]);
    const r = await adapter(impl).send({ to: '+27821234567', body: 'x' });
    expect(r.provider_ref).toBe('SM2');
    expect(calls).toHaveLength(2);
  });
});

describe('Twilio webhook signature (X-Twilio-Signature)', () => {
  // Vector from https://www.twilio.com/docs/usage/webhooks/webhooks-security
  const url = 'https://mycompany.com/myapp.php?foo=1&bar=2';
  const params = { CallSid: 'CA1234567890ABCDE', Caller: '+12349013030', Digits: '1234', From: '+12349013030', To: '+18005551212' };

  it('reproduces the documented example signature', () => {
    expect(computeTwilioSignature('12345', url, params)).toBe('0/KCTR6DLpKmkAf8muzZqo1nDgQ=');
  });
  it('validates in constant time and rejects tampering, wrong tokens and missing inputs', () => {
    const sig = computeTwilioSignature('12345', url, params);
    expect(validateTwilioSignature('12345', sig, url, params)).toBe(true);
    expect(validateTwilioSignature('12345', sig, [`http://other/${'x'}`, url], params)).toBe(true);
    expect(validateTwilioSignature('12345', sig, url, { ...params, Digits: '9999' })).toBe(false);
    expect(validateTwilioSignature('54321', sig, url, params)).toBe(false);
    expect(validateTwilioSignature('12345', sig, 'https://mycompany.com/myapp.php', params)).toBe(false);
    expect(validateTwilioSignature('', sig, url, params)).toBe(false);
    expect(validateTwilioSignature('12345', undefined, url, params)).toBe(false);
    expect(validateTwilioSignature('12345', 'nope', url, params)).toBe(false);
  });
  it('sorts params by key and handles repeated keys', () => {
    const a = computeTwilioSignature('t', 'https://x/y', { B: '2', A: '1' });
    const b = computeTwilioSignature('t', 'https://x/y', { A: '1', B: '2' });
    expect(a).toBe(b);
    expect(computeTwilioSignature('t', 'https://x/y', { A: ['2', '1'] })).toBe(computeTwilioSignature('t', 'https://x/y', { A: ['1', '2'] }));
  });
});

describe('status mapping + adapter selection', () => {
  const saved = { ...process.env };
  afterEach(() => {
    for (const k of ['WHATSAPP_PROVIDER', 'TWILIO_ACCOUNT_SID', 'TWILIO_AUTH_TOKEN', 'PUBLIC_API_BASE_URL', 'TWILIO_MESSAGING_SERVICE_SID']) {
      if (saved[k] === undefined) delete process.env[k];
      else process.env[k] = saved[k];
    }
  });

  it('maps Twilio message statuses', () => {
    expect(mapTwilioStatus('queued')).toBe('queued');
    expect(mapTwilioStatus('accepted')).toBe('queued');
    expect(mapTwilioStatus('sending')).toBe('queued');
    expect(mapTwilioStatus('sent')).toBe('sent');
    expect(mapTwilioStatus('delivered')).toBe('delivered');
    expect(mapTwilioStatus('read')).toBe('delivered');
    expect(mapTwilioStatus('failed')).toBe('failed');
    expect(mapTwilioStatus('undelivered')).toBe('failed');
    expect(mapTwilioStatus('whatever')).toBeNull();
  });

  it('picks the adapter from config', () => {
    expect(getWhatsAppAdapter(false)).toBeInstanceOf(NoopWhatsAppAdapter);
    delete process.env.TWILIO_ACCOUNT_SID;
    delete process.env.TWILIO_AUTH_TOKEN;
    process.env.WHATSAPP_PROVIDER = '';
    expect(getWhatsAppAdapter(true)).toBeInstanceOf(SandboxWhatsAppAdapter);
    process.env.TWILIO_ACCOUNT_SID = SID;
    process.env.TWILIO_AUTH_TOKEN = TOKEN;
    const t = getWhatsAppAdapter(true);
    expect(t).toBeInstanceOf(TwilioWhatsAppAdapter);
    expect((t as TwilioWhatsAppAdapter).messagesUrl).toContain(SID);
    process.env.WHATSAPP_PROVIDER = 'sandbox';
    expect(getWhatsAppAdapter(true)).toBeInstanceOf(SandboxWhatsAppAdapter);
  });

  it('derives the status callback URL from PUBLIC_API_BASE_URL', () => {
    delete process.env.PUBLIC_API_BASE_URL;
    expect(twilioStatusCallbackUrl()).toBeNull();
    process.env.PUBLIC_API_BASE_URL = 'https://europe-west1-sparkling-4e89d.cloudfunctions.net/api/';
    expect(twilioStatusCallbackUrl()).toBe('https://europe-west1-sparkling-4e89d.cloudfunctions.net/api/v1/notifications/twilio/status');
  });
});
