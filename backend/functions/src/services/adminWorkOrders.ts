/**
 * Admin work-order board (`GET /admin/work-orders[/:id]`): the flat card shape
 * the dashboard renders — customer / vehicle / service / outlet names, booking
 * or quotation ref, assignee, checklist progress, the task id the actions act
 * on and the task_events audit trail. Expansion is done with plain `in()`
 * lookups so it behaves the same on PostgREST and the test fake.
 */
import { getSupabase, unwrap } from '../lib/supabase.js';
import type { ChecklistStep, Task, WorkOrder, WorkStatus } from '../types.js';

export const ACTIVE_WORK_STATUSES: WorkStatus[] = ['queued', 'assigned', 'in_progress', 'blocked'];
export const DONE_WORK_STATUSES: WorkStatus[] = ['completed', 'verified'];

export interface AdminTaskEvent {
  id: string;
  task_id: string | null;
  actor_id: string | null;
  actor_name: string | null;
  event: string;
  from_status: string | null;
  to_status: string | null;
  reason: string | null;
  metadata: Record<string, unknown> | null;
  created_at: string;
}

export interface AdminWorkOrder {
  id: string;
  ref: string;
  outlet: { id: string; name: string };
  booking_id: string | null;
  booking_ref: string | null;
  quotation_id: string | null;
  quotation_ref: string | null;
  customer_id: string;
  customer_name: string;
  vehicle: { id: string; registration_no: string; make: string | null; model: string | null };
  service: { id: string; name: string; category: string };
  status: WorkStatus;
  priority: 1 | 2 | 3;
  bay: string | null;
  assignee_id: string | null;
  assignee_name: string | null;
  eta_at: string | null;
  due_at: string | null;
  started_at: string | null;
  completed_at: string | null;
  verified_at: string | null;
  blocked_reason: string | null;
  steps_done: number;
  step_count: number;
  progress_pct: number;
  /** First (seq 1) task of the work order — the id `/tasks/:id/assign|transition` act on. */
  task_id: string | null;
  task_status: WorkStatus | null;
  events: AdminTaskEvent[];
  created_at: string;
  updated_at: string;
}

type Row = Record<string, any>;
const uniq = (xs: Array<string | null | undefined>): string[] => [...new Set(xs.filter((x): x is string => typeof x === 'string' && x.length > 0))];

async function lookup<T extends Row>(table: string, columns: string, column: string, ids: string[]): Promise<T[]> {
  if (ids.length === 0) return [];
  return unwrap<T[]>(await getSupabase().from(table).select(columns).in(column, ids), table);
}

/** Expands raw `work_orders` rows into the admin card shape (order preserved). */
export async function expandAdminWorkOrders(rows: WorkOrder[]): Promise<AdminWorkOrder[]> {
  if (rows.length === 0) return [];
  const ids = rows.map((r) => r.id);
  const [outlets, bookings, quotations, vehicles, services, tasks, events, results, templates] = await Promise.all([
    lookup<Row>('outlets', 'id, name', 'id', uniq(rows.map((r) => r.outlet_id))),
    lookup<Row>('bookings', 'id, ref', 'id', uniq(rows.map((r) => r.booking_id))),
    lookup<Row>('quotations', 'id, ref', 'id', uniq(rows.map((r) => r.quotation_id))),
    lookup<Row>('vehicles', 'id, registration_no, make, model', 'id', uniq(rows.map((r) => r.vehicle_id))),
    lookup<Row>('services', 'id, name, category', 'id', uniq(rows.map((r) => r.service_id))),
    lookup<Task>('tasks', '*', 'work_order_id', ids),
    lookup<Row>('task_events', '*', 'work_order_id', ids),
    lookup<Row>('checklist_step_results', 'work_order_id, step_key, status', 'work_order_id', ids),
    lookup<Row>('checklist_templates', 'id, steps', 'id', uniq(rows.map((r) => r.checklist_template_id))),
  ]);
  const profiles = await lookup<Row>('profiles', 'id, full_name', 'id', uniq([...rows.map((r) => r.customer_id), ...rows.map((r) => r.assignee_id), ...events.map((e) => e.actor_id as string | null)]));
  const byId = <T extends Row>(xs: T[]) => new Map(xs.map((x) => [x.id as string, x]));
  const outletById = byId(outlets);
  const bookingById = byId(bookings);
  const quotationById = byId(quotations);
  const vehicleById = byId(vehicles);
  const serviceById = byId(services);
  const templateById = byId(templates);
  const nameOf = new Map(profiles.map((p) => [p.id as string, p.full_name as string]));
  const firstTask = new Map<string, Task>();
  for (const t of [...tasks].sort((a, b) => a.seq - b.seq)) if (!firstTask.has(t.work_order_id)) firstTask.set(t.work_order_id, t);
  const doneKeys = new Map<string, Set<string>>();
  for (const r of results) {
    if (r.status !== 'done') continue;
    doneKeys.set(r.work_order_id, (doneKeys.get(r.work_order_id) ?? new Set()).add(r.step_key));
  }
  const eventsByWo = new Map<string, AdminTaskEvent[]>();
  for (const e of [...events].sort((a, b) => String(a.created_at).localeCompare(String(b.created_at)))) {
    const list = eventsByWo.get(e.work_order_id) ?? [];
    list.push({
      id: e.id,
      task_id: e.task_id ?? null,
      actor_id: e.actor_id ?? null,
      actor_name: e.actor_id ? (nameOf.get(e.actor_id) ?? null) : null,
      event: e.event,
      from_status: e.from_status ?? null,
      to_status: e.to_status ?? null,
      reason: e.reason ?? null,
      metadata: (e.metadata as Record<string, unknown> | null) ?? null,
      created_at: e.created_at,
    });
    eventsByWo.set(e.work_order_id, list);
  }

  return rows.map((w) => {
    const steps = ((templateById.get(w.checklist_template_id ?? '')?.steps ?? []) as ChecklistStep[]).map((s) => s.key);
    const done = doneKeys.get(w.id) ?? new Set<string>();
    const steps_done = steps.length ? steps.filter((k) => done.has(k)).length : done.size;
    const step_count = steps.length;
    const task = firstTask.get(w.id) ?? null;
    const vehicle = vehicleById.get(w.vehicle_id);
    const service = serviceById.get(w.service_id);
    const priority = Math.min(3, Math.max(1, Number(w.priority) || 2)) as 1 | 2 | 3;
    return {
      id: w.id,
      ref: w.ref,
      outlet: { id: w.outlet_id, name: outletById.get(w.outlet_id)?.name ?? '' },
      booking_id: w.booking_id ?? null,
      booking_ref: w.booking_id ? (bookingById.get(w.booking_id)?.ref ?? null) : null,
      quotation_id: w.quotation_id ?? null,
      quotation_ref: w.quotation_id ? (quotationById.get(w.quotation_id)?.ref ?? null) : null,
      customer_id: w.customer_id,
      customer_name: nameOf.get(w.customer_id) ?? '',
      vehicle: { id: w.vehicle_id, registration_no: vehicle?.registration_no ?? '', make: vehicle?.make ?? null, model: vehicle?.model ?? null },
      service: { id: w.service_id, name: service?.name ?? '', category: service?.category ?? 'car_wash' },
      status: w.status,
      priority,
      bay: w.bay ?? null,
      assignee_id: w.assignee_id ?? null,
      assignee_name: w.assignee_id ? (nameOf.get(w.assignee_id) ?? null) : null,
      eta_at: w.eta_at ?? null,
      due_at: w.due_at ?? null,
      started_at: w.started_at ?? null,
      completed_at: w.completed_at ?? null,
      verified_at: w.verified_at ?? null,
      blocked_reason: w.blocked_reason ?? null,
      steps_done,
      step_count,
      progress_pct: step_count ? Math.round((steps_done / step_count) * 100) : 0,
      task_id: task?.id ?? null,
      task_status: task?.status ?? null,
      events: eventsByWo.get(w.id) ?? [],
      created_at: w.created_at,
      updated_at: w.updated_at,
    };
  });
}

/** Board order: priority, then due time (unknown last), then creation. */
export function sortForBoard(rows: AdminWorkOrder[]): AdminWorkOrder[] {
  return [...rows].sort((a, b) => a.priority - b.priority || (a.due_at ?? '9').localeCompare(b.due_at ?? '9') || a.created_at.localeCompare(b.created_at));
}

export interface AdminWorkOrderFilter {
  outletIds: string[] | null;
  statuses: WorkStatus[] | null;
  /** Completed / verified work orders touched at or after this instant are included when no explicit status filter is given. */
  doneSince: string;
  limit: number;
}

/** Active work orders plus the recently finished ones (or exactly the requested statuses). */
export async function listAdminWorkOrders(f: AdminWorkOrderFilter): Promise<AdminWorkOrder[]> {
  const db = getSupabase();
  const base = () => {
    let q = db.from('work_orders').select('*');
    if (f.outletIds) q = q.in('outlet_id', f.outletIds);
    return q;
  };
  let rows: WorkOrder[];
  if (f.statuses) {
    rows = unwrap<WorkOrder[]>(await base().in('status', f.statuses).order('created_at', { ascending: false }).limit(f.limit), 'work orders');
  } else {
    const [active, done] = await Promise.all([
      base().in('status', ACTIVE_WORK_STATUSES).order('created_at', { ascending: false }).limit(f.limit),
      base().in('status', DONE_WORK_STATUSES).gte('updated_at', f.doneSince).order('updated_at', { ascending: false }).limit(f.limit),
    ]);
    rows = [...unwrap<WorkOrder[]>(active, 'work orders'), ...unwrap<WorkOrder[]>(done, 'work orders')].slice(0, f.limit);
  }
  return sortForBoard(await expandAdminWorkOrders(rows));
}

export async function getAdminWorkOrder(id: string): Promise<AdminWorkOrder | null> {
  const row = unwrap<WorkOrder | null>(await getSupabase().from('work_orders').select('*').eq('id', id).maybeSingle(), 'work order');
  if (!row) return null;
  const [expanded] = await expandAdminWorkOrders([row]);
  return expanded ?? null;
}
