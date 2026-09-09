/** Staff tasks (STF-020..024). */
import { Router } from 'express';
import { z } from 'zod';
import { getSupabase, unwrap } from '../lib/supabase.js';
import { clientOpId, parseBody, parseQuery, uuid } from '../lib/validate.js';
import { canSeeOutlet, requireProfile, requireStaff, requireSupervisor } from '../middleware/auth.js';
import { ApiError, asyncHandler } from '../middleware/errors.js';
import { assignTask, transitionTask } from '../services/workflow.js';
import type { Task, WorkOrder } from '../types.js';

export const tasksRouter = Router();
tasksRouter.use('/tasks', requireProfile, requireStaff);

const TASK_EXPAND = '*, work_order:work_orders(id, ref, status, bay, priority, eta_at, due_at, blocked_reason, started_at, checklist_template_id, vehicle:vehicles(id, registration_no, make, model, colour), service:services(id, name, category, duration_minutes)), assignee:profiles!tasks_assignee_id_fkey(id, full_name)';

export async function expandTasks(rows: Array<Task & { work_order: (Partial<WorkOrder> & Record<string, unknown>) | null }>) {
  if (!rows.length) return rows;
  const db = getSupabase();
  const woIds = rows.map((r) => r.work_order_id);
  const [results, templates] = await Promise.all([
    db.from('checklist_step_results').select('work_order_id, status').in('work_order_id', woIds),
    db.from('checklist_templates').select('id, steps').in('id', [...new Set(rows.map((r) => r.work_order?.checklist_template_id).filter(Boolean))] as string[]),
  ]);
  const doneCount = new Map<string, number>();
  for (const r of (results.data ?? []) as Array<{ work_order_id: string; status: string }>) {
    if (r.status === 'done') doneCount.set(r.work_order_id, (doneCount.get(r.work_order_id) ?? 0) + 1);
  }
  const stepCount = new Map(((templates.data ?? []) as Array<{ id: string; steps: unknown[] }>).map((t) => [t.id, t.steps.length]));
  return rows.map((t) => ({
    ...t,
    work_order: t.work_order
      ? {
          ...t.work_order,
          progress: {
            steps_done: doneCount.get(t.work_order_id) ?? 0,
            step_count: t.work_order.checklist_template_id ? (stepCount.get(t.work_order.checklist_template_id as string) ?? 0) : 0,
          },
        }
      : null,
  }));
}

tasksRouter.get(
  '/tasks',
  asyncHandler(async (req, res) => {
    const q = parseQuery(z.object({ scope: z.enum(['mine', 'queue', 'done']).default('mine'), outlet_id: uuid.optional(), limit: z.coerce.number().int().min(1).max(200).default(100) }), req.query);
    const auth = req.auth!;
    const db = getSupabase();
    let query = db.from('tasks').select(TASK_EXPAND).limit(q.limit);
    if (q.outlet_id) {
      if (!canSeeOutlet(auth, q.outlet_id)) throw ApiError.forbidden('Outlet is outside your scope');
      query = query.eq('outlet_id', q.outlet_id);
    } else if (auth.role !== 'admin' && auth.role !== 'finance') {
      if (!auth.outletIds.length) return res.json({ data: [] });
      query = query.in('outlet_id', auth.outletIds);
    }
    if (q.scope === 'mine') query = query.eq('assignee_id', auth.uid).in('status', ['assigned', 'in_progress', 'blocked', 'completed']).order('priority').order('due_at', { ascending: true, nullsFirst: false });
    else if (q.scope === 'queue') query = query.in('status', ['queued', 'assigned', 'in_progress', 'blocked']).order('priority').order('due_at', { ascending: true, nullsFirst: false });
    else query = query.in('status', ['completed', 'verified']).order('completed_at', { ascending: false });
    const rows = unwrap<Array<Task & { work_order: Record<string, unknown> | null }>>(await query, 'tasks');
    res.json({ data: await expandTasks(rows as any), scope: q.scope });
  }),
);

const transitionSchema = z.object({
  to: z.enum(['in_progress', 'blocked', 'completed', 'verified', 'cancelled']),
  reason: z.string().trim().max(500).nullable().optional(),
  client_op_id: clientOpId.optional(),
  override: z.object({ reason: z.string().trim().min(3).max(500) }).nullable().optional(),
});

tasksRouter.post(
  '/tasks/:id/transition',
  asyncHandler(async (req, res) => {
    const id = uuid.parse(req.params.id);
    const body = parseBody(transitionSchema, req.body);
    const result = await transitionTask(req.ctx, id, { to: body.to, reason: body.reason, clientOpId: body.client_op_id, override: body.override });
    res.json(result);
  }),
);

tasksRouter.post(
  '/tasks/:id/assign',
  requireSupervisor,
  asyncHandler(async (req, res) => {
    const id = uuid.parse(req.params.id);
    const body = parseBody(z.object({ assignee_id: z.string().min(1), reason: z.string().trim().max(500).nullable().optional() }), req.body);
    const task = await assignTask(req.ctx, id, body.assignee_id, body.reason);
    res.json({ task });
  }),
);
