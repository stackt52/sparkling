/**
 * Membership plans (docs/MEMBERSHIPS.md; migration 0010).
 *
 * A plan (Gold / Platinum / Black) is a monthly subscription that grants
 * entitlement groups (choose_one / all) of quantity × period service
 * allowances plus a discount rule. The customer's loyalty tier IS the plan
 * (`memberships_sync_tier` trigger; mirrored here by `syncTier` so the fake
 * database used in tests behaves the same).
 *
 * Periods:   monthly = [current_period_start, +1 calendar month) (Postgres
 *            interval semantics: 31 Jan + 1 month = 28/29 Feb). Annual
 *            entitlements use the membership year [anniversary, +1 year) where
 *            anniversary = started_at advanced by whole years to cover "now".
 * Allowance: remaining = quantity − Σ membership_usage.quantity for rows whose
 *            period_start equals the current period start of that entitlement.
 * Usage:     append-only, +1 on booking create (key booking:<id>:membership),
 *            −1 release on cancel (key booking:<id>:membership_release).
 * Benefits:  only while status = 'active'; past_due keeps the tier label but
 *            pauses benefits (pricing sees no plan).
 */
import { nextReceiptNo } from '../lib/refs.js';
import { DatabaseError, getSupabase, PG_UNIQUE_VIOLATION, unwrap } from '../lib/supabase.js';
import { logger } from '../middleware/correlation.js';
import { ApiError } from '../middleware/errors.js';
import type {
  Allowance,
  LoyaltyTier,
  Membership,
  MembershipBenefitKind,
  MembershipBrief,
  MembershipEntitlement,
  MembershipGroup,
  MembershipInvoice,
  MembershipPlan,
  MembershipStatus,
  MembershipSummary,
  MembershipUsage,
  Payment,
  PosPaymentMethod,
  RequestContext,
} from '../types.js';
import { MEMBERSHIP_LIVE_STATUSES } from '../types.js';
import { audit } from './audit.js';
import { formatRand, notify } from './notifications.js';
import { getPaymentProvider, POS_EVENT_TYPE, POS_PROVIDER, posIdempotencyKey, sandboxConfirm } from './payments.js';

export const RENEWAL_LEAD_DAYS = 3;
/** A past_due membership whose period ended this long ago without payment expires. */
export const PAST_DUE_EXPIRY_DAYS = 30;
export const SA_TIMEZONE = 'Africa/Johannesburg';

// ---------------------------------------------------------------------------
// Period maths (pure)
// ---------------------------------------------------------------------------

/** Adds calendar months, clamping the day to the target month's length (31 Jan + 1 → 28 Feb). */
export function addMonths(date: Date, months: number): Date {
  const day = date.getUTCDate();
  const target = new Date(Date.UTC(date.getUTCFullYear(), date.getUTCMonth() + months, 1, date.getUTCHours(), date.getUTCMinutes(), date.getUTCSeconds(), date.getUTCMilliseconds()));
  const lastDay = new Date(Date.UTC(target.getUTCFullYear(), target.getUTCMonth() + 1, 0)).getUTCDate();
  target.setUTCDate(Math.min(day, lastDay));
  return target;
}

export function addYears(date: Date, years: number): Date {
  return addMonths(date, years * 12);
}

export interface Period {
  period_start: string;
  period_end: string;
}

/** Monthly period starting at `start`. */
export function monthlyPeriod(start: Date): Period {
  return { period_start: start.toISOString(), period_end: addMonths(start, 1).toISOString() };
}

/** Membership year covering `now`: [anniversary, anniversary + 1 year). */
export function annualPeriod(startedAt: Date, now: Date): Period {
  let k = now.getUTCFullYear() - startedAt.getUTCFullYear();
  let anniversary = addYears(startedAt, k);
  if (anniversary.getTime() > now.getTime()) {
    k -= 1;
    anniversary = addYears(startedAt, k);
  }
  return { period_start: anniversary.toISOString(), period_end: addYears(startedAt, k + 1).toISOString() };
}

export function sameInstant(a: string | null | undefined, b: string | null | undefined): boolean {
  if (!a || !b) return false;
  return new Date(a).getTime() === new Date(b).getTime();
}

const MONTHS = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];

/** "5 Oct 2026" in South African time (for notifications; fixed month names so ICU locale data cannot change the copy). */
export function formatDateSA(iso: string | null | undefined): string {
  if (!iso) return '';
  const parts = new Intl.DateTimeFormat('en-US', { day: 'numeric', month: 'numeric', year: 'numeric', timeZone: SA_TIMEZONE }).formatToParts(new Date(iso));
  const get = (type: string) => parts.find((p) => p.type === type)?.value ?? '';
  return `${Number(get('day'))} ${MONTHS[Number(get('month')) - 1] ?? ''} ${get('year')}`;
}

export function formatFee(cents: number): string {
  return `R ${formatRand(cents)}`;
}

// ---------------------------------------------------------------------------
// Plans
// ---------------------------------------------------------------------------

interface PlanRow {
  id: string;
  code: string;
  tier: LoyaltyTier;
  name: string;
  tagline: string | null;
  monthly_fee_cents: number;
  discount_pct: number | string;
  discount_scope: MembershipPlan['discount_scope'];
  discount_note: string | null;
  color: string | null;
  sort_order: number;
  is_active: boolean;
}
interface GroupRow { id: string; plan_id: string; code: string; name: string; selection: MembershipGroup['selection']; sort_order: number }
interface EntitlementRow { id: string; group_id: string; code: string; label: string; quantity: number; period: MembershipEntitlement['period']; sort_order: number }
interface MapRow { entitlement_id: string; service_id: string; is_primary: boolean }
interface ServiceRow { id: string; code: string; name: string }

const bySort = <T extends { sort_order: number }>(a: T, b: T) => Number(a.sort_order) - Number(b.sort_order);

/** Loads every plan with its groups → entitlements → services (flat queries, assembled here). */
export async function loadPlans(opts: { includeInactive?: boolean } = {}): Promise<MembershipPlan[]> {
  const db = getSupabase();
  const [plansRes, groupsRes, entsRes, mapRes, servicesRes] = await Promise.all([
    db.from('membership_plans').select('*').order('sort_order'),
    db.from('membership_plan_groups').select('*').order('sort_order'),
    db.from('membership_plan_entitlements').select('*').order('sort_order'),
    db.from('membership_entitlement_services').select('*'),
    db.from('services').select('id, code, name'),
  ]);
  const plans = unwrap<PlanRow[]>(plansRes, 'membership plans');
  const groups = unwrap<GroupRow[]>(groupsRes, 'plan groups');
  const ents = unwrap<EntitlementRow[]>(entsRes, 'plan entitlements');
  const map = unwrap<MapRow[]>(mapRes, 'entitlement services');
  const services = new Map(unwrap<ServiceRow[]>(servicesRes, 'services').map((s) => [s.id, s]));

  const servicesByEnt = new Map<string, MembershipEntitlement['services']>();
  for (const m of map) {
    const s = services.get(m.service_id);
    if (!s) continue;
    const list = servicesByEnt.get(m.entitlement_id) ?? [];
    list.push({ id: s.id, code: s.code, name: s.name, is_primary: !!m.is_primary });
    servicesByEnt.set(m.entitlement_id, list);
  }
  const entsByGroup = new Map<string, MembershipEntitlement[]>();
  for (const e of [...ents].sort(bySort)) {
    const list = entsByGroup.get(e.group_id) ?? [];
    list.push({ id: e.id, group_id: e.group_id, code: e.code, label: e.label, quantity: Number(e.quantity), period: e.period, sort_order: Number(e.sort_order), services: (servicesByEnt.get(e.id) ?? []).sort((a, b) => Number(b.is_primary) - Number(a.is_primary) || a.code.localeCompare(b.code)) });
    entsByGroup.set(e.group_id, list);
  }
  const groupsByPlan = new Map<string, MembershipGroup[]>();
  for (const g of [...groups].sort(bySort)) {
    const list = groupsByPlan.get(g.plan_id) ?? [];
    list.push({ id: g.id, plan_id: g.plan_id, code: g.code, name: g.name, selection: g.selection, sort_order: Number(g.sort_order), entitlements: entsByGroup.get(g.id) ?? [] });
    groupsByPlan.set(g.plan_id, list);
  }
  return [...plans]
    .filter((p) => opts.includeInactive || p.is_active !== false)
    .sort(bySort)
    .map((p) => ({
      id: p.id,
      code: p.code,
      tier: p.tier,
      name: p.name,
      tagline: p.tagline ?? null,
      monthly_fee_cents: Number(p.monthly_fee_cents),
      discount_pct: Number(p.discount_pct ?? 0),
      discount_scope: p.discount_scope ?? 'none',
      discount_note: p.discount_note ?? null,
      color: p.color ?? null,
      sort_order: Number(p.sort_order ?? 100),
      is_active: p.is_active !== false,
      groups: groupsByPlan.get(p.id) ?? [],
    }));
}

export async function getPlanByCode(code: string, opts: { includeInactive?: boolean } = {}): Promise<MembershipPlan> {
  const plan = (await loadPlans(opts)).find((p) => p.code === code);
  if (!plan) throw ApiError.notFound('Membership plan');
  return plan;
}

/** Every service id any entitlement of the plan can redeem (selected or not). */
export function planServiceIds(plan: MembershipPlan): Set<string> {
  const out = new Set<string>();
  for (const g of plan.groups) for (const e of g.entitlements) for (const s of e.services) out.add(s.id);
  return out;
}

/**
 * Validates `{ [group_code]: entitlement_code }` against the plan: every
 * choose_one group needs exactly one of its own options; `all` groups need
 * nothing (extra keys are refused).
 */
export function resolveSelections(plan: MembershipPlan, selections: Record<string, string> | null | undefined): Array<{ group: MembershipGroup; entitlement: MembershipEntitlement }> {
  const given = selections ?? {};
  const out: Array<{ group: MembershipGroup; entitlement: MembershipEntitlement }> = [];
  const issues: Array<{ path: string; message: string }> = [];
  for (const g of plan.groups) {
    const code = given[g.code];
    if (g.selection === 'all') {
      if (code !== undefined) issues.push({ path: `selections.${g.code}`, message: 'This group applies in full; no selection needed' });
      continue;
    }
    if (!code) {
      issues.push({ path: `selections.${g.code}`, message: `Choose one of ${g.entitlements.map((e) => e.code).join(', ')}` });
      continue;
    }
    const ent = g.entitlements.find((e) => e.code === code);
    if (!ent) issues.push({ path: `selections.${g.code}`, message: `Unknown option ${code} for ${g.code}` });
    else out.push({ group: g, entitlement: ent });
  }
  for (const key of Object.keys(given)) if (!plan.groups.some((g) => g.code === key)) issues.push({ path: `selections.${key}`, message: 'Unknown group' });
  if (issues.length) throw ApiError.validation('Invalid plan selections', issues);
  return out;
}

// ---------------------------------------------------------------------------
// Membership context (membership + plan + selections + usage → allowances)
// ---------------------------------------------------------------------------

export interface MembershipContext {
  membership: Membership;
  plan: MembershipPlan;
  /** Entitlements in force: the chosen option of every choose_one group + every option of `all` groups. */
  entitlements: MembershipEntitlement[];
  /** Chosen option per group code (current plan). */
  selections: Record<string, string>;
  /** Selections stored for `next_plan_id` (applied at the switch). */
  next_selections: Record<string, string>;
  allowances: Allowance[];
  usage: MembershipUsage[];
}

interface SelectionRow { membership_id: string; group_id: string; entitlement_id: string }

/** Entitlements that apply to a membership given its stored selections (rows for other plans' groups are ignored). */
export function activeEntitlements(plan: MembershipPlan, rows: SelectionRow[]): MembershipEntitlement[] {
  const out: MembershipEntitlement[] = [];
  for (const g of plan.groups) {
    if (g.selection === 'all') {
      out.push(...g.entitlements);
      continue;
    }
    const sel = rows.find((r) => r.group_id === g.id);
    const ent = sel ? g.entitlements.find((e) => e.id === sel.entitlement_id) : undefined;
    if (ent) out.push(ent);
  }
  return out;
}

export function selectionMap(plan: MembershipPlan, rows: SelectionRow[]): Record<string, string> {
  const out: Record<string, string> = {};
  for (const g of plan.groups) {
    const sel = rows.find((r) => r.group_id === g.id);
    const ent = sel ? g.entitlements.find((e) => e.id === sel.entitlement_id) : undefined;
    if (ent) out[g.code] = ent.code;
  }
  return out;
}

/** Period of one entitlement for a membership at `now` (null while pending / no period yet). */
export function entitlementPeriod(membership: Pick<Membership, 'started_at' | 'current_period_start' | 'current_period_end'>, ent: Pick<MembershipEntitlement, 'period'>, now: Date): Period | null {
  if (!membership.current_period_start || !membership.current_period_end) return null;
  if (ent.period === 'year') return annualPeriod(new Date(membership.started_at ?? membership.current_period_start), now);
  return { period_start: new Date(membership.current_period_start).toISOString(), period_end: new Date(membership.current_period_end).toISOString() };
}

/** remaining = quantity − Σ usage in the entitlement's current period (never negative). */
export function computeAllowances(membership: Membership, plan: MembershipPlan, entitlements: MembershipEntitlement[], usage: MembershipUsage[], now: Date): Allowance[] {
  const out: Allowance[] = [];
  for (const g of plan.groups) {
    for (const e of g.entitlements) {
      if (!entitlements.some((x) => x.id === e.id)) continue;
      const period = entitlementPeriod(membership, e, now);
      if (!period) continue;
      const used = usage.filter((u) => u.entitlement_id === e.id && sameInstant(u.period_start, period.period_start)).reduce((a, u) => a + Number(u.quantity), 0);
      out.push({
        entitlement_id: e.id,
        entitlement_code: e.code,
        group_code: g.code,
        label: e.label,
        quantity: e.quantity,
        used: Math.max(0, used),
        remaining: Math.max(0, e.quantity - used),
        period: e.period,
        period_start: period.period_start,
        period_end: period.period_end,
      });
    }
  }
  return out;
}

export async function liveMembership(customerId: string): Promise<Membership | null> {
  const db = getSupabase();
  const rows = unwrap<Membership[]>(await db.from('memberships').select('*').eq('customer_id', customerId).in('status', MEMBERSHIP_LIVE_STATUSES), 'membership');
  return rows.sort((a, b) => String(b.updated_at).localeCompare(String(a.updated_at)))[0] ?? null;
}

export async function getMembershipOrThrow(id: string): Promise<Membership> {
  const m = unwrap<Membership | null>(await getSupabase().from('memberships').select('*').eq('id', id).maybeSingle(), 'membership');
  if (!m) throw ApiError.notFound('Membership');
  return m;
}

/** Builds contexts for many memberships at once (selections + usage in two queries). */
export async function loadContexts(memberships: Membership[], plans?: MembershipPlan[], now = new Date()): Promise<Map<string, MembershipContext>> {
  const out = new Map<string, MembershipContext>();
  if (memberships.length === 0) return out;
  const db = getSupabase();
  const allPlans = plans ?? (await loadPlans({ includeInactive: true }));
  const planById = new Map(allPlans.map((p) => [p.id, p]));
  const ids = memberships.map((m) => m.id);
  const [selRes, usageRes] = await Promise.all([db.from('membership_selections').select('*').in('membership_id', ids), db.from('membership_usage').select('*').in('membership_id', ids)]);
  const sels = unwrap<SelectionRow[]>(selRes, 'membership selections');
  const usage = unwrap<MembershipUsage[]>(usageRes, 'membership usage');
  for (const m of memberships) {
    const plan = planById.get(m.plan_id);
    if (!plan) continue;
    const rows = sels.filter((s) => s.membership_id === m.id);
    const entitlements = activeEntitlements(plan, rows);
    const nextPlan = m.next_plan_id ? planById.get(m.next_plan_id) : undefined;
    const mine = usage.filter((u) => u.membership_id === m.id);
    out.set(m.id, {
      membership: m,
      plan,
      entitlements,
      selections: selectionMap(plan, rows),
      next_selections: nextPlan ? selectionMap(nextPlan, rows) : {},
      allowances: computeAllowances(m, plan, entitlements, mine, now),
      usage: mine,
    });
  }
  return out;
}

/** Live membership context of a customer, or null. */
export async function loadContext(customerId: string, now = new Date()): Promise<MembershipContext | null> {
  const m = await liveMembership(customerId);
  if (!m) return null;
  return (await loadContexts([m], undefined, now)).get(m.id) ?? null;
}

// ---------------------------------------------------------------------------
// Pricing benefit (docs/MEMBERSHIPS.md "Pricing rules")
// ---------------------------------------------------------------------------

export interface MembershipBenefit {
  membership_id: string;
  plan_code: string;
  plan_name: string;
  benefit: MembershipBenefitKind | null;
  /** Percentage applied when `benefit === 'discount'`, else 0. */
  discount_pct: number;
  entitlement_id: string | null;
  entitlement_code: string | null;
  entitlement_quantity: number | null;
  /** Allowance left after this booking (included only). */
  remaining_after: number | null;
  period_start: string | null;
  period_end: string | null;
}

/**
 * Resolves what an active membership does for one service:
 *  - a selected (or `all`-group) entitlement covers it and has allowance left → `included`;
 *  - else the plan discount by scope (plan_services / other_services / all_services);
 *  - else nothing (benefit null). Non-active memberships (pending / past_due) → null.
 */
export function benefitFor(serviceId: string, ctx: MembershipContext | null): MembershipBenefit | null {
  if (!ctx || ctx.membership.status !== 'active') return null;
  const { plan, membership } = ctx;
  const base: MembershipBenefit = {
    membership_id: membership.id,
    plan_code: plan.code,
    plan_name: plan.name,
    benefit: null,
    discount_pct: 0,
    entitlement_id: null,
    entitlement_code: null,
    entitlement_quantity: null,
    remaining_after: null,
    period_start: membership.current_period_start,
    period_end: membership.current_period_end,
  };
  const covering = ctx.entitlements.filter((e) => e.services.some((s) => s.id === serviceId));
  for (const e of covering) {
    const a = ctx.allowances.find((x) => x.entitlement_id === e.id);
    if (a && a.remaining > 0) {
      return { ...base, benefit: 'included', entitlement_id: e.id, entitlement_code: e.code, entitlement_quantity: e.quantity, remaining_after: a.remaining - 1, period_start: a.period_start, period_end: a.period_end };
    }
  }
  const pct = Number(plan.discount_pct ?? 0);
  let discounted = false;
  switch (plan.discount_scope) {
    case 'plan_services':
      discounted = covering.length > 0;
      break;
    case 'other_services':
      discounted = !planServiceIds(plan).has(serviceId);
      break;
    case 'all_services':
      discounted = true;
      break;
    default:
      discounted = false;
  }
  if (discounted && pct > 0) return { ...base, benefit: 'discount', discount_pct: pct };
  return base;
}

// ---------------------------------------------------------------------------
// Usage ledger (append-only, idempotent)
// ---------------------------------------------------------------------------

export interface PostUsageInput {
  membershipId: string;
  entitlementId: string;
  bookingId: string | null;
  quantity: number;
  period: Period;
  idempotencyKey: string;
  createdBy?: string | null;
}

export async function postUsage(input: PostUsageInput): Promise<{ inserted: boolean; usage: MembershipUsage | null }> {
  const db = getSupabase();
  const res = await db
    .from('membership_usage')
    .insert({
      membership_id: input.membershipId,
      entitlement_id: input.entitlementId,
      booking_id: input.bookingId,
      quantity: input.quantity,
      period_start: input.period.period_start,
      period_end: input.period.period_end,
      idempotency_key: input.idempotencyKey,
      created_by: input.createdBy ?? null,
    })
    .select('*')
    .single();
  if (res.error) {
    if (res.error.code === PG_UNIQUE_VIOLATION) {
      const existing = unwrap<MembershipUsage | null>(await db.from('membership_usage').select('*').eq('idempotency_key', input.idempotencyKey).maybeSingle(), 'usage');
      return { inserted: false, usage: existing };
    }
    throw new DatabaseError(res.error, 'membership usage');
  }
  return { inserted: true, usage: res.data as MembershipUsage };
}

/** +1 for a booking that redeems an entitlement (key `booking:<id>:membership`). */
export async function redeemForBooking(booking: { id: string; membership_id: string | null; entitlement_id: string | null; membership_benefit: MembershipBenefitKind | null }, period: Period, createdBy: string | null): Promise<{ inserted: boolean }> {
  if (booking.membership_benefit !== 'included' || !booking.membership_id || !booking.entitlement_id) return { inserted: false };
  const r = await postUsage({ membershipId: booking.membership_id, entitlementId: booking.entitlement_id, bookingId: booking.id, quantity: 1, period, idempotencyKey: `booking:${booking.id}:membership`, createdBy });
  return { inserted: r.inserted };
}

/** −1 release when a redeeming booking is cancelled (key `booking:<id>:membership_release`); no-op without a redeem row. */
export async function releaseForBooking(bookingId: string, createdBy: string | null): Promise<{ inserted: boolean }> {
  const db = getSupabase();
  const redeem = unwrap<MembershipUsage | null>(await db.from('membership_usage').select('*').eq('idempotency_key', `booking:${bookingId}:membership`).maybeSingle(), 'usage');
  if (!redeem) return { inserted: false };
  const r = await postUsage({
    membershipId: redeem.membership_id,
    entitlementId: redeem.entitlement_id,
    bookingId,
    quantity: -Number(redeem.quantity),
    period: { period_start: redeem.period_start, period_end: redeem.period_end },
    idempotencyKey: `booking:${bookingId}:membership_release`,
    createdBy,
  });
  return { inserted: r.inserted };
}

// ---------------------------------------------------------------------------
// Tier sync (mirrors the DB trigger `memberships_sync_tier`)
// ---------------------------------------------------------------------------

export async function syncTier(customerId: string): Promise<LoyaltyTier> {
  const db = getSupabase();
  const live = unwrap<Membership[]>(await db.from('memberships').select('*').eq('customer_id', customerId).in('status', ['active', 'past_due']), 'memberships');
  let tier: LoyaltyTier = 'silver';
  const current = live.sort((a, b) => String(b.updated_at).localeCompare(String(a.updated_at)))[0];
  if (current) {
    const plan = unwrap<{ tier: LoyaltyTier } | null>(await db.from('membership_plans').select('tier').eq('id', current.plan_id).maybeSingle(), 'plan');
    tier = plan?.tier ?? 'silver';
  }
  const acct = unwrap<{ tier: LoyaltyTier } | null>(await db.from('loyalty_accounts').select('tier').eq('customer_id', customerId).maybeSingle(), 'account');
  if (!acct) {
    const ins = await db.from('loyalty_accounts').insert({ customer_id: customerId, tier, tier_since: new Date().toISOString(), balance_points: 0, lifetime_points: 0 });
    if (ins.error && ins.error.code !== PG_UNIQUE_VIOLATION) throw new DatabaseError(ins.error, 'loyalty account');
  } else if (acct.tier !== tier) {
    await db.from('loyalty_accounts').update({ tier, tier_since: new Date().toISOString() }).eq('customer_id', customerId);
  }
  return tier;
}

// ---------------------------------------------------------------------------
// Summaries
// ---------------------------------------------------------------------------

export function benefitsSummary(ctx: MembershipContext | null): string {
  if (!ctx) return '';
  const parts = ctx.allowances.map((a) => `${a.remaining} of ${a.quantity} ${primaryName(ctx, a)} left`);
  if (ctx.plan.discount_pct > 0 && ctx.plan.discount_scope !== 'none') parts.push(ctx.plan.discount_note ?? `${ctx.plan.discount_pct}% off ${ctx.plan.discount_scope === 'other_services' ? 'other services' : 'plan services'}`);
  return parts.join(' · ');
}

function primaryName(ctx: MembershipContext, a: Allowance): string {
  const ent = ctx.entitlements.find((e) => e.id === a.entitlement_id);
  const svc = ent?.services.find((s) => s.is_primary) ?? ent?.services[0];
  const name = svc?.name ?? a.label;
  if (a.quantity === 1) return name;
  return /(s|sh|ch|x)$/i.test(name) ? `${name}es` : `${name}s`;
}

export function toBrief(ctx: MembershipContext): MembershipBrief {
  return {
    membership_id: ctx.membership.id,
    plan_code: ctx.plan.code,
    plan_name: ctx.plan.name,
    tier: ctx.plan.tier,
    status: ctx.membership.status,
    period_end: ctx.membership.current_period_end,
    cancel_at_period_end: !!ctx.membership.cancel_at_period_end,
    allowances: ctx.allowances,
  };
}

/** Brief per customer id (batch; customers without a live membership are absent). */
export async function membershipBriefs(customerIds: string[], now = new Date()): Promise<Map<string, MembershipBrief>> {
  const out = new Map<string, MembershipBrief>();
  if (customerIds.length === 0) return out;
  const db = getSupabase();
  const rows = unwrap<Membership[]>(await db.from('memberships').select('*').in('customer_id', customerIds).in('status', MEMBERSHIP_LIVE_STATUSES), 'memberships');
  const ctxs = await loadContexts(rows, undefined, now);
  for (const ctx of ctxs.values()) out.set(ctx.membership.customer_id, toBrief(ctx));
  return out;
}

export async function membershipBrief(customerId: string, now = new Date()): Promise<MembershipBrief | null> {
  const ctx = await loadContext(customerId, now);
  return ctx ? toBrief(ctx) : null;
}

/** Sum of remaining monthly washes (group `washes`; every monthly entitlement when the plan has no such group). */
export function includedRemaining(brief: MembershipBrief | null | undefined): number {
  if (!brief) return 0;
  const monthly = brief.allowances.filter((a) => a.period === 'month');
  const washes = monthly.filter((a) => a.group_code === 'washes');
  return (washes.length ? washes : monthly).reduce((a, x) => a + x.remaining, 0);
}

/** `GET /memberships/me` shape for a customer. */
export async function membershipSummary(customerId: string, now = new Date()): Promise<MembershipSummary> {
  const ctx = await loadContext(customerId, now);
  if (!ctx) return { membership: null, plan: null, next_plan: null, selections: {}, allowances: [], open_invoice: null, invoices: [], next_renewal_at: null, benefits_summary: '' };
  const db = getSupabase();
  const invoices = unwrap<MembershipInvoice[]>(await db.from('membership_invoices').select('*').eq('membership_id', ctx.membership.id), 'invoices').sort((a, b) => String(b.period_start).localeCompare(String(a.period_start)) || String(b.created_at).localeCompare(String(a.created_at)));
  const open = invoices.find((i) => i.status === 'pending') ?? null;
  const nextPlan = ctx.membership.next_plan_id ? (await loadPlans({ includeInactive: true })).find((p) => p.id === ctx.membership.next_plan_id) : null;
  return {
    membership: ctx.membership,
    plan: ctx.plan,
    next_plan: nextPlan ? { id: nextPlan.id, code: nextPlan.code, name: nextPlan.name, monthly_fee_cents: nextPlan.monthly_fee_cents } : null,
    selections: ctx.selections,
    allowances: ctx.allowances,
    open_invoice: open,
    invoices: invoices.slice(0, 12),
    next_renewal_at: ctx.membership.cancel_at_period_end ? null : ctx.membership.current_period_end,
    benefits_summary: benefitsSummary(ctx),
  };
}

// ---------------------------------------------------------------------------
// Invoices & payments
// ---------------------------------------------------------------------------

async function insertInvoice(row: { membership_id: string; customer_id: string; period: Period; amount_cents: number; due_at: string; idempotency_key: string; status?: MembershipInvoice['status']; paid_at?: string | null }): Promise<{ invoice: MembershipInvoice; created: boolean }> {
  const db = getSupabase();
  const res = await db
    .from('membership_invoices')
    .insert({
      membership_id: row.membership_id,
      customer_id: row.customer_id,
      period_start: row.period.period_start,
      period_end: row.period.period_end,
      amount_cents: row.amount_cents,
      status: row.status ?? 'pending',
      due_at: row.due_at,
      paid_at: row.paid_at ?? null,
      idempotency_key: row.idempotency_key,
    })
    .select('*')
    .single();
  if (res.error) {
    if (res.error.code === PG_UNIQUE_VIOLATION) {
      const existing = unwrap<MembershipInvoice>(await db.from('membership_invoices').select('*').eq('idempotency_key', row.idempotency_key).single(), 'invoice');
      return { invoice: existing, created: false };
    }
    throw new DatabaseError(res.error, 'membership invoice');
  }
  return { invoice: res.data as MembershipInvoice, created: true };
}

async function voidPendingInvoices(membershipId: string, exceptId?: string): Promise<number> {
  const db = getSupabase();
  const pending = unwrap<MembershipInvoice[]>(await db.from('membership_invoices').select('*').eq('membership_id', membershipId).eq('status', 'pending'), 'invoices');
  let n = 0;
  for (const inv of pending) {
    if (inv.id === exceptId) continue;
    await db.from('membership_invoices').update({ status: 'void' }).eq('id', inv.id);
    n++;
  }
  return n;
}

export interface InvoiceIntent {
  payment: Payment;
  client_secret: string | null;
  duplicate: boolean;
}

/**
 * Creates (or replays) a provider payment intent for a pending invoice. A
 * pending/initiated payment for the invoice is returned as-is; failed ones are
 * superseded by a new attempt (key `<customer>:minv:<invoice>:<n>`).
 */
export async function createInvoiceIntent(invoice: MembershipInvoice): Promise<InvoiceIntent> {
  const db = getSupabase();
  if (invoice.status !== 'pending') throw ApiError.conflict(`Invoice is ${invoice.status}`, { invoice_id: invoice.id, status: invoice.status });
  const prior = unwrap<Payment[]>(await db.from('payments').select('*').eq('membership_invoice_id', invoice.id), 'payments').sort((a, b) => String(a.created_at).localeCompare(String(b.created_at)));
  const open = prior.find((p) => p.status === 'pending' || p.status === 'initiated');
  if (open) return { payment: open, client_secret: null, duplicate: true };
  const paid = prior.find((p) => p.status === 'successful');
  if (paid) throw ApiError.conflict('Invoice is already paid', { payment_id: paid.id });
  const provider = getPaymentProvider();
  const key = `${invoice.customer_id}:minv:${invoice.id}:${prior.length + 1}`;
  const initiated = unwrap<Payment>(
    await db
      .from('payments')
      .insert({ booking_id: null, membership_invoice_id: invoice.id, customer_id: invoice.customer_id, provider: provider.name, amount_cents: invoice.amount_cents, currency: 'ZAR', status: 'initiated', idempotency_key: key })
      .select('*')
      .single(),
    'create membership payment',
  );
  const intent = await provider.createIntent({ payment: initiated });
  const payment = unwrap<Payment>(await db.from('payments').update({ status: 'pending', provider_ref: intent.provider_ref }).eq('id', initiated.id).select('*').single(), 'membership payment pending');
  return { payment, client_secret: intent.client_secret ?? null, duplicate: false };
}

/** Applies the paid invoice's period (and any pending plan switch) to the membership. */
async function rollPeriod(membership: Membership, invoice: MembershipInvoice, plans: MembershipPlan[]): Promise<Membership> {
  const db = getSupabase();
  const patch: Record<string, unknown> = { status: 'active', current_period_start: invoice.period_start, current_period_end: invoice.period_end };
  if (membership.next_plan_id && membership.next_plan_id !== membership.plan_id) {
    const oldPlan = plans.find((p) => p.id === membership.plan_id);
    patch.plan_id = membership.next_plan_id;
    patch.next_plan_id = null;
    if (oldPlan?.groups.length) await db.from('membership_selections').delete().eq('membership_id', membership.id).in('group_id', oldPlan.groups.map((g) => g.id));
  } else if (membership.next_plan_id) {
    patch.next_plan_id = null;
  }
  return unwrap<Membership>(await db.from('memberships').update(patch).eq('id', membership.id).select('*').single(), 'roll membership period');
}

export type MembershipPaidEvent = 'activated' | 'renewed' | 'deferred' | 'noop';

/**
 * Hook for `payments` reaching `successful` with `membership_invoice_id`:
 * marks the invoice paid, activates a pending membership (period = now → +1
 * month) or rolls an active/past_due one to the invoice period (a renewal paid
 * before the period ends is applied by the renewals job at period end), then
 * notifies `membership_activated` / `membership_renewed`. Idempotent.
 */
export async function applyMembershipInvoicePaid(payment: Payment, now = new Date()): Promise<{ membership: Membership; invoice: MembershipInvoice; event: MembershipPaidEvent } | null> {
  const db = getSupabase();
  if (!payment.membership_invoice_id) return null;
  const invoice = unwrap<MembershipInvoice | null>(await db.from('membership_invoices').select('*').eq('id', payment.membership_invoice_id).maybeSingle(), 'invoice');
  if (!invoice) return null;
  const membership = await getMembershipOrThrow(invoice.membership_id);
  if (invoice.status === 'paid') return { membership, invoice, event: 'noop' };
  const plans = await loadPlans({ includeInactive: true });
  const plan = plans.find((p) => p.id === membership.plan_id);
  let paidInvoice = unwrap<MembershipInvoice>(await db.from('membership_invoices').update({ status: 'paid', paid_at: now.toISOString(), payment_id: payment.id }).eq('id', invoice.id).select('*').single(), 'invoice paid');

  let updated: Membership;
  let event: MembershipPaidEvent;
  if (membership.status === 'pending' || !membership.current_period_end) {
    const period = monthlyPeriod(now);
    updated = unwrap<Membership>(
      await db.from('memberships').update({ status: 'active', started_at: membership.started_at ?? period.period_start, current_period_start: period.period_start, current_period_end: period.period_end }).eq('id', membership.id).select('*').single(),
      'activate membership',
    );
    paidInvoice = unwrap<MembershipInvoice>(await db.from('membership_invoices').update({ period_start: period.period_start, period_end: period.period_end }).eq('id', invoice.id).select('*').single(), 'invoice period');
    event = 'activated';
  } else if (new Date(invoice.period_start).getTime() <= now.getTime() || membership.status === 'past_due') {
    updated = await rollPeriod(membership, paidInvoice, plans);
    event = 'renewed';
  } else {
    // Paid ahead of the period end: keep the current allowances; the renewals job rolls at period end.
    updated = membership;
    event = 'deferred';
  }
  await syncTier(updated.customer_id);
  const effectivePlan = plans.find((p) => p.id === updated.plan_id) ?? plan;
  const ctx = (await loadContexts([updated], plans, now)).get(updated.id) ?? null;
  await notify({
    recipientId: updated.customer_id,
    templateKey: event === 'activated' ? 'membership_activated' : 'membership_renewed',
    vars: { plan: effectivePlan?.name ?? '', amount: formatFee(paidInvoice.amount_cents), period_end: formatDateSA(updated.current_period_end), benefits: benefitsSummary(ctx), membership_id: updated.id },
    dedupeKey: `${event === 'activated' ? 'membership_activated' : 'membership_renewed'}:${paidInvoice.id}`,
    payload: { type: 'membership', membership_id: updated.id, invoice_id: paidInvoice.id },
  });
  return { membership: updated, invoice: paidInvoice, event };
}

// ---------------------------------------------------------------------------
// Subscribe (customer, sandbox card) / enrol (counter)
// ---------------------------------------------------------------------------

export interface SubscribeInput {
  customerId: string;
  planCode: string;
  selections: Record<string, string>;
  clientOpId: string;
}

export interface SubscribeResult {
  membership: Membership;
  invoice: MembershipInvoice;
  payment: (Payment & { client_secret: string | null }) | null;
  duplicate: boolean;
}

async function assertNoLiveMembership(customerId: string): Promise<void> {
  const live = await liveMembership(customerId);
  if (live) throw ApiError.conflict('Customer already has a membership', { membership_id: live.id, status: live.status });
}

async function insertMembership(row: Record<string, unknown>, clientOpId: string): Promise<{ membership: Membership; duplicate: boolean }> {
  const db = getSupabase();
  const res = await db.from('memberships').insert({ ...row, client_op_id: clientOpId }).select('*').single();
  if (res.error) {
    if (res.error.code === PG_UNIQUE_VIOLATION) {
      const dup = unwrap<Membership | null>(await db.from('memberships').select('*').eq('client_op_id', clientOpId).maybeSingle(), 'membership');
      if (dup) return { membership: dup, duplicate: true };
      throw ApiError.conflict('Customer already has a membership');
    }
    throw new DatabaseError(res.error, 'create membership');
  }
  return { membership: res.data as Membership, duplicate: false };
}

async function storeSelections(membershipId: string, chosen: Array<{ group: MembershipGroup; entitlement: MembershipEntitlement }>): Promise<void> {
  const db = getSupabase();
  if (chosen.length === 0) return;
  await db.from('membership_selections').delete().eq('membership_id', membershipId).in('group_id', chosen.map((c) => c.group.id));
  const ins = await db.from('membership_selections').insert(chosen.map((c) => ({ membership_id: membershipId, group_id: c.group.id, entitlement_id: c.entitlement.id })));
  if (ins.error) throw new DatabaseError(ins.error, 'membership selections');
}

/** Customer self-service: pending membership + first invoice + sandbox payment intent (activated on payment success). */
export async function subscribe(ctx: RequestContext, input: SubscribeInput): Promise<SubscribeResult> {
  const db = getSupabase();
  const prior = unwrap<Membership | null>(await db.from('memberships').select('*').eq('client_op_id', input.clientOpId).maybeSingle(), 'membership');
  if (prior) {
    const inv = unwrap<MembershipInvoice[]>(await db.from('membership_invoices').select('*').eq('membership_id', prior.id), 'invoices').sort((a, b) => String(a.created_at).localeCompare(String(b.created_at)))[0];
    const pay = inv ? unwrap<Payment[]>(await db.from('payments').select('*').eq('membership_invoice_id', inv.id), 'payments')[0] ?? null : null;
    return { membership: prior, invoice: inv, payment: pay ? { ...pay, client_secret: null } : null, duplicate: true };
  }
  await assertNoLiveMembership(input.customerId);
  const plan = await getPlanByCode(input.planCode);
  const chosen = resolveSelections(plan, input.selections);
  const now = new Date();
  const { membership, duplicate } = await insertMembership({ customer_id: input.customerId, plan_id: plan.id, status: 'pending', started_at: null, current_period_start: null, current_period_end: null, payment_method: 'card', created_by: ctx.auth.uid }, input.clientOpId);
  if (duplicate) return subscribe(ctx, input);
  await storeSelections(membership.id, chosen);
  const { invoice } = await insertInvoice({ membership_id: membership.id, customer_id: input.customerId, period: monthlyPeriod(now), amount_cents: plan.monthly_fee_cents, due_at: now.toISOString(), idempotency_key: `first:${membership.id}` });
  const intent = await createInvoiceIntent(invoice);
  await audit(ctx, { action: 'membership.subscribe', entity_type: 'membership', entity_id: membership.id, after: { ref: membership.ref, plan_code: plan.code, selections: input.selections, amount_cents: invoice.amount_cents, invoice_id: invoice.id, payment_id: intent.payment.id } });
  return { membership, invoice, payment: { ...intent.payment, client_secret: intent.client_secret }, duplicate: false };
}

export interface EnrolInput {
  customerId: string;
  planCode: string;
  selections: Record<string, string>;
  paymentMethod: Extract<PosPaymentMethod, 'cash' | 'card_terminal' | 'eft'>;
  clientOpId: string;
  reference?: string | null;
  outletId?: string | null;
}

export interface EnrolResult {
  membership: Membership;
  invoice: MembershipInvoice;
  payment: Payment | null;
  duplicate: boolean;
}

function membershipMethodFor(method: PosPaymentMethod): Membership['payment_method'] {
  if (method === 'cash') return 'cash';
  if (method === 'eft') return 'eft';
  return 'card';
}

/** Inserts a `pos` payment row like `payment.record`, but for a membership invoice. */
async function insertPosPayment(ctx: RequestContext, invoice: MembershipInvoice, method: PosPaymentMethod, key: string, reference: string | null): Promise<{ payment: Payment; duplicate: boolean }> {
  const db = getSupabase();
  const replay = unwrap<Payment | null>(await db.from('payments').select('*').eq('idempotency_key', key).maybeSingle(), 'payment');
  if (replay) return { payment: replay, duplicate: true };
  const now = new Date().toISOString();
  let payment: Payment | null = null;
  for (let attempt = 0; attempt < 3 && !payment; attempt++) {
    const receipt = await nextReceiptNo(db);
    const res = await db
      .from('payments')
      .insert({
        booking_id: null,
        membership_invoice_id: invoice.id,
        customer_id: invoice.customer_id,
        provider: POS_PROVIDER,
        method,
        provider_ref: reference?.trim() || null,
        amount_cents: invoice.amount_cents,
        currency: 'ZAR',
        status: 'successful',
        receipt_no: receipt,
        idempotency_key: key,
        verified_at: now,
        recorded_by: ctx.auth.uid,
      })
      .select('*')
      .single();
    if (!res.error) {
      payment = res.data as Payment;
      break;
    }
    if (res.error.code !== PG_UNIQUE_VIOLATION) throw new DatabaseError(res.error, 'record membership payment');
    if (`${res.error.message} ${res.error.details ?? ''}`.includes('idempotency_key')) {
      const dup = unwrap<Payment | null>(await db.from('payments').select('*').eq('idempotency_key', key).maybeSingle(), 'payment');
      if (dup) return { payment: dup, duplicate: true };
    }
  }
  if (!payment) throw ApiError.internal('Could not allocate a receipt number');
  const event = await db.from('payment_events').insert({
    payment_id: payment.id,
    provider: POS_PROVIDER,
    provider_event_id: key,
    event_type: POS_EVENT_TYPE,
    signature_ok: true,
    payload: { actor: ctx.auth.uid, actor_role: ctx.auth.role, method, reference: payment.provider_ref, amount_cents: payment.amount_cents, membership_invoice_id: invoice.id },
  });
  if (event.error && event.error.code !== PG_UNIQUE_VIOLATION) throw new DatabaseError(event.error, 'pos payment event');
  return { payment, duplicate: false };
}

/** Staff/admin counter enrolment: membership active immediately, invoice paid, POS payment row. */
export async function enrolAtCounter(ctx: RequestContext, input: EnrolInput): Promise<EnrolResult> {
  const db = getSupabase();
  const prior = unwrap<Membership | null>(await db.from('memberships').select('*').eq('client_op_id', input.clientOpId).maybeSingle(), 'membership');
  if (prior) {
    const inv = unwrap<MembershipInvoice[]>(await db.from('membership_invoices').select('*').eq('membership_id', prior.id), 'invoices').sort((a, b) => String(a.created_at).localeCompare(String(b.created_at)))[0];
    const pay = inv ? unwrap<Payment[]>(await db.from('payments').select('*').eq('membership_invoice_id', inv.id), 'payments')[0] ?? null : null;
    return { membership: prior, invoice: inv, payment: pay, duplicate: true };
  }
  await assertNoLiveMembership(input.customerId);
  const plan = await getPlanByCode(input.planCode);
  const chosen = resolveSelections(plan, input.selections);
  const now = new Date();
  const period = monthlyPeriod(now);
  const { membership, duplicate } = await insertMembership(
    { customer_id: input.customerId, plan_id: plan.id, status: 'active', started_at: period.period_start, current_period_start: period.period_start, current_period_end: period.period_end, payment_method: membershipMethodFor(input.paymentMethod), created_by: ctx.auth.uid },
    input.clientOpId,
  );
  if (duplicate) return enrolAtCounter(ctx, input);
  await storeSelections(membership.id, chosen);
  const { invoice } = await insertInvoice({ membership_id: membership.id, customer_id: input.customerId, period, amount_cents: plan.monthly_fee_cents, due_at: now.toISOString(), paid_at: now.toISOString(), status: 'paid', idempotency_key: `first:${membership.id}` });
  const { payment } = await insertPosPayment(ctx, invoice, input.paymentMethod, posIdempotencyKey(ctx.auth.uid, `membership:${input.clientOpId}`), input.reference ?? null);
  const paidInvoice = unwrap<MembershipInvoice>(await db.from('membership_invoices').update({ payment_id: payment.id }).eq('id', invoice.id).select('*').single(), 'invoice');
  await syncTier(input.customerId);
  const mctx = (await loadContexts([membership], undefined, now)).get(membership.id) ?? null;
  await notify({
    recipientId: input.customerId,
    templateKey: 'membership_activated',
    vars: { plan: plan.name, amount: formatFee(paidInvoice.amount_cents), period_end: formatDateSA(membership.current_period_end), benefits: benefitsSummary(mctx), membership_id: membership.id },
    dedupeKey: `membership_activated:${paidInvoice.id}`,
    payload: { type: 'membership', membership_id: membership.id, invoice_id: paidInvoice.id },
  });
  await audit(ctx, {
    action: 'membership.enrol',
    entity_type: 'membership',
    entity_id: membership.id,
    outlet_id: input.outletId ?? ctx.auth.outletIds[0] ?? null,
    after: { ref: membership.ref, customer_id: input.customerId, plan_code: plan.code, selections: input.selections, method: input.paymentMethod, amount_cents: paidInvoice.amount_cents, receipt_no: payment.receipt_no, payment_id: payment.id },
  });
  return { membership, invoice: paidInvoice, payment, duplicate: false };
}

/** Staff/admin: pays a pending (renewal) invoice at the counter; rolls the period like a card payment. */
export async function recordInvoicePayment(ctx: RequestContext, membershipId: string, invoiceId: string, input: { method: PosPaymentMethod; clientOpId: string; reference?: string | null; outletId?: string | null }): Promise<{ payment: Payment; invoice: MembershipInvoice; membership: Membership; duplicate: boolean }> {
  const db = getSupabase();
  const membership = await getMembershipOrThrow(membershipId);
  const invoice = unwrap<MembershipInvoice | null>(await db.from('membership_invoices').select('*').eq('id', invoiceId).eq('membership_id', membershipId).maybeSingle(), 'invoice');
  if (!invoice) throw ApiError.notFound('Invoice');
  const key = posIdempotencyKey(ctx.auth.uid, `minv:${input.clientOpId}`);
  const replay = unwrap<Payment | null>(await db.from('payments').select('*').eq('idempotency_key', key).maybeSingle(), 'payment');
  if (replay) return { payment: replay, invoice, membership, duplicate: true };
  if (invoice.status !== 'pending') throw ApiError.conflict(`Invoice is ${invoice.status}`, { invoice_id: invoice.id, status: invoice.status });
  const { payment } = await insertPosPayment(ctx, invoice, input.method, key, input.reference ?? null);
  const applied = await applyMembershipInvoicePaid(payment);
  await audit(ctx, {
    action: 'membership.record_payment',
    entity_type: 'membership',
    entity_id: membership.id,
    outlet_id: input.outletId ?? ctx.auth.outletIds[0] ?? null,
    after: { invoice_id: invoice.id, invoice_ref: invoice.ref, amount_cents: payment.amount_cents, method: input.method, receipt_no: payment.receipt_no, payment_id: payment.id, event: applied?.event ?? null },
  });
  return { payment, invoice: applied?.invoice ?? invoice, membership: applied?.membership ?? membership, duplicate: false };
}

/** Customer: sandbox payment intent for a pending invoice (renewal / upgrade). */
export async function payInvoice(ctx: RequestContext, invoiceId: string): Promise<InvoiceIntent & { invoice: MembershipInvoice }> {
  const db = getSupabase();
  const invoice = unwrap<MembershipInvoice | null>(await db.from('membership_invoices').select('*').eq('id', invoiceId).maybeSingle(), 'invoice');
  if (!invoice) throw ApiError.notFound('Invoice');
  if (invoice.customer_id !== ctx.auth.uid) throw ApiError.forbidden();
  const intent = await createInvoiceIntent(invoice);
  if (!intent.duplicate) await audit(ctx, { action: 'membership.pay_invoice', entity_type: 'membership_invoice', entity_id: invoice.id, after: { membership_id: invoice.membership_id, amount_cents: invoice.amount_cents, payment_id: intent.payment.id } });
  return { ...intent, invoice };
}

// ---------------------------------------------------------------------------
// Changes: selections, plan, cancel
// ---------------------------------------------------------------------------

function usedThisPeriod(ctx: MembershipContext): number {
  return ctx.allowances.reduce((a, x) => a + x.used, 0);
}

/** Replaces the chosen options; 409 once anything has been redeemed this period. */
export async function changeSelections(ctx: RequestContext, customerId: string, selections: Record<string, string>): Promise<MembershipSummary> {
  const mctx = await loadContext(customerId);
  if (!mctx) throw ApiError.notFound('Membership');
  const used = usedThisPeriod(mctx);
  if (used > 0) throw ApiError.conflict('Selections can only change before any allowance is used this period', { used, period_end: mctx.membership.current_period_end });
  const chosen = resolveSelections(mctx.plan, selections);
  await storeSelections(mctx.membership.id, chosen);
  await audit(ctx, { action: 'membership.selections', entity_type: 'membership', entity_id: mctx.membership.id, before: mctx.selections, after: selections });
  return membershipSummary(customerId);
}

export interface ChangePlanResult {
  membership: Membership;
  change: 'upgrade' | 'downgrade';
  invoice: MembershipInvoice | null;
  payment: (Payment & { client_secret: string | null }) | null;
  applies_at: string | null;
}

/**
 * Upgrade (higher fee) → new full-fee invoice now (+ sandbox intent); the plan
 * and a fresh period start on payment. Downgrade → `next_plan_id`, applied at
 * renewal. Selections for the new plan are stored alongside (their groups
 * belong to the new plan, so they do not collide with the current ones).
 */
export async function changePlan(ctx: RequestContext, customerId: string, input: { planCode: string; selections: Record<string, string> }): Promise<ChangePlanResult> {
  const db = getSupabase();
  const mctx = await loadContext(customerId);
  if (!mctx) throw ApiError.notFound('Membership');
  if (mctx.membership.status !== 'active') throw ApiError.conflict(`Membership is ${mctx.membership.status}`, { status: mctx.membership.status });
  const target = await getPlanByCode(input.planCode);
  if (target.id === mctx.plan.id) throw ApiError.conflict('Already on this plan', { plan_code: target.code });
  const chosen = resolveSelections(target, input.selections);
  await storeSelections(mctx.membership.id, chosen);
  const now = new Date();
  if (target.monthly_fee_cents > mctx.plan.monthly_fee_cents) {
    await voidPendingInvoices(mctx.membership.id);
    const { invoice } = await insertInvoice({ membership_id: mctx.membership.id, customer_id: customerId, period: monthlyPeriod(now), amount_cents: target.monthly_fee_cents, due_at: now.toISOString(), idempotency_key: `upgrade:${mctx.membership.id}:${target.code}:${now.toISOString()}` });
    const membership = unwrap<Membership>(await db.from('memberships').update({ next_plan_id: target.id }).eq('id', mctx.membership.id).select('*').single(), 'membership');
    const intent = await createInvoiceIntent(invoice);
    await audit(ctx, { action: 'membership.change_plan', entity_type: 'membership', entity_id: membership.id, before: { plan_code: mctx.plan.code }, after: { plan_code: target.code, change: 'upgrade', invoice_id: invoice.id, amount_cents: invoice.amount_cents } });
    return { membership, change: 'upgrade', invoice, payment: { ...intent.payment, client_secret: intent.client_secret }, applies_at: null };
  }
  const membership = unwrap<Membership>(await db.from('memberships').update({ next_plan_id: target.id }).eq('id', mctx.membership.id).select('*').single(), 'membership');
  await audit(ctx, { action: 'membership.change_plan', entity_type: 'membership', entity_id: membership.id, before: { plan_code: mctx.plan.code }, after: { plan_code: target.code, change: 'downgrade', applies_at: membership.current_period_end } });
  return { membership, change: 'downgrade', invoice: null, payment: null, applies_at: membership.current_period_end };
}

/** Cancel at period end (default) or immediately (benefits stop, tier → silver). */
export async function cancelMembership(ctx: RequestContext, membershipId: string, opts: { atPeriodEnd: boolean; reason?: string | null }): Promise<Membership> {
  const db = getSupabase();
  const membership = await getMembershipOrThrow(membershipId);
  if (!MEMBERSHIP_LIVE_STATUSES.includes(membership.status)) throw ApiError.conflict(`Membership is already ${membership.status}`, { status: membership.status });
  const now = new Date().toISOString();
  const plan = unwrap<{ name: string } | null>(await db.from('membership_plans').select('name').eq('id', membership.plan_id).maybeSingle(), 'plan');
  let updated: Membership;
  const immediate = !opts.atPeriodEnd || membership.status === 'pending' || !membership.current_period_end;
  if (immediate) {
    updated = unwrap<Membership>(await db.from('memberships').update({ status: 'cancelled', cancel_at_period_end: false, cancelled_at: now, ended_at: now, next_plan_id: null }).eq('id', membershipId).select('*').single(), 'cancel membership');
    await voidPendingInvoices(membershipId);
  } else {
    if (membership.cancel_at_period_end) return membership;
    updated = unwrap<Membership>(await db.from('memberships').update({ cancel_at_period_end: true, cancelled_at: now, next_plan_id: null }).eq('id', membershipId).select('*').single(), 'cancel membership');
    await voidPendingInvoices(membershipId);
  }
  await syncTier(membership.customer_id);
  await notify({
    recipientId: membership.customer_id,
    templateKey: 'membership_cancelled',
    vars: { plan: plan?.name ?? '', period_end: formatDateSA(immediate ? now : membership.current_period_end), membership_id: membership.id },
    dedupeKey: `membership_cancelled:${membership.id}:${now}`,
    payload: { type: 'membership', membership_id: membership.id },
  });
  await audit(ctx, { action: 'membership.cancel', entity_type: 'membership', entity_id: membership.id, before: { status: membership.status }, after: { status: updated.status, cancel_at_period_end: updated.cancel_at_period_end, immediate, reason: opts.reason ?? null, on_behalf: membership.customer_id !== ctx.auth.uid } });
  return updated;
}

// ---------------------------------------------------------------------------
// Renewals job (daily; also POST /admin/memberships/run-renewals)
// ---------------------------------------------------------------------------

export interface RenewalRunResult {
  ran_at: string;
  scanned: number;
  rolled: number;
  cancelled: number;
  expired: number;
  invoices_created: number;
  auto_charged: number;
  past_due: number;
  errors: Array<{ membership_id: string; message: string }>;
}

export function renewalInvoiceKey(membershipId: string, periodStart: string): string {
  return `renewal:${membershipId}:${new Date(periodStart).toISOString().slice(0, 10)}`;
}

/**
 * 1. cancel_at_period_end and period ended → cancelled (ended_at); past_due for
 *    PAST_DUE_EXPIRY_DAYS after the period end → expired. Tier → silver.
 * 2. active, period ends within RENEWAL_LEAD_DAYS, no invoice for the next
 *    period → create it (fee of next_plan when a downgrade is pending) and
 *    notify membership_renewal_due.
 * 4. payment_method = 'card' with the sandbox provider (and not a counter
 *    member) → the due renewal invoice is auto-charged; success rolls the period.
 * 3. period ended and the invoice still unpaid → past_due, membership_past_due.
 * (4 runs before 3 so a successful card charge is never flagged past_due.)
 * A renewal paid ahead of time is applied (period rolled) once the period ends.
 */
export async function runRenewals(now = new Date()): Promise<RenewalRunResult> {
  const db = getSupabase();
  const result: RenewalRunResult = { ran_at: now.toISOString(), scanned: 0, rolled: 0, cancelled: 0, expired: 0, invoices_created: 0, auto_charged: 0, past_due: 0, errors: [] };
  const plans = await loadPlans({ includeInactive: true });
  const planById = new Map(plans.map((p) => [p.id, p]));
  const live = unwrap<Membership[]>(await db.from('memberships').select('*').in('status', ['active', 'past_due']), 'memberships');
  result.scanned = live.length;
  if (live.length === 0) return result;
  const invoicesAll = unwrap<MembershipInvoice[]>(await db.from('membership_invoices').select('*').in('membership_id', live.map((m) => m.id)), 'invoices');
  const paymentsAll = invoicesAll.length ? unwrap<Payment[]>(await db.from('payments').select('*').in('membership_invoice_id', invoicesAll.map((i) => i.id)), 'payments') : [];
  const sandbox = getPaymentProvider().name === 'sandbox';
  const leadMs = RENEWAL_LEAD_DAYS * 86_400_000;

  for (const original of live) {
    let m = original;
    try {
      const plan = planById.get(m.plan_id);
      if (!plan || !m.current_period_end) continue;
      const end = new Date(m.current_period_end).getTime();
      const ended = end <= now.getTime();
      const invoices = invoicesAll.filter((i) => i.membership_id === m.id);
      const nextInvoice = (): MembershipInvoice | undefined => invoices.find((i) => sameInstant(i.period_start, m.current_period_end) && i.status !== 'void');

      // 1. end of life
      if (ended && m.cancel_at_period_end) {
        await db.from('memberships').update({ status: 'cancelled', ended_at: now.toISOString() }).eq('id', m.id);
        await voidPendingInvoices(m.id);
        await syncTier(m.customer_id);
        result.cancelled++;
        continue;
      }
      if (m.status === 'past_due' && end + PAST_DUE_EXPIRY_DAYS * 86_400_000 <= now.getTime()) {
        await db.from('memberships').update({ status: 'expired', ended_at: now.toISOString() }).eq('id', m.id);
        await voidPendingInvoices(m.id);
        await syncTier(m.customer_id);
        result.expired++;
        continue;
      }

      // Paid ahead of time → roll now that the period has ended.
      const paidNext = ended ? invoices.find((i) => sameInstant(i.period_start, m.current_period_end) && i.status === 'paid') : undefined;
      if (paidNext) {
        m = await rollPeriod(m, paidNext, plans);
        await syncTier(m.customer_id);
        result.rolled++;
        continue;
      }

      // 2. next invoice
      let invoice = nextInvoice();
      if (m.status === 'active' && !m.cancel_at_period_end && end <= now.getTime() + leadMs && !invoice) {
        const feePlan = (m.next_plan_id && planById.get(m.next_plan_id)) || plan;
        const period = { period_start: new Date(m.current_period_end).toISOString(), period_end: addMonths(new Date(m.current_period_end), 1).toISOString() };
        const created = await insertInvoice({ membership_id: m.id, customer_id: m.customer_id, period, amount_cents: feePlan.monthly_fee_cents, due_at: period.period_start, idempotency_key: renewalInvoiceKey(m.id, period.period_start) });
        invoice = created.invoice;
        invoices.push(invoice);
        if (created.created) {
          result.invoices_created++;
          await notify({
            recipientId: m.customer_id,
            templateKey: 'membership_renewal_due',
            vars: { plan: feePlan.name, amount: formatFee(invoice.amount_cents), period_end: formatDateSA(m.current_period_end), membership_id: m.id, invoice_id: invoice.id },
            dedupeKey: `membership_renewal_due:${invoice.id}`,
            payload: { type: 'membership', membership_id: m.id, invoice_id: invoice.id },
          });
        }
      }

      // 4. sandbox card auto-charge once the invoice is due
      if (invoice && invoice.status === 'pending' && sandbox && m.payment_method === 'card' && new Date(invoice.due_at).getTime() <= now.getTime()) {
        const counterMember = paymentsAll.filter((p) => invoices.some((i) => i.id === p.membership_invoice_id) && p.status === 'successful').sort((a, b) => String(b.created_at).localeCompare(String(a.created_at)))[0]?.provider === POS_PROVIDER;
        if (!counterMember) {
          const intent = await createInvoiceIntent(invoice);
          const outcome = await sandboxConfirm(intent.payment, 'succeeded');
          if (outcome.payment?.status === 'successful') {
            result.auto_charged++;
            continue;
          }
        }
      }

      // 3. past due
      if (ended && m.status === 'active' && (!invoice || invoice.status === 'pending')) {
        await db.from('memberships').update({ status: 'past_due' }).eq('id', m.id);
        result.past_due++;
        await notify({
          recipientId: m.customer_id,
          templateKey: 'membership_past_due',
          vars: { plan: plan.name, amount: formatFee(invoice?.amount_cents ?? plan.monthly_fee_cents), period_end: formatDateSA(m.current_period_end), membership_id: m.id, invoice_id: invoice?.id ?? null },
          dedupeKey: `membership_past_due:${m.id}:${invoice?.id ?? m.current_period_end}`,
          payload: { type: 'membership', membership_id: m.id, invoice_id: invoice?.id ?? null },
        });
      }
    } catch (err) {
      logger.error({ err, membership_id: m.id }, 'membership renewal step failed');
      result.errors.push({ membership_id: m.id, message: (err as Error).message });
    }
  }
  return result;
}

// ---------------------------------------------------------------------------
// Admin: plans (full replace by code) and members list
// ---------------------------------------------------------------------------

export interface PlanUpsertInput {
  name: string;
  tagline?: string | null;
  monthly_fee_cents: number;
  discount_pct: number;
  discount_scope: MembershipPlan['discount_scope'];
  discount_note?: string | null;
  is_active?: boolean;
  color?: string | null;
  sort_order?: number;
  groups: Array<{ code: string; name: string; selection: MembershipGroup['selection']; sort_order?: number; entitlements: Array<{ code: string; label: string; quantity: number; period: MembershipEntitlement['period']; sort_order?: number; service_codes: string[] }> }>;
}

/**
 * Replaces a plan's groups/entitlements by code. Ids are kept when the code
 * already exists (usage rows stay valid); an entitlement with usage cannot be
 * removed (409) — deactivate it by leaving it out of new memberships instead.
 * Fee changes apply from the next invoice.
 */
export async function updatePlan(ctx: RequestContext, code: string, input: PlanUpsertInput): Promise<MembershipPlan> {
  const db = getSupabase();
  const existing = await getPlanByCode(code, { includeInactive: true });
  const wantedCodes = [...new Set(input.groups.flatMap((g) => g.entitlements.flatMap((e) => e.service_codes)))];
  const serviceRows = wantedCodes.length ? unwrap<ServiceRow[]>(await db.from('services').select('id, code, name').in('code', wantedCodes), 'services') : [];
  const serviceByCode = new Map(serviceRows.map((s) => [s.code, s]));
  const missing = wantedCodes.filter((c) => !serviceByCode.has(c));
  if (missing.length) throw ApiError.validation('Unknown service codes', missing.map((c) => ({ path: 'groups.entitlements.service_codes', message: `service ${c} not found` })));
  const groupCodes = input.groups.map((g) => g.code);
  if (new Set(groupCodes).size !== groupCodes.length) throw ApiError.validation('Group codes must be unique');

  // Refuse to drop entitlements with usage.
  const keptEnt = new Set(input.groups.flatMap((g) => g.entitlements.map((e) => `${g.code}:${e.code}`)));
  const dropped = existing.groups.flatMap((g) => g.entitlements.filter((e) => !keptEnt.has(`${g.code}:${e.code}`)));
  if (dropped.length) {
    const used = unwrap<Array<{ entitlement_id: string }>>(await db.from('membership_usage').select('entitlement_id').in('entitlement_id', dropped.map((e) => e.id)).limit(1), 'usage');
    if (used.length) {
      const e = dropped.find((x) => x.id === used[0].entitlement_id);
      throw ApiError.conflict(`Entitlement ${e?.code ?? used[0].entitlement_id} has usage and cannot be removed`, { entitlement_id: used[0].entitlement_id });
    }
  }

  await db
    .from('membership_plans')
    .update({ name: input.name, tagline: input.tagline ?? null, monthly_fee_cents: input.monthly_fee_cents, discount_pct: input.discount_pct, discount_scope: input.discount_scope, discount_note: input.discount_note ?? null, is_active: input.is_active ?? existing.is_active, color: input.color === undefined ? existing.color : input.color, sort_order: input.sort_order ?? existing.sort_order })
    .eq('id', existing.id);

  const keepGroupIds: string[] = [];
  for (const [gi, g] of input.groups.entries()) {
    const prevGroup = existing.groups.find((x) => x.code === g.code);
    let groupId: string;
    if (prevGroup) {
      groupId = prevGroup.id;
      await db.from('membership_plan_groups').update({ name: g.name, selection: g.selection, sort_order: g.sort_order ?? (gi + 1) * 10 }).eq('id', groupId);
    } else {
      const row = unwrap<{ id: string }>(await db.from('membership_plan_groups').insert({ plan_id: existing.id, code: g.code, name: g.name, selection: g.selection, sort_order: g.sort_order ?? (gi + 1) * 10 }).select('id').single(), 'plan group');
      groupId = row.id;
    }
    keepGroupIds.push(groupId);
    const keepEntIds: string[] = [];
    for (const [ei, e] of g.entitlements.entries()) {
      const prevEnt = prevGroup?.entitlements.find((x) => x.code === e.code);
      let entId: string;
      if (prevEnt) {
        entId = prevEnt.id;
        await db.from('membership_plan_entitlements').update({ label: e.label, quantity: e.quantity, period: e.period, sort_order: e.sort_order ?? (ei + 1) * 10 }).eq('id', entId);
      } else {
        const row = unwrap<{ id: string }>(await db.from('membership_plan_entitlements').insert({ group_id: groupId, code: e.code, label: e.label, quantity: e.quantity, period: e.period, sort_order: e.sort_order ?? (ei + 1) * 10 }).select('id').single(), 'plan entitlement');
        entId = row.id;
      }
      keepEntIds.push(entId);
      await db.from('membership_entitlement_services').delete().eq('entitlement_id', entId);
      const rows = e.service_codes.map((c, i) => ({ entitlement_id: entId, service_id: serviceByCode.get(c)!.id, is_primary: i === 0 }));
      if (rows.length) {
        const ins = await db.from('membership_entitlement_services').insert(rows);
        if (ins.error) throw new DatabaseError(ins.error, 'entitlement services');
      }
    }
    if (prevGroup) {
      for (const stale of prevGroup.entitlements.filter((x) => !keepEntIds.includes(x.id))) {
        await db.from('membership_entitlement_services').delete().eq('entitlement_id', stale.id);
        await db.from('membership_plan_entitlements').delete().eq('id', stale.id);
      }
    }
  }
  for (const stale of existing.groups.filter((g) => !keepGroupIds.includes(g.id))) {
    for (const e of stale.entitlements) {
      await db.from('membership_entitlement_services').delete().eq('entitlement_id', e.id);
      await db.from('membership_plan_entitlements').delete().eq('id', e.id);
    }
    await db.from('membership_selections').delete().eq('group_id', stale.id);
    await db.from('membership_plan_groups').delete().eq('id', stale.id);
  }
  const updated = await getPlanByCode(code, { includeInactive: true });
  await audit(ctx, { action: 'membership_plan.update', entity_type: 'membership_plan', entity_id: existing.id, before: { monthly_fee_cents: existing.monthly_fee_cents, discount_pct: existing.discount_pct, discount_scope: existing.discount_scope, groups: existing.groups.map((g) => `${g.code}:${g.entitlements.map((e) => e.code).join('|')}`) }, after: { monthly_fee_cents: updated.monthly_fee_cents, discount_pct: updated.discount_pct, discount_scope: updated.discount_scope, is_active: updated.is_active, groups: updated.groups.map((g) => `${g.code}:${g.entitlements.map((e) => e.code).join('|')}`) } });
  return updated;
}

export interface PlanStats {
  member_count: number;
  mrr_cents: number;
}

/** Members (active/past_due) and monthly recurring revenue per plan id. */
export async function planStats(): Promise<Map<string, PlanStats>> {
  const db = getSupabase();
  const [plansRes, membersRes] = await Promise.all([db.from('membership_plans').select('id, monthly_fee_cents'), db.from('memberships').select('id, plan_id, status').in('status', ['active', 'past_due'])]);
  const fee = new Map(unwrap<Array<{ id: string; monthly_fee_cents: number }>>(plansRes, 'plans').map((p) => [p.id, Number(p.monthly_fee_cents)]));
  const out = new Map<string, PlanStats>();
  for (const id of fee.keys()) out.set(id, { member_count: 0, mrr_cents: 0 });
  for (const m of unwrap<Array<{ plan_id: string; status: MembershipStatus }>>(membersRes, 'memberships')) {
    const s = out.get(m.plan_id) ?? { member_count: 0, mrr_cents: 0 };
    s.member_count++;
    if (m.status === 'active') s.mrr_cents += fee.get(m.plan_id) ?? 0;
    out.set(m.plan_id, s);
  }
  return out;
}

export interface MemberRow {
  membership: Membership;
  customer: { id: string; full_name: string; phone: string | null; email: string | null } | null;
  plan: { id: string; code: string; name: string; tier: LoyaltyTier; monthly_fee_cents: number };
  next_plan: { id: string; code: string; name: string } | null;
  allowances: Allowance[];
  open_invoice: MembershipInvoice | null;
}

export interface MembersFilter {
  status?: MembershipStatus[];
  planCode?: string;
  q?: string;
}

/** Admin members list (newest first); `q` matches the member name / phone / membership ref. */
export async function listMembers(filter: MembersFilter, now = new Date()): Promise<MemberRow[]> {
  const db = getSupabase();
  const plans = await loadPlans({ includeInactive: true });
  const planById = new Map(plans.map((p) => [p.id, p]));
  let query = db.from('memberships').select('*');
  if (filter.status?.length) query = query.in('status', filter.status);
  if (filter.planCode) {
    const plan = plans.find((p) => p.code === filter.planCode);
    if (!plan) return [];
    query = query.eq('plan_id', plan.id);
  }
  let rows = unwrap<Membership[]>(await query, 'memberships').sort((a, b) => String(b.created_at).localeCompare(String(a.created_at)));
  if (rows.length === 0) return [];
  const customerIds = [...new Set(rows.map((r) => r.customer_id))];
  const profiles = unwrap<Array<{ id: string; full_name: string; phone: string | null; email: string | null }>>(await db.from('profiles').select('id, full_name, phone, email').in('id', customerIds), 'profiles');
  const byId = new Map(profiles.map((p) => [p.id, p]));
  if (filter.q) {
    const needle = filter.q.trim().toLowerCase();
    const digits = needle.replace(/\D/g, '');
    rows = rows.filter((m) => {
      const p = byId.get(m.customer_id);
      return m.ref.toLowerCase().includes(needle) || (p?.full_name ?? '').toLowerCase().includes(needle) || (digits.length >= 4 && (p?.phone ?? '').replace(/\D/g, '').includes(digits)) || (p?.email ?? '').toLowerCase().includes(needle);
    });
  }
  const ctxs = await loadContexts(rows, plans, now);
  const invoices = unwrap<MembershipInvoice[]>(await db.from('membership_invoices').select('*').in('membership_id', rows.map((r) => r.id)).eq('status', 'pending'), 'invoices');
  return rows.map((m) => {
    const plan = planById.get(m.plan_id)!;
    const next = m.next_plan_id ? planById.get(m.next_plan_id) : undefined;
    const p = byId.get(m.customer_id);
    return {
      membership: m,
      customer: p ? { id: p.id, full_name: p.full_name, phone: p.phone ?? null, email: p.email ?? null } : null,
      plan: { id: plan.id, code: plan.code, name: plan.name, tier: plan.tier, monthly_fee_cents: plan.monthly_fee_cents },
      next_plan: next ? { id: next.id, code: next.code, name: next.name } : null,
      allowances: ctxs.get(m.id)?.allowances ?? [],
      open_invoice: invoices.filter((i) => i.membership_id === m.id).sort((a, b) => String(a.due_at).localeCompare(String(b.due_at)))[0] ?? null,
    };
  });
}
