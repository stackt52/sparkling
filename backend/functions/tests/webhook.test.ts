import { beforeEach, describe, expect, it } from 'vitest';
import { setFirebaseMessagingForTests } from '../src/lib/firebase.js';
import { setSupabaseClient } from '../src/lib/supabase.js';
import { handleProviderEvent, SandboxProvider, sandboxConfirm, setPaymentProviderForTests, type ProviderEvent } from '../src/services/payments.js';
import { nextReceiptNo } from '../src/lib/refs.js';
import { fakeSupabase, type FakeSupabase } from './helpers/fakeSupabase.js';

const BOOKING = '10000000-0000-4000-8000-000000000001';
const PAYMENT = '60000000-0000-4000-8000-000000000001';

let db: FakeSupabase;
const provider = new SandboxProvider('test-secret');

beforeEach(() => {
  db = fakeSupabase();
  db.seed('feature_flags', [{ key: 'whatsapp_enabled', enabled: false }]);
  db.seed('profiles', [{ id: 'cust_1', role: 'customer', full_name: 'Thabo', email: 't@example.com', phone: '+27831112222', is_active: true, marketing_opt_in: true, whatsapp_opt_in: true, push_opt_in: true }]);
  db.seed('outlets', [{ id: 'a0000000-0000-4000-8000-000000000001', name: 'Sparkling Sandton' }]);
  db.seed('services', [{ id: 'b0000000-0000-4000-8000-000000000002', name: 'Full Valet' }]);
  db.seed('bookings', [{ id: BOOKING, ref: 'SPK-2026-0091', customer_id: 'cust_1', outlet_id: 'a0000000-0000-4000-8000-000000000001', service_id: 'b0000000-0000-4000-8000-000000000002', status: 'pending', slot_start: '2026-09-08T08:00:00Z', total_cents: 19800 }]);
  db.seed('payments', [{ id: PAYMENT, booking_id: BOOKING, customer_id: 'cust_1', provider: 'sandbox', provider_ref: 'pi_1', amount_cents: 19800, currency: 'ZAR', status: 'pending', receipt_no: null, idempotency_key: 'k1' }]);
  db.seed('payments', [...db.rows('payments'), { id: 'p_old', booking_id: null, customer_id: 'cust_1', provider: 'sandbox', amount_cents: 100, status: 'successful', receipt_no: 'RCP-70004', idempotency_key: 'k0' }]);
  db.seed('notification_templates', [
    { key: 'payment_successful', channel: 'push', title: 'Payment received', body: 'R {{amount}} received. Receipt {{receipt}}.', is_promotional: false, is_active: true },
    { key: 'booking_confirmed', channel: 'push', title: 'Booking confirmed', body: '{{service}} at {{outlet}}. Ref {{ref}}.', is_promotional: false, is_active: true },
    { key: 'payment_failed', channel: 'push', title: 'Payment failed', body: 'We could not process R {{amount}}.', is_promotional: false, is_active: true },
  ]);
  db.seed('device_tokens', [{ profile_id: 'cust_1', token: 'tok_1', platform: 'android', app: 'customer' }]);
  setSupabaseClient(db as any);
  setPaymentProviderForTests(provider);
  setFirebaseMessagingForTests({ sendEachForMulticast: async ({ tokens }: { tokens: string[] }) => ({ successCount: tokens.length, failureCount: 0, responses: tokens.map(() => ({ success: true })) }) } as any);
});

function event(id: string, type: ProviderEvent['type'] = 'payment.succeeded'): ProviderEvent {
  return { id, type, payment_id: PAYMENT, amount_cents: 19800, provider_ref: 'pi_1' };
}

describe('payment webhook (API-009 / CUS-041..045)', () => {
  it('verifies HMAC signatures', () => {
    const raw = JSON.stringify(event('evt_1'));
    expect(provider.verifyWebhook(raw, provider.sign(raw))).toBe(true);
    expect(provider.verifyWebhook(raw, 'deadbeef')).toBe(false);
    expect(provider.verifyWebhook(raw, undefined)).toBe(false);
    expect(new SandboxProvider('other').verifyWebhook(raw, provider.sign(raw))).toBe(false);
  });

  it('allocates receipt numbers from the next_receipt_no RPC when it is available', async () => {
    let n = 70000;
    const rpcDb = fakeSupabase({ rpc: { next_receipt_no: () => `RCP-${n++}` } });
    for (const t of db.tables.keys()) rpcDb.seed(t, db.rows(t));
    setSupabaseClient(rpcDb as any);
    const out = await handleProviderEvent('sandbox', event('evt_rpc'), true, {});
    expect(out.payment?.receipt_no).toBe('RCP-70000');
    expect(await nextReceiptNo(rpcDb as any)).toBe('RCP-70001');
    expect(rpcDb.calls.filter((c) => c.table === 'payments' && c.op === 'select').length).toBe(1); // no max+1 scan
  });

  it('falls back to max+1 when the RPC errors or returns garbage', async () => {
    expect(await nextReceiptNo(db as any)).toBe('RCP-70005'); // fake has no rpc → 42883
    const bad = fakeSupabase({ rpc: { next_receipt_no: () => 'nope' } });
    bad.seed('payments', db.rows('payments'));
    expect(await nextReceiptNo(bad as any)).toBe('RCP-70005');
    const throwing = fakeSupabase({ rpc: { next_receipt_no: () => { throw new Error('boom'); } } });
    expect(await nextReceiptNo(throwing as any)).toBe('RCP-70000');
  });

  it('marks the payment successful, allocates a receipt (max+1 fallback), confirms the booking and notifies', async () => {
    const out = await handleProviderEvent('sandbox', event('evt_1'), true, {});
    expect(out.duplicate).toBe(false);
    expect(out.payment?.status).toBe('successful');
    expect(out.payment?.receipt_no).toBe('RCP-70005');
    expect(db.rows('bookings')[0].status).toBe('confirmed');
    const notes = db.rows('notifications');
    expect(notes.map((n) => n.template_key).sort()).toEqual(['booking_confirmed', 'payment_successful']);
    expect(notes.find((n) => n.template_key === 'payment_successful')?.body).toBe('R 198.00 received. Receipt RCP-70005.');
    expect(notes.every((n) => n.status === 'sent')).toBe(true);
    expect(db.rows('payment_events')).toHaveLength(1);
  });

  it('treats a replayed provider event id as a duplicate with no side effects', async () => {
    await handleProviderEvent('sandbox', event('evt_1'), true, {});
    const before = db.calls.length;
    const notesBefore = db.rows('notifications').length;
    const dup = await handleProviderEvent('sandbox', event('evt_1'), true, {});
    expect(dup.duplicate).toBe(true);
    expect(db.rows('payment_events')).toHaveLength(1);
    expect(db.rows('notifications')).toHaveLength(notesBefore);
    // Only the lookup + failed insert happened.
    expect(db.calls.length - before).toBe(2);
  });

  it('ignores out-of-order events after success (failed after successful)', async () => {
    await handleProviderEvent('sandbox', event('evt_1'), true, {});
    const out = await handleProviderEvent('sandbox', event('evt_2', 'payment.failed'), true, {});
    expect(out.duplicate).toBe(false);
    expect(out.ignored).toContain('cannot move');
    expect(db.rows('payments').find((p) => p.id === PAYMENT)?.status).toBe('successful');
  });

  it('sandbox-confirm runs the same signed handler in-process', async () => {
    const payment = db.rows('payments').find((p) => p.id === PAYMENT)!;
    const out = await sandboxConfirm(payment as any, 'succeeded');
    expect(out.payment?.status).toBe('successful');
    expect(db.rows('payment_events')[0].signature_ok).toBe(true);
    expect(db.rows('payment_events')[0].event_type).toBe('payment.succeeded');
  });

  it('records failure with reason and sends payment_failed', async () => {
    const out = await handleProviderEvent('sandbox', { ...event('evt_f', 'payment.failed'), reason: 'card_declined' }, true, {});
    expect(out.payment?.status).toBe('failed');
    expect(out.payment?.failure_reason).toBe('card_declined');
    expect(db.rows('notifications').map((n) => n.template_key)).toEqual(['payment_failed']);
  });
});
