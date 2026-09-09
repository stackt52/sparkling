/** Vehicles (CUS-010..016). */
import { Router } from 'express';
import { z } from 'zod';
import { DiscParseError, parseDisc } from '../lib/pdf417.js';
import { getSupabase, unwrap } from '../lib/supabase.js';
import { clientOpId, isoDate, parseBody, uuid } from '../lib/validate.js';
import { isStaff, requireProfile } from '../middleware/auth.js';
import { ApiError, asyncHandler } from '../middleware/errors.js';
import { audit } from '../services/audit.js';
import { createVehicle } from '../services/vehicles.js';
import type { Vehicle } from '../types.js';

export const vehiclesRouter = Router();
vehiclesRouter.use('/vehicles', requireProfile);

vehiclesRouter.get(
  '/vehicles',
  asyncHandler(async (req, res) => {
    const db = getSupabase();
    const auth = req.auth!;
    let q = db.from('vehicles').select('*').eq('is_active', true).order('created_at', { ascending: false });
    if (isStaff(auth.role)) {
      const customer = typeof req.query.customer_id === 'string' ? req.query.customer_id : undefined;
      const reg = typeof req.query.registration_no === 'string' ? req.query.registration_no : undefined;
      if (customer) q = q.eq('customer_id', customer);
      if (reg) q = q.ilike('registration_no', `%${reg.replace(/[%_]/g, '')}%`);
      if (!customer && !reg) q = q.limit(100);
    } else {
      q = q.eq('customer_id', auth.uid);
    }
    res.json({ data: unwrap<Vehicle[]>(await q, 'vehicles') });
  }),
);

export const vehicleSchema = z.object({
  registration_no: z.string().trim().min(2).max(16),
  vin: z.string().trim().length(17).nullable().optional(),
  make: z.string().trim().max(60).nullable().optional(),
  model: z.string().trim().max(60).nullable().optional(),
  colour: z.string().trim().max(40).nullable().optional(),
  year: z.number().int().min(1950).max(2100).nullable().optional(),
  licence_no: z.string().trim().max(32).nullable().optional(),
  disc_expiry: isoDate.nullable().optional(),
  engine_no: z.string().trim().max(32).nullable().optional(),
  source: z.enum(['manual', 'scan']).default('manual'),
  disc_hash: z.string().length(64).nullable().optional(),
  force: z.boolean().optional(),
  client_op_id: clientOpId.optional(),
});

vehiclesRouter.post(
  '/vehicles',
  asyncHandler(async (req, res) => {
    const body = parseBody(vehicleSchema, req.body);
    const { vehicle, duplicate } = await createVehicle(req.ctx, body);
    res.status(duplicate ? 200 : 201).json({ vehicle });
  }),
);

const patchSchema = vehicleSchema.omit({ force: true, client_op_id: true, source: true }).partial().strict();

vehiclesRouter.patch(
  '/vehicles/:id',
  asyncHandler(async (req, res) => {
    const id = uuid.parse(req.params.id);
    const patch = parseBody(patchSchema, req.body);
    const db = getSupabase();
    const existing = unwrap<Vehicle | null>(await db.from('vehicles').select('*').eq('id', id).maybeSingle(), 'vehicle');
    if (!existing || !existing.is_active) throw ApiError.notFound('Vehicle');
    if (existing.customer_id !== req.auth!.uid) throw ApiError.forbidden();
    const vehicle = unwrap<Vehicle>(await db.from('vehicles').update(patch).eq('id', id).select('*').single(), 'vehicle update');
    res.json({ vehicle });
  }),
);

vehiclesRouter.delete(
  '/vehicles/:id',
  asyncHandler(async (req, res) => {
    const id = uuid.parse(req.params.id);
    const db = getSupabase();
    const existing = unwrap<Vehicle | null>(await db.from('vehicles').select('*').eq('id', id).maybeSingle(), 'vehicle');
    if (!existing) throw ApiError.notFound('Vehicle');
    if (existing.customer_id !== req.auth!.uid) throw ApiError.forbidden();
    await db.from('vehicles').update({ is_active: false }).eq('id', id);
    await audit(req.ctx, { action: 'vehicle.delete', entity_type: 'vehicle', entity_id: id });
    res.status(204).end();
  }),
);

vehiclesRouter.post(
  '/vehicles/parse-disc',
  asyncHandler(async (req, res) => {
    const { raw } = parseBody(z.object({ raw: z.string().min(20).max(4096) }), req.body);
    try {
      const parsed = parseDisc(raw);
      res.json({ vehicle: { ...parsed, source: 'scan' } });
    } catch (err) {
      if (err instanceof DiscParseError) throw ApiError.validation(err.message);
      throw err;
    }
  }),
);
