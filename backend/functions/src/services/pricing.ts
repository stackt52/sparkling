/**
 * Pricing & points (CUS-020/060..062).
 *
 * effective price  = outlet_services.price_cents ?? services.base_price_cents
 * discount         = round(price × tier.discount_pct / 100) from the PUBLISHED
 *                    loyalty config for the customer's tier
 * total            = price − discount
 *
 * Points rule (documented, matches the API.md reference payload and seed):
 *   points_pending = round(total_rand × rules.points_per_rand)
 *   → the base estimate shown at booking time (R198 × 0.10 = 19.8 → 20 pts).
 *   The tier `earn_multiplier` is applied when the earn ledger entry is posted
 *   on verification: earned = round(points_pending × earn_multiplier)
 *   (Gold 1.25 → 20 × 1.25 = 25 pts). Rounding is half-up (Math.round).
 */
import { getSupabase, unwrap } from '../lib/supabase.js';
import type { LoyaltyConfig, LoyaltyTier, LoyaltyTierConfig, Outlet, Service } from '../types.js';
import { ApiError } from '../middleware/errors.js';

export interface PriceQuote {
  price_cents: number;
  discount_cents: number;
  total_cents: number;
  discount_label: string | null;
  points_pending: number;
  tier: LoyaltyTier;
  earn_multiplier: number;
}

export interface PriceInput {
  basePriceCents: number;
  outletPriceCents?: number | null;
  tier: LoyaltyTier;
  tierConfig: LoyaltyTierConfig | null;
  pointsPerRand: number;
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
  const price = effectivePrice(input.basePriceCents, input.outletPriceCents);
  const pct = input.tierConfig?.discount_pct ?? 0;
  const discount = pct > 0 ? roundHalfUp((price * pct) / 100) : 0;
  const total = Math.max(0, price - discount);
  const tierName = input.tierConfig?.name ?? capitalize(input.tier);
  return {
    price_cents: price,
    discount_cents: discount,
    total_cents: total,
    discount_label: discount > 0 ? `${tierName} −${pct}%` : null,
    points_pending: estimatePoints(total, input.pointsPerRand),
    tier: input.tier,
    earn_multiplier: input.tierConfig?.earn_multiplier ?? 1,
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

/** Loads catalogue rows and prices a service for a customer at an outlet. */
export async function priceService(outletId: string, serviceId: string, customerId: string): Promise<{ quote: PriceQuote; service: Service; outlet: Outlet }> {
  const db = getSupabase();
  const [outletRes, serviceRes, osRes, cfg, tier] = await Promise.all([
    db.from('outlets').select('*').eq('id', outletId).eq('is_active', true).maybeSingle(),
    db.from('services').select('*').eq('id', serviceId).eq('is_active', true).maybeSingle(),
    db.from('outlet_services').select('price_cents, is_available').eq('outlet_id', outletId).eq('service_id', serviceId).maybeSingle(),
    getPublishedLoyaltyConfig(),
    getCustomerTier(customerId),
  ]);
  const outlet = unwrap<Outlet | null>(outletRes, 'outlet');
  const service = unwrap<Service | null>(serviceRes, 'service');
  const os = unwrap<{ price_cents: number | null; is_available: boolean } | null>(osRes, 'outlet service');
  if (!outlet) throw ApiError.notFound('Outlet');
  if (!service) throw ApiError.notFound('Service');
  if (!os || !os.is_available) throw ApiError.validation('Service is not available at this outlet');
  const quote = computePrice({
    basePriceCents: service.base_price_cents,
    outletPriceCents: os.price_cents,
    tier,
    tierConfig: tierFor(cfg, tier),
    pointsPerRand: Number(cfg?.rules?.points_per_rand ?? service.points_per_rand ?? 0.1),
  });
  return { quote, service, outlet };
}
