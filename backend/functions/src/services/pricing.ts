/**
 * Pricing & points (CUS-020/060..062; catalogue pricing model, migration 0008).
 *
 * base_cents       = outlet price for the vehicle size (small/large; general when
 *                    size-independent; bike → small) ?? service default
 * addons_cents     = Σ add-on prices resolved the same way (add-ons must be
 *                    `is_addon` with `addon_group_name` = the base service's group)
 * price_cents      = base + add-ons
 * discount         = membership benefit (docs/MEMBERSHIPS.md "Pricing rules"):
 *                      included → discount = base (add-ons still charged),
 *                                 label "Included in Gold · 2 of 4 left"
 *                      discount → round(price × plan.discount_pct / 100),
 *                                 label "Gold −10%"
 *                    else the tier discount from the PUBLISHED loyalty config
 *                    (kept as a fallback; 0 for every tier since the plans
 *                    carry the discounts)
 * vat_cents        = 15% of (price − discount) when vat_mode = excl, else 0
 * total            = price − discount + vat
 * `by_quote` services have no price and are refused with 409 validation_error
 * { reason: 'by_quote' }; `from` prices are minimums ("From R x").
 *
 * Points rule (documented, matches the API.md reference payload and seed):
 *   points_pending = round(total_rand × rules.points_per_rand)
 *   → the base estimate shown at booking time (R198 × 0.10 = 19.8 → 20 pts).
 *   The tier `earn_multiplier` is applied when the earn ledger entry is posted
 *   on verification: earned = round(points_pending × earn_multiplier)
 *   (Gold 1.25 → 20 × 1.25 = 25 pts). Rounding is half-up (Math.round).
 */
import { getSupabase, unwrap } from '../lib/supabase.js';
import type { LoyaltyConfig, LoyaltyTier, LoyaltyTierConfig, Outlet, OutletServiceOffer, PricingMode, Service, VatMode, VehicleSize } from '../types.js';
import { VAT_RATE } from '../types.js';
import { ApiError } from '../middleware/errors.js';
import { listOutletOffers, priceLabel, resolveOfferPrice } from './catalogue.js';
import { benefitFor, loadContext, type MembershipBenefit, type MembershipContext } from './memberships.js';

export interface PriceAddon {
  service_id: string;
  name: string;
  price_cents: number;
}

/** Membership block on a quote (`membership: null` when the customer has no active plan). */
export interface PriceQuoteMembership {
  membership_id: string;
  plan_code: string;
  plan_name: string;
  benefit: 'included' | 'discount' | null;
  entitlement_id: string | null;
  entitlement_code: string | null;
  /** Allowance left after this booking (included only). */
  remaining_after: number | null;
  period_end: string | null;
}

export interface PriceQuote {
  /** base + add-ons before discount (legacy name kept for bookings.price_cents). */
  price_cents: number;
  base_cents: number;
  addons_cents: number;
  addons: PriceAddon[];
  discount_cents: number;
  vat_cents: number;
  total_cents: number;
  discount_label: string | null;
  /** "From R 150" for `from` pricing, "R 150" for fixed; "excl. VAT" suffix when applicable. */
  label: string;
  vehicle_size: VehicleSize;
  pricing_mode: PricingMode;
  vat_mode: VatMode;
  points_pending: number;
  tier: LoyaltyTier;
  earn_multiplier: number;
  membership: PriceQuoteMembership | null;
}

export interface PriceInput {
  basePriceCents: number;
  outletPriceCents?: number | null;
  addons?: PriceAddon[];
  vehicleSize?: VehicleSize;
  pricingMode?: PricingMode;
  vatMode?: VatMode;
  tier: LoyaltyTier;
  tierConfig: LoyaltyTierConfig | null;
  pointsPerRand: number;
  /** Resolved plan benefit for this service (see `benefitFor`); null/undefined = no active membership. */
  membership?: MembershipBenefit | null;
}

export function effectivePrice(basePriceCents: number, outletPriceCents?: number | null): number {
  return outletPriceCents === null || outletPriceCents === undefined ? basePriceCents : outletPriceCents;
}

export function roundHalfUp(n: number): number {
  return Math.round(n + Number.EPSILON);
}

export function estimatePoints(totalCents: number, pointsPerRand: number): number {
  return Math.max(0, roundHalfUp((totalCents / 100) * pointsPerRand));
}

export function applyMultiplier(points: number, earnMultiplier: number): number {
  return Math.max(0, roundHalfUp(points * (earnMultiplier || 1)));
}

export function computePrice(input: PriceInput): PriceQuote {
  const base = effectivePrice(input.basePriceCents, input.outletPriceCents);
  const addons = input.addons ?? [];
  const addonsCents = addons.reduce((sum, a) => sum + a.price_cents, 0);
  const price = base + addonsCents;
  const m = input.membership ?? null;
  let discount = 0;
  let discountLabel: string | null = null;
  if (m?.benefit === 'included') {
    // The plan covers the base service for this vehicle size; add-ons are still charged.
    discount = base;
    discountLabel = `Included in ${m.plan_name} · ${m.remaining_after ?? 0} of ${m.entitlement_quantity ?? 0} left`;
  } else if (m?.benefit === 'discount' && m.discount_pct > 0) {
    discount = roundHalfUp((price * m.discount_pct) / 100);
    discountLabel = `${m.plan_name} −${m.discount_pct}%`;
  } else {
    const pct = input.tierConfig?.discount_pct ?? 0;
    discount = pct > 0 ? roundHalfUp((price * pct) / 100) : 0;
    discountLabel = discount > 0 ? `${input.tierConfig?.name ?? capitalize(input.tier)} −${pct}%` : null;
  }
  const net = Math.max(0, price - discount);
  const vatMode = input.vatMode ?? 'incl';
  const vat = vatMode === 'excl' ? roundHalfUp(net * VAT_RATE) : 0;
  const total = net + vat;
  const pricingMode = input.pricingMode ?? 'fixed';
  return {
    price_cents: price,
    base_cents: base,
    addons_cents: addonsCents,
    addons,
    discount_cents: discount,
    vat_cents: vat,
    total_cents: total,
    discount_label: discountLabel,
    label: priceLabel(pricingMode, total, vatMode),
    vehicle_size: input.vehicleSize ?? 'small',
    pricing_mode: pricingMode,
    vat_mode: vatMode,
    points_pending: estimatePoints(total, input.pointsPerRand),
    tier: input.tier,
    earn_multiplier: input.tierConfig?.earn_multiplier ?? 1,
    membership: m ? { membership_id: m.membership_id, plan_code: m.plan_code, plan_name: m.plan_name, benefit: m.benefit, entitlement_id: m.entitlement_id, entitlement_code: m.entitlement_code, remaining_after: m.remaining_after, period_end: m.period_end } : null,
  };
}

function capitalize(s: string): string {
  return s.charAt(0).toUpperCase() + s.slice(1);
}

export function tierFor(config: LoyaltyConfig | null, tier: LoyaltyTier): LoyaltyTierConfig | null {
  return config?.tiers.find((t) => t.tier === tier) ?? null;
}

/** Which tier a lifetime/balance figure maps to under a config (highest matching). */
export function tierForPoints(config: LoyaltyConfig | null, points: number): LoyaltyTier {
  if (!config) return 'silver';
  const sorted = [...config.tiers].sort((a, b) => a.min_points - b.min_points);
  let result: LoyaltyTier = 'silver';
  for (const t of sorted) if (points >= t.min_points) result = t.tier;
  return result;
}

export async function getPublishedLoyaltyConfig(): Promise<LoyaltyConfig | null> {
  const db = getSupabase();
  const res = await db.from('loyalty_configs').select('*').eq('status', 'published').maybeSingle();
  return unwrap<LoyaltyConfig | null>(res, 'published loyalty config');
}

export async function getCustomerTier(customerId: string): Promise<LoyaltyTier> {
  const db = getSupabase();
  const res = await db.from('loyalty_accounts').select('tier').eq('customer_id', customerId).maybeSingle();
  const row = unwrap<{ tier: LoyaltyTier } | null>(res, 'loyalty account');
  return row?.tier ?? 'silver';
}

export interface PriceServiceOptions {
  vehicleSize?: VehicleSize | null;
  addonServiceIds?: string[] | null;
  /** Pre-loaded membership context (skips the lookup); `null` = the customer has none. */
  membership?: MembershipContext | null;
}

/**
 * Resolves the add-ons attached to a base offer at an outlet: each must be an
 * available `is_addon` offer whose `addon_group_name` is the base's group and
 * must carry a price for the vehicle size (400 otherwise).
 */
export function resolveAddons(base: OutletServiceOffer, offers: OutletServiceOffer[], addonServiceIds: string[], size: VehicleSize): PriceAddon[] {
  const ids = [...new Set(addonServiceIds)];
  const out: PriceAddon[] = [];
  for (const id of ids) {
    const offer = offers.find((o) => o.service_id === id);
    if (!offer || !offer.is_available) throw ApiError.validation('Add-on is not available at this outlet', [{ path: 'addon_service_ids', service_id: id, message: 'Not offered here' }]);
    if (!offer.is_addon) throw ApiError.validation('Service is not an add-on', [{ path: 'addon_service_ids', service_id: id, message: 'Not an add-on' }]);
    if (id === base.service_id) throw ApiError.validation('An add-on cannot be the booked service', [{ path: 'addon_service_ids', service_id: id, message: 'Same as service_id' }]);
    if (!offer.addon_group_name || offer.addon_group_name !== base.group_name) {
      throw ApiError.validation(`Add-on "${offer.name}" attaches to ${offer.addon_group_name ?? 'no group'}, not to ${base.group_name}`, [
        { path: 'addon_service_ids', service_id: id, message: 'Add-on group mismatch', addon_group_name: offer.addon_group_name, group_name: base.group_name },
      ]);
    }
    const price = resolveOfferPrice(offer, size);
    if (price === null) throw ApiError.validation(`Add-on "${offer.name}" has no price for this vehicle size`, [{ path: 'addon_service_ids', service_id: id, message: 'No price', vehicle_size: size }]);
    out.push({ service_id: id, name: offer.name, price_cents: price });
  }
  return out;
}

/** Loads catalogue rows and prices a service (+ add-ons) for a customer at an outlet, for a vehicle size. */
export async function priceService(
  outletId: string,
  serviceId: string,
  customerId: string,
  opts: PriceServiceOptions = {},
): Promise<{ quote: PriceQuote; service: Service; outlet: Outlet; offer: OutletServiceOffer; addons: PriceAddon[] }> {
  const db = getSupabase();
  const [outletRes, serviceRes, offerList, cfg, tier, membership] = await Promise.all([
    db.from('outlets').select('*').eq('id', outletId).eq('is_active', true).maybeSingle(),
    db.from('services').select('*').eq('id', serviceId).eq('is_active', true).maybeSingle(),
    listOutletOffers(outletId, { includeUnavailable: true }),
    getPublishedLoyaltyConfig(),
    getCustomerTier(customerId),
    opts.membership === undefined ? loadContext(customerId) : Promise.resolve(opts.membership),
  ]);
  const outlet = unwrap<Outlet | null>(outletRes, 'outlet');
  const service = unwrap<Service | null>(serviceRes, 'service');
  if (!outlet) throw ApiError.notFound('Outlet');
  if (!service) throw ApiError.notFound('Service');
  const offer = offerList.offers.find((o) => o.service_id === serviceId);
  if (!offer || !offer.is_available) throw ApiError.validation('Service is not available at this outlet');
  if (offer.pricing_mode === 'by_quote' || service.is_quote_based) {
    throw ApiError.validationConflict('This service is priced by quotation; request a quote instead (POST /v1/quotations)', { reason: 'by_quote', service_id: serviceId, outlet_id: outletId });
  }
  const size: VehicleSize = opts.vehicleSize ?? 'small';
  const base = resolveOfferPrice(offer, size);
  if (base === null) throw ApiError.validation('Service has no price at this outlet', [{ path: 'service_id', message: 'No price', vehicle_size: size }]);
  const addons = resolveAddons(offer, offerList.offers, opts.addonServiceIds ?? [], size);
  const quote = computePrice({
    basePriceCents: base,
    addons,
    vehicleSize: size,
    pricingMode: offer.pricing_mode,
    vatMode: offer.vat_mode,
    tier,
    tierConfig: tierFor(cfg, tier),
    pointsPerRand: Number(cfg?.rules?.points_per_rand ?? service.points_per_rand ?? 0.1),
    membership: benefitFor(serviceId, membership),
  });
  return { quote, service, outlet, offer, addons };
}
