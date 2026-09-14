'use client';
import * as React from 'react';
import Link from 'next/link';
import { useParams } from 'next/navigation';
import Box from '@mui/material/Box';
import Typography from '@mui/material/Typography';
import Button from '@mui/material/Button';
import IconButton from '@mui/material/IconButton';
import TextField from '@mui/material/TextField';
import MenuItem from '@mui/material/MenuItem';
import Chip from '@mui/material/Chip';
import Table from '@mui/material/Table';
import TableHead from '@mui/material/TableHead';
import TableRow from '@mui/material/TableRow';
import TableCell from '@mui/material/TableCell';
import TableBody from '@mui/material/TableBody';
import Dialog from '@mui/material/Dialog';
import DialogTitle from '@mui/material/DialogTitle';
import DialogContent from '@mui/material/DialogContent';
import DialogActions from '@mui/material/DialogActions';
import Autocomplete from '@mui/material/Autocomplete';
import FormControlLabel from '@mui/material/FormControlLabel';
import Checkbox from '@mui/material/Checkbox';
import CircularProgress from '@mui/material/CircularProgress';
import LinearProgress from '@mui/material/LinearProgress';
import InputAdornment from '@mui/material/InputAdornment';
import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query';
import PageHeader from '@/components/layout/PageHeader';
import ConfigTabs from '@/components/layout/ConfigTabs';
import SectionCard from '@/components/ui/SectionCard';
import StatusChip from '@/components/ui/StatusChip';
import M3Switch from '@/components/ui/M3Switch';
import Toast from '@/components/ui/Toast';
import Tile from '@/components/ui/Tile';
import MSymbol from '@/components/MSymbol';
import { NavyPill, TonalPill } from '@/components/ui/Pills';
import { EmptyState, ErrorState, LoadingRows } from '@/components/ui/States';
import OutletCompositionDialog from '@/components/catalogue/OutletCompositionDialog';
import { GROUP_HINT, GROUP_ICON, PRICING_MODE_LABEL, SIZE_LABEL, SizeToggle, VAT_MODE_LABEL, isSizePriced, parseRands, priceLabelFor, randsInput } from '@/components/catalogue/pricing';
import { useApi, useAuth } from '@/lib/auth/AuthProvider';
import { useToast } from '@/lib/hooks';
import { can } from '@/lib/rbac';
import { fonts, shape, tk } from '@/theme/tokens';
import { SERVICE_GROUPS, type OutletServiceInput, type OutletServiceOffer, type PricingMode, type Service, type ServiceComponent, type ServiceGroup, type VatMode, type VehicleSize } from '@/lib/types';

/* ---------- row drafts ---------- */
interface RowDraft { display_name: string; price_small: string; price_large: string; price_general: string; pricing_mode: PricingMode | ''; vat_mode: VatMode | ''; sort_order: string; notes: string }
const draftFrom = (o: OutletServiceOffer): RowDraft => ({
  display_name: o.display_name ?? '', price_small: randsInput(o.price_small_cents), price_large: randsInput(o.price_large_cents), price_general: randsInput(o.price_general_cents),
  pricing_mode: o.pricing_mode_override ?? '', vat_mode: o.vat_mode_override ?? '', sort_order: o.sort_order === null ? '' : String(o.sort_order), notes: o.notes ?? '',
});
const same = (a: RowDraft, b: RowDraft) => JSON.stringify(a) === JSON.stringify(b);

/** Effective price for the preview size from the draft (outlet override → service default; bike → small; large → small). */
function preview(d: RowDraft, o: OutletServiceOffer, svc: Service | undefined, size: VehicleSize): { mode: PricingMode; vat: VatMode; cents: number | null } {
  const mode = d.pricing_mode || svc?.pricing_mode || o.pricing_mode;
  const vat = d.vat_mode || svc?.vat_mode || o.vat_mode;
  const pick = (v: string, fallback: number | null | undefined) => { const p = parseRands(v); return p === undefined ? null : p ?? fallback ?? null; };
  const small = pick(d.price_small, svc?.price_small_cents);
  const large = pick(d.price_large, svc?.price_large_cents);
  const general = pick(d.price_general, svc?.price_general_cents);
  const cents = mode === 'by_quote' ? null : size === 'large' ? large ?? small ?? general : small ?? general;
  return { mode, vat, cents };
}

function bodyFrom(d: RowDraft, group: ServiceGroup): OutletServiceInput {
  const sized = isSizePriced(group);
  return {
    display_name: d.display_name.trim() || null,
    price_small_cents: sized ? parseRands(d.price_small) ?? null : null,
    price_large_cents: sized ? parseRands(d.price_large) ?? null : null,
    price_general_cents: sized ? null : parseRands(d.price_general) ?? null,
    pricing_mode: d.pricing_mode || null, vat_mode: d.vat_mode || null,
    sort_order: d.sort_order.trim() === '' ? null : Number(d.sort_order), notes: d.notes.trim() || null,
  };
}

const priceField = (label: string, value: string, onChange: (v: string) => void, disabled: boolean) => (
  <TextField value={value} onChange={(e) => onChange(e.target.value)} size="small" disabled={disabled} error={parseRands(value) === undefined} placeholder="inherit" sx={{ width: 108 }}
    slotProps={{ input: { startAdornment: <InputAdornment position="start" sx={{ '& p': { fontSize: 13 } }}>R</InputAdornment> }, htmlInput: { inputMode: 'decimal', 'aria-label': label, style: { paddingTop: 7, paddingBottom: 7 } } }} />
);

export default function OutletCataloguePage() {
  const { id } = useParams<{ id: string }>();
  const api = useApi();
  const qc = useQueryClient();
  const { role } = useAuth();
  const toast = useToast();
  const manage = can(role, 'catalogue:manage');
  const outlets = useQuery({ queryKey: ['outlets'], queryFn: () => api.listOutlets() });
  const outlet = outlets.data?.find((o) => o.id === id) ?? null;
  const services = useQuery({ queryKey: ['services'], queryFn: () => api.listServices() });
  const offersKey = React.useMemo(() => ['outlet-offers', id] as const, [id]);
  const offers = useQuery({ queryKey: offersKey, queryFn: () => api.listOutletOffers(id, { includeUnavailable: true }), enabled: Boolean(id) });
  const rows = React.useMemo(() => offers.data ?? [], [offers.data]);
  const svcById = React.useMemo(() => new Map((services.data ?? []).map((s) => [s.id, s])), [services.data]);

  const [size, setSize] = React.useState<VehicleSize>('small');
  const [drafts, setDrafts] = React.useState<Record<string, RowDraft>>({});
  const draftOf = (o: OutletServiceOffer) => drafts[o.service_id] ?? draftFrom(o);
  const dirty = (o: OutletServiceOffer) => Boolean(drafts[o.service_id]) && !same(drafts[o.service_id], draftFrom(o));
  const setDraft = (o: OutletServiceOffer, patch: Partial<RowDraft>) => setDrafts((d) => ({ ...d, [o.service_id]: { ...draftOf(o), ...patch } }));
  const [compOffer, setCompOffer] = React.useState<OutletServiceOffer | null>(null);
  const [unbind, setUnbind] = React.useState<OutletServiceOffer | null>(null);
  const [addOpen, setAddOpen] = React.useState(false);
  const [addPick, setAddPick] = React.useState<Service | null>(null);
  const [copyOpen, setCopyOpen] = React.useState(false);
  const [busyRow, setBusyRow] = React.useState<string | null>(null);

  const invalidateDependents = React.useCallback(() => {
    void qc.invalidateQueries({ queryKey: ['walkin-services'] });
    void qc.invalidateQueries({ queryKey: ['outlet-services-for'] });
  }, [qc]);

  /** `PUT /admin/outlets/:id/services/:serviceId` with an optimistic cache update and rollback. */
  const save = useMutation({
    mutationFn: (v: { serviceId: string; body: OutletServiceInput; optimistic?: Partial<OutletServiceOffer>; label?: string }) => api.upsertOutletService(id, v.serviceId, v.body),
    onMutate: async (v) => {
      setBusyRow(v.serviceId);
      await qc.cancelQueries({ queryKey: offersKey });
      const prev = qc.getQueryData<OutletServiceOffer[]>(offersKey);
      if (prev && v.optimistic) qc.setQueryData<OutletServiceOffer[]>(offersKey, prev.map((r) => (r.service_id === v.serviceId ? { ...r, ...v.optimistic } : r)));
      return { prev };
    },
    onError: (e, _v, ctx) => { if (ctx?.prev) qc.setQueryData(offersKey, ctx.prev); toast.error(e); },
    onSuccess: (offer, v) => {
      qc.setQueryData<OutletServiceOffer[]>(offersKey, (prev) => {
        const list = prev ?? [];
        return list.some((r) => r.service_id === offer.service_id) ? list.map((r) => (r.service_id === offer.service_id ? offer : r)) : [...list, offer];
      });
      setDrafts((d) => { const { [offer.service_id]: _gone, ...rest } = d; void _gone; return rest; });
      toast.success(v.label ?? `${offer.name} saved`);
      invalidateDependents();
    },
    onSettled: () => setBusyRow(null),
  });

  const remove = useMutation({
    mutationFn: (o: OutletServiceOffer) => api.removeOutletService(id, o.service_id),
    onSuccess: (_r, o) => { qc.setQueryData<OutletServiceOffer[]>(offersKey, (prev) => (prev ?? []).filter((r) => r.service_id !== o.service_id)); toast.success(`${o.name} removed from ${outlet?.name ?? 'outlet'}`); setUnbind(null); invalidateDependents(); },
    onError: (e) => toast.error(e),
  });

  const saveRow = (o: OutletServiceOffer) => {
    const d = draftOf(o);
    const body = bodyFrom(d, o.group_name);
    const p = preview(d, o, svcById.get(o.service_id), size);
    save.mutate({ serviceId: o.service_id, body, optimistic: { display_name: body.display_name ?? null, name: body.display_name ?? o.service_name, price_small_cents: body.price_small_cents ?? null, price_large_cents: body.price_large_cents ?? null, price_general_cents: body.price_general_cents ?? null, pricing_mode_override: body.pricing_mode ?? null, vat_mode_override: body.vat_mode ?? null, pricing_mode: p.mode, vat_mode: p.vat, sort_order: body.sort_order ?? o.sort_order, notes: body.notes ?? null } });
  };

  const unbound = React.useMemo(() => (services.data ?? []).filter((s) => s.is_active && !rows.some((r) => r.service_id === s.id)), [services.data, rows]);
  const grouped = SERVICE_GROUPS.map((g) => ({ group: g, rows: rows.filter((r) => r.group_name === g).sort((a, b) => (a.sort_order ?? 9999) - (b.sort_order ?? 9999) || a.name.localeCompare(b.name)) }));
  const notFound = outlets.isSuccess && !outlet;

  return (
    <>
      <PageHeader
        title={outlet ? outlet.name : 'Outlet catalogue'}
        subtitle={outlet ? <>Catalogue · {rows.filter((r) => r.is_available).length} of {rows.length} bound services available · prices in rand{manage ? '' : ' · read-only'}. <Link href="/outlets" style={{ color: tk.primary, fontWeight: 600 }}>All outlets</Link></> : 'Per-outlet wording, prices, pricing / VAT overrides and composition'}
        actions={(
          <>
            <Box sx={{ display: 'flex', alignItems: 'center', gap: 1 }}>
              <Typography variant="body2" color="text.secondary">Preview for</Typography>
              <SizeToggle value={size} onChange={setSize} dense ariaLabel="Preview vehicle size" />
            </Box>
            {manage && <TonalPill icon="content_copy" endIcon={null} onClick={() => setCopyOpen(true)} disabled={!outlet}>Copy prices from outlet…</TonalPill>}
            {manage && <NavyPill icon="add" onClick={() => { setAddPick(null); setAddOpen(true); }} disabled={!outlet || !unbound.length}>Add service to outlet</NavyPill>}
          </>
        )}
      />
      <ConfigTabs />
      {(outlets.isLoading || offers.isLoading || services.isLoading) && <SectionCard><LoadingRows rows={6} /></SectionCard>}
      {notFound && <SectionCard><EmptyState icon="storefront" title="Outlet not found" action={<Button component={Link} href="/outlets" variant="outlined">Back to outlets</Button>} /></SectionCard>}
      {offers.error && <SectionCard><ErrorState error={offers.error} onRetry={() => offers.refetch()} /></SectionCard>}

      {outlet && offers.isSuccess && grouped.map(({ group, rows: list }) => {
        const sized = isSizePriced(group);
        return (
          <SectionCard key={group} flush title={<Box sx={{ display: 'flex', alignItems: 'center', gap: 1 }}><MSymbol name={GROUP_ICON[group]} size={22} filled style={{ color: tk.primary }} /><Typography variant="h4" component="h2">{group}</Typography><Chip size="small" label={list.length} sx={{ bgcolor: tk.surfaceContainerHigh }} /></Box>} subtitle={GROUP_HINT[group]}>
            {list.length === 0 ? (
              <Box sx={{ px: 2.5, pb: 2.5 }}><Typography variant="body2" color="text.secondary">No {group.toLowerCase()} services bound at this outlet{manage ? ' — use "Add service to outlet".' : '.'}</Typography></Box>
            ) : (
              <Box sx={{ overflowX: 'auto', pb: 1 }}>
                <Table size="small" aria-label={`${group} catalogue at ${outlet.name}`} sx={{ minWidth: sized ? 1320 : 1220, '& th': { fontSize: 11.5, letterSpacing: '0.06em', textTransform: 'uppercase', color: tk.onSurfaceVariant, fontWeight: 600, whiteSpace: 'nowrap', borderBottom: `1px solid ${tk.outlineVariant}` }, '& td': { borderBottom: `1px solid ${tk.outlineVariant}`, py: 1, verticalAlign: 'middle' } }}>
                  <TableHead>
                    <TableRow>
                      <TableCell sx={{ pl: 2.5 }}>Available</TableCell>
                      <TableCell>Service</TableCell>
                      <TableCell>Display name</TableCell>
                      {sized ? <><TableCell>Small</TableCell><TableCell>Large</TableCell></> : <TableCell>General</TableCell>}
                      <TableCell>Mode</TableCell>
                      <TableCell>VAT</TableCell>
                      <TableCell>Includes</TableCell>
                      <TableCell>Sort</TableCell>
                      <TableCell>Notes</TableCell>
                      <TableCell>{SIZE_LABEL[size]} preview</TableCell>
                      <TableCell align="right" sx={{ pr: 2.5 }} />
                    </TableRow>
                  </TableHead>
                  <TableBody>
                    {list.map((o) => {
                      const d = draftOf(o);
                      const svc = svcById.get(o.service_id);
                      const p = preview(d, o, svc, size);
                      const isDirty = dirty(o);
                      const busy = busyRow === o.service_id;
                      const byQuote = p.mode === 'by_quote';
                      return (
                        <TableRow key={o.service_id} hover sx={{ opacity: o.is_available ? 1 : 0.62, bgcolor: isDirty ? `color-mix(in srgb, ${tk.primaryContainer} 35%, transparent)` : undefined }}>
                          <TableCell sx={{ pl: 2.5 }}>
                            <M3Switch checked={o.is_available} disabled={!manage || busy} onChange={(e) => save.mutate({ serviceId: o.service_id, body: { is_available: e.target.checked }, optimistic: { is_available: e.target.checked }, label: `${o.name} ${e.target.checked ? 'switched on' : 'switched off'}` })} slotProps={{ input: { 'aria-label': `${o.name} available at ${outlet.name}` } }} />
                          </TableCell>
                          <TableCell sx={{ minWidth: 200, maxWidth: 240 }}>
                            <Typography variant="body2" sx={{ fontWeight: 600, lineHeight: 1.25 }}>{o.service_name}</Typography>
                            <Typography variant="caption" sx={{ fontFamily: fonts.mono, color: tk.onSurfaceVariant }}>{o.code}</Typography>
                            {o.is_addon && <StatusChip tone="gold" label="Add-on" sx={{ ml: 0.75, height: 20, fontSize: 11 }} />}
                          </TableCell>
                          <TableCell sx={{ minWidth: 220 }}>
                            <TextField value={d.display_name} onChange={(e) => setDraft(o, { display_name: e.target.value })} size="small" fullWidth disabled={!manage} placeholder={o.service_name} slotProps={{ htmlInput: { 'aria-label': `Display name for ${o.service_name}`, style: { paddingTop: 7, paddingBottom: 7 } } }} />
                          </TableCell>
                          {sized ? (
                            <>
                              <TableCell>{priceField(`${o.service_name} small price`, d.price_small, (v) => setDraft(o, { price_small: v }), !manage || byQuote)}</TableCell>
                              <TableCell>{priceField(`${o.service_name} large price`, d.price_large, (v) => setDraft(o, { price_large: v }), !manage || byQuote)}</TableCell>
                            </>
                          ) : (
                            <TableCell>{priceField(`${o.service_name} general price`, d.price_general, (v) => setDraft(o, { price_general: v }), !manage || byQuote)}</TableCell>
                          )}
                          <TableCell>
                            <TextField select value={d.pricing_mode} onChange={(e) => setDraft(o, { pricing_mode: e.target.value as PricingMode | '' })} size="small" disabled={!manage} sx={{ width: 128 }} slotProps={{ select: { displayEmpty: true, renderValue: (v) => (v ? PRICING_MODE_LABEL[v as PricingMode] : <span style={{ color: tk.onSurfaceVariant }}>Inherit · {PRICING_MODE_LABEL[svc?.pricing_mode ?? o.pricing_mode]}</span>) }, htmlInput: { 'aria-label': `${o.service_name} pricing mode` } }}>
                              <MenuItem value=""><em>Inherit ({PRICING_MODE_LABEL[svc?.pricing_mode ?? o.pricing_mode]})</em></MenuItem>
                              {(Object.keys(PRICING_MODE_LABEL) as PricingMode[]).map((m) => <MenuItem key={m} value={m}>{PRICING_MODE_LABEL[m]}</MenuItem>)}
                            </TextField>
                          </TableCell>
                          <TableCell>
                            <TextField select value={d.vat_mode} onChange={(e) => setDraft(o, { vat_mode: e.target.value as VatMode | '' })} size="small" disabled={!manage} sx={{ width: 122 }} slotProps={{ select: { displayEmpty: true, renderValue: (v) => (v ? VAT_MODE_LABEL[v as VatMode] : <span style={{ color: tk.onSurfaceVariant }}>Inherit · {VAT_MODE_LABEL[svc?.vat_mode ?? o.vat_mode]}</span>) }, htmlInput: { 'aria-label': `${o.service_name} VAT mode` } }}>
                              <MenuItem value=""><em>Inherit ({VAT_MODE_LABEL[svc?.vat_mode ?? o.vat_mode]})</em></MenuItem>
                              {(Object.keys(VAT_MODE_LABEL) as VatMode[]).map((m) => <MenuItem key={m} value={m}>{VAT_MODE_LABEL[m]}</MenuItem>)}
                            </TextField>
                          </TableCell>
                          <TableCell sx={{ minWidth: 180, maxWidth: 260 }}>
                            <Box role={manage ? 'button' : undefined} tabIndex={manage ? 0 : undefined} onClick={() => manage && setCompOffer(o)} onKeyDown={(e) => { if (manage && (e.key === 'Enter' || e.key === ' ')) { e.preventDefault(); setCompOffer(o); } }} aria-label={manage ? `Edit composition of ${o.name}` : undefined} sx={{ display: 'flex', gap: 0.5, flexWrap: 'wrap', alignItems: 'center', cursor: manage ? 'pointer' : 'default', borderRadius: `${shape.field}px`, p: 0.5, '&:hover': manage ? { bgcolor: tk.surfaceContainer } : undefined, '&:focus-visible': { outline: `3px solid ${tk.primary}` } }} title={o.includes.map((c) => c.name).join(', ') || undefined}>
                              {o.includes.length ? o.includes.slice(0, 3).map((c) => <Chip key={c.service_id} size="small" label={`${c.code}${c.quantity > 1 ? ` ×${c.quantity}` : ''}`} sx={{ bgcolor: o.components_source === 'outlet' ? tk.primaryContainer : tk.secondaryContainer, color: o.components_source === 'outlet' ? tk.onPrimaryContainer : tk.onSecondaryContainer, fontFamily: fonts.mono, fontSize: 11, height: 22 }} />) : <Typography variant="caption" color="text.secondary">{manage ? 'Add components…' : '—'}</Typography>}
                              {o.includes.length > 3 && <Chip size="small" label={`+${o.includes.length - 3}`} sx={{ height: 22, bgcolor: tk.surfaceContainerHigh }} />}
                              {o.includes.length > 0 && <Typography variant="caption" sx={{ color: tk.onSurfaceVariant, width: '100%' }}>{o.components_source === 'outlet' ? 'Custom for this outlet' : 'Global set'}</Typography>}
                            </Box>
                          </TableCell>
                          <TableCell>
                            <TextField type="number" value={d.sort_order} onChange={(e) => setDraft(o, { sort_order: e.target.value })} size="small" disabled={!manage} sx={{ width: 76 }} slotProps={{ htmlInput: { 'aria-label': `${o.service_name} sort order`, style: { paddingTop: 7, paddingBottom: 7 } } }} />
                          </TableCell>
                          <TableCell sx={{ minWidth: 180 }}>
                            <TextField value={d.notes} onChange={(e) => setDraft(o, { notes: e.target.value })} size="small" fullWidth disabled={!manage} placeholder="Notes" slotProps={{ htmlInput: { 'aria-label': `${o.service_name} notes`, style: { paddingTop: 7, paddingBottom: 7 } } }} />
                          </TableCell>
                          <TableCell sx={{ whiteSpace: 'nowrap' }}>
                            <StatusChip tone={byQuote ? 'warning' : p.cents === null ? 'error' : 'primary'} label={byQuote ? 'By quote' : p.cents === null ? 'No price' : priceLabelFor(p.mode, p.vat, p.cents)} />
                          </TableCell>
                          <TableCell align="right" sx={{ pr: 2.5, whiteSpace: 'nowrap' }}>
                            {manage && (
                              <>
                                <Button size="small" variant={isDirty ? 'contained' : 'text'} color="secondary" disabled={!isDirty || busy} onClick={() => saveRow(o)} startIcon={busy ? <CircularProgress size={14} color="inherit" /> : <MSymbol name="save" size={18} />} aria-label={`Save ${o.service_name}`}>Save</Button>
                                <IconButton size="small" aria-label={`Remove ${o.service_name} from ${outlet.name}`} onClick={() => setUnbind(o)} disabled={busy}><MSymbol name="link_off" size={18} /></IconButton>
                              </>
                            )}
                          </TableCell>
                        </TableRow>
                      );
                    })}
                  </TableBody>
                </Table>
              </Box>
            )}
          </SectionCard>
        );
      })}

      <OutletCompositionDialog
        open={Boolean(compOffer)}
        offer={compOffer}
        offers={rows}
        services={services.data ?? []}
        saving={save.isPending}
        onClose={() => setCompOffer(null)}
        onSave={(components: ServiceComponent[] | null) => {
          if (!compOffer) return;
          save.mutate({ serviceId: compOffer.service_id, body: { components }, label: components === null ? `${compOffer.name} now uses the global set` : `${compOffer.name} composition saved` }, { onSuccess: () => setCompOffer(null) });
        }}
      />

      <Dialog open={Boolean(unbind)} onClose={() => setUnbind(null)} aria-labelledby="unbind-title">
        <DialogTitle id="unbind-title">Remove {unbind?.name} from {outlet?.name}?</DialogTitle>
        <DialogContent><Typography variant="body2" color="text.secondary">The service stays in the global catalogue; only this outlet&apos;s wording, prices and composition are dropped. Existing bookings keep their price. Recorded in the audit log.</Typography></DialogContent>
        <DialogActions sx={{ p: 2.5, pt: 0 }}>
          <Button onClick={() => setUnbind(null)}>Keep</Button>
          <Button variant="contained" color="error" disabled={remove.isPending} onClick={() => unbind && remove.mutate(unbind)}>Remove</Button>
        </DialogActions>
      </Dialog>

      <Dialog open={addOpen} onClose={() => setAddOpen(false)} fullWidth maxWidth="sm" aria-labelledby="add-service-title">
        <DialogTitle id="add-service-title">Add service to {outlet?.name}</DialogTitle>
        <DialogContent sx={{ display: 'flex', flexDirection: 'column', gap: 2, pt: '8px !important' }}>
          <Typography variant="body2" color="text.secondary">Binds the service with the global defaults; set the outlet&apos;s wording and prices in the row afterwards.</Typography>
          <Autocomplete
            options={unbound}
            value={addPick}
            onChange={(_e, v) => setAddPick(v)}
            groupBy={(s) => s.group_name}
            getOptionLabel={(s) => s.name}
            renderOption={(props, s) => { const { key, ...rest } = props as React.HTMLAttributes<HTMLLIElement> & { key: string }; return <li key={key} {...rest}><Box><Typography variant="body2" sx={{ fontWeight: 600 }}>{s.name}</Typography><Typography variant="caption" color="text.secondary" sx={{ fontFamily: fonts.mono }}>{s.code} · {PRICING_MODE_LABEL[s.pricing_mode]} · {VAT_MODE_LABEL[s.vat_mode]}</Typography></Box></li>; }}
            renderInput={(params) => <TextField {...params} label="Service" autoFocus placeholder="Search the global catalogue…" />}
          />
        </DialogContent>
        <DialogActions sx={{ p: 2.5, pt: 0 }}>
          <Button onClick={() => setAddOpen(false)}>Cancel</Button>
          <Button variant="contained" color="secondary" disabled={!addPick || save.isPending} onClick={() => addPick && save.mutate({ serviceId: addPick.id, body: { is_available: true }, label: `${addPick.name} added to ${outlet?.name}` }, { onSuccess: () => setAddOpen(false) })}>Add service</Button>
        </DialogActions>
      </Dialog>

      {outlet && copyOpen && <CopyPricesDialog open={copyOpen} onClose={() => setCopyOpen(false)} target={outlet.id} targetName={outlet.name} outlets={(outlets.data ?? []).filter((o) => o.id !== outlet.id)} rows={rows} onDone={(n, added) => { toast.success(`${n} price${n === 1 ? '' : 's'} copied${added ? ` · ${added} service${added === 1 ? '' : 's'} added` : ''}`); void qc.invalidateQueries({ queryKey: offersKey }); invalidateDependents(); }} onError={toast.error} />}
      <Toast toast={toast.toast} onClose={toast.close} />
    </>
  );
}

/** "Copy prices from outlet…": prefill this outlet's rows from another outlet's offers, then bulk-save (one PUT per service). */
function CopyPricesDialog({ open, onClose, target, targetName, outlets, rows, onDone, onError }: {
  open: boolean; onClose: () => void; target: string; targetName: string; outlets: { id: string; name: string }[]; rows: OutletServiceOffer[];
  onDone: (saved: number, added: number) => void; onError: (e: unknown) => void;
}) {
  const api = useApi();
  const [source, setSource] = React.useState('');
  const [addMissing, setAddMissing] = React.useState(false);
  const [copyNames, setCopyNames] = React.useState(false);
  const [progress, setProgress] = React.useState<{ done: number; total: number } | null>(null);
  const src = useQuery({ queryKey: ['outlet-offers', source], queryFn: () => api.listOutletOffers(source, { includeUnavailable: true }), enabled: open && Boolean(source) });
  // Mounted only while open (see the caller), so state starts fresh on every open.
  const bound = new Set(rows.map((r) => r.service_id));
  const candidates = (src.data ?? []).filter((o) => o.is_available && (bound.has(o.service_id) || addMissing));
  const willAdd = candidates.filter((o) => !bound.has(o.service_id)).length;

  const run = async () => {
    setProgress({ done: 0, total: candidates.length });
    let saved = 0;
    try {
      for (const o of candidates) {
        await api.upsertOutletService(target, o.service_id, {
          price_small_cents: o.price_small_cents, price_large_cents: o.price_large_cents, price_general_cents: o.price_general_cents,
          pricing_mode: o.pricing_mode_override, vat_mode: o.vat_mode_override, ...(copyNames ? { display_name: o.display_name } : {}), ...(bound.has(o.service_id) ? {} : { is_available: true, sort_order: o.sort_order }),
        });
        saved += 1;
        setProgress({ done: saved, total: candidates.length });
      }
      onDone(saved, willAdd);
      onClose();
    } catch (e) {
      onError(e);
      onDone(saved, 0);
    } finally {
      setProgress(null);
    }
  };

  return (
    <Dialog open={open} onClose={() => !progress && onClose()} fullWidth maxWidth="sm" aria-labelledby="copy-prices-title">
      <DialogTitle id="copy-prices-title">Copy prices to {targetName}</DialogTitle>
      <DialogContent sx={{ display: 'flex', flexDirection: 'column', gap: 2, pt: '8px !important' }}>
        <TextField select label="Copy from" value={source} onChange={(e) => setSource(e.target.value)} disabled={Boolean(progress)} helperText="Prices and pricing / VAT overrides are copied for services both outlets offer.">
          {outlets.map((o) => <MenuItem key={o.id} value={o.id}>{o.name}</MenuItem>)}
        </TextField>
        <FormControlLabel control={<Checkbox checked={addMissing} onChange={(e) => setAddMissing(e.target.checked)} disabled={Boolean(progress)} />} label="Also add services this outlet does not offer yet" />
        <FormControlLabel control={<Checkbox checked={copyNames} onChange={(e) => setCopyNames(e.target.checked)} disabled={Boolean(progress)} />} label="Copy the display names too" />
        {source && src.isSuccess && (
          <Tile sx={{ flexDirection: 'column', alignItems: 'stretch', gap: 0.5 }}>
            <Typography variant="body2"><b>{candidates.length}</b> service{candidates.length === 1 ? '' : 's'} will be updated{willAdd ? <> · <b>{willAdd}</b> added</> : null}.</Typography>
            <Typography variant="caption" color="text.secondary">Each row is saved with a separate PUT so partial failures are visible; existing composition overrides are kept.</Typography>
          </Tile>
        )}
        {progress && <Box><LinearProgress variant="determinate" value={(progress.done / Math.max(1, progress.total)) * 100} /><Typography variant="caption" color="text.secondary">Saving {progress.done} / {progress.total}…</Typography></Box>}
      </DialogContent>
      <DialogActions sx={{ p: 2.5, pt: 0 }}>
        <Button onClick={onClose} disabled={Boolean(progress)}>Cancel</Button>
        <Button variant="contained" color="secondary" disabled={!source || !candidates.length || Boolean(progress)} onClick={() => void run()} startIcon={<MSymbol name="content_copy" size={18} />}>Copy {candidates.length ? `${candidates.length} prices` : 'prices'}</Button>
      </DialogActions>
    </Dialog>
  );
}
