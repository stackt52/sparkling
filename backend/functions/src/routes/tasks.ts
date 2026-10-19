/** Staff tasks (STF-020..024). */
import { Router } from 'express';
import { z } from 'zod';
import { getSupabase, unwrap } from '../lib/supabase.js';
import { clientOpId, isoDateTime, parseBody, parseQuery, uuid } from '../lib/validate.js';
import { canSeeOutlet, isSupervisor, requireProfile, requireStaff, requireSupervisor, seesAllOutlets } from '../middleware/auth.js';
import { ApiError, asyncHandler } from '../middleware/errors.js';
import { assignTask, AWAITING_VERIFICATION_STATUSES, transitionTask } from '../services/workflow.js';
import type { Task, WorkOrder } from '../types.js';

export const tasksRouter = Router();
tasksRouter.use('/tasks', requireProfile, requireStaff);

export const TASK_EXPAND = '*, work_order:work_orders(id, ref, status, bay, priority, eta_at, due_at, blocked_reason, started_at, checked_in_at, checked_in_by, collected_at, checklist_template_id, vehicle:vehicles(id, registration_no, make, model, colour), service:services(id, name, category, duration_minutes), booking:bookings(id, ref, status, slot_start, slot_end, total_cents, payment_method, pay_at)), assignee:profiles!tasks_assignee_id_fkey(id, full_name)';

export async function expandTasks(rows: Array<Task & { work_order: (Partial<WorkOrder> & Record<string, unknown>) | null }>) {
  if (!rows.length) return rows;
  const db = getSupabase();
  const woIds = rows.map((r) => r.work_order_id);
  // Every booking: tell staff whether a successful payment is on file (cash on collection, or a card
  // booking that is still unpaid and can be settled at check-in / hand-over).
  const bookingIds = [...new Set(rows.map((r) => (r.work_order?.booking as { id?: string } | null | undefined)?.id).filter(Boolean))] as string[];
  const [results, templates, paidRows] = await Promise.all([
    db.from('checklist_step_results').select('work_order_id, status').in('work_order_id', woIds),
    db.from('checklist_templates').select('id, steps').in('id', [...new Set(rows.map((r) => r.work_order?.checklist_template_id).filter(Boolean))] as string[]),
    bookingIds.length ? db.from('payments').select('booking_id').in('booking_id', bookingIds).eq('status', 'successful') : Promise.resolve({ data: [] as Array<{ booking_id: string }> }),
  ]);
  const paidBookings = new Set(((paidRows.data ?? []) as Array<{ booking_id: string }>).map((p) => p.booking_id));
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
          booking: t.work_order.booking
            ? { ...(t.work_order.booking as Record<string, unknown>), paid: paidBookings.has((t.work_order.booking as { id: string }).id) }
            : null,
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
    const q = parseQuery(
      z.object({
        scope: z.enum(['mine', 'queue', 'done']).default('mine'),
        outlet_id: uuid.optional(),
        limit: z.coerce.number().int().min(1).max(200).default(100),
        /** Period filter (`queue`/`done` only): half-open `[from, to)` — `done` by `completed_at`, `queue` by `due_at` or `created_at`. */
        from: isoDateTime.optional(),
        to: isoDateTime.optional(),
      }),
      req.query,
    );
    if ((q.from && !q.to) || (!q.from && q.to)) throw ApiError.validation('from and to must be given together', [{ path: q.from ? 'to' : 'from', message: 'required' }]);
    if (q.from && q.to && new Date(q.from) >= new Date(q.to)) throw ApiError.validation('from must be before to', [{ path: 'to', message: 'must be after from' }]);
    const range = q.from && q.to ? { from: new Date(q.from).toISOString(), to: new Date(q.to).toISOString() } : null;
    const auth = req.auth!;
    const db = getSupabase();
    if (q.outlet_id && !canSeeOutlet(auth, q.outlet_id)) throw ApiError.forbidden('Outlet is outside your scope');
    if (!q.outlet_id && !seesAllOutlets(auth.role) && !auth.outletIds.length) return res.json({ data: [] });
    const scoped = () => {
      const base = db.from('tasks').select(TASK_EXPAND).limit(q.limit);
      if (q.outlet_id) return base.eq('outlet_id', q.outlet_id);
      if (!seesAllOutlets(auth.role)) return base.in('outlet_id', auth.outletIds);
      return base;
    };
    let query = scoped();
    if (q.scope === 'mine') query = query.eq('assignee_id', auth.uid).in('status', ['assigned', 'in_progress', 'blocked', 'completed']).order('priority').order('due_at', { ascending: true, nullsFirst: false });
    else if (q.scope === 'queue') {
      query = query.in('status', ['queued', 'assigned', 'in_progress', 'blocked']).order('priority').order('due_at', { ascending: true, nullsFirst: false });
      // Work scheduled in the period, or raised during it (walk-ins / quotation conversions without a slot).
      if (range) query = query.or(`and(due_at.gte.${range.from},due_at.lt.${range.to}),and(created_at.gte.${range.from},created_at.lt.${range.to})`);
    } else {
      query = query.in('status', ['completed', 'verified']).order('completed_at', { ascending: false });
      if (range) query = query.gte('completed_at', range.from).lt('completed_at', range.to);
    }
    type Row = Task & { work_order: Record<string, unknown> | null };
    const rows = unwrap<Row[]>(await query, 'tasks');
    if (q.scope === 'mine' && isSupervisor(auth.role)) {
      // Supervisors also own the sign-offs: tasks in their outlets whose checklist reached the
      // supervisor step (STF-033) join their list even though they are assigned to the technician.
      const awaiting = unwrap<Row[]>(
        await scoped().not('verification_requested_at', 'is', null).in('status', AWAITING_VERIFICATION_STATUSES).order('verification_requested_at', { ascending: true }),
        'tasks awaiting verification',
      );
      const seen = new Set(rows.map((r) => r.id));
      for (const t of awaiting) if (!seen.has(t.id)) rows.push(t);
      rows.sort((a, b) => a.priority - b.priority || (a.due_at ?? '\uffff').localeCompare(b.due_at ?? '\uffff'));
    }
    res.json({ data: await expandTasks(rows as any), scope: q.scope, ...(range ? { from: range.from, to: range.to } : {}) });
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
