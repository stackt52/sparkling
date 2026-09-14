/** Customer membership plans (docs/MEMBERSHIPS.md "API (v1)" — customer). */
import { Router } from 'express';
import { z } from 'zod';
import { clientOpId, parseBody, uuid } from '../lib/validate.js';
import { requireProfile, requireRole } from '../middleware/auth.js';
import { asyncHandler } from '../middleware/errors.js';
import { paymentLimiter } from '../middleware/rateLimit.js';
import { cancelMembership, changePlan, changeSelections, liveMembership, loadPlans, membershipSummary, payInvoice, subscribe } from '../services/memberships.js';
import { ApiError } from '../middleware/errors.js';

export const membershipsRouter = Router();
membershipsRouter.use('/memberships', requireProfile, requireRole('customer'));

export const selectionsSchema = z.record(z.string().trim().min(1).max(40));
const planCode = z.string().trim().min(2).max(40).toLowerCase();

membershipsRouter.get(
  '/memberships/plans',
  asyncHandler(async (req, res) => {
    const [plans, live] = await Promise.all([loadPlans(), liveMembership(req.auth!.uid)]);
    const current = live ? plans.find((p) => p.id === live.plan_id) : undefined;
    res.json({ data: plans, current_plan_code: current?.code ?? null, current_status: live?.status ?? null });
  }),
);

membershipsRouter.get(
  '/memberships/me',
  asyncHandler(async (req, res) => {
    res.json(await membershipSummary(req.auth!.uid));
  }),
);

const subscribeSchema = z.object({
  plan_code: planCode,
  selections: selectionsSchema.default({}),
  payment_method: z.enum(['card']).default('card'),
  client_op_id: clientOpId,
});

membershipsRouter.post(
  '/memberships',
  paymentLimiter,
  asyncHandler(async (req, res) => {
    const body = parseBody(subscribeSchema, req.body);
    const r = await subscribe(req.ctx, { customerId: req.auth!.uid, planCode: body.plan_code, selections: body.selections, clientOpId: body.client_op_id });
    res.status(r.duplicate ? 200 : 201).json({ membership: r.membership, invoice: r.invoice, payment: r.payment, duplicate: r.duplicate });
  }),
);

membershipsRouter.post(
  '/memberships/me/invoices/:id/pay',
  paymentLimiter,
  asyncHandler(async (req, res) => {
    const id = uuid.parse(req.params.id);
    const r = await payInvoice(req.ctx, id);
    res.status(r.duplicate ? 200 : 201).json({ invoice: r.invoice, payment: { ...r.payment, client_secret: r.client_secret }, duplicate: r.duplicate });
  }),
);

membershipsRouter.put(
  '/memberships/me/selections',
  asyncHandler(async (req, res) => {
    const body = parseBody(z.object({ selections: selectionsSchema }), req.body);
    res.json(await changeSelections(req.ctx, req.auth!.uid, body.selections));
  }),
);

membershipsRouter.post(
  '/memberships/me/change-plan',
  paymentLimiter,
  asyncHandler(async (req, res) => {
    const body = parseBody(z.object({ plan_code: planCode, selections: selectionsSchema.default({}) }), req.body);
    const r = await changePlan(req.ctx, req.auth!.uid, { planCode: body.plan_code, selections: body.selections });
    res.status(r.change === 'upgrade' ? 201 : 200).json(r);
  }),
);

membershipsRouter.post(
  '/memberships/me/cancel',
  asyncHandler(async (req, res) => {
    const body = parseBody(z.object({ at_period_end: z.boolean().default(true), reason: z.string().trim().max(500).nullable().optional() }), req.body);
    const live = await liveMembership(req.auth!.uid);
    if (!live) throw ApiError.notFound('Membership');
    const membership = await cancelMembership(req.ctx, live.id, { atPeriodEnd: body.at_period_end, reason: body.reason ?? null });
    res.json({ membership });
  }),
);
