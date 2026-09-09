/** Work orders & checklist steps (STF-030..035). */
import { Router } from 'express';
import { z } from 'zod';
import { getSupabase, unwrap } from '../lib/supabase.js';
import { clientOpId, parseBody, uuid } from '../lib/validate.js';
import { assertOwnerOrOutletStaff, requireProfile, requireStaff } from '../middleware/auth.js';
import { ApiError, asyncHandler } from '../middleware/errors.js';
import { buildTimeline, loadStepResults, loadTemplateForWorkOrder, progress, recordStep } from '../services/workflow.js';
import type { Task, WorkOrder } from '../types.js';

export const workOrdersRouter = Router();
workOrdersRouter.use('/work-orders', requireProfile);

workOrdersRouter.get(
  '/work-orders/:id',
  asyncHandler(async (req, res) => {
    const id = uuid.parse(req.params.id);
    const db = getSupabase();
    const wo = unwrap<(WorkOrder & Record<string, unknown>) | null>(
      await db
        .from('work_orders')
        .select('*, vehicle:vehicles(id, registration_no, make, model, colour), service:services(id, name, category, duration_minutes), outlet:outlets(id, name), customer:profiles!work_orders_customer_id_fkey(id, full_name, phone), assignee:profiles!work_orders_assignee_id_fkey(id, full_name), booking:bookings(id, ref, status, slot_start, slot_end, total_cents)')
        .eq('id', id)
        .maybeSingle(),
      'work order',
    );
    if (!wo) throw ApiError.notFound('Work order');
    assertOwnerOrOutletStaff(req.auth!, wo);
    const isCustomer = req.auth!.role === 'customer';
    const [template, results, task, events] = await Promise.all([
      loadTemplateForWorkOrder(wo),
      loadStepResults(id),
      db.from('tasks').select('*').eq('work_order_id', id).order('seq').limit(1).maybeSingle(),
      isCustomer ? Promise.resolve({ data: [] }) : db.from('task_events').select('*').eq('work_order_id', id).order('created_at', { ascending: false }).limit(100),
    ]);
    const steps = template?.steps ?? [];
    if (isCustomer) delete (wo as Record<string, unknown>).customer;
    res.json({
      work_order: { ...wo, ...progress(steps, results) },
      template: template ? { id: template.id, name: template.name, version: template.version, steps } : null,
      results,
      events: (events.data ?? []) as unknown[],
      task: (task.data as Task | null) ?? null,
      timeline: buildTimeline(wo, steps, results),
    });
  }),
);

const stepSchema = z.object({
  status: z.enum(['done', 'blocked', 'skipped']),
  value: z.unknown().optional(),
  attachment_id: uuid.nullable().optional(),
  note: z.string().trim().max(500).nullable().optional(),
  client_op_id: clientOpId.optional(),
});

workOrdersRouter.post(
  '/work-orders/:id/steps/:key',
  requireStaff,
  asyncHandler(async (req, res) => {
    const id = uuid.parse(req.params.id);
    const key = z.string().regex(/^[a-z0-9_]{1,64}$/).parse(req.params.key);
    const body = parseBody(stepSchema, req.body);
    const result = await recordStep(req.ctx, id, key, { status: body.status, value: body.value, attachmentId: body.attachment_id, note: body.note, clientOpId: body.client_op_id });
    res.json(result);
  }),
);
