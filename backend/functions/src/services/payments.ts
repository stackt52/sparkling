/**
 * CUS-040..045 / API-009: provider adapter + webhook handling.
 * Only a verified provider event (or the sandbox confirm endpoint, which
 * builds one) may move a payment to `successful`.
 */
import { createHmac, randomUUID, timingSafeEqual } from 'node:crypto';
import { config } from '../config.js';
import { nextReceiptNo } from '../lib/refs.js';
import { DatabaseError, getSupabase, PG_UNIQUE_VIOLATION, unwrap } from '../lib/supabase.js';
import { ApiError } from '../middleware/errors.js';
import { logger } from '../middleware/correlation.js';
import { canTransitionBooking, canTransitionPayment } from '../domain/stateMachines.js';
import type { Booking, Payment, PaymentStatus } from '../types.js';
import { formatRand, notify } from './notifications.js';

export type ProviderEventType = 'payment.succeeded' | 'payment.failed' | 'payment.refunded' | 'payment.cancelled';

export interface ProviderEvent {
  id: string;
  type: ProviderEventType;
  payment_id: string;
  provider_ref?: string | null;
  amount_cents?: number;
  reason?: string | null;
  created_at?: string;
}

export interface CreateIntentInput {
  payment: Payment;
  methodToken?: string | null;
}

export interface CreateIntentResult {
  provider_ref: string;
  client_secret?: string;
  redirect_url?: string;
}

export interface PaymentProvider {
  readonly name: string;
  createIntent(input: CreateIntentInput): Promise<CreateIntentResult>;
  verifyWebhook(rawBody: string | Buffer, signature: string | undefined): boolean;
  parseEvent(rawBody: string | Buffer): ProviderEvent;
  /** Test helper: produce a signed payload (sandbox only). */
  sign?(rawBody: string): string;
}

export class SandboxProvider implements PaymentProvider {
  readonly name = 'sandbox';
  constructor(private readonly secret: string) {}

  async createIntent(input: CreateIntentInput): Promise<CreateIntentResult> {
    const ref = `pi_sbx_${input.payment.id.slice(0, 8)}_${randomUUID().slice(0, 8)}`;
    return { provider_ref: ref, client_secret: `${ref}_secret_${randomUUID().slice(0, 12)}` };
  }

  sign(rawBody: string): string {
    return createHmac('sha256', this.secret).update(rawBody).digest('hex');
  }

  verifyWebhook(rawBody: string | Buffer, signature: string | undefined): boolean {
    if (!signature) return false;
    const expected = this.sign(typeof rawBody === 'string' ? rawBody : rawBody.toString('utf8'));
    const a = Buffer.from(expected, 'utf8');
    const b = Buffer.from(signature.trim().toLowerCase(), 'utf8');
    return a.length === b.length && timingSafeEqual(a, b);
  }

  parseEvent(rawBody: string | Buffer): ProviderEvent {
    let parsed: unknown;
    try {
      parsed = JSON.parse(typeof rawBody === 'string' ? rawBody : rawBody.toString('utf8'));
    } catch {
      throw ApiError.validation('Webhook body is not valid JSON');
    }
    const e = parsed as Partial<ProviderEvent>;
    if (!e || typeof e.id !== 'string' || typeof e.type !== 'string' || typeof e.payment_id !== 'string') {
      throw ApiError.validation('Webhook event missing id/type/payment_id');
    }
    return {
      id: e.id,
      type: e.type as ProviderEventType,
      payment_id: e.payment_id,
      provider_ref: e.provider_ref ?? null,
      amount_cents: typeof e.amount_cents === 'number' ? e.amount_cents : undefined,
      reason: e.reason ?? null,
      created_at: e.created_at,
    };
  }
}

let providerOverride: PaymentProvider | null = null;
export function getPaymentProvider(): PaymentProvider {
  return providerOverride ?? new SandboxProvider(config.paymentWebhookSecret);
}
export function setPaymentProviderForTests(p: PaymentProvider | null): void {
  providerOverride = p;
}

const EVENT_TO_STATUS: Record<ProviderEventType, PaymentStatus> = {
  'payment.succeeded': 'successful',
  'payment.failed': 'failed',
  'payment.refunded': 'refunded',
  'payment.cancelled': 'cancelled',
};

export interface WebhookOutcome {
  duplicate: boolean;
  payment?: Payment;
  ignored?: string;
}

/**
 * Idempotent webhook processing: records `payment_events` first (unique on
 * provider + event id) — a duplicate returns `{duplicate:true}` with no side
 * effects; otherwise transitions the payment and runs side effects.
 */
export async function handleProviderEvent(provider: string, event: ProviderEvent, signatureOk: boolean, rawPayload: unknown): Promise<WebhookOutcome> {
  const db = getSupabase();
  const payment = unwrap<Payment | null>(await db.from('payments').select('*').eq('id', event.payment_id).maybeSingle(), 'payment');

  const inserted = await db.from('payment_events').insert({
    payment_id: payment?.id ?? null,
    provider,
    provider_event_id: event.id,
    event_type: event.type,
    signature_ok: signatureOk,
    payload: rawPayload ?? {},
  });
  if (inserted.error) {
    if (inserted.error.code === PG_UNIQUE_VIOLATION) return { duplicate: true, payment: payment ?? undefined };
    throw new DatabaseError(inserted.error, 'payment event');
  }
  if (!payment) throw ApiError.notFound('Payment');

  const target = EVENT_TO_STATUS[event.type];
  if (!target) return { duplicate: false, payment, ignored: `unknown event ${event.type}` };
  if (payment.status === target) return { duplicate: false, payment, ignored: 'already in target state' };
  if (!canTransitionPayment(payment.status, target)) {
    logger.warn({ payment_id: payment.id, from: payment.status, to: target }, 'ignoring out-of-order payment event');
    return { duplicate: false, payment, ignored: `cannot move ${payment.status} → ${target}` };
  }
  if (event.amount_cents !== undefined && target === 'successful' && event.amount_cents !== payment.amount_cents) {
    await db.from('payments').update({ status: 'failed', failure_reason: 'amount_mismatch' }).eq('id', payment.id);
    throw ApiError.conflict('Amount mismatch', { expected: payment.amount_cents, received: event.amount_cents });
  }

  const patch: Partial<Payment> = { status: target, provider_ref: event.provider_ref ?? payment.provider_ref };
  if (target === 'successful') {
    patch.verified_at = new Date().toISOString();
    patch.receipt_no = payment.receipt_no ?? (await allocateReceipt(db));
  }
  if (target === 'failed' || target === 'cancelled') patch.failure_reason = event.reason ?? null;

  let updated: Payment | null = null;
  for (let attempt = 0; attempt < 3 && !updated; attempt++) {
    const res = await db.from('payments').update(patch).eq('id', payment.id).select('*').single();
    if (res.error) {
      if (res.error.code === PG_UNIQUE_VIOLATION && target === 'successful') {
        patch.receipt_no = await allocateReceipt(db);
        continue;
      }
      throw new DatabaseError(res.error, 'payment update');
    }
    updated = res.data as Payment;
  }
  if (!updated) throw ApiError.internal('Payment update failed');

  await runSideEffects(updated, target);
  return { duplicate: false, payment: updated };
}

async function allocateReceipt(db: ReturnType<typeof getSupabase>): Promise<string> {
  return nextReceiptNo(db);
}

async function runSideEffects(payment: Payment, target: PaymentStatus): Promise<void> {
  const db = getSupabase();
  let booking: Booking | null = null;
  if (payment.booking_id) {
    booking = unwrap<Booking | null>(await db.from('bookings').select('*').eq('id', payment.booking_id).maybeSingle(), 'booking');
  }
  if (target === 'successful') {
    if (booking && booking.status === 'pending' && canTransitionBooking(booking.status, 'confirmed')) {
      await db.from('bookings').update({ status: 'confirmed' }).eq('id', booking.id);
      const [outlet, service] = await Promise.all([
        db.from('outlets').select('name').eq('id', booking.outlet_id).maybeSingle(),
        db.from('services').select('name').eq('id', booking.service_id).maybeSingle(),
      ]);
      await notify({
        recipientId: booking.customer_id,
        templateKey: 'booking_confirmed',
        vars: {
          service: (service.data as { name: string } | null)?.name ?? '',
          outlet: (outlet.data as { name: string } | null)?.name ?? '',
          slot: booking.slot_start,
          ref: booking.ref,
          name: '',
        },
        dedupeKey: `booking_confirmed:${booking.id}`,
        payload: { type: 'booking', booking_id: booking.id },
      });
    }
    await notify({
      recipientId: payment.customer_id,
      templateKey: 'payment_successful',
      vars: { amount: formatRand(payment.amount_cents), receipt: payment.receipt_no ?? '' },
      dedupeKey: `payment_successful:${payment.id}`,
      payload: { type: 'payment', payment_id: payment.id, booking_id: payment.booking_id },
    });
  } else if (target === 'failed') {
    await notify({
      recipientId: payment.customer_id,
      templateKey: 'payment_failed',
      vars: { amount: formatRand(payment.amount_cents) },
      dedupeKey: `payment_failed:${payment.id}:${payment.updated_at}`,
      payload: { type: 'payment', payment_id: payment.id, booking_id: payment.booking_id },
    });
  }
}

/** Builds a signed sandbox event and runs it through the same handler in-process. */
export async function sandboxConfirm(payment: Payment, outcome: 'succeeded' | 'failed' = 'succeeded'): Promise<WebhookOutcome> {
  const provider = getPaymentProvider();
  const event: ProviderEvent = {
    id: `evt_sbx_${payment.id.slice(0, 8)}_${outcome}_${randomUUID().slice(0, 8)}`,
    type: outcome === 'succeeded' ? 'payment.succeeded' : 'payment.failed',
    payment_id: payment.id,
    provider_ref: payment.provider_ref,
    amount_cents: payment.amount_cents,
    reason: outcome === 'failed' ? 'sandbox_declined' : null,
    created_at: new Date().toISOString(),
  };
  const raw = JSON.stringify(event);
  const signature = provider.sign ? provider.sign(raw) : '';
  const ok = provider.verifyWebhook(raw, signature);
  if (!ok) throw ApiError.internal('Sandbox signature verification failed');
  return handleProviderEvent(provider.name, provider.parseEvent(raw), true, event);
}
