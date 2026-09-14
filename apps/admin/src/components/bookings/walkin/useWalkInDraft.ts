'use client';
import * as React from 'react';
import { format } from 'date-fns';
import { uuid } from '@/lib/api';
import { useHydrated } from '@/lib/hooks';
import { rands } from '@/lib/format';
import { VAT_RATE, priceLabel, type Booking, type LoyaltyTier, type MembershipBenefit, type MembershipSummary, type OutletServiceOffer, type PosPayment, type VatMode, type VehicleSize, type WalkInCustomer, type WalkInPriority, type WalkInVehicle, type WorkOrderSummary } from '@/lib/types';

export type WalkInPaymentChoice = 'cash' | 'card_terminal' | 'in_app';
export const WALK_IN_STEPS = ['Customer', 'Vehicle', 'Service & time', 'Payment & confirm'] as const;

export interface WalkInResult {
  booking: Booking;
  payment: PosPayment | null;
  work_order: WorkOrderSummary | null;
}

/**
 * In-progress walk-in (STF-010/012). Mirrors the staff app's WalkInFlowController: the
 * draft survives a reload (sessionStorage) and `client_op_id` / `payment_key` are generated
 * once per walk-in so `POST /bookings` and `POST /payments/record` are idempotent on retry.
 */
export interface WalkInDraft {
  step: 0 | 1 | 2 | 3;
  customer: WalkInCustomer | null;
  /** The customer's live membership (`GET /staff/customers/:id/membership`), refreshed by the page. */
  membership: MembershipSummary | null;
  vehicle: WalkInVehicle | null;
  /** Pricing size (prefilled from `vehicle.size_class`, staff may override). */
  vehicle_size: VehicleSize;
  outlet_id: string | null;
  service: OutletServiceOffer | null;
  /** Add-ons of the service's group chosen at the outlet (`addon_service_ids` on submit). */
  addons: OutletServiceOffer[];
  book_now: boolean;
  date: string;
  slot_start: string | null;
  payment: WalkInPaymentChoice;
  reference: string;
  check_in: boolean;
  bay: string;
  priority: WalkInPriority;
  notes: string;
  client_op_id: string;
  payment_key: string;
  /** Booking already created by this attempt (payment may still be outstanding). */
  created: { booking: Booking; work_order: WorkOrderSummary | null } | null;
  result: WalkInResult | null;
}

const KEY = 'sparkling.admin.walkInDraft';

export function newDraft(): WalkInDraft {
  return {
    step: 0, customer: null, membership: null, vehicle: null, vehicle_size: 'small', outlet_id: null, service: null, addons: [], book_now: true, date: format(new Date(), 'yyyy-MM-dd'), slot_start: null,
    payment: 'cash', reference: '', check_in: true, bay: '', priority: 2, notes: '', client_op_id: uuid(), payment_key: uuid(), created: null, result: null,
  };
}

/** Resolved price of an offer for a size (tolerates drafts saved before size-aware offers). */
export function offerPriceFor(o: OutletServiceOffer | null | undefined, size: VehicleSize): number | null {
  if (!o) return null;
  if (o.pricing_mode === 'by_quote') return null;
  const v = o.price_for?.[size];
  return v === undefined ? o.price_cents ?? null : v;
}

/** Furthest step the draft allows (steps beyond it are disabled in the stepper). */
export function maxStep(d: WalkInDraft): 0 | 1 | 2 | 3 {
  if (!d.customer) return 0;
  if (!d.vehicle) return 1;
  if (!d.outlet_id || !d.service || offerPriceFor(d.service, d.vehicle_size) === null || (!d.book_now && !d.slot_start)) return 2;
  return 3;
}

/** Membership benefit for one service (docs/MEMBERSHIPS.md pricing rules 2–3, previewed client-side). */
export interface MemberBenefit {
  benefit: MembershipBenefit;
  plan_name: string;
  /** "Included in Gold · 2 of 4 left" / "Gold −10%". */
  label: string;
  discount: number;
  pct: number;
  entitlement_code: string | null;
  remaining_after: number | null;
  quantity: number | null;
}

/**
 * Included wash (allowance left on a selected entitlement covering the service → discount = base, add-ons
 * still charged) or the plan discount by scope; `past_due` / no plan → null. Mirrors `priceService`.
 */
export function memberBenefit(summary: MembershipSummary | null | undefined, serviceCode: string | null | undefined, base: number, addons_cents: number): MemberBenefit | null {
  const m = summary?.membership;
  const plan = summary?.plan;
  if (!m || !plan || m.status !== 'active' || !serviceCode) return null;
  const selected = plan.groups.flatMap((g) => (g.selection === 'all' ? g.entitlements : g.entitlements.filter((e) => e.code === summary!.selections[g.code])));
  const covering = selected.find((e) => e.services.some((sv) => sv.code === serviceCode));
  if (covering) {
    const a = summary!.allowances.find((x) => x.entitlement_code === covering.code);
    if (a && a.remaining > 0) {
      return { benefit: 'included', plan_name: plan.name, label: `Included in ${plan.name} · ${a.remaining - 1} of ${a.quantity} left`, discount: base, pct: 0, entitlement_code: covering.code, remaining_after: a.remaining - 1, quantity: a.quantity };
    }
  }
  const planCodes = new Set(plan.groups.flatMap((g) => g.entitlements.flatMap((e) => e.services.map((sv) => sv.code))));
  const selectedCodes = new Set(selected.flatMap((e) => e.services.map((sv) => sv.code)));
  const applies = plan.discount_scope === 'plan_services' ? selectedCodes.has(serviceCode) : plan.discount_scope === 'other_services' ? !planCodes.has(serviceCode) : plan.discount_scope === 'all_services';
  if (!applies || plan.discount_pct <= 0) return null;
  return { benefit: 'discount', plan_name: plan.name, label: `${plan.name} −${plan.discount_pct}%`, discount: Math.round(((base + addons_cents) * plan.discount_pct) / 100), pct: plan.discount_pct, entitlement_code: null, remaining_after: null, quantity: null };
}

export interface WalkInPricing {
  size: VehicleSize;
  /** Base service price for the size ("From" prices are minimums). */
  base: number;
  base_label: string;
  addons: { service_id: string; name: string; cents: number }[];
  addons_cents: number;
  /** base + add-ons. */
  price: number;
  /** Plan discount percentage (0 for an included wash / no plan). */
  pct: number;
  /** Included wash → the base; plan discount → pct of base + add-ons. */
  discount: number;
  /** "Included in Gold · 2 of 4 left" / "Gold −10%" / null. */
  discount_label: string | null;
  member: MemberBenefit | null;
  vat_mode: VatMode;
  /** 15 % VAT on (price − discount) for `excl` offers, else 0. */
  vat: number;
  total: number;
  tier: LoyaltyTier | null;
}

/** Client-side preview of the server pricing (docs/API.md "Catalogue pricing model" + docs/MEMBERSHIPS.md). */
export function pricing(d: WalkInDraft): WalkInPricing {
  const size = d.vehicle_size ?? 'small';
  const base = offerPriceFor(d.service, size) ?? 0;
  const addons = (d.addons ?? []).map((a) => ({ service_id: a.service_id ?? a.id, name: a.name, cents: offerPriceFor(a, size) ?? 0 }));
  const addons_cents = addons.reduce((s, a) => s + a.cents, 0);
  const price = base + addons_cents;
  const member = d.service ? memberBenefit(d.membership, d.service.code, base, addons_cents) : null;
  const discount = member?.discount ?? 0;
  const vat_mode: VatMode = d.service?.vat_mode ?? 'incl';
  const vat = vat_mode === 'excl' ? Math.round((price - discount) * VAT_RATE) : 0;
  return { size, base, base_label: d.service ? priceLabel(d.service, base, (c) => rands(c)) : '', addons, addons_cents, price, pct: member?.pct ?? 0, discount, discount_label: member?.label ?? null, member, vat_mode, vat, total: price - discount + vat, tier: d.customer?.loyalty?.tier ?? null };
}

function restore(): WalkInDraft {
  if (typeof window === 'undefined') return newDraft();
  try {
    const raw = sessionStorage.getItem(KEY);
    if (raw) return { ...newDraft(), ...(JSON.parse(raw) as Partial<WalkInDraft>) };
  } catch {
    /* corrupt draft or storage unavailable — start clean */
  }
  return newDraft();
}

export function useWalkInDraft() {
  // Lazy-restored on the client; nothing draft-dependent renders until hydration completes,
  // so server and client markup still match.
  const [draft, setDraft] = React.useState<WalkInDraft>(restore);
  const hydrated = useHydrated();

  React.useEffect(() => {
    if (!hydrated) return;
    try {
      sessionStorage.setItem(KEY, JSON.stringify(draft));
    } catch {
      /* storage unavailable */
    }
  }, [draft, hydrated]);

  const patch = React.useCallback((p: Partial<WalkInDraft> | ((d: WalkInDraft) => Partial<WalkInDraft>)) => {
    setDraft((d) => ({ ...d, ...(typeof p === 'function' ? p(d) : p) }));
  }, []);

  const setCustomer = React.useCallback((c: WalkInCustomer) => {
    setDraft((d) => ({ ...d, customer: c, membership: d.customer?.id === c.id ? d.membership : null, vehicle: d.customer?.id === c.id ? d.vehicle : null }));
  }, []);

  const reset = React.useCallback(() => setDraft(newDraft()), []);

  return { draft, hydrated, patch, setCustomer, reset };
}
