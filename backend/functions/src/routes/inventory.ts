/** Inventory (STF-040..044). */
import { Router } from 'express';
import { z } from 'zod';
import { getSupabase, unwrap } from '../lib/supabase.js';
import { clientOpId, parseBody, uuid } from '../lib/validate.js';
import { ApiError } from '../middleware/errors.js';
import { assertOutlet, requireManager, requireProfile, requireStaff } from '../middleware/auth.js';
import { asyncHandler } from '../middleware/errors.js';
import { recordMovement, updateItem } from '../services/inventory.js';

export const inventoryRouter = Router();
inventoryRouter.use('/inventory', requireProfile, requireStaff);

export async function listInventory(outletIds: string[], alertsFirst = false) {
  const db = getSupabase();
  const [items, alerts] = await Promise.all([
    db.from('inventory_items').select('*').in('outlet_id', outletIds).eq('is_active', true).order('name'),
    db.from('inventory_alerts').select('*').in('outlet_id', outletIds).neq('status', 'resolved'),
  ]);
  const alertMap = new Map(((alerts.data ?? []) as Array<any>).map((a) => [a.item_id, a]));
  const data: Array<Record<string, any>> = unwrap<Array<Record<string, any>>>(items, 'inventory').map((i) => ({ ...i, on_hand: Number(i.on_hand), reorder_threshold: Number(i.reorder_threshold), alert: alertMap.get(i.id) ?? null }));
  if (alertsFirst) data.sort((a, b) => (b.alert ? (b.alert.level === 'out' ? 2 : 1) : 0) - (a.alert ? (a.alert.level === 'out' ? 2 : 1) : 0) || a.name.localeCompare(b.name));
  return data;
}

inventoryRouter.get(
  '/inventory',
  asyncHandler(async (req, res) => {
    const outletId = typeof req.query.outlet_id === 'string' ? uuid.parse(req.query.outlet_id) : req.auth!.outletIds[0];
    if (!outletId) throw ApiError.validation('outlet_id is required');
    assertOutlet(req.auth!, outletId);
    res.json({ data: await listInventory([outletId]), outlet_id: outletId });
  }),
);

const movementSchema = z.object({
  delta: z.number().finite(),
  reason: z.enum(['usage', 'receive', 'adjust', 'reorder_request', 'count']),
  note: z.string().trim().max(500).nullable().optional(),
  work_order_id: uuid.nullable().optional(),
  client_op_id: clientOpId.optional(),
});

inventoryRouter.post(
  '/inventory/:id/movements',
  asyncHandler(async (req, res) => {
    const id = uuid.parse(req.params.id);
    const body = parseBody(movementSchema, req.body);
    const result = await recordMovement(req.ctx, { itemId: id, delta: body.delta, reason: body.reason, note: body.note, workOrderId: body.work_order_id, clientOpId: body.client_op_id });
    res.status(result.duplicate ? 200 : 201).json(result);
  }),
);

inventoryRouter.patch(
  '/inventory/:id',
  requireManager,
  asyncHandler(async (req, res) => {
    const id = uuid.parse(req.params.id);
    const body = parseBody(z.object({ reorder_threshold: z.number().min(0).optional(), name: z.string().trim().min(1).max(120).optional(), unit: z.string().trim().min(1).max(24).optional() }).strict(), req.body);
    if (!Object.keys(body).length) throw ApiError.validation('Nothing to update');
    res.json({ item: await updateItem(req.ctx, id, body) });
  }),
);
