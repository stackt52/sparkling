'use client';
import * as React from 'react';
import Box from '@mui/material/Box';
import Typography from '@mui/material/Typography';
import Button from '@mui/material/Button';
import Chip from '@mui/material/Chip';
import Drawer from '@mui/material/Drawer';
import IconButton from '@mui/material/IconButton';
import TextField from '@mui/material/TextField';
import Divider from '@mui/material/Divider';
import type { GridColDef } from '@mui/x-data-grid';
import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query';
import { format, addDays } from 'date-fns';
import PageHeader from '@/components/layout/PageHeader';
import SectionCard from '@/components/ui/SectionCard';
import AdminGrid from '@/components/ui/AdminGrid';
import StatusChip from '@/components/ui/StatusChip';
import Tile from '@/components/ui/Tile';
import Toast from '@/components/ui/Toast';
import MSymbol from '@/components/MSymbol';
import { OutletPill } from '@/components/ui/Pills';
import { EmptyState } from '@/components/ui/States';
import { useApi, useAuth } from '@/lib/auth/AuthProvider';
import { useFilters } from '@/lib/filters';
import { useToast } from '@/lib/hooks';
import { can } from '@/lib/rbac';
import { fonts, tk } from '@/theme/tokens';
import { fmtDate, fmtDateTime, rands, statusLabel } from '@/lib/format';
import type { QuoteLineItem, Quotation, QuotationStatus } from '@/lib/types';

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

function QuoteForm({ q, onDone }: { q: Quotation; onDone: () => void }) {
  const api = useApi();
  const qc = useQueryClient();
  const toast = useToast();
  const [items, setItems] = React.useState<QuoteLineItem[]>(q.line_items.length ? q.line_items : [{ label: '', amount_cents: 0 }]);
  const [validUntil, setValidUntil] = React.useState(q.valid_until ?? format(addDays(new Date(), 14), 'yyyy-MM-dd'));
  const total = items.reduce((s, i) => s + (i.amount_cents || 0), 0);
  const m = useMutation({
    mutationFn: () => api.submitQuote(q.id, { amount_cents: total, line_items: items.filter((i) => i.label.trim()), valid_until: validUntil }),
    onSuccess: () => { toast.success(`Quote ${q.ref} sent to ${q.customer_name}`); void qc.invalidateQueries({ queryKey: ['quotations'] }); onDone(); },
    onError: (e) => toast.error(e),
  });
  return (
    <Box component="form" onSubmit={(e) => { e.preventDefault(); m.mutate(); }} sx={{ display: 'flex', flexDirection: 'column', gap: 1.5, mt: 1 }}>
      <Typography variant="h4">Line items</Typography>
      {items.map((it, i) => (
        <Box key={i} sx={{ display: 'flex', gap: 1 }}>
          <TextField label="Description" value={it.label} onChange={(e) => setItems(items.map((x, j) => (j === i ? { ...x, label: e.target.value } : x)))} size="small" sx={{ flex: 1 }} required />
          <TextField label="Amount (R)" type="number" value={it.amount_cents / 100 || ''} onChange={(e) => setItems(items.map((x, j) => (j === i ? { ...x, amount_cents: Math.round(Number(e.target.value) * 100) } : x)))} size="small" sx={{ width: 130 }} slotProps={{ htmlInput: { min: 0, step: 1 } }} />
          <IconButton aria-label="Remove line" onClick={() => setItems(items.filter((_, j) => j !== i))} disabled={items.length === 1}><MSymbol name="delete" size={20} /></IconButton>
        </Box>
      ))}
      <Button size="small" variant="text" onClick={() => setItems([...items, { label: '', amount_cents: 0 }])} startIcon={<MSymbol name="add" size={18} />} sx={{ alignSelf: 'flex-start' }}>Add line</Button>
      <TextField label="Valid until" type="date" value={validUntil} onChange={(e) => setValidUntil(e.target.value)} size="small" slotProps={{ inputLabel: { shrink: true } }} sx={{ maxWidth: 200 }} />
      <Tile sx={{ justifyContent: 'space-between' }}>
        <Typography variant="h5">Total</Typography>
        <Typography variant="h3" sx={{ color: tk.primary }}>{rands(total, { decimals: true })}</Typography>
      </Tile>
      <Typography variant="body2" color="text.secondary">The customer accepts or declines in the app — nothing is booked until they approve (CUS-033).</Typography>
      <Button type="submit" variant="contained" color="secondary" disabled={m.isPending || total <= 0} startIcon={<MSymbol name="send" size={20} />}>
        {q.status === 'quoted' ? 'Re-send quote' : 'Send quote'}
      </Button>
      <Toast toast={toast.toast} onClose={toast.close} />
    </Box>
  );
}

function QuotationDrawer({ id, onClose }: { id: string | null; onClose: () => void }) {
  const api = useApi();
  const { role } = useAuth();
  const qc = useQueryClient();
  const toast = useToast();
  const q = useQuery({ queryKey: ['quotation', id], queryFn: () => api.getQuotation(id!), enabled: Boolean(id) });
  const convert = useMutation({
    mutationFn: () => api.convertQuotation(id!),
    onSuccess: (res) => { toast.success(`Converted to ${res.work_order_ref}`); void qc.invalidateQueries({ queryKey: ['quotations'] }); void qc.invalidateQueries({ queryKey: ['quotation', id] }); },
    onError: (e) => toast.error(e),
  });
  const d = q.data;
  const canWrite = can(role, 'quote:write');
  return (
    <Drawer anchor="right" open={Boolean(id)} onClose={onClose} slotProps={{ paper: { sx: { width: { xs: '100%', sm: 500 }, borderRadius: { xs: 0, sm: '28px 0 0 28px' }, p: 3 } } }}>
      <Box sx={{ display: 'flex', alignItems: 'center', justifyContent: 'space-between' }}>
        <Typography variant="overline" color="text.secondary">Quotation</Typography>
        <IconButton aria-label="Close" onClick={onClose}><MSymbol name="close" /></IconButton>
      </Box>
      {d && (
        <>
          <Box sx={{ display: 'flex', alignItems: 'center', gap: 1.5 }}>
            <Typography variant="h2" className="mono" sx={{ color: tk.primary }}>{d.ref}</Typography>
            <StatusChip status={d.status} />
          </Box>
          <Typography color="text.secondary">{d.customer_name} · {d.vehicle.make} {d.vehicle.model} · <span className="mono">{d.vehicle.registration_no}</span></Typography>
          <Tile sx={{ mt: 2, alignItems: 'flex-start', flexDirection: 'column', gap: 0.5 }}>
            <Chip size="small" label={d.category} sx={{ bgcolor: tk.secondaryContainer, color: tk.onSecondaryContainer }} />
            <Typography>{d.description}</Typography>
            <Typography variant="caption" color="text.secondary">{d.outlet.name} · requested {fmtDateTime(d.created_at)}</Typography>
          </Tile>
          {d.attachments.length > 0 && (
            <Box sx={{ display: 'flex', gap: 1, mt: 1.5 }}>
              {d.attachments.map((a) => (
                <Box key={a.id} sx={{ width: 88, height: 88, borderRadius: '14px', background: `repeating-linear-gradient(45deg, ${tk.surfaceContainerHigh} 0 8px, ${tk.surfaceContainer} 8px 16px)`, display: 'grid', placeItems: 'center', color: tk.onSurfaceVariant }} aria-label={`Attachment ${a.storage_path}`}>
                  <MSymbol name="image" size={26} />
                </Box>
              ))}
            </Box>
          )}
          {d.line_items.length > 0 && (
            <>
              <Typography variant="h4" sx={{ mt: 2.5, mb: 1 }}>Quote</Typography>
              <Tile sx={{ flexDirection: 'column', alignItems: 'stretch', gap: 0.5 }}>
                {d.line_items.map((li, i) => (
                  <Box key={i} sx={{ display: 'flex', justifyContent: 'space-between' }}>
                    <Typography>{li.label}</Typography>
                    <Typography sx={{ fontWeight: 600 }}>{rands(li.amount_cents, { decimals: true })}</Typography>
                  </Box>
                ))}
                <Divider sx={{ borderStyle: 'dashed', my: 0.5 }} />
                <Box sx={{ display: 'flex', justifyContent: 'space-between' }}>
                  <Typography variant="h5">Total</Typography>
                  <Typography variant="h3" sx={{ color: tk.primary }}>{rands(d.amount_cents ?? 0, { decimals: true })}</Typography>
                </Box>
                <Typography variant="caption" color="text.secondary">Valid until {fmtDate(d.valid_until, 'd MMM yyyy')} · assessed by {d.assessor_name}{d.decided_at ? ` · decided ${fmtDateTime(d.decided_at)}` : ''}</Typography>
                {d.decision_note && <Typography variant="body2">Customer note: “{d.decision_note}”</Typography>}
              </Tile>
            </>
          )}
          {d.status === 'accepted' && can(role, 'quote:convert') && (
            <Button variant="contained" color="secondary" sx={{ mt: 2.5 }} onClick={() => convert.mutate()} disabled={convert.isPending} startIcon={<MSymbol name="build" size={20} />}>
              Convert to work order
            </Button>
          )}
          {d.status === 'converted' && <Typography sx={{ mt: 2, fontWeight: 600, color: tk.success }}>Converted to {d.work_order_ref}</Typography>}
          {['requested', 'assessing', 'quoted'].includes(d.status) && canWrite && (
            <>
              <Divider sx={{ my: 2.5 }} />
              <QuoteForm q={d} onDone={() => void qc.invalidateQueries({ queryKey: ['quotation', id] })} />
            </>
          )}
          {!canWrite && ['requested', 'assessing'].includes(d.status) && <Typography variant="body2" color="text.secondary" sx={{ mt: 2 }}>Only supervisors and managers can issue quotes.</Typography>}
        </>
      )}
      <Toast toast={toast.toast} onClose={toast.close} />
    </Drawer>
  );
}

export default function QuotationsPage() {
  const api = useApi();
  const { outletId } = useFilters();
  const [status, setStatus] = React.useState<QuotationStatus | 'all'>('all');
  const [focus, setFocus] = React.useState<string | null>(null);
  const q = useQuery({ queryKey: ['quotations', outletId, status], queryFn: () => api.listQuotations({ outlet_id: outletId, status }) });
  const counts = React.useMemo(() => {
    const all = q.data ?? [];
    return { requested: all.filter((x) => x.status === 'requested').length, accepted: all.filter((x) => x.status === 'accepted').length };
  }, [q.data]);
  return (
    <>
      <PageHeader title="Quotations" subtitle="Auto-body quote requests · assess, quote, convert to work orders" actions={<OutletPill />} />
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
    </>
  );
}
