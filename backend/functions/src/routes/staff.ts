/** Staff ops, team, leaderboard (STF-050..060). */
import { Router } from 'express';
import { z } from 'zod';
import { getSupabase, unwrap } from '../lib/supabase.js';
import { isoDate, parseQuery, uuid } from '../lib/validate.js';
import { assertOutlet, requireProfile, requireStaff, requireSupervisor } from '../middleware/auth.js';
import { ApiError, asyncHandler } from '../middleware/errors.js';
import { leaderboard, periodStart } from '../services/gamification.js';
import { activeTaskCounts } from '../services/workflow.js';
import type { Task, WorkOrder } from '../types.js';

export const staffRouter = Router();
staffRouter.use('/staff', requireProfile, requireStaff);

function defaultOutlet(req: import('express').Request): string {
  const q = req.query.outlet_id;
  if (typeof q === 'string' && q) return uuid.parse(q);
  const first = req.auth!.outletIds[0];
  if (!first) throw ApiError.validation('outlet_id is required');
  return first;
}

staffRouter.get(
  '/staff/ops-summary',
  requireSupervisor,
  asyncHandler(async (req, res) => {
    const outletId = defaultOutlet(req);
    assertOutlet(req.auth!, outletId);
    const q = parseQuery(z.object({ date: isoDate.optional() }), req.query);
    const db = getSupabase();
    const day = q.date ?? new Date().toISOString().slice(0, 10);
    const dayStart = `${day}T00:00:00Z`;
    const dayEnd = `${day}T23:59:59.999Z`;
    const [wos, tasks, alerts] = await Promise.all([
      db.from('work_orders').select('*, vehicle:vehicles(registration_no), service:services(name), assignee:profiles!work_orders_assignee_id_fkey(full_name)').eq('outlet_id', outletId).or(`status.in.(queued,assigned,in_progress,blocked),and(status.in.(completed,verified),updated_at.gte.${dayStart},updated_at.lte.${dayEnd})`),
      db.from('tasks').select('assignee_id, status').eq('outlet_id', outletId).in('status', ['assigned', 'in_progress', 'blocked']),
      db.from('inventory_alerts').select('id, level, item:inventory_items(id, name, on_hand, reorder_threshold)').eq('outlet_id', outletId).neq('status', 'resolved'),
    ]);
    const orders = unwrap<Array<WorkOrder & Record<string, any>>>(wos, 'work orders');
    const counts = { in_progress: 0, queued: 0, blocked: 0, done: 0 };
    const now = Date.now();
    const needs: unknown[] = [];
    for (const w of orders) {
      if (w.status === 'in_progress') counts.in_progress++;
      else if (w.status === 'queued' || w.status === 'assigned') counts.queued++;
      else if (w.status === 'blocked') counts.blocked++;
      else counts.done++;
      const overdue = w.due_at && new Date(w.due_at).getTime() < now && !['completed', 'verified', 'cancelled'].includes(w.status);
      if (w.status === 'blocked' || overdue || (w.status === 'queued' && !w.assignee_id)) {
        needs.push({
          type: w.status === 'blocked' ? 'blocked' : overdue ? 'overdue' : 'unassigned',
          work_order_id: w.id,
          ref: w.ref,
          registration_no: w.vehicle?.registration_no ?? null,
          service: w.service?.name ?? null,
          assignee_name: w.assignee?.full_name ?? null,
          reason: w.blocked_reason,
          due_at: w.due_at,
          bay: w.bay,
        });
      }
    }
    for (const a of ((alerts.data ?? []) as Array<any>)) needs.push({ type: a.level === 'out' ? 'out_of_stock' : 'low_stock', item_id: a.item?.id, name: a.item?.name, on_hand: a.item?.on_hand, threshold: a.item?.reorder_threshold });

    const staff = unwrap<Array<{ profile_id: string; profiles: { id: string; full_name: string; role: string } | null }>>(
      await db.from('staff_outlets').select('profile_id, profiles!inner(id, full_name, role)').eq('outlet_id', outletId),
      'team',
    );
    const avail = await db.from('staff_availability').select('profile_id, status, capacity').in('profile_id', staff.map((s) => s.profile_id));
    const availMap = new Map(((avail.data ?? []) as Array<{ profile_id: string; status: string; capacity: number }>).map((a) => [a.profile_id, a]));
    const load = new Map<string, number>();
    for (const t of ((tasks.data ?? []) as Array<{ assignee_id: string | null }>)) if (t.assignee_id) load.set(t.assignee_id, (load.get(t.assignee_id) ?? 0) + 1);
    const team_load = staff
      .filter((s) => s.profiles && ['technician', 'supervisor'].includes(s.profiles.role))
      .map((s) => ({
        staff_id: s.profile_id,
        name: s.profiles!.full_name,
        role: s.profiles!.role,
        availability: availMap.get(s.profile_id)?.status ?? 'off',
        capacity: availMap.get(s.profile_id)?.capacity ?? 0,
        active_tasks: load.get(s.profile_id) ?? 0,
      }));
    res.json({ outlet_id: outletId, date: day, counts, needs_attention: needs, team_load });
  }),
);

staffRouter.get(
  '/staff/team',
  requireSupervisor,
  asyncHandler(async (req, res) => {
    const outletId = defaultOutlet(req);
    assertOutlet(req.auth!, outletId);
    const db = getSupabase();
    const staff = unwrap<Array<{ profile_id: string; is_primary: boolean; profiles: { id: string; full_name: string; role: string; avatar_url: string | null; is_active: boolean } | null }>>(
      await db.from('staff_outlets').select('profile_id, is_primary, profiles!inner(id, full_name, role, avatar_url, is_active)').eq('outlet_id', outletId),
      'team',
    );
    const ids = staff.map((s) => s.profile_id);
    const [skills, avail, counts] = await Promise.all([
      db.from('staff_skills').select('profile_id, skill').in('profile_id', ids),
      db.from('staff_availability').select('*').in('profile_id', ids),
      activeTaskCounts(ids),
    ]);
    const skillMap = new Map<string, string[]>();
    for (const s of ((skills.data ?? []) as Array<{ profile_id: string; skill: string }>)) skillMap.set(s.profile_id, [...(skillMap.get(s.profile_id) ?? []), s.skill]);
    const availMap = new Map(((avail.data ?? []) as Array<any>).map((a) => [a.profile_id, a]));
    res.json({
      data: staff
        .filter((s) => s.profiles?.is_active)
        .map((s) => ({
          id: s.profile_id,
          full_name: s.profiles!.full_name,
          role: s.profiles!.role,
          avatar_url: s.profiles!.avatar_url,
          is_primary: s.is_primary,
          skills: skillMap.get(s.profile_id) ?? [],
          availability: availMap.get(s.profile_id)?.status ?? 'off',
          capacity: availMap.get(s.profile_id)?.capacity ?? 0,
          active_task_count: counts.get(s.profile_id) ?? 0,
        })),
    });
  }),
);

staffRouter.get(
  '/staff/leaderboard',
  asyncHandler(async (req, res) => {
    const outletId = defaultOutlet(req);
    assertOutlet(req.auth!, outletId);
    const q = parseQuery(z.object({ period: z.enum(['week', 'month']).default('week') }), req.query);
    const db = getSupabase();
    const rows = await leaderboard(outletId, q.period);
    const me = rows.find((r) => r.staff_id === req.auth!.uid) ?? null;
    const [badges, mine] = await Promise.all([
      db.from('badges').select('*').order('code'),
      db.from('staff_badges').select('badge_id, awarded_at').eq('staff_id', req.auth!.uid),
    ]);
    const earned = new Map(((mine.data ?? []) as Array<{ badge_id: string; awarded_at: string }>).map((b) => [b.badge_id, b.awarded_at]));
    res.json({
      period: q.period,
      period_start: periodStart(q.period).toISOString(),
      rows,
      me,
      badges: ((badges.data ?? []) as Array<any>).map((b) => ({ badge: { id: b.id, code: b.code, name: b.name, description: b.description, icon: b.icon, colour: b.colour }, earned_at: earned.get(b.id) ?? null })),
    });
  }),
);

export type { Task };
