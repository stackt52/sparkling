/**
 * STF-050..054: staff points from PUBLISHED gamification_rules, idempotent
 * ledger writes, leaderboard aggregation.
 */
import { DatabaseError, getSupabase, PG_UNIQUE_VIOLATION, unwrap } from '../lib/supabase.js';

export interface GamificationRules {
  task_completed?: number;
  checklist_compliant?: number;
  verified_first_time?: number;
  p1_on_time?: number;
  blocked_resolved?: number;
  streak_5_days?: number;
  [k: string]: number | undefined;
}

export async function getPublishedRules(): Promise<GamificationRules> {
  const db = getSupabase();
  const res = await db.from('gamification_rules').select('rules').eq('status', 'published').order('version', { ascending: false }).limit(1).maybeSingle();
  const row = unwrap<{ rules: GamificationRules } | null>(res, 'gamification rules');
  return row?.rules ?? {};
}

export async function awardStaffPoints(input: {
  staffId: string;
  outletId: string | null;
  eventType: string;
  points: number;
  idempotencyKey: string;
  sourceType?: string;
  sourceId?: string | null;
}): Promise<boolean> {
  if (!input.points) return false;
  const db = getSupabase();
  const { error } = await db.from('staff_points_ledger').insert({
    staff_id: input.staffId,
    outlet_id: input.outletId,
    delta: input.points,
    event_type: input.eventType,
    source_type: input.sourceType ?? 'task',
    source_id: input.sourceId ?? null,
    idempotency_key: input.idempotencyKey,
  });
  if (error && error.code !== PG_UNIQUE_VIOLATION) throw new DatabaseError(error, 'staff points');
  return !error;
}

/** Awards the verification bundle for a task (called on `verified`). */
export async function awardForVerifiedTask(input: {
  taskId: string;
  staffId: string | null;
  outletId: string;
  priority: number;
  onTime: boolean;
  checklistCompliant: boolean;
  firstTime: boolean;
}): Promise<Array<{ event_type: string; points: number }>> {
  if (!input.staffId) return [];
  const rules = await getPublishedRules();
  const awards: Array<{ event_type: string; points: number; key: string }> = [];
  const push = (event: string, key: string, cond = true) => {
    const pts = Number(rules[event] ?? 0);
    if (cond && pts > 0) awards.push({ event_type: event, points: pts, key });
  };
  push('task_completed', `task:${input.taskId}:completed`);
  push('checklist_compliant', `task:${input.taskId}:compliant`, input.checklistCompliant);
  push('verified_first_time', `task:${input.taskId}:first_time`, input.firstTime);
  push('p1_on_time', `task:${input.taskId}:p1_on_time`, input.priority === 1 && input.onTime);
  const out: Array<{ event_type: string; points: number }> = [];
  for (const a of awards) {
    const inserted = await awardStaffPoints({
      staffId: input.staffId,
      outletId: input.outletId,
      eventType: a.event_type,
      points: a.points,
      idempotencyKey: a.key,
      sourceType: 'task',
      sourceId: input.taskId,
    });
    if (inserted) out.push({ event_type: a.event_type, points: a.points });
  }
  return out;
}

export function periodStart(period: 'week' | 'month', now = new Date()): Date {
  const d = new Date(Date.UTC(now.getUTCFullYear(), now.getUTCMonth(), now.getUTCDate()));
  if (period === 'month') return new Date(Date.UTC(now.getUTCFullYear(), now.getUTCMonth(), 1));
  const dow = (d.getUTCDay() + 6) % 7; // Monday = 0
  d.setUTCDate(d.getUTCDate() - dow);
  return d;
}

export function previousPeriodStart(period: 'week' | 'month', start: Date): Date {
  const d = new Date(start);
  if (period === 'month') d.setUTCMonth(d.getUTCMonth() - 1);
  else d.setUTCDate(d.getUTCDate() - 7);
  return d;
}

export interface LeaderboardRow {
  staff_id: string;
  name: string;
  points: number;
  rank: number;
  delta: number;
}

export async function leaderboard(outletId: string, period: 'week' | 'month'): Promise<LeaderboardRow[]> {
  const db = getSupabase();
  const start = periodStart(period);
  const prevStart = previousPeriodStart(period, start);
  const rows = unwrap<Array<{ staff_id: string; delta: number; created_at: string }>>(
    await db.from('staff_points_ledger').select('staff_id, delta, created_at').eq('outlet_id', outletId).gte('created_at', prevStart.toISOString()),
    'staff points',
  );
  const cur = new Map<string, number>();
  const prev = new Map<string, number>();
  for (const r of rows) {
    const target = new Date(r.created_at) >= start ? cur : prev;
    target.set(r.staff_id, (target.get(r.staff_id) ?? 0) + Number(r.delta));
  }
  const staffIds = [...new Set([...cur.keys(), ...prev.keys()])];
  const outletStaff = unwrap<Array<{ profile_id: string }>>(await db.from('staff_outlets').select('profile_id').eq('outlet_id', outletId), 'staff');
  for (const s of outletStaff) if (!staffIds.includes(s.profile_id)) staffIds.push(s.profile_id);
  const profiles = staffIds.length
    ? unwrap<Array<{ id: string; full_name: string; role: string }>>(await db.from('profiles').select('id, full_name, role').in('id', staffIds), 'profiles')
    : [];
  const names = new Map(profiles.filter((p) => p.role !== 'customer').map((p) => [p.id, p.full_name]));
  const rank = (m: Map<string, number>) =>
    [...names.keys()].map((id) => ({ id, pts: m.get(id) ?? 0 })).sort((a, b) => b.pts - a.pts || a.id.localeCompare(b.id));
  const prevRanked = rank(prev);
  const prevRank = new Map(prevRanked.map((r, i) => [r.id, i + 1]));
  return rank(cur).map((r, i) => ({
    staff_id: r.id,
    name: names.get(r.id) ?? r.id,
    points: r.pts,
    rank: i + 1,
    delta: (prevRank.get(r.id) ?? i + 1) - (i + 1),
  }));
}
