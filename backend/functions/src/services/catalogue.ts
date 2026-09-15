/**
 * Catalogue pricing model (migration 0008): per-outlet offers, size-aware
 * price resolution, composite membership and vehicle size classes.
 *
 * Resolution rules (docs/API.md "Catalogue pricing model"):
 *   price          = outlet override for the vehicle size (small/large; general
 *                    when size-independent; bike uses small) → service default
 *   by_quote       → no price (null)
 *   composition    = outlet-specific `service_components` rows when any exist
 *                    for the parent at that outlet, else the global set
 *   vehicle size   = vehicles.size_class ?? disc description keywords ?? small
 */
import { getSupabase, unwrap } from '../lib/supabase.js';
import type { OutletService, OutletServiceOffer, PricingMode, Service, ServiceComponent, VatMode, VehicleSize } from '../types.js';
import { VAT_RATE } from '../types.js';
import { estimatePoints, roundHalfUp } from './pricing.js';

// ---------------------------------------------------------------------------
// Vehicle size
// ---------------------------------------------------------------------------

const LARGE_RE = /\b(station\s*wagon|suv|pick[\s-]?up|bakkie|bus|mpv|van|minibus|4x4|double\s*cab|single\s*cab|ldv|panel\s*van|kombi|combi)\b/i;
const BIKE_RE = /\b(motor\s*cycle|motorcycle|motorbike|bike|scooter|quad|trike)\b/i;
const SMALL_RE = /\b(hatch(back)?|sedan|coupe|coupé|convertible|cabriolet|roadster|saloon)\b/i;

/** Maps an SA licence-disc description ("Sedan (closed top)", "Station wagon", "Motorcycle") to a size class; null when unknown. */
export function sizeClassFromDescription(description: string | null | undefined): VehicleSize | null {
  if (!description) return null;
  const d = description.trim();
  if (!d) return null;
  if (BIKE_RE.test(d)) return 'bike';
  if (LARGE_RE.test(d)) return 'large';
  if (SMALL_RE.test(d)) return 'small';
  return null;
}

/** Effective pricing size of a vehicle: stored `size_class`, else derived from a disc description, else `small`. */
export function resolveVehicleSize(vehicle: { size_class?: VehicleSize | null; description?: string | null } | null | undefined): VehicleSize {
  if (!vehicle) return 'small';
  return vehicle.size_class ?? sizeClassFromDescription(vehicle.description) ?? 'small';
}

// ---------------------------------------------------------------------------
// Price resolution (pure)
// ---------------------------------------------------------------------------

export interface PriceCard {
  pricing_mode: PricingMode;
  price_small_cents: number | null;
  price_large_cents: number | null;
  price_general_cents: number | null;
}

/**
 * Price of an offer for a vehicle size. `bike` prices as `small`; `large` falls
 * back to `small` when the outlet has no large price; both fall back to the
 * size-independent `general` price. `by_quote` → null.
 */
export function resolveOfferPrice(offer: PriceCard, size: VehicleSize): number | null {
  if (offer.pricing_mode === 'by_quote') return null;
  const small = offer.price_small_cents ?? offer.price_general_cents ?? null;
  if (size === 'large') return offer.price_large_cents ?? small;
  return small;
}

/** Lowest non-null price (the "From R x" figure); null when by-quote or unpriced. */
export function priceFrom(offer: PriceCard): number | null {
  if (offer.pricing_mode === 'by_quote') return null;
  const vals = [offer.price_small_cents, offer.price_large_cents, offer.price_general_cents].filter((v): v is number => typeof v === 'number');
  return vals.length ? Math.min(...vals) : null;
}

export function formatRand(cents: number): string {
  const rand = cents / 100;
  return Number.isInteger(rand) ? `R ${rand}` : `R ${rand.toFixed(2)}`;
}

/** Display label: "From R 150", "R 400 excl. VAT", "By quotation". */
export function priceLabel(mode: PricingMode, cents: number | null, vatMode: VatMode = 'incl'): string {
  if (mode === 'by_quote' || cents === null) return 'By quotation';
  const base = mode === 'from' ? `From ${formatRand(cents)}` : formatRand(cents);
  return vatMode === 'excl' ? `${base} excl. VAT` : base;
}

export function vatOn(cents: number, vatMode: VatMode): number {
  return vatMode === 'excl' ? roundHalfUp(cents * VAT_RATE) : 0;
}

// ---------------------------------------------------------------------------
// Composition (pure)
// ---------------------------------------------------------------------------

/** Outlet rows override the global set per parent; returns child rows per parent and where they came from. */
export function resolveComposition(components: ServiceComponent[], outletId: string | null): Map<string, { source: 'outlet' | 'global'; rows: ServiceComponent[] }> {
  const out = new Map<string, { source: 'outlet' | 'global'; rows: ServiceComponent[] }>();
  const byParent = new Map<string, { outlet: ServiceComponent[]; global: ServiceComponent[] }>();
  for (const c of components) {
    if (c.outlet_id && c.outlet_id !== outletId) continue;
    const cur = byParent.get(c.parent_service_id) ?? { outlet: [], global: [] };
    (c.outlet_id ? cur.outlet : cur.global).push(c);
    byParent.set(c.parent_service_id, cur);
  }
  const sortRows = (rows: ServiceComponent[]) => [...rows].sort((a, b) => a.sort_order - b.sort_order);
  for (const [parent, sets] of byParent) {
    if (sets.outlet.length) out.set(parent, { source: 'outlet', rows: sortRows(sets.outlet) });
    else if (sets.global.length) out.set(parent, { source: 'global', rows: sortRows(sets.global) });
  }
  return out;
}

/**
 * Returns the path of a cycle that would exist if `parent` included `children`
 * on top of the given resolved graph (parent → child ids), or null when acyclic.
 */
export function findCompositionCycle(graph: Map<string, string[]>, parent: string, children: string[]): string[] | null {
  if (children.includes(parent)) return [parent, parent];
  const edges = new Map(graph);
  edges.set(parent, children);
  const seen = new Set<string>();
  const stack: string[] = [];
  const visit = (node: string, path: string[]): string[] | null => {
    if (stack.includes(node)) return [...path.slice(path.indexOf(node)), node];
    if (seen.has(node)) return null;
    seen.add(node);
    stack.push(node);
    for (const next of edges.get(node) ?? []) {
      const hit = visit(next, [...path, node]);
      if (hit) return hit;
    }
    stack.pop();
    return null;
  };
  return visit(parent, []);
}

// ---------------------------------------------------------------------------
// Offer building
// ---------------------------------------------------------------------------

export interface OfferOptions {
  vehicleSize?: VehicleSize | null;
  includeUnavailable?: boolean;
  /** Points per rand from the published loyalty config (default: service.points_per_rand ?? 0.1). */
  pointsPerRand?: number | null;
}

export interface OfferList {
  offers: OutletServiceOffer[];
  groups: string[];
}

const GROUP_ORDER = ['Car Wash Options', 'Combinations', 'Auto Body Repair'];

/** Merges a service row with its outlet binding into the price card used everywhere (outlet override ?? service default; legacy price_cents/base_price_cents as last resort). */
export function mergeOffer(service: Service, os: Partial<OutletService> | null | undefined): PriceCard & { vat_mode: VatMode; name: string; sort_order: number; notes: string | null; is_available: boolean } {
  const pricing_mode: PricingMode = os?.pricing_mode ?? service.pricing_mode ?? (service.is_quote_based ? 'by_quote' : 'from');
  const price_small_cents = os?.price_small_cents ?? service.price_small_cents ?? null;
  const price_large_cents = os?.price_large_cents ?? service.price_large_cents ?? null;
  let price_general_cents = os?.price_general_cents ?? service.price_general_cents ?? null;
  if (price_small_cents === null && price_large_cents === null && price_general_cents === null) {
    // Rows created before migration 0008 only carry the legacy single price.
    const legacy = os?.price_cents ?? (service.base_price_cents ? service.base_price_cents : null);
    if (legacy !== null && legacy !== undefined) price_general_cents = legacy;
  }
  return {
    pricing_mode,
    vat_mode: os?.vat_mode ?? service.vat_mode ?? 'incl',
    price_small_cents,
    price_large_cents,
    price_general_cents,
    name: os?.display_name ?? service.name,
    sort_order: os?.sort_order ?? service.sort_order ?? 100,
    notes: os?.notes ?? service.notes ?? null,
    is_available: os?.is_available ?? true,
  };
}

/** Loads the raw rows an outlet's offers are built from. */
export async function loadOutletCatalogue(outletId: string, opts: { includeInactiveServices?: boolean } = {}): Promise<{ services: Service[]; bindings: OutletService[]; components: ServiceComponent[] }> {
  const db = getSupabase();
  const servicesQuery = db.from('services').select('*');
  const [servicesRes, bindingsRes, outletCompRes, globalCompRes] = await Promise.all([
    opts.includeInactiveServices ? servicesQuery : servicesQuery.eq('is_active', true),
    db.from('outlet_services').select('*').eq('outlet_id', outletId),
    db.from('service_components').select('*').eq('outlet_id', outletId),
    db.from('service_components').select('*').is('outlet_id', null),
  ]);
  return {
    services: unwrap<Service[]>(servicesRes, 'services'),
    bindings: unwrap<OutletService[]>(bindingsRes, 'outlet services'),
    components: [...unwrap<ServiceComponent[]>(outletCompRes, 'outlet components'), ...unwrap<ServiceComponent[]>(globalCompRes, 'global components')],
  };
}

/** Builds the offers from already-loaded rows (pure; used by the loader and by tests). */
export function buildOffers(outletId: string, rows: { services: Service[]; bindings: OutletService[]; components: ServiceComponent[] }, opts: OfferOptions = {}): OfferList {
  const services = new Map(rows.services.map((s) => [s.id, s]));
  const bindings = rows.bindings.filter((b) => b.outlet_id === outletId && services.has(b.service_id));
  const composition = resolveComposition(rows.components, outletId);
  const offered = new Set(bindings.map((b) => b.service_id));

  const cards = new Map<string, ReturnType<typeof mergeOffer>>();
  for (const b of bindings) cards.set(b.service_id, mergeOffer(services.get(b.service_id)!, b));

  const includedIn = new Map<string, string[]>();
  for (const [parent, set] of composition) {
    if (!offered.has(parent)) continue;
    for (const c of set.rows) includedIn.set(c.child_service_id, [...(includedIn.get(c.child_service_id) ?? []), parent]);
  }

  const offers: OutletServiceOffer[] = [];
  for (const b of bindings) {
    const s = services.get(b.service_id)!;
    const card = cards.get(b.service_id)!;
    if (!opts.includeUnavailable && !card.is_available) continue;
    const comp = composition.get(s.id);
    const includes = (comp?.rows ?? [])
      .filter((c) => services.has(c.child_service_id))
      .map((c) => {
        const child = services.get(c.child_service_id)!;
        return { service_id: child.id, code: child.code, name: cards.get(child.id)?.name ?? child.name, quantity: c.quantity ?? 1 };
      });
    const price_for: Record<VehicleSize, number | null> = {
      small: resolveOfferPrice(card, 'small'),
      large: resolveOfferPrice(card, 'large'),
      bike: resolveOfferPrice(card, 'bike'),
    };
    const from = priceFrom(card);
    const forSize = opts.vehicleSize ? price_for[opts.vehicleSize] : from;
    const ppr = Number(opts.pointsPerRand ?? s.points_per_rand ?? 0.1);
    offers.push({
      id: s.id,
      service_id: s.id,
      code: s.code,
      name: card.name,
      service_name: s.name,
      display_name: b.display_name ?? null,
      description: s.description ?? null,
      group_name: s.group_name ?? 'Car Wash Options',
      category: s.category,
      duration_minutes: s.duration_minutes,
      icon: s.icon ?? null,
      pricing_mode: card.pricing_mode,
      vat_mode: card.vat_mode,
      pricing_mode_override: b.pricing_mode ?? null,
      vat_mode_override: b.vat_mode ?? null,
      is_quote_based: card.pricing_mode === 'by_quote',
      price_small_cents: card.price_small_cents,
      price_large_cents: card.price_large_cents,
      price_general_cents: card.price_general_cents,
      price_from_cents: from,
      price_for,
      price_label: priceLabel(card.pricing_mode, forSize ?? from, card.vat_mode),
      is_addon: !!s.is_addon,
      addon_group_name: s.addon_group_name ?? null,
      includes,
      included_in: (includedIn.get(s.id) ?? []).filter((p) => opts.includeUnavailable || cards.get(p)?.is_available),
      components_source: comp ? comp.source : 'none',
      is_available: card.is_available,
      sort_order: card.sort_order,
      notes: card.notes,
      points_estimate: forSize === null || forSize === undefined ? 0 : estimatePoints(forSize + vatOn(forSize, card.vat_mode), ppr),
    });
  }
  offers.sort((a, b) => groupRank(a.group_name) - groupRank(b.group_name) || a.sort_order - b.sort_order || a.name.localeCompare(b.name));
  const groups: string[] = [];
  for (const o of offers) if (!groups.includes(o.group_name)) groups.push(o.group_name);
  return { offers, groups };
}

function groupRank(group: string): number {
  const i = GROUP_ORDER.indexOf(group);
  return i === -1 ? GROUP_ORDER.length : i;
}

/** Offers at an outlet with resolved composition and per-size prices. */
export async function listOutletOffers(outletId: string, opts: OfferOptions = {}): Promise<OfferList> {
  return buildOffers(outletId, await loadOutletCatalogue(outletId), opts);
}

/** Parent → children graph for cycle checks (outlet-resolved when `outletId` given, else the global set). */
export function compositionGraph(components: ServiceComponent[], outletId: string | null): Map<string, string[]> {
  const graph = new Map<string, string[]>();
  for (const [parent, set] of resolveComposition(components, outletId)) graph.set(parent, set.rows.map((r) => r.child_service_id));
  return graph;
}
