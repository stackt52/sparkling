/**
 * Demo dataset mirroring backend/supabase/seed.sql + seed_catalogue.sql (South African sample data).
 * The outlet / service catalogue comes from `./catalogue` (generated from the real price sheets);
 * bookings, work orders and quotes are remapped onto the Pretoria / Potchefstroom outlets.
 * Times are relative to "today 10:00" local time so the dashboard always looks live.
 */
import {
  VAT_RATE,
  vehicleSizeOf,
  type AuditEvent,
  type BookingStatus,
  type ChecklistTemplate,
  type FeatureFlag,
  type InventoryItem,
  type LedgerEntry,
  type LoyaltyAccount,
  type LoyaltyConfig,
  type NotificationRow,
  type Outlet,
  type OutletLegal,
  type Payment,
  type PricingMode,
  type Profile,
  type Quotation,
  type Service,
  type UserRole,
  type VatMode,
  type Vehicle,
  type VehicleSize,
  type WorkOrder,
  type WorkStatus,
} from '../types';
import { CATALOGUE_COMPONENTS, CATALOGUE_OFFERS, CATALOGUE_OUTLETS, CATALOGUE_SERVICES, SVC_ID, type CatalogueComponent, type CatalogueOffer } from './catalogue';
import { MEMBERSHIPS, MEMBERSHIP_PAYMENTS, PLANS } from './memberships';

/* ---------- time helpers ---------- */
export const TEN = (() => {
  const d = new Date();
  d.setHours(10, 0, 0, 0);
  return d;
})();
export const at = (minutesFromTen: number) => new Date(TEN.getTime() + minutesFromTen * 60_000).toISOString();
/** Minutes relative to *now* (for live-feeling work orders, payments and activity). */
export const rel = (minutesFromNow: number) => new Date(Date.now() + minutesFromNow * 60_000).toISOString();
export const daysAgo = (days: number, hour = 12) => {
  const d = new Date();
  d.setDate(d.getDate() - days);
  d.setHours(hour, 0, 0, 0);
  return d.toISOString();
};
export const nowIso = () => new Date().toISOString();

/* deterministic PRNG so the demo is stable between reloads */
export function rng(seed: number) {
  let a = seed >>> 0;
  return () => {
    a = (a + 0x6d2b79f5) >>> 0;
    let t = a;
    t = Math.imul(t ^ (t >>> 15), t | 1);
    t ^= t + Math.imul(t ^ (t >>> 7), t | 61);
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
  };
}

/* ---------- outlets (docs/CATALOGUE.md) ---------- */
export const OUTLET_MEN = 'a0000000-0000-4000-8000-000000000001';
export const OUTLET_GLV = 'a0000000-0000-4000-8000-000000000002';
export const OUTLET_POT = 'a0000000-0000-4000-8000-000000000003';
export const OUTLET_TOT = 'a0000000-0000-4000-8000-000000000004';
export const OUTLET_RUS = 'a0000000-0000-4000-8000-000000000005';
const ALL_OUTLETS = [OUTLET_MEN, OUTLET_GLV, OUTLET_POT, OUTLET_TOT, OUTLET_RUS];

const hours = {
  mon: ['07:30', '17:30'] as [string, string],
  tue: ['07:30', '17:30'] as [string, string],
  wed: ['07:30', '17:30'] as [string, string],
  thu: ['07:30', '17:30'] as [string, string],
  fri: ['07:30', '17:30'] as [string, string],
  sat: ['08:00', '14:00'] as [string, string],
  sun: null,
};

/** Menlyn carries the legal / banking identity from the reference quotation (migration 0007). */
const MENLYN_LEGAL: OutletLegal = {
  legal_name: 'Izandra Trading 36 (Pty) Ltd',
  trading_as: 'Sparkling Auto Care Centre Menlyn',
  company_registration_no: '2006/024689/07',
  vat_number: '4310233384',
  registered_office: 'PO Box 238, Potchefstroom, North West, 2531, South Africa',
  bank_details: { financial_institution: 'FNB', account_name: 'Izandra Trading 36 (Pty) Ltd', branch: 'Menlyn', branch_code: '250655', account_number: '63041170711', account_type: 'Gold Business Account' },
};
/** The other outlets' legal fields are captured in Admin → Outlets (empty until then; trading_as = name). */
const emptyLegal = (name: string): OutletLegal => ({ legal_name: null, trading_as: name, company_registration_no: null, vat_number: null, registered_office: null, bank_details: null });

const RATINGS: Record<string, number> = { MEN: 4.8, GLV: 4.7, POT: 4.6, TOT: 4.5, RUS: 4.6 };
/** Short labels for chips / activity lines ("Menlyn", "Glen Village", …). */
export const OUTLET_SHORT: Record<string, string> = { MEN: 'Menlyn', GLV: 'Glen Village', POT: 'Potchefstroom', TOT: 'Amanzimtoti', RUS: 'Rustenburg' };

export const OUTLETS: Outlet[] = CATALOGUE_OUTLETS.map((o) => ({
  id: o.id, code: o.code, name: o.name, address_line: o.address_line, city: o.city, province: o.province, phone: o.phone, email: o.email,
  timezone: 'Africa/Johannesburg', opening_hours: { ...hours }, slot_minutes: 30, bay_count: o.bay_count, rating: RATINGS[o.code] ?? null, is_active: true,
  ...(o.code === 'MEN' ? MENLYN_LEGAL : emptyLegal(o.name)),
}));
export const outletName = (id: string) => OUTLETS.find((o) => o.id === id)?.name ?? 'Unknown outlet';
export const outletShort = (id: string) => {
  const o = OUTLETS.find((x) => x.id === id);
  return o ? (OUTLET_SHORT[o.code] ?? o.name.replace('Sparkling ', '')) : 'Unknown outlet';
};

/* ---------- templates ---------- */
export const TPL_VALET = 'c0000000-0000-4000-8000-000000000001';
export const TPL_EXPRESS = 'c0000000-0000-4000-8000-000000000002';
export const TPL_BODY = 'c0000000-0000-4000-8000-000000000003';

export const TEMPLATES: ChecklistTemplate[] = [
  { id: TPL_VALET, name: 'Sparkling Wash checklist', category: 'car_wash', version: 3, status: 'published', outlet_id: null, created_by: 'seed_admin', created_at: daysAgo(30), steps: [
    { key: 'prewash', title: 'Pre-wash inspection', type: 'photo', required: true, hint: 'Photograph all four sides before starting', photo_required: true },
    { key: 'exterior', title: 'Exterior wash & rinse', type: 'confirm', required: true },
    { key: 'wheels', title: 'Wheels, arches & tyre shine', type: 'confirm', required: true },
    { key: 'interior', title: 'Interior vacuum & dash', type: 'confirm', required: true, hint: 'Include boot and door pockets' },
    { key: 'windows', title: 'Windows inside & out', type: 'confirm', required: true },
    { key: 'tyre_pressure', title: 'Tyre pressure check', type: 'numeric', required: true, unit: 'bar', min: 1.5, max: 3.5, hint: 'Record front-left pressure' },
    { key: 'supervisor', title: 'Supervisor verification', type: 'supervisor_verify', required: true, hint: 'Locked until all required steps pass' },
  ] },
  { id: TPL_EXPRESS, name: 'Exterior wash checklist', category: 'car_wash', version: 2, status: 'published', outlet_id: null, created_by: 'seed_admin', created_at: daysAgo(45), steps: [
    { key: 'exterior', title: 'Exterior wash & rinse', type: 'confirm', required: true },
    { key: 'wheels', title: 'Wheels & tyres', type: 'confirm', required: true },
    { key: 'dry', title: 'Hand dry & windows', type: 'confirm', required: true },
    { key: 'supervisor', title: 'Supervisor verification', type: 'supervisor_verify', required: false },
  ] },
  { id: TPL_BODY, name: 'Auto body repair checklist', category: 'auto_body', version: 1, status: 'published', outlet_id: null, created_by: 'seed_admin', created_at: daysAgo(60), steps: [
    { key: 'intake', title: 'Damage intake photos', type: 'photo', required: true, photo_required: true },
    { key: 'prep', title: 'Panel prep & masking', type: 'confirm', required: true },
    { key: 'repair', title: 'Repair / filler / sanding', type: 'confirm', required: true },
    { key: 'paint', title: 'Paint & clear coat', type: 'select', required: true, options: ['Spot', 'Panel', 'Blend'] },
    { key: 'cure', title: 'Cure time (hours)', type: 'numeric', required: true, unit: 'h', min: 1, max: 48 },
    { key: 'polish', title: 'Polish & final photos', type: 'photo', required: true, photo_required: true },
    { key: 'supervisor', title: 'Supervisor verification', type: 'supervisor_verify', required: true },
  ] },
];

/* ---------- services (canonical catalogue, migration 0008) ---------- */
/** Service ids by code — see `SVC_ID` in ./catalogue for the full list. */
export const SVC = SVC_ID;

const EXPRESS_CODES = new Set(['WASH_GO', 'EXT_WASH', 'EXT_WASH_TYRE', 'EXT_WASH_TYRE_BUMPER', 'WASH_BIKE', 'WINDOWS_INSIDE']);
const templateFor = (code: string, category: Service['category']) => (category === 'auto_body' ? TPL_BODY : EXPRESS_CODES.has(code) ? TPL_EXPRESS : TPL_VALET);

export const SERVICES: Service[] = CATALOGUE_SERVICES.map((s) => ({
  id: s.id, code: s.code, name: s.name, description: s.description || null, category: s.category, group_name: s.group_name, duration_minutes: s.duration_minutes,
  base_price_cents: 0, is_quote_based: s.pricing_mode === 'by_quote', pricing_mode: s.pricing_mode, vat_mode: s.vat_mode,
  price_small_cents: null, price_large_cents: null, price_general_cents: null, is_addon: s.is_addon, addon_group_name: s.addon_group_name, notes: null,
  points_per_rand: 0.1, icon: s.icon, checklist_template_id: templateFor(s.code, s.category), is_active: true, sort_order: s.sort_order,
  components: CATALOGUE_COMPONENTS.filter((c) => c.outlet_id === null && c.parent_service_id === s.id).sort((a, b) => a.sort_order - b.sort_order).map((c) => ({ child_service_id: c.child_service_id, quantity: c.quantity, sort_order: c.sort_order })),
}));
export const serviceById = (id: string) => SERVICES.find((s) => s.id === id)!;

/** `outlet_services` rows (per-outlet wording, prices and overrides). */
export const OUTLET_OFFERS: CatalogueOffer[] = CATALOGUE_OFFERS;
/** Outlet-specific composite rows (`service_components` with `outlet_id`); the global set lives on `Service.components`. */
export const OUTLET_COMPONENTS: CatalogueComponent[] = CATALOGUE_COMPONENTS.filter((c) => c.outlet_id !== null);

export interface EffectivePricing {
  pricing_mode: PricingMode;
  vat_mode: VatMode;
  price_small_cents: number | null;
  price_large_cents: number | null;
  price_general_cents: number | null;
  /** Resolved per size (null when by-quote / no price). Bike uses the small price; large falls back to small. */
  price_for: Record<VehicleSize, number | null>;
  price_from_cents: number | null;
}

/** Pricing rules from docs/API.md "Catalogue pricing model": outlet override per size → service default; by_quote → no price. */
export function effectivePricing(s: Pick<Service, 'pricing_mode' | 'vat_mode' | 'price_small_cents' | 'price_large_cents' | 'price_general_cents'>, os: Pick<CatalogueOffer, 'pricing_mode' | 'vat_mode' | 'price_small_cents' | 'price_large_cents' | 'price_general_cents'> | null | undefined): EffectivePricing {
  const pricing_mode = os?.pricing_mode ?? s.pricing_mode;
  const vat_mode = os?.vat_mode ?? s.vat_mode;
  const small = os?.price_small_cents ?? s.price_small_cents;
  const large = os?.price_large_cents ?? s.price_large_cents;
  const general = os?.price_general_cents ?? s.price_general_cents;
  const price_for: Record<VehicleSize, number | null> = pricing_mode === 'by_quote'
    ? { small: null, large: null, bike: null }
    : { small: small ?? general, large: large ?? small ?? general, bike: small ?? general };
  const known = [price_for.small, price_for.large, price_for.bike].filter((x): x is number => x !== null);
  return { pricing_mode, vat_mode, price_small_cents: small, price_large_cents: large, price_general_cents: general, price_for, price_from_cents: known.length ? Math.min(...known) : null };
}

/** Seed-time price lookup (offer at the outlet, resolved for the size); throws so bad demo data is caught early. */
function priceAt(outletId: string, serviceId: string, size: VehicleSize): { price: number; vat_mode: VatMode; pricing_mode: PricingMode } {
  const s = serviceById(serviceId);
  const os = OUTLET_OFFERS.find((o) => o.outlet_id === outletId && o.service_id === serviceId);
  if (!os || !os.is_available) throw new Error(`demo seed: ${s.code} is not offered at ${outletShort(outletId)}`);
  const p = effectivePricing(s, os);
  const price = p.price_for[size];
  if (price === null) throw new Error(`demo seed: ${s.code} at ${outletShort(outletId)} has no ${size} price`);
  return { price, vat_mode: p.vat_mode, pricing_mode: p.pricing_mode };
}

/* ---------- people ---------- */
type DemoProfile = Profile & { outlet_ids: string[]; skills: string[]; availability?: 'available' | 'busy' | 'break' | 'off' };
const person = (id: string, role: UserRole, full_name: string, email: string, phone: string, outlet_ids: string[] = [], skills: string[] = [], availability?: DemoProfile['availability'], marketing = false): DemoProfile => ({
  id, role, full_name, email, phone, avatar_url: null, is_active: true, marketing_opt_in: marketing, whatsapp_opt_in: true, push_opt_in: true, last_seen_at: rel(-15), created_at: daysAgo(200), must_change_password: false, password_changed_at: daysAgo(199), outlet_ids, skills, availability,
});

export const DEMO_PROFILES: DemoProfile[] = [
  person('seed_admin', 'admin', 'Sparkling Admin', 'admin@sparklingauto.co.za', '+27 82 000 0001', ALL_OUTLETS),
  person('seed_finance', 'finance', 'Nomvula Finance', 'finance@sparklingauto.co.za', '+27 82 000 0002', ALL_OUTLETS),
  person('seed_ayesha', 'manager', 'Ayesha Patel', 'ayesha@sparklingauto.co.za', '+27 82 000 0010', [OUTLET_MEN, OUTLET_GLV]),
  person('seed_johan', 'supervisor', 'Johan Botha', 'johan@sparklingauto.co.za', '+27 82 000 0011', [OUTLET_MEN], [], 'available'),
  person('seed_pieter', 'technician', 'Pieter van der Merwe', 'pieter@sparklingauto.co.za', '+27 82 000 0012', [OUTLET_MEN], ['wash', 'detail'], 'available'),
  person('seed_lerato', 'technician', 'Lerato Mahlangu', 'lerato@sparklingauto.co.za', '+27 82 000 0013', [OUTLET_MEN], ['wash', 'interior'], 'busy'),
  person('seed_sipho_staff', 'technician', 'Sipho Ndlovu', 'sipho.n@sparklingauto.co.za', '+27 82 000 0014', [OUTLET_MEN], ['wash', 'paint', 'panel'], 'busy'),
  person('seed_thandi', 'technician', 'Thandi Khumalo', 'thandi@sparklingauto.co.za', '+27 82 000 0015', [OUTLET_GLV], ['wash'], 'available'),
  person('seed_thabo', 'customer', 'Thabo Nkosi', 'thabo@example.com', '+27 83 111 2222', [], [], undefined, true),
  person('seed_naledi', 'customer', 'Naledi Mokoena', 'naledi@example.com', '+27 83 111 3333'),
  person('seed_sipho', 'customer', 'Sipho Dlamini', 'sipho@example.com', '+27 83 111 4444', [], [], undefined, true),
  person('seed_zanele', 'customer', 'Zanele Mthembu', 'zanele@example.com', '+27 83 111 5555', [], [], undefined, true),
  person('seed_daniel', 'customer', 'Daniel Botha', 'daniel@example.com', '+27 83 111 6666'),
  person('seed_ayanda', 'customer', 'Ayanda Zulu', 'ayanda@example.com', '+27 83 111 7777'),
  person('seed_lindiwe', 'customer', 'Lindiwe Sithole', 'lindiwe@example.com', '+27 83 111 8888'),
  person('seed_kabelo', 'customer', 'Kabelo Molefe', 'kabelo@example.com', '+27 83 111 9999'),
];
export const profileById = (id: string) => DEMO_PROFILES.find((p) => p.id === id);
export const profileName = (id: string | null) => (id ? profileById(id)?.full_name ?? id : null);

/* ---------- vehicles ---------- */
const veh = (id: string, customer_id: string, reg: string, vin: string | null, make: string, model: string, colour: string, year: number, expiry: string, source: 'manual' | 'scan', size: VehicleSize): Vehicle => ({
  id, customer_id, registration_no: reg, vin, make, model, colour, year, disc_expiry: expiry, source, disc_verified: source === 'scan', size_class: size,
});
export const VEHICLES: Vehicle[] = [
  veh('d0000000-0000-4000-8000-000000000001', 'seed_thabo', 'KL 45 MN GP', 'AHTFB3CB301234567', 'Toyota', 'Corolla Cross', 'Celestite Grey', 2023, '2027-03-31', 'scan', 'small'),
  veh('d0000000-0000-4000-8000-000000000002', 'seed_thabo', 'CJ 12 PZ GP', 'WVWZZZ1KZ9W654321', 'Volkswagen', 'Polo Vivo', 'Reflex Silver', 2019, '2026-11-30', 'manual', 'small'),
  veh('d0000000-0000-4000-8000-000000000003', 'seed_naledi', 'HR 88 TS GP', 'MA3FB1B4200123456', 'Suzuki', 'Swift', 'Pearl Arctic White', 2022, '2027-01-31', 'scan', 'small'),
  veh('d0000000-0000-4000-8000-000000000004', 'seed_sipho', 'DN 07 KX GP', 'SB1KZ3BE10E234567', 'Toyota', 'Hilux', 'Glacier White', 2021, '2026-10-15', 'scan', 'large'),
  veh('d0000000-0000-4000-8000-000000000005', 'seed_zanele', 'BW 33 RG GP', 'WBA5R1C50KA112233', 'BMW', '330i', 'Portimao Blue', 2020, '2027-05-31', 'scan', 'small'),
  veh('d0000000-0000-4000-8000-000000000006', 'seed_daniel', 'CJ 118-334', null, 'Ford', 'Ranger', 'Frozen White', 2022, '2027-02-28', 'manual', 'large'),
  veh('d0000000-0000-4000-8000-000000000007', 'seed_ayanda', 'FT 21 GB GP', 'JTDKN3DU5A0123456', 'Hyundai', 'i20', 'Fiery Red', 2021, '2026-12-31', 'scan', 'small'),
  veh('d0000000-0000-4000-8000-000000000008', 'seed_lindiwe', 'HX 42 KL GP', 'KMHCT41BAFU123456', 'Kia', 'Sonet', 'Aurora Black', 2023, '2027-04-30', 'scan', 'small'),
  veh('d0000000-0000-4000-8000-000000000009', 'seed_kabelo', 'DR 88 SN GP', null, 'Mazda', 'CX-5', 'Soul Red', 2020, '2026-09-30', 'manual', 'large'),
];
export const vehicleById = (id: string) => VEHICLES.find((v) => v.id === id)!;

/* ---------- loyalty ---------- */
/**
 * Tier = membership plan (docs/MEMBERSHIPS.md): `discount_pct` is 0 for every tier — all discounts come
 * from the plan — and `min_points` / `max_points` are informational only (no points-based promotion).
 */
const TIERS = [
  { tier: 'silver' as const, name: 'Silver', min_points: 0, max_points: 499, earn_multiplier: 1.0, discount_pct: 0, perks: 'Free — earns points', members: 7214 },
  { tier: 'gold' as const, name: 'Gold', min_points: 500, max_points: 1999, earn_multiplier: 1.25, discount_pct: 0, perks: 'Gold plan', members: 1892 },
  { tier: 'platinum' as const, name: 'Platinum', min_points: 2000, max_points: 4999, earn_multiplier: 1.5, discount_pct: 0, perks: 'Platinum plan', members: 417 },
  { tier: 'black' as const, name: 'Black', min_points: 5000, max_points: null, earn_multiplier: 1.75, discount_pct: 0, perks: 'Black plan', members: 86 },
];
export const LOYALTY_CONFIGS: LoyaltyConfig[] = [
  {
    id: 'e0000000-0000-4000-8000-000000000014', version: 14, status: 'published',
    tiers: TIERS.map((t) => ({ ...t })),
    rules: { points_per_rand: 0.1, award_on: 'completion', idempotent_award: true, expiry_months: 24, birthday_bonus: { enabled: false, points: 100, reason: 'Pending consent review (ADM-042)' }, referral_bonus: { enabled: true, points: 150 } },
    change_note: 'Baseline tiers and earn rules', created_by: 'seed_admin', published_by: 'seed_admin', published_at: daysAgo(40), created_at: daysAgo(41),
  },
  {
    id: 'e0000000-0000-4000-8000-000000000015', version: 15, status: 'draft',
    tiers: TIERS.map((t) => (t.tier === 'gold' ? { ...t, earn_multiplier: 1.3, max_points: 1799 } : t.tier === 'platinum' ? { ...t, min_points: 1800 } : { ...t })),
    rules: { points_per_rand: 0.12, award_on: 'completion', idempotent_award: true, expiry_months: 24, birthday_bonus: { enabled: false, points: 100, reason: 'Pending consent review (ADM-042)' }, referral_bonus: { enabled: true, points: 200 } },
    change_note: 'Raise earn rate to 0.12/R and referral bonus to 200', created_by: 'seed_ayesha', published_by: null, published_at: null, created_at: daysAgo(2),
  },
];

/** The tier follows the live membership (trigger `memberships_sync_tier`); everyone else is silver. */
export function membershipTierOf(customerId: string): { tier: LoyaltyAccount['tier']; since: string } {
  const m = MEMBERSHIPS.find((x) => x.customer_id === customerId && ['pending', 'active', 'past_due'].includes(x.status));
  const plan = m ? PLANS.find((p) => p.id === m.plan_id) : undefined;
  return plan && m ? { tier: plan.tier, since: m.started_at } : { tier: 'silver', since: daysAgo(30) };
}
const acct = (customer_id: string, balance_points: number, lifetime_points: number, silverSinceDays: number): LoyaltyAccount => {
  const t = membershipTierOf(customer_id);
  return { customer_id, tier: t.tier, balance_points, lifetime_points, tier_since: t.tier === 'silver' ? daysAgo(silverSinceDays) : t.since };
};
export const LOYALTY_ACCOUNTS: LoyaltyAccount[] = [
  acct('seed_thabo', 1450, 1800, 95),
  acct('seed_naledi', 620, 620, 60),
  acct('seed_sipho', 2150, 2150, 150),
  acct('seed_zanele', 500, 500, 10),
  acct('seed_daniel', 120, 120, 20),
  acct('seed_ayanda', 260, 260, 80),
  acct('seed_lindiwe', 845, 845, 30),
  acct('seed_kabelo', 40, 40, 5),
];

const led = (i: number, customer_id: string, delta: number, type: LedgerEntry['type'], reference: string, description: string, key: string, days: number): LedgerEntry => ({
  id: `ll-${i}`, customer_id, delta, type, reference, description, idempotency_key: key, created_at: daysAgo(days),
});
export const LEDGER: LedgerEntry[] = [
  led(1, 'seed_thabo', 500, 'bonus', 'WELCOME', 'Welcome bonus', 'll-thabo-welcome', 120),
  led(2, 'seed_thabo', 380, 'earn', 'SPK-2026-0031', 'Auto detailing complete & polish', 'll-thabo-0031', 95),
  led(3, 'seed_thabo', 150, 'bonus', 'REF-NALEDI', 'Referral: Naledi M.', 'll-thabo-ref1', 70),
  led(4, 'seed_thabo', 120, 'earn', 'SPK-2026-0052', 'Exterior wash, tyre shine & bumper polish', 'll-thabo-0052', 40),
  led(5, 'seed_thabo', -350, 'redeem', 'RW-1182', 'Interior refresh', 'll-thabo-rw1182', 30),
  led(6, 'seed_thabo', 450, 'earn', 'SPK-2026-0067', 'Auto detailing complete & polish', 'll-thabo-0067', 21),
  led(7, 'seed_thabo', 200, 'earn', 'SPK-2026-0078', 'Sparkling Wash', 'll-thabo-0078', 9),
  led(8, 'seed_naledi', 500, 'bonus', 'WELCOME', 'Welcome bonus', 'll-naledi-welcome', 60),
  led(9, 'seed_naledi', 120, 'earn', 'SPK-2026-0092', 'Exterior wash, tyre shine & bumper polish', 'll-naledi-0092', 0),
  led(10, 'seed_sipho', 500, 'bonus', 'WELCOME', 'Welcome bonus', 'll-sipho-welcome', 200),
  led(11, 'seed_sipho', 1650, 'earn', 'SPK-2025-0410', '3 stage paint polishing & auto glaze', 'll-sipho-0410', 150),
  led(12, 'seed_zanele', 500, 'bonus', 'WELCOME', 'Welcome bonus', 'll-zanele-welcome', 10),
  led(13, 'seed_lindiwe', 500, 'bonus', 'WELCOME', 'Welcome bonus', 'll-lindiwe-welcome', 30),
  led(14, 'seed_lindiwe', 345, 'earn', 'SPK-2026-0071', 'Auto detailing complete & polish', 'll-lindiwe-0071', 12),
];

/* ---------- bookings ---------- */
export interface RawBooking {
  id: string;
  ref: string;
  customer_id: string;
  vehicle_id: string;
  outlet_id: string;
  service_id: string;
  slot_start: string;
  slot_end: string;
  status: BookingStatus;
  /** Base + add-ons (before discount and VAT). */
  price_cents: number;
  discount_cents: number;
  /** 15 % VAT on (price − discount) when `vat_mode === 'excl'`, else 0. */
  vat_cents: number;
  total_cents: number;
  discount_label: string | null;
  points_pending: number;
  notes: string | null;
  cancel_reason: string | null;
  created_at: string;
  quotation_id: string | null;
  /** Staff walk-in (STF-010/012). */
  walk_in?: boolean;
  created_by?: string | null;
  /* catalogue pricing (migration 0008) */
  vehicle_size: VehicleSize;
  pricing_mode: PricingMode;
  vat_mode: VatMode;
  addon_service_ids: string[];
  addons_cents: number;
  price_label: string | null;
  /* membership plans (migration 0010) */
  membership_id?: string | null;
  entitlement_id?: string | null;
  membership_benefit?: 'included' | 'discount' | null;
}

/**
 * Membership benefit applied to a seed booking (docs/MEMBERSHIPS.md pricing rules): `included` covers the
 * base price (add-ons still charged); `discount` takes the plan percentage off base + add-ons.
 */
type SeedBenefit =
  | { kind: 'included'; membership_id: string; entitlement_id: string; label: string }
  | { kind: 'discount'; membership_id: string; pct: number; label: string }
  | null;

/**
 * Builds a seed booking priced from the outlet's offer for the vehicle's size (+ add-ons, membership benefit,
 * VAT on `excl` prices). `fixedPrice` (quoted amounts, incl. VAT) bypasses the catalogue price.
 */
const bk = (n: number, ref: string, customer_id: string, vehicle_id: string, outlet_id: string, service_id: string, start: number, status: BookingStatus, benefit: SeedBenefit, created: string, opts: { addons?: string[]; fixedPrice?: number } = {}): RawBooking => {
  const s = serviceById(service_id);
  const size = vehicleSizeOf(vehicleById(vehicle_id));
  const base = opts.fixedPrice !== undefined ? { price: opts.fixedPrice, vat_mode: 'incl' as VatMode, pricing_mode: 'fixed' as PricingMode } : priceAt(outlet_id, service_id, size);
  const addons = (opts.addons ?? []).map((id) => priceAt(outlet_id, id, size).price);
  const addons_cents = addons.reduce((a, b) => a + b, 0);
  const price = base.price + addons_cents;
  const discount = benefit?.kind === 'included' ? base.price : benefit?.kind === 'discount' ? Math.round((price * benefit.pct) / 100) : 0;
  const vat = base.vat_mode === 'excl' ? Math.round((price - discount) * VAT_RATE) : 0;
  const total = price - discount + vat;
  const duration = s.duration_minutes + (opts.addons ?? []).reduce((d, id) => d + serviceById(id).duration_minutes, 0);
  return {
    id: `10000000-0000-4000-8000-${String(n).padStart(12, '0')}`, ref, customer_id, vehicle_id, outlet_id, service_id,
    slot_start: at(start), slot_end: at(start + duration), status, price_cents: price, discount_cents: discount, vat_cents: vat, total_cents: total,
    discount_label: benefit?.label ?? null, points_pending: Math.round((total / 100) * 0.1), notes: null, cancel_reason: null, created_at: created, quotation_id: null,
    vehicle_size: size, pricing_mode: base.pricing_mode, vat_mode: base.vat_mode, addon_service_ids: opts.addons ?? [], addons_cents,
    price_label: base.pricing_mode === 'by_quote' ? 'By quote' : base.pricing_mode === 'from' ? `From R ${Math.round(base.price / 100)}` : `R ${Math.round(base.price / 100)}`,
    membership_id: benefit?.membership_id ?? null, entitlement_id: benefit?.kind === 'included' ? benefit.entitlement_id : null, membership_benefit: benefit?.kind ?? null,
  };
};
const MEM_THABO = 'c4000000-0000-4000-8000-000000000001';
const MEM_ZANELE = 'c4000000-0000-4000-8000-000000000004';
/** Thabo's Gold G1 wash (1 of 4 used this period) and Zanele's Black B3 detail (1 of 1) — see ./memberships USAGE. */
const THABO_WASH: SeedBenefit = { kind: 'included', membership_id: MEM_THABO, entitlement_id: 'c3000000-0000-4000-8000-000000000001', label: 'Included in Gold · 3 of 4 left' };
const THABO_OTHER: SeedBenefit = { kind: 'discount', membership_id: MEM_THABO, pct: 10, label: 'Gold −10%' };
const ZANELE_DETAIL: SeedBenefit = { kind: 'included', membership_id: MEM_ZANELE, entitlement_id: 'c3000000-0000-4000-8000-000000000007', label: 'Included in Black · 0 of 1 left' };

export const SEED_BOOKINGS: RawBooking[] = [
  bk(1, 'SPK-2026-0091', 'seed_thabo', 'd0000000-0000-4000-8000-000000000001', OUTLET_MEN, SVC.SPARKLING_WASH, 0, 'in_service', THABO_WASH, daysAgo(2)),
  bk(2, 'SPK-2026-0094', 'seed_thabo', 'd0000000-0000-4000-8000-000000000002', OUTLET_GLV, SVC.WASH_GO, 23 * 60, 'confirmed', null, daysAgo(0, 7)),
  bk(3, 'SPK-2026-0067', 'seed_thabo', 'd0000000-0000-4000-8000-000000000001', OUTLET_MEN, SVC.AUTO_DETAIL_COMPLETE, -21 * 24 * 60, 'completed', THABO_OTHER, daysAgo(24)),
  bk(4, 'SPK-2026-0052', 'seed_thabo', 'd0000000-0000-4000-8000-000000000002', OUTLET_MEN, SVC.EXT_WASH_TYRE_BUMPER, -38 * 24 * 60, 'completed', null, daysAgo(40)),
  bk(5, 'SPK-2026-0092', 'seed_naledi', 'd0000000-0000-4000-8000-000000000003', OUTLET_MEN, SVC.EXT_WASH_TYRE_BUMPER, -90, 'completed', null, daysAgo(1)),
  bk(6, 'SPK-2026-0093', 'seed_sipho', 'd0000000-0000-4000-8000-000000000004', OUTLET_MEN, SVC.AUTO_DETAIL_INTERIOR, 30, 'in_service', null, daysAgo(1), { addons: [SVC.ADDON_ODOUR] }),
  bk(7, 'SPK-2026-0095', 'seed_zanele', 'd0000000-0000-4000-8000-000000000005', OUTLET_MEN, SVC.AUTO_DETAIL_COMPLETE, 120, 'confirmed', ZANELE_DETAIL, daysAgo(0, 8)),
  bk(8, 'SPK-2026-0096', 'seed_naledi', 'd0000000-0000-4000-8000-000000000003', OUTLET_GLV, SVC.SPARKLING_WASH, 180, 'pending', null, daysAgo(0, 9)),
  bk(9, 'SPK-2026-0090', 'seed_sipho', 'd0000000-0000-4000-8000-000000000004', OUTLET_MEN, SVC.EXT_WASH_TYRE_BUMPER, -180, 'cancelled', null, daysAgo(1)),
  bk(10, 'SPK-2026-0089', 'seed_daniel', 'd0000000-0000-4000-8000-000000000006', OUTLET_MEN, SVC.BUMPER_SCUFF, -60, 'confirmed', null, daysAgo(1), { fixedPrice: 385000 }),
  bk(11, 'SPK-2026-0088', 'seed_ayanda', 'd0000000-0000-4000-8000-000000000007', OUTLET_MEN, SVC.SPARKLING_WASH, -45, 'completed', null, daysAgo(1)),
  bk(12, 'SPK-2026-0087', 'seed_lindiwe', 'd0000000-0000-4000-8000-000000000008', OUTLET_GLV, SVC.WASH_GO, 30, 'in_service', null, daysAgo(1)),
  bk(13, 'SPK-2026-0086', 'seed_kabelo', 'd0000000-0000-4000-8000-000000000009', OUTLET_POT, SVC.EXT_WASH_TYRE, -120, 'completed', null, daysAgo(2)),
];
const totalOf = (ref: string) => SEED_BOOKINGS.find((b) => b.ref === ref)!.total_cents;

/** Priced services bound at an outlet (seed helper for the generated bookings). */
function boundAt(outletId: string, ids: string[]): string[] {
  return ids.filter((id) => OUTLET_OFFERS.some((o) => o.outlet_id === outletId && o.service_id === id && o.is_available && (o.pricing_mode ?? serviceById(id).pricing_mode) !== 'by_quote'));
}

/** Extra today's bookings so the by-hour chart and live table look busy (deterministic). */
export function generateExtraBookings(): RawBooking[] {
  const r = rng(20260908);
  const customers = DEMO_PROFILES.filter((p) => p.role === 'customer');
  const out: RawBooking[] = [];
  let n = 100;
  const plan: { hour: number; count: number }[] = [
    { hour: 7, count: 3 }, { hour: 8, count: 5 }, { hour: 9, count: 7 }, { hour: 10, count: 8 }, { hour: 11, count: 7 },
    { hour: 12, count: 5 }, { hour: 13, count: 4 }, { hour: 14, count: 5 }, { hour: 15, count: 4 }, { hour: 16, count: 3 },
  ];
  const WASHES = [SVC.WASH_GO, SVC.EXT_WASH_TYRE_BUMPER, SVC.EXT_WASH_TYRE, SVC.SPARKLING_WASH, SVC.SPARKLING_WASH, SVC.EXEC_WASH, SVC.AUTO_DETAIL_COMPLETE, SVC.AUTO_DETAIL_INTERIOR];
  const BODY = [SVC.PDR, SVC.SPOT_REPAIR, SVC.BUMPER_SCUFF, SVC.HEADLIGHT_RENEWAL];
  for (const { hour, count } of plan) {
    for (let i = 0; i < count; i++) {
      const c = customers[Math.floor(r() * customers.length)];
      const v = VEHICLES.find((x) => x.customer_id === c.id) ?? VEHICLES[0];
      const outlet = [OUTLET_MEN, OUTLET_MEN, OUTLET_GLV, OUTLET_POT][Math.floor(r() * 4)];
      const isBody = r() < 0.22;
      const pool = boundAt(outlet, isBody ? BODY : WASHES);
      const service = pool[Math.floor(r() * pool.length)];
      const s = serviceById(service);
      const startMin = (hour - 10) * 60 + [0, 15, 30, 45][Math.floor(r() * 4)];
      const nowMin = (Date.now() - TEN.getTime()) / 60_000;
      let status: BookingStatus;
      if (startMin + s.duration_minutes < nowMin - 10) status = r() < 0.9 ? 'completed' : 'cancelled';
      else if (startMin <= nowMin) status = 'in_service';
      else status = r() < 0.85 ? 'confirmed' : 'pending';
      n += 1;
      // Generated fillers are priced without membership benefits (the seed memberships' usage is fixed in ./memberships).
      out.push(bk(n, `SPK-2026-${String(n).padStart(4, '0')}`, c.id, v.id, outlet, service, startMin, status, null, daysAgo(1 + Math.floor(r() * 3))));
    }
  }
  return out;
}

/* ---------- quotations ---------- */
const MEN_REF = { id: OUTLET_MEN, name: outletName(OUTLET_MEN) };
const GLV_REF = { id: OUTLET_GLV, name: outletName(OUTLET_GLV) };
export const QUOTATIONS: Quotation[] = [
  { id: '20000000-0000-4000-8000-000000000001', ref: 'QT-2026-0041', customer_id: 'seed_thabo', customer_name: 'Thabo Nkosi', vehicle: { id: 'd0000000-0000-4000-8000-000000000001', registration_no: 'KL 45 MN GP', make: 'Toyota', model: 'Corolla Cross' }, outlet: MEN_REF, category: 'Bumper', description: 'Rear bumper scuffed in parking lot, paint cracked on left corner.', status: 'quoted', amount_cents: 385000, line_items: [{ label: 'Bumper repair & respray', description: 'Rear bumper, left corner: fill cracked paint, sand and respray in Celestite Grey.', category: 'bumper', service_id: SVC.BUMPER_SCUFF, amount_cents: 320000 }, { label: 'Blend to quarter panel', description: 'Blend the new paint into the left rear quarter panel so the repair is invisible.', category: 'paint', service_id: SVC.SPOT_REPAIR, amount_cents: 65000 }], items_note: 'Allow 3 working days. Courtesy wash included on collection.', assessor_id: 'seed_sipho_staff', assessor_name: 'Sipho Ndlovu', valid_until: daysAgo(-14).slice(0, 10), quoted_at: daysAgo(1), decided_at: null, decision_note: null, decision_source: null, decision_by_name: null, attachments: [{ id: 'att-1', kind: 'damage_photo', url: '/demo/damage-1.svg', caption: 'Rear bumper — left corner', width: 800, height: 600, mime_type: 'image/svg+xml', storage_path: 'quotations/qt41/front.jpg' }, { id: 'att-2', kind: 'damage_photo', url: '/demo/damage-2.svg', caption: 'Close-up of cracked paint', width: 800, height: 600, mime_type: 'image/svg+xml', storage_path: 'quotations/qt41/side.jpg' }], created_at: daysAgo(2) },
  { id: '20000000-0000-4000-8000-000000000002', ref: 'QT-2026-0042', customer_id: 'seed_zanele', customer_name: 'Zanele Mthembu', vehicle: { id: 'd0000000-0000-4000-8000-000000000005', registration_no: 'BW 33 RG GP', make: 'BMW', model: '330i' }, outlet: MEN_REF, category: 'Dent', description: 'Door ding on driver door, no paint damage.', status: 'requested', amount_cents: null, line_items: [], assessor_id: null, assessor_name: null, valid_until: null, quoted_at: null, decided_at: null, decision_note: null, attachments: [{ id: 'att-3', kind: 'damage_photo', url: '/demo/damage-2.svg', caption: 'Driver door', width: 800, height: 600, mime_type: 'image/svg+xml', storage_path: 'quotations/qt42/door.jpg' }], created_at: rel(-200) },
  { id: '20000000-0000-4000-8000-000000000003', ref: 'QT-2026-0038', customer_id: 'seed_sipho', customer_name: 'Sipho Dlamini', vehicle: { id: 'd0000000-0000-4000-8000-000000000004', registration_no: 'DN 07 KX GP', make: 'Toyota', model: 'Hilux' }, outlet: MEN_REF, category: 'Scratch', description: 'Key scratch along passenger side.', status: 'converted', amount_cents: 210000, line_items: [{ label: 'Scratch repair & blend', service_id: SVC.SPOT_REPAIR, amount_cents: 210000 }], assessor_id: 'seed_sipho_staff', assessor_name: 'Sipho Ndlovu', valid_until: daysAgo(-7).slice(0, 10), quoted_at: daysAgo(4), decided_at: daysAgo(2), decision_note: 'Go ahead', decision_source: 'app', decision_by_name: 'Sipho Dlamini', attachments: [], created_at: daysAgo(5), work_order_ref: 'WO-2026-4818' },
  { id: '20000000-0000-4000-8000-000000000004', ref: 'QT-2026-0039', customer_id: 'seed_daniel', customer_name: 'Daniel Botha', vehicle: { id: 'd0000000-0000-4000-8000-000000000006', registration_no: 'CJ 118-334', make: 'Ford', model: 'Ranger' }, outlet: MEN_REF, category: 'Panel', description: 'Tailgate dented and scratched from towing accident.', status: 'accepted', amount_cents: 485000, line_items: [{ label: 'Tailgate panel repair', service_id: SVC.PDR, amount_cents: 385000 }, { label: 'Respray & blend', service_id: SVC.SPOT_REPAIR, amount_cents: 100000 }], assessor_id: 'seed_sipho_staff', assessor_name: 'Sipho Ndlovu', valid_until: daysAgo(-10).slice(0, 10), quoted_at: daysAgo(3), decided_at: rel(-130), decision_note: null, decision_source: 'app', decision_by_name: 'Daniel Botha', attachments: [], created_at: daysAgo(4) },
  { id: '20000000-0000-4000-8000-000000000005', ref: 'QT-2026-0037', customer_id: 'seed_ayanda', customer_name: 'Ayanda Zulu', vehicle: { id: 'd0000000-0000-4000-8000-000000000007', registration_no: 'FT 21 GB GP', make: 'Hyundai', model: 'i20' }, outlet: GLV_REF, category: 'Glass', description: 'Windscreen chip on passenger side.', status: 'declined', amount_cents: 95000, line_items: [{ label: 'Windscreen chip repair', service_id: SVC.WINDSHIELD_REPAIR, amount_cents: 95000 }], assessor_id: 'seed_thandi', assessor_name: 'Thandi Khumalo', valid_until: daysAgo(-3).slice(0, 10), quoted_at: daysAgo(6), decided_at: daysAgo(5), decision_note: 'Going through insurance', decision_source: 'app', decision_by_name: 'Ayanda Zulu', attachments: [], created_at: daysAgo(7) },
];

/* ---------- work orders ---------- */
const wo = (id: string, ref: string, outlet_id: string, booking_ref: string | null, quotation_ref: string | null, customer: string, vehicle_id: string, service_id: string, status: WorkStatus, priority: 1 | 2 | 3, bay: string | null, tpl: string, assignee: string | null, eta: number | null, due: number | null, started: number | null, blocked: string | null, stepsDone: number): WorkOrder => {
  const t = TEMPLATES.find((x) => x.id === tpl)!;
  const v = vehicleById(vehicle_id);
  const s = serviceById(service_id);
  return {
    id, ref, outlet: { id: outlet_id, name: outletName(outlet_id) }, booking_ref, quotation_ref, customer_name: profileName(customer) ?? customer,
    vehicle: { registration_no: v.registration_no, make: v.make, model: v.model }, service: { name: s.name, category: s.category }, status, priority, bay,
    assignee_id: assignee, assignee_name: profileName(assignee), eta_at: eta === null ? null : rel(eta), due_at: due === null ? null : rel(due), started_at: started === null ? null : rel(started),
    blocked_reason: blocked, steps_done: stepsDone, step_count: t.steps.length, task_id: id.replace('30000000', '40000000'), events: [], updated_at: rel(-1),
  };
};

export const WORK_ORDERS: WorkOrder[] = [
  wo('30000000-0000-4000-8000-000000000001', 'WO-2026-4821', OUTLET_MEN, 'SPK-2026-0091', null, 'seed_thabo', 'd0000000-0000-4000-8000-000000000001', SVC.SPARKLING_WASH, 'in_progress', 1, 'Bay 2', TPL_VALET, 'seed_pieter', 20, 25, -30, null, 4),
  wo('30000000-0000-4000-8000-000000000002', 'WO-2026-4822', OUTLET_MEN, 'SPK-2026-0092', null, 'seed_naledi', 'd0000000-0000-4000-8000-000000000003', SVC.EXT_WASH_TYRE_BUMPER, 'verified', 2, 'Bay 1', TPL_EXPRESS, 'seed_lerato', -70, -70, -90, null, 4),
  wo('30000000-0000-4000-8000-000000000003', 'WO-2026-4823', OUTLET_MEN, 'SPK-2026-0093', null, 'seed_sipho', 'd0000000-0000-4000-8000-000000000004', SVC.AUTO_DETAIL_INTERIOR, 'blocked', 1, 'Bay 3', TPL_VALET, 'seed_lerato', 85, 85, -45, 'Out of interior shampoo — substitute stock needed', 2),
  wo('30000000-0000-4000-8000-000000000004', 'WO-2026-4824', OUTLET_MEN, 'SPK-2026-0095', null, 'seed_zanele', 'd0000000-0000-4000-8000-000000000005', SVC.AUTO_DETAIL_COMPLETE, 'queued', 2, null, TPL_VALET, null, 240, 240, null, null, 0),
  wo('30000000-0000-4000-8000-000000000005', 'WO-2026-4818', OUTLET_MEN, null, 'QT-2026-0038', 'seed_sipho', 'd0000000-0000-4000-8000-000000000004', SVC.SPOT_REPAIR, 'assigned', 2, 'Body 1', TPL_BODY, 'seed_sipho_staff', 2 * 24 * 60, -12, null, null, 0),
  wo('30000000-0000-4000-8000-000000000006', 'WO-2026-4820', OUTLET_MEN, 'SPK-2026-0088', null, 'seed_ayanda', 'd0000000-0000-4000-8000-000000000007', SVC.SPARKLING_WASH, 'completed', 2, 'Bay 4', TPL_VALET, 'seed_pieter', -5, 15, -50, null, 7),
  wo('30000000-0000-4000-8000-000000000007', 'WO-2026-4825', OUTLET_GLV, 'SPK-2026-0087', null, 'seed_lindiwe', 'd0000000-0000-4000-8000-000000000008', SVC.WASH_GO, 'in_progress', 2, 'Bay 1', TPL_EXPRESS, 'seed_thandi', 12, 15, -8, null, 1),
  wo('30000000-0000-4000-8000-000000000008', 'WO-2026-4819', OUTLET_MEN, 'SPK-2026-0089', null, 'seed_daniel', 'd0000000-0000-4000-8000-000000000006', SVC.BUMPER_SCUFF, 'assigned', 3, 'Body 2', TPL_BODY, 'seed_sipho_staff', 3 * 24 * 60, 3 * 24 * 60, null, null, 0),
];
WORK_ORDERS[0].events = [
  { id: 'te-1', actor_name: 'Johan Botha', event: 'assigned', from_status: 'queued', to_status: 'assigned', reason: 'Auto-assign: skill match, lowest load', created_at: rel(-40) },
  { id: 'te-2', actor_name: 'Pieter van der Merwe', event: 'transition', from_status: 'assigned', to_status: 'in_progress', reason: null, created_at: rel(-30) },
];
WORK_ORDERS[2].events = [
  { id: 'te-3', actor_name: 'Lerato Mahlangu', event: 'transition', from_status: 'in_progress', to_status: 'blocked', reason: 'Out of interior shampoo — substitute stock needed', created_at: rel(-24) },
];
WORK_ORDERS[1].events = [
  { id: 'te-4', actor_name: 'Johan Botha', event: 'transition', from_status: 'completed', to_status: 'verified', reason: 'Checklist compliant', created_at: rel(-70) },
];

/* ---------- payments (amounts follow the booking totals so receipts reconcile) ---------- */
export const PAYMENTS: Payment[] = [
  { id: '60000000-0000-4000-8000-000000000001', booking_ref: 'SPK-2026-0091', customer_name: 'Thabo Nkosi', provider: 'sandbox', amount_cents: totalOf('SPK-2026-0091'), status: 'successful', receipt_no: 'RCP-70001', verified_at: daysAgo(2), created_at: daysAgo(2) },
  { id: '60000000-0000-4000-8000-000000000002', booking_ref: 'SPK-2026-0067', customer_name: 'Thabo Nkosi', provider: 'sandbox', amount_cents: totalOf('SPK-2026-0067'), status: 'successful', receipt_no: 'RCP-70002', verified_at: daysAgo(24), created_at: daysAgo(24) },
  { id: '60000000-0000-4000-8000-000000000003', booking_ref: 'SPK-2026-0052', customer_name: 'Thabo Nkosi', provider: 'sandbox', amount_cents: totalOf('SPK-2026-0052'), status: 'successful', receipt_no: 'RCP-70003', verified_at: daysAgo(40), created_at: daysAgo(40) },
  { id: '60000000-0000-4000-8000-000000000004', booking_ref: 'SPK-2026-0092', customer_name: 'Naledi Mokoena', provider: 'sandbox', amount_cents: totalOf('SPK-2026-0092'), status: 'successful', receipt_no: 'RCP-70004', verified_at: rel(-80), created_at: rel(-85) },
  { id: '60000000-0000-4000-8000-000000000005', booking_ref: 'SPK-2026-0095', customer_name: 'Zanele Mthembu', provider: 'sandbox', amount_cents: totalOf('SPK-2026-0095'), status: 'pending', receipt_no: null, verified_at: null, created_at: rel(-30) },
  { id: '60000000-0000-4000-8000-000000000006', booking_ref: 'SPK-2026-0094', customer_name: 'Thabo Nkosi', provider: 'sandbox', amount_cents: totalOf('SPK-2026-0094'), status: 'successful', receipt_no: 'RCP-70005', verified_at: rel(-180), created_at: rel(-180) },
  { id: '60000000-0000-4000-8000-000000000007', booking_ref: 'SPK-2026-0093', customer_name: 'Sipho Dlamini', provider: 'sandbox', amount_cents: totalOf('SPK-2026-0093'), status: 'failed', receipt_no: null, verified_at: null, created_at: rel(-40) },
  { id: '60000000-0000-4000-8000-000000000008', booking_ref: 'SPK-2026-0088', customer_name: 'Ayanda Zulu', provider: 'sandbox', amount_cents: totalOf('SPK-2026-0088'), status: 'successful', receipt_no: 'RCP-70006', verified_at: rel(-50), created_at: rel(-55) },
  // Membership invoice payments (`membership_invoice_id` set, no booking).
  ...MEMBERSHIP_PAYMENTS,
];

/* ---------- inventory ---------- */
const inv = (id: string, outlet_id: string, sku: string, name: string, unit: string, on_hand: number, threshold: number, pack: number, capacity: number): InventoryItem => ({
  id, outlet_id, outlet_name: outletShort(outlet_id), sku, name, unit, on_hand, reorder_threshold: threshold, pack_size: pack, capacity, is_active: true, alert: null, blocking_work_orders: 0, updated_at: rel(-15),
});
export const INVENTORY: InventoryItem[] = [
  inv('70000000-0000-4000-8000-000000000001', OUTLET_MEN, 'SHP-INT', 'Interior shampoo 5L', 'bottle', 0, 4, 5, 8),
  inv('70000000-0000-4000-8000-000000000002', OUTLET_MEN, 'WAX-CRN', 'Carnauba wax 500ml', 'tin', 3, 6, 1, 14),
  inv('70000000-0000-4000-8000-000000000003', OUTLET_MEN, 'TWL-MF', 'Microfibre towels', 'pack', 18, 10, 20, 24),
  inv('70000000-0000-4000-8000-000000000004', OUTLET_MEN, 'TYR-SHN', 'Tyre shine 1L', 'bottle', 9, 4, 1, 16),
  inv('70000000-0000-4000-8000-000000000005', OUTLET_MEN, 'SNW-FOAM', 'Snow foam 5L', 'bottle', 12, 5, 5, 16),
  inv('70000000-0000-4000-8000-000000000006', OUTLET_MEN, 'GLS-CLN', 'Glass cleaner 1L', 'bottle', 7, 4, 1, 12),
  inv('70000000-0000-4000-8000-000000000007', OUTLET_MEN, 'PNT-CLR', 'Clear coat 1L', 'tin', 5, 3, 1, 8),
  inv('70000000-0000-4000-8000-000000000011', OUTLET_GLV, 'SHP-INT', 'Interior shampoo 5L', 'bottle', 6, 4, 5, 8),
  inv('70000000-0000-4000-8000-000000000012', OUTLET_GLV, 'WAX-CRN', 'Carnauba wax 500ml', 'tin', 8, 6, 1, 14),
  inv('70000000-0000-4000-8000-000000000013', OUTLET_GLV, 'TWL-MF', 'Microfibre towels', 'pack', 4, 10, 20, 24),
  inv('70000000-0000-4000-8000-000000000021', OUTLET_POT, 'SNW-FOAM', 'Snow foam 5L', 'bottle', 15, 5, 5, 16),
  inv('70000000-0000-4000-8000-000000000022', OUTLET_POT, 'TYR-SHN', 'Tyre shine 1L', 'bottle', 1, 4, 1, 16),
];

/* ---------- badges ---------- */
export const BADGES = [
  { code: 'FIRST_50', name: 'Half century', icon: 'military_tech', colour: '#E2BA5F' },
  { code: 'STREAK_5', name: 'On a roll', icon: 'local_fire_department', colour: '#FF7A59' },
  { code: 'SPOTLESS', name: 'Spotless', icon: 'verified', colour: '#1D8A4E' },
  { code: 'SCANNER', name: 'Sharp eye', icon: 'qr_code_scanner', colour: '#00A0E0' },
  { code: 'MENTOR', name: 'Mentor', icon: 'groups', colour: '#8BD2FF' },
  { code: 'TOP_MONTH', name: 'Top of the month', icon: 'social_leaderboard', colour: '#F3DDA4' },
];
export const STAFF_BADGES: Record<string, { code: string; days: number }[]> = {
  seed_pieter: [{ code: 'FIRST_50', days: 20 }, { code: 'STREAK_5', days: 3 }, { code: 'SCANNER', days: 12 }],
  seed_lerato: [{ code: 'FIRST_50', days: 30 }, { code: 'SPOTLESS', days: 6 }],
  seed_sipho_staff: [{ code: 'FIRST_50', days: 50 }],
  seed_thandi: [],
};

/* ---------- flags & audit ---------- */
export const FLAGS: FeatureFlag[] = [
  { key: 'payments_sandbox', enabled: true, description: 'Use the sandbox payment provider (no real charges)', updated_at: daysAgo(30) },
  { key: 'whatsapp_enabled', enabled: false, description: 'Send WhatsApp Business notifications', updated_at: daysAgo(30) },
  { key: 'auto_assignment', enabled: true, description: 'Automatically assign queued work orders to available staff', updated_at: daysAgo(12) },
  { key: 'birthday_bonus', enabled: false, description: 'Award birthday loyalty bonus (pending consent review)', updated_at: daysAgo(5) },
];

export const AUDIT: AuditEvent[] = [
  { id: 'au-1', actor_id: 'seed_admin', actor_name: 'Sparkling Admin', actor_role: 'admin', action: 'loyalty_config.publish', entity_type: 'loyalty_config', entity_id: 'e0000000-0000-4000-8000-000000000014', outlet_id: null, before: { version: 13 }, after: { version: 14 }, correlation_id: 'seed-corr-1', outcome: 'ok', created_at: daysAgo(40) },
  { id: 'au-2', actor_id: 'seed_ayesha', actor_name: 'Ayesha Patel', actor_role: 'manager', action: 'loyalty_config.draft', entity_type: 'loyalty_config', entity_id: 'e0000000-0000-4000-8000-000000000015', outlet_id: null, before: null, after: { version: 15 }, correlation_id: 'seed-corr-2', outcome: 'ok', created_at: daysAgo(2) },
  { id: 'au-3', actor_id: 'seed_johan', actor_name: 'Johan Botha', actor_role: 'supervisor', action: 'task.assign', entity_type: 'task', entity_id: '40000000-0000-4000-8000-000000000001', outlet_id: OUTLET_MEN, before: { assignee: null }, after: { assignee: 'seed_pieter' }, correlation_id: 'seed-corr-3', outcome: 'ok', created_at: rel(-40) },
  { id: 'au-4', actor_id: 'seed_ayesha', actor_name: 'Ayesha Patel', actor_role: 'manager', action: 'inventory.threshold', entity_type: 'inventory_item', entity_id: '70000000-0000-4000-8000-000000000001', outlet_id: OUTLET_MEN, before: { reorder_threshold: 3 }, after: { reorder_threshold: 4 }, correlation_id: 'seed-corr-4', outcome: 'ok', created_at: daysAgo(10) },
  { id: 'au-5', actor_id: 'seed_admin', actor_name: 'Sparkling Admin', actor_role: 'admin', action: 'user.update', entity_type: 'profile', entity_id: 'seed_thandi', outlet_id: OUTLET_GLV, before: { outlet_ids: [] }, after: { outlet_ids: [OUTLET_GLV] }, correlation_id: 'seed-corr-5', outcome: 'ok', created_at: daysAgo(14) },
  { id: 'au-6', actor_id: 'seed_ayesha', actor_name: 'Ayesha Patel', actor_role: 'manager', action: 'customer.view', entity_type: 'profile', entity_id: 'seed_thabo', outlet_id: null, before: null, after: { reason: 'support call' }, correlation_id: 'seed-corr-6', outcome: 'ok', created_at: daysAgo(1) },
  { id: 'au-7', actor_id: 'seed_admin', actor_name: 'Sparkling Admin', actor_role: 'admin', action: 'flag.update', entity_type: 'feature_flag', entity_id: 'auto_assignment', outlet_id: null, before: { enabled: false }, after: { enabled: true }, correlation_id: 'seed-corr-7', outcome: 'ok', created_at: daysAgo(12) },
  { id: 'au-8', actor_id: 'seed_johan', actor_name: 'Johan Botha', actor_role: 'supervisor', action: 'task.transition', entity_type: 'task', entity_id: '40000000-0000-4000-8000-000000000002', outlet_id: OUTLET_MEN, before: { status: 'completed' }, after: { status: 'verified' }, correlation_id: 'seed-corr-8', outcome: 'ok', created_at: rel(-70) },
  { id: 'au-9', actor_id: 'seed_admin', actor_name: 'Sparkling Admin', actor_role: 'admin', action: 'outlet_service.update', entity_type: 'outlet_service', entity_id: `${OUTLET_GLV}:${SVC.SPARKLING_WASH}`, outlet_id: OUTLET_GLV, before: { price_small_cents: 15000 }, after: { price_small_cents: 16000 }, correlation_id: 'seed-corr-9', outcome: 'ok', created_at: daysAgo(6) },
];

/* ---------- notifications (NOT-003 / WhatsApp via Twilio) ---------- */
const note = (
  id: string, recipient_id: string, channel: NotificationRow['channel'], template_key: string, title: string | null, body: string,
  status: NotificationRow['status'], minutesAgo: number,
  extra: Partial<NotificationRow> = {},
): NotificationRow => ({
  id, recipient_id, recipient_name: profileName(recipient_id), channel, template_key, title, body, payload: {}, status,
  provider_status: channel === 'whatsapp' ? (status === 'queued' ? 'queued' : status === 'failed' ? 'undelivered' : status) : null,
  provider_ref: channel === 'whatsapp' ? `SM${id.replace(/-/g, '').padEnd(32, '0').slice(0, 32)}` : null,
  provider_error_code: null, error: null, attempts: status === 'queued' ? 0 : 1,
  sent_at: status === 'queued' ? null : rel(-minutesAgo), delivered_at: status === 'delivered' ? rel(-minutesAgo + 1) : null,
  read_at: null, created_at: rel(-minutesAgo), ...extra,
});

/** Mirrors the sparkling_core demo seed plus one failed WhatsApp row (Twilio 63016 — outside the 24 h session). */
export const NOTIFICATIONS: NotificationRow[] = [
  note('c0000000-0000-4000-8000-00000000n001', 'seed_thabo', 'push', 'service_started', 'Service started', 'Your Toyota Corolla Cross is now in Bay 2.', 'sent', 25, { payload: { type: 'booking', id: '10000000-0000-4000-8000-000000000001' } }),
  note('c0000000-0000-4000-8000-00000000n002', 'seed_thabo', 'whatsapp', 'booking_confirmed', null, `Hi Thabo, your Sparkling booking SPK-2026-0094 is confirmed for tomorrow 09:00 at ${outletName(OUTLET_GLV)}.`, 'delivered', 180, { read_at: rel(-120), payload: { type: 'booking', id: '10000000-0000-4000-8000-000000000002' } }),
  note('c0000000-0000-4000-8000-00000000n003', 'seed_thabo', 'whatsapp', 'pickup_otp', 'Ready for collection', `Your Volkswagen Polo Vivo is ready at ${outletName(OUTLET_MEN)}. Collection OTP: 73104 — show it at the counter to collect your keys.`, 'delivered', 100, { read_at: rel(-95), payload: { type: 'booking', id: '10000000-0000-4000-8000-000000000010' } }),
  note('c0000000-0000-4000-8000-00000000n004', 'seed_thabo', 'push', 'quote_ready', 'Your quotation is ready', 'QT-2026-0041: R 3 850.00. Accept or decline in the app.', 'sent', 24 * 60, { payload: { type: 'quotation', id: '20000000-0000-4000-8000-000000000001' } }),
  note('c0000000-0000-4000-8000-00000000n005', 'seed_pieter', 'push', 'task_assigned', 'New task', 'WO-2026-4821 assigned to you · Sparkling Wash · Bay 2.', 'sent', 35, { payload: { type: 'task', id: '40000000-0000-4000-8000-000000000001' } }),
  note('c0000000-0000-4000-8000-00000000n006', 'seed_ayesha', 'push', 'low_stock', 'Low stock alert', 'Interior shampoo 5L at Menlyn is out of stock (0/4).', 'sent', 14, { payload: { type: 'inventory_item', id: '70000000-0000-4000-8000-000000000001' } }),
  note('c0000000-0000-4000-8000-00000000n007', 'seed_naledi', 'whatsapp', 'pickup_otp', 'Ready for collection', `Your Suzuki Swift is ready at ${outletName(OUTLET_MEN)}. Collection OTP: 48213 — show it at the counter to collect your keys.`, 'delivered', 70, { payload: { type: 'booking', id: '10000000-0000-4000-8000-000000000005' } }),
  note('c0000000-0000-4000-8000-00000000n008', 'seed_naledi', 'push', 'service_ready', 'Ready for collection', `Your Suzuki Swift is ready at ${outletName(OUTLET_MEN)}.`, 'delivered', 70, { payload: { type: 'booking', id: '10000000-0000-4000-8000-000000000005' } }),
  note('c0000000-0000-4000-8000-00000000n009', 'seed_zanele', 'whatsapp', 'booking_reminder', null, `Reminder: your Auto detailing complete & polish at ${outletName(OUTLET_MEN)} starts at 12:00 today. Reply STOP to opt out.`, 'failed', 45, {
    provider_status: 'undelivered', provider_error_code: '63016', error: '63016 outside 24h session — free-form message sent outside the WhatsApp 24 h customer-service window; use an approved template', attempts: 1, delivered_at: null,
    payload: { type: 'booking', id: '10000000-0000-4000-8000-000000000007' },
  }),
  note('c0000000-0000-4000-8000-00000000n010', 'seed_sipho', 'whatsapp', 'booking_cancelled', null, 'Your Sparkling booking SPK-2026-0090 was cancelled. Rebook any time in the app.', 'suppressed', 3 * 60, { provider_status: null, provider_ref: null, attempts: 0, sent_at: null, error: 'whatsapp_opt_in=false', payload: { type: 'booking', id: '10000000-0000-4000-8000-000000000009' } }),
  note('c0000000-0000-4000-8000-00000000n011', 'seed_lindiwe', 'push', 'service_started', 'Service started', `Your Kia Sonet is now in Bay 1 at ${outletName(OUTLET_GLV)}.`, 'queued', 2, { payload: { type: 'booking', id: '10000000-0000-4000-8000-000000000012' } }),
];
