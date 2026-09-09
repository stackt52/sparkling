/**
 * ARC-004 / STF-035 / DAT-005: offline queue replay.
 * Ops are applied in order; each is recorded in `sync_operations`. Duplicates
 * (same client_op_id) return `applied` with the previous result; state
 * conflicts return `conflict` with the server state; bad input → `rejected`.
 */
import { Router } from 'express';
import { z } from 'zod';
import { getSupabase, unwrap } from '../lib/supabase.js';
import { clientOpId, isoDateTime, parseBody, uuid } from '../lib/validate.js';
import { requireProfile } from '../middleware/auth.js';
import { ApiError, asyncHandler, toApiError } from '../middleware/errors.js';
import { createBooking } from '../services/bookings.js';
import { recordMovement } from '../services/inventory.js';
import { createQuotation } from '../services/quotations.js';
import { createVehicle } from '../services/vehicles.js';
import { recordStep, transitionTask } from '../services/workflow.js';
import type { RequestContext, SyncStatus } from '../types.js';
import { vehicleSchema } from './vehicles.js';

export const syncRouter = Router();
syncRouter.use('/sync', requireProfile);

export const SYNC_KINDS = ['task.transition', 'step.result', 'inventory.movement', 'booking.create', 'quotation.create', 'vehicle.create'] as const;
export type SyncKind = (typeof SYNC_KINDS)[number];

const opSchema = z.object({
  client_op_id: clientOpId,
  kind: z.enum(SYNC_KINDS),
  payload: z.record(z.unknown()),
  device_time: isoDateTime.optional(),
});

const batchSchema = z.object({ operations: z.array(opSchema).min(1).max(100) });

const payloadSchemas: Record<SyncKind, z.ZodTypeAny> = {
  'task.transition': z.object({
    task_id: uuid,
    to: z.enum(['in_progress', 'blocked', 'completed', 'verified', 'cancelled']),
    reason: z.string().max(500).nullable().optional(),
    override: z.object({ reason: z.string().min(3).max(500) }).nullable().optional(),
  }),
  'step.result': z.object({
    work_order_id: uuid,
    step_key: z.string().regex(/^[a-z0-9_]{1,64}$/),
    status: z.enum(['done', 'blocked', 'skipped']),
    value: z.unknown().optional(),
    attachment_id: uuid.nullable().optional(),
    note: z.string().max(500).nullable().optional(),
  }),
  'inventory.movement': z.object({
    item_id: uuid,
    delta: z.number().finite(),
    reason: z.enum(['usage', 'receive', 'adjust', 'reorder_request', 'count']),
    note: z.string().max(500).nullable().optional(),
    work_order_id: uuid.nullable().optional(),
  }),
  'booking.create': z.object({
    vehicle_id: uuid,
    outlet_id: uuid,
    service_id: uuid,
    slot_start: isoDateTime,
    notes: z.string().max(500).nullable().optional(),
  }),
  'quotation.create': z.object({
    vehicle_id: uuid,
    outlet_id: uuid,
    category: z.enum(['Dent', 'Scratch', 'Bumper', 'Panel', 'Paint', 'Glass', 'Other']),
    description: z.string().min(5).max(2000),
    attachment_ids: z.array(uuid).max(10).optional(),
  }),
  'vehicle.create': vehicleSchema.omit({ client_op_id: true }),
};

export interface SyncOpResult {
  client_op_id: string;
  status: SyncStatus;
  result: unknown;
}

export async function applyOperation(ctx: RequestContext, op: z.infer<typeof opSchema>): Promise<SyncOpResult> {
  const db = getSupabase();
  const prior = unwrap<{ status: SyncStatus; result: unknown } | null>(
    await db.from('sync_operations').select('status, result').eq('client_op_id', op.client_op_id).maybeSingle(),
    'sync op lookup',
  );
  if (prior && prior.status !== 'pending') return { client_op_id: op.client_op_id, status: prior.status, result: prior.result };

  let status: SyncStatus = 'applied';
  let result: unknown;
  try {
    const parsed = payloadSchemas[op.kind].safeParse(op.payload);
    if (!parsed.success) {
      throw ApiError.validation('Invalid payload', parsed.error.issues.map((i) => ({ path: i.path.join('.'), message: i.message })));
    }
    const p = parsed.data as any;
    switch (op.kind) {
      case 'task.transition': {
        const r = await transitionTask(ctx, p.task_id, { to: p.to, reason: p.reason, clientOpId: op.client_op_id, override: p.override });
        result = { task: r.task, work_order: r.work_order, duplicate: r.duplicate };
        break;
      }
      case 'step.result': {
        const r = await recordStep(ctx, p.work_order_id, p.step_key, { status: p.status, value: p.value, attachmentId: p.attachment_id, note: p.note, clientOpId: op.client_op_id });
        result = r;
        break;
      }
      case 'inventory.movement': {
        const r = await recordMovement(ctx, { itemId: p.item_id, delta: p.delta, reason: p.reason, note: p.note, workOrderId: p.work_order_id, clientOpId: op.client_op_id });
        result = { movement: r.movement, item: r.item, duplicate: r.duplicate };
        break;
      }
      case 'booking.create': {
        const r = await createBooking(ctx, { vehicleId: p.vehicle_id, outletId: p.outlet_id, serviceId: p.service_id, slotStart: p.slot_start, notes: p.notes, clientOpId: op.client_op_id });
        result = r;
        break;
      }
      case 'quotation.create': {
        const r = await createQuotation(ctx, { vehicleId: p.vehicle_id, outletId: p.outlet_id, category: p.category, description: p.description, attachmentIds: p.attachment_ids, clientOpId: op.client_op_id });
        result = r;
        break;
      }
      case 'vehicle.create': {
        const r = await createVehicle(ctx, { ...p, client_op_id: op.client_op_id });
        result = r;
        break;
      }
    }
  } catch (err) {
    const apiErr = toApiError(err);
    if (apiErr.status >= 500) {
      ctx.log.error({ err, kind: op.kind, client_op_id: op.client_op_id }, 'sync op failed');
    }
    status = apiErr.code === 'conflict' || apiErr.code === 'invalid_transition' ? 'conflict' : 'rejected';
    result = { error: { code: apiErr.code, message: apiErr.message, details: apiErr.details ?? [] }, server_state: await serverState(op) };
  }

  const row = {
    client_op_id: op.client_op_id,
    profile_id: ctx.auth.uid,
    kind: op.kind,
    payload: op.payload,
    status,
    result: result ?? null,
    device_time: op.device_time ?? null,
    applied_at: new Date().toISOString(),
  };
  const { error } = await db.from('sync_operations').upsert(row, { onConflict: 'client_op_id' });
  if (error) ctx.log.warn({ err: error }, 'sync op record failed');
  return { client_op_id: op.client_op_id, status, result };
}

/** Best-effort server state for conflict responses. */
async function serverState(op: z.infer<typeof opSchema>): Promise<unknown> {
  const db = getSupabase();
  try {
    const p = op.payload as Record<string, unknown>;
    if (op.kind === 'task.transition' && typeof p.task_id === 'string') {
      const t = await db.from('tasks').select('id, status, assignee_id, updated_at').eq('id', p.task_id).maybeSingle();
      return t.data ?? null;
    }
    if (op.kind === 'step.result' && typeof p.work_order_id === 'string') {
      const r = await db.from('checklist_step_results').select('*').eq('work_order_id', p.work_order_id).eq('step_key', String(p.step_key ?? '')).maybeSingle();
      const w = await db.from('work_orders').select('id, status').eq('id', p.work_order_id).maybeSingle();
      return { work_order: w.data ?? null, step: r.data ?? null };
    }
    if (op.kind === 'inventory.movement' && typeof p.item_id === 'string') {
      const i = await db.from('inventory_items').select('id, on_hand, reorder_threshold').eq('id', p.item_id).maybeSingle();
      return i.data ?? null;
    }
  } catch {
    /* ignore */
  }
  return null;
}

syncRouter.post(
  '/sync/batch',
  asyncHandler(async (req, res) => {
    const body = parseBody(batchSchema, req.body);
    const results: SyncOpResult[] = [];
    for (const op of body.operations) {
      results.push(await applyOperation(req.ctx, op));
    }
    res.json({ results, applied: results.filter((r) => r.status === 'applied').length, conflicts: results.filter((r) => r.status === 'conflict').length, rejected: results.filter((r) => r.status === 'rejected').length });
  }),
);
