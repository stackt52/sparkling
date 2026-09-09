/**
 * Demo dataset mirroring backend/supabase/seed.sql (South African sample data).
 * Times are relative to "today 10:00" local time so the dashboard always looks live.
 */
import type {
  AuditEvent,
  BookingStatus,
  ChecklistTemplate,
  FeatureFlag,
  InventoryItem,
  LedgerEntry,
  LoyaltyAccount,
  LoyaltyConfig,
  Outlet,
  OutletService,
  Payment,
  Profile,
  Quotation,
  Service,
  ServiceCategory,
  UserRole,
  Vehicle,
  WorkOrder,
  WorkStatus,
} from '../types';

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

/* ---------- outlets ---------- */
export const OUTLET_SAN = 'a0000000-0000-4000-8000-000000000001';
export const OUTLET_ROS = 'a0000000-0000-4000-8000-000000000002';
export const OUTLET_CEN = 'a0000000-0000-4000-8000-000000000003';

const hours = {
  mon: ['07:30', '17:30'] as [string, string],
  tue: ['07:30', '17:30'] as [string, string],
  wed: ['07:30', '17:30'] as [string, string],
  thu: ['07:30', '17:30'] as [string, string],
  fri: ['07:30', '17:30'] as [string, string],
  sat: ['08:00', '14:00'] as [string, string],
  sun: null,
};

export const OUTLETS: Outlet[] = [
  { id: OUTLET_SAN, code: 'SAN', name: 'Sparkling Sandton', address_line: '14 Rivonia Rd, Sandton', city: 'Johannesburg', province: 'Gauteng', phone: '+27 11 555 0101', email: 'sandton@sparkling.co.za', timezone: 'Africa/Johannesburg', opening_hours: { ...hours }, slot_minutes: 30, bay_count: 4, rating: 4.8, is_active: true },
  { id: OUTLET_ROS, code: 'ROS', name: 'Sparkling Rosebank', address_line: 'Cradock Ave, Rosebank', city: 'Johannesburg', province: 'Gauteng', phone: '+27 11 555 0102', email: 'rosebank@sparkling.co.za', timezone: 'Africa/Johannesburg', opening_hours: { ...hours }, slot_minutes: 30, bay_count: 3, rating: 4.7, is_active: true },
  { id: OUTLET_CEN, code: 'CEN', name: 'Sparkling Centurion', address_line: 'Lenchen Ave, Centurion', city: 'Centurion', province: 'Gauteng', phone: '+27 12 555 0103', email: 'centurion@sparkling.co.za', timezone: 'Africa/Johannesburg', opening_hours: { ...hours }, slot_minutes: 30, bay_count: 3, rating: 4.6, is_active: true },
];
export const outletName = (id: string) => OUTLETS.find((o) => o.id === id)?.name ?? 'Unknown outlet';
export const outletShort = (id: string) => outletName(id).replace('Sparkling ', '');

/* ---------- templates ---------- */
export const TPL_VALET = 'c0000000-0000-4000-8000-000000000001';
export const TPL_EXPRESS = 'c0000000-0000-4000-8000-000000000002';
export const TPL_BODY = 'c0000000-0000-4000-8000-000000000003';

export const TEMPLATES: ChecklistTemplate[] = [
  { id: TPL_VALET, name: 'Full valet checklist', category: 'car_wash', version: 3, status: 'published', outlet_id: null, created_by: 'seed_admin', created_at: daysAgo(30), steps: [
    { key: 'prewash', title: 'Pre-wash inspection', type: 'photo', required: true, hint: 'Photograph all four sides before starting', photo_required: true },
    { key: 'exterior', title: 'Exterior wash & rinse', type: 'confirm', required: true },
    { key: 'wheels', title: 'Wheels, arches & tyre shine', type: 'confirm', required: true },
    { key: 'interior', title: 'Interior vacuum & dash', type: 'confirm', required: true, hint: 'Include boot and door pockets' },
    { key: 'windows', title: 'Windows inside & out', type: 'confirm', required: true },
    { key: 'tyre_pressure', title: 'Tyre pressure check', type: 'numeric', required: true, unit: 'bar', min: 1.5, max: 3.5, hint: 'Record front-left pressure' },
    { key: 'supervisor', title: 'Supervisor verification', type: 'supervisor_verify', required: true, hint: 'Locked until all required steps pass' },
  ] },
  { id: TPL_EXPRESS, name: 'Express wash checklist', category: 'car_wash', version: 2, status: 'published', outlet_id: null, created_by: 'seed_admin', created_at: daysAgo(45), steps: [
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

/* ---------- services ---------- */
export const SVC = {
  EXPRESS: 'b0000000-0000-4000-8000-000000000001',
  VALET: 'b0000000-0000-4000-8000-000000000002',
  DETAIL: 'b0000000-0000-4000-8000-000000000003',
  INTERIOR: 'b0000000-0000-4000-8000-000000000004',
  DENT: 'b0000000-0000-4000-8000-000000000011',
  SCRATCH: 'b0000000-0000-4000-8000-000000000012',
  BUMPER: 'b0000000-0000-4000-8000-000000000013',
  PANEL: 'b0000000-0000-4000-8000-000000000014',
} as const;

const svc = (id: string, code: string, name: string, description: string, category: ServiceCategory, duration: number, price: number, quote: boolean, icon: string, tpl: string, sort: number): Service => ({
  id, code, name, description, category, duration_minutes: duration, base_price_cents: price, is_quote_based: quote, points_per_rand: 0.1, icon, checklist_template_id: tpl, is_active: true, sort_order: sort,
});
export const SERVICES: Service[] = [
  svc(SVC.EXPRESS, 'EXPRESS', 'Express Wash', 'Exterior wash, wheels and hand dry', 'car_wash', 20, 12000, false, 'water_drop', TPL_EXPRESS, 10),
  svc(SVC.VALET, 'VALET', 'Full Valet', 'Exterior + interior vacuum, dash and windows', 'car_wash', 60, 22000, false, 'local_car_wash', TPL_VALET, 20),
  svc(SVC.DETAIL, 'DETAIL', 'Premium Detail', 'Clay bar, polish, wax and full interior detail', 'car_wash', 120, 45000, false, 'auto_awesome', TPL_VALET, 30),
  svc(SVC.INTERIOR, 'INTERIOR', 'Interior Deep Clean', 'Seats, carpets and upholstery shampoo', 'car_wash', 90, 28000, false, 'cleaning_services', TPL_VALET, 40),
  svc(SVC.DENT, 'DENT', 'Dent removal', 'Paintless dent removal', 'auto_body', 240, 0, true, 'car_crash', TPL_BODY, 110),
  svc(SVC.SCRATCH, 'SCRATCH', 'Scratch repair', 'Scratch and scuff repair with blend', 'auto_body', 240, 0, true, 'car_crash', TPL_BODY, 120),
  svc(SVC.BUMPER, 'BUMPER', 'Bumper repair', 'Plastic bumper repair and respray', 'auto_body', 480, 0, true, 'car_crash', TPL_BODY, 130),
  svc(SVC.PANEL, 'PANEL', 'Panel respray', 'Single panel respray', 'auto_body', 960, 0, true, 'car_crash', TPL_BODY, 140),
];
export const serviceById = (id: string) => SERVICES.find((s) => s.id === id)!;

export const OUTLET_SERVICES: OutletService[] = OUTLETS.flatMap((o) =>
  SERVICES.map((s) => ({
    outlet_id: o.id,
    service_id: s.id,
    price_cents: o.id === OUTLET_SAN && s.id === SVC.VALET ? 24000 : null,
    is_available: !(o.id === OUTLET_CEN && s.id === SVC.PANEL),
  })),
);

/* ---------- people ---------- */
type DemoProfile = Profile & { outlet_ids: string[]; skills: string[]; availability?: 'available' | 'busy' | 'break' | 'off' };
const person = (id: string, role: UserRole, full_name: string, email: string, phone: string, outlet_ids: string[] = [], skills: string[] = [], availability?: DemoProfile['availability'], marketing = false): DemoProfile => ({
  id, role, full_name, email, phone, avatar_url: null, is_active: true, marketing_opt_in: marketing, whatsapp_opt_in: true, push_opt_in: true, last_seen_at: rel(-15), created_at: daysAgo(200), outlet_ids, skills, availability,
});

export const DEMO_PROFILES: DemoProfile[] = [
  person('seed_admin', 'admin', 'Sparkling Admin', 'admin@sparkling.co.za', '+27 82 000 0001', [OUTLET_SAN, OUTLET_ROS, OUTLET_CEN]),
  person('seed_finance', 'finance', 'Nomvula Finance', 'finance@sparkling.co.za', '+27 82 000 0002', [OUTLET_SAN, OUTLET_ROS, OUTLET_CEN]),
  person('seed_ayesha', 'manager', 'Ayesha Patel', 'ayesha@sparkling.co.za', '+27 82 000 0010', [OUTLET_SAN, OUTLET_ROS]),
  person('seed_johan', 'supervisor', 'Johan Botha', 'johan@sparkling.co.za', '+27 82 000 0011', [OUTLET_SAN], [], 'available'),
  person('seed_pieter', 'technician', 'Pieter van der Merwe', 'pieter@sparkling.co.za', '+27 82 000 0012', [OUTLET_SAN], ['wash', 'detail'], 'available'),
  person('seed_lerato', 'technician', 'Lerato Mahlangu', 'lerato@sparkling.co.za', '+27 82 000 0013', [OUTLET_SAN], ['wash', 'interior'], 'busy'),
  person('seed_sipho_staff', 'technician', 'Sipho Ndlovu', 'sipho.n@sparkling.co.za', '+27 82 000 0014', [OUTLET_SAN], ['wash', 'paint', 'panel'], 'busy'),
  person('seed_thandi', 'technician', 'Thandi Khumalo', 'thandi@sparkling.co.za', '+27 82 000 0015', [OUTLET_ROS], ['wash'], 'available'),
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
const veh = (id: string, customer_id: string, reg: string, vin: string | null, make: string, model: string, colour: string, year: number, expiry: string, source: 'manual' | 'scan'): Vehicle => ({
  id, customer_id, registration_no: reg, vin, make, model, colour, year, disc_expiry: expiry, source, disc_verified: source === 'scan',
});
export const VEHICLES: Vehicle[] = [
  veh('d0000000-0000-4000-8000-000000000001', 'seed_thabo', 'KL 45 MN GP', 'AHTFB3CB301234567', 'Toyota', 'Corolla Cross', 'Celestite Grey', 2023, '2027-03-31', 'scan'),
  veh('d0000000-0000-4000-8000-000000000002', 'seed_thabo', 'CJ 12 PZ GP', 'WVWZZZ1KZ9W654321', 'Volkswagen', 'Polo Vivo', 'Reflex Silver', 2019, '2026-11-30', 'manual'),
  veh('d0000000-0000-4000-8000-000000000003', 'seed_naledi', 'HR 88 TS GP', 'MA3FB1B4200123456', 'Suzuki', 'Swift', 'Pearl Arctic White', 2022, '2027-01-31', 'scan'),
  veh('d0000000-0000-4000-8000-000000000004', 'seed_sipho', 'DN 07 KX GP', 'SB1KZ3BE10E234567', 'Toyota', 'Hilux', 'Glacier White', 2021, '2026-10-15', 'scan'),
  veh('d0000000-0000-4000-8000-000000000005', 'seed_zanele', 'BW 33 RG GP', 'WBA5R1C50KA112233', 'BMW', '330i', 'Portimao Blue', 2020, '2027-05-31', 'scan'),
  veh('d0000000-0000-4000-8000-000000000006', 'seed_daniel', 'CJ 118-334', null, 'Ford', 'Ranger', 'Frozen White', 2022, '2027-02-28', 'manual'),
  veh('d0000000-0000-4000-8000-000000000007', 'seed_ayanda', 'FT 21 GB GP', 'JTDKN3DU5A0123456', 'Hyundai', 'i20', 'Fiery Red', 2021, '2026-12-31', 'scan'),
  veh('d0000000-0000-4000-8000-000000000008', 'seed_lindiwe', 'HX 42 KL GP', 'KMHCT41BAFU123456', 'Kia', 'Sonet', 'Aurora Black', 2023, '2027-04-30', 'scan'),
  veh('d0000000-0000-4000-8000-000000000009', 'seed_kabelo', 'DR 88 SN GP', null, 'Mazda', 'CX-5', 'Soul Red', 2020, '2026-09-30', 'manual'),
];
export const vehicleById = (id: string) => VEHICLES.find((v) => v.id === id)!;

/* ---------- loyalty ---------- */
const TIERS = [
  { tier: 'silver' as const, name: 'Silver', min_points: 0, max_points: 499, earn_multiplier: 1.0, discount_pct: 0, perks: '—', members: 7214 },
  { tier: 'gold' as const, name: 'Gold', min_points: 500, max_points: 1999, earn_multiplier: 1.25, discount_pct: 10, perks: '10%', members: 1892 },
  { tier: 'platinum' as const, name: 'Platinum', min_points: 2000, max_points: null, earn_multiplier: 1.5, discount_pct: 15, perks: '15% + priority slots', members: 417 },
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
    tiers: TIERS.map((t) => (t.tier === 'gold' ? { ...t, earn_multiplier: 1.3 } : t.tier === 'platinum' ? { ...t, min_points: 1800 } : { ...t, max_points: 499 })).map((t) => (t.tier === 'gold' ? { ...t, max_points: 1799 } : t)),
    rules: { points_per_rand: 0.12, award_on: 'completion', idempotent_award: true, expiry_months: 24, birthday_bonus: { enabled: false, points: 100, reason: 'Pending consent review (ADM-042)' }, referral_bonus: { enabled: true, points: 200 } },
    change_note: 'Raise earn rate to 0.12/R and referral bonus to 200', created_by: 'seed_ayesha', published_by: null, published_at: null, created_at: daysAgo(2),
  },
];

export const LOYALTY_ACCOUNTS: LoyaltyAccount[] = [
  { customer_id: 'seed_thabo', tier: 'gold', balance_points: 1450, lifetime_points: 1800, tier_since: daysAgo(95) },
  { customer_id: 'seed_naledi', tier: 'gold', balance_points: 620, lifetime_points: 620, tier_since: daysAgo(60) },
  { customer_id: 'seed_sipho', tier: 'platinum', balance_points: 2150, lifetime_points: 2150, tier_since: daysAgo(150) },
  { customer_id: 'seed_zanele', tier: 'gold', balance_points: 500, lifetime_points: 500, tier_since: daysAgo(10) },
  { customer_id: 'seed_daniel', tier: 'silver', balance_points: 120, lifetime_points: 120, tier_since: daysAgo(20) },
  { customer_id: 'seed_ayanda', tier: 'silver', balance_points: 260, lifetime_points: 260, tier_since: daysAgo(80) },
  { customer_id: 'seed_lindiwe', tier: 'gold', balance_points: 845, lifetime_points: 845, tier_since: daysAgo(30) },
  { customer_id: 'seed_kabelo', tier: 'silver', balance_points: 40, lifetime_points: 40, tier_since: daysAgo(5) },
];

const led = (i: number, customer_id: string, delta: number, type: LedgerEntry['type'], reference: string, description: string, key: string, days: number): LedgerEntry => ({
  id: `ll-${i}`, customer_id, delta, type, reference, description, idempotency_key: key, created_at: daysAgo(days),
});
export const LEDGER: LedgerEntry[] = [
  led(1, 'seed_thabo', 500, 'bonus', 'WELCOME', 'Welcome bonus', 'll-thabo-welcome', 120),
  led(2, 'seed_thabo', 380, 'earn', 'SPK-2026-0031', 'Premium Detail', 'll-thabo-0031', 95),
  led(3, 'seed_thabo', 150, 'bonus', 'REF-NALEDI', 'Referral: Naledi M.', 'll-thabo-ref1', 70),
  led(4, 'seed_thabo', 120, 'earn', 'SPK-2026-0052', 'Express Wash', 'll-thabo-0052', 40),
  led(5, 'seed_thabo', -350, 'redeem', 'RW-1182', 'Interior refresh', 'll-thabo-rw1182', 30),
  led(6, 'seed_thabo', 450, 'earn', 'SPK-2026-0067', 'Premium Detail', 'll-thabo-0067', 21),
  led(7, 'seed_thabo', 200, 'earn', 'SPK-2026-0078', 'Full Valet', 'll-thabo-0078', 9),
  led(8, 'seed_naledi', 500, 'bonus', 'WELCOME', 'Welcome bonus', 'll-naledi-welcome', 60),
  led(9, 'seed_naledi', 120, 'earn', 'SPK-2026-0092', 'Express Wash', 'll-naledi-0092', 0),
  led(10, 'seed_sipho', 500, 'bonus', 'WELCOME', 'Welcome bonus', 'll-sipho-welcome', 200),
  led(11, 'seed_sipho', 1650, 'earn', 'SPK-2025-0410', 'Panel respray', 'll-sipho-0410', 150),
  led(12, 'seed_zanele', 500, 'bonus', 'WELCOME', 'Welcome bonus', 'll-zanele-welcome', 10),
  led(13, 'seed_lindiwe', 500, 'bonus', 'WELCOME', 'Welcome bonus', 'll-lindiwe-welcome', 30),
  led(14, 'seed_lindiwe', 345, 'earn', 'SPK-2026-0071', 'Premium Detail', 'll-lindiwe-0071', 12),
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
  price_cents: number;
  discount_cents: number;
  total_cents: number;
  discount_label: string | null;
  points_pending: number;
  notes: string | null;
  cancel_reason: string | null;
  created_at: string;
  quotation_id: string | null;
}

const bk = (n: number, ref: string, customer_id: string, vehicle_id: string, outlet_id: string, service_id: string, start: number, status: BookingStatus, price: number, discount: number, label: string | null, created: string): RawBooking => {
  const s = serviceById(service_id);
  return {
    id: `10000000-0000-4000-8000-${String(n).padStart(12, '0')}`, ref, customer_id, vehicle_id, outlet_id, service_id,
    slot_start: at(start), slot_end: at(start + s.duration_minutes), status, price_cents: price, discount_cents: discount, total_cents: price - discount,
    discount_label: label, points_pending: Math.round(((price - discount) / 100) * 0.1), notes: null, cancel_reason: null, created_at: created, quotation_id: null,
  };
};

export const SEED_BOOKINGS: RawBooking[] = [
  bk(1, 'SPK-2026-0091', 'seed_thabo', 'd0000000-0000-4000-8000-000000000001', OUTLET_SAN, SVC.VALET, 0, 'in_service', 22000, 2200, 'Gold −10%', daysAgo(2)),
  bk(2, 'SPK-2026-0094', 'seed_thabo', 'd0000000-0000-4000-8000-000000000002', OUTLET_ROS, SVC.EXPRESS, 23 * 60, 'confirmed', 12000, 1200, 'Gold −10%', daysAgo(0, 7)),
  bk(3, 'SPK-2026-0067', 'seed_thabo', 'd0000000-0000-4000-8000-000000000001', OUTLET_SAN, SVC.DETAIL, -21 * 24 * 60, 'completed', 45000, 4500, 'Gold −10%', daysAgo(24)),
  bk(4, 'SPK-2026-0052', 'seed_thabo', 'd0000000-0000-4000-8000-000000000002', OUTLET_SAN, SVC.EXPRESS, -38 * 24 * 60, 'completed', 12000, 0, null, daysAgo(40)),
  bk(5, 'SPK-2026-0092', 'seed_naledi', 'd0000000-0000-4000-8000-000000000003', OUTLET_SAN, SVC.EXPRESS, -90, 'completed', 12000, 0, null, daysAgo(1)),
  bk(6, 'SPK-2026-0093', 'seed_sipho', 'd0000000-0000-4000-8000-000000000004', OUTLET_SAN, SVC.INTERIOR, 30, 'in_service', 28000, 0, null, daysAgo(1)),
  bk(7, 'SPK-2026-0095', 'seed_zanele', 'd0000000-0000-4000-8000-000000000005', OUTLET_SAN, SVC.DETAIL, 120, 'confirmed', 45000, 6750, 'Platinum −15%', daysAgo(0, 8)),
  bk(8, 'SPK-2026-0096', 'seed_naledi', 'd0000000-0000-4000-8000-000000000003', OUTLET_ROS, SVC.VALET, 180, 'pending', 22000, 0, null, daysAgo(0, 9)),
  bk(9, 'SPK-2026-0090', 'seed_sipho', 'd0000000-0000-4000-8000-000000000004', OUTLET_SAN, SVC.EXPRESS, -180, 'cancelled', 12000, 0, null, daysAgo(1)),
  bk(10, 'SPK-2026-0089', 'seed_daniel', 'd0000000-0000-4000-8000-000000000006', OUTLET_SAN, SVC.BUMPER, -60, 'confirmed', 385000, 0, null, daysAgo(1)),
  bk(11, 'SPK-2026-0088', 'seed_ayanda', 'd0000000-0000-4000-8000-000000000007', OUTLET_SAN, SVC.VALET, -45, 'completed', 24000, 0, null, daysAgo(1)),
  bk(12, 'SPK-2026-0087', 'seed_lindiwe', 'd0000000-0000-4000-8000-000000000008', OUTLET_ROS, SVC.EXPRESS, 30, 'in_service', 12000, 1200, 'Gold −10%', daysAgo(1)),
  bk(13, 'SPK-2026-0086', 'seed_kabelo', 'd0000000-0000-4000-8000-000000000009', OUTLET_CEN, SVC.EXPRESS, -120, 'completed', 12000, 0, null, daysAgo(2)),
];

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
  for (const { hour, count } of plan) {
    for (let i = 0; i < count; i++) {
      const c = customers[Math.floor(r() * customers.length)];
      const v = VEHICLES.find((x) => x.customer_id === c.id) ?? VEHICLES[0];
      const outlet = [OUTLET_SAN, OUTLET_SAN, OUTLET_ROS, OUTLET_CEN][Math.floor(r() * 4)];
      const isBody = r() < 0.22;
      const service = isBody ? [SVC.DENT, SVC.SCRATCH][Math.floor(r() * 2)] : [SVC.EXPRESS, SVC.EXPRESS, SVC.VALET, SVC.DETAIL, SVC.INTERIOR][Math.floor(r() * 5)];
      const s = serviceById(service);
      const startMin = (hour - 10) * 60 + [0, 15, 30, 45][Math.floor(r() * 4)];
      const price = s.is_quote_based ? [180000, 210000, 260000][Math.floor(r() * 3)] : (OUTLET_SERVICES.find((os) => os.outlet_id === outlet && os.service_id === service)?.price_cents ?? s.base_price_cents);
      const acct = LOYALTY_ACCOUNTS.find((a) => a.customer_id === c.id);
      const pct = acct?.tier === 'platinum' ? 15 : acct?.tier === 'gold' ? 10 : 0;
      const discount = Math.round((price * pct) / 100);
      const nowMin = (Date.now() - TEN.getTime()) / 60_000;
      let status: BookingStatus;
      if (startMin + s.duration_minutes < nowMin - 10) status = r() < 0.9 ? 'completed' : 'cancelled';
      else if (startMin <= nowMin) status = 'in_service';
      else status = r() < 0.85 ? 'confirmed' : 'pending';
      n += 1;
      out.push(bk(n, `SPK-2026-${String(n).padStart(4, '0')}`, c.id, v.id, outlet, service, startMin, status, price, discount, pct ? `${acct!.tier === 'platinum' ? 'Platinum' : 'Gold'} −${pct}%` : null, daysAgo(1 + Math.floor(r() * 3))));
    }
  }
  return out;
}

/* ---------- quotations ---------- */
export const QUOTATIONS: Quotation[] = [
  { id: '20000000-0000-4000-8000-000000000001', ref: 'QT-2026-0041', customer_id: 'seed_thabo', customer_name: 'Thabo Nkosi', vehicle: { id: 'd0000000-0000-4000-8000-000000000001', registration_no: 'KL 45 MN GP', make: 'Toyota', model: 'Corolla Cross' }, outlet: { id: OUTLET_SAN, name: 'Sparkling Sandton' }, category: 'Bumper', description: 'Rear bumper scuffed in parking lot, paint cracked on left corner.', status: 'quoted', amount_cents: 385000, line_items: [{ label: 'Bumper repair & respray', amount_cents: 320000 }, { label: 'Blend to quarter panel', amount_cents: 65000 }], assessor_id: 'seed_sipho_staff', assessor_name: 'Sipho Ndlovu', valid_until: daysAgo(-14).slice(0, 10), quoted_at: daysAgo(1), decided_at: null, decision_note: null, attachments: [{ id: 'att-1', storage_path: 'quotations/qt41/front.jpg', mime_type: 'image/jpeg' }, { id: 'att-2', storage_path: 'quotations/qt41/side.jpg', mime_type: 'image/jpeg' }], created_at: daysAgo(2) },
  { id: '20000000-0000-4000-8000-000000000002', ref: 'QT-2026-0042', customer_id: 'seed_zanele', customer_name: 'Zanele Mthembu', vehicle: { id: 'd0000000-0000-4000-8000-000000000005', registration_no: 'BW 33 RG GP', make: 'BMW', model: '330i' }, outlet: { id: OUTLET_SAN, name: 'Sparkling Sandton' }, category: 'Dent', description: 'Door ding on driver door, no paint damage.', status: 'requested', amount_cents: null, line_items: [], assessor_id: null, assessor_name: null, valid_until: null, quoted_at: null, decided_at: null, decision_note: null, attachments: [{ id: 'att-3', storage_path: 'quotations/qt42/door.jpg', mime_type: 'image/jpeg' }], created_at: rel(-200) },
  { id: '20000000-0000-4000-8000-000000000003', ref: 'QT-2026-0038', customer_id: 'seed_sipho', customer_name: 'Sipho Dlamini', vehicle: { id: 'd0000000-0000-4000-8000-000000000004', registration_no: 'DN 07 KX GP', make: 'Toyota', model: 'Hilux' }, outlet: { id: OUTLET_SAN, name: 'Sparkling Sandton' }, category: 'Scratch', description: 'Key scratch along passenger side.', status: 'converted', amount_cents: 210000, line_items: [{ label: 'Scratch repair & blend', amount_cents: 210000 }], assessor_id: 'seed_sipho_staff', assessor_name: 'Sipho Ndlovu', valid_until: daysAgo(-7).slice(0, 10), quoted_at: daysAgo(4), decided_at: daysAgo(2), decision_note: 'Go ahead', attachments: [], created_at: daysAgo(5), work_order_ref: 'WO-2026-4818' },
  { id: '20000000-0000-4000-8000-000000000004', ref: 'QT-2026-0039', customer_id: 'seed_daniel', customer_name: 'Daniel Botha', vehicle: { id: 'd0000000-0000-4000-8000-000000000006', registration_no: 'CJ 118-334', make: 'Ford', model: 'Ranger' }, outlet: { id: OUTLET_SAN, name: 'Sparkling Sandton' }, category: 'Panel', description: 'Tailgate dented and scratched from towing accident.', status: 'accepted', amount_cents: 485000, line_items: [{ label: 'Tailgate panel repair', amount_cents: 385000 }, { label: 'Respray & blend', amount_cents: 100000 }], assessor_id: 'seed_sipho_staff', assessor_name: 'Sipho Ndlovu', valid_until: daysAgo(-10).slice(0, 10), quoted_at: daysAgo(3), decided_at: rel(-130), decision_note: null, attachments: [], created_at: daysAgo(4) },
  { id: '20000000-0000-4000-8000-000000000005', ref: 'QT-2026-0037', customer_id: 'seed_ayanda', customer_name: 'Ayanda Zulu', vehicle: { id: 'd0000000-0000-4000-8000-000000000007', registration_no: 'FT 21 GB GP', make: 'Hyundai', model: 'i20' }, outlet: { id: OUTLET_ROS, name: 'Sparkling Rosebank' }, category: 'Glass', description: 'Windscreen chip on passenger side.', status: 'declined', amount_cents: 95000, line_items: [{ label: 'Windscreen chip repair', amount_cents: 95000 }], assessor_id: 'seed_thandi', assessor_name: 'Thandi Khumalo', valid_until: daysAgo(-3).slice(0, 10), quoted_at: daysAgo(6), decided_at: daysAgo(5), decision_note: 'Going through insurance', attachments: [], created_at: daysAgo(7) },
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
  wo('30000000-0000-4000-8000-000000000001', 'WO-2026-4821', OUTLET_SAN, 'SPK-2026-0091', null, 'seed_thabo', 'd0000000-0000-4000-8000-000000000001', SVC.VALET, 'in_progress', 1, 'Bay 2', TPL_VALET, 'seed_pieter', 20, 25, -30, null, 4),
  wo('30000000-0000-4000-8000-000000000002', 'WO-2026-4822', OUTLET_SAN, 'SPK-2026-0092', null, 'seed_naledi', 'd0000000-0000-4000-8000-000000000003', SVC.EXPRESS, 'verified', 2, 'Bay 1', TPL_EXPRESS, 'seed_lerato', -70, -70, -90, null, 4),
  wo('30000000-0000-4000-8000-000000000003', 'WO-2026-4823', OUTLET_SAN, 'SPK-2026-0093', null, 'seed_sipho', 'd0000000-0000-4000-8000-000000000004', SVC.INTERIOR, 'blocked', 1, 'Bay 3', TPL_VALET, 'seed_lerato', 85, 85, -45, 'Out of interior shampoo — substitute stock needed', 2),
  wo('30000000-0000-4000-8000-000000000004', 'WO-2026-4824', OUTLET_SAN, 'SPK-2026-0095', null, 'seed_zanele', 'd0000000-0000-4000-8000-000000000005', SVC.DETAIL, 'queued', 2, null, TPL_VALET, null, 240, 240, null, null, 0),
  wo('30000000-0000-4000-8000-000000000005', 'WO-2026-4818', OUTLET_SAN, null, 'QT-2026-0038', 'seed_sipho', 'd0000000-0000-4000-8000-000000000004', SVC.SCRATCH, 'assigned', 2, 'Body 1', TPL_BODY, 'seed_sipho_staff', 2 * 24 * 60, -12, null, null, 0),
  wo('30000000-0000-4000-8000-000000000006', 'WO-2026-4820', OUTLET_SAN, 'SPK-2026-0088', null, 'seed_ayanda', 'd0000000-0000-4000-8000-000000000007', SVC.VALET, 'completed', 2, 'Bay 4', TPL_VALET, 'seed_pieter', -5, 15, -50, null, 7),
  wo('30000000-0000-4000-8000-000000000007', 'WO-2026-4825', OUTLET_ROS, 'SPK-2026-0087', null, 'seed_lindiwe', 'd0000000-0000-4000-8000-000000000008', SVC.EXPRESS, 'in_progress', 2, 'Bay 1', TPL_EXPRESS, 'seed_thandi', 12, 15, -8, null, 1),
  wo('30000000-0000-4000-8000-000000000008', 'WO-2026-4819', OUTLET_SAN, 'SPK-2026-0089', null, 'seed_daniel', 'd0000000-0000-4000-8000-000000000006', SVC.BUMPER, 'assigned', 3, 'Body 2', TPL_BODY, 'seed_sipho_staff', 3 * 24 * 60, 3 * 24 * 60, null, null, 0),
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

/* ---------- payments ---------- */
export const PAYMENTS: Payment[] = [
  { id: '60000000-0000-4000-8000-000000000001', booking_ref: 'SPK-2026-0091', customer_name: 'Thabo Nkosi', provider: 'sandbox', amount_cents: 19800, status: 'successful', receipt_no: 'RCP-70001', verified_at: daysAgo(2), created_at: daysAgo(2) },
  { id: '60000000-0000-4000-8000-000000000002', booking_ref: 'SPK-2026-0067', customer_name: 'Thabo Nkosi', provider: 'sandbox', amount_cents: 40500, status: 'successful', receipt_no: 'RCP-70002', verified_at: daysAgo(24), created_at: daysAgo(24) },
  { id: '60000000-0000-4000-8000-000000000003', booking_ref: 'SPK-2026-0052', customer_name: 'Thabo Nkosi', provider: 'sandbox', amount_cents: 12000, status: 'successful', receipt_no: 'RCP-70003', verified_at: daysAgo(40), created_at: daysAgo(40) },
  { id: '60000000-0000-4000-8000-000000000004', booking_ref: 'SPK-2026-0092', customer_name: 'Naledi Mokoena', provider: 'sandbox', amount_cents: 12000, status: 'successful', receipt_no: 'RCP-70004', verified_at: rel(-80), created_at: rel(-85) },
  { id: '60000000-0000-4000-8000-000000000005', booking_ref: 'SPK-2026-0095', customer_name: 'Zanele Mthembu', provider: 'sandbox', amount_cents: 38250, status: 'pending', receipt_no: null, verified_at: null, created_at: rel(-30) },
  { id: '60000000-0000-4000-8000-000000000006', booking_ref: 'SPK-2026-0094', customer_name: 'Thabo Nkosi', provider: 'sandbox', amount_cents: 10800, status: 'successful', receipt_no: 'RCP-70005', verified_at: rel(-180), created_at: rel(-180) },
  { id: '60000000-0000-4000-8000-000000000007', booking_ref: 'SPK-2026-0093', customer_name: 'Sipho Dlamini', provider: 'sandbox', amount_cents: 28000, status: 'failed', receipt_no: null, verified_at: null, created_at: rel(-40) },
  { id: '60000000-0000-4000-8000-000000000008', booking_ref: 'SPK-2026-0088', customer_name: 'Ayanda Zulu', provider: 'sandbox', amount_cents: 24000, status: 'successful', receipt_no: 'RCP-70006', verified_at: rel(-50), created_at: rel(-55) },
];

/* ---------- inventory ---------- */
const inv = (id: string, outlet_id: string, sku: string, name: string, unit: string, on_hand: number, threshold: number, pack: number, capacity: number): InventoryItem => ({
  id, outlet_id, outlet_name: outletShort(outlet_id), sku, name, unit, on_hand, reorder_threshold: threshold, pack_size: pack, capacity, is_active: true, alert: null, blocking_work_orders: 0, updated_at: rel(-15),
});
export const INVENTORY: InventoryItem[] = [
  inv('70000000-0000-4000-8000-000000000001', OUTLET_SAN, 'SHP-INT', 'Interior shampoo 5L', 'bottle', 0, 4, 5, 8),
  inv('70000000-0000-4000-8000-000000000002', OUTLET_SAN, 'WAX-CRN', 'Carnauba wax 500ml', 'tin', 3, 6, 1, 14),
  inv('70000000-0000-4000-8000-000000000003', OUTLET_SAN, 'TWL-MF', 'Microfibre towels', 'pack', 18, 10, 20, 24),
  inv('70000000-0000-4000-8000-000000000004', OUTLET_SAN, 'TYR-SHN', 'Tyre shine 1L', 'bottle', 9, 4, 1, 16),
  inv('70000000-0000-4000-8000-000000000005', OUTLET_SAN, 'SNW-FOAM', 'Snow foam 5L', 'bottle', 12, 5, 5, 16),
  inv('70000000-0000-4000-8000-000000000006', OUTLET_SAN, 'GLS-CLN', 'Glass cleaner 1L', 'bottle', 7, 4, 1, 12),
  inv('70000000-0000-4000-8000-000000000007', OUTLET_SAN, 'PNT-CLR', 'Clear coat 1L', 'tin', 5, 3, 1, 8),
  inv('70000000-0000-4000-8000-000000000011', OUTLET_ROS, 'SHP-INT', 'Interior shampoo 5L', 'bottle', 6, 4, 5, 8),
  inv('70000000-0000-4000-8000-000000000012', OUTLET_ROS, 'WAX-CRN', 'Carnauba wax 500ml', 'tin', 8, 6, 1, 14),
  inv('70000000-0000-4000-8000-000000000013', OUTLET_ROS, 'TWL-MF', 'Microfibre towels', 'pack', 4, 10, 20, 24),
  inv('70000000-0000-4000-8000-000000000021', OUTLET_CEN, 'SNW-FOAM', 'Snow foam 5L', 'bottle', 15, 5, 5, 16),
  inv('70000000-0000-4000-8000-000000000022', OUTLET_CEN, 'TYR-SHN', 'Tyre shine 1L', 'bottle', 1, 4, 1, 16),
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
  { id: 'au-3', actor_id: 'seed_johan', actor_name: 'Johan Botha', actor_role: 'supervisor', action: 'task.assign', entity_type: 'task', entity_id: '40000000-0000-4000-8000-000000000001', outlet_id: OUTLET_SAN, before: { assignee: null }, after: { assignee: 'seed_pieter' }, correlation_id: 'seed-corr-3', outcome: 'ok', created_at: rel(-40) },
  { id: 'au-4', actor_id: 'seed_ayesha', actor_name: 'Ayesha Patel', actor_role: 'manager', action: 'inventory.threshold', entity_type: 'inventory_item', entity_id: '70000000-0000-4000-8000-000000000001', outlet_id: OUTLET_SAN, before: { reorder_threshold: 3 }, after: { reorder_threshold: 4 }, correlation_id: 'seed-corr-4', outcome: 'ok', created_at: daysAgo(10) },
  { id: 'au-5', actor_id: 'seed_admin', actor_name: 'Sparkling Admin', actor_role: 'admin', action: 'user.update', entity_type: 'profile', entity_id: 'seed_thandi', outlet_id: OUTLET_ROS, before: { outlet_ids: [] }, after: { outlet_ids: [OUTLET_ROS] }, correlation_id: 'seed-corr-5', outcome: 'ok', created_at: daysAgo(14) },
  { id: 'au-6', actor_id: 'seed_ayesha', actor_name: 'Ayesha Patel', actor_role: 'manager', action: 'customer.view', entity_type: 'profile', entity_id: 'seed_thabo', outlet_id: null, before: null, after: { reason: 'support call' }, correlation_id: 'seed-corr-6', outcome: 'ok', created_at: daysAgo(1) },
  { id: 'au-7', actor_id: 'seed_admin', actor_name: 'Sparkling Admin', actor_role: 'admin', action: 'flag.update', entity_type: 'feature_flag', entity_id: 'auto_assignment', outlet_id: null, before: { enabled: false }, after: { enabled: true }, correlation_id: 'seed-corr-7', outcome: 'ok', created_at: daysAgo(12) },
  { id: 'au-8', actor_id: 'seed_johan', actor_name: 'Johan Botha', actor_role: 'supervisor', action: 'task.transition', entity_type: 'task', entity_id: '40000000-0000-4000-8000-000000000002', outlet_id: OUTLET_SAN, before: { status: 'completed' }, after: { status: 'verified' }, correlation_id: 'seed-corr-8', outcome: 'ok', created_at: rel(-70) },
];
