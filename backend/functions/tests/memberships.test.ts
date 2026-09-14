/**
 * Membership plans (docs/MEMBERSHIPS.md): pricing rules per plan/scope, usage
 * ledger idempotency, subscribe → activation on payment success, counter
 * enrolment (+ sync batch), selection/plan changes, cancellation, the daily
 * renewals job and route authorisation.
 */
import { createServer, type Server } from 'node:http';
import { afterAll, afterEach, beforeAll, beforeEach, describe, expect, it, vi } from 'vitest';
import { createApp } from '../src/app.js';
import { setFirebaseAuthForTests, setFirebaseMessagingForTests } from '../src/lib/firebase.js';
import { setSupabaseClient } from '../src/lib/supabase.js';
import { resetRateLimits } from '../src/middleware/rateLimit.js';
import { invalidateFlags } from '../src/services/flags.js';
import { addMonths, annualPeriod, benefitFor, loadContext, membershipSummary, renewalInvoiceKey, runRenewals } from '../src/services/memberships.js';
import { SandboxProvider, setPaymentProviderForTests } from '../src/services/payments.js';
import { computePrice, priceService } from '../src/services/pricing.js';
import { raiseQuotation } from '../src/services/quotations.js';
import { makeCtx } from './helpers/context.js';
import { fakeSupabase, type FakeSupabase } from './helpers/fakeSupabase.js';

const NOW = '2026-09-14T10:00:00.000Z';
const OUTLET = 'a0000000-0000-4000-8000-000000000001';
const S_WASH = 'b0000000-0000-4000-8000-000000000001';
const S_EXT = 'b0000000-0000-4000-8000-000000000002';
const S_VALET = 'b0000000-0000-4000-8000-000000000003';
const S_DETAIL = 'b0000000-0000-4000-8000-000000000004';
const S_STEAM = 'b0000000-0000-4000-8000-000000000005';
const S_COAT = 'b0000000-0000-4000-8000-000000000006';
const S_TYRE = 'b0000000-0000-4000-8000-000000000007';
const PLAN_GOLD = 'c1000000-0000-4000-8000-000000000001';
const PLAN_PLAT = 'c1000000-0000-4000-8000-000000000002';
const PLAN_BLACK = 'c1000000-0000-4000-8000-000000000003';
const G_GOLD = 'c2000000-0000-4000-8000-000000000001';
const G_PLAT = 'c2000000-0000-4000-8000-000000000002';
const G_BLACK_W = 'c2000000-0000-4000-8000-000000000003';
const G_BLACK_D = 'c2000000-0000-4000-8000-000000000004';
const G_BLACK_C = 'c2000000-0000-4000-8000-000000000005';
const E = (n: number) => `c3000000-0000-4000-8000-00000000000${n}`; // G1..B5 = 1..9
const M_GOLD = 'c4000000-0000-4000-8000-000000000001';
const M_GOLD_X = 'c4000000-0000-4000-8000-000000000002';
const M_PLAT = 'c4000000-0000-4000-8000-000000000003';
const M_BLACK = 'c4000000-0000-4000-8000-000000000004';
const M_PASTDUE = 'c4000000-0000-4000-8000-000000000005';
const M_CASH = 'c4000000-0000-4000-8000-000000000006';
const M_STALE = 'c4000000-0000-4000-8000-000000000007';
const M_ENDING = 'c4000000-0000-4000-8000-000000000008';
const INV_CASH_NEXT = 'c5000000-0000-4000-8000-000000000201';
const INV_PASTDUE = 'c5000000-0000-4000-8000-000000000202';
const VEH_GOLD = '20000000-0000-4000-8000-000000000001';
const VEH_GOLD_LARGE = '20000000-0000-4000-8000-000000000002';
const VEH_NONE = '20000000-0000-4000-8000-000000000003';
const VEH_BLACK = '20000000-0000-4000-8000-000000000004';
const SAST_OFFSET_MS = 2 * 60 * 60_000;

let db: FakeSupabase;
let server: Server;
let base: string;
let receiptSeq = 70000;

/** Mirrors `public.get_available_slots` for the fake: 07:00–18:00 SAST, `slot_minutes` grid. */
function slotsRpc(args: Record<string, unknown>) {
  const outlet = db.rows('outlets').find((o) => o.id === args.p_outlet);
  const service = db.rows('services').find((s) => s.id === args.p_service);
  if (!outlet || !service) return [];
  const dayStart = new Date(`${args.p_date}T00:00:00.000Z`).getTime() - SAST_OFFSET_MS;
  const open = dayStart + 7 * 60 * 60_000;
  const close = dayStart + 18 * 60 * 60_000;
  const dur = service.duration_minutes * 60_000;
  const out: unknown[] = [];
  for (let cursor = open; cursor + dur <= close; cursor += outlet.slot_minutes * 60_000) {
    const booked = db.rows('bookings').filter((b) => b.outlet_id === outlet.id && ['pending', 'confirmed', 'in_service'].includes(b.status) && new Date(b.slot_start).getTime() < cursor + dur && new Date(b.slot_end).getTime() > cursor).length;
    out.push({ slot_start: new Date(cursor).toISOString(), slot_end: new Date(cursor + dur).toISOString(), capacity: outlet.bay_count, booked, available: booked < outlet.bay_count && cursor > Date.now() });
  }
  return out;
}

const service = (id: string, code: string, name: string, small: number | null, large: number | null, extra: Record<string, unknown> = {}) => ({
  id, code, name, category: 'car_wash', duration_minutes: 30, base_price_cents: small ?? 0, is_quote_based: false, points_per_rand: 0.1, is_active: true, group_name: 'Car Wash Options', pricing_mode: 'fixed', vat_mode: 'incl', price_small_cents: small, price_large_cents: large, price_general_cents: null, is_addon: false, addon_group_name: null, sort_order: 10, ...extra,
});
const profile = (id: string, full_name: string, extra: Record<string, unknown> = {}) => ({ id, role: 'customer', full_name, email: `${id}@example.com`, phone: '+27831112222', is_active: true, push_opt_in: true, whatsapp_opt_in: false, marketing_opt_in: false, ...extra });
const iso = (s: string) => new Date(s).toISOString();

beforeAll(async () => {
  server = createServer(createApp());
  await new Promise<void>((r) => server.listen(0, r));
  base = `http://127.0.0.1:${(server.address() as { port: number }).port}`;
  setFirebaseAuthForTests({
    verifyIdToken: async (token: string) => {
      const users: Record<string, string> = { gold: 'cust_gold', goldx: 'cust_gold_x', plat: 'cust_plat', black: 'cust_black', pastdue: 'cust_pastdue', cash: 'cust_cash', none: 'cust_none', tech: 'tech_1', other: 'tech_other', admin: 'uid_admin', manager: 'uid_manager', finance: 'uid_finance' };
      if (users[token]) return { uid: users[token], email: `${users[token]}@example.com` };
      throw new Error('bad token');
    },
    setCustomUserClaims: async () => undefined,
  } as any);
  setFirebaseMessagingForTests({ sendEachForMulticast: async ({ tokens }: { tokens: string[] }) => ({ successCount: tokens.length, failureCount: 0, responses: tokens.map(() => ({ success: true })) }) } as any);
  setPaymentProviderForTests(new SandboxProvider('s3cret'));
});
afterAll(() => server.close());

beforeEach(() => {
  vi.useFakeTimers({ now: new Date(NOW), toFake: ['Date'] });
  receiptSeq = 70000;
  db = fakeSupabase({ rpc: { get_available_slots: slotsRpc, next_receipt_no: () => `RCP-${++receiptSeq}` } });
  db.seed('feature_flags', [{ key: 'auto_assignment', enabled: false }, { key: 'whatsapp_enabled', enabled: false }, { key: 'payments_sandbox', enabled: true }]);
  db.seed('profiles', [
    profile('cust_gold', 'Thabo Nkosi'),
    profile('cust_gold_x', 'Gugu Exhausted'),
    profile('cust_plat', 'Sipho Dlamini'),
    profile('cust_black', 'Zanele Khumalo'),
    profile('cust_pastdue', 'Naledi Late'),
    profile('cust_cash', 'Naledi Mokoena'),
    profile('cust_stale', 'Old Member'),
    profile('cust_ending', 'Leaving Member'),
    profile('cust_none', 'Lerato New'),
    { id: 'tech_1', role: 'technician', full_name: 'Pieter', is_active: true, push_opt_in: true, whatsapp_opt_in: false, marketing_opt_in: false },
    { id: 'tech_other', role: 'technician', full_name: 'Elsewhere', is_active: true, push_opt_in: true, whatsapp_opt_in: false, marketing_opt_in: false },
    { id: 'uid_admin', role: 'admin', full_name: 'Ada Admin', is_active: true, push_opt_in: true, whatsapp_opt_in: false, marketing_opt_in: false },
    { id: 'uid_manager', role: 'manager', full_name: 'Musa Manager', is_active: true, push_opt_in: true, whatsapp_opt_in: false, marketing_opt_in: false },
    { id: 'uid_finance', role: 'finance', full_name: 'Fikile Finance', is_active: true, push_opt_in: true, whatsapp_opt_in: false, marketing_opt_in: false },
  ]);
  db.seed('staff_outlets', [{ profile_id: 'tech_1', outlet_id: OUTLET }, { profile_id: 'uid_manager', outlet_id: OUTLET }, { profile_id: 'tech_other', outlet_id: 'a0000000-0000-4000-8000-000000000002' }]);
  db.seed('outlets', [{ id: OUTLET, code: 'SAN', name: 'Sparkling Sandton', timezone: 'Africa/Johannesburg', slot_minutes: 15, bay_count: 4, is_active: true }]);
  db.seed('services', [
    service(S_WASH, 'SPARKLING_WASH', 'Sparkling Wash', 15000, 20000),
    service(S_EXT, 'EXT_WASH', 'Exterior Wash', 8000, 10000),
    service(S_VALET, 'FULL_VALET', 'Full Valet', 22000, 26000, { group_name: 'Combinations' }),
    service(S_DETAIL, 'AUTO_DETAIL_COMPLETE', 'Auto Detail Complete', 45000, 55000, { group_name: 'Combinations' }),
    service(S_STEAM, 'ENGINE_STEAM', 'Engine Steam Clean', 35000, 35000),
    service(S_COAT, 'CERAMIC_COATING', 'Ceramic coating', null, null, { category: 'auto_body', group_name: 'Auto Body Repair', pricing_mode: 'by_quote', is_quote_based: true }),
    service(S_TYRE, 'TYRE_SHINE', 'Tyre shine', 3000, 3000, { is_addon: true, addon_group_name: 'Car Wash Options' }),
  ]);
  db.seed('outlet_services', [S_WASH, S_EXT, S_VALET, S_DETAIL, S_STEAM, S_COAT, S_TYRE].map((service_id) => ({ outlet_id: OUTLET, service_id, price_cents: null, is_available: true })));
  db.seed('loyalty_configs', [{ id: 'cfg1', version: 3, status: 'published', rules: { points_per_rand: 0.1 }, tiers: [
    { tier: 'silver', name: 'Silver', min_points: 0, max_points: 499, earn_multiplier: 1, discount_pct: 0 },
    { tier: 'gold', name: 'Gold', min_points: 500, max_points: 1999, earn_multiplier: 1.25, discount_pct: 0 },
    { tier: 'platinum', name: 'Platinum', min_points: 2000, max_points: 4999, earn_multiplier: 1.5, discount_pct: 0 },
    { tier: 'black', name: 'Black', min_points: 5000, max_points: null, earn_multiplier: 1.75, discount_pct: 0 },
  ] }]);
  db.seed('loyalty_accounts', [
    { customer_id: 'cust_gold', tier: 'gold', balance_points: 120, lifetime_points: 400 },
    { customer_id: 'cust_gold_x', tier: 'gold', balance_points: 0, lifetime_points: 0 },
    { customer_id: 'cust_plat', tier: 'platinum', balance_points: 50, lifetime_points: 50 },
    { customer_id: 'cust_black', tier: 'black', balance_points: 0, lifetime_points: 0 },
    { customer_id: 'cust_pastdue', tier: 'gold', balance_points: 0, lifetime_points: 0 },
    { customer_id: 'cust_cash', tier: 'gold', balance_points: 0, lifetime_points: 0 },
    { customer_id: 'cust_stale', tier: 'gold', balance_points: 0, lifetime_points: 0 },
    { customer_id: 'cust_ending', tier: 'gold', balance_points: 0, lifetime_points: 0 },
    { customer_id: 'cust_none', tier: 'silver', balance_points: 9000, lifetime_points: 9000 },
  ]);
  db.seed('vehicles', [
    { id: VEH_GOLD, customer_id: 'cust_gold', registration_no: 'HR 88 TS GP', size_class: 'small', source: 'manual', disc_verified: false, is_active: true },
    { id: VEH_GOLD_LARGE, customer_id: 'cust_gold', registration_no: 'BAKKIE GP', size_class: 'large', source: 'manual', disc_verified: false, is_active: true },
    { id: VEH_NONE, customer_id: 'cust_none', registration_no: 'NEW 1 GP', size_class: 'small', source: 'manual', disc_verified: false, is_active: true },
    { id: VEH_BLACK, customer_id: 'cust_black', registration_no: 'ZK 1 GP', size_class: 'small', source: 'manual', disc_verified: false, is_active: true },
  ]);

  // Plans as seeded by migration 0010.
  db.seed('membership_plans', [
    { id: PLAN_GOLD, code: 'gold', tier: 'gold', name: 'Gold', tagline: '4 Sparkling Washes or 8 Exterior Washes a month', monthly_fee_cents: 29500, discount_pct: '10.00', discount_scope: 'other_services', discount_note: '10% discount on any other Sparkling service', color: 'gold', sort_order: 10, is_active: true },
    { id: PLAN_PLAT, code: 'platinum', tier: 'platinum', name: 'Platinum', tagline: null, monthly_fee_cents: 47500, discount_pct: '10.00', discount_scope: 'plan_services', discount_note: '10% discount on the above selected services', color: 'platinum', sort_order: 20, is_active: true },
    { id: PLAN_BLACK, code: 'black', tier: 'black', name: 'Black', tagline: null, monthly_fee_cents: 85000, discount_pct: '10.00', discount_scope: 'plan_services', discount_note: '10% discount on the above selected services', color: 'black', sort_order: 30, is_active: true },
  ]);
  db.seed('membership_plan_groups', [
    { id: G_GOLD, plan_id: PLAN_GOLD, code: 'washes', name: 'Monthly washes', selection: 'choose_one', sort_order: 10 },
    { id: G_PLAT, plan_id: PLAN_PLAT, code: 'washes', name: 'Monthly washes', selection: 'choose_one', sort_order: 10 },
    { id: G_BLACK_W, plan_id: PLAN_BLACK, code: 'washes', name: 'Monthly washes', selection: 'choose_one', sort_order: 10 },
    { id: G_BLACK_D, plan_id: PLAN_BLACK, code: 'detail', name: 'Monthly detail', selection: 'choose_one', sort_order: 20 },
    { id: G_BLACK_C, plan_id: PLAN_BLACK, code: 'coating', name: 'Annual ceramic coating', selection: 'all', sort_order: 30 },
  ]);
  db.seed('membership_plan_entitlements', [
    { id: E(1), group_id: G_GOLD, code: 'G1', label: '4 × Sparkling Wash', quantity: 4, period: 'month', sort_order: 10 },
    { id: E(2), group_id: G_GOLD, code: 'G2', label: '8 × Exterior Wash', quantity: 8, period: 'month', sort_order: 20 },
    { id: E(3), group_id: G_PLAT, code: 'P1', label: '8 × Sparkling Wash', quantity: 8, period: 'month', sort_order: 10 },
    { id: E(4), group_id: G_PLAT, code: 'P2', label: '16 × Exterior Wash', quantity: 16, period: 'month', sort_order: 20 },
    { id: E(5), group_id: G_BLACK_W, code: 'B1', label: '10 × Sparkling Wash per month', quantity: 10, period: 'month', sort_order: 10 },
    { id: E(6), group_id: G_BLACK_W, code: 'B2', label: '20 × Exterior Wash', quantity: 20, period: 'month', sort_order: 20 },
    { id: E(7), group_id: G_BLACK_D, code: 'B3', label: '1 × Auto Detail Complete per month', quantity: 1, period: 'month', sort_order: 10 },
    { id: E(8), group_id: G_BLACK_D, code: 'B4', label: '1 × Engine Steam Clean per month', quantity: 1, period: 'month', sort_order: 20 },
    { id: E(9), group_id: G_BLACK_C, code: 'B5', label: '1 × Ceramic coating per annum', quantity: 1, period: 'year', sort_order: 10 },
  ]);
  db.seed('membership_entitlement_services', [
    { entitlement_id: E(1), service_id: S_WASH, is_primary: true },
    { entitlement_id: E(2), service_id: S_EXT, is_primary: true },
    { entitlement_id: E(3), service_id: S_WASH, is_primary: true },
    { entitlement_id: E(4), service_id: S_EXT, is_primary: true },
    { entitlement_id: E(5), service_id: S_WASH, is_primary: true },
    { entitlement_id: E(6), service_id: S_EXT, is_primary: true },
    { entitlement_id: E(7), service_id: S_DETAIL, is_primary: true },
    { entitlement_id: E(8), service_id: S_STEAM, is_primary: true },
    { entitlement_id: E(9), service_id: S_COAT, is_primary: true },
  ]);

  // Demo memberships (today = 14 Sep 2026).
  const m = (id: string, customer_id: string, plan_id: string, status: string, started: string, start: string, end: string, extra: Record<string, unknown> = {}) => ({
    id, ref: `MEM-${id.slice(-4)}`, customer_id, plan_id, status, started_at: iso(started), current_period_start: iso(start), current_period_end: iso(end), cancel_at_period_end: false, cancelled_at: null, ended_at: null, next_plan_id: null, payment_method: 'card', client_op_id: `seed-${id.slice(-4)}`, created_by: customer_id, created_at: iso(started), updated_at: iso(start), ...extra,
  });
  db.seed('memberships', [
    m(M_GOLD, 'cust_gold', PLAN_GOLD, 'active', '2026-06-10T09:00:00Z', '2026-09-10T09:00:00Z', '2026-10-10T09:00:00Z'),
    m(M_GOLD_X, 'cust_gold_x', PLAN_GOLD, 'active', '2026-06-10T09:00:00Z', '2026-09-10T09:00:00Z', '2026-10-10T09:00:00Z'),
    m(M_PLAT, 'cust_plat', PLAN_PLAT, 'active', '2026-04-20T09:00:00Z', '2026-08-20T09:00:00Z', '2026-09-20T09:00:00Z'),
    m(M_BLACK, 'cust_black', PLAN_BLACK, 'active', '2026-08-17T09:00:00Z', '2026-08-17T09:00:00Z', '2026-09-17T09:00:00Z'),
    m(M_PASTDUE, 'cust_pastdue', PLAN_GOLD, 'past_due', '2026-05-01T09:00:00Z', '2026-08-01T09:00:00Z', '2026-09-01T09:00:00Z', { payment_method: 'eft' }),
    m(M_CASH, 'cust_cash', PLAN_GOLD, 'active', '2026-07-10T09:00:00Z', '2026-08-10T09:00:00Z', '2026-09-10T09:00:00Z', { payment_method: 'cash', created_by: 'tech_1' }),
    m(M_STALE, 'cust_stale', PLAN_GOLD, 'past_due', '2026-05-01T09:00:00Z', '2026-07-01T09:00:00Z', '2026-08-01T09:00:00Z'),
    m(M_ENDING, 'cust_ending', PLAN_GOLD, 'active', '2026-05-12T09:00:00Z', '2026-08-12T09:00:00Z', '2026-09-12T09:00:00Z', { cancel_at_period_end: true, cancelled_at: iso('2026-08-20T09:00:00Z') }),
  ]);
  db.seed('membership_selections', [
    { membership_id: M_GOLD, group_id: G_GOLD, entitlement_id: E(1) },
    { membership_id: M_GOLD_X, group_id: G_GOLD, entitlement_id: E(1) },
    { membership_id: M_PLAT, group_id: G_PLAT, entitlement_id: E(3) },
    { membership_id: M_BLACK, group_id: G_BLACK_W, entitlement_id: E(5) },
    { membership_id: M_BLACK, group_id: G_BLACK_D, entitlement_id: E(7) },
    { membership_id: M_PASTDUE, group_id: G_GOLD, entitlement_id: E(1) },
    { membership_id: M_CASH, group_id: G_GOLD, entitlement_id: E(2) },
    { membership_id: M_STALE, group_id: G_GOLD, entitlement_id: E(1) },
    { membership_id: M_ENDING, group_id: G_GOLD, entitlement_id: E(1) },
  ]);
  const use = (membership_id: string, entitlement_id: string, key: string, start: string, end: string, quantity = 1) => ({ membership_id, entitlement_id, booking_id: null, quantity, period_start: iso(start), period_end: iso(end), idempotency_key: key, created_by: null });
  db.seed('membership_usage', [
    use(M_GOLD, E(1), 'seed-use-gold-1', '2026-09-10T09:00:00Z', '2026-10-10T09:00:00Z'),
    use(M_GOLD, E(1), 'seed-use-gold-old', '2026-08-10T09:00:00Z', '2026-09-10T09:00:00Z', 3), // previous period: must not count
    ...[1, 2, 3, 4].map((i) => use(M_GOLD_X, E(1), `seed-use-goldx-${i}`, '2026-09-10T09:00:00Z', '2026-10-10T09:00:00Z')),
    ...[1, 2, 3, 4, 5, 6, 7, 8].map((i) => use(M_PLAT, E(3), `seed-use-plat-${i}`, '2026-08-20T09:00:00Z', '2026-09-20T09:00:00Z')),
    use(M_BLACK, E(5), 'seed-use-black-1', '2026-08-17T09:00:00Z', '2026-09-17T09:00:00Z'),
    use(M_BLACK, E(5), 'seed-use-black-2', '2026-08-17T09:00:00Z', '2026-09-17T09:00:00Z'),
    use(M_BLACK, E(7), 'seed-use-black-3', '2026-08-17T09:00:00Z', '2026-09-17T09:00:00Z'),
  ]);
  const inv = (id: string, membership_id: string, customer_id: string, start: string, end: string, amount: number, status: string, key: string) => ({ id, ref: `MINV-${id.slice(-4)}`, membership_id, customer_id, period_start: iso(start), period_end: iso(end), amount_cents: amount, status, due_at: iso(start), paid_at: status === 'paid' ? iso(start) : null, payment_id: null, idempotency_key: key, created_at: iso(start) });
  db.seed('membership_invoices', [
    inv('c5000000-0000-4000-8000-000000000101', M_GOLD, 'cust_gold', '2026-09-10T09:00:00Z', '2026-10-10T09:00:00Z', 29500, 'paid', 'seed-minv-gold-cur'),
    inv('c5000000-0000-4000-8000-000000000103', M_PLAT, 'cust_plat', '2026-08-20T09:00:00Z', '2026-09-20T09:00:00Z', 47500, 'paid', 'seed-minv-plat-cur'),
    inv('c5000000-0000-4000-8000-000000000104', M_BLACK, 'cust_black', '2026-08-17T09:00:00Z', '2026-09-17T09:00:00Z', 85000, 'paid', 'seed-minv-black-cur'),
    inv(INV_PASTDUE, M_PASTDUE, 'cust_pastdue', '2026-09-01T09:00:00Z', '2026-10-01T09:00:00Z', 29500, 'pending', renewalInvoiceKey(M_PASTDUE, '2026-09-01T09:00:00Z')),
    inv(INV_CASH_NEXT, M_CASH, 'cust_cash', '2026-09-10T09:00:00Z', '2026-10-10T09:00:00Z', 29500, 'pending', renewalInvoiceKey(M_CASH, '2026-09-10T09:00:00Z')),
    inv('c5000000-0000-4000-8000-000000000203', M_STALE, 'cust_stale', '2026-08-01T09:00:00Z', '2026-09-01T09:00:00Z', 29500, 'pending', renewalInvoiceKey(M_STALE, '2026-08-01T09:00:00Z')),
  ]);
  db.seed('payments', [
    { id: '60000000-0000-4000-8000-000000000101', booking_id: null, membership_invoice_id: 'c5000000-0000-4000-8000-000000000101', customer_id: 'cust_gold', provider: 'sandbox', provider_ref: 'pi_sbx_mem_0101', amount_cents: 29500, currency: 'ZAR', status: 'successful', receipt_no: 'RCP-60101', idempotency_key: 'pay-seed-mem-0101', method: 'card', created_at: iso('2026-09-10T09:00:00Z') },
    { id: '60000000-0000-4000-8000-000000000104', booking_id: null, membership_invoice_id: 'c5000000-0000-4000-8000-000000000104', customer_id: 'cust_black', provider: 'sandbox', provider_ref: 'pi_sbx_mem_0104', amount_cents: 85000, currency: 'ZAR', status: 'successful', receipt_no: 'RCP-60104', idempotency_key: 'pay-seed-mem-0104', method: 'card', created_at: iso('2026-08-17T09:00:00Z') },
  ]);
  db.seed('notification_templates', [
    { key: 'membership_activated', channel: 'push', title: 'Welcome to Sparkling {{plan}}', body: 'Your {{plan}} membership is active until {{period_end}}. {{benefits}}', is_promotional: false, is_active: true },
    { key: 'membership_renewal_due', channel: 'push', title: '{{plan}} membership renewal', body: 'Your {{plan}} membership renews on {{period_end}} ({{amount}}).', is_promotional: false, is_active: true },
    { key: 'membership_renewed', channel: 'push', title: '{{plan}} membership renewed', body: 'Paid {{amount}}. Your washes have been reset for the month.', is_promotional: false, is_active: true },
    { key: 'membership_past_due', channel: 'push', title: 'Membership payment due', body: 'Your {{plan}} benefits are paused until {{amount}} is paid.', is_promotional: false, is_active: true },
    { key: 'membership_cancelled', channel: 'push', title: 'Membership cancelled', body: 'Your {{plan}} membership ends on {{period_end}}. You can rejoin any time.', is_promotional: false, is_active: true },
    { key: 'payment_successful', channel: 'push', title: 'Payment received', body: 'Paid {{amount}} — receipt {{receipt}}.', is_promotional: false, is_active: true },
  ]);
  setSupabaseClient(db as any);
  invalidateFlags();
  resetRateLimits();
});

afterEach(() => {
  vi.useRealTimers();
});

async function call(path: string, token: string, init: RequestInit = {}) {
  const res = await fetch(`${base}${path}`, { ...init, headers: { Authorization: `Bearer ${token}`, 'Content-Type': 'application/json', ...(init.headers ?? {}) } });
  const text = await res.text();
  let body: any = text;
  try { body = JSON.parse(text); } catch { /* keep text */ }
  return { status: res.status, body, headers: res.headers };
}
const post = (path: string, token: string, body: unknown = {}) => call(path, token, { method: 'POST', body: JSON.stringify(body) });
const put = (path: string, token: string, body: unknown) => call(path, token, { method: 'PUT', body: JSON.stringify(body) });
const audits = (action: string) => db.rows('audit_events').filter((a) => a.action === action);
const notes = (key: string) => db.rows('notifications').filter((n) => n.template_key === key);
const usage = (membershipId: string) => db.rows('membership_usage').filter((u) => u.membership_id === membershipId);
const tierOf = (customerId: string) => db.rows('loyalty_accounts').find((a) => a.customer_id === customerId)?.tier;
const selectionsOf = (membershipId: string) => db.rows('membership_selections').filter((s) => s.membership_id === membershipId).map(({ membership_id, group_id, entitlement_id }) => ({ membership_id, group_id, entitlement_id }));

// ---------------------------------------------------------------------------
// Period maths
// ---------------------------------------------------------------------------

describe('period maths', () => {
  it('adds calendar months with Postgres clamping and finds the membership year', () => {
    expect(addMonths(new Date('2026-01-31T09:00:00Z'), 1).toISOString()).toBe('2026-02-28T09:00:00.000Z');
    expect(addMonths(new Date('2026-08-17T09:00:00Z'), 1).toISOString()).toBe('2026-09-17T09:00:00.000Z');
    expect(addMonths(new Date('2026-12-15T09:00:00Z'), 1).toISOString()).toBe('2027-01-15T09:00:00.000Z');
    const started = new Date('2025-03-05T09:00:00Z');
    expect(annualPeriod(started, new Date('2026-09-14T08:00:00Z'))).toEqual({ period_start: '2026-03-05T09:00:00.000Z', period_end: '2027-03-05T09:00:00.000Z' });
    expect(annualPeriod(started, new Date('2026-03-04T08:00:00Z'))).toEqual({ period_start: '2025-03-05T09:00:00.000Z', period_end: '2026-03-05T09:00:00.000Z' });
    expect(annualPeriod(started, started)).toEqual({ period_start: '2025-03-05T09:00:00.000Z', period_end: '2026-03-05T09:00:00.000Z' });
  });
});

// ---------------------------------------------------------------------------
// Pricing rules
// ---------------------------------------------------------------------------

describe('pricing with a membership (docs/MEMBERSHIPS.md rules)', () => {
  it('Gold covered wash → base included, add-ons charged, label counts after this booking', async () => {
    const { quote } = await priceService(OUTLET, S_WASH, 'cust_gold', { vehicleSize: 'small', addonServiceIds: [S_TYRE] });
    expect(quote).toMatchObject({ base_cents: 15000, addons_cents: 3000, price_cents: 18000, discount_cents: 15000, vat_cents: 0, total_cents: 3000, discount_label: 'Included in Gold · 2 of 4 left', tier: 'gold', points_pending: 3 });
    expect(quote.membership).toEqual({ membership_id: M_GOLD, plan_code: 'gold', plan_name: 'Gold', benefit: 'included', entitlement_id: E(1), entitlement_code: 'G1', remaining_after: 2, period_end: '2026-10-10T09:00:00.000Z' });
  });

  it('a larger vehicle is still covered (the large base is the discount)', async () => {
    const { quote } = await priceService(OUTLET, S_WASH, 'cust_gold', { vehicleSize: 'large' });
    expect(quote).toMatchObject({ base_cents: 20000, discount_cents: 20000, total_cents: 0, discount_label: 'Included in Gold · 2 of 4 left' });
  });

  it('Gold other service → −10%; a plan service that was not selected gets nothing', async () => {
    const valet = await priceService(OUTLET, S_VALET, 'cust_gold', { vehicleSize: 'small' });
    expect(valet.quote).toMatchObject({ price_cents: 22000, discount_cents: 2200, total_cents: 19800, discount_label: 'Gold −10%', points_pending: 20 });
    expect(valet.quote.membership).toMatchObject({ plan_code: 'gold', benefit: 'discount', entitlement_code: null, remaining_after: null });
    const ext = await priceService(OUTLET, S_EXT, 'cust_gold', { vehicleSize: 'small' });
    expect(ext.quote).toMatchObject({ price_cents: 8000, discount_cents: 0, total_cents: 8000, discount_label: null });
    expect(ext.quote.membership).toMatchObject({ plan_code: 'gold', benefit: null });
  });

  it('Gold selected service with the allowance exhausted → full price (other_services scope)', async () => {
    const { quote } = await priceService(OUTLET, S_WASH, 'cust_gold_x', { vehicleSize: 'small' });
    expect(quote).toMatchObject({ price_cents: 15000, discount_cents: 0, total_cents: 15000, discount_label: null });
    expect(quote.membership).toMatchObject({ plan_code: 'gold', benefit: null });
  });

  it('Platinum exhausted → −10% on the selected service; nothing on other services', async () => {
    const wash = await priceService(OUTLET, S_WASH, 'cust_plat', { vehicleSize: 'small', addonServiceIds: [S_TYRE] });
    expect(wash.quote).toMatchObject({ price_cents: 18000, discount_cents: 1800, total_cents: 16200, discount_label: 'Platinum −10%' });
    expect(wash.quote.membership).toMatchObject({ plan_code: 'platinum', benefit: 'discount' });
    const valet = await priceService(OUTLET, S_VALET, 'cust_plat', { vehicleSize: 'small' });
    expect(valet.quote).toMatchObject({ discount_cents: 0, discount_label: null });
  });

  it('Black: monthly detail used → −10%, the annual coating still has its allowance, washes remain', async () => {
    const ctx = await loadContext('cust_black');
    expect(ctx?.allowances.map((a) => [a.entitlement_code, a.used, a.remaining, a.period])).toEqual([['B1', 2, 8, 'month'], ['B3', 1, 0, 'month'], ['B5', 0, 1, 'year']]);
    expect(ctx?.allowances.find((a) => a.entitlement_code === 'B5')).toMatchObject({ period_start: '2026-08-17T09:00:00.000Z', period_end: '2027-08-17T09:00:00.000Z' });
    expect(benefitFor(S_COAT, ctx)).toMatchObject({ benefit: 'included', entitlement_code: 'B5', remaining_after: 0, period_end: '2027-08-17T09:00:00.000Z' });
    const detail = await priceService(OUTLET, S_DETAIL, 'cust_black', { vehicleSize: 'small' });
    expect(detail.quote).toMatchObject({ discount_cents: 4500, total_cents: 40500, discount_label: 'Black −10%' });
    const steam = await priceService(OUTLET, S_STEAM, 'cust_black', { vehicleSize: 'small' });
    expect(steam.quote).toMatchObject({ discount_cents: 0, discount_label: null }); // B4 not selected, scope = plan_services
    await expect(priceService(OUTLET, S_COAT, 'cust_black', {})).rejects.toMatchObject({ status: 409, details: { reason: 'by_quote' } });
  });

  it('past_due pauses benefits; no membership → membership null and no discount', async () => {
    const late = await priceService(OUTLET, S_WASH, 'cust_pastdue', { vehicleSize: 'small' });
    expect(late.quote).toMatchObject({ discount_cents: 0, total_cents: 15000, discount_label: null, tier: 'gold', membership: null });
    const none = await priceService(OUTLET, S_WASH, 'cust_none', { vehicleSize: 'small' });
    expect(none.quote).toMatchObject({ discount_cents: 0, total_cents: 15000, discount_label: null, tier: 'silver', membership: null });
  });

  it('computePrice: included on an excl-VAT offer charges VAT on the add-ons only; tier config stays a fallback', () => {
    const included = { membership_id: 'm', plan_code: 'gold', plan_name: 'Gold', benefit: 'included' as const, discount_pct: 0, entitlement_id: 'e', entitlement_code: 'G1', entitlement_quantity: 4, remaining_after: 3, period_start: null, period_end: null };
    const q = computePrice({ basePriceCents: 15000, addons: [{ service_id: S_TYRE, name: 'Tyre shine', price_cents: 3000 }], vatMode: 'excl', tier: 'gold', tierConfig: null, pointsPerRand: 0.1, membership: included });
    expect(q).toMatchObject({ discount_cents: 15000, vat_cents: 450, total_cents: 3450, discount_label: 'Included in Gold · 3 of 4 left', points_pending: 3 });
    const fallback = computePrice({ basePriceCents: 10000, tier: 'gold', tierConfig: { tier: 'gold', name: 'Gold', min_points: 0, max_points: null, earn_multiplier: 1, discount_pct: 5 }, pointsPerRand: 0.1, membership: null });
    expect(fallback).toMatchObject({ discount_cents: 500, discount_label: 'Gold −5%', membership: null });
  });

  it('GET /outlets/:id/services?vehicle_size marks covered offers for the caller', async () => {
    const r = await call(`/v1/outlets/${OUTLET}/services?vehicle_size=small`, 'gold');
    expect(r.status).toBe(200);
    expect(r.body.membership).toEqual({ plan_code: 'gold', plan_name: 'Gold', status: 'active' });
    const wash = r.body.data.find((o: any) => o.service_id === S_WASH);
    expect(wash).toMatchObject({ total_cents: 0, discount_label: 'Included in Gold · 2 of 4 left', membership: { benefit: 'included', entitlement_code: 'G1' } });
    const valet = r.body.data.find((o: any) => o.service_id === S_VALET);
    expect(valet).toMatchObject({ total_cents: 19800, discount_label: 'Gold −10%' });
  });
});

// ---------------------------------------------------------------------------
// Bookings: usage + release
// ---------------------------------------------------------------------------

describe('booking lifecycle consumes and releases allowances', () => {
  const body = { vehicle_id: VEH_GOLD, outlet_id: OUTLET, service_id: S_WASH, slot_start: '2026-09-15T08:00:00.000Z', client_op_id: 'op-mem-book-0001', addon_service_ids: [S_TYRE] };

  it('posts +1 usage once per booking (idempotent replay), stores the membership columns and releases on cancel', async () => {
    const r = await post('/v1/bookings', 'gold', body);
    expect(r.status).toBe(201);
    const b = r.body.booking;
    expect(b).toMatchObject({ total_cents: 3000, discount_cents: 15000, discount_label: 'Included in Gold · 2 of 4 left', membership_id: M_GOLD, entitlement_id: E(1), membership_benefit: 'included' });
    expect(usage(M_GOLD).filter((u) => u.booking_id === b.id)).toEqual([expect.objectContaining({ quantity: 1, entitlement_id: E(1), idempotency_key: `booking:${b.id}:membership`, period_start: '2026-09-10T09:00:00.000Z', created_by: 'cust_gold' })]);
    expect(b.status).toBe('pending'); // add-ons still due
    expect((await membershipSummary('cust_gold')).allowances[0]).toMatchObject({ entitlement_code: 'G1', used: 2, remaining: 2 });

    const again = await post('/v1/bookings', 'gold', body);
    expect(again.status).toBe(201);
    expect(again.headers.get('idempotent-replayed')).toBe('true');
    expect(usage(M_GOLD)).toHaveLength(3); // 2 seed rows + 1

    const next = await priceService(OUTLET, S_WASH, 'cust_gold', { vehicleSize: 'small' });
    expect(next.quote.discount_label).toBe('Included in Gold · 1 of 4 left');

    const cancel = await post(`/v1/bookings/${b.id}/cancel`, 'gold', { reason: 'plans changed' });
    expect(cancel.status).toBe(200);
    const release = usage(M_GOLD).find((u) => u.idempotency_key === `booking:${b.id}:membership_release`);
    expect(release).toMatchObject({ quantity: -1, booking_id: b.id, entitlement_id: E(1), period_start: '2026-09-10T09:00:00.000Z' });
    expect((await membershipSummary('cust_gold')).allowances[0]).toMatchObject({ used: 1, remaining: 3 });
    const cancelAgain = await post(`/v1/bookings/${b.id}/cancel`, 'gold', {});
    expect(cancelAgain.status).toBe(409); // already cancelled → no second release
    expect(usage(M_GOLD).filter((u) => u.booking_id === b.id)).toHaveLength(2);
    expect(audits('booking.create')[0].after).toMatchObject({ membership_benefit: 'included', entitlement_id: E(1) });
  });

  it('a fully covered customer booking (no add-ons) is confirmed on creation and refuses a payment intent', async () => {
    const r = await post('/v1/bookings', 'gold', { vehicle_id: VEH_GOLD, outlet_id: OUTLET, service_id: S_WASH, slot_start: '2026-09-16T08:00:00.000Z', client_op_id: 'op-mem-book-zero' });
    expect(r.status).toBe(201);
    expect(r.body.booking).toMatchObject({ status: 'confirmed', total_cents: 0, discount_cents: 15000, membership_benefit: 'included' });
    const intent = await post('/v1/payments/intents', 'gold', { booking_id: r.body.booking.id, idempotency_key: 'zero-intent-0001' });
    expect(intent.status).toBe(409);
    expect(intent.body.error?.details ?? intent.body.details ?? intent.body).toMatchObject({ reason: 'nothing_to_pay' });
  });

  it('the walk-in path (staff, on behalf) goes through the same rules and consumes the allowance', async () => {
    const r = await post('/v1/bookings', 'tech', { vehicle_id: VEH_GOLD_LARGE, outlet_id: OUTLET, service_id: S_WASH, customer_id: 'cust_gold', walk_in: true, client_op_id: 'op-mem-walk-0001' });
    expect(r.status).toBe(201);
    expect(r.body.booking).toMatchObject({ status: 'confirmed', walk_in: true, vehicle_size: 'large', price_cents: 20000, discount_cents: 20000, total_cents: 0, membership_benefit: 'included', entitlement_id: E(1) });
    expect(usage(M_GOLD).find((u) => u.booking_id === r.body.booking.id)).toMatchObject({ quantity: 1, created_by: 'tech_1' });
    const discounted = await post('/v1/bookings', 'tech', { vehicle_id: VEH_GOLD, outlet_id: OUTLET, service_id: S_VALET, customer_id: 'cust_gold', walk_in: true, client_op_id: 'op-mem-walk-0002' });
    expect(discounted.body.booking).toMatchObject({ total_cents: 19800, discount_label: 'Gold −10%', membership_id: M_GOLD, entitlement_id: null, membership_benefit: 'discount' });
    expect(usage(M_GOLD).filter((u) => u.booking_id === discounted.body.booking.id)).toHaveLength(0);
  });

  it('once the allowance is exhausted the next booking is charged (Gold other_services → no discount on the plan service)', async () => {
    for (let i = 1; i <= 3; i++) {
      const r = await post('/v1/bookings', 'gold', { ...body, addon_service_ids: [], slot_start: `2026-09-1${5 + i}T08:00:00.000Z`, client_op_id: `op-mem-book-fill-${i}` });
      expect(r.status).toBe(201);
      expect(r.body.booking.membership_benefit).toBe('included');
    }
    const full = await post('/v1/bookings', 'gold', { ...body, addon_service_ids: [], slot_start: '2026-09-20T08:00:00.000Z', client_op_id: 'op-mem-book-full' });
    expect(full.status).toBe(201);
    expect(full.body.booking).toMatchObject({ total_cents: 15000, discount_cents: 0, membership_benefit: null, entitlement_id: null });
  });

  it('a staff-raised quotation records a covered by-quote line at R0 and consumes the annual allowance', async () => {
    const r = await raiseQuotation(makeCtx('supervisor', 'tech_1', [OUTLET]), { customerId: 'cust_black', vehicleId: VEH_BLACK, outletId: OUTLET, category: 'Paint', description: 'Ceramic coating for the bonnet', items: [{ label: 'Ceramic coating', service_id: S_COAT, amount_cents: 350000 }, { label: 'Paint correction', amount_cents: 120000 }], validUntil: '2026-10-14', clientOpId: 'op-mem-quote-0001', sendToCustomer: false });
    expect(r.quotation.line_items).toEqual([{ label: 'Ceramic coating', service_id: S_COAT, amount_cents: 0, membership_benefit: 'included', entitlement_id: E(9) }, { label: 'Paint correction', amount_cents: 120000 }]);
    expect(r.quotation.amount_cents).toBe(120000);
    expect(usage(M_BLACK).find((u) => u.entitlement_id === E(9))).toMatchObject({ quantity: 1, period_start: '2026-08-17T09:00:00.000Z', period_end: '2027-08-17T09:00:00.000Z', idempotency_key: `quotation:${r.quotation.id}:membership:${E(9)}` });
    expect(benefitFor(S_COAT, await loadContext('cust_black'))).toMatchObject({ benefit: 'discount', discount_pct: 10 });
  });
});

// ---------------------------------------------------------------------------
// Subscribe → activation on payment success
// ---------------------------------------------------------------------------

describe('POST /memberships (customer subscribe)', () => {
  const body = { plan_code: 'gold', selections: { washes: 'G1' }, payment_method: 'card', client_op_id: 'op-mem-sub-0001' };

  it('creates a pending membership + first invoice + sandbox intent; the successful payment activates it', async () => {
    const r = await post('/v1/memberships', 'none', body);
    expect(r.status).toBe(201);
    expect(r.body.membership).toMatchObject({ customer_id: 'cust_none', plan_id: PLAN_GOLD, status: 'pending', payment_method: 'card', current_period_start: null, created_by: 'cust_none' });
    expect(r.body.invoice).toMatchObject({ membership_id: r.body.membership.id, amount_cents: 29500, status: 'pending', idempotency_key: `first:${r.body.membership.id}` });
    expect(r.body.payment).toMatchObject({ membership_invoice_id: r.body.invoice.id, booking_id: null, amount_cents: 29500, status: 'pending', provider: 'sandbox' });
    expect(r.body.payment.client_secret).toMatch(/_secret_/);
    expect(selectionsOf(r.body.membership.id)).toEqual([{ membership_id: r.body.membership.id, group_id: G_GOLD, entitlement_id: E(1) }]);
    expect(tierOf('cust_none')).toBe('silver');
    expect((await priceService(OUTLET, S_WASH, 'cust_none', {})).quote.membership).toBeNull(); // pending → no benefits yet

    const replay = await post('/v1/memberships', 'none', body);
    expect(replay.status).toBe(201);
    expect(replay.headers.get('idempotent-replayed')).toBe('true');
    expect(db.rows('memberships').filter((m) => m.customer_id === 'cust_none')).toHaveLength(1);

    const pay = await post(`/v1/payments/${r.body.payment.id}/sandbox-confirm`, 'none', { outcome: 'succeeded' });
    expect(pay.status).toBe(200);
    expect(pay.body.payment.status).toBe('successful');
    const m = db.rows('memberships').find((x) => x.id === r.body.membership.id)!;
    expect(m).toMatchObject({ status: 'active', started_at: NOW, current_period_start: NOW, current_period_end: '2026-10-14T10:00:00.000Z' });
    const inv = db.rows('membership_invoices').find((x) => x.id === r.body.invoice.id)!;
    expect(inv).toMatchObject({ status: 'paid', paid_at: NOW, payment_id: r.body.payment.id, period_start: NOW, period_end: '2026-10-14T10:00:00.000Z' });
    expect(tierOf('cust_none')).toBe('gold');
    expect(notes('membership_activated')).toHaveLength(1);
    expect(notes('membership_activated')[0].body).toBe('Your Gold membership is active until 14 Oct 2026. 4 of 4 Sparkling Washes left · 10% discount on any other Sparkling service');
    expect(notes('payment_successful')).toHaveLength(1);

    const me = await call('/v1/memberships/me', 'none');
    expect(me.status).toBe(200);
    expect(me.body.membership.id).toBe(m.id);
    expect(me.body.plan.code).toBe('gold');
    expect(me.body.selections).toEqual({ washes: 'G1' });
    expect(me.body.allowances).toEqual([{ entitlement_id: E(1), entitlement_code: 'G1', group_code: 'washes', label: '4 × Sparkling Wash', quantity: 4, used: 0, remaining: 4, period: 'month', period_start: NOW, period_end: '2026-10-14T10:00:00.000Z' }]);
    expect(me.body.open_invoice).toBeNull();
    expect(me.body.invoices).toHaveLength(1);
    expect(me.body.next_renewal_at).toBe('2026-10-14T10:00:00.000Z');
    expect((await priceService(OUTLET, S_WASH, 'cust_none', {})).quote.discount_label).toBe('Included in Gold · 3 of 4 left');
    expect(audits('membership.subscribe')).toHaveLength(1);
  });

  it('409s when a live membership exists and validates the selections', async () => {
    const dup = await post('/v1/memberships', 'gold', body);
    expect(dup.status).toBe(409);
    expect(dup.body.error.details).toMatchObject({ membership_id: M_GOLD, status: 'active' });
    const missing = await post('/v1/memberships', 'none', { ...body, client_op_id: 'op-mem-sub-0002', selections: {} });
    expect(missing.status).toBe(400);
    expect(missing.body.error.details[0].path).toBe('selections.washes');
    const wrong = await post('/v1/memberships', 'none', { ...body, client_op_id: 'op-mem-sub-0003', selections: { washes: 'P1' } });
    expect(wrong.status).toBe(400);
    const extra = await post('/v1/memberships', 'none', { ...body, client_op_id: 'op-mem-sub-0004', plan_code: 'black', selections: { washes: 'B1', detail: 'B3', coating: 'B5' } });
    expect(extra.status).toBe(400);
    expect(extra.body.error.details[0].path).toBe('selections.coating');
    const unknown = await post('/v1/memberships', 'none', { ...body, client_op_id: 'op-mem-sub-0005', plan_code: 'diamond' });
    expect(unknown.status).toBe(404);
    expect(db.rows('memberships').filter((m) => m.customer_id === 'cust_none')).toHaveLength(0);
  });

  it('lists plans with the caller’s current plan and exposes the summary shapes on /me and /loyalty/account', async () => {
    const plans = await call('/v1/memberships/plans', 'black');
    expect(plans.status).toBe(200);
    expect(plans.body.current_plan_code).toBe('black');
    expect(plans.body.data.map((p: any) => p.code)).toEqual(['gold', 'platinum', 'black']);
    const black = plans.body.data[2];
    expect(black.groups.map((g: any) => [g.code, g.selection, g.entitlements.map((e: any) => e.code)])).toEqual([['washes', 'choose_one', ['B1', 'B2']], ['detail', 'choose_one', ['B3', 'B4']], ['coating', 'all', ['B5']]]);
    expect(black.groups[2].entitlements[0].services).toEqual([{ id: S_COAT, code: 'CERAMIC_COATING', name: 'Ceramic coating', is_primary: true }]);
    expect(black.discount_pct).toBe(10);

    const me = await call('/v1/me', 'black');
    expect(me.body.membership).toMatchObject({ plan_code: 'black', plan_name: 'Black', tier: 'black', status: 'active', period_end: '2026-09-17T09:00:00.000Z' });
    expect(me.body.membership.allowances.map((a: any) => a.entitlement_code)).toEqual(['B1', 'B3', 'B5']);
    const acct = await call('/v1/loyalty/account', 'black');
    expect(acct.body.membership.plan_code).toBe('black');
    expect(acct.body.account.tier).toBe('black');
    const nobody = await call('/v1/me', 'none');
    expect(nobody.body.membership).toBeNull();
  });
});

// ---------------------------------------------------------------------------
// Counter enrolment (staff / admin / sync)
// ---------------------------------------------------------------------------

describe('counter enrolment', () => {
  const body = { plan_code: 'platinum', selections: { washes: 'P2' }, payment_method: 'cash', reference: 'till-3', client_op_id: 'op-mem-enrol-0001' };

  it('POST /staff/customers/:id/membership activates immediately with a paid invoice and a pos payment row', async () => {
    const r = await post('/v1/staff/customers/cust_none/membership', 'tech', body);
    expect(r.status).toBe(201);
    expect(r.body.membership).toMatchObject({ customer_id: 'cust_none', plan_id: PLAN_PLAT, status: 'active', payment_method: 'cash', started_at: NOW, current_period_start: NOW, current_period_end: '2026-10-14T10:00:00.000Z', created_by: 'tech_1' });
    expect(r.body.invoice).toMatchObject({ amount_cents: 47500, status: 'paid', paid_at: NOW, payment_id: r.body.payment.id });
    expect(r.body.payment).toMatchObject({ provider: 'pos', method: 'cash', provider_ref: 'till-3', status: 'successful', receipt_no: 'RCP-70001', recorded_by: 'tech_1', membership_invoice_id: r.body.invoice.id, booking_id: null, amount_cents: 47500, idempotency_key: 'tech_1:membership:op-mem-enrol-0001' });
    expect(r.body.summary.allowances).toEqual([expect.objectContaining({ entitlement_code: 'P2', quantity: 16, remaining: 16 })]);
    expect(db.rows('payment_events').find((e) => e.payment_id === r.body.payment.id)).toMatchObject({ provider: 'pos', event_type: 'pos.recorded', signature_ok: true });
    expect(tierOf('cust_none')).toBe('platinum');
    expect(notes('membership_activated')).toHaveLength(1);
    const log = audits('membership.enrol');
    expect(log).toHaveLength(1);
    expect(log[0]).toMatchObject({ actor_id: 'tech_1', entity_id: r.body.membership.id, outlet_id: OUTLET });
    expect(log[0].after).toMatchObject({ plan_code: 'platinum', method: 'cash', receipt_no: 'RCP-70001' });

    const replay = await post('/v1/staff/customers/cust_none/membership', 'tech', body);
    expect(replay.status).toBe(201);
    expect(replay.headers.get('idempotent-replayed')).toBe('true');
    expect(db.rows('memberships').filter((m) => m.customer_id === 'cust_none')).toHaveLength(1);
    expect(db.rows('payments').filter((p) => p.customer_id === 'cust_none')).toHaveLength(1);

    const search = await call('/v1/staff/customers?search=lerato', 'tech');
    expect(search.body.data[0].loyalty).toEqual({ tier: 'platinum', balance_points: 9000, discount_pct: 0, plan_code: 'platinum', plan_name: 'Platinum', membership_status: 'active', included_remaining: 16 });
    const view = await call('/v1/staff/customers/cust_none/membership', 'tech');
    expect(view.status).toBe(200);
    expect(view.body.plan.code).toBe('platinum');
    expect(view.body.benefits_summary).toBe('16 of 16 Exterior Washes left · 10% discount on the above selected services');
  });

  it('is staff-only and outlet-scoped; refuses a second live membership', async () => {
    const cust = await post('/v1/staff/customers/cust_none/membership', 'gold', body);
    expect(cust.status).toBe(403);
    const outside = await post('/v1/staff/customers/cust_none/membership', 'other', { ...body, outlet_id: OUTLET });
    expect(outside.status).toBe(403);
    const dup = await post('/v1/staff/customers/cust_gold/membership', 'tech', { ...body, client_op_id: 'op-mem-enrol-0002' });
    expect(dup.status).toBe(409);
    const missing = await post('/v1/staff/customers/nobody/membership', 'tech', body);
    expect(missing.status).toBe(404);
    const view = await call('/v1/staff/customers/cust_gold/membership', 'gold');
    expect(view.status).toBe(403);
  });

  it('works through the sync batch (kind membership.enrol) and the admin route', async () => {
    const sync = await post('/v1/sync/batch', 'tech', { operations: [{ client_op_id: 'op-mem-sync-0001', kind: 'membership.enrol', payload: { customer_id: 'cust_none', plan_code: 'gold', selections: { washes: 'G2' }, payment_method: 'card_terminal' } }] });
    expect(sync.status).toBe(200);
    expect(sync.body.applied).toBe(1);
    expect(sync.body.results[0].result.membership).toMatchObject({ status: 'active', payment_method: 'card', client_op_id: 'op-mem-sync-0001' });
    expect(sync.body.results[0].result.payment).toMatchObject({ provider: 'pos', method: 'card_terminal' });
    const again = await post('/v1/sync/batch', 'tech', { operations: [{ client_op_id: 'op-mem-sync-0001', kind: 'membership.enrol', payload: { customer_id: 'cust_none', plan_code: 'gold', selections: { washes: 'G2' }, payment_method: 'card_terminal' } }] });
    expect(again.body.results[0].status).toBe('applied');
    expect(db.rows('memberships').filter((m) => m.customer_id === 'cust_none')).toHaveLength(1);
    const custSync = await post('/v1/sync/batch', 'none', { operations: [{ client_op_id: 'op-mem-sync-0002', kind: 'membership.enrol', payload: { customer_id: 'cust_none', plan_code: 'gold', selections: { washes: 'G2' }, payment_method: 'cash' } }] });
    expect(custSync.body.results[0].status).toBe('rejected');

    const cancel = await post(`/v1/memberships/me/cancel`, 'none', { at_period_end: false });
    expect(cancel.status).toBe(200);
    const admin = await post('/v1/admin/customers/cust_none/membership', 'manager', { plan_code: 'black', selections: { washes: 'B2', detail: 'B4' }, payment_method: 'eft', client_op_id: 'op-mem-admin-0001' });
    expect(admin.status).toBe(201);
    expect(admin.body.membership).toMatchObject({ status: 'active', payment_method: 'eft', created_by: 'uid_manager' });
    expect(admin.body.summary.allowances.map((a: any) => a.entitlement_code)).toEqual(['B2', 'B4', 'B5']);
    expect(tierOf('cust_none')).toBe('black');
    const finance = await post('/v1/admin/customers/cust_gold_x/membership', 'finance', { plan_code: 'gold', selections: { washes: 'G1' }, payment_method: 'cash', client_op_id: 'op-mem-admin-0002' });
    expect(finance.status).toBe(403);
  });
});

// ---------------------------------------------------------------------------
// Selections, plan changes, cancellation
// ---------------------------------------------------------------------------

describe('changing selections, plan and cancelling', () => {
  it('PUT /memberships/me/selections is refused once anything was used this period', async () => {
    const r = await put('/v1/memberships/me/selections', 'gold', { selections: { washes: 'G2' } });
    expect(r.status).toBe(409);
    expect(r.body.error.details).toMatchObject({ used: 1, period_end: '2026-10-10T09:00:00.000Z' });
    await post('/v1/staff/customers/cust_none/membership', 'tech', { plan_code: 'gold', selections: { washes: 'G1' }, payment_method: 'cash', client_op_id: 'op-mem-enrol-sel' });
    const ok = await put('/v1/memberships/me/selections', 'none', { selections: { washes: 'G2' } });
    expect(ok.status).toBe(200);
    expect(ok.body.selections).toEqual({ washes: 'G2' });
    expect(ok.body.allowances[0]).toMatchObject({ entitlement_code: 'G2', quantity: 8, remaining: 8 });
    expect(audits('membership.selections')).toHaveLength(1);
    const bad = await put('/v1/memberships/me/selections', 'none', { selections: { washes: 'P1' } });
    expect(bad.status).toBe(400);
    const late = await put('/v1/memberships/me/selections', 'pastdue', { selections: { washes: 'G2' } }); // past_due, nothing used this period → allowed
    expect(late.status).toBe(200);
    const nobody = await put('/v1/memberships/me/selections', 'cash', { selections: { washes: 'G2' } });
    expect(nobody.status).toBe(200);
  });

  it('upgrade applies now through a full-fee invoice; downgrade waits for renewal', async () => {
    const up = await post('/v1/memberships/me/change-plan', 'gold', { plan_code: 'platinum', selections: { washes: 'P1' } });
    expect(up.status).toBe(201);
    expect(up.body).toMatchObject({ change: 'upgrade', applies_at: null });
    expect(up.body.membership).toMatchObject({ plan_id: PLAN_GOLD, next_plan_id: PLAN_PLAT, status: 'active' });
    expect(up.body.invoice).toMatchObject({ amount_cents: 47500, status: 'pending', period_start: NOW, period_end: '2026-10-14T10:00:00.000Z' });
    expect(up.body.payment.client_secret).toMatch(/_secret_/);
    expect(db.rows('membership_selections').filter((s) => s.membership_id === M_GOLD).map((s) => s.entitlement_id).sort()).toEqual([E(1), E(3)]);
    // Still Gold until paid.
    expect((await priceService(OUTLET, S_WASH, 'cust_gold', {})).quote.membership).toMatchObject({ plan_code: 'gold' });
    const pay = await post(`/v1/payments/${up.body.payment.id}/sandbox-confirm`, 'gold', { outcome: 'succeeded' });
    expect(pay.status).toBe(200);
    const m = db.rows('memberships').find((x) => x.id === M_GOLD)!;
    expect(m).toMatchObject({ plan_id: PLAN_PLAT, next_plan_id: null, status: 'active', current_period_start: NOW, current_period_end: '2026-10-14T10:00:00.000Z' });
    expect(selectionsOf(M_GOLD)).toEqual([{ membership_id: M_GOLD, group_id: G_PLAT, entitlement_id: E(3) }]);
    expect(tierOf('cust_gold')).toBe('platinum');
    expect(notes('membership_renewed')).toHaveLength(1);
    const q = await priceService(OUTLET, S_WASH, 'cust_gold', {});
    expect(q.quote.discount_label).toBe('Included in Platinum · 7 of 8 left'); // fresh period: old usage does not carry over

    const down = await post('/v1/memberships/me/change-plan', 'black', { plan_code: 'gold', selections: { washes: 'G2' } });
    expect(down.status).toBe(200);
    expect(down.body).toMatchObject({ change: 'downgrade', invoice: null, payment: null, applies_at: '2026-09-17T09:00:00.000Z' });
    expect(db.rows('memberships').find((x) => x.id === M_BLACK)).toMatchObject({ plan_id: PLAN_BLACK, next_plan_id: PLAN_GOLD });
    const me = await call('/v1/memberships/me', 'black');
    expect(me.body.next_plan).toMatchObject({ code: 'gold', monthly_fee_cents: 29500 });
    const same = await post('/v1/memberships/me/change-plan', 'black', { plan_code: 'black', selections: { washes: 'B1', detail: 'B3' } });
    expect(same.status).toBe(409);
    expect(audits('membership.change_plan')).toHaveLength(2);
  });

  it('cancels at period end by default (benefits continue) or immediately (tier → silver, pending invoices void)', async () => {
    const r = await post('/v1/memberships/me/cancel', 'gold', {});
    expect(r.status).toBe(200);
    expect(r.body.membership).toMatchObject({ status: 'active', cancel_at_period_end: true, cancelled_at: NOW, ended_at: null });
    expect(tierOf('cust_gold')).toBe('gold');
    expect((await priceService(OUTLET, S_WASH, 'cust_gold', {})).quote.discount_label).toBe('Included in Gold · 2 of 4 left');
    expect((await call('/v1/memberships/me', 'gold')).body.next_renewal_at).toBeNull();
    expect(notes('membership_cancelled')[0].body).toBe('Your Gold membership ends on 10 Oct 2026. You can rejoin any time.');

    const now = await post('/v1/memberships/me/cancel', 'cash', { at_period_end: false, reason: 'moving' });
    expect(now.status).toBe(200);
    expect(now.body.membership).toMatchObject({ status: 'cancelled', cancelled_at: NOW, ended_at: NOW });
    expect(tierOf('cust_cash')).toBe('silver');
    expect(db.rows('membership_invoices').find((i) => i.id === INV_CASH_NEXT)!.status).toBe('void');
    expect((await priceService(OUTLET, S_EXT, 'cust_cash', {})).quote.membership).toBeNull();
    expect((await call('/v1/memberships/me', 'cash')).body.membership).toBeNull();
    const again = await post('/v1/memberships/me/cancel', 'cash', {});
    expect(again.status).toBe(404);
    const admin = await post(`/v1/admin/memberships/${M_PLAT}/cancel`, 'admin', { at_period_end: false });
    expect(admin.status).toBe(200);
    expect(tierOf('cust_plat')).toBe('silver');
    expect(audits('membership.cancel')).toHaveLength(3);
    expect(audits('membership.cancel')[2].after).toMatchObject({ on_behalf: true, immediate: true });
  });
});

// ---------------------------------------------------------------------------
// Renewals job
// ---------------------------------------------------------------------------

describe('runRenewals (daily job / POST /admin/memberships/run-renewals)', () => {
  it('creates the next invoice 3 days ahead (once), marks unpaid periods past_due, ends cancelled ones and expires stale past_due', async () => {
    const r = await runRenewals();
    expect(r).toMatchObject({ scanned: 8, invoices_created: 1, past_due: 1, cancelled: 1, expired: 1, auto_charged: 0, rolled: 0, errors: [] });
    // Zanele (Black, ends 17 Sep) → invoice for [17 Sep, 17 Oct), notified.
    const inv = db.rows('membership_invoices').find((i) => i.membership_id === M_BLACK && i.status === 'pending')!;
    expect(inv).toMatchObject({ amount_cents: 85000, period_start: '2026-09-17T09:00:00.000Z', period_end: '2026-10-17T09:00:00.000Z', due_at: '2026-09-17T09:00:00.000Z', idempotency_key: `renewal:${M_BLACK}:2026-09-17` });
    expect(notes('membership_renewal_due')).toHaveLength(1);
    expect(notes('membership_renewal_due')[0].body).toBe('Your Black membership renews on 17 Sep 2026 (R 850.00).');
    expect((await call('/v1/memberships/me', 'black')).body.open_invoice.id).toBe(inv.id);
    // Naledi (cash, period ended 10 Sep, invoice unpaid) → past_due, benefits paused, tier kept.
    expect(db.rows('memberships').find((m) => m.id === M_CASH)).toMatchObject({ status: 'past_due' });
    expect(notes('membership_past_due')[0].body).toBe('Your Gold benefits are paused until R 295.00 is paid.');
    expect(tierOf('cust_cash')).toBe('gold');
    expect((await priceService(OUTLET, S_EXT, 'cust_cash', {})).quote.membership).toBeNull();
    // Leaving member (cancel_at_period_end, ended 12 Sep) → cancelled, silver.
    expect(db.rows('memberships').find((m) => m.id === M_ENDING)).toMatchObject({ status: 'cancelled', ended_at: NOW });
    expect(tierOf('cust_ending')).toBe('silver');
    // Stale past_due (period ended 1 Aug, > 30 days) → expired, invoice void, silver.
    expect(db.rows('memberships').find((m) => m.id === M_STALE)).toMatchObject({ status: 'expired', ended_at: NOW });
    expect(db.rows('membership_invoices').find((i) => i.membership_id === M_STALE)!.status).toBe('void');
    expect(tierOf('cust_stale')).toBe('silver');
    // Recent past_due (ended 1 Sep) stays past_due, untouched.
    expect(db.rows('memberships').find((m) => m.id === M_PASTDUE)!.status).toBe('past_due');

    const second = await runRenewals();
    expect(second).toMatchObject({ invoices_created: 0, past_due: 0, cancelled: 0, expired: 0, auto_charged: 0 });
    expect(db.rows('membership_invoices').filter((i) => i.membership_id === M_BLACK)).toHaveLength(2);
    expect(notes('membership_renewal_due')).toHaveLength(1);
  });

  it('auto-charges a sandbox card member once the invoice is due and rolls the period; a downgrade applies at that renewal', async () => {
    await runRenewals();
    await post('/v1/memberships/me/change-plan', 'black', { plan_code: 'gold', selections: { washes: 'G1' } });
    vi.setSystemTime(new Date('2026-09-17T10:00:00.000Z'));
    const r = await runRenewals();
    expect(r).toMatchObject({ auto_charged: 1, past_due: 0, errors: [] });
    const m = db.rows('memberships').find((x) => x.id === M_BLACK)!;
    expect(m).toMatchObject({ status: 'active', plan_id: PLAN_GOLD, next_plan_id: null, current_period_start: '2026-09-17T09:00:00.000Z', current_period_end: '2026-10-17T09:00:00.000Z' });
    const inv = db.rows('membership_invoices').find((i) => i.membership_id === M_BLACK && i.period_start === '2026-09-17T09:00:00.000Z')!;
    expect(inv.status).toBe('paid');
    const pay = db.rows('payments').find((p) => p.id === inv.payment_id)!;
    expect(pay).toMatchObject({ provider: 'sandbox', status: 'successful', amount_cents: 85000, membership_invoice_id: inv.id, customer_id: 'cust_black' });
    expect(pay.receipt_no).toMatch(/^RCP-/);
    expect(selectionsOf(M_BLACK)).toEqual([{ membership_id: M_BLACK, group_id: G_GOLD, entitlement_id: E(1) }]);
    expect(tierOf('cust_black')).toBe('gold');
    expect(notes('membership_renewed')).toHaveLength(1);
    const q = await priceService(OUTLET, S_WASH, 'cust_black', {});
    expect(q.quote.discount_label).toBe('Included in Gold · 3 of 4 left');
    expect(await runRenewals()).toMatchObject({ auto_charged: 0, invoices_created: 0 });
  });

  it('never auto-charges a counter member (cash / pos history); staff record the renewal at the counter', async () => {
    await runRenewals();
    expect(db.rows('memberships').find((m) => m.id === M_CASH)!.status).toBe('past_due');
    vi.setSystemTime(new Date('2026-09-15T10:00:00.000Z'));
    expect(await runRenewals()).toMatchObject({ auto_charged: 0 });
    const r = await post(`/v1/staff/memberships/${M_CASH}/invoices/${INV_CASH_NEXT}/record-payment`, 'tech', { method: 'card_terminal', client_op_id: 'op-mem-rp-0001' });
    expect(r.status).toBe(201);
    expect(r.body.payment).toMatchObject({ provider: 'pos', method: 'card_terminal', status: 'successful', amount_cents: 29500, recorded_by: 'tech_1', membership_invoice_id: INV_CASH_NEXT });
    expect(r.body.invoice).toMatchObject({ status: 'paid', payment_id: r.body.payment.id });
    expect(r.body.membership).toMatchObject({ status: 'active', current_period_start: '2026-09-10T09:00:00.000Z', current_period_end: '2026-10-10T09:00:00.000Z' });
    expect(notes('membership_renewed')).toHaveLength(1);
    expect(audits('membership.record_payment')[0]).toMatchObject({ actor_id: 'tech_1', entity_id: M_CASH, outlet_id: OUTLET });
    const replay = await post(`/v1/staff/memberships/${M_CASH}/invoices/${INV_CASH_NEXT}/record-payment`, 'tech', { method: 'card_terminal', client_op_id: 'op-mem-rp-0001' });
    expect(replay.status).toBe(201);
    expect(replay.headers.get('idempotent-replayed')).toBe('true');
    const again = await post(`/v1/staff/memberships/${M_CASH}/invoices/${INV_CASH_NEXT}/record-payment`, 'tech', { method: 'cash', client_op_id: 'op-mem-rp-0002' });
    expect(again.status).toBe(409);
    expect(db.rows('payments').filter((p) => p.membership_invoice_id === INV_CASH_NEXT)).toHaveLength(1);
    const cust = await post(`/v1/staff/memberships/${M_CASH}/invoices/${INV_CASH_NEXT}/record-payment`, 'cash', { method: 'cash', client_op_id: 'op-mem-rp-0003' });
    expect(cust.status).toBe(403);
  });

  it('the customer can pay a pending renewal in the app (past_due → active on success)', async () => {
    const r = await post(`/v1/memberships/me/invoices/${INV_PASTDUE}/pay`, 'pastdue', {});
    expect(r.status).toBe(201);
    expect(r.body.payment).toMatchObject({ status: 'pending', amount_cents: 29500, membership_invoice_id: INV_PASTDUE });
    expect(r.body.payment.client_secret).toMatch(/_secret_/);
    const twice = await post(`/v1/memberships/me/invoices/${INV_PASTDUE}/pay`, 'pastdue', {});
    expect(twice.status).toBe(200);
    expect(twice.body.duplicate).toBe(true);
    expect(twice.body.payment.id).toBe(r.body.payment.id);
    const other = await post(`/v1/memberships/me/invoices/${INV_PASTDUE}/pay`, 'gold', {});
    expect(other.status).toBe(403);
    const pay = await post(`/v1/payments/${r.body.payment.id}/sandbox-confirm`, 'pastdue', { outcome: 'succeeded' });
    expect(pay.status).toBe(200);
    expect(db.rows('memberships').find((m) => m.id === M_PASTDUE)).toMatchObject({ status: 'active', current_period_start: '2026-09-01T09:00:00.000Z', current_period_end: '2026-10-01T09:00:00.000Z' });
    expect((await priceService(OUTLET, S_WASH, 'cust_pastdue', {})).quote.discount_label).toBe('Included in Gold · 3 of 4 left');
    const admin = await post('/v1/admin/memberships/run-renewals', 'manager', {});
    expect(admin.status).toBe(200);
    expect(admin.body).toMatchObject({ scanned: 8, invoices_created: 1 });
    expect(audits('membership.run_renewals')).toHaveLength(1);
  });
});

// ---------------------------------------------------------------------------
// Admin: plans, members, KPIs, export, auth
// ---------------------------------------------------------------------------

describe('admin memberships', () => {
  it('lists plans with member_count / mrr and members with allowances; KPIs and the CSV export include memberships', async () => {
    const plans = await call('/v1/admin/memberships/plans', 'finance');
    expect(plans.status).toBe(200);
    // member_count = active + past_due; MRR counts active members only.
    expect(plans.body.data.map((p: any) => [p.code, p.member_count, p.mrr_cents])).toEqual([['gold', 6, 118000], ['platinum', 1, 47500], ['black', 1, 85000]]);
    const members = await call('/v1/admin/memberships?status=active&plan_code=gold&q=thabo', 'manager');
    expect(members.status).toBe(200);
    expect(members.body.data).toHaveLength(1);
    expect(members.body.data[0]).toMatchObject({ membership: { id: M_GOLD, status: 'active' }, customer: { id: 'cust_gold', full_name: 'Thabo Nkosi' }, plan: { code: 'gold', monthly_fee_cents: 29500 }, open_invoice: null });
    expect(members.body.data[0].allowances[0]).toMatchObject({ entitlement_code: 'G1', used: 1, remaining: 3 });
    const all = await call('/v1/admin/memberships?limit=3', 'admin');
    expect(all.body.data).toHaveLength(3);
    expect(all.body.next_cursor).not.toBeNull();
    const kpis = await call('/v1/admin/kpis', 'finance');
    expect(kpis.body).toMatchObject({ active_members: 6, membership_mrr_cents: 29500 * 4 + 47500 + 85000 });
    const csv = await call('/v1/admin/exports/memberships.csv', 'finance');
    expect(csv.status).toBe(200);
    expect(csv.body).toContain('ref,customer_id,customer,plan,status,period_start,period_end,fee_cents,used,remaining');
    expect(csv.body).toContain('Zanele Khumalo,Black,active,2026-08-17T09:00:00.000Z,2026-09-17T09:00:00.000Z,85000,3,9,B1 2/10; B3 1/1; B5 0/1');
    const customer = await call('/v1/admin/customers/cust_black', 'manager');
    expect(customer.body.membership.plan.code).toBe('black');
    expect(customer.body.membership.allowances).toHaveLength(3);
  });

  it('PUT /admin/memberships/plans/:code replaces groups by code, keeps ids, refuses to drop used entitlements, audits', async () => {
    const body = { name: 'Gold', tagline: 'New tagline', monthly_fee_cents: 31500, discount_pct: 12, discount_scope: 'other_services', discount_note: '12% off', groups: [{ code: 'washes', name: 'Monthly washes', selection: 'choose_one', entitlements: [{ code: 'G1', label: '5 × Sparkling Wash', quantity: 5, period: 'month', service_codes: ['SPARKLING_WASH'] }, { code: 'G2', label: '8 × Exterior Wash', quantity: 8, period: 'month', service_codes: ['EXT_WASH', 'TYRE_SHINE'] }, { code: 'G3', label: '2 × Full Valet', quantity: 2, period: 'month', service_codes: ['FULL_VALET'] }] }, { code: 'perk', name: 'Annual perk', selection: 'all', entitlements: [{ code: 'G9', label: '1 × Engine Steam Clean', quantity: 1, period: 'year', service_codes: ['ENGINE_STEAM'] }] }] };
    const r = await put('/v1/admin/memberships/plans/gold', 'manager', body);
    expect(r.status).toBe(200);
    expect(r.body.plan).toMatchObject({ code: 'gold', monthly_fee_cents: 31500, discount_pct: 12, tagline: 'New tagline', member_count: 6 });
    expect(r.body.plan.groups.map((g: any) => [g.id === G_GOLD, g.code, g.entitlements.map((e: any) => [e.code, e.id, e.quantity, e.services.map((s: any) => s.code)])])).toEqual([
      [true, 'washes', [['G1', E(1), 5, ['SPARKLING_WASH']], ['G2', E(2), 8, ['EXT_WASH', 'TYRE_SHINE']], ['G3', expect.any(String), 2, ['FULL_VALET']]]],
      [false, 'perk', [['G9', expect.any(String), 1, ['ENGINE_STEAM']]]],
    ]);
    // Existing members immediately see the new allowance and the annual perk; the fee applies from the next invoice.
    expect((await priceService(OUTLET, S_WASH, 'cust_gold', {})).quote.discount_label).toBe('Included in Gold · 3 of 5 left');
    expect((await membershipSummary('cust_gold')).allowances.map((a) => a.entitlement_code)).toEqual(['G1', 'G9']);
    expect(audits('membership_plan.update')).toHaveLength(1);

    const drop = await put('/v1/admin/memberships/plans/gold', 'manager', { ...body, groups: [{ ...body.groups[0], entitlements: body.groups[0].entitlements.slice(1) }] });
    expect(drop.status).toBe(409);
    expect(drop.body.error.details.entitlement_id).toBe(E(1));
    const unknownService = await put('/v1/admin/memberships/plans/gold', 'manager', { ...body, groups: [{ ...body.groups[0], entitlements: [{ ...body.groups[0].entitlements[0], service_codes: ['NOPE'] }] }] });
    expect(unknownService.status).toBe(400);
    const finance = await put('/v1/admin/memberships/plans/gold', 'finance', body);
    expect(finance.status).toBe(403);
    const missing = await put('/v1/admin/memberships/plans/diamond', 'admin', body);
    expect(missing.status).toBe(404);
  });

  it('accepts the black tier (4 tiers) in the loyalty draft and enforces route roles', async () => {
    const draft = await put('/v1/admin/loyalty/config/draft', 'manager', { tiers: [
      { tier: 'silver', name: 'Silver', min_points: 0, max_points: 499, earn_multiplier: 1, discount_pct: 0 },
      { tier: 'gold', name: 'Gold', min_points: 500, max_points: 1999, earn_multiplier: 1.25, discount_pct: 0 },
      { tier: 'platinum', name: 'Platinum', min_points: 2000, max_points: 4999, earn_multiplier: 1.5, discount_pct: 0 },
      { tier: 'black', name: 'Black', min_points: 5000, max_points: null, earn_multiplier: 1.75, discount_pct: 0 },
    ], rules: { points_per_rand: 0.1 } });
    expect(draft.status).toBe(200);
    expect(draft.body.draft.tiers.map((t: any) => t.tier)).toEqual(['silver', 'gold', 'platinum', 'black']);
    for (const [path, token, status] of [
      ['/v1/memberships/me', 'tech', 403],
      ['/v1/memberships/plans', 'admin', 403],
      ['/v1/admin/memberships', 'gold', 403],
      ['/v1/admin/memberships/plans', 'tech', 403],
      ['/v1/staff/customers/cust_gold/membership', 'gold', 403],
      ['/v1/memberships/me', 'gold', 200],
      ['/v1/admin/memberships', 'finance', 200],
    ] as const) {
      const r = await call(path, token);
      expect([path, token, r.status]).toEqual([path, token, status]);
    }
    const run = await post('/v1/admin/memberships/run-renewals', 'finance', {});
    expect(run.status).toBe(403);
    const anon = await fetch(`${base}/v1/memberships/me`);
    expect(anon.status).toBe(401);
  });
});
