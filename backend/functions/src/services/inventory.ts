/**
 * STF-040..044: inventory movements (append-only; trigger updates on_hand and
 * alerts). Technicians may only record usage (negative) or reorder requests
 * (delta 0 + note); managers/admin anything. Resulting on_hand < 0 → 409.
 */
import { DatabaseError, getSupabase, PG_CHECK_VIOLATION, PG_UNIQUE_VIOLATION, unwrap } from '../lib/supabase.js';
import { ApiError } from '../middleware/errors.js';
import { assertOutlet, isManager } from '../middleware/auth.js';
import type { InventoryItem, InventoryReason, RequestContext } from '../types.js';
import { audit } from './audit.js';
import { notify } from './notifications.js';

export interface MovementInput {
  itemId: string;
  delta: number;
  reason: InventoryReason;
  note?: string | null;
  workOrderId?: string | null;
  clientOpId?: string | null;
}

export interface MovementResult {
  movement: Record<string, unknown>;
  item: InventoryItem;
  duplicate: boolean;
}

export async function recordMovement(ctx: RequestContext, input: MovementInput): Promise<MovementResult> {
  const db = getSupabase();
  const item = unwrap<InventoryItem | null>(await db.from('inventory_items').select('*').eq('id', input.itemId).maybeSingle(), 'item');
  if (!item || !item.is_active) throw ApiError.notFound('Inventory item');
  assertOutlet(ctx.auth, item.outlet_id);

  const role = ctx.auth.role;
  if (!isManager(role)) {
    if (input.reason === 'usage') {
      if (!(input.delta < 0)) throw ApiError.validation('Usage must be a negative delta');
    } else if (input.reason === 'reorder_request') {
      if (input.delta !== 0) throw ApiError.validation('Reorder request must have delta 0');
      if (!input.note || !input.note.trim()) throw ApiError.validation('Reorder request requires a note');
    } else {
      throw ApiError.forbidden('Only managers may record this movement reason');
    }
  }
  if (input.reason === 'reorder_request' && input.delta !== 0) throw ApiError.validation('Reorder request must have delta 0');

  if (input.clientOpId) {
    const existing = await db.from('inventory_movements').select('*').eq('client_op_id', input.clientOpId).maybeSingle();
    if (existing.data) {
      const fresh = unwrap<InventoryItem>(await db.from('inventory_items').select('*').eq('id', item.id).single(), 'item');
      return { movement: existing.data as Record<string, unknown>, item: fresh, duplicate: true };
    }
  }

  const resulting = Number(item.on_hand) + input.delta;
  if (resulting < 0) {
    throw ApiError.conflict('Insufficient stock — resulting on_hand would be negative', { on_hand: Number(item.on_hand), delta: input.delta });
  }

  const res = await db
    .from('inventory_movements')
    .insert({
      item_id: item.id,
      delta: input.delta,
      reason: input.reason,
      actor_id: ctx.auth.uid,
      work_order_id: input.workOrderId ?? null,
      note: input.note ?? null,
      client_op_id: input.clientOpId ?? null,
    })
    .select('*')
    .single();
  if (res.error) {
    if (res.error.code === PG_CHECK_VIOLATION) throw ApiError.conflict('Insufficient stock — on_hand cannot go below zero');
    if (res.error.code === PG_UNIQUE_VIOLATION && input.clientOpId) {
      const existing = await db.from('inventory_movements').select('*').eq('client_op_id', input.clientOpId).single();
      const fresh = unwrap<InventoryItem>(await db.from('inventory_items').select('*').eq('id', item.id).single(), 'item');
      return { movement: existing.data as Record<string, unknown>, item: fresh, duplicate: true };
    }
    throw new DatabaseError(res.error, 'movement');
  }
  const fresh = unwrap<InventoryItem>(await db.from('inventory_items').select('*').eq('id', item.id).single(), 'item');

  if (input.reason === 'reorder_request' || Number(fresh.on_hand) <= Number(fresh.reorder_threshold)) {
    await notifyLowStock(fresh, input.reason === 'reorder_request' ? ctx.auth.uid : null);
  }
  return { movement: res.data as Record<string, unknown>, item: fresh, duplicate: false };
}

async function notifyLowStock(item: InventoryItem, requestedBy: string | null): Promise<void> {
  const db = getSupabase();
  const managers = unwrap<Array<{ profile_id: string; profiles: { role: string } | null }>>(
    await db.from('staff_outlets').select('profile_id, profiles!inner(role)').eq('outlet_id', item.outlet_id),
    'outlet managers',
  );
  const outlet = unwrap<{ name: string } | null>(await db.from('outlets').select('name').eq('id', item.outlet_id).maybeSingle(), 'outlet');
  const alert = await db.from('inventory_alerts').select('id, level').eq('item_id', item.id).neq('status', 'resolved').maybeSingle();
  const alertId = (alert.data as { id: string } | null)?.id ?? 'req';
  for (const m of managers) {
    if (!m.profiles || !['manager', 'supervisor'].includes(m.profiles.role)) continue;
    await notify({
      recipientId: m.profile_id,
      templateKey: 'low_stock',
      vars: { item: item.name, outlet: outlet?.name ?? '', on_hand: Number(item.on_hand), threshold: Number(item.reorder_threshold) },
      dedupeKey: requestedBy ? `low_stock:${item.id}:req:${requestedBy}:${Date.now()}` : `low_stock:${item.id}:${alertId}`,
      payload: { type: 'inventory', item_id: item.id, outlet_id: item.outlet_id },
    });
  }
  if (alert.data) await db.from('inventory_alerts').update({ notified_at: new Date().toISOString() }).eq('id', alertId);
}

export async function updateItem(
  ctx: RequestContext,
  itemId: string,
  patch: { reorder_threshold?: number; name?: string; unit?: string },
): Promise<InventoryItem> {
  const db = getSupabase();
  const before = unwrap<InventoryItem | null>(await db.from('inventory_items').select('*').eq('id', itemId).maybeSingle(), 'item');
  if (!before) throw ApiError.notFound('Inventory item');
  assertOutlet(ctx.auth, before.outlet_id);
  const after = unwrap<InventoryItem>(await db.from('inventory_items').update(patch).eq('id', itemId).select('*').single(), 'item update');
  await audit(ctx, {
    action: 'inventory.threshold',
    entity_type: 'inventory_item',
    entity_id: itemId,
    outlet_id: before.outlet_id,
    before: { reorder_threshold: before.reorder_threshold, name: before.name, unit: before.unit },
    after: patch,
  });
  return after;
}
