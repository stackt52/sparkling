import { afterEach, beforeEach, describe, expect, it } from 'vitest';
import { setFirebaseMessagingForTests } from '../src/lib/firebase.js';
import { setSupabaseClient } from '../src/lib/supabase.js';
import { setWhatsAppAdapterForTests, type WhatsAppAdapter, type WhatsAppSendInput, type WhatsAppSendResult } from '../src/lib/whatsapp.js';
import { invalidateFlags } from '../src/services/flags.js';
import { buildContentVariables, firstName, formatRand, notify, renderTemplate, resendNotification } from '../src/services/notifications.js';
import { fakeSupabase, type FakeSupabase } from './helpers/fakeSupabase.js';
import { makeCtx } from './helpers/context.js';

describe('template rendering (NOT-001)', () => {
  it('substitutes {{vars}} and blanks unknown ones', () => {
    expect(renderTemplate('{{service}} at {{outlet}} on {{slot}}. Ref {{ref}}.', { service: 'Full Valet', outlet: 'Sandton', slot: '08:00', ref: 'SPK-1' })).toBe('Full Valet at Sandton on 08:00. Ref SPK-1.');
    expect(renderTemplate('Hi {{ name }}, {{missing}}!', { name: 'Thabo' })).toBe('Hi Thabo, !');
    expect(renderTemplate(null, {})).toBe('');
    expect(renderTemplate('+{{points}} pts. Balance {{balance}}.', { points: 25, balance: 1475 })).toBe('+25 pts. Balance 1475.');
  });
  it('formats rand amounts', () => {
    expect(formatRand(19800)).toBe('198.00');
    expect(formatRand(385000)).toBe('3 850.00');
    expect(formatRand(5)).toBe('0.05');
  });
  it('derives first_name like the legacy capitalize()', () => {
    expect(firstName('thabo mokoena')).toBe('Thabo');
    expect(firstName('  Naledi ')).toBe('Naledi');
    expect(firstName('')).toBe('');
    expect(firstName(null)).toBe('');
  });
  it('builds positional Twilio ContentVariables from provider_variables', () => {
    expect(buildContentVariables({ '1': 'first_name', '2': 'quotation_id' }, { first_name: 'Thabo', quotation_id: 'q-1', ref: 'QT-1' })).toEqual({ variables: { '1': 'Thabo', '2': 'q-1' }, missing: [] });
    expect(buildContentVariables({ '1': 'otp' }, { otp: 12345 })).toEqual({ variables: { '1': '12345' }, missing: [] });
    expect(buildContentVariables({ '1': 'otp', '2': 'nope' }, { otp: '1' })).toEqual({ variables: { '1': '1', '2': '' }, missing: ['nope'] });
    expect(buildContentVariables(null, { a: 1 })).toEqual({ variables: {}, missing: [] });
  });
});

describe('notify() (NOT-002..004)', () => {
  let db: FakeSupabase;
  let sent: string[][] = [];
  beforeEach(() => {
    sent = [];
    db = fakeSupabase();
    db.seed('feature_flags', [{ key: 'whatsapp_enabled', enabled: false }]);
    db.seed('profiles', [
      { id: 'c1', role: 'customer', full_name: 'A', phone: '+27830000000', marketing_opt_in: false, whatsapp_opt_in: true, push_opt_in: true, is_active: true },
      { id: 'c2', role: 'customer', full_name: 'B', phone: '+27830000001', marketing_opt_in: true, whatsapp_opt_in: true, push_opt_in: true, is_active: true },
    ]);
    db.seed('notification_templates', [
      { key: 'service_ready', channel: 'push', title: 'Ready', body: 'Your {{vehicle}} is ready at {{outlet}}.', is_promotional: false, is_active: true },
      { key: 'service_ready', channel: 'whatsapp', title: null, body: 'Ready at {{outlet}}. Ref {{ref}}.', is_promotional: false, is_active: true },
      { key: 'promo_weekend', channel: 'whatsapp', title: null, body: 'Weekend special', is_promotional: true, is_active: true },
    ]);
    db.seed('device_tokens', [{ profile_id: 'c1', token: 'tok_c1', platform: 'ios', app: 'customer' }, { profile_id: 'c1', token: 'tok_dead', platform: 'android', app: 'customer' }]);
    setSupabaseClient(db as any);
    invalidateFlags();
    setFirebaseMessagingForTests({
      sendEachForMulticast: async ({ tokens }: { tokens: string[] }) => {
        sent.push(tokens);
        return { successCount: tokens.filter((t) => t !== 'tok_dead').length, failureCount: tokens.filter((t) => t === 'tok_dead').length, responses: tokens.map((t) => (t === 'tok_dead' ? { success: false, error: { code: 'messaging/registration-token-not-registered' } } : { success: true })) };
      },
    } as any);
  });

  it('renders, stores, pushes via FCM, prunes dead tokens, and suppresses WhatsApp when the flag is off', async () => {
    const out = await notify({ recipientId: 'c1', templateKey: 'service_ready', vars: { vehicle: 'Toyota Corolla Cross', outlet: 'Sandton', ref: 'WO-1' }, dedupeKey: 'service_ready:wo1' });
    expect(out.map((o) => [o.channel, o.status])).toEqual([['push', 'sent'], ['whatsapp', 'suppressed']]);
    const rows = db.rows('notifications');
    expect(rows.find((r) => r.channel === 'push')?.body).toBe('Your Toyota Corolla Cross is ready at Sandton.');
    expect(rows.find((r) => r.channel === 'push')?.dedupe_key).toBe('service_ready:wo1:push');
    expect(sent[0]).toEqual(['tok_c1', 'tok_dead']);
    expect(db.rows('device_tokens').map((t) => t.token)).toEqual(['tok_c1']);
  });

  it('dedupes by dedupe_key', async () => {
    await notify({ recipientId: 'c1', templateKey: 'service_ready', vars: {}, dedupeKey: 'k', channels: ['push'] });
    const second = await notify({ recipientId: 'c1', templateKey: 'service_ready', vars: {}, dedupeKey: 'k', channels: ['push'] });
    expect(second[0].status).toBe('duplicate');
    expect(db.rows('notifications')).toHaveLength(1);
    expect(sent).toHaveLength(1);
  });

  it('suppresses promotional templates when marketing_opt_in=false (CUS-053)', async () => {
    const a = await notify({ recipientId: 'c1', templateKey: 'promo_weekend', vars: {}, dedupeKey: 'promo:c1' });
    expect(a[0].status).toBe('suppressed');
    expect(db.rows('notifications')[0].status).toBe('suppressed');
    const b = await notify({ recipientId: 'c2', templateKey: 'promo_weekend', vars: {}, dedupeKey: 'promo:c2' });
    // opted in, but whatsapp flag is off → suppressed by the channel gate, not consent
    expect(b[0].status).toBe('suppressed');
    expect(db.rows('notifications')[1].error).toContain('whatsapp_enabled');
  });

  it('marks push failed when FCM throws', async () => {
    setFirebaseMessagingForTests({ sendEachForMulticast: async () => { throw new Error('boom'); } } as any);
    const out = await notify({ recipientId: 'c1', templateKey: 'service_ready', vars: {}, dedupeKey: 'fail', channels: ['push'] });
    expect(out[0].status).toBe('failed');
    expect(db.rows('notifications')[0].error).toBe('boom');
  });
});

describe('notify() with Twilio Content templates + admin resend', () => {
  let db: FakeSupabase;
  let sends: WhatsAppSendInput[];
  let nextResult: WhatsAppSendResult;
  const HX_QUOTE = 'HX011c7f1b31697f8e21d36ff6b4d02b06';
  const HX_OTP = 'HX63a748f8b6680eac890e0137dfcf0fdb';

  const adapter: WhatsAppAdapter = {
    name: 'fake-twilio',
    async send(input) {
      sends.push(input);
      return nextResult;
    },
  };

  beforeEach(() => {
    sends = [];
    nextResult = { provider_ref: 'SM_ok', status: 'sent', provider_status: 'queued' };
    db = fakeSupabase();
    db.seed('feature_flags', [{ key: 'whatsapp_enabled', enabled: true }]);
    db.seed('profiles', [
      { id: 'c1', role: 'customer', full_name: 'thabo mokoena', phone: '082 000 0000', marketing_opt_in: false, whatsapp_opt_in: true, push_opt_in: true, is_active: true },
      { id: 'c3', role: 'customer', full_name: 'No Phone', phone: null, marketing_opt_in: false, whatsapp_opt_in: true, push_opt_in: false, is_active: true },
    ]);
    db.seed('notification_templates', [
      { key: 'quote_ready', channel: 'whatsapp', title: null, body: 'Hi {{first_name}}, your quotation {{ref}} is ready.', is_promotional: false, is_active: true, provider: 'twilio', provider_template_sid: HX_QUOTE, provider_variables: { '1': 'first_name', '2': 'quotation_id' } },
      { key: 'quote_ready', channel: 'push', title: 'Quote ready', body: '{{ref}}: R {{amount}}.', is_promotional: false, is_active: true, provider: null, provider_template_sid: null, provider_variables: {} },
      { key: 'pickup_otp', channel: 'whatsapp', title: null, body: 'Your Sparkling collection OTP is {{otp}}.', is_promotional: false, is_active: true, provider: 'twilio', provider_template_sid: HX_OTP, provider_variables: { '1': 'otp' } },
      { key: 'booking_confirmed', channel: 'whatsapp', title: null, body: 'Hi {{name}}, booking {{ref}} confirmed.', is_promotional: false, is_active: true, provider: null, provider_template_sid: null, provider_variables: {} },
    ]);
    setSupabaseClient(db as any);
    invalidateFlags();
    setWhatsAppAdapterForTests(adapter);
    setFirebaseMessagingForTests({ sendEachForMulticast: async () => ({ successCount: 0, failureCount: 0, responses: [] }) } as any);
    delete process.env.PUBLIC_API_BASE_URL;
  });
  afterEach(() => {
    setWhatsAppAdapterForTests(null);
    delete process.env.PUBLIC_API_BASE_URL;
  });

  it('sends the Content SID with positional variables resolved from the render context and persists vars/provider fields', async () => {
    process.env.PUBLIC_API_BASE_URL = 'https://api.example.com';
    const out = await notify({ recipientId: 'c1', templateKey: 'quote_ready', vars: { ref: 'QT-2026-1001', amount: '3 850.00', quotation_id: 'q-1' }, dedupeKey: 'quote_ready:q-1', payload: { type: 'quotation', quotation_id: 'q-1' } });
    expect(out.map((o) => [o.channel, o.status])).toEqual([['whatsapp', 'sent'], ['push', 'queued']]);
    expect(sends).toHaveLength(1);
    expect(sends[0]).toMatchObject({
      to: '082 000 0000',
      body: 'Hi Thabo, your quotation QT-2026-1001 is ready.',
      contentSid: HX_QUOTE,
      contentVariables: { '1': 'Thabo', '2': 'q-1' },
      statusCallback: 'https://api.example.com/v1/notifications/twilio/status',
      meta: { template: 'quote_ready', notification_id: expect.any(String) },
    });
    const wa = db.rows('notifications').find((n) => n.channel === 'whatsapp')!;
    expect(wa).toMatchObject({ status: 'sent', provider_ref: 'SM_ok', provider_status: 'queued', provider_error_code: null, error: null, attempts: 1 });
    expect(typeof wa.sent_at).toBe('string');
    expect(wa.payload).toEqual({ type: 'quotation', quotation_id: 'q-1', vars: { first_name: 'Thabo', name: 'thabo mokoena', ref: 'QT-2026-1001', amount: '3 850.00', quotation_id: 'q-1' } });
  });

  it('sends free-form templates without a Content SID and records the session warning', async () => {
    nextResult = { provider_ref: 'SM_ff', status: 'sent', provider_status: 'queued', warning: 'session only' };
    await notify({ recipientId: 'c1', templateKey: 'booking_confirmed', vars: { ref: 'SPK-1' }, dedupeKey: 'bc:1' });
    expect(sends[0]).toMatchObject({ contentSid: null, contentVariables: null, body: 'Hi thabo mokoena, booking SPK-1 confirmed.', statusCallback: null });
    expect(db.rows('notifications')[0].error).toBe('warning: session only');
  });

  it('records provider failures with the Twilio error code', async () => {
    nextResult = { provider_ref: null, status: 'failed', error: 'Outside the 24-hour customer session (63016)', provider_error_code: '63016' };
    const out = await notify({ recipientId: 'c1', templateKey: 'pickup_otp', vars: { otp: '48213' }, dedupeKey: 'otp:1', channels: ['whatsapp'] });
    expect(out[0].status).toBe('failed');
    expect(sends[0].contentVariables).toEqual({ '1': '48213' });
    const row = db.rows('notifications')[0];
    expect(row).toMatchObject({ status: 'failed', provider_error_code: '63016', provider_ref: null, sent_at: null, attempts: 1 });
    expect(row.error).toContain('63016');
  });

  it('admin resend re-sends a failed row from payload.vars, bumps attempts and audits; refuses non-resendable rows', async () => {
    nextResult = { provider_ref: null, status: 'failed', error: 'boom', provider_error_code: '63016' };
    const [first] = await notify({ recipientId: 'c1', templateKey: 'quote_ready', vars: { ref: 'QT-9', amount: '1.00', quotation_id: 'q-9' }, dedupeKey: 'quote_ready:q-9', channels: ['whatsapp'] });
    expect(first.status).toBe('failed');

    nextResult = { provider_ref: 'SM_retry', status: 'sent', provider_status: 'accepted' };
    const ctx = makeCtx('manager', 'uid_manager');
    const out = await resendNotification(ctx, first.id!);
    expect(out.outcome).toEqual({ channel: 'whatsapp', status: 'sent', id: first.id });
    expect(out.notification).toMatchObject({ status: 'sent', attempts: 2, provider_ref: 'SM_retry', provider_status: 'accepted', provider_error_code: null, error: null });
    expect(sends).toHaveLength(2);
    expect(sends[1]).toMatchObject({ contentSid: HX_QUOTE, contentVariables: { '1': 'Thabo', '2': 'q-9' }, body: 'Hi Thabo, your quotation QT-9 is ready.' });
    const audit = db.rows('audit_events').find((a) => a.action === 'notification.resend')!;
    expect(audit).toMatchObject({ actor_id: 'uid_manager', entity_type: 'notification', entity_id: first.id, before: { status: 'failed', attempts: 1 }, after: { status: 'sent', attempts: 2, provider_ref: 'SM_retry' } });

    // now sent → cannot resend again
    await expect(resendNotification(ctx, first.id!)).rejects.toMatchObject({ code: 'conflict' });
    await expect(resendNotification(ctx, '90000000-0000-4000-8000-00000000dead')).rejects.toMatchObject({ code: 'not_found' });
  });

  it('admin resend delivers a row that was suppressed while whatsapp_enabled was off', async () => {
    db.rows('feature_flags')[0].enabled = false;
    invalidateFlags();
    const [sup] = await notify({ recipientId: 'c1', templateKey: 'pickup_otp', vars: { otp: '55555' }, dedupeKey: 'otp:2', channels: ['whatsapp'] });
    expect(sup.status).toBe('suppressed');
    expect(sends).toHaveLength(0);

    db.rows('feature_flags')[0].enabled = true;
    invalidateFlags();
    const out = await resendNotification(makeCtx('admin', 'uid_admin'), sup.id!);
    expect(out.notification.status).toBe('sent');
    expect(out.notification.attempts).toBe(2);
    expect(sends[0].contentVariables).toEqual({ '1': '55555' });
  });

  it('admin resend keeps consent gates (suppressed stays suppressed) and fails without a phone', async () => {
    const [row] = await notify({ recipientId: 'c3', templateKey: 'quote_ready', vars: { ref: 'QT-3', quotation_id: 'q-3' }, dedupeKey: 'quote_ready:q-3', channels: ['whatsapp'] });
    expect(row.status).toBe('suppressed'); // no phone
    db.rows('profiles').find((p) => p.id === 'c3')!.phone = '+27820000003';
    nextResult = { provider_ref: 'SM_c3', status: 'sent', provider_status: 'queued' };
    const out = await resendNotification(makeCtx('manager', 'uid_manager'), row.id!);
    expect(out.notification.status).toBe('sent');

    db.rows('profiles').find((p) => p.id === 'c3')!.whatsapp_opt_in = false;
    db.rows('notifications')[0].status = 'failed';
    const gated = await resendNotification(makeCtx('manager', 'uid_manager'), row.id!);
    expect(gated.notification.status).toBe('suppressed');
    expect(gated.notification.error).toBe('whatsapp_opt_in=false');
    expect(sends).toHaveLength(1);
  });
});
