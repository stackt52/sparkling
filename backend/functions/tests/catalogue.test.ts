/**
 * Catalogue pricing model (migration 0008, docs/API.md "Catalogue pricing model"):
 * offer resolution (outlet override vs global, size fallback, bike, by-quote),
 * composition override + cycle rejection, server-side pricing (from-price +
 * add-on + tier discount, excl-VAT, by-quote refusal, add-on group mismatch),
 * vehicle size derivation, booking persistence, admin management, CSV export.
 *
 * Fixture mirrors backend/supabase/seed_catalogue.sql at Menlyn (MEN) and Glen
 * Village (GLV): SPARKLING_WASH small 14000 / large 15000, ADDON_ODOUR 18000,
 * HEADLIGHT_RENEWAL general 40000 excl, TAR_REMOVAL by quote.
 */
import { createServer, type Server } from 'node:http';
import { afterAll, beforeAll, beforeEach, describe, expect, it } from 'vitest';
import { createApp } from '../src/app.js';
import { setFirebaseAuthForTests } from '../src/lib/firebase.js';
import { setSupabaseClient } from '../src/lib/supabase.js';
import { resetRateLimits } from '../src/middleware/rateLimit.js';
import { buildOffers, findCompositionCycle, formatRand, priceFrom, priceLabel, resolveComposition, resolveOfferPrice, resolveVehicleSize, sizeClassFromDescription } from '../src/services/catalogue.js';
import { computePrice } from '../src/services/pricing.js';
import type { OutletService, Service, ServiceComponent } from '../src/types.js';
import { fakeSupabase, type FakeSupabase } from './helpers/fakeSupabase.js';

const MEN = 'a0000000-0000-4000-8000-000000000001';
const GLV = 'a0000000-0000-4000-8000-000000000002';
const SPARKLING_WASH = '1a416567-06ce-5997-952b-1407bc1e82ca';
const ENGINE_STEAM = 'e1d469ed-5c14-541f-b94b-9eafd996577c';
const CHASSIS_STEAM = '690c258e-efd3-5c46-85fa-6887d453f618';
const ENGINE_CHASSIS_COMBO = 'f24143b8-edc7-5fba-8710-318cda03f2b7';
const ADDON_ODOUR = '529152b1-6234-553e-b260-ec41d70e7843';
const HEADLIGHT_RENEWAL = '528e1de8-1127-5b85-801c-fca4efea0b78';
const TAR_REMOVAL = '5cbf1397-ab01-5139-9874-58ea1021048a';
const WASH_BIKE = '4121af2c-10af-58c2-a22c-db9773a49b07';
const VEH_LARGE = '20000000-0000-4000-8000-000000000001';
const VEH_SMALL = '20000000-0000-4000-8000-000000000002';
const SLOT = '2027-03-10T08:00:00.000Z';
const SAST_OFFSET_MS = 2 * 60 * 60_000;

const svc = (id: string, code: string, name: string, group: string, extra: Partial<Service> = {}): Service =>
  ({
    id, code, name, description: null, category: group === 'Auto Body Repair' ? 'auto_body' : 'car_wash', duration_minutes: 30, base_price_cents: 0, is_quote_based: false, points_per_rand: 0.1, icon: null, checklist_template_id: null, is_active: true, sort_order: 100,
    group_name: group, pricing_mode: 'from', vat_mode: group === 'Auto Body Repair' ? 'excl' : 'incl', price_small_cents: null, price_large_cents: null, price_general_cents: null, is_addon: false, addon_group_name: null, notes: null, ...extra,
  }) as Service;

const bind = (outlet_id: string, service_id: string, display_name: string, small: number | null, large: number | null, general: number | null, extra: Partial<OutletService> = {}): OutletService =>
  ({ outlet_id, service_id, display_name, price_cents: small ?? general, price_small_cents: small, price_large_cents: large, price_general_cents: general, pricing_mode: null, vat_mode: null, sort_order: null, notes: null, is_available: true, ...extra });

const comp = (parent: string, child: string, outlet: string | null, sort_order = 100): ServiceComponent => ({ id: `${parent}:${child}:${outlet ?? 'g'}`, parent_service_id: parent, child_service_id: child, outlet_id: outlet, quantity: 1, sort_order });

const SERVICES: Service[] = [
  svc(SPARKLING_WASH, 'SPARKLING_WASH', 'Sparkling Wash', 'Car Wash Options', { sort_order: 40 }),
  svc(ENGINE_STEAM, 'ENGINE_STEAM', 'Engine steam clean', 'Car Wash Options', { sort_order: 60 }),
  svc(CHASSIS_STEAM, 'CHASSIS_STEAM', 'Chassis steam clean', 'Car Wash Options', { sort_order: 70 }),
  svc(WASH_BIKE, 'WASH_BIKE', 'Wash bike', 'Car Wash Options', { sort_order: 80 }),
  svc(TAR_REMOVAL, 'TAR_REMOVAL', 'Tar removal / excess mud', 'Car Wash Options', { sort_order: 90, pricing_mode: 'by_quote', is_quote_based: true }),
  svc(ENGINE_CHASSIS_COMBO, 'ENGINE_CHASSIS_COMBO', 'Engine & chassis steam clean combo', 'Combinations', { sort_order: 110 }),
  svc(ADDON_ODOUR, 'ADDON_ODOUR', 'Add-on: odour removal', 'Combinations', { sort_order: 170, is_addon: true, addon_group_name: 'Combinations' }),
  svc(HEADLIGHT_RENEWAL, 'HEADLIGHT_RENEWAL', 'Headlight renewal (per light)', 'Auto Body Repair', { sort_order: 180 }),
];

const BINDINGS: OutletService[] = [
  bind(MEN, SPARKLING_WASH, '"Sparkling wash" - include All of the above', 14000, 15000, null, { sort_order: 50 }),
  bind(MEN, ENGINE_STEAM, 'Engine steam clean', 17000, 18000, null, { sort_order: 80 }),
  bind(MEN, CHASSIS_STEAM, 'Chassis steam clean', 18000, 20000, null, { sort_order: 90 }),
  bind(MEN, WASH_BIKE, 'Wash bike', 8000, null, null, { sort_order: 70, is_available: false }),
  bind(MEN, TAR_REMOVAL, 'Tar Removal | Excess Mud', null, null, null, { sort_order: 100, pricing_mode: 'by_quote' }),
  bind(MEN, ENGINE_CHASSIS_COMBO, 'Engine & Chassis steam clean Combo', 31000, 33000, null, { sort_order: 110 }),
  bind(MEN, ADDON_ODOUR, 'Add to any Combo: Odour Removal', 18000, 18000, null, { sort_order: 160 }),
  bind(MEN, HEADLIGHT_RENEWAL, 'Headlight renewal (Per light)', null, null, 40000, { sort_order: 210, pricing_mode: 'from', vat_mode: 'excl' }),
  bind(GLV, SPARKLING_WASH, '"Sparkling wash" - include All of the above', 16000, 18000, null, { sort_order: 40 }),
  bind(GLV, ENGINE_STEAM, 'Engine steam clean', 17000, 18000, null, { sort_order: 80 }),
  bind(GLV, CHASSIS_STEAM, 'Chassis steam clean', 18000, 20000, null, { sort_order: 90 }),
  bind(GLV, ENGINE_CHASSIS_COMBO, 'Engine & Chassis steam clean Combo', 31000, 33000, null, { sort_order: 110 }),
];

/** Global default: the combo includes engine steam only; Menlyn's own set adds chassis steam. */
const COMPONENTS: ServiceComponent[] = [comp(ENGINE_CHASSIS_COMBO, ENGINE_STEAM, null, 10), comp(ENGINE_CHASSIS_COMBO, ENGINE_STEAM, MEN, 100), comp(ENGINE_CHASSIS_COMBO, CHASSIS_STEAM, MEN, 110)];

const rows = () => ({ services: SERVICES, bindings: BINDINGS, components: COMPONENTS });

describe('catalogue — pure resolution', () => {
  it('resolves per-size prices: large → small fallback, bike → small, general when size-independent, by_quote → null', () => {
    const wash = { pricing_mode: 'from' as const, price_small_cents: 14000, price_large_cents: 15000, price_general_cents: null };
    expect(resolveOfferPrice(wash, 'small')).toBe(14000);
    expect(resolveOfferPrice(wash, 'large')).toBe(15000);
    expect(resolveOfferPrice(wash, 'bike')).toBe(14000);
    const bike = { pricing_mode: 'from' as const, price_small_cents: 8000, price_large_cents: null, price_general_cents: null };
    expect(resolveOfferPrice(bike, 'large')).toBe(8000);
    const headlight = { pricing_mode: 'from' as const, price_small_cents: null, price_large_cents: null, price_general_cents: 40000 };
    expect(resolveOfferPrice(headlight, 'small')).toBe(40000);
    expect(resolveOfferPrice(headlight, 'large')).toBe(40000);
    expect(resolveOfferPrice({ ...headlight, pricing_mode: 'by_quote' }, 'small')).toBeNull();
    expect(priceFrom(wash)).toBe(14000);
    expect(priceFrom({ ...wash, pricing_mode: 'by_quote' })).toBeNull();
  });

  it('labels: From R x, excl. VAT suffix, By quotation, cents formatting', () => {
    expect(priceLabel('from', 14000)).toBe('From R 140');
    expect(priceLabel('fixed', 14050)).toBe('R 140.50');
    expect(priceLabel('from', 40000, 'excl')).toBe('From R 400 excl. VAT');
    expect(priceLabel('by_quote', null)).toBe('By quotation');
    expect(formatRand(45900)).toBe('R 459');
  });

  it('derives the size class from licence-disc descriptions', () => {
    expect(sizeClassFromDescription('Station wagon')).toBe('large');
    expect(sizeClassFromDescription('SUV')).toBe('large');
    expect(sizeClassFromDescription('Pick-up')).toBe('large');
    expect(sizeClassFromDescription('LDV / Bakkie')).toBe('large');
    expect(sizeClassFromDescription('Bus')).toBe('large');
    expect(sizeClassFromDescription('MPV')).toBe('large');
    expect(sizeClassFromDescription('Panel van')).toBe('large');
    expect(sizeClassFromDescription('Sedan (closed top)')).toBe('small');
    expect(sizeClassFromDescription('Hatch back')).toBe('small');
    expect(sizeClassFromDescription('Coupe')).toBe('small');
    expect(sizeClassFromDescription('Motorcycle')).toBe('bike');
    expect(sizeClassFromDescription('Motor cycle > 125cc')).toBe('bike');
    expect(sizeClassFromDescription('')).toBeNull();
    expect(sizeClassFromDescription('Special vehicle')).toBeNull();
    expect(resolveVehicleSize({ size_class: 'bike', description: 'Station wagon' })).toBe('bike');
    expect(resolveVehicleSize({ size_class: null, description: 'Station wagon' })).toBe('large');
    expect(resolveVehicleSize({ size_class: null, description: null })).toBe('small');
    expect(resolveVehicleSize(null)).toBe('small');
  });

  it('outlet composition rows override the global set per parent', () => {
    const men = resolveComposition(COMPONENTS, MEN);
    expect(men.get(ENGINE_CHASSIS_COMBO)?.source).toBe('outlet');
    expect(men.get(ENGINE_CHASSIS_COMBO)?.rows.map((r) => r.child_service_id)).toEqual([ENGINE_STEAM, CHASSIS_STEAM]);
    const glv = resolveComposition(COMPONENTS, GLV);
    expect(glv.get(ENGINE_CHASSIS_COMBO)?.source).toBe('global');
    expect(glv.get(ENGINE_CHASSIS_COMBO)?.rows.map((r) => r.child_service_id)).toEqual([ENGINE_STEAM]);
  });

  it('detects self-inclusion and cycles', () => {
    const graph = new Map([[ENGINE_CHASSIS_COMBO, [ENGINE_STEAM, CHASSIS_STEAM]]]);
    expect(findCompositionCycle(graph, ENGINE_STEAM, [ENGINE_STEAM])).toEqual([ENGINE_STEAM, ENGINE_STEAM]);
    expect(findCompositionCycle(graph, ENGINE_STEAM, [ENGINE_CHASSIS_COMBO])).toEqual([ENGINE_STEAM, ENGINE_CHASSIS_COMBO, ENGINE_STEAM]);
    expect(findCompositionCycle(graph, SPARKLING_WASH, [ENGINE_CHASSIS_COMBO])).toBeNull();
    expect(findCompositionCycle(graph, ENGINE_CHASSIS_COMBO, [SPARKLING_WASH])).toBeNull();
  });

  it('builds offers: outlet wording, per-size prices, includes/included_in, groups in catalogue order', () => {
    const { offers, groups } = buildOffers(MEN, rows(), { includeUnavailable: true });
    expect(groups).toEqual(['Car Wash Options', 'Combinations', 'Auto Body Repair']);
    const wash = offers.find((o) => o.service_id === SPARKLING_WASH)!;
    expect(wash.name).toBe('"Sparkling wash" - include All of the above');
    expect(wash.price_for).toEqual({ small: 14000, large: 15000, bike: 14000 });
    expect(wash.price_from_cents).toBe(14000);
    expect(wash.price_label).toBe('From R 140');
    expect(wash.points_estimate).toBe(14);
    const combo = offers.find((o) => o.service_id === ENGINE_CHASSIS_COMBO)!;
    expect(combo.components_source).toBe('outlet');
    expect(combo.includes.map((i) => i.code)).toEqual(['ENGINE_STEAM', 'CHASSIS_STEAM']);
    expect(combo.includes[0].name).toBe('Engine steam clean');
    expect(offers.find((o) => o.service_id === CHASSIS_STEAM)!.included_in).toEqual([ENGINE_CHASSIS_COMBO]);
    const bike = offers.find((o) => o.service_id === WASH_BIKE)!;
    expect(bike.price_for).toEqual({ small: 8000, large: 8000, bike: 8000 });
    expect(bike.is_available).toBe(false);
    const tar = offers.find((o) => o.service_id === TAR_REMOVAL)!;
    expect(tar.pricing_mode).toBe('by_quote');
    expect(tar.price_for).toEqual({ small: null, large: null, bike: null });
    expect(tar.price_from_cents).toBeNull();
    expect(tar.price_label).toBe('By quotation');
    expect(tar.points_estimate).toBe(0);
    const headlight = offers.find((o) => o.service_id === HEADLIGHT_RENEWAL)!;
    expect(headlight.vat_mode).toBe('excl');
    expect(headlight.price_for.large).toBe(40000);
    expect(headlight.price_label).toBe('From R 400 excl. VAT');
    expect(headlight.points_estimate).toBe(46); // R 460 incl. VAT × 0.1
    // Glen Village has no outlet rows for the combo → the global default applies.
    const glv = buildOffers(GLV, rows()).offers.find((o) => o.service_id === ENGINE_CHASSIS_COMBO)!;
    expect(glv.components_source).toBe('global');
    expect(glv.includes.map((i) => i.code)).toEqual(['ENGINE_STEAM']);
    // Unavailable offers are hidden by default and dropped from included_in.
    expect(buildOffers(MEN, rows()).offers.some((o) => o.service_id === WASH_BIKE)).toBe(false);
  });

  it('computePrice: add-ons join the base before the tier discount; excl adds 15% VAT after it', () => {
    const gold = { tier: 'gold' as const, name: 'Gold', min_points: 500, max_points: 1999, earn_multiplier: 1.25, discount_pct: 10 };
    const q = computePrice({ basePriceCents: 33000, addons: [{ service_id: ADDON_ODOUR, name: 'Odour', price_cents: 18000 }], vehicleSize: 'large', pricingMode: 'from', vatMode: 'incl', tier: 'gold', tierConfig: gold, pointsPerRand: 0.1 });
    expect(q).toMatchObject({ base_cents: 33000, addons_cents: 18000, price_cents: 51000, discount_cents: 5100, vat_cents: 0, total_cents: 45900, label: 'From R 459', vehicle_size: 'large', points_pending: 46 });
    const excl = computePrice({ basePriceCents: 40000, pricingMode: 'from', vatMode: 'excl', tier: 'gold', tierConfig: gold, pointsPerRand: 0.1 });
    expect(excl).toMatchObject({ price_cents: 40000, discount_cents: 4000, vat_cents: 5400, total_cents: 41400, label: 'From R 414 excl. VAT' });
  });
});

// ---------------------------------------------------------------------------
// HTTP
// ---------------------------------------------------------------------------

let db: FakeSupabase;
let server: Server;
let base: string;

function slotsRpc(args: Record<string, unknown>) {
  const outlet = db.rows('outlets').find((o) => o.id === args.p_outlet);
  const service = db.rows('services').find((s) => s.id === args.p_service);
  if (!outlet || !service) return [];
  const dayStart = new Date(`${args.p_date}T00:00:00.000Z`).getTime() - SAST_OFFSET_MS;
  const dur = service.duration_minutes * 60_000;
  const out: unknown[] = [];
  for (let cursor = dayStart + 7 * 3_600_000; cursor + dur <= dayStart + 18 * 3_600_000; cursor += outlet.slot_minutes * 60_000) {
    const booked = db.rows('bookings').filter((b) => b.outlet_id === outlet.id && ['pending', 'confirmed', 'in_service'].includes(b.status) && new Date(b.slot_start).getTime() < cursor + dur && new Date(b.slot_end).getTime() > cursor).length;
    out.push({ slot_start: new Date(cursor).toISOString(), slot_end: new Date(cursor + dur).toISOString(), capacity: outlet.bay_count, booked, available: booked < outlet.bay_count && cursor > Date.now() });
  }
  return out;
}

async function api(method: string, path: string, token: string, body?: unknown) {
  const res = await fetch(`${base}/v1${path}`, { method, headers: { authorization: `Bearer ${token}`, 'content-type': 'application/json' }, body: body === undefined ? undefined : JSON.stringify(body) });
  const text = await res.text();
  let json: any = null;
  try { json = text ? JSON.parse(text) : null; } catch { json = null; }
  return { status: res.status, json, text };
}

beforeAll(async () => {
  server = createServer(createApp());
  await new Promise<void>((r) => server.listen(0, r));
  base = `http://127.0.0.1:${(server.address() as { port: number }).port}`;
  setFirebaseAuthForTests({
    verifyIdToken: async (token: string) => {
      const users: Record<string, string> = { gold: 'cust_gold', silver: 'cust_silver', admin: 'uid_admin', manager: 'uid_manager', finance: 'uid_finance' };
      if (users[token]) return { uid: users[token], email: `${token}@example.com` };
      throw new Error('bad token');
    },
    setCustomUserClaims: async () => undefined,
  } as any);
});
afterAll(() => server.close());

beforeEach(() => {
  db = fakeSupabase({ rpc: { get_available_slots: slotsRpc } });
  db.seed('feature_flags', [{ key: 'auto_assignment', enabled: false }, { key: 'whatsapp_enabled', enabled: false }]);
  db.seed('profiles', [
    { id: 'cust_gold', role: 'customer', full_name: 'Naledi Mokoena', email: 'gold@example.com', is_active: true, push_opt_in: true, whatsapp_opt_in: false, marketing_opt_in: false },
    { id: 'cust_silver', role: 'customer', full_name: 'Sipho Dlamini', email: 'silver@example.com', is_active: true, push_opt_in: true, whatsapp_opt_in: false, marketing_opt_in: false },
    { id: 'uid_admin', role: 'admin', full_name: 'Ada Admin', email: 'admin@example.com', is_active: true },
    { id: 'uid_manager', role: 'manager', full_name: 'Musa Manager', email: 'manager@example.com', is_active: true },
    { id: 'uid_finance', role: 'finance', full_name: 'Fikile Finance', email: 'finance@example.com', is_active: true },
  ]);
  db.seed('staff_outlets', [{ profile_id: 'uid_manager', outlet_id: MEN, is_primary: true }]);
  db.seed('outlets', [
    { id: MEN, code: 'MEN', name: 'Sparkling Auto Care Centre Menlyn', timezone: 'Africa/Johannesburg', slot_minutes: 30, bay_count: 3, is_active: true, rating: 4.8 },
    { id: GLV, code: 'GLV', name: 'Sparkling Elite Centre Glen Village', timezone: 'Africa/Johannesburg', slot_minutes: 30, bay_count: 2, is_active: true, rating: 4.6 },
  ]);
  db.seed('services', SERVICES.map((s) => ({ ...s })));
  db.seed('outlet_services', BINDINGS.map((b) => ({ ...b })));
  db.seed('service_components', COMPONENTS.map(({ id: _id, ...c }) => ({ ...c })));
  db.seed('loyalty_accounts', [{ customer_id: 'cust_gold', tier: 'gold', balance_points: 700, lifetime_points: 900 }, { customer_id: 'cust_silver', tier: 'silver', balance_points: 0, lifetime_points: 0 }]);
  db.seed('loyalty_configs', [{ id: 'cfg_1', version: 1, status: 'published', rules: { points_per_rand: 0.1 }, tiers: [
    { tier: 'silver', name: 'Silver', min_points: 0, max_points: 499, earn_multiplier: 1, discount_pct: 0 },
    { tier: 'gold', name: 'Gold', min_points: 500, max_points: 1999, earn_multiplier: 1.25, discount_pct: 10 },
    { tier: 'platinum', name: 'Platinum', min_points: 2000, max_points: null, earn_multiplier: 1.5, discount_pct: 15 },
  ] }]);
  db.seed('vehicles', [
    { id: VEH_LARGE, customer_id: 'cust_gold', registration_no: 'HR 88 TS GP', make: 'Toyota', model: 'Fortuner', source: 'manual', disc_verified: false, is_active: true, size_class: 'large' },
    { id: VEH_SMALL, customer_id: 'cust_silver', registration_no: 'CA 123 456', make: 'VW', model: 'Polo', source: 'manual', disc_verified: false, is_active: true, size_class: null },
  ]);
  setSupabaseClient(db as any);
  resetRateLimits();
});

describe('GET /outlets/:id/services', () => {
  it('returns grouped offers with per-size prices, composition and labels', async () => {
    const r = await api('GET', `/outlets/${MEN}/services`, 'gold');
    expect(r.status).toBe(200);
    expect(r.json.groups).toEqual(['Car Wash Options', 'Combinations', 'Auto Body Repair']);
    expect(r.json.tier).toBe('gold');
    expect(r.json.vehicle_size).toBeNull();
    const wash = r.json.data.find((o: any) => o.service_id === SPARKLING_WASH);
    expect(wash).toMatchObject({ code: 'SPARKLING_WASH', name: '"Sparkling wash" - include All of the above', group_name: 'Car Wash Options', pricing_mode: 'from', vat_mode: 'incl', price_from_cents: 14000, price_for: { small: 14000, large: 15000, bike: 14000 }, price_label: 'From R 140', is_addon: false });
    expect(wash.price_cents).toBeUndefined();
    const combo = r.json.data.find((o: any) => o.service_id === ENGINE_CHASSIS_COMBO);
    expect(combo.includes.map((i: any) => i.code)).toEqual(['ENGINE_STEAM', 'CHASSIS_STEAM']);
    expect(r.json.data.find((o: any) => o.service_id === TAR_REMOVAL)).toMatchObject({ pricing_mode: 'by_quote', price_from_cents: null, price_label: 'By quotation' });
    expect(r.json.data.find((o: any) => o.service_id === ADDON_ODOUR)).toMatchObject({ is_addon: true, addon_group_name: 'Combinations', price_for: { small: 18000, large: 18000, bike: 18000 } });
    expect(r.json.data.some((o: any) => o.service_id === WASH_BIKE)).toBe(false); // unavailable at Menlyn
  });

  it('?vehicle_size resolves price_cents and the caller’s tier discount / VAT', async () => {
    const gold = await api('GET', `/outlets/${MEN}/services?vehicle_size=large`, 'gold');
    expect(gold.status).toBe(200);
    expect(gold.json.vehicle_size).toBe('large');
    expect(gold.json.data.find((o: any) => o.service_id === SPARKLING_WASH)).toMatchObject({ price_cents: 15000, discount_cents: 1500, vat_cents: 0, total_cents: 13500, discount_label: 'Gold −10%', price_label: 'From R 135', points_estimate: 14 });
    expect(gold.json.data.find((o: any) => o.service_id === TAR_REMOVAL)).toMatchObject({ price_cents: null, total_cents: null });
    const silver = await api('GET', `/outlets/${MEN}/services?vehicle_size=small`, 'silver');
    expect(silver.json.data.find((o: any) => o.service_id === HEADLIGHT_RENEWAL)).toMatchObject({ price_cents: 40000, discount_cents: 0, vat_cents: 6000, total_cents: 46000, price_label: 'From R 460 excl. VAT' });
    expect((await api('GET', `/outlets/${MEN}/services?vehicle_size=huge`, 'gold')).status).toBe(400);
  });

  it('falls back to the global composition where the outlet has no rows', async () => {
    const r = await api('GET', `/outlets/${GLV}/services`, 'gold');
    const combo = r.json.data.find((o: any) => o.service_id === ENGINE_CHASSIS_COMBO);
    expect(combo.components_source).toBe('global');
    expect(combo.includes.map((i: any) => i.code)).toEqual(['ENGINE_STEAM']);
    expect(r.json.data.find((o: any) => o.service_id === SPARKLING_WASH).price_for).toEqual({ small: 16000, large: 18000, bike: 16000 });
  });
});

describe('POST /bookings — catalogue pricing', () => {
  it('prices a from-price combo + add-on for the vehicle size with the Gold discount and stores the pricing basis', async () => {
    const r = await api('POST', '/bookings', 'gold', { vehicle_id: VEH_LARGE, outlet_id: MEN, service_id: ENGINE_CHASSIS_COMBO, slot_start: SLOT, client_op_id: 'op_combo_1', addon_service_ids: [ADDON_ODOUR] });
    expect(r.status).toBe(201);
    const b = r.json.booking;
    expect(b).toMatchObject({ vehicle_size: 'large', pricing_mode: 'from', vat_mode: 'incl', price_cents: 51000, addons_cents: 18000, discount_cents: 5100, total_cents: 45900, discount_label: 'Gold −10%', points_pending: 46, addon_service_ids: [ADDON_ODOUR], price_label: 'From R 459' });
    expect(b.addons).toEqual([{ service_id: ADDON_ODOUR, name: 'Add to any Combo: Odour Removal', price_cents: 18000 }]);
    const stored = db.rows('bookings').find((x) => x.id === b.id)!;
    expect(stored).toMatchObject({ vehicle_size: 'large', pricing_mode: 'from', vat_mode: 'incl', addon_service_ids: [ADDON_ODOUR], addons_cents: 18000, total_cents: 45900 });
    const detail = await api('GET', `/bookings/${b.id}`, 'gold');
    expect(detail.status).toBe(200);
    expect(detail.json.addons[0].name).toBe('Add to any Combo: Odour Removal');
    expect(detail.json.price_label).toBe('From R 459');
    const audit = db.rows('audit_events').find((a) => a.action === 'booking.create');
    expect(audit?.after).toMatchObject({ vehicle_size: 'large', addons_cents: 18000 });
  });

  it('an explicit vehicle_size overrides the vehicle’s size class', async () => {
    const r = await api('POST', '/bookings', 'gold', { vehicle_id: VEH_LARGE, outlet_id: MEN, service_id: SPARKLING_WASH, slot_start: SLOT, client_op_id: 'op_wash_small', vehicle_size: 'small' });
    expect(r.status).toBe(201);
    expect(r.json.booking).toMatchObject({ vehicle_size: 'small', price_cents: 14000, addons_cents: 0, total_cents: 12600, addons: [] });
  });

  it('excl-VAT auto body work adds 15% VAT on the total', async () => {
    const r = await api('POST', '/bookings', 'silver', { vehicle_id: VEH_SMALL, outlet_id: MEN, service_id: HEADLIGHT_RENEWAL, slot_start: SLOT, client_op_id: 'op_headlight_1' });
    expect(r.status).toBe(201);
    expect(r.json.booking).toMatchObject({ vehicle_size: 'small', vat_mode: 'excl', price_cents: 40000, discount_cents: 0, total_cents: 46000, points_pending: 46, price_label: 'From R 460 excl. VAT' });
  });

  it('refuses a by-quote service with 409 validation_error { reason: by_quote }', async () => {
    const r = await api('POST', '/bookings', 'gold', { vehicle_id: VEH_LARGE, outlet_id: MEN, service_id: TAR_REMOVAL, slot_start: SLOT, client_op_id: 'op_tar_1' });
    expect(r.status).toBe(409);
    expect(r.json.error.code).toBe('validation_error');
    expect(r.json.error.details).toMatchObject({ reason: 'by_quote', service_id: TAR_REMOVAL, outlet_id: MEN });
    expect(db.rows('bookings')).toHaveLength(0);
  });

  it('rejects an add-on from another group, a non-add-on and an add-on not offered here (400)', async () => {
    const mismatch = await api('POST', '/bookings', 'gold', { vehicle_id: VEH_LARGE, outlet_id: MEN, service_id: SPARKLING_WASH, slot_start: SLOT, client_op_id: 'op_mismatch', addon_service_ids: [ADDON_ODOUR] });
    expect(mismatch.status).toBe(400);
    expect(mismatch.json.error.details[0]).toMatchObject({ path: 'addon_service_ids', message: 'Add-on group mismatch', addon_group_name: 'Combinations', group_name: 'Car Wash Options' });
    const notAddon = await api('POST', '/bookings', 'gold', { vehicle_id: VEH_LARGE, outlet_id: MEN, service_id: ENGINE_CHASSIS_COMBO, slot_start: SLOT, client_op_id: 'op_notaddon', addon_service_ids: [ENGINE_STEAM] });
    expect(notAddon.status).toBe(400);
    expect(notAddon.json.error.details[0].message).toBe('Not an add-on');
    const notHere = await api('POST', '/bookings', 'gold', { vehicle_id: VEH_LARGE, outlet_id: GLV, service_id: ENGINE_CHASSIS_COMBO, slot_start: SLOT, client_op_id: 'op_nothere', addon_service_ids: [ADDON_ODOUR] });
    expect(notHere.status).toBe(400);
    expect(notHere.json.error.details[0].message).toBe('Not offered here');
    expect(db.rows('bookings')).toHaveLength(0);
  });
});

describe('vehicles — size_class', () => {
  it('derives size_class from the disc description on create, explicit size_class wins, PATCH updates it', async () => {
    const wagon = await api('POST', '/vehicles', 'silver', { registration_no: 'ND 1 GP', description: 'Station wagon', source: 'manual' });
    expect(wagon.status).toBe(201);
    expect(wagon.json.vehicle.size_class).toBe('large');
    const sedan = await api('POST', '/vehicles', 'silver', { registration_no: 'ND 2 GP', description: 'Sedan (closed top)', source: 'manual' });
    expect(sedan.json.vehicle.size_class).toBe('small');
    const bike = await api('POST', '/vehicles', 'silver', { registration_no: 'ND 3 GP', description: 'Motorcycle', source: 'manual' });
    expect(bike.json.vehicle.size_class).toBe('bike');
    const explicit = await api('POST', '/vehicles', 'silver', { registration_no: 'ND 4 GP', description: 'Station wagon', size_class: 'small', source: 'manual' });
    expect(explicit.json.vehicle.size_class).toBe('small');
    const unknown = await api('POST', '/vehicles', 'silver', { registration_no: 'ND 5 GP', source: 'manual' });
    expect(unknown.json.vehicle.size_class).toBeNull();
    expect((await api('POST', '/vehicles', 'silver', { registration_no: 'ND 6 GP', size_class: 'huge' })).status).toBe(400);
    const patched = await api('PATCH', `/vehicles/${VEH_SMALL}`, 'silver', { size_class: 'large' });
    expect(patched.status).toBe(200);
    expect(patched.json.vehicle.size_class).toBe('large');
    const derived = await api('PATCH', `/vehicles/${VEH_SMALL}`, 'silver', { description: 'Motorcycle' });
    expect(derived.json.vehicle.size_class).toBe('bike');
    // The booking default follows the vehicle: bike prices as small.
    const booking = await api('POST', '/bookings', 'silver', { vehicle_id: VEH_SMALL, outlet_id: MEN, service_id: SPARKLING_WASH, slot_start: SLOT, client_op_id: 'op_bike_1' });
    expect(booking.status).toBe(201);
    expect(booking.json.booking).toMatchObject({ vehicle_size: 'bike', price_cents: 14000 });
  });
});

describe('admin — services', () => {
  it('lists services with the global composition only', async () => {
    const r = await api('GET', '/admin/services', 'manager');
    expect(r.status).toBe(200);
    const combo = r.json.data.find((s: any) => s.id === ENGINE_CHASSIS_COMBO);
    expect(combo.components).toEqual([{ child_service_id: ENGINE_STEAM, code: 'ENGINE_STEAM', name: 'Engine steam clean', quantity: 1, sort_order: 10 }]);
    expect(r.json.data.find((s: any) => s.id === SPARKLING_WASH).components).toEqual([]);
    expect(r.json.data.map((s: any) => s.group_name).indexOf('Auto Body Repair')).toBeGreaterThan(r.json.data.map((s: any) => s.group_name).indexOf('Combinations'));
  });

  it('validates pricing mode / prices / add-on group on create', async () => {
    const byQuote = await api('POST', '/admin/services', 'admin', { code: 'MAG_WHEEL', name: 'Mag wheel repair', category: 'auto_body', duration_minutes: 120, group_name: 'Auto Body Repair', pricing_mode: 'by_quote', vat_mode: 'excl' });
    expect(byQuote.status).toBe(201);
    expect(byQuote.json.service).toMatchObject({ code: 'MAG_WHEEL', pricing_mode: 'by_quote', is_quote_based: true, components: [] });
    const noPrice = await api('POST', '/admin/services', 'admin', { code: 'NO_PRICE', name: 'Priceless', category: 'car_wash', duration_minutes: 30, pricing_mode: 'from' });
    expect(noPrice.status).toBe(400);
    expect(noPrice.json.error.details[0].path).toBe('price_small_cents');
    const addon = await api('POST', '/admin/services', 'admin', { code: 'ADDON_X', name: 'Add-on X', category: 'car_wash', duration_minutes: 15, pricing_mode: 'fixed', price_general_cents: 5000, is_addon: true });
    expect(addon.status).toBe(400);
    expect(addon.json.error.details[0].path).toBe('addon_group_name');
    const ok = await api('POST', '/admin/services', 'admin', { code: 'ADDON_X', name: 'Add-on X', category: 'car_wash', duration_minutes: 15, pricing_mode: 'fixed', price_general_cents: 5000, is_addon: true, addon_group_name: 'Combinations' });
    expect(ok.status).toBe(201);
    expect(ok.json.service).toMatchObject({ is_addon: true, addon_group_name: 'Combinations', price_general_cents: 5000, base_price_cents: 5000 });
    expect((await api('POST', '/admin/services', 'manager', { code: 'X', name: 'X' })).status).toBe(403);
  });

  it('creates and replaces the global composition; rejects self-inclusion and cycles', async () => {
    const created = await api('POST', '/admin/services', 'admin', { code: 'FULL_MONTY', name: 'The Full Monty', category: 'car_wash', duration_minutes: 240, group_name: 'Combinations', pricing_mode: 'from', price_small_cents: 150000, components: [{ child_service_id: ENGINE_CHASSIS_COMBO }, { child_service_id: SPARKLING_WASH, quantity: 2 }] });
    expect(created.status).toBe(201);
    expect(created.json.service.components.map((c: any) => [c.code, c.quantity])).toEqual([['ENGINE_CHASSIS_COMBO', 1], ['SPARKLING_WASH', 2]]);
    const id = created.json.service.id;
    const replaced = await api('PUT', `/admin/services/${id}`, 'admin', { components: [{ child_service_id: SPARKLING_WASH }] });
    expect(replaced.status).toBe(200);
    expect(replaced.json.service.components.map((c: any) => c.code)).toEqual(['SPARKLING_WASH']);
    expect(db.rows('service_components').filter((c) => c.parent_service_id === id)).toHaveLength(1);
    const self = await api('PUT', `/admin/services/${id}`, 'admin', { components: [{ child_service_id: id }] });
    expect(self.status).toBe(400);
    expect(self.json.error.details[0].message).toBe('A service cannot include itself');
    // Global graph: COMBO → ENGINE_STEAM. Making ENGINE_STEAM include COMBO closes the loop.
    const cycle = await api('PUT', `/admin/services/${ENGINE_STEAM}`, 'admin', { components: [{ child_service_id: ENGINE_CHASSIS_COMBO }] });
    expect(cycle.status).toBe(400);
    expect(cycle.json.error.message).toContain('ENGINE_STEAM → ENGINE_CHASSIS_COMBO → ENGINE_STEAM');
    expect(db.rows('service_components').filter((c) => c.parent_service_id === ENGINE_STEAM)).toHaveLength(0);
    expect(db.rows('audit_events').filter((a) => a.action === 'service.update')).toHaveLength(1);
  });

  it('allows a non-pricing edit of a legacy service without default prices, but not switching it to from/fixed without one', async () => {
    const rename = await api('PUT', `/admin/services/${SPARKLING_WASH}`, 'admin', { name: 'Sparkling Wash (full)' });
    expect(rename.status).toBe(200);
    expect(rename.json.service.name).toBe('Sparkling Wash (full)');
    const toFixed = await api('PATCH', `/admin/services/${SPARKLING_WASH}`, 'admin', { pricing_mode: 'fixed' });
    expect(toFixed.status).toBe(400);
    const priced = await api('PATCH', `/admin/services/${SPARKLING_WASH}`, 'admin', { pricing_mode: 'fixed', price_small_cents: 14000 });
    expect(priced.status).toBe(200);
    expect(priced.json.service).toMatchObject({ pricing_mode: 'fixed', is_quote_based: false, price_small_cents: 14000, base_price_cents: 14000 });
    expect((await api('PUT', '/admin/services/00000000-0000-4000-8000-000000000000', 'admin', { name: 'Nope' })).status).toBe(404);
  });
});

describe('admin — outlet services', () => {
  it('lists offers incl. unavailable with components_source, scoped to visible outlets', async () => {
    const r = await api('GET', `/admin/outlets/${MEN}/services`, 'manager');
    expect(r.status).toBe(200);
    expect(r.json.groups).toEqual(['Car Wash Options', 'Combinations', 'Auto Body Repair']);
    expect(r.json.data.find((o: any) => o.service_id === WASH_BIKE)).toMatchObject({ is_available: false, price_for: { small: 8000, large: 8000, bike: 8000 } });
    expect(r.json.data.find((o: any) => o.service_id === ENGINE_CHASSIS_COMBO).components_source).toBe('outlet');
    expect(r.json.data.find((o: any) => o.service_id === SPARKLING_WASH).components_source).toBe('none');
    expect((await api('GET', `/admin/outlets/${GLV}/services`, 'manager')).status).toBe(403);
    expect((await api('GET', `/admin/outlets/${GLV}/services`, 'admin')).json.data.find((o: any) => o.service_id === ENGINE_CHASSIS_COMBO).components_source).toBe('global');
  });

  it('PUT upserts wording, prices, mode and an outlet-specific composition; null components → global', async () => {
    const put = await api('PUT', `/admin/outlets/${GLV}/services/${ENGINE_CHASSIS_COMBO}`, 'admin', { display_name: 'Engine + chassis combo', price_small_cents: 32000, price_large_cents: 34000, sort_order: 5, components: [{ child_service_id: CHASSIS_STEAM }, { child_service_id: ENGINE_STEAM, sort_order: 20 }] });
    expect(put.status).toBe(200);
    expect(put.json.outlet_service).toMatchObject({ service_id: ENGINE_CHASSIS_COMBO, name: 'Engine + chassis combo', price_for: { small: 32000, large: 34000, bike: 32000 }, components_source: 'outlet', sort_order: 5 });
    expect(put.json.outlet_service.includes.map((i: any) => i.code)).toEqual(['CHASSIS_STEAM', 'ENGINE_STEAM']);
    const row = db.rows('outlet_services').find((o) => o.outlet_id === GLV && o.service_id === ENGINE_CHASSIS_COMBO)!;
    expect(row).toMatchObject({ display_name: 'Engine + chassis combo', price_small_cents: 32000, price_large_cents: 34000, price_cents: 32000, is_available: true });
    expect(db.rows('service_components').filter((c) => c.parent_service_id === ENGINE_CHASSIS_COMBO && c.outlet_id === GLV)).toHaveLength(2);
    expect(db.rows('service_components').filter((c) => c.parent_service_id === ENGINE_CHASSIS_COMBO && c.outlet_id === MEN)).toHaveLength(2); // Menlyn untouched
    const audit = db.rows('audit_events').filter((a) => a.action === 'outlet_service.update');
    expect(audit).toHaveLength(1);
    expect(audit[0].after.components).toHaveLength(2);

    const back = await api('PUT', `/admin/outlets/${GLV}/services/${ENGINE_CHASSIS_COMBO}`, 'admin', { components: null });
    expect(back.status).toBe(200);
    expect(back.json.outlet_service).toMatchObject({ components_source: 'global', name: 'Engine + chassis combo', price_for: { small: 32000, large: 34000, bike: 32000 } });
    expect(back.json.outlet_service.includes.map((i: any) => i.code)).toEqual(['ENGINE_STEAM']);
    expect(db.rows('service_components').filter((c) => c.parent_service_id === ENGINE_CHASSIS_COMBO && c.outlet_id === GLV)).toHaveLength(0);

    // The new binding is immediately visible to customers with the outlet wording.
    const offers = await api('GET', `/outlets/${GLV}/services?vehicle_size=large`, 'gold');
    expect(offers.json.data.find((o: any) => o.service_id === ENGINE_CHASSIS_COMBO)).toMatchObject({ name: 'Engine + chassis combo', price_cents: 34000 });
  });

  it('PUT creates a new binding, refuses from/fixed without any price, accepts by_quote, rejects outlet cycles', async () => {
    const noPrice = await api('PUT', `/admin/outlets/${GLV}/services/${TAR_REMOVAL}`, 'admin', { pricing_mode: 'from' });
    expect(noPrice.status).toBe(400);
    const byQuote = await api('PUT', `/admin/outlets/${GLV}/services/${TAR_REMOVAL}`, 'admin', { display_name: 'Tar removal', pricing_mode: 'by_quote' });
    expect(byQuote.status).toBe(200);
    expect(byQuote.json.outlet_service).toMatchObject({ pricing_mode: 'by_quote', price_label: 'By quotation', is_available: true });
    const inherit = await api('PUT', `/admin/outlets/${GLV}/services/${TAR_REMOVAL}`, 'admin', { pricing_mode: null });
    expect(inherit.json.outlet_service.pricing_mode).toBe('by_quote'); // service default
    const cycle = await api('PUT', `/admin/outlets/${MEN}/services/${ENGINE_STEAM}`, 'admin', { components: [{ child_service_id: ENGINE_CHASSIS_COMBO }] });
    expect(cycle.status).toBe(400);
    expect(cycle.json.error.details[0].message).toBe('Cyclic composition');
    expect((await api('PUT', `/admin/outlets/${GLV}/services/00000000-0000-4000-8000-000000000000`, 'admin', { is_available: true })).status).toBe(404);
    expect((await api('PUT', `/admin/outlets/${GLV}/services/${TAR_REMOVAL}`, 'manager', { is_available: true })).status).toBe(403);
  });

  it('DELETE removes the binding and its outlet composition rows', async () => {
    const del = await api('DELETE', `/admin/outlets/${MEN}/services/${ENGINE_CHASSIS_COMBO}`, 'admin');
    expect(del.status).toBe(204);
    expect(db.rows('outlet_services').some((o) => o.outlet_id === MEN && o.service_id === ENGINE_CHASSIS_COMBO)).toBe(false);
    expect(db.rows('service_components').filter((c) => c.parent_service_id === ENGINE_CHASSIS_COMBO && c.outlet_id === MEN)).toHaveLength(0);
    expect(db.rows('service_components').filter((c) => c.parent_service_id === ENGINE_CHASSIS_COMBO && c.outlet_id === null)).toHaveLength(1);
    expect((await api('DELETE', `/admin/outlets/${MEN}/services/${ENGINE_CHASSIS_COMBO}`, 'admin')).status).toBe(404);
    expect((await api('GET', `/outlets/${MEN}/services`, 'gold')).json.data.some((o: any) => o.service_id === ENGINE_CHASSIS_COMBO)).toBe(false);
  });
});

describe('admin — bookings CSV', () => {
  it('exports vehicle_size, addons (names) and vat_mode', async () => {
    db.seed('bookings', [
      { id: '10000000-0000-4000-8000-000000000001', ref: 'SPK-2026-0001', customer_id: 'cust_gold', vehicle_id: VEH_LARGE, outlet_id: MEN, service_id: ENGINE_CHASSIS_COMBO, status: 'confirmed', slot_start: '2026-09-02T08:00:00.000Z', slot_end: '2026-09-02T09:00:00.000Z', price_cents: 51000, discount_cents: 5100, total_cents: 45900, points_pending: 46, vehicle_size: 'large', pricing_mode: 'from', vat_mode: 'incl', addon_service_ids: [ADDON_ODOUR], addons_cents: 18000 },
      { id: '10000000-0000-4000-8000-000000000002', ref: 'SPK-2026-0002', customer_id: 'cust_silver', vehicle_id: VEH_SMALL, outlet_id: MEN, service_id: HEADLIGHT_RENEWAL, status: 'completed', slot_start: '2026-09-03T08:00:00.000Z', slot_end: '2026-09-03T09:00:00.000Z', price_cents: 40000, discount_cents: 0, total_cents: 46000, points_pending: 46, vehicle_size: 'small', pricing_mode: 'from', vat_mode: 'excl', addon_service_ids: [], addons_cents: 0 },
    ]);
    const r = await api('GET', '/admin/exports/bookings.csv?from=2026-09-01T00:00:00Z&to=2026-09-30T00:00:00Z', 'finance');
    expect(r.status).toBe(200);
    const lines = r.text.trim().split('\n');
    const header = lines.find((l) => l.startsWith('ref,'))!;
    expect(header).toBe('ref,status,slot_start,slot_end,outlet,service,category,customer,registration_no,price_cents,discount_cents,total_cents,points_pending,vehicle_size,addons,vat_mode');
    const row1 = lines.find((l) => l.startsWith('SPK-2026-0001'))!;
    expect(row1.endsWith(',large,Add-on: odour removal,incl')).toBe(true);
    const row2 = lines.find((l) => l.startsWith('SPK-2026-0002'))!;
    expect(row2.endsWith(',small,,excl')).toBe(true);
  });
});
