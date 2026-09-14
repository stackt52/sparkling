'use client';
import * as React from 'react';
import Box from '@mui/material/Box';
import Typography from '@mui/material/Typography';
import Divider from '@mui/material/Divider';
import { format } from 'date-fns';
import MSymbol from '@/components/MSymbol';
import SectionCard from '@/components/ui/SectionCard';
import { SIZE_LABEL } from '@/components/catalogue/pricing';
import { pricing, type WalkInDraft } from './useWalkInDraft';
import { fmtTime, rands } from '@/lib/format';
import { fonts, tk } from '@/theme/tokens';
import { TIER_NAME } from '@/components/ui/TierChip';

function Line({ icon, label, value, mono }: { icon: string; label: string; value: React.ReactNode; mono?: boolean }) {
  const empty = value === null || value === undefined || value === '';
  return (
    <Box sx={{ display: 'flex', gap: 1.25, alignItems: 'flex-start', py: 0.75 }}>
      <MSymbol name={icon} size={20} filled={!empty} style={{ color: empty ? tk.outline : tk.primary, marginTop: 1 }} />
      <Box sx={{ minWidth: 0 }}>
        <Typography variant="caption" color="text.secondary" sx={{ display: 'block' }}>{label}</Typography>
        <Typography variant="body1" component="div" sx={{ fontWeight: 600, fontFamily: mono ? fonts.mono : undefined, color: empty ? tk.onSurfaceVariant : tk.onSurface }}>{empty ? '—' : value}</Typography>
      </Box>
    </Box>
  );
}

function Money({ label, value, tone }: { label: React.ReactNode; value: string; tone?: 'success' | 'muted' }) {
  return (
    <Box sx={{ display: 'flex', justifyContent: 'space-between', gap: 1, py: 0.25, color: tone === 'success' ? tk.success : tone === 'muted' ? tk.onSurfaceVariant : undefined }}>
      <Typography variant="body2" sx={{ color: 'inherit' }}>{label}</Typography>
      <Typography variant="body2" sx={{ color: 'inherit', fontVariantNumeric: 'tabular-nums', whiteSpace: 'nowrap' }}>{value}</Typography>
    </Box>
  );
}

/** Sticky side panel: what has been chosen so far and the running total (announced politely). */
export default function WalkInSummary({ draft, outletName }: { draft: WalkInDraft; outletName: string | null }) {
  const p = pricing(draft);
  const when = draft.book_now ? 'Now (walk-in)' : draft.slot_start ? `${format(new Date(draft.slot_start), 'EEE d MMM')} · ${fmtTime(draft.slot_start)}` : null;
  return (
    <SectionCard title="Walk-in summary" component="aside" sx={{ position: { lg: 'sticky' }, top: { lg: 96 }, gap: 0 }}>
      <Line icon="person" label="Customer" value={draft.customer ? <>{draft.customer.full_name}{draft.customer.loyalty && <Typography component="span" variant="body2" color="text.secondary"> · {draft.customer.loyalty.plan_name ?? TIER_NAME[draft.customer.loyalty.tier]}{draft.customer.loyalty.plan_code ? ` · ${draft.customer.loyalty.included_remaining} wash${draft.customer.loyalty.included_remaining === 1 ? '' : 'es'} left` : ''}</Typography>}</> : null} />
      <Line icon="directions_car" label="Vehicle" value={draft.vehicle ? <>{draft.vehicle.registration_no}<Typography component="span" variant="body2" color="text.secondary" sx={{ fontFamily: fonts.sans }}> · {SIZE_LABEL[draft.vehicle_size]}</Typography></> : null} mono />
      <Line icon="storefront" label="Outlet" value={outletName} />
      <Line icon="local_car_wash" label="Service" value={draft.service ? `${draft.service.name} · ${draft.service.duration_minutes} min` : null} />
      {draft.addons.length > 0 && <Line icon="add_circle" label="Add-ons" value={draft.addons.map((a) => a.name).join(', ')} />}
      <Line icon="schedule" label="When" value={draft.service ? when : null} />
      <Divider sx={{ my: 1.5, borderStyle: 'dashed' }} />
      <Box aria-live="polite" aria-atomic="true">
        {draft.service && (
          <>
            <Money label={<>{draft.service.name}{draft.service.pricing_mode === 'from' ? ' (from)' : ''}</>} value={rands(p.base, { decimals: true })} tone="muted" />
            {p.addons.map((a) => <Money key={a.service_id} label={`+ ${a.name}`} value={rands(a.cents, { decimals: true })} tone="muted" />)}
            {p.discount > 0 && p.discount_label && <Money label={p.discount_label} value={`− ${rands(p.discount, { decimals: true })}`} tone="success" />}
            {p.vat_mode === 'excl' && <Money label="VAT 15 %" value={rands(p.vat, { decimals: true })} tone="muted" />}
          </>
        )}
        <Box sx={{ display: 'flex', justifyContent: 'space-between', alignItems: 'baseline', pt: 1 }}>
          <Typography variant="h5" component="p">Total{draft.service?.vat_mode === 'incl' ? <Typography component="span" variant="caption" color="text.secondary"> incl. VAT</Typography> : null}</Typography>
          <Typography component="p" sx={{ fontWeight: 700, fontSize: 24, color: tk.primary, fontVariantNumeric: 'tabular-nums' }}>{draft.service ? rands(p.total, { decimals: true }) : '—'}</Typography>
        </Box>
      </Box>
    </SectionCard>
  );
}
