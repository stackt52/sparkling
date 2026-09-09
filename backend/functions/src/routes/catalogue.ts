/** Catalogue: outlets, services, availability (CUS-020/021). */
import { Router } from 'express';
import { z } from 'zod';
import { getSupabase, unwrap } from '../lib/supabase.js';
import { isoDate, parseQuery, uuid } from '../lib/validate.js';
import { requireProfile } from '../middleware/auth.js';
import { asyncHandler } from '../middleware/errors.js';
import { getSlots } from '../services/availability.js';
import { computePrice, getCustomerTier, getPublishedLoyaltyConfig, tierFor } from '../services/pricing.js';
import type { Outlet, Service } from '../types.js';

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
    const db = getSupabase();
    const [rows, cfg, tier] = await Promise.all([
      db.from('outlet_services').select('price_cents, is_available, services(*)').eq('outlet_id', outletId).eq('is_available', true),
      getPublishedLoyaltyConfig(),
      getCustomerTier(req.auth!.uid),
    ]);
    const list = unwrap<Array<{ price_cents: number | null; is_available: boolean; services: Service }>>(rows, 'outlet services');
    const tierCfg = tierFor(cfg, tier);
    const data = list
      .filter((r) => r.services && r.services.is_active)
      .map((r) => {
        const s = r.services;
        const quote = computePrice({
          basePriceCents: s.base_price_cents,
          outletPriceCents: r.price_cents,
          tier,
          tierConfig: tierCfg,
          pointsPerRand: Number(cfg?.rules?.points_per_rand ?? s.points_per_rand ?? 0.1),
        });
        return {
          ...s,
          price_cents: quote.price_cents,
          discount_cents: quote.discount_cents,
          total_cents: quote.total_cents,
          discount_label: quote.discount_label,
          points_estimate: quote.points_pending,
        };
      })
      .sort((a, b) => a.sort_order - b.sort_order);
    res.json({ data, tier });
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
