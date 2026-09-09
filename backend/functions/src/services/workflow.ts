/**
 * Work orders, tasks and checklists (STF-020..035, CUS-034).
 * All transitions are validated by the state machine; side effects on
 * `verified` follow ARCHITECTURE.md.
 */
import { canTransitionBooking, canTransitionWork, ACTIVE_WORK_STATUSES } from '../domain/stateMachines.js';
import { DatabaseError, getSupabase, PG_UNIQUE_VIOLATION, unwrap } from '../lib/supabase.js';
import { assertOutlet, isSupervisor } from '../middleware/auth.js';
import { ApiError } from '../middleware/errors.js';
import type {
  Booking,
  ChecklistStep,
  ChecklistTemplate,
  Quotation,
  RequestContext,
  Service,
  StepResult,
  StepStatus,
  Task,
  Vehicle,
  WorkOrder,
  WorkStatus,
} from '../types.js';
import { audit } from './audit.js';
import { flagEnabled } from './flags.js';
import { awardForVerifiedTask } from './gamification.js';
import { earnForBooking } from './loyalty.js';
import { notify } from './notifications.js';

// ---------------------------------------------------------------------------
// Creation
// ---------------------------------------------------------------------------

export interface CreateWorkOrderInput {
  outletId: string;
  bookingId?: string | null;
  quotationId?: string | null;
  vehicleId: string;
  customerId: string;
  service: Service;
  bay?: string | null;
  priority?: number;
  etaAt?: string | null;
  dueAt?: string | null;
  title?: string;
  clientOpId?: string | null;
}

export async function findTemplate(service: Service, outletId: string): Promise<ChecklistTemplate | null> {
  const db = getSupabase();
  if (service.checklist_template_id) {
    const t = unwrap<ChecklistTemplate | null>(
      await db.from('checklist_templates').select('*').eq('id', service.checklist_template_id).maybeSingle(),
      'template',
    );
    if (t) return t;
  }
  // Fallback: latest published template for the category (outlet-specific first).
  const rows = unwrap<ChecklistTemplate[]>(
    await db.from('checklist_templates').select('*').eq('category', service.category).eq('status', 'published').order('version', { ascending: false }),
    'templates',
  );
  return rows.find((r) => r.outlet_id === outletId) ?? rows.find((r) => r.outlet_id === null) ?? null;
}

export async function createWorkOrderWithTask(ctx: RequestContext, input: CreateWorkOrderInput): Promise<{ work_order: WorkOrder; task: Task; created: boolean }> {
  const db = getSupabase();
  if (input.bookingId) {
    const existing = unwrap<WorkOrder | null>(await db.from('work_orders').select('*').eq('booking_id', input.bookingId).maybeSingle(), 'work order');
    if (existing) {
      const task = unwrap<Task | null>(await db.from('tasks').select('*').eq('work_order_id', existing.id).order('seq').limit(1).maybeSingle(), 'task');
      if (task) return { work_order: existing, task, created: false };
    }
  }
  if (input.quotationId) {
    const existing = unwrap<WorkOrder | null>(await db.from('work_orders').select('*').eq('quotation_id', input.quotationId).maybeSingle(), 'work order');
    if (existing) {
      const task = unwrap<Task | null>(await db.from('tasks').select('*').eq('work_order_id', existing.id).order('seq').limit(1).maybeSingle(), 'task');
      if (task) return { work_order: existing, task, created: false };
    }
  }
  const template = await findTemplate(input.service, input.outletId);
  const wo = unwrap<WorkOrder>(
    await db
      .from('work_orders')
      .insert({
        outlet_id: input.outletId,
        booking_id: input.bookingId ?? null,
        quotation_id: input.quotationId ?? null,
        vehicle_id: input.vehicleId,
        customer_id: input.customerId,
        service_id: input.service.id,
        status: 'queued',
        priority: input.priority ?? 2,
        bay: input.bay ?? null,
        checklist_template_id: template?.id ?? null,
        template_version: template?.version ?? null,
        eta_at: input.etaAt ?? null,
        due_at: input.dueAt ?? input.etaAt ?? null,
      })
      .select('*')
      .single(),
    'create work order',
  );
  const vehicle = unwrap<Vehicle | null>(await db.from('vehicles').select('registration_no').eq('id', input.vehicleId).maybeSingle(), 'vehicle');
  const taskRes = await db
    .from('tasks')
    .insert({
      work_order_id: wo.id,
      outlet_id: input.outletId,
      title: input.title ?? `${input.service.name} · ${vehicle?.registration_no ?? ''}`.trim(),
      seq: 1,
      status: 'queued',
      priority: input.priority ?? 2,
      due_at: wo.due_at,
      client_op_id: input.clientOpId ?? null,
    })
    .select('*')
    .single();
  if (taskRes.error) throw new DatabaseError(taskRes.error, 'create task');
  let task = taskRes.data as Task;

  // Seed pending step rows so progress/timeline queries are simple.
  if (template?.steps?.length) {
    await db.from('checklist_step_results').upsert(
      template.steps.map((s) => ({ work_order_id: wo.id, step_key: s.key, status: 'pending' })),
      { onConflict: 'work_order_id,step_key', ignoreDuplicates: true },
    );
  }

  if (await flagEnabled('auto_assignment')) {
    const assigned = await autoAssign(ctx, wo, task, input.service);
    if (assigned) task = assigned;
  }
  return { work_order: await reloadWorkOrder(wo.id), task, created: true };
}

async function reloadWorkOrder(id: string): Promise<WorkOrder> {
  return unwrap<WorkOrder>(await getSupabase().from('work_orders').select('*').eq('id', id).single(), 'work order');
}

// ---------------------------------------------------------------------------
// Assignment (STF-021/022)
// ---------------------------------------------------------------------------

export function skillsForCategory(category: Service['category']): string[] {
  return category === 'auto_body' ? ['paint', 'panel'] : ['wash'];
}

export async function activeTaskCounts(staffIds: string[]): Promise<Map<string, number>> {
  const db = getSupabase();
  const counts = new Map<string, number>();
  if (staffIds.length === 0) return counts;
  const rows = unwrap<Array<{ assignee_id: string }>>(
    await db.from('tasks').select('assignee_id').in('assignee_id', staffIds).in('status', [...ACTIVE_WORK_STATUSES]),
    'task counts',
  );
  for (const r of rows) counts.set(r.assignee_id, (counts.get(r.assignee_id) ?? 0) + 1);
  return counts;
}

export async function pickAssignee(outletId: string, category: Service['category']): Promise<string | null> {
  const db = getSupabase();
  const skills = skillsForCategory(category);
  const staff = unwrap<Array<{ profile_id: string }>>(await db.from('staff_outlets').select('profile_id').eq('outlet_id', outletId), 'outlet staff');
  const ids = staff.map((s) => s.profile_id);
  if (ids.length === 0) return null;
  const [skilled, avail, profiles] = await Promise.all([
    db.from('staff_skills').select('profile_id').in('profile_id', ids).in('skill', skills),
    db.from('staff_availability').select('profile_id, status, capacity').in('profile_id', ids).eq('status', 'available'),
    db.from('profiles').select('id, role, is_active').in('id', ids),
  ]);
  const skilledSet = new Set(((skilled.data ?? []) as Array<{ profile_id: string }>).map((r) => r.profile_id));
  const availMap = new Map(((avail.data ?? []) as Array<{ profile_id: string; capacity: number }>).map((r) => [r.profile_id, r.capacity]));
  const eligibleRoles = new Set(['technician', 'supervisor']);
  const candidates = ((profiles.data ?? []) as Array<{ id: string; role: string; is_active: boolean }>)
    .filter((p) => p.is_active && eligibleRoles.has(p.role) && skilledSet.has(p.id) && availMap.has(p.id))
    .map((p) => p.id);
  if (candidates.length === 0) return null;
  const counts = await activeTaskCounts(candidates);
  const ranked = candidates
    .map((id) => ({ id, load: counts.get(id) ?? 0, cap: availMap.get(id) ?? 1 }))
    .filter((c) => c.load < c.cap)
    .sort((a, b) => a.load - b.load || a.id.localeCompare(b.id));
  return ranked[0]?.id ?? null;
}

export async function autoAssign(ctx: RequestContext, wo: WorkOrder, task: Task, service: Service): Promise<Task | null> {
  const assignee = await pickAssignee(wo.outlet_id, service.category);
  if (!assignee) return null;
  return applyAssignment(ctx, wo, task, assignee, 'Auto-assign: skill match, lowest load', true);
}

export async function applyAssignment(ctx: RequestContext, wo: WorkOrder, task: Task, assigneeId: string, reason: string | null, auto: boolean): Promise<Task> {
  const db = getSupabase();
  const from = task.status;
  const to: WorkStatus = task.status === 'queued' ? 'assigned' : task.status;
  const updated = unwrap<Task>(
    await db.from('tasks').update({ assignee_id: assigneeId, status: to }).eq('id', task.id).select('*').single(),
    'assign task',
  );
  await db.from('work_orders').update({ assignee_id: assigneeId, status: wo.status === 'queued' ? 'assigned' : wo.status }).eq('id', wo.id);
  await db.from('task_events').insert({
    task_id: task.id,
    work_order_id: wo.id,
    actor_id: ctx.auth.uid,
    event: 'assigned',
    from_status: from,
    to_status: to,
    reason,
    metadata: { assignee_id: assigneeId, auto },
  });
  await audit(ctx, { action: auto ? 'task.auto_assign' : 'task.assign', entity_type: 'task', entity_id: task.id, outlet_id: wo.outlet_id, after: { assignee: assigneeId } });
  const service = unwrap<{ name: string } | null>(await db.from('services').select('name').eq('id', wo.service_id).maybeSingle(), 'service');
  await notify({
    recipientId: assigneeId,
    templateKey: 'task_assigned',
    vars: { ref: wo.ref, service: service?.name ?? '', bay: wo.bay ?? '—' },
    dedupeKey: `task_assigned:${task.id}:${assigneeId}`,
    payload: { type: 'task', task_id: task.id, work_order_id: wo.id },
  });
  return updated;
}

// ---------------------------------------------------------------------------
// Checklist helpers
// ---------------------------------------------------------------------------

export async function loadTemplateForWorkOrder(wo: WorkOrder): Promise<ChecklistTemplate | null> {
  if (!wo.checklist_template_id) return null;
  return unwrap<ChecklistTemplate | null>(
    await getSupabase().from('checklist_templates').select('*').eq('id', wo.checklist_template_id).maybeSingle(),
    'template',
  );
}

export async function loadStepResults(workOrderId: string): Promise<StepResult[]> {
  return unwrap<StepResult[]>(await getSupabase().from('checklist_step_results').select('*').eq('work_order_id', workOrderId), 'step results');
}

export function missingRequiredSteps(steps: ChecklistStep[], results: StepResult[], excludeKey?: string): ChecklistStep[] {
  const done = new Set(results.filter((r) => r.status === 'done').map((r) => r.step_key));
  return steps.filter((s) => s.required !== false && s.key !== excludeKey && s.type !== 'supervisor_verify' && !done.has(s.key));
}

export interface TimelineEntry {
  key: string;
  title: string;
  state: 'done' | 'current' | 'pending' | 'blocked' | 'skipped';
  at?: string | null;
}

export function buildTimeline(wo: WorkOrder, steps: ChecklistStep[], results: StepResult[], booking?: Booking | null): TimelineEntry[] {
  const byKey = new Map(results.map((r) => [r.step_key, r]));
  const timeline: TimelineEntry[] = [];
  const checkedIn = !!wo.started_at || ['in_progress', 'blocked', 'completed', 'verified'].includes(wo.status) || booking?.status === 'in_service';
  timeline.push({ key: 'checked_in', title: 'Checked in', state: checkedIn ? 'done' : wo.status === 'queued' || wo.status === 'assigned' ? 'current' : 'pending', at: wo.started_at ?? wo.created_at });
  let currentSet = !checkedIn;
  for (const s of steps) {
    const r = byKey.get(s.key);
    let state: TimelineEntry['state'] = 'pending';
    if (r?.status === 'done') state = 'done';
    else if (r?.status === 'blocked') state = 'blocked';
    else if (r?.status === 'skipped') state = 'skipped';
    else if (!currentSet && checkedIn) {
      state = 'current';
      currentSet = true;
    }
    timeline.push({ key: s.key, title: s.title, state, at: r?.completed_at ?? null });
  }
  timeline.push({ key: 'ready', title: 'Ready for collection', state: wo.status === 'verified' ? 'done' : 'pending', at: wo.verified_at });
  return timeline;
}

export function progress(steps: ChecklistStep[], results: StepResult[]) {
  const done = results.filter((r) => r.status === 'done' && steps.some((s) => s.key === r.step_key)).length;
  const count = steps.length;
  return { steps_done: done, step_count: count, progress_pct: count ? Math.round((done / count) * 100) : 0, stage: Math.min(count, done + 1) };
}

// ---------------------------------------------------------------------------
// Step results (STF-030..033)
// ---------------------------------------------------------------------------

export interface StepInput {
  status: StepStatus;
  value?: unknown;
  attachmentId?: string | null;
  note?: string | null;
  clientOpId?: string | null;
}

export function validateStepValue(step: ChecklistStep, input: StepInput): void {
  if (input.status !== 'done') return;
  switch (step.type) {
    case 'numeric': {
      const n = typeof input.value === 'number' ? input.value : Number(input.value);
      if (input.value === undefined || input.value === null || Number.isNaN(n)) throw ApiError.validation(`Step '${step.key}' requires a numeric value`);
      if (step.min !== undefined && n < step.min) throw ApiError.validation(`Value below minimum ${step.min}${step.unit ? ' ' + step.unit : ''}`, { min: step.min, value: n });
      if (step.max !== undefined && n > step.max) throw ApiError.validation(`Value above maximum ${step.max}${step.unit ? ' ' + step.unit : ''}`, { max: step.max, value: n });
      return;
    }
    case 'photo':
      if ((step.photo_required ?? true) && !input.attachmentId) throw ApiError.validation(`Step '${step.key}' requires a photo attachment`);
      return;
    case 'select':
      if (step.options?.length && (typeof input.value !== 'string' || !step.options.includes(input.value))) {
        throw ApiError.validation(`Value must be one of: ${step.options.join(', ')}`, { options: step.options });
      }
      return;
    case 'text':
      if (typeof input.value !== 'string' || !input.value.trim()) throw ApiError.validation(`Step '${step.key}' requires text`);
      return;
    default:
      return;
  }
}

export async function recordStep(ctx: RequestContext, workOrderId: string, stepKey: string, input: StepInput): Promise<{ result: StepResult; duplicate: boolean; progress: ReturnType<typeof progress> }> {
  const db = getSupabase();
  const wo = unwrap<WorkOrder | null>(await db.from('work_orders').select('*').eq('id', workOrderId).maybeSingle(), 'work order');
  if (!wo) throw ApiError.notFound('Work order');
  assertOutlet(ctx.auth, wo.outlet_id);
  const template = await loadTemplateForWorkOrder(wo);
  const steps = template?.steps ?? [];
  const step = steps.find((s) => s.key === stepKey);
  if (!step) throw ApiError.notFound(`Checklist step '${stepKey}'`);
  const results = await loadStepResults(wo.id);

  if (input.clientOpId) {
    const dup = results.find((r) => r.client_op_id === input.clientOpId);
    if (dup) return { result: dup, duplicate: true, progress: progress(steps, results) };
  }
  if (['verified', 'cancelled'].includes(wo.status)) {
    throw ApiError.conflict(`Work order is ${wo.status}; checklist is locked`, { status: wo.status });
  }
  if (step.type === 'supervisor_verify') {
    if (!isSupervisor(ctx.auth.role)) throw ApiError.forbidden('Supervisor verification requires supervisor or manager role');
    const missing = missingRequiredSteps(steps, results, step.key);
    if (input.status === 'done' && missing.length) {
      throw ApiError.conflict('All required steps must be done before supervisor verification', { missing: missing.map((m) => m.key) });
    }
  }
  validateStepValue(step, input);
  if (input.attachmentId) {
    const att = await db.from('attachments').select('id').eq('id', input.attachmentId).maybeSingle();
    if (!att.data) throw ApiError.validation('attachment_id does not exist');
  }
  const now = new Date().toISOString();
  const row = {
    work_order_id: wo.id,
    step_key: stepKey,
    status: input.status,
    value: input.value ?? null,
    attachment_id: input.attachmentId ?? null,
    actor_id: ctx.auth.uid,
    note: input.note ?? null,
    client_op_id: input.clientOpId ?? null,
    completed_at: input.status === 'done' ? now : null,
    updated_at: now,
  };
  const res = await db.from('checklist_step_results').upsert(row, { onConflict: 'work_order_id,step_key' }).select('*').single();
  if (res.error) {
    if (res.error.code === PG_UNIQUE_VIOLATION && input.clientOpId) {
      const dup = unwrap<StepResult>(await db.from('checklist_step_results').select('*').eq('client_op_id', input.clientOpId).single(), 'dup');
      return { result: dup, duplicate: true, progress: progress(steps, results) };
    }
    throw new DatabaseError(res.error, 'step result');
  }
  const result = res.data as StepResult;
  const task = unwrap<Task | null>(await db.from('tasks').select('*').eq('work_order_id', wo.id).order('seq').limit(1).maybeSingle(), 'task');
  const eventRes = await db.from('task_events').insert({
    task_id: task?.id ?? null,
    work_order_id: wo.id,
    actor_id: ctx.auth.uid,
    event: input.status === 'blocked' ? 'step_blocked' : input.status === 'done' ? 'step_done' : 'step_skipped',
    reason: input.note ?? null,
    metadata: { step_key: stepKey, value: input.value ?? null },
    client_op_id: input.clientOpId ? `step:${input.clientOpId}` : null,
  });
  if (eventRes.error && eventRes.error.code !== PG_UNIQUE_VIOLATION) ctx.log.warn({ err: eventRes.error }, 'task_event insert failed');

  if (input.status === 'blocked' && task && canTransitionWork(task.status, 'blocked')) {
    await db.from('tasks').update({ status: 'blocked', blocked_reason: input.note ?? `Blocked at ${step.title}` }).eq('id', task.id);
    await db.from('work_orders').update({ status: 'blocked', blocked_reason: input.note ?? `Blocked at ${step.title}` }).eq('id', wo.id);
  }
  const fresh = await loadStepResults(wo.id);
  const prog = progress(steps, fresh);
  if (input.status === 'done') {
    await notify({
      recipientId: wo.customer_id,
      templateKey: 'stage_changed',
      vars: { vehicle: await vehicleLabel(wo.vehicle_id), stage: step.title },
      dedupeKey: `stage_changed:${wo.id}:${stepKey}`,
      payload: { type: 'work_order', work_order_id: wo.id, booking_id: wo.booking_id },
    });
  }
  return { result, duplicate: false, progress: prog };
}

async function vehicleLabel(vehicleId: string): Promise<string> {
  const v = unwrap<Vehicle | null>(await getSupabase().from('vehicles').select('make, model, registration_no').eq('id', vehicleId).maybeSingle(), 'vehicle');
  if (!v) return 'vehicle';
  return [v.make, v.model].filter(Boolean).join(' ') || v.registration_no;
}

// ---------------------------------------------------------------------------
// Task transitions (STF-023 / STF-033)
// ---------------------------------------------------------------------------

export interface TransitionInput {
  to: WorkStatus;
  reason?: string | null;
  clientOpId?: string | null;
  override?: { reason: string } | null;
}

export interface TransitionResult {
  task: Task;
  work_order: WorkOrder;
  duplicate: boolean;
  side_effects?: Record<string, unknown>;
}

export async function transitionTask(ctx: RequestContext, taskId: string, input: TransitionInput): Promise<TransitionResult> {
  const db = getSupabase();
  const task = unwrap<Task | null>(await db.from('tasks').select('*').eq('id', taskId).maybeSingle(), 'task');
  if (!task) throw ApiError.notFound('Task');
  assertOutlet(ctx.auth, task.outlet_id);
  const wo = unwrap<WorkOrder>(await db.from('work_orders').select('*').eq('id', task.work_order_id).single(), 'work order');

  if (input.clientOpId) {
    const dup = await db.from('task_events').select('id').eq('client_op_id', input.clientOpId).maybeSingle();
    if (dup.data) return { task, work_order: wo, duplicate: true };
  }

  const from = task.status;
  const to = input.to;
  if (!canTransitionWork(from, to)) throw ApiError.invalidTransition(from, to, 'task');

  const role = ctx.auth.role;
  const isAssignee = task.assignee_id === ctx.auth.uid;
  if (to === 'verified' && !isSupervisor(role)) throw ApiError.forbidden('Only supervisors or managers may verify');
  if (to !== 'verified' && !isAssignee && !isSupervisor(role)) throw ApiError.forbidden('Only the assignee or a supervisor may transition this task');
  if (to === 'blocked' && !input.reason) throw ApiError.validation('A reason is required when blocking');

  const template = await loadTemplateForWorkOrder(wo);
  const steps = template?.steps ?? [];
  const results = await loadStepResults(wo.id);
  let overrideRecorded = false;
  if (to === 'completed' || to === 'verified') {
    const missing = missingRequiredSteps(steps, results);
    if (missing.length) {
      if (input.override?.reason && isSupervisor(role)) {
        await db.from('task_events').insert({
          task_id: task.id,
          work_order_id: wo.id,
          actor_id: ctx.auth.uid,
          event: 'override',
          from_status: from,
          to_status: to,
          reason: input.override.reason,
          metadata: { missing: missing.map((m) => m.key) },
        });
        overrideRecorded = true;
      } else {
        throw ApiError.conflict('Required checklist steps are not done', {
          missing: missing.map((m) => ({ key: m.key, title: m.title })),
          override_allowed: isSupervisor(role),
        });
      }
    }
  }

  const now = new Date().toISOString();
  const taskPatch: Partial<Task> = { status: to };
  const woPatch: Partial<WorkOrder> = { status: to };
  if (to === 'in_progress') {
    if (!task.started_at) taskPatch.started_at = now;
    if (!wo.started_at) woPatch.started_at = now;
    if (!task.assignee_id) taskPatch.assignee_id = ctx.auth.uid;
    if (!wo.assignee_id) woPatch.assignee_id = ctx.auth.uid;
    taskPatch.blocked_reason = null;
    woPatch.blocked_reason = null;
  }
  if (to === 'blocked') {
    taskPatch.blocked_reason = input.reason ?? null;
    woPatch.blocked_reason = input.reason ?? null;
  }
  if (to === 'completed') {
    taskPatch.completed_at = now;
    woPatch.completed_at = now;
    if (task.started_at) taskPatch.elapsed_seconds = Math.max(0, Math.round((Date.now() - new Date(task.started_at).getTime()) / 1000));
  }
  if (to === 'verified') {
    woPatch.verified_at = now;
    woPatch.verified_by = ctx.auth.uid;
    if (!task.completed_at) {
      taskPatch.completed_at = now;
      woPatch.completed_at = wo.completed_at ?? now;
    }
  }
  if (to === 'cancelled') taskPatch.blocked_reason = input.reason ?? task.blocked_reason;

  const updatedTask = unwrap<Task>(await db.from('tasks').update(taskPatch).eq('id', task.id).eq('status', from).select('*').maybeSingle(), 'task update');
  if (!updatedTask) {
    const current = unwrap<Task>(await db.from('tasks').select('*').eq('id', task.id).single(), 'task');
    throw ApiError.conflict('Task was modified concurrently', { status: current.status });
  }
  const updatedWo = unwrap<WorkOrder>(await db.from('work_orders').update(woPatch).eq('id', wo.id).select('*').single(), 'work order update');

  const ev = await db.from('task_events').insert({
    task_id: task.id,
    work_order_id: wo.id,
    actor_id: ctx.auth.uid,
    event: 'transition',
    from_status: from,
    to_status: to,
    reason: input.reason ?? null,
    metadata: { override: overrideRecorded },
    client_op_id: input.clientOpId ?? null,
  });
  if (ev.error && ev.error.code !== PG_UNIQUE_VIOLATION) ctx.log.warn({ err: ev.error }, 'task_event insert failed');

  const sideEffects: Record<string, unknown> = {};
  if (to === 'in_progress' && from !== 'blocked' && wo.booking_id) {
    await notify({
      recipientId: wo.customer_id,
      templateKey: 'service_started',
      vars: { vehicle: await vehicleLabel(wo.vehicle_id), bay: wo.bay ?? '—' },
      dedupeKey: `service_started:${wo.id}`,
      payload: { type: 'work_order', work_order_id: wo.id, booking_id: wo.booking_id },
    });
  }
  if (to === 'in_progress' && from === 'blocked' && task.assignee_id) {
    const { awardStaffPoints, getPublishedRules } = await import('./gamification.js');
    const rules = await getPublishedRules();
    if (rules.blocked_resolved) {
      await awardStaffPoints({
        staffId: task.assignee_id,
        outletId: task.outlet_id,
        eventType: 'blocked_resolved',
        points: Number(rules.blocked_resolved),
        idempotencyKey: `task:${task.id}:unblocked:${now}`,
        sourceId: task.id,
      });
    }
  }
  if (to === 'verified') {
    Object.assign(sideEffects, await onVerified(ctx, updatedWo, updatedTask, steps, results, overrideRecorded));
  }
  await audit(ctx, { action: `task.${to}`, entity_type: 'task', entity_id: task.id, outlet_id: task.outlet_id, before: { status: from }, after: { status: to, reason: input.reason ?? null } });
  return { task: updatedTask, work_order: updatedWo, duplicate: false, side_effects: sideEffects };
}

async function onVerified(ctx: RequestContext, wo: WorkOrder, task: Task, steps: ChecklistStep[], results: StepResult[], overridden: boolean): Promise<Record<string, unknown>> {
  const db = getSupabase();
  const out: Record<string, unknown> = {};
  const service = unwrap<Service | null>(await db.from('services').select('*').eq('id', wo.service_id).maybeSingle(), 'service');

  // Booking → completed + loyalty earn.
  if (wo.booking_id) {
    const booking = unwrap<Booking | null>(await db.from('bookings').select('*').eq('id', wo.booking_id).maybeSingle(), 'booking');
    if (booking) {
      if (canTransitionBooking(booking.status, 'completed')) {
        await db.from('bookings').update({ status: 'completed' }).eq('id', booking.id);
        out.booking_status = 'completed';
      }
      const earn = await earnForBooking(ctx, booking, service?.name ?? 'Service');
      out.loyalty = earn;
    }
  }
  // Quotation-based work: mark quotation converted is done at convert time; nothing here.

  // Staff points from published rules.
  const compliant = !overridden && !results.some((r) => r.status === 'blocked' || r.status === 'skipped');
  const priorVerifyAttempts = unwrap<Array<{ id: string }>>(
    await db.from('task_events').select('id').eq('task_id', task.id).eq('event', 'transition').eq('to_status', 'in_progress').eq('from_status', 'completed'),
    'events',
  );
  const onTime = !wo.due_at || new Date(wo.verified_at ?? Date.now()) <= new Date(wo.due_at);
  out.staff_points = await awardForVerifiedTask({
    taskId: task.id,
    staffId: task.assignee_id,
    outletId: task.outlet_id,
    priority: task.priority,
    onTime,
    checklistCompliant: compliant && steps.length > 0,
    firstTime: priorVerifyAttempts.length === 0,
  });

  // Customer notification.
  const outlet = unwrap<{ name: string } | null>(await db.from('outlets').select('name').eq('id', wo.outlet_id).maybeSingle(), 'outlet');
  out.notification = await notify({
    recipientId: wo.customer_id,
    templateKey: 'service_ready',
    vars: { vehicle: await vehicleLabel(wo.vehicle_id), outlet: outlet?.name ?? '', ref: wo.ref },
    dedupeKey: `service_ready:${wo.id}`,
    payload: { type: 'work_order', work_order_id: wo.id, booking_id: wo.booking_id },
  });
  await audit(ctx, { action: 'work_order.verified', entity_type: 'work_order', entity_id: wo.id, outlet_id: wo.outlet_id, after: { verified_by: ctx.auth.uid, overridden } });
  return out;
}

// ---------------------------------------------------------------------------
// Manual assignment (STF-021)
// ---------------------------------------------------------------------------

export async function assignTask(ctx: RequestContext, taskId: string, assigneeId: string, reason?: string | null): Promise<Task> {
  const db = getSupabase();
  const task = unwrap<Task | null>(await db.from('tasks').select('*').eq('id', taskId).maybeSingle(), 'task');
  if (!task) throw ApiError.notFound('Task');
  assertOutlet(ctx.auth, task.outlet_id);
  if (['verified', 'cancelled'].includes(task.status)) throw ApiError.invalidTransition(task.status, 'assigned', 'task');
  const wo = unwrap<WorkOrder>(await db.from('work_orders').select('*').eq('id', task.work_order_id).single(), 'work order');
  const assignee = unwrap<{ id: string; role: string; is_active: boolean } | null>(await db.from('profiles').select('id, role, is_active').eq('id', assigneeId).maybeSingle(), 'assignee');
  if (!assignee || !assignee.is_active || assignee.role === 'customer') throw ApiError.validation('Assignee must be an active staff member');
  const member = await db.from('staff_outlets').select('profile_id').eq('profile_id', assigneeId).eq('outlet_id', task.outlet_id).maybeSingle();
  if (!member.data) throw ApiError.validation('Assignee is not a member of this outlet');
  return applyAssignment(ctx, wo, task, assigneeId, reason ?? null, false);
}

// ---------------------------------------------------------------------------
// Quotation → work order (CUS-034)
// ---------------------------------------------------------------------------

export async function convertQuotation(ctx: RequestContext, quotation: Quotation): Promise<{ quotation: Quotation; work_order: WorkOrder; task: Task }> {
  const db = getSupabase();
  const services = unwrap<Service[]>(await db.from('services').select('*').eq('category', 'auto_body').eq('is_active', true).order('sort_order'), 'services');
  const byCategory = services.find((s) => s.code.toLowerCase() === quotation.category.toLowerCase() || s.name.toLowerCase().startsWith(quotation.category.toLowerCase()));
  const service = byCategory ?? services[0];
  if (!service) throw ApiError.conflict('No auto-body service configured to convert this quotation');
  const created = await createWorkOrderWithTask(ctx, {
    outletId: quotation.outlet_id,
    quotationId: quotation.id,
    vehicleId: quotation.vehicle_id,
    customerId: quotation.customer_id,
    service,
    priority: 2,
    title: `${quotation.category} repair · ${quotation.ref}`,
    etaAt: new Date(Date.now() + service.duration_minutes * 60_000).toISOString(),
  });
  const updated = unwrap<Quotation>(await db.from('quotations').update({ status: 'converted' }).eq('id', quotation.id).select('*').single(), 'quotation');
  await audit(ctx, { action: 'quotation.convert', entity_type: 'quotation', entity_id: quotation.id, outlet_id: quotation.outlet_id, after: { work_order_id: created.work_order.id } });
  return { quotation: updated, work_order: created.work_order, task: created.task };
}
