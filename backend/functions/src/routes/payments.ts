/** Payments (CUS-040..045, API-009). */
import { Router, raw as rawBody } from 'express';
import { z } from 'zod';
import { getSupabase, unwrap } from '../lib/supabase.js';
import { parseBody, uuid } from '../lib/validate.js';
import { requireProfile, requireRole } from '../middleware/auth.js';
import { ApiError, asyncHandler } from '../middleware/errors.js';
import { paymentLimiter, webhookLimiter } from '../middleware/rateLimit.js';
import { audit } from '../services/audit.js';
import { flagEnabled } from '../services/flags.js';
import { getBookingOrThrow } from '../services/bookings.js';
import { getPaymentProvider, handleProviderEvent, sandboxConfirm } from '../services/payments.js';
import type { Payment } from '../types.js';

/** Unauthenticated webhook router (mounted before auth). */
export const paymentsWebhookRouter = Router();

paymentsWebhookRouter.post(
  '/payments/webhook',
  webhookLimiter,
  rawBody({ type: '*/*', limit: '256kb' }),
  asyncHandler(async (req, res) => {
    const provider = getPaymentProvider();
    const raw: Buffer = Buffer.isBuffer(req.body) ? req.body : Buffer.from(typeof req.body === 'string' ? req.body : JSON.stringify(req.body ?? {}));
    const signature = req.header('X-Signature');
    const ok = provider.verifyWebhook(raw, signature);
    if (!ok) {
      req.log.warn('webhook signature invalid');
      throw ApiError.unauthenticated('Invalid webhook signature');
    }
    const event = provider.parseEvent(raw);
    let payload: unknown = {};
    try {
      payload = JSON.parse(raw.toString('utf8'));
    } catch {
      payload = {};
    }
    const outcome = await handleProviderEvent(provider.name, event, true, payload);
    if (outcome.duplicate) return res.json({ duplicate: true });
    res.json({ received: true, payment_id: outcome.payment?.id, status: outcome.payment?.status, ignored: outcome.ignored ?? null });
  }),
);

export const paymentsRouter = Router();
paymentsRouter.use('/payments', requireProfile);

paymentsRouter.get(
  '/payments/methods',
  requireRole('customer'),
  asyncHandler(async (req, res) => {
    const db = getSupabase();
    const rows = unwrap<unknown[]>(
      await db.from('payment_methods').select('id, provider, brand, last4, label, is_default, created_at').eq('customer_id', req.auth!.uid).order('is_default', { ascending: false }),
      'methods',
    );
    res.json({ data: rows });
  }),
);

const methodSchema = z.object({
  provider_token: z.string().min(4).max(256).regex(/^(tok|pm|card)_/i, 'Expected a provider token, never a PAN'),
  brand: z.string().trim().max(32),
  last4: z.string().regex(/^\d{4}$/).nullable().optional(),
  label: z.string().trim().max(60).optional(),
  is_default: z.boolean().optional(),
});

paymentsRouter.post(
  '/payments/methods',
  requireRole('customer'),
  asyncHandler(async (req, res) => {
    const body = parseBody(methodSchema, req.body);
    const db = getSupabase();
    if (body.is_default) await db.from('payment_methods').update({ is_default: false }).eq('customer_id', req.auth!.uid);
    const row = unwrap<Record<string, unknown>>(
      await db
        .from('payment_methods')
        .insert({ customer_id: req.auth!.uid, provider: getPaymentProvider().name, token: body.provider_token, brand: body.brand, last4: body.last4 ?? null, label: body.label ?? `${body.brand} •••• ${body.last4 ?? ''}`.trim(), is_default: body.is_default ?? false })
        .select('id, provider, brand, last4, label, is_default, created_at')
        .single(),
      'method',
    );
    res.status(201).json({ method: row });
  }),
);

const intentSchema = z.object({
  booking_id: uuid,
  method_id: uuid.nullable().optional(),
  idempotency_key: z.string().min(6).max(128),
});

paymentsRouter.post(
  '/payments/intents',
  requireRole('customer'),
  paymentLimiter,
  asyncHandler(async (req, res) => {
    const body = parseBody(intentSchema, req.body);
    const db = getSupabase();
    const uid = req.auth!.uid;
    const key = `${uid}:${body.idempotency_key}`;
    const existing = unwrap<Payment | null>(await db.from('payments').select('*').eq('idempotency_key', key).maybeSingle(), 'payment');
    if (existing) return res.json({ payment: existing, client_secret: null, redirect_url: null, duplicate: true });

    const booking = await getBookingOrThrow(body.booking_id);
    if (booking.customer_id !== uid) throw ApiError.forbidden();
    if (!['pending', 'confirmed', 'in_service', 'completed'].includes(booking.status)) throw ApiError.conflict(`Booking is ${booking.status}`);
    const paid = unwrap<Payment[]>(await db.from('payments').select('*').eq('booking_id', booking.id).eq('status', 'successful'), 'payments');
    if (paid.length) throw ApiError.conflict('Booking is already paid', { payment_id: paid[0].id });
    if (body.method_id) {
      const m = await db.from('payment_methods').select('id, token').eq('id', body.method_id).eq('customer_id', uid).maybeSingle();
      if (!m.data) throw ApiError.validation('Unknown payment method');
    }
    const provider = getPaymentProvider();
    const initiated = unwrap<Payment>(
      await db
        .from('payments')
        .insert({ booking_id: booking.id, customer_id: uid, provider: provider.name, method_id: body.method_id ?? null, amount_cents: booking.total_cents, currency: 'ZAR', status: 'initiated', idempotency_key: key })
        .select('*')
        .single(),
      'create payment',
    );
    const intent = await provider.createIntent({ payment: initiated });
    const payment = unwrap<Payment>(
      await db.from('payments').update({ status: 'pending', provider_ref: intent.provider_ref }).eq('id', initiated.id).select('*').single(),
      'payment pending',
    );
    await audit(req.ctx, { action: 'payment.intent', entity_type: 'payment', entity_id: payment.id, outlet_id: booking.outlet_id, after: { amount_cents: payment.amount_cents } });
    res.status(201).json({ payment, client_secret: intent.client_secret ?? null, redirect_url: intent.redirect_url ?? null });
  }),
);

paymentsRouter.post(
  '/payments/:id/sandbox-confirm',
  requireRole('customer'),
  paymentLimiter,
  asyncHandler(async (req, res) => {
    const id = uuid.parse(req.params.id);
    const body = parseBody(z.object({ outcome: z.enum(['succeeded', 'failed']).default('succeeded') }), req.body);
    if (!(await flagEnabled('payments_sandbox'))) throw ApiError.forbidden('Sandbox payments are disabled');
    const db = getSupabase();
    const payment = unwrap<Payment | null>(await db.from('payments').select('*').eq('id', id).maybeSingle(), 'payment');
    if (!payment) throw ApiError.notFound('Payment');
    if (payment.customer_id !== req.auth!.uid) throw ApiError.forbidden();
    if (payment.status !== 'pending' && payment.status !== 'initiated') throw ApiError.invalidTransition(payment.status, body.outcome === 'succeeded' ? 'successful' : 'failed', 'payment');
    const outcome = await sandboxConfirm(payment, body.outcome);
    res.json({ payment: outcome.payment, duplicate: outcome.duplicate });
  }),
);

paymentsRouter.get(
  '/payments/:id',
  asyncHandler(async (req, res) => {
    const id = uuid.parse(req.params.id);
    const db = getSupabase();
    const payment = unwrap<(Payment & Record<string, unknown>) | null>(
      await db.from('payments').select('*, booking:bookings(id, ref, slot_start, outlet_id, service_id), method:payment_methods(id, brand, last4, label)').eq('id', id).maybeSingle(),
      'payment',
    );
    if (!payment) throw ApiError.notFound('Payment');
    const auth = req.auth!;
    if (payment.customer_id !== auth.uid && !['finance', 'admin', 'manager'].includes(auth.role)) throw ApiError.forbidden();
    const receipt =
      payment.status === 'successful'
        ? { receipt_no: payment.receipt_no, amount_cents: payment.amount_cents, currency: payment.currency, paid_at: payment.verified_at, provider: payment.provider, provider_ref: payment.provider_ref }
        : null;
    res.json({ payment: { ...payment, receipt } });
  }),
);
