'use client';
import * as React from 'react';
import { useRouter } from 'next/navigation';
import Box from '@mui/material/Box';
import Typography from '@mui/material/Typography';
import TextField from '@mui/material/TextField';
import MenuItem from '@mui/material/MenuItem';
import ToggleButton from '@mui/material/ToggleButton';
import ToggleButtonGroup from '@mui/material/ToggleButtonGroup';
import Button from '@mui/material/Button';
import Chip from '@mui/material/Chip';
import Checkbox from '@mui/material/Checkbox';
import FormControlLabel from '@mui/material/FormControlLabel';
import Divider from '@mui/material/Divider';
import { useQuery } from '@tanstack/react-query';
import { addDays, format, isSameDay } from 'date-fns';
import MSymbol from '@/components/MSymbol';
import IconTile from '@/components/ui/IconTile';
import Tile from '@/components/ui/Tile';
import { EmptyState, ErrorState, LoadingRows } from '@/components/ui/States';
import RaiseQuoteDialog from '@/components/quotations/RaiseQuoteDialog';
import { GROUP_HINT, GROUP_ICON, SIZE_LABEL, priceLabelFor } from '@/components/catalogue/pricing';
import RadioCards from './RadioCards';
import { memberBenefit, offerPriceFor, pricing, type MemberBenefit, type WalkInDraft } from './useWalkInDraft';
import { useApi, useAuth } from '@/lib/auth/AuthProvider';
import { fmtTime, rands } from '@/lib/format';
import { tk } from '@/theme/tokens';
import { SERVICE_GROUPS, type AvailabilitySlot, type MembershipSummary, type Outlet, type OutletServiceOffer, type VehicleSize } from '@/lib/types';

function ServiceCard({ s, size, onQuote, membership }: { s: OutletServiceOffer; size: VehicleSize; onQuote: () => void; membership: MembershipSummary | null }) {
  const cents = offerPriceFor(s, size);
  const byQuote = s.pricing_mode === 'by_quote';
  const pts = byQuote ? 0 : s.points_estimate;
  const mb: MemberBenefit | null = byQuote || cents === null ? null : memberBenefit(membership, s.code, cents, 0);
  return (
    <>
      <IconTile icon={s.icon || 'local_car_wash'} tone={mb?.benefit === 'included' ? 'gold' : byQuote ? 'neutral' : 'primary'} size={44} />
      <Box sx={{ minWidth: 0, display: 'flex', flexDirection: 'column', gap: 0.4, flex: 1 }}>
        <Typography variant="h5" component="span">{s.name}</Typography>
        <Typography variant="body2" component="span" sx={{ color: tk.onSurfaceVariant }}>{s.description ? `${s.description} · ` : ''}{s.duration_minutes} min</Typography>
        {s.includes.length > 0 && (
          <Typography variant="body2" component="span" sx={{ color: tk.onSurfaceVariant, display: 'flex', gap: 0.5, alignItems: 'flex-start' }}>
            <MSymbol name="layers" size={16} style={{ marginTop: 2, flexShrink: 0 }} />
            <span><b>Includes:</b> {s.includes.map((c) => `${c.name}${c.quantity > 1 ? ` ×${c.quantity}` : ''}`).join(', ')}</span>
          </Typography>
        )}
        <Box sx={{ display: 'flex', gap: 0.75, flexWrap: 'wrap', mt: 0.25, alignItems: 'center' }}>
          {mb?.benefit === 'included' && <Chip size="small" icon={<MSymbol name="workspace_premium" size={14} filled />} label={mb.label} sx={{ background: tk.goldGradient, color: tk.onGold, fontWeight: 700, '& .MuiChip-icon': { color: tk.onGold } }} />}
          {mb?.benefit === 'discount' && <Chip size="small" icon={<MSymbol name="sell" size={14} filled />} label={`${mb.label} · plan discount`} sx={{ bgcolor: tk.successContainer, color: tk.onSuccessContainer, fontWeight: 600, '& .MuiChip-icon': { color: tk.onSuccessContainer } }} />}
          {pts > 0 && mb?.benefit !== 'included' && <Chip size="small" icon={<MSymbol name="sell" size={14} filled style={{ color: tk.onGold }} />} label={`Earn ${pts} pts`} sx={{ bgcolor: tk.goldLight, color: tk.onGold, fontWeight: 600, '& .MuiChip-icon': { color: tk.onGold } }} />}
          {byQuote && (
            <Button size="small" variant="outlined" onClick={(e) => { e.stopPropagation(); onQuote(); }} onKeyDown={(e) => e.stopPropagation()} startIcon={<MSymbol name="request_quote" size={16} />} sx={{ pointerEvents: 'auto', py: 0.25 }}>
              Request a quote instead
            </Button>
          )}
          {!byQuote && cents === null && <Chip size="small" label={`No ${SIZE_LABEL[size].toLowerCase()} price`} sx={{ bgcolor: tk.errorContainer, color: tk.onErrorContainer }} />}
        </Box>
      </Box>
      <Typography component="span" sx={{ mr: 1, fontWeight: 700, fontSize: 17, whiteSpace: 'nowrap', color: byQuote ? tk.onSurfaceVariant : 'inherit', textAlign: 'right' }}>
        {mb?.benefit === 'included' ? (
          <>
            <Typography component="span" variant="caption" sx={{ display: 'block', fontWeight: 500, color: tk.onSurfaceVariant, textDecoration: 'line-through' }}>{priceLabelFor(s.pricing_mode, s.vat_mode, cents, { vat: false })}</Typography>
            {rands(0)}
          </>
        ) : mb?.benefit === 'discount' && cents !== null ? (
          <>
            <Typography component="span" variant="caption" sx={{ display: 'block', fontWeight: 500, color: tk.onSurfaceVariant, textDecoration: 'line-through' }}>{priceLabelFor(s.pricing_mode, s.vat_mode, cents, { vat: false })}</Typography>
            {priceLabelFor(s.pricing_mode, s.vat_mode, cents - mb.discount, { vat: false })}
          </>
        ) : priceLabelFor(s.pricing_mode, s.vat_mode, cents, { vat: false })}
        {s.vat_mode === 'excl' && !byQuote && <Typography component="span" variant="caption" sx={{ display: 'block', fontWeight: 500, color: tk.onSurfaceVariant }}>excl. VAT</Typography>}
      </Typography>
    </>
  );
}

export default function ServiceStep({ draft, patch, onToast }: { draft: WalkInDraft; patch: (p: Partial<WalkInDraft>) => void; onToast?: (kind: 'success' | 'error' | 'info', message: string | Error) => void }) {
  const api = useApi();
  const router = useRouter();
  const { profile, role } = useAuth();
  const outletsQ = useQuery({ queryKey: ['outlets'], queryFn: () => api.listOutlets() });
  const outlets = React.useMemo<Outlet[]>(() => {
    const all = (outletsQ.data ?? []).filter((o) => o.is_active);
    return role === 'admin' ? all : all.filter((o) => profile?.outlet_ids.includes(o.id));
  }, [outletsQ.data, role, profile]);

  // Default the outlet to the only / first one the user may book at.
  React.useEffect(() => {
    if (!draft.outlet_id && outlets.length) patch({ outlet_id: outlets[0].id });
  }, [draft.outlet_id, outlets, patch]);

  const outlet = outlets.find((o) => o.id === draft.outlet_id) ?? null;
  const size = draft.vehicle_size;
  const servicesQ = useQuery({ queryKey: ['walkin-services', draft.outlet_id, size], queryFn: () => api.listOutletServicesFor(draft.outlet_id!, size), enabled: Boolean(draft.outlet_id) });
  const offers = React.useMemo(() => servicesQ.data ?? [], [servicesQ.data]);
  const groups = React.useMemo(() => SERVICE_GROUPS.map((g) => ({ group: g, items: offers.filter((o) => o.group_name === g && !o.is_addon) })).filter((x) => x.items.length), [offers]);
  const addonOffers = React.useMemo(() => (draft.service ? offers.filter((o) => o.is_addon && o.addon_group_name === draft.service!.group_name && o.service_id !== draft.service!.service_id && offerPriceFor(o, size) !== null) : []), [offers, draft.service, size]);

  // Keep the chosen service / add-ons in step with the freshly priced offers (size or outlet changed, prices edited).
  React.useEffect(() => {
    if (!servicesQ.isSuccess || !draft.service) return;
    const fresh = offers.find((o) => o.service_id === draft.service!.service_id);
    const freshAddons = draft.addons.map((a) => offers.find((o) => o.service_id === a.service_id)).filter((o): o is OutletServiceOffer => Boolean(o));
    if (!fresh) { patch({ service: null, addons: [] }); return; }
    if (JSON.stringify(fresh) !== JSON.stringify(draft.service) || freshAddons.length !== draft.addons.length || freshAddons.some((a, i) => JSON.stringify(a) !== JSON.stringify(draft.addons[i]))) patch({ service: fresh, addons: freshAddons });
  }, [servicesQ.isSuccess, offers, draft.service, draft.addons, patch]);

  const slotsQ = useQuery({
    queryKey: ['availability', draft.outlet_id, draft.service?.id, draft.date],
    queryFn: () => api.availability(draft.outlet_id!, draft.service!.id, draft.date),
    enabled: Boolean(draft.outlet_id && draft.service && !draft.book_now),
  });

  const p = pricing(draft);
  const days = React.useMemo(() => Array.from({ length: 14 }, (_, i) => addDays(new Date(), i)), []);
  const selectedDay = days.find((d) => format(d, 'yyyy-MM-dd') === draft.date) ?? days[0];
  const slot = (slotsQ.data ?? []).find((s) => s.slot_start === draft.slot_start) ?? null;
  const [quoteOpen, setQuoteOpen] = React.useState(false);
  const quoteInitial = React.useMemo(() => ({ customer: draft.customer, vehicle: draft.vehicle, outlet_id: draft.outlet_id ?? '' }), [draft.customer, draft.vehicle, draft.outlet_id]);
  const toggleAddon = (a: OutletServiceOffer, on: boolean) => patch({ addons: on ? [...draft.addons.filter((x) => x.service_id !== a.service_id), a] : draft.addons.filter((x) => x.service_id !== a.service_id) });

  return (
    <Box sx={{ display: 'flex', flexDirection: 'column', gap: 3 }}>
      <Box sx={{ display: 'grid', gridTemplateColumns: { xs: '1fr', md: '1fr 1fr' }, gap: 2 }}>
        <TextField
          select
          label="Outlet"
          value={outlet?.id ?? ''}
          onChange={(e) => patch({ outlet_id: e.target.value, service: null, addons: [], slot_start: null })}
          disabled={!outlets.length}
          helperText={outlet ? `${outlet.bay_count} bays · slots every ${outlet.slot_minutes} min · prices for a ${SIZE_LABEL[size].toLowerCase()} vehicle` : outletsQ.isLoading ? 'Loading outlets…' : 'No outlet available for your account'}
        >
          {outlets.map((o) => <MenuItem key={o.id} value={o.id}>{o.name}</MenuItem>)}
        </TextField>
        <Box>
          <Typography component="span" id="walkin-when-label" variant="body2" color="text.secondary" sx={{ display: 'block', mb: 0.75 }}>When</Typography>
          <ToggleButtonGroup
            exclusive
            value={draft.book_now ? 'now' : 'slot'}
            onChange={(_e, v: 'now' | 'slot' | null) => { if (v) patch({ book_now: v === 'now', slot_start: v === 'now' ? null : draft.slot_start }); }}
            aria-labelledby="walkin-when-label"
            sx={{ bgcolor: tk.surfaceContainerHigh, borderRadius: 999, p: 0.5, gap: 0.5, '& .MuiToggleButton-root': { border: 0, borderRadius: '999px !important', px: 2.25, py: 0.75, fontWeight: 600, color: tk.onSurfaceVariant, '&.Mui-selected': { bgcolor: tk.secondary, color: tk.onSecondary, '&:hover': { bgcolor: tk.secondary } } } }}
          >
            <ToggleButton value="now"><MSymbol name="bolt" size={18} filled style={{ marginRight: 6 }} />Now (walk-in)</ToggleButton>
            <ToggleButton value="slot"><MSymbol name="event" size={18} style={{ marginRight: 6 }} />Pick a slot</ToggleButton>
          </ToggleButtonGroup>
        </Box>
      </Box>

      {draft.membership?.plan && draft.membership.membership && (
        <Tile tone={draft.membership.membership.status === 'active' ? 'gold' : 'warning'} sx={{ minHeight: 52, py: 1 }} role="note">
          <MSymbol name="workspace_premium" filled size={22} style={{ color: tk.onGold }} />
          <Typography variant="body2" sx={{ fontWeight: 600 }}>
            {draft.membership.membership.status === 'active'
              ? `${draft.membership.plan.name} member · ${draft.membership.benefits_summary} — covered services are marked below`
              : `${draft.membership.plan.name} membership is ${draft.membership.membership.status.replace('_', ' ')} — benefits paused until the open invoice is paid`}
          </Typography>
        </Tile>
      )}
      <Box sx={{ display: 'flex', flexDirection: 'column', gap: 2.5 }}>
        {servicesQ.isLoading && <LoadingRows rows={3} height={72} />}
        {servicesQ.error && <ErrorState error={servicesQ.error} onRetry={() => servicesQ.refetch()} />}
        {servicesQ.isSuccess && (groups.length ? groups.map(({ group, items }) => (
          <Box key={group}>
            <Box sx={{ display: 'flex', alignItems: 'center', gap: 1, mb: 0.25 }}>
              <MSymbol name={GROUP_ICON[group]} size={22} filled style={{ color: tk.primary }} />
              <Typography variant="h4" component="h3">{group}</Typography>
              <Chip size="small" label={items.length} sx={{ bgcolor: tk.surfaceContainerHigh, height: 22 }} />
            </Box>
            <Typography variant="body2" color="text.secondary" sx={{ mb: 1.25 }}>{GROUP_HINT[group]}</Typography>
            <RadioCards
              label={`${group} services`}
              items={items}
              getKey={(s) => s.service_id}
              selected={draft.service?.service_id ?? null}
              onSelect={(s) => patch({ service: s, addons: [], slot_start: null })}
              isDisabled={(s) => s.pricing_mode === 'by_quote' || offerPriceFor(s, size) === null}
              render={(s) => <ServiceCard s={s} size={size} onQuote={() => setQuoteOpen(true)} membership={draft.membership} />}
              columns={{ xs: '1fr', lg: '1fr 1fr' }}
              sx={{ '& [role=radio][aria-disabled=true]': { opacity: 0.7 } }}
            />
          </Box>
        )) : <EmptyState icon="local_car_wash" title="No services at this outlet" description="Bind services to this outlet under Configuration → Outlets → Catalogue." />)}
      </Box>

      {draft.service && addonOffers.length > 0 && (
        <Box>
          <Typography variant="h4" component="h3" sx={{ mb: 0.25 }}>Add-ons</Typography>
          <Typography variant="body2" color="text.secondary" sx={{ mb: 1.25 }}>Extras for {draft.service.group_name.toLowerCase()} — priced for a {SIZE_LABEL[size].toLowerCase()} vehicle and added to the total.</Typography>
          <Box role="group" aria-label="Add-ons" sx={{ display: 'grid', gridTemplateColumns: { xs: '1fr', md: '1fr 1fr' }, gap: 1 }}>
            {addonOffers.map((a) => {
              const on = draft.addons.some((x) => x.service_id === a.service_id);
              const cents = offerPriceFor(a, size) ?? 0;
              return (
                <Tile key={a.service_id} sx={{ py: 1, bgcolor: on ? tk.primaryContainer : tk.surfaceContainer, border: `2px solid ${on ? tk.primary : 'transparent'}` }}>
                  <FormControlLabel
                    control={<Checkbox checked={on} onChange={(e) => toggleAddon(a, e.target.checked)} />}
                    label={<Box><Typography variant="body1" sx={{ fontWeight: 600 }}>{a.name}</Typography><Typography variant="body2" sx={{ color: tk.onSurfaceVariant }}>{a.description ? `${a.description} · ` : ''}+{a.duration_minutes} min</Typography></Box>}
                    sx={{ flex: 1, m: 0 }}
                  />
                  <Typography sx={{ fontWeight: 700, whiteSpace: 'nowrap' }}>+ {rands(cents)}</Typography>
                </Tile>
              );
            })}
          </Box>
        </Box>
      )}

      {!draft.book_now && draft.service && (
        <Box sx={{ display: 'flex', flexDirection: 'column', gap: 2 }}>
          <Box>
            <Typography variant="h4" component="h3" sx={{ mb: 1.5 }}>{format(selectedDay, 'MMMM yyyy')}</Typography>
            <RadioCards
              label="Date"
              items={days}
              getKey={(d) => format(d, 'yyyy-MM-dd')}
              selected={draft.date}
              onSelect={(d) => patch({ date: format(d, 'yyyy-MM-dd'), slot_start: null })}
              dense
              columns="repeat(7, minmax(0, 1fr))"
              sx={{ '& [role=radio]': { flexDirection: 'column', gap: 0, py: 1, borderRadius: '16px', justifyContent: 'center' } }}
              render={(d, sel) => (
                <>
                  <Typography variant="caption" component="span" sx={{ color: sel ? tk.onPrimaryContainer : tk.onSurfaceVariant }}>{isSameDay(d, new Date()) ? 'Today' : format(d, 'EEE')}</Typography>
                  <Typography component="span" sx={{ fontWeight: 700, fontSize: 18, lineHeight: 1.2 }}>{format(d, 'd')}</Typography>
                </>
              )}
            />
          </Box>
          <Box>
            <Typography variant="h4" component="h3" sx={{ mb: 0.25 }}>Available slots <Typography component="span" variant="body2" color="text.secondary">· revalidated on submit</Typography></Typography>
            {slotsQ.isLoading && <LoadingRows rows={2} height={40} />}
            {slotsQ.error && <ErrorState error={slotsQ.error} onRetry={() => slotsQ.refetch()} />}
            {slotsQ.isSuccess && (slotsQ.data.length ? (
              <RadioCards<AvailabilitySlot>
                label="Time slot"
                items={slotsQ.data}
                getKey={(s) => s.slot_start}
                selected={draft.slot_start}
                onSelect={(s) => patch({ slot_start: s.slot_start })}
                isDisabled={(s) => !s.available}
                dense
                columns="repeat(auto-fill, minmax(96px, 1fr))"
                sx={{ mt: 1.5, '& [role=radio]': { justifyContent: 'center' } }}
                render={(s) => <Typography component="span" sx={{ fontWeight: 600, fontVariantNumeric: 'tabular-nums' }} title={s.available ? `${s.capacity - s.booked} of ${s.capacity} bays free` : 'Fully booked'}>{fmtTime(s.slot_start)}</Typography>}
              />
            ) : <EmptyState icon="event_busy" title="Closed on this day" description="Pick another date." />)}
          </Box>
        </Box>
      )}

      {draft.service && outlet && (draft.book_now || slot) && (
        <Tile tone="primary" sx={{ alignItems: 'flex-start', gap: 1.5, py: 2 }} role="status">
          <MSymbol name={draft.book_now ? 'bolt' : 'event_available'} filled size={24} />
          <Box sx={{ flex: 1, minWidth: 0 }}>
            <Typography variant="h5" component="p">
              {draft.book_now ? 'Now' : `${format(new Date(slot!.slot_start), 'EEE d MMM')}, ${fmtTime(slot!.slot_start)}`} at {outlet.name} · {draft.service.name}, ±{draft.service.duration_minutes + draft.addons.reduce((s, a) => s + a.duration_minutes, 0)} min
            </Typography>
            <Box sx={{ mt: 0.75, display: 'grid', gridTemplateColumns: 'auto auto', columnGap: 2, rowGap: 0.25, justifyContent: 'start', fontSize: 14 }}>
              <span>{draft.service.name} · {SIZE_LABEL[p.size]}{draft.service.pricing_mode === 'from' ? ' (from)' : ''}</span><span style={{ textAlign: 'right', fontVariantNumeric: 'tabular-nums' }}>{rands(p.base, { decimals: true })}</span>
              {p.addons.map((a) => <React.Fragment key={a.service_id}><span>+ {a.name}</span><span style={{ textAlign: 'right', fontVariantNumeric: 'tabular-nums' }}>{rands(a.cents, { decimals: true })}</span></React.Fragment>)}
              {p.discount > 0 && p.discount_label && <><span>{p.discount_label}</span><span style={{ textAlign: 'right', fontVariantNumeric: 'tabular-nums' }}>−{rands(p.discount, { decimals: true })}</span></>}
              {p.vat_mode === 'excl' && <><span>VAT 15 %</span><span style={{ textAlign: 'right', fontVariantNumeric: 'tabular-nums' }}>{rands(p.vat, { decimals: true })}</span></>}
              <Divider sx={{ gridColumn: '1 / -1', borderStyle: 'dashed', my: 0.25 }} />
              <strong>Total</strong><strong style={{ textAlign: 'right', fontVariantNumeric: 'tabular-nums' }}>{rands(p.total, { decimals: true })}</strong>
            </Box>
            {draft.book_now && <Typography variant="body2" sx={{ mt: 0.75 }}>Rounded up to the next free slot; capacity is checked on confirm.</Typography>}
          </Box>
        </Tile>
      )}

      <RaiseQuoteDialog
        open={quoteOpen}
        initial={quoteInitial}
        onClose={() => setQuoteOpen(false)}
        onOpenQuotation={(id) => router.push(`/quotations?focus=${id}`)}
        onToast={(kind, message) => onToast?.(kind, message)}
      />
    </Box>
  );
}
