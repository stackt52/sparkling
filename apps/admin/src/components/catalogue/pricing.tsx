'use client';
import * as React from 'react';
import ToggleButton from '@mui/material/ToggleButton';
import ToggleButtonGroup from '@mui/material/ToggleButtonGroup';
import StatusChip, { type Tone } from '@/components/ui/StatusChip';
import MSymbol from '@/components/MSymbol';
import { rands } from '@/lib/format';
import { tk } from '@/theme/tokens';
import { VEHICLE_SIZES, type PricingMode, type ServiceGroup, type VatMode, type VehicleSize } from '@/lib/types';

/* ---------- labels ---------- */
export const PRICING_MODE_LABEL: Record<PricingMode, string> = { from: 'From', fixed: 'Fixed', by_quote: 'By quote' };
export const PRICING_MODE_HINT: Record<PricingMode, string> = { from: 'Minimum price — shown as "From R x"', fixed: 'Exact price', by_quote: 'No price; customers request a quotation' };
const PRICING_MODE_TONE: Record<PricingMode, Tone> = { from: 'primary', fixed: 'success', by_quote: 'warning' };
export const VAT_MODE_LABEL: Record<VatMode, string> = { incl: 'incl. VAT', excl: 'excl. VAT' };
export const VAT_MODE_HINT: Record<VatMode, string> = { incl: 'Price is final', excl: '15 % VAT is added on the booking / quotation total' };
export const GROUP_ICON: Record<ServiceGroup, string> = { 'Car Wash Options': 'local_car_wash', Combinations: 'layers', 'Auto Body Repair': 'car_repair' };
export const GROUP_HINT: Record<ServiceGroup, string> = {
  'Car Wash Options': 'Single washes and cleans, priced per vehicle size (incl. VAT)',
  Combinations: 'Bundles that include other services; add-ons attach here',
  'Auto Body Repair': 'Repair and paint work, one general price (excl. VAT) or by quote',
};
export const SIZE_LABEL: Record<VehicleSize, string> = { small: 'Small', large: 'Large', bike: 'Bike' };
export const SIZE_HINT: Record<VehicleSize, string> = { small: 'Hatch / sedan', large: 'SUV / bakkie / bus', bike: 'Motorcycle (small price)' };
export const SIZE_ICON: Record<VehicleSize, string> = { small: 'directions_car', large: 'airport_shuttle', bike: 'two_wheeler' };

/** Car-wash groups price per Small / Large vehicle; Auto body uses one general price. */
export const isSizePriced = (group: ServiceGroup) => group !== 'Auto Body Repair';

/* ---------- chips ---------- */
export function PricingModeChip({ mode, inherited, ...rest }: { mode: PricingMode; inherited?: boolean } & Omit<React.ComponentProps<typeof StatusChip>, 'tone' | 'label'>) {
  return <StatusChip tone={PRICING_MODE_TONE[mode]} label={PRICING_MODE_LABEL[mode]} title={inherited ? `${PRICING_MODE_HINT[mode]} (inherited from the service)` : PRICING_MODE_HINT[mode]} sx={{ opacity: inherited ? 0.75 : 1 }} {...rest} />;
}

export function VatChip({ mode, inherited, ...rest }: { mode: VatMode; inherited?: boolean } & Omit<React.ComponentProps<typeof StatusChip>, 'tone' | 'label'>) {
  return <StatusChip tone={mode === 'excl' ? 'secondary' : 'neutral'} label={VAT_MODE_LABEL[mode]} title={inherited ? `${VAT_MODE_HINT[mode]} (inherited from the service)` : VAT_MODE_HINT[mode]} sx={{ opacity: inherited ? 0.75 : 1 }} {...rest} />;
}

/* ---------- money helpers ---------- */
/** "R 1 250" or "—" for a nullable cents value. */
export const priceText = (cents: number | null | undefined) => (cents === null || cents === undefined ? '—' : rands(cents));

/** "From R 140" / "R 140" / "By quote" (+ " excl. VAT"). */
export function priceLabelFor(mode: PricingMode, vat: VatMode, cents: number | null | undefined, opts: { vat?: boolean } = {}): string {
  if (mode === 'by_quote' || cents === null || cents === undefined) return 'By quote';
  const base = mode === 'from' ? `From ${rands(cents)}` : rands(cents);
  return opts.vat !== false && vat === 'excl' ? `${base} excl. VAT` : base;
}

/** Cents → rand string for a text input ("" for null). */
export const randsInput = (cents: number | null | undefined) => (cents === null || cents === undefined ? '' : String(cents / 100));

/** Rand string → cents. "" → null; not a non-negative number → undefined (invalid). */
export function parseRands(v: string): number | null | undefined {
  const t = v.trim().replace(/^R\s*/i, '').replace(/\s/g, '').replace(',', '.');
  if (t === '') return null;
  const n = Number(t);
  if (!Number.isFinite(n) || n < 0) return undefined;
  return Math.round(n * 100);
}

/* ---------- vehicle-size toggle ---------- */
export function SizeToggle({ value, onChange, dense, ariaLabel = 'Vehicle size' }: { value: VehicleSize; onChange: (s: VehicleSize) => void; dense?: boolean; ariaLabel?: string }) {
  return (
    <ToggleButtonGroup
      exclusive
      value={value}
      onChange={(_e, v: VehicleSize | null) => { if (v) onChange(v); }}
      aria-label={ariaLabel}
      sx={{ bgcolor: tk.surfaceContainerHigh, borderRadius: 999, p: 0.5, gap: 0.5, '& .MuiToggleButton-root': { border: 0, borderRadius: '999px !important', px: dense ? 1.5 : 2, py: dense ? 0.4 : 0.75, fontWeight: 600, color: tk.onSurfaceVariant, '&.Mui-selected': { bgcolor: tk.secondary, color: tk.onSecondary, '&:hover': { bgcolor: tk.secondary } } } }}
    >
      {VEHICLE_SIZES.map((s) => (
        <ToggleButton key={s} value={s} title={SIZE_HINT[s]}>
          <MSymbol name={SIZE_ICON[s]} size={18} filled={value === s} style={{ marginRight: 6 }} />{SIZE_LABEL[s]}
        </ToggleButton>
      ))}
    </ToggleButtonGroup>
  );
}

/** Curated Material Symbols for service icons (free text is still accepted). */
export const SERVICE_ICONS = ['local_car_wash', 'water_drop', 'cleaning_services', 'auto_awesome', 'layers', 'car_repair', 'car_crash', 'format_paint', 'build', 'tire_repair', 'two_wheeler', 'airport_shuttle', 'sanitizer', 'lightbulb', 'window', 'shield'];
