/** Staff — walk-in customers (STF-010/012, CUS-020..025 on behalf of a customer). */
import { Router } from 'express';
import { z } from 'zod';
import { clientOpId, parseBody, parseQuery, uuid } from '../lib/validate.js';
import { assertOutlet, requireProfile, requireStaff } from '../middleware/auth.js';
import { asyncHandler } from '../middleware/errors.js';
import { createWalkInCustomer, CUSTOMER_SEARCH_DEFAULT_LIMIT, CUSTOMER_SEARCH_MAX_LIMIT, getCustomerOrThrow, searchCustomers } from '../services/customers.js';
import { createVehicle } from '../services/vehicles.js';
import { vehicleSchema } from './vehicles.js';

export const walkInRouter = Router();
walkInRouter.use('/staff/customers', requireProfile, requireStaff);

const searchSchema = z.object({
  search: z.string().trim().min(2, 'search needs at least 2 characters').max(80),
  limit: z.coerce.number().int().min(1).max(CUSTOMER_SEARCH_MAX_LIMIT).default(CUSTOMER_SEARCH_DEFAULT_LIMIT),
});

walkInRouter.get(
  '/staff/customers',
  asyncHandler(async (req, res) => {
    const q = parseQuery(searchSchema, req.query);
    res.json({ data: await searchCustomers(req.ctx, q.search, q.limit) });
  }),
);

export const customerCreateSchema = z.object({
  full_name: z.string().trim().min(2).max(120),
  phone: z.string().trim().min(6).max(32),
  email: z.string().trim().email().max(254).nullable().optional(),
  marketing_opt_in: z.boolean().optional(),
  whatsapp_opt_in: z.boolean().optional(),
  outlet_id: uuid.optional(),
  client_op_id: clientOpId,
});

walkInRouter.post(
  '/staff/customers',
  asyncHandler(async (req, res) => {
    const body = parseBody(customerCreateSchema, req.body);
    if (body.outlet_id) assertOutlet(req.auth!, body.outlet_id);
    const customer = await createWalkInCustomer(req.ctx, {
      full_name: body.full_name,
      phone: body.phone,
      email: body.email ?? null,
      marketing_opt_in: body.marketing_opt_in,
      whatsapp_opt_in: body.whatsapp_opt_in,
      outlet_id: body.outlet_id ?? null,
    });
    res.status(201).json({ customer });
  }),
);

walkInRouter.post(
  '/staff/customers/:id/vehicles',
  asyncHandler(async (req, res) => {
    const id = z.string().min(1).max(128).parse(req.params.id);
    const body = parseBody(vehicleSchema, req.body);
    const customer = await getCustomerOrThrow(id);
    const { vehicle, duplicate } = await createVehicle(req.ctx, { ...body, customer_id: customer.id });
    res.status(duplicate ? 200 : 201).json({ vehicle, duplicate });
  }),
);
