/**
 * Membership demo data mirroring migration 0010 + backend/supabase/seed_memberships.sql
 * (docs/MEMBERSHIPS.md). Plans, groups and entitlements use the stable ids from the
 * migration; entitlement services are resolved against the demo catalogue by code.
 */
import type { DiscountScope, EntitlementPeriod, GroupSelection, LoyaltyTier, Membership, MembershipInvoice, MembershipPaymentMethod, Payment } from '../types';
import { CATALOGUE_SERVICES } from './catalogue';

/* ---------- stable ids ---------- */
export const PLAN_GOLD = 'c1000000-0000-4000-8000-000000000001';
export const PLAN_PLATINUM = 'c1000000-0000-4000-8000-000000000002';
export const PLAN_BLACK = 'c1000000-0000-4000-8000-000000000003';
const GRP = (n: number) => `c2000000-0000-4000-8000-00000000000${n}`;
const ENT = (n: number) => `c3000000-0000-4000-8000-00000000000${n}`;
const MEM = (n: number) => `c4000000-0000-4000-8000-00000000000${n}`;
const INV = (n: number) => `c5000000-0000-4000-8000-00000000000${n}`;
const PAY = (n: number) => `60000000-0000-4000-8000-000000000${String(n).padStart(3, '0')}`;

/** Raw plan rows (`membership_plans`). */
export interface RawPlan {
  id: string;
  code: string;
  tier: LoyaltyTier;
  name: string;
  tagline: string | null;
  monthly_fee_cents: number;
  discount_pct: number;
  discount_scope: DiscountScope;
  discount_note: string | null;
  color: string | null;
  sort_order: number;
  is_active: boolean;
}
/** `membership_plan_groups`. */
export interface RawGroup {
  id: string;
  plan_id: string;
  code: string;
  name: string;
  selection: GroupSelection;
  sort_order: number;
}
/** `membership_plan_entitlements` + `membership_entitlement_services` (service codes, first = primary). */
export interface RawEntitlement {
  id: string;
  group_id: string;
  code: string;
  label: string;
  quantity: number;
  period: EntitlementPeriod;
  sort_order: number;
  service_codes: string[];
}
/** `membership_selections`. */
export interface RawSelection {
  membership_id: string;
  group_id: string;
  entitlement_id: string;
}
/** `membership_usage` (append-only; −1 rows release a cancelled booking). */
export interface RawUsage {
  id: string;
  membership_id: string;
  entitlement_id: string;
  booking_id: string | null;
  quantity: number;
  period_start: string;
  period_end: string;
  idempotency_key: string;
  created_at: string;
}

export const PLANS: RawPlan[] = [
  { id: PLAN_GOLD, code: 'gold', tier: 'gold', name: 'Gold', tagline: 'Monthly washes, 10 % off everything else', monthly_fee_cents: 29500, discount_pct: 10, discount_scope: 'other_services', discount_note: '10 % on any other Sparkling service', color: '#E2BA5F', sort_order: 10, is_active: true },
  { id: PLAN_PLATINUM, code: 'platinum', tier: 'platinum', name: 'Platinum', tagline: 'Double the washes, 10 % off your plan services', monthly_fee_cents: 47500, discount_pct: 10, discount_scope: 'plan_services', discount_note: '10 % on the selected plan services once the allowance is used', color: '#8BD2FF', sort_order: 20, is_active: true },
  { id: PLAN_BLACK, code: 'black', tier: 'black', name: 'Black', tagline: 'Washes, a monthly detail and a yearly ceramic coating', monthly_fee_cents: 85000, discount_pct: 10, discount_scope: 'plan_services', discount_note: '10 % on the selected plan services once the allowance is used', color: '#0B1220', sort_order: 30, is_active: true },
];

export const GROUPS: RawGroup[] = [
  { id: GRP(1), plan_id: PLAN_GOLD, code: 'washes', name: 'Washes', selection: 'choose_one', sort_order: 10 },
  { id: GRP(2), plan_id: PLAN_PLATINUM, code: 'washes', name: 'Washes', selection: 'choose_one', sort_order: 10 },
  { id: GRP(3), plan_id: PLAN_BLACK, code: 'washes', name: 'Washes', selection: 'choose_one', sort_order: 10 },
  { id: GRP(4), plan_id: PLAN_BLACK, code: 'detail', name: 'Detail', selection: 'choose_one', sort_order: 20 },
  { id: GRP(5), plan_id: PLAN_BLACK, code: 'coating', name: 'Coating', selection: 'all', sort_order: 30 },
];

const SPARKLING = ['SPARKLING_WASH'];
const EXTERIOR = ['EXT_WASH', 'EXT_WASH_TYRE', 'WASH_GO'];
export const ENTITLEMENTS: RawEntitlement[] = [
  { id: ENT(1), group_id: GRP(1), code: 'G1', label: '4 × Sparkling Wash', quantity: 4, period: 'month', sort_order: 10, service_codes: SPARKLING },
  { id: ENT(2), group_id: GRP(1), code: 'G2', label: '8 × Exterior Wash', quantity: 8, period: 'month', sort_order: 20, service_codes: EXTERIOR },
  { id: ENT(3), group_id: GRP(2), code: 'P1', label: '8 × Sparkling Wash', quantity: 8, period: 'month', sort_order: 10, service_codes: SPARKLING },
  { id: ENT(4), group_id: GRP(2), code: 'P2', label: '16 × Exterior Wash', quantity: 16, period: 'month', sort_order: 20, service_codes: EXTERIOR },
  { id: ENT(5), group_id: GRP(3), code: 'B1', label: '10 × Sparkling Wash', quantity: 10, period: 'month', sort_order: 10, service_codes: SPARKLING },
  { id: ENT(6), group_id: GRP(3), code: 'B2', label: '20 × Exterior Wash', quantity: 20, period: 'month', sort_order: 20, service_codes: EXTERIOR },
  { id: ENT(7), group_id: GRP(4), code: 'B3', label: '1 × Auto Detail Complete', quantity: 1, period: 'month', sort_order: 10, service_codes: ['AUTO_DETAIL_COMPLETE'] },
  { id: ENT(8), group_id: GRP(4), code: 'B4', label: '1 × Engine Steam Clean', quantity: 1, period: 'month', sort_order: 20, service_codes: ['ENGINE_STEAM'] },
  { id: ENT(9), group_id: GRP(5), code: 'B5', label: '1 × Ceramic coating / year', quantity: 1, period: 'year', sort_order: 10, service_codes: ['CERAMIC_COATING'] },
];

/** Service id ↔ code lookups against the demo catalogue. */
export const serviceByCode = (code: string) => CATALOGUE_SERVICES.find((s) => s.code === code);

/* ---------- time helpers (relative to now, like seed_memberships.sql) ---------- */
const dayMs = 24 * 60 * 60_000;
const daysFromNow = (d: number) => new Date(Date.now() + d * dayMs);
/** `start + 1 calendar month` (Postgres `interval '1 month'` semantics). */
export function addMonths(iso: string | Date, n: number): string {
  const d = new Date(iso);
  const day = d.getDate();
  d.setMonth(d.getMonth() + n);
  if (d.getDate() !== day) d.setDate(0); // clamp (31 Jan + 1 month → 28/29 Feb)
  return d.toISOString();
}
export function addYears(iso: string | Date, n: number): string {
  const d = new Date(iso);
  d.setFullYear(d.getFullYear() + n);
  return d.toISOString();
}

const mem = (n: number, ref: string, customer_id: string, plan_id: string, startedDaysAgo: number, periodStartDaysAgo: number, payment_method: MembershipPaymentMethod, created_by: string, periodEnd?: string): Membership => {
  const start = daysFromNow(-periodStartDaysAgo).toISOString();
  return {
    id: MEM(n), ref, customer_id, plan_id, status: 'active', started_at: daysFromNow(-startedDaysAgo).toISOString(),
    current_period_start: start, current_period_end: periodEnd ?? addMonths(start, 1), cancel_at_period_end: false, cancelled_at: null, ended_at: null, next_plan_id: null,
    payment_method, created_by, created_at: daysFromNow(-startedDaysAgo).toISOString(),
  };
};

/** Thabo Gold/G1 (1 of 4) · Naledi Gold/G2 (2 of 8, cash) · Sipho Platinum/P1 (3 of 8) · Zanele Black/B1+B3+B5 (2 washes + detail, renewal in 3 days). */
export const MEMBERSHIPS: Membership[] = [
  mem(1, 'MEM-2026-0001', 'seed_thabo', PLAN_GOLD, 95, 5, 'card', 'seed_thabo'),
  mem(2, 'MEM-2026-0002', 'seed_naledi', PLAN_GOLD, 60, 12, 'cash', 'seed_johan'),
  mem(3, 'MEM-2026-0003', 'seed_sipho', PLAN_PLATINUM, 150, 20, 'card', 'seed_sipho'),
  mem(4, 'MEM-2026-0004', 'seed_zanele', PLAN_BLACK, 27, 27, 'card', 'seed_zanele', daysFromNow(3).toISOString()),
];

export const SELECTIONS: RawSelection[] = [
  { membership_id: MEM(1), group_id: GRP(1), entitlement_id: ENT(1) },
  { membership_id: MEM(2), group_id: GRP(1), entitlement_id: ENT(2) },
  { membership_id: MEM(3), group_id: GRP(2), entitlement_id: ENT(3) },
  { membership_id: MEM(4), group_id: GRP(3), entitlement_id: ENT(5) },
  { membership_id: MEM(4), group_id: GRP(4), entitlement_id: ENT(7) },
];

const m = (n: number) => MEMBERSHIPS[n - 1];
const usageRow = (mn: number, ent: string, key: string, offsetDays: number, booking_id: string | null = null): RawUsage => {
  const ms = m(mn);
  return { id: `mu-${key}`, membership_id: ms.id, entitlement_id: ent, booking_id, quantity: 1, period_start: ms.current_period_start, period_end: ms.current_period_end, idempotency_key: key, created_at: new Date(new Date(ms.current_period_start).getTime() + offsetDays * dayMs).toISOString() };
};
/** Usage this period. Thabo's wash is today's in-service SPK-2026-0091; Zanele's detail is today's SPK-2026-0095. */
export const USAGE: RawUsage[] = [
  usageRow(1, ENT(1), 'booking:10000000-0000-4000-8000-000000000001:membership', 5, '10000000-0000-4000-8000-000000000001'),
  usageRow(2, ENT(2), 'seed-use-naledi-1', 3),
  usageRow(2, ENT(2), 'seed-use-naledi-2', 9),
  usageRow(3, ENT(3), 'seed-use-sipho-1', 4),
  usageRow(3, ENT(3), 'seed-use-sipho-2', 11),
  usageRow(3, ENT(3), 'seed-use-sipho-3', 17),
  usageRow(4, ENT(5), 'seed-use-zanele-1', 6),
  usageRow(4, ENT(5), 'seed-use-zanele-2', 20),
  usageRow(4, ENT(7), 'booking:10000000-0000-4000-8000-000000000007:membership', 27, '10000000-0000-4000-8000-000000000007'),
];

const planFee = (id: string) => PLANS.find((p) => p.id === id)!.monthly_fee_cents;
const inv = (n: number, mn: number, ref: string): MembershipInvoice => {
  const ms = m(mn);
  return { id: INV(n), ref, membership_id: ms.id, customer_id: ms.customer_id, period_start: ms.current_period_start, period_end: ms.current_period_end, amount_cents: planFee(ms.plan_id), status: 'paid', due_at: ms.current_period_start, paid_at: ms.current_period_start, payment_id: PAY(100 + n) };
};
/** Current-period invoices, all paid (Zanele's renewal invoice is created by the renewal job 3 days before period end). */
export const MEMBERSHIP_INVOICES: MembershipInvoice[] = [inv(1, 1, 'MINV-2026-0101'), inv(2, 2, 'MINV-2026-0102'), inv(3, 3, 'MINV-2026-0103'), inv(4, 4, 'MINV-2026-0104')];

const customerName: Record<string, string> = { seed_thabo: 'Thabo Nkosi', seed_naledi: 'Naledi Mokoena', seed_sipho: 'Sipho Dlamini', seed_zanele: 'Zanele Mthembu' };
/** `payments` rows for the invoices above (`booking_ref` null, `membership_invoice_id` set). */
export const MEMBERSHIP_PAYMENTS: Payment[] = MEMBERSHIP_INVOICES.map((i, idx) => {
  const ms = MEMBERSHIPS.find((x) => x.id === i.membership_id)!;
  return { id: PAY(101 + idx), booking_ref: null, membership_invoice_id: i.id, customer_name: customerName[i.customer_id] ?? i.customer_id, provider: ms.payment_method === 'card' ? 'sandbox' : 'pos', amount_cents: i.amount_cents, status: 'successful', receipt_no: `RCP-${70101 + idx}`, verified_at: i.paid_at, created_at: i.paid_at! };
});
