import { fmtDate, rands } from '@/lib/format';
import type { Tone } from '@/components/ui/StatusChip';
import type { DiscountScope, EntitlementPeriod, GroupSelection, MembershipAllowance, MembershipInvoice, MembershipPlan, MembershipStatus } from '@/lib/types';

export const SCOPE_LABEL: Record<DiscountScope, string> = {
  plan_services: 'Selected plan services',
  other_services: 'Any other service',
  all_services: 'All services',
  none: 'No discount',
};
export const SCOPE_HINT: Record<DiscountScope, string> = {
  plan_services: 'Applies to the member’s chosen entitlement services once the allowance is used up',
  other_services: 'Applies to services that are not part of any entitlement of this plan',
  all_services: 'Applies to every priced service',
  none: 'The plan only includes the entitlements',
};
export const PERIOD_LABEL: Record<EntitlementPeriod, string> = { month: 'per month', year: 'per year' };
export const SELECTION_LABEL: Record<GroupSelection, string> = { choose_one: 'Choose one', all: 'All included' };
/** Joiner shown between the options of a group: OR for `choose_one`, AND for `all`. */
export const SELECTION_JOINER: Record<GroupSelection, string> = { choose_one: 'OR', all: 'AND' };

export const STATUS_LABEL: Record<MembershipStatus, string> = { pending: 'Pending', active: 'Active', past_due: 'Past due', cancelled: 'Cancelled', expired: 'Expired' };
export const STATUS_TONE: Record<MembershipStatus, Tone> = { pending: 'warning', active: 'success', past_due: 'error', cancelled: 'neutral', expired: 'neutral' };

/** "10 % off any other service" / "No discount". */
export function discountRule(p: Pick<MembershipPlan, 'discount_pct' | 'discount_scope'>): string {
  if (p.discount_scope === 'none' || p.discount_pct <= 0) return 'No discount';
  return `${p.discount_pct} % off ${p.discount_scope === 'plan_services' ? 'selected plan services' : p.discount_scope === 'other_services' ? 'any other service' : 'all services'}`;
}

/** "R 295 / month". */
export const feeLabel = (cents: number) => `${rands(cents)} / month`;

/** "5 Oct → 5 Nov". */
export const periodLabel = (start: string, end: string) => `${fmtDate(start)} → ${fmtDate(end)}`;

/** "3 of 4 Sparkling Washes left · resets 5 Oct". */
export function allowanceLabel(a: MembershipAllowance): string {
  const what = a.label.replace(/^\d+\s*×\s*/, '').replace(/\s*\/\s*(month|year)$/i, '');
  return `${a.remaining} of ${a.quantity} ${what}${a.quantity > 1 && !/s$/i.test(what) ? 'es' : ''} left · resets ${fmtDate(a.period_end)}`;
}

export function invoiceTone(i: MembershipInvoice): Tone {
  return i.status === 'paid' ? 'success' : i.status === 'pending' ? 'warning' : i.status === 'failed' ? 'error' : 'neutral';
}
