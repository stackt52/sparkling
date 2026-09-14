/** Staff — membership at the counter (docs/MEMBERSHIPS.md "API (v1)" — staff; outlet-scoped like the walk-in routes). */
import { Router } from 'express';
import { z } from 'zod';
import { clientOpId, parseBody, uuid } from '../lib/validate.js';
import { assertOutlet, requireProfile, requireStaff } from '../middleware/auth.js';
import { asyncHandler } from '../middleware/errors.js';
import { getCustomerOrThrow } from '../services/customers.js';
import { enrolAtCounter, membershipSummary, recordInvoicePayment } from '../services/memberships.js';
import { selectionsSchema } from './memberships.js';

export const staffMembershipsRouter = Router();
staffMembershipsRouter.use('/staff/customers', requireProfile, requireStaff);
staffMembershipsRouter.use('/staff/memberships', requireProfile, requireStaff);

export const enrolSchema = z.object({
  plan_code: z.string().trim().min(2).max(40).toLowerCase(),
  selections: selectionsSchema.default({}),
  payment_method: z.enum(['cash', 'card_terminal', 'eft']),
  reference: z.string().trim().max(120).nullable().optional(),
  outlet_id: uuid.optional(),
  client_op_id: clientOpId,
});

staffMembershipsRouter.get(
  '/staff/customers/:id/membership',
  asyncHandler(async (req, res) => {
    const id = z.string().min(1).max(128).parse(req.params.id);
    const customer = await getCustomerOrThrow(id);
    res.json(await membershipSummary(customer.id));
  }),
);

staffMembershipsRouter.post(
  '/staff/customers/:id/membership',
  asyncHandler(async (req, res) => {
    const id = z.string().min(1).max(128).parse(req.params.id);
    const body = parseBody(enrolSchema, req.body);
    if (body.outlet_id) assertOutlet(req.auth!, body.outlet_id);
    const customer = await getCustomerOrThrow(id);
    const r = await enrolAtCounter(req.ctx, { customerId: customer.id, planCode: body.plan_code, selections: body.selections, paymentMethod: body.payment_method, clientOpId: body.client_op_id, reference: body.reference ?? null, outletId: body.outlet_id ?? null });
    res.status(r.duplicate ? 200 : 201).json({ membership: r.membership, invoice: r.invoice, payment: r.payment, duplicate: r.duplicate, summary: await membershipSummary(customer.id) });
  }),
);

export const recordPaymentSchema = z.object({
  method: z.enum(['cash', 'card_terminal', 'eft']),
  reference: z.string().trim().max(120).nullable().optional(),
  outlet_id: uuid.optional(),
  client_op_id: clientOpId,
});

staffMembershipsRouter.post(
  '/staff/memberships/:id/invoices/:invoiceId/record-payment',
  asyncHandler(async (req, res) => {
    const id = uuid.parse(req.params.id);
    const invoiceId = uuid.parse(req.params.invoiceId);
    const body = parseBody(recordPaymentSchema, req.body);
    if (body.outlet_id) assertOutlet(req.auth!, body.outlet_id);
    const r = await recordInvoicePayment(req.ctx, id, invoiceId, { method: body.method, clientOpId: body.client_op_id, reference: body.reference ?? null, outletId: body.outlet_id ?? null });
    res.status(r.duplicate ? 200 : 201).json(r);
  }),
);
