/**
 * Admin management of the catalogue pricing model (migration 0008):
 * canonical services + global composition, per-outlet bindings + outlet
 * composition sets. All writes are audited by the caller-facing functions.
 *
 * Validation rules (docs/API.md "Catalogue pricing model"):
 *   - `by_quote` needs no prices; `from` / `fixed` need at least one price
 *     (small / large / general — the legacy `base_price_cents` counts)
 *   - an add-on (`is_addon`) needs `addon_group_name`
 *   - composition may not include the parent itself or form a cycle (400)
 *   - an outlet's `components: null` removes the outlet set → global default
 */
import { getSupabase, unwrap } from '../lib/supabase.js';
import { ApiError } from '../middleware/errors.js';
import type { OutletService, OutletServiceOffer, PricingMode, RequestContext, Service, ServiceComponent, ServiceComponentInput, VatMode } from '../types.js';
import { audit } from './audit.js';
import { buildOffers, compositionGraph, findCompositionCycle, loadOutletCatalogue, mergeOffer } from './catalogue.js';

export interface ServiceComponentView {
  child_service_id: string;
  code: string;
  name: string;
  quantity: number;
  sort_order: number;
}

export type AdminService = Service & { components: ServiceComponentView[] };

export interface ServiceFields {
  code?: string;
  name?: string;
  description?: string | null;
  category?: Service['category'];
  duration_minutes?: number;
  base_price_cents?: number;
  is_quote_based?: boolean;
  points_per_rand?: number;
  icon?: string | null;
  checklist_template_id?: string | null;
  is_active?: boolean;
  sort_order?: number;
  group_name?: string;
  pricing_mode?: PricingMode;
  vat_mode?: VatMode;
  price_small_cents?: number | null;
  price_large_cents?: number | null;
  price_general_cents?: number | null;
  is_addon?: boolean;
  addon_group_name?: string | null;
  notes?: string | null;
}

export interface OutletServiceFields {
  display_name?: string | null;
  price_small_cents?: number | null;
  price_large_cents?: number | null;
  price_general_cents?: number | null;
  pricing_mode?: PricingMode | null;
  vat_mode?: VatMode | null;
  is_available?: boolean;
  sort_order?: number | null;
  notes?: string | null;
  /** Legacy single price (older admin clients). */
  price_cents?: number | null;
}

const PRICE_FIELDS = ['pricing_mode', 'price_small_cents', 'price_large_cents', 'price_general_cents', 'base_price_cents', 'is_quote_based'] as const;

function hasPrice(row: { price_small_cents?: number | null; price_large_cents?: number | null; price_general_cents?: number | null; base_price_cents?: number | null }): boolean {
  return [row.price_small_cents, row.price_large_cents, row.price_general_cents].some((v) => typeof v === 'number') || (typeof row.base_price_cents === 'number' && row.base_price_cents > 0);
}

/**
 * Validates the *effective* service row (existing ?? patch). `pricingTouched`
 * lets a non-pricing edit of a legacy row without default prices go through.
 */
export function validateServiceRow(row: ServiceFields & Partial<Service>, pricingTouched = true): void {
  const details: Array<{ path: string; message: string }> = [];
  const mode: PricingMode = row.pricing_mode ?? (row.is_quote_based ? 'by_quote' : 'from');
  if (mode !== 'by_quote' && pricingTouched && !hasPrice(row)) {
    details.push({ path: 'price_small_cents', message: `pricing_mode "${mode}" needs at least one of price_small_cents, price_large_cents or price_general_cents` });
  }
  if (row.is_addon && !row.addon_group_name) details.push({ path: 'addon_group_name', message: 'An add-on needs addon_group_name (the group it attaches to)' });
  if (details.length) throw ApiError.validation('Service validation failed', details);
}

function serviceComponentsView(services: Map<string, Service>, rows: ServiceComponent[]): ServiceComponentView[] {
  return [...rows]
    .sort((a, b) => a.sort_order - b.sort_order)
    .filter((c) => services.has(c.child_service_id))
    .map((c) => {
      const child = services.get(c.child_service_id)!;
      return { child_service_id: child.id, code: child.code, name: child.name, quantity: c.quantity ?? 1, sort_order: c.sort_order };
    });
}

const GROUP_ORDER = ['Car Wash Options', 'Combinations', 'Auto Body Repair'];
const groupRank = (g: string) => (GROUP_ORDER.indexOf(g) === -1 ? GROUP_ORDER.length : GROUP_ORDER.indexOf(g));

/** All services (active and inactive) with their global composition set. */
export async function listServicesWithComponents(): Promise<AdminService[]> {
  const db = getSupabase();
  const [servicesRes, compRes] = await Promise.all([db.from('services').select('*'), db.from('service_components').select('*').is('outlet_id', null)]);
  const services = unwrap<Service[]>(servicesRes, 'services');
  const components = unwrap<ServiceComponent[]>(compRes, 'global components');
  const byId = new Map(services.map((s) => [s.id, s]));
  return services
    .sort((a, b) => groupRank(a.group_name ?? '') - groupRank(b.group_name ?? '') || (a.sort_order ?? 100) - (b.sort_order ?? 100) || a.name.localeCompare(b.name))
    .map((s) => ({ ...s, components: serviceComponentsView(byId, components.filter((c) => c.parent_service_id === s.id)) }));
}

export async function getServiceWithComponents(id: string): Promise<AdminService> {
  const all = await listServicesWithComponents();
  const found = all.find((s) => s.id === id);
  if (!found) throw ApiError.notFound('Service');
  return found;
}

/**
 * Replaces the composition set of `parent` (global when `outletId` is null,
 * else that outlet's override). Rejects unknown children, the parent itself and
 * cycles against the graph as it would be after the change.
 */
export async function replaceComponents(parentId: string, outletId: string | null, components: ServiceComponentInput[]): Promise<ServiceComponent[]> {
  const db = getSupabase();
  const [servicesRes, compRes] = await Promise.all([db.from('services').select('id, code, is_active'), db.from('service_components').select('*')]);
  const services = new Map(unwrap<Array<{ id: string; code: string; is_active: boolean }>>(servicesRes, 'services').map((s) => [s.id, s]));
  const all = unwrap<ServiceComponent[]>(compRes, 'components');

  const seen = new Set<string>();
  const details: Array<Record<string, unknown>> = [];
  components.forEach((c, i) => {
    if (c.child_service_id === parentId) details.push({ path: `components.${i}.child_service_id`, message: 'A service cannot include itself' });
    else if (!services.has(c.child_service_id)) details.push({ path: `components.${i}.child_service_id`, message: 'Unknown service' });
    if (seen.has(c.child_service_id)) details.push({ path: `components.${i}.child_service_id`, message: 'Duplicate component' });
    seen.add(c.child_service_id);
  });
  if (details.length) throw ApiError.validation('Invalid composition', details);

  const graph = compositionGraph(all, outletId);
  const cycle = findCompositionCycle(graph, parentId, components.map((c) => c.child_service_id));
  if (cycle) {
    const codes = cycle.map((id) => services.get(id)?.code ?? id);
    throw ApiError.validation(`Composition would be cyclic: ${codes.join(' → ')}`, [{ path: 'components', message: 'Cyclic composition', cycle }]);
  }

  let del = db.from('service_components').delete().eq('parent_service_id', parentId);
  del = outletId === null ? del.is('outlet_id', null) : del.eq('outlet_id', outletId);
  const delRes = await del;
  if (delRes.error) throw ApiError.internal(`Could not replace components: ${delRes.error.message}`);
  if (components.length === 0) return [];
  const rows = components.map((c, i) => ({ parent_service_id: parentId, child_service_id: c.child_service_id, outlet_id: outletId, quantity: c.quantity ?? 1, sort_order: c.sort_order ?? (i + 1) * 10 }));
  return unwrap<ServiceComponent[]>(await db.from('service_components').insert(rows).select('*'), 'insert components');
}

/** Drops every outlet-specific composition row of `parent` at `outletId` (→ global set applies). */
export async function clearOutletComponents(parentId: string, outletId: string): Promise<void> {
  const res = await getSupabase().from('service_components').delete().eq('parent_service_id', parentId).eq('outlet_id', outletId);
  if (res.error) throw ApiError.internal(`Could not clear outlet components: ${res.error.message}`);
}

function serviceColumns(fields: ServiceFields): Record<string, unknown> {
  const out: Record<string, unknown> = {};
  for (const [k, v] of Object.entries(fields)) if (v !== undefined) out[k] = v;
  if (fields.pricing_mode !== undefined) out.is_quote_based = fields.pricing_mode === 'by_quote';
  else if (fields.is_quote_based !== undefined) out.pricing_mode = fields.is_quote_based ? 'by_quote' : (out.pricing_mode ?? 'from');
  // Keep the legacy single price in step for old readers (migration 0008 does the same on import).
  if (fields.price_small_cents !== undefined || fields.price_general_cents !== undefined) {
    const legacy = fields.price_small_cents ?? fields.price_general_cents;
    if (typeof legacy === 'number' && fields.base_price_cents === undefined) out.base_price_cents = legacy;
  }
  return out;
}

export async function createService(ctx: RequestContext, fields: ServiceFields, components?: ServiceComponentInput[] | null): Promise<AdminService> {
  const db = getSupabase();
  const cols = { pricing_mode: 'from', vat_mode: 'incl', group_name: 'Car Wash Options', is_addon: false, is_quote_based: false, base_price_cents: 0, ...serviceColumns(fields) };
  validateServiceRow(cols as ServiceFields);
  const created = unwrap<Service>(await db.from('services').insert(cols).select('*').single(), 'create service');
  if (components && components.length) await replaceComponents(created.id, null, components);
  await audit(ctx, { action: 'service.create', entity_type: 'service', entity_id: created.id, after: { ...cols, components: components ?? [] } });
  return getServiceWithComponents(created.id);
}

export async function updateService(ctx: RequestContext, id: string, fields: ServiceFields, components?: ServiceComponentInput[] | null): Promise<AdminService> {
  const db = getSupabase();
  const before = unwrap<Service | null>(await db.from('services').select('*').eq('id', id).maybeSingle(), 'service');
  if (!before) throw ApiError.notFound('Service');
  const pricingTouched = PRICE_FIELDS.some((k) => fields[k] !== undefined);
  const merged: ServiceFields & Service = { ...before, ...Object.fromEntries(Object.entries(fields).filter(([, v]) => v !== undefined)) } as ServiceFields & Service;
  validateServiceRow(merged, pricingTouched || hasPrice(before));
  const cols = serviceColumns(fields);
  if (Object.keys(cols).length) unwrap<Service>(await db.from('services').update(cols).eq('id', id).select('*').single(), 'update service');
  if (components !== undefined && components !== null) await replaceComponents(id, null, components);
  await audit(ctx, { action: 'service.update', entity_type: 'service', entity_id: id, before, after: { ...cols, ...(components !== undefined ? { components } : {}) } });
  return getServiceWithComponents(id);
}

/** Offers of an outlet for admin screens: includes unavailable bindings and `components_source`. */
export async function listAdminOutletOffers(outletId: string): Promise<{ offers: OutletServiceOffer[]; groups: string[] }> {
  const rows = await loadOutletCatalogue(outletId, { includeInactiveServices: true });
  return buildOffers(outletId, rows, { includeUnavailable: true });
}

/**
 * Upserts the outlet binding. `components` array → outlet-specific set;
 * `null` → drop the outlet set (global applies); omitted → untouched.
 */
export async function upsertOutletService(ctx: RequestContext, outletId: string, serviceId: string, fields: OutletServiceFields, components?: ServiceComponentInput[] | null): Promise<OutletServiceOffer> {
  const db = getSupabase();
  const [outletRes, serviceRes, beforeRes] = await Promise.all([
    db.from('outlets').select('id').eq('id', outletId).maybeSingle(),
    db.from('services').select('*').eq('id', serviceId).maybeSingle(),
    db.from('outlet_services').select('*').eq('outlet_id', outletId).eq('service_id', serviceId).maybeSingle(),
  ]);
  if (!unwrap<{ id: string } | null>(outletRes, 'outlet')) throw ApiError.notFound('Outlet');
  const service = unwrap<Service | null>(serviceRes, 'service');
  if (!service) throw ApiError.notFound('Service');
  const before = unwrap<OutletService | null>(beforeRes, 'outlet service');

  const patch: Record<string, unknown> = {};
  for (const [k, v] of Object.entries(fields)) if (v !== undefined) patch[k] = v;
  const merged = { ...(before ?? {}), ...patch } as Partial<OutletService>;
  const card = mergeOffer(service, merged);
  if (card.pricing_mode !== 'by_quote' && !hasPrice(card)) {
    throw ApiError.validation(`pricing_mode "${card.pricing_mode}" needs at least one of price_small_cents, price_large_cents or price_general_cents (outlet or service default)`, [{ path: 'price_small_cents', message: 'No price' }]);
  }
  // Legacy single price mirrors the small/general figure so pre-0008 readers stay consistent.
  if (fields.price_cents === undefined && (fields.price_small_cents !== undefined || fields.price_general_cents !== undefined)) {
    patch.price_cents = merged.price_small_cents ?? merged.price_general_cents ?? null;
  }
  const row = { outlet_id: outletId, service_id: serviceId, is_available: merged.is_available ?? true, ...patch };
  unwrap<OutletService>(await db.from('outlet_services').upsert(row, { onConflict: 'outlet_id,service_id' }).select('*').single(), 'upsert outlet service');

  if (Array.isArray(components)) await replaceComponents(serviceId, outletId, components);
  else if (components === null) await clearOutletComponents(serviceId, outletId);

  await audit(ctx, { action: 'outlet_service.update', entity_type: 'outlet_service', entity_id: `${outletId}:${serviceId}`, outlet_id: outletId, before, after: { ...patch, ...(components !== undefined ? { components } : {}) } });
  const { offers } = await listAdminOutletOffers(outletId);
  const offer = offers.find((o) => o.service_id === serviceId);
  if (!offer) throw ApiError.internal('Outlet service vanished after upsert');
  return offer;
}

/** Removes the binding and any outlet-specific composition rows of that service. */
export async function deleteOutletService(ctx: RequestContext, outletId: string, serviceId: string): Promise<void> {
  const db = getSupabase();
  const before = unwrap<OutletService | null>(await db.from('outlet_services').select('*').eq('outlet_id', outletId).eq('service_id', serviceId).maybeSingle(), 'outlet service');
  if (!before) throw ApiError.notFound('Outlet service');
  await db.from('outlet_services').delete().eq('outlet_id', outletId).eq('service_id', serviceId);
  await clearOutletComponents(serviceId, outletId);
  await audit(ctx, { action: 'outlet_service.delete', entity_type: 'outlet_service', entity_id: `${outletId}:${serviceId}`, outlet_id: outletId, before });
}
