/** Catalogue: outlets, services, availability (CUS-020/021). */
import { Router } from 'express';
import { z } from 'zod';
import { getSupabase, unwrap } from '../lib/supabase.js';
import { isoDate, parseQuery, uuid, vehicleSize } from '../lib/validate.js';
import { requireProfile } from '../middleware/auth.js';
import { asyncHandler } from '../middleware/errors.js';
import { getSlots } from '../services/availability.js';
import { listOutletOffers } from '../services/catalogue.js';
import { benefitFor, loadContext } from '../services/memberships.js';
import { computePrice, getCustomerTier, getPublishedLoyaltyConfig, tierFor } from '../services/pricing.js';
import type { Outlet } from '../types.js';

export const catalogueRouter = Router();
catalogueRouter.use(['/outlets', '/availability'], requireProfile);

export function distanceKm(lat1: number, lng1: number, lat2: number, lng2: number): number {
  const R = 6371;
  const dLat = ((lat2 - lat1) * Math.PI) / 180;
  const dLng = ((lng2 - lng1) * Math.PI) / 180;
  const a = Math.sin(dLat / 2) ** 2 + Math.cos((lat1 * Math.PI) / 180) * Math.cos((lat2 * Math.PI) / 180) * Math.sin(dLng / 2) ** 2;
  return Math.round(R * 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a)) * 10) / 10;
}

catalogueRouter.get(
  '/outlets',
  asyncHandler(async (req, res) => {
    const q = parseQuery(z.object({ lat: z.coerce.number().min(-90).max(90).optional(), lng: z.coerce.number().min(-180).max(180).optional() }), req.query);
    const db = getSupabase();
    const outlets = unwrap<Outlet[]>(await db.from('outlets').select('*').eq('is_active', true).order('name'), 'outlets');
    const data = outlets.map((o) => {
      const withDistance =
        q.lat !== undefined && q.lng !== undefined && o.latitude !== null && o.longitude !== null
          ? { ...o, distance_km: distanceKm(q.lat, q.lng, o.latitude, o.longitude) }
          : o;
      return withDistance;
    });
    if (q.lat !== undefined && q.lng !== undefined) data.sort((a, b) => ((a as any).distance_km ?? 1e9) - ((b as any).distance_km ?? 1e9));
    res.json({ data });
  }),
);

catalogueRouter.get(
  '/outlets/:id/services',
  asyncHandler(async (req, res) => {
    const outletId = uuid.parse(req.params.id);
    const q = parseQuery(z.object({ vehicle_size: vehicleSize.optional() }), req.query);
    const [cfg, tier, membership] = await Promise.all([getPublishedLoyaltyConfig(), getCustomerTier(req.auth!.uid), q.vehicle_size ? loadContext(req.auth!.uid) : Promise.resolve(null)]);
    const tierCfg = tierFor(cfg, tier);
    const pointsPerRand = cfg?.rules?.points_per_rand;
    const { offers, groups } = await listOutletOffers(outletId, { vehicleSize: q.vehicle_size ?? null, pointsPerRand: pointsPerRand === undefined ? null : Number(pointsPerRand) });
    const data = offers.map((offer) => {
      if (!q.vehicle_size) return offer;
      // Resolved for the caller's vehicle size and tier (kept for older clients that read price_cents).
      const price = offer.price_for[q.vehicle_size];
      if (price === null) return { ...offer, price_cents: null, discount_cents: 0, total_cents: null, discount_label: null };
      const quote = computePrice({ basePriceCents: price, vehicleSize: q.vehicle_size, pricingMode: offer.pricing_mode, vatMode: offer.vat_mode, tier, tierConfig: tierCfg, pointsPerRand: Number(pointsPerRand ?? 0.1), membership: benefitFor(offer.service_id, membership) });
      return { ...offer, price_cents: quote.price_cents, discount_cents: quote.discount_cents, vat_cents: quote.vat_cents, total_cents: quote.total_cents, discount_label: quote.discount_label, points_estimate: quote.points_pending, price_label: quote.label, membership: quote.membership };
    });
    res.json({ data, groups, tier, vehicle_size: q.vehicle_size ?? null, membership: membership ? { plan_code: membership.plan.code, plan_name: membership.plan.name, status: membership.membership.status } : null });
  }),
);

catalogueRouter.get(
  '/availability',
  asyncHandler(async (req, res) => {
    const q = parseQuery(z.object({ outlet_id: uuid, service_id: uuid, date: isoDate }), req.query);
    const slots = await getSlots(q.outlet_id, q.service_id, q.date);
    res.json({ data: slots, outlet_id: q.outlet_id, service_id: q.service_id, date: q.date });
  }),
);
