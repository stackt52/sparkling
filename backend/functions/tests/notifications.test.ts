import { beforeEach, describe, expect, it } from 'vitest';
import { setFirebaseMessagingForTests } from '../src/lib/firebase.js';
import { setSupabaseClient } from '../src/lib/supabase.js';
import { invalidateFlags } from '../src/services/flags.js';
import { formatRand, notify, renderTemplate } from '../src/services/notifications.js';
import { fakeSupabase, type FakeSupabase } from './helpers/fakeSupabase.js';

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
