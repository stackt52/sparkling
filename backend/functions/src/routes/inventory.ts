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

/** Suggested "full" level for the stock bar: a few reorder packs above the threshold, never below what is on hand. */
export function stockCapacity(item: { on_hand: number; reorder_threshold: number; pack_size?: number | null }): number {
  const pack = Number(item.pack_size) || 0;
  const suggested = Math.max(item.reorder_threshold * 4, item.reorder_threshold + pack * 4, item.on_hand, 1);
  return Math.ceil(suggested);
}

/**
 * Items with their open alert, plus the admin decorations: `outlet_name`,
 * `capacity` (level-bar ceiling) and `blocking_work_orders` (blocked work
 * orders that logged usage of the item).
 */
export async function listInventory(outletIds: string[], alertsFirst = false) {
  if (outletIds.length === 0) return [];
  const db = getSupabase();
  const [items, alerts, outlets] = await Promise.all([
    db.from('inventory_items').select('*').in('outlet_id', outletIds).eq('is_active', true).order('name'),
    db.from('inventory_alerts').select('*').in('outlet_id', outletIds).neq('status', 'resolved'),
    db.from('outlets').select('id, name').in('id', outletIds),
  ]);
  const alertMap = new Map(((alerts.data ?? []) as Array<any>).map((a) => [a.item_id, a]));
  const outletName = new Map(unwrap<Array<{ id: string; name: string }>>(outlets, 'outlets').map((o) => [o.id, o.name]));
  const rows = unwrap<Array<Record<string, any>>>(items, 'inventory');
  const blocking = new Map<string, number>();
  const alerted = rows.filter((i) => alertMap.has(i.id)).map((i) => i.id);
  if (alerted.length) {
    const movements = unwrap<Array<{ item_id: string; work_order_id: string | null }>>(await db.from('inventory_movements').select('item_id, work_order_id').in('item_id', alerted).not('work_order_id', 'is', null), 'movements');
    const woIds = [...new Set(movements.map((m) => m.work_order_id).filter((x): x is string => Boolean(x)))];
    const blockedWos = woIds.length ? new Set(unwrap<Array<{ id: string }>>(await db.from('work_orders').select('id').in('id', woIds).eq('status', 'blocked'), 'work orders').map((w) => w.id)) : new Set<string>();
    const seen = new Set<string>();
    for (const m of movements) {
      if (!m.work_order_id || !blockedWos.has(m.work_order_id) || seen.has(`${m.item_id}:${m.work_order_id}`)) continue;
      seen.add(`${m.item_id}:${m.work_order_id}`);
      blocking.set(m.item_id, (blocking.get(m.item_id) ?? 0) + 1);
    }
  }
  const data: Array<Record<string, any>> = rows.map((i) => {
    const on_hand = Number(i.on_hand);
    const reorder_threshold = Number(i.reorder_threshold);
    return { ...i, on_hand, reorder_threshold, outlet_name: outletName.get(i.outlet_id) ?? '', capacity: stockCapacity({ on_hand, reorder_threshold, pack_size: i.pack_size }), alert: alertMap.get(i.id) ?? null, blocking_work_orders: blocking.get(i.id) ?? 0 };
  });
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
