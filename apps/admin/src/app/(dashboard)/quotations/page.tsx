'use client';
import { useSearchParams } from 'next/navigation';
import * as React from 'react';
import Box from '@mui/material/Box';
import Typography from '@mui/material/Typography';
import Button from '@mui/material/Button';
import Chip from '@mui/material/Chip';
import TextField from '@mui/material/TextField';
import Divider from '@mui/material/Divider';
import type { GridColDef } from '@mui/x-data-grid';
import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query';
import { format, addDays } from 'date-fns';
import PageHeader from '@/components/layout/PageHeader';
import SectionCard from '@/components/ui/SectionCard';
import AdminGrid from '@/components/ui/AdminGrid';
import DetailDrawer from '@/components/ui/DetailDrawer';
import StatusChip from '@/components/ui/StatusChip';
import Tile from '@/components/ui/Tile';
import Toast from '@/components/ui/Toast';
import MSymbol from '@/components/MSymbol';
import { NavyPill, OutletPill } from '@/components/ui/Pills';
import { EmptyState } from '@/components/ui/States';
import QuoteItemsEditor, { cleanQuoteItems, emptyQuoteItem, quoteItemsTotal } from '@/components/quotations/QuoteItemsEditor';
import PhotoDropzone, { vetPhotos } from '@/components/quotations/PhotoDropzone';
import QuotationPhotoGrid from '@/components/quotations/QuotationPhotoGrid';
import PublicLinkRow from '@/components/quotations/PublicLinkRow';
import DownloadPdfButton from '@/components/quotations/DownloadPdfButton';
import RaiseQuoteDialog from '@/components/quotations/RaiseQuoteDialog';
import { categoryMeta } from '@/components/quotations/quoteCategories';
import { useApi, useAuth } from '@/lib/auth/AuthProvider';
import { useFilters } from '@/lib/filters';
import { useToast } from '@/lib/hooks';
import { can } from '@/lib/rbac';
import { fonts, tk } from '@/theme/tokens';
import { fmtDate, fmtDateTime, rands, statusLabel } from '@/lib/format';
import type { QuoteLineItem, Quotation, QuotationAttachment, QuotationStatus } from '@/lib/types';

const STATUSES: (QuotationStatus | 'all')[] = ['all', 'requested', 'assessing', 'quoted', 'accepted', 'declined', 'expired', 'converted'];

const columns: GridColDef<Quotation>[] = [
  { field: 'ref', headerName: 'Ref', minWidth: 130, flex: 0.9, renderCell: (p) => <span className="mono" style={{ color: tk.primary, fontWeight: 700 }}>{p.row.ref}</span> },
  { field: 'customer_name', headerName: 'Customer', minWidth: 150, flex: 1.2 },
  { field: 'vehicle', headerName: 'Vehicle', minWidth: 150, flex: 1.1, valueGetter: (_v, r) => `${r.vehicle.registration_no}`, renderCell: (p) => <span><span className="mono">{p.row.vehicle.registration_no}</span> · {p.row.vehicle.make}</span> },
  { field: 'category', headerName: 'Category', minWidth: 110, flex: 0.8 },
  { field: 'outlet', headerName: 'Outlet', minWidth: 140, flex: 1, valueGetter: (_v, r) => r.outlet.name.replace('Sparkling ', '') },
  { field: 'created_at', headerName: 'Requested', minWidth: 120, flex: 0.9, renderCell: (p) => fmtDateTime(p.row.created_at) },
  { field: 'status', headerName: 'Status', minWidth: 130, flex: 0.9, renderCell: (p) => <StatusChip status={p.row.status} /> },
  { field: 'amount_cents', headerName: 'Amount', minWidth: 110, flex: 0.8, align: 'right', headerAlign: 'right', renderCell: (p) => <b>{p.row.amount_cents != null ? rands(p.row.amount_cents) : '—'}</b> },
];

type ToastFn = (kind: 'success' | 'error' | 'info', message: string | Error) => void;

const decisionSourceLabel = (s: Quotation['decision_source']) => (s === 'public_link' ? 'via link' : s === 'app' ? 'in the app' : s === 'staff' ? 'at the counter' : null);

/** Human line for the decision, e.g. "Accepted via link by Thabo N. on 12 Sep 15:19". */
function decisionLine(q: Quotation): string | null {
  if (!q.decided_at) return null;
  const verb = q.status === 'declined' ? 'Declined' : 'Accepted';
  const src = decisionSourceLabel(q.decision_source);
  return `${verb}${src ? ` ${src}` : ''}${q.decision_by_name ? ` by ${q.decision_by_name}` : ''} on ${fmtDateTime(q.decided_at)}`;
}

/** Photo management for an existing quotation: signed-in grid + immediate multipart upload. */
function PhotosSection({ q, canEdit, onToast }: { q: Quotation; canEdit: boolean; onToast: ToastFn }) {
  const api = useApi();
  const qc = useQueryClient();
  const [removing, setRemoving] = React.useState<string | null>(null);
  const invalidate = () => { void qc.invalidateQueries({ queryKey: ['quotation', q.id] }); void qc.invalidateQueries({ queryKey: ['quotations'] }); };
  const upload = useMutation({
    mutationFn: async (files: File[]) => {
      let failed = 0;
      for (const f of files) {
        try {
          await api.uploadQuotationPhoto(q.id, f);
        } catch (e) {
          failed += 1;
          onToast('error', e instanceof Error ? e : new Error(String(e)));
        }
      }
      return { added: files.length - failed };
    },
    onSuccess: ({ added }) => { if (added) onToast('success', `${added} photo${added === 1 ? '' : 's'} added`); invalidate(); },
  });
  const remove = useMutation({
    mutationFn: (att: QuotationAttachment) => { setRemoving(att.id); return api.deleteQuotationPhoto(q.id, att.id); },
    onSuccess: () => { onToast('success', 'Photo removed'); invalidate(); },
    onError: (e) => onToast('error', e),
    onSettled: () => setRemoving(null),
  });
  const editable = canEdit && !q.decided_at;
  if (!q.attachments.length && !editable) return null;
  return (
    <Box sx={{ mt: 2.5 }}>
      <Typography variant="h4" component="h3" sx={{ mb: 1 }}>Damage photos{q.attachments.length ? ` · ${q.attachments.length}` : ''}</Typography>
      <QuotationPhotoGrid quotationId={q.id} attachments={q.attachments} onRemove={editable ? (a) => remove.mutate(a) : undefined} removing={removing}>
        {editable && <PhotoDropzone compact count={q.attachments.length} busy={upload.isPending} onFiles={(files) => { const { ok, rejected } = vetPhotos(files, q.attachments.length); rejected.forEach((r) => onToast('error', new Error(r))); if (ok.length) upload.mutate(ok); }} />}
      </QuotationPhotoGrid>
      {editable && <Typography variant="caption" color="text.secondary" sx={{ display: 'block', mt: 1 }}>JPEG, PNG or HEIC up to 10 MB · shown to the customer on the public quote page.</Typography>}
    </Box>
  );
}

function QuoteForm({ q, onDone, onToast }: { q: Quotation; onDone: () => void; onToast: ToastFn }) {
  const api = useApi();
  const qc = useQueryClient();
  const source = q.items ?? q.line_items;
  const [items, setItems] = React.useState<QuoteLineItem[]>(source.length ? source.map((i) => ({ ...i })) : [emptyQuoteItem()]);
  const [validUntil, setValidUntil] = React.useState(q.valid_until ?? format(addDays(new Date(), 14), 'yyyy-MM-dd'));
  const [note, setNote] = React.useState(q.items_note ?? '');
  const services = useQuery({ queryKey: ['outlet-services-for', q.outlet.id], queryFn: () => api.listOutletServicesFor(q.outlet.id), select: (rows) => rows.filter((s) => s.category === 'auto_body') });
  const clean = cleanQuoteItems(items);
  const total = quoteItemsTotal(clean);
  const m = useMutation({
    mutationFn: () => api.submitQuote(q.id, { amount_cents: total, line_items: clean, valid_until: validUntil, items_note: note.trim() || null }),
    onSuccess: () => { onToast('success', `Quote ${q.ref} sent to ${q.customer_name}`); void qc.invalidateQueries({ queryKey: ['quotations'] }); onDone(); },
    onError: (e) => onToast('error', e),
  });
  return (
    <Box component="form" onSubmit={(e) => { e.preventDefault(); m.mutate(); }} sx={{ display: 'flex', flexDirection: 'column', gap: 1.5, mt: 1 }}>
      <Typography variant="h4" component="h3">{q.status === 'quoted' ? 'Revise quote' : 'Build quote'}</Typography>
      <QuoteItemsEditor items={items} onChange={setItems} services={services.data} disabled={m.isPending} />
      <Box sx={{ display: 'grid', gridTemplateColumns: { xs: '1fr', sm: '180px 1fr' }, gap: 1.5 }}>
        <TextField label="Valid until" type="date" value={validUntil} onChange={(e) => setValidUntil(e.target.value)} size="small" slotProps={{ inputLabel: { shrink: true }, htmlInput: { min: format(new Date(), 'yyyy-MM-dd') } }} />
        <TextField label="Notes for the customer (optional)" value={note} onChange={(e) => setNote(e.target.value)} size="small" multiline minRows={1} maxRows={3} slotProps={{ htmlInput: { maxLength: 500 } }} />
      </Box>
      <Typography variant="body2" color="text.secondary">The customer accepts or declines via the public link or in the app — nothing is booked until they approve (CUS-033).</Typography>
      <Button type="submit" variant="contained" color="secondary" disabled={m.isPending || total <= 0 || clean.length === 0} startIcon={<MSymbol name="send" size={20} />}>
        {q.status === 'quoted' ? 'Re-send quote' : 'Send quote'}
      </Button>
    </Box>
  );
}

function QuotationDrawer({ id, onClose }: { id: string | null; onClose: () => void }) {
  const api = useApi();
  const { role } = useAuth();
  const qc = useQueryClient();
  const toast = useToast();
  const onToast: ToastFn = (kind, message) => (kind === 'error' ? toast.error(message) : kind === 'info' ? toast.info(String(message)) : toast.success(String(message)));
  const q = useQuery({ queryKey: ['quotation', id], queryFn: () => api.getQuotation(id!), enabled: Boolean(id) });
  const convert = useMutation({
    mutationFn: () => api.convertQuotation(id!),
    onSuccess: (res) => { toast.success(`Converted to ${res.work_order_ref}`); void qc.invalidateQueries({ queryKey: ['quotations'] }); void qc.invalidateQueries({ queryKey: ['quotation', id] }); },
    onError: (e) => toast.error(e),
  });
  const d = q.data;
  const canWrite = can(role, 'quote:write');
  const items = d ? (d.items ?? d.line_items) : [];
  const quoted = d ? ['quoted', 'accepted', 'declined', 'expired', 'converted'].includes(d.status) : false;
  const decision = d ? decisionLine(d) : null;
  return (
    <DetailDrawer
      open={Boolean(id)}
      onClose={onClose}
      width={{ xs: '100%', sm: 520 }}
      label="Quotation"
      titleId="quotation-drawer-title"
      title={d && (
        <>
          <Typography variant="h2" className="mono" sx={{ color: tk.primary }}>{d.ref}</Typography>
          <StatusChip status={d.status} />
        </>
      )}
      subtitle={d && <>{d.customer_name} · {d.vehicle.make} {d.vehicle.model} · <span className="mono">{d.vehicle.registration_no}</span></>}
      footer={d && (
        <Box sx={{ display: 'flex', gap: 1.25, flexWrap: 'wrap' }}>
          {quoted && <DownloadPdfButton q={d} onToast={onToast} />}
          {d.status === 'accepted' && can(role, 'quote:convert') && (
            <Button variant="contained" color="secondary" sx={{ flex: 1 }} onClick={() => convert.mutate()} disabled={convert.isPending} startIcon={<MSymbol name="build" size={20} />}>
              Convert to work order
            </Button>
          )}
        </Box>
      )}
    >
      {d && (
        <>
          <Tile sx={{ alignItems: 'flex-start', flexDirection: 'column', gap: 0.5 }}>
            <Chip size="small" label={d.category} sx={{ bgcolor: tk.secondaryContainer, color: tk.onSecondaryContainer }} />
            <Typography>{d.description}</Typography>
            <Typography variant="caption" color="text.secondary">{d.outlet.name} · requested {fmtDateTime(d.created_at)}</Typography>
          </Tile>

          {decision && (
            <Tile tone={d.status === 'declined' ? 'error' : 'success'} sx={{ mt: 1.5, gap: 1.25, alignItems: 'flex-start' }}>
              <MSymbol name={d.status === 'declined' ? 'cancel' : 'check_circle'} filled size={22} />
              <Box>
                <Typography sx={{ fontWeight: 600, color: 'inherit' }}>{decision}</Typography>
                {d.decision_note && <Typography variant="body2" sx={{ color: 'inherit', opacity: 0.9 }}>“{d.decision_note}”</Typography>}
              </Box>
            </Tile>
          )}

          <PhotosSection q={d} canEdit={canWrite} onToast={onToast} />

          {items.length > 0 && (
            <>
              <Typography variant="h4" component="h3" sx={{ mt: 2.5, mb: 1 }}>What needs attention</Typography>
              <Tile sx={{ flexDirection: 'column', alignItems: 'stretch', gap: 1.25 }}>
                {items.map((li, i) => {
                  const meta = categoryMeta(li.category);
                  const qty = li.quantity ?? 1;
                  return (
                    <Box key={i} sx={{ display: 'flex', justifyContent: 'space-between', gap: 1.5, alignItems: 'flex-start' }}>
                      <Box sx={{ minWidth: 0 }}>
                        <Box sx={{ display: 'flex', alignItems: 'center', gap: 1, flexWrap: 'wrap' }}>
                          {meta && <StatusChip tone={meta.tone} label={meta.label} icon={<MSymbol name={meta.icon} size={14} filled />} />}
                          <Typography sx={{ fontWeight: 600 }}>{li.label}{qty > 1 ? ` × ${qty}` : ''}</Typography>
                        </Box>
                        {li.description && <Typography variant="body2" color="text.secondary" sx={{ mt: 0.25 }}>{li.description}</Typography>}
                      </Box>
                      <Typography sx={{ fontWeight: 600, whiteSpace: 'nowrap' }}>{rands(li.amount_cents * qty, { decimals: true })}</Typography>
                    </Box>
                  );
                })}
                <Divider sx={{ borderStyle: 'dashed', my: 0.5 }} />
                <Box sx={{ display: 'flex', justifyContent: 'space-between', alignItems: 'baseline' }}>
                  <Typography variant="h5">Total</Typography>
                  <Typography sx={{ color: tk.primary, fontSize: 22, fontWeight: 700 }}>{rands(d.amount_cents ?? 0, { decimals: true })}</Typography>
                </Box>
                <Typography variant="caption" color="text.secondary">Valid until {fmtDate(d.valid_until, 'd MMM yyyy')} · assessed by {d.assessor_name}{d.quoted_at ? ` · sent ${fmtDateTime(d.quoted_at)}` : ''}</Typography>
                {d.items_note && <Typography variant="body2" sx={{ mt: 0.5 }}><b>Notes:</b> {d.items_note}</Typography>}
              </Tile>
              {d.terms && (
                <Box component="section" aria-labelledby="quotation-terms-title" sx={{ mt: 1.5 }}>
                  <Typography id="quotation-terms-title" variant="caption" sx={{ fontWeight: 700, color: tk.onSurfaceVariant, textTransform: 'uppercase', letterSpacing: '0.06em' }}>Terms</Typography>
                  <Typography variant="caption" component="p" color="text.secondary" sx={{ mt: 0.5, lineHeight: 1.5 }}>{d.terms}</Typography>
                </Box>
              )}
            </>
          )}

          {quoted && (
            <Box sx={{ mt: 2 }}>
              <PublicLinkRow q={d} canShare={canWrite && d.status !== 'converted'} onToast={onToast} />
            </Box>
          )}

          {d.status === 'converted' && <Typography sx={{ mt: 2, fontWeight: 600, color: tk.success }}>Converted to {d.work_order_ref}</Typography>}
          {['requested', 'assessing', 'quoted'].includes(d.status) && canWrite && (
            <>
              <Divider sx={{ my: 2.5 }} />
              <QuoteForm key={`${d.id}-${d.quoted_at ?? ''}`} q={d} onToast={onToast} onDone={() => void qc.invalidateQueries({ queryKey: ['quotation', id] })} />
            </>
          )}
          {!canWrite && ['requested', 'assessing'].includes(d.status) && <Typography variant="body2" color="text.secondary" sx={{ mt: 2 }}>Only supervisors and managers can issue quotes.</Typography>}
        </>
      )}
      <Toast toast={toast.toast} onClose={toast.close} />
    </DetailDrawer>
  );
}

export default function QuotationsPage() {
  const api = useApi();
  const { role } = useAuth();
  const { outletId } = useFilters();
  const toast = useToast();
  const [status, setStatus] = React.useState<QuotationStatus | 'all'>('all');
  const params = useSearchParams();
  const [focus, setFocus] = React.useState<string | null>(params.get('focus'));
  const [raise, setRaise] = React.useState(false);
  const q = useQuery({ queryKey: ['quotations', outletId, status], queryFn: () => api.listQuotations({ outlet_id: outletId, status }) });
  const counts = React.useMemo(() => {
    const all = q.data ?? [];
    return { requested: all.filter((x) => x.status === 'requested').length, accepted: all.filter((x) => x.status === 'accepted').length };
  }, [q.data]);
  const onToast = (kind: 'success' | 'error' | 'info', message: string | Error) => (kind === 'error' ? toast.error(message) : kind === 'info' ? toast.info(String(message)) : toast.success(String(message)));
  return (
    <>
      <PageHeader
        title="Quotations"
        subtitle="Auto-body quote requests · assess, quote, share the public link, convert to work orders"
        actions={
          <>
            <OutletPill />
            {can(role, 'quote:write') && <NavyPill icon="request_quote" onClick={() => setRaise(true)}>Raise quote</NavyPill>}
          </>
        }
      />
      <Box sx={{ display: 'flex', gap: 1, flexWrap: 'wrap' }}>
        {STATUSES.map((s) => (
          <Chip key={s} label={s === 'all' ? 'All' : statusLabel(s)} clickable onClick={() => setStatus(s)} sx={{ bgcolor: s === status ? tk.secondary : tk.surfaceContainerHigh, color: s === status ? tk.onSecondary : tk.onSurface }} aria-pressed={s === status} />
        ))}
      </Box>
      <SectionCard flush title="Quote requests" subtitle={status === 'all' ? `${counts.requested} awaiting assessment · ${counts.accepted} accepted, ready to convert` : undefined}>
        <Box sx={{ px: 1.5, pb: 1 }}>
          {!q.isLoading && !q.data?.length ? <EmptyState icon="request_quote" title="No quotations" /> : (
            <AdminGrid<Quotation> rows={q.data ?? []} columns={columns} loading={q.isLoading} getRowClassName={() => 'row-clickable'} onRowClick={(p) => setFocus(p.row.id)} sx={{ '& .MuiDataGrid-cell': { fontFamily: fonts.sans } }} />
          )}
        </Box>
      </SectionCard>
      <QuotationDrawer id={focus} onClose={() => setFocus(null)} />
      {can(role, 'quote:write') && <RaiseQuoteDialog open={raise} onClose={() => setRaise(false)} onOpenQuotation={(id) => setFocus(id)} onToast={onToast} />}
      <Toast toast={toast.toast} onClose={toast.close} />
    </>
  );
}
