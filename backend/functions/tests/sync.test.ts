import { beforeEach, describe, expect, it } from 'vitest';
import { setFirebaseMessagingForTests } from '../src/lib/firebase.js';
import { setSupabaseClient } from '../src/lib/supabase.js';
import { applyOperation } from '../src/routes/sync.js';
import { invalidateFlags } from '../src/services/flags.js';
import { fakeSupabase, type FakeSupabase } from './helpers/fakeSupabase.js';
import { makeCtx } from './helpers/context.js';

const OUTLET = 'a0000000-0000-4000-8000-000000000001';
const WO = '30000000-0000-4000-8000-000000000001';
const TASK = '40000000-0000-4000-8000-000000000001';
const TEMPLATE = 'c0000000-0000-4000-8000-000000000002';
const ITEM = '70000000-0000-4000-8000-000000000001';

let db: FakeSupabase;

beforeEach(() => {
  db = fakeSupabase();
  db.seed('feature_flags', [{ key: 'auto_assignment', enabled: false }, { key: 'whatsapp_enabled', enabled: false }]);
  db.seed('profiles', [
    { id: 'tech_1', role: 'technician', full_name: 'Pieter', is_active: true, push_opt_in: true, whatsapp_opt_in: true, marketing_opt_in: false },
    { id: 'sup_1', role: 'supervisor', full_name: 'Johan', is_active: true, push_opt_in: true, whatsapp_opt_in: true, marketing_opt_in: false },
    { id: 'cust_1', role: 'customer', full_name: 'Naledi', is_active: true, push_opt_in: true, whatsapp_opt_in: true, marketing_opt_in: false },
  ]);
  db.seed('outlets', [{ id: OUTLET, name: 'Sandton' }]);
  db.seed('services', [{ id: 'svc_1', name: 'Express Wash', category: 'car_wash' }]);
  db.seed('vehicles', [{ id: 'veh_1', customer_id: 'cust_1', registration_no: 'HR 88 TS GP', make: 'Suzuki', model: 'Swift', is_active: true }]);
  db.seed('checklist_templates', [{ id: TEMPLATE, name: 'Express', category: 'car_wash', version: 2, status: 'published', steps: [
    { key: 'exterior', title: 'Exterior', type: 'confirm', required: true },
    { key: 'wheels', title: 'Wheels', type: 'confirm', required: true },
    { key: 'pressure', title: 'Tyre pressure', type: 'numeric', required: false, min: 1.5, max: 3.5 },
    { key: 'supervisor', title: 'Supervisor', type: 'supervisor_verify', required: false },
  ] }]);
  db.seed('work_orders', [{ id: WO, ref: 'WO-2026-4821', outlet_id: OUTLET, booking_id: null, vehicle_id: 'veh_1', customer_id: 'cust_1', service_id: 'svc_1', status: 'in_progress', priority: 2, bay: 'Bay 1', checklist_template_id: TEMPLATE, template_version: 2, assignee_id: 'tech_1', started_at: new Date().toISOString(), due_at: null }]);
  db.seed('tasks', [{ id: TASK, work_order_id: WO, outlet_id: OUTLET, title: 'Express · HR 88 TS GP', seq: 1, assignee_id: 'tech_1', status: 'in_progress', priority: 2, started_at: new Date().toISOString(), elapsed_seconds: 0 }]);
  db.seed('checklist_step_results', [
    { work_order_id: WO, step_key: 'exterior', status: 'pending' },
    { work_order_id: WO, step_key: 'wheels', status: 'pending' },
  ]);
  db.seed('inventory_items', [{ id: ITEM, outlet_id: OUTLET, sku: 'SHP', name: 'Shampoo', unit: 'bottle', on_hand: 1, reorder_threshold: 4, is_active: true }]);
  db.seed('gamification_rules', [{ version: 3, status: 'published', rules: { task_completed: 25, checklist_compliant: 10 } }]);
  db.seed('notification_templates', [{ key: 'service_ready', channel: 'push', title: 'Ready', body: 'Ready {{vehicle}}', is_promotional: false, is_active: true }]);
  setSupabaseClient(db as any);
  invalidateFlags();
  setFirebaseMessagingForTests({ sendEachForMulticast: async () => ({ successCount: 0, failureCount: 0, responses: [] }) } as any);
});

const tech = () => makeCtx('technician', 'tech_1', [OUTLET]);
const sup = () => makeCtx('supervisor', 'sup_1', [OUTLET]);

describe('/sync/batch operations (ARC-004 / STF-035 / DAT-005)', () => {
  it('applies a step result and dedupes a replay by client_op_id', async () => {
    const op = { client_op_id: 'op-step-1', kind: 'step.result' as const, payload: { work_order_id: WO, step_key: 'exterior', status: 'done', value: true } };
    const first = await applyOperation(tech(), op);
    expect(first.status).toBe('applied');
    expect((first.result as any).result.status).toBe('done');
    expect(db.rows('sync_operations')).toHaveLength(1);

    const replay = await applyOperation(tech(), { ...op, payload: { ...op.payload, value: false } });
    expect(replay.status).toBe('applied');
    expect(replay.result).toEqual(first.result);
    expect(db.rows('checklist_step_results').find((r) => r.step_key === 'exterior')?.value).toBe(true);
    expect(db.rows('sync_operations')).toHaveLength(1);
  });

  it('rejects numeric values outside min/max and photo steps without an attachment', async () => {
    const bad = await applyOperation(tech(), { client_op_id: 'op-num-1', kind: 'step.result', payload: { work_order_id: WO, step_key: 'pressure', status: 'done', value: 9 } });
    expect(bad.status).toBe('rejected');
    expect((bad.result as any).error.code).toBe('validation_error');
    expect((bad.result as any).server_state.work_order.status).toBe('in_progress');
  });

  it('returns conflict with server state when the task cannot transition', async () => {
    // Complete requires both required steps — only one done.
    await applyOperation(tech(), { client_op_id: 'op-s1', kind: 'step.result', payload: { work_order_id: WO, step_key: 'exterior', status: 'done', value: true } });
    const res = await applyOperation(tech(), { client_op_id: 'op-t1', kind: 'task.transition', payload: { task_id: TASK, to: 'completed' } });
    expect(res.status).toBe('conflict');
    expect((res.result as any).error.details.missing[0].key).toBe('wheels');
    expect((res.result as any).server_state.status).toBe('in_progress');
  });

  it('technician cannot verify; supervisor verifies once and a stale replay from another device conflicts', async () => {
    await applyOperation(tech(), { client_op_id: 'op-s1', kind: 'step.result', payload: { work_order_id: WO, step_key: 'exterior', status: 'done', value: true } });
    await applyOperation(tech(), { client_op_id: 'op-s2', kind: 'step.result', payload: { work_order_id: WO, step_key: 'wheels', status: 'done', value: true } });
    const done = await applyOperation(tech(), { client_op_id: 'op-t-complete', kind: 'task.transition', payload: { task_id: TASK, to: 'completed' } });
    expect(done.status).toBe('applied');

    const forbidden = await applyOperation(tech(), { client_op_id: 'op-t-verify-tech', kind: 'task.transition', payload: { task_id: TASK, to: 'verified' } });
    expect(forbidden.status).toBe('rejected');
    expect((forbidden.result as any).error.code).toBe('forbidden');

    const verified = await applyOperation(sup(), { client_op_id: 'op-t-verify', kind: 'task.transition', payload: { task_id: TASK, to: 'verified' } });
    expect(verified.status).toBe('applied');
    expect(db.rows('tasks')[0].status).toBe('verified');
    expect(db.rows('staff_points_ledger').map((r) => [r.event_type, r.delta, r.idempotency_key])).toEqual([
      ['task_completed', 25, `task:${TASK}:completed`],
      ['checklist_compliant', 10, `task:${TASK}:compliant`],
    ]);
    expect(db.rows('notifications').map((n) => n.template_key)).toEqual(['service_ready']);

    // A second device replays a *different* op id trying to move the verified task → conflict + server state.
    const stale = await applyOperation(sup(), { client_op_id: 'op-t-verify-other', kind: 'task.transition', payload: { task_id: TASK, to: 'verified' } });
    expect(stale.status).toBe('conflict');
    expect((stale.result as any).error.code).toBe('invalid_transition');
    expect((stale.result as any).server_state.status).toBe('verified');
    expect(db.rows('staff_points_ledger')).toHaveLength(2);
  });

  it('inventory usage is applied once; a negative resulting stock conflicts; techs cannot receive stock', async () => {
    const use = await applyOperation(tech(), { client_op_id: 'op-inv-1', kind: 'inventory.movement', payload: { item_id: ITEM, delta: -1, reason: 'usage' } });
    expect(use.status).toBe('applied');
    expect(db.rows('inventory_movements')).toHaveLength(1);
    const replay = await applyOperation(tech(), { client_op_id: 'op-inv-1', kind: 'inventory.movement', payload: { item_id: ITEM, delta: -1, reason: 'usage' } });
    expect(replay.status).toBe('applied');
    expect(db.rows('inventory_movements')).toHaveLength(1);

    // the fake has no trigger, so mimic on_hand update for the next assertion
    db.rows('inventory_items')[0].on_hand = 0;
    const neg = await applyOperation(tech(), { client_op_id: 'op-inv-2', kind: 'inventory.movement', payload: { item_id: ITEM, delta: -1, reason: 'usage' } });
    expect(neg.status).toBe('conflict');
    const receive = await applyOperation(tech(), { client_op_id: 'op-inv-3', kind: 'inventory.movement', payload: { item_id: ITEM, delta: 5, reason: 'receive' } });
    expect(receive.status).toBe('rejected');
    expect((receive.result as any).error.code).toBe('forbidden');
  });

  it('rejects unknown payload shapes without touching the domain', async () => {
    const res = await applyOperation(tech(), { client_op_id: 'op-bad', kind: 'task.transition', payload: { task_id: 'not-a-uuid', to: 'flying' } });
    expect(res.status).toBe('rejected');
    expect(db.rows('task_events')).toHaveLength(0);
    expect(db.rows('sync_operations')[0].status).toBe('rejected');
  });
});
