'use client';
import * as React from 'react';
import Link from 'next/link';
import Box from '@mui/material/Box';
import Typography from '@mui/material/Typography';
import Button from '@mui/material/Button';
import Dialog from '@mui/material/Dialog';
import DialogTitle from '@mui/material/DialogTitle';
import DialogContent from '@mui/material/DialogContent';
import DialogActions from '@mui/material/DialogActions';
import TextField from '@mui/material/TextField';
import FormControlLabel from '@mui/material/FormControlLabel';
import type { GridColDef } from '@mui/x-data-grid';
import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query';
import PageHeader from '@/components/layout/PageHeader';
import ConfigTabs from '@/components/layout/ConfigTabs';
import SectionCard from '@/components/ui/SectionCard';
import AdminGrid from '@/components/ui/AdminGrid';
import StatusChip from '@/components/ui/StatusChip';
import M3Switch from '@/components/ui/M3Switch';
import IconTile from '@/components/ui/IconTile';
import Toast from '@/components/ui/Toast';
import MSymbol from '@/components/MSymbol';
import { NavyPill } from '@/components/ui/Pills';
import PhoneField from '@/components/ui/PhoneField';
import { ErrorState, LoadingRows } from '@/components/ui/States';
import { useApi, useAuth } from '@/lib/auth/AuthProvider';
import { useToast } from '@/lib/hooks';
import { can } from '@/lib/rbac';
import { fonts, tk } from '@/theme/tokens';
import { formatPhone, isE164 } from '@/lib/phone';
import type { OpeningHours, Outlet, OutletBankDetails } from '@/lib/types';

const DAYS: (keyof OpeningHours)[] = ['mon', 'tue', 'wed', 'thu', 'fri', 'sat', 'sun'];
const DAY_LABEL: Record<keyof OpeningHours, string> = { mon: 'Mon', tue: 'Tue', wed: 'Wed', thu: 'Thu', fri: 'Fri', sat: 'Sat', sun: 'Sun' };
const blankBank: OutletBankDetails = { financial_institution: '', account_name: '', branch: '', branch_code: '', account_number: '', account_type: '' };
const BANK_FIELDS: { key: keyof OutletBankDetails; label: string }[] = [
  { key: 'financial_institution', label: 'Financial institution' },
  { key: 'account_name', label: 'Account name' },
  { key: 'branch', label: 'Branch' },
  { key: 'branch_code', label: 'Branch code' },
  { key: 'account_number', label: 'Account number' },
  { key: 'account_type', label: 'Account type' },
];
const blank: Partial<Outlet> = { code: '', name: '', address_line: '', city: '', province: 'Gauteng', phone: '', email: '', bay_count: 3, slot_minutes: 30, is_active: true, legal_name: '', trading_as: '', company_registration_no: '', vat_number: '', registered_office: '', bank_details: { ...blankBank }, opening_hours: { mon: ['07:30', '17:30'], tue: ['07:30', '17:30'], wed: ['07:30', '17:30'], thu: ['07:30', '17:30'], fri: ['07:30', '17:30'], sat: ['08:00', '14:00'], sun: null } };

/** Compact "Mon–Fri 07:30–17:30 · Sat 08:00–14:00" summary for the grid. */
function hoursSummary(h: OpeningHours): string {
  const parts: string[] = [];
  let i = 0;
  while (i < DAYS.length) {
    const v = h[DAYS[i]];
    let j = i;
    while (j + 1 < DAYS.length && JSON.stringify(h[DAYS[j + 1]]) === JSON.stringify(v)) j += 1;
    if (v) parts.push(`${DAY_LABEL[DAYS[i]]}${j > i ? `–${DAY_LABEL[DAYS[j]]}` : ''} ${v[0]}–${v[1]}`);
    i = j + 1;
  }
  return parts.join(' · ') || 'Closed';
}

function OutletDialog({ outlet, open, onClose }: { outlet: Outlet | null; open: boolean; onClose: () => void }) {
  return (
    <Dialog open={open} onClose={onClose} fullWidth maxWidth="sm" aria-labelledby="outlet-title">
      {open && <OutletForm outlet={outlet} onClose={onClose} />}
    </Dialog>
  );
}

function OutletForm({ outlet, onClose }: { outlet: Outlet | null; onClose: () => void }) {
  const api = useApi();
  const qc = useQueryClient();
  const toast = useToast();
  const [form, setForm] = React.useState<Partial<Outlet>>(() => (outlet ? { ...outlet } : { ...blank }));
  // Outlet numbers are stored as E.164; older rows may still hold free text ("012 348 4228 / 079 …") — shown until replaced.
  const legacyPhone = form.phone && !isE164(form.phone) ? form.phone : null;
  const [phoneValid, setPhoneValid] = React.useState(true);
  const m = useMutation({
    mutationFn: () => (outlet ? api.updateOutlet(outlet.id, form) : api.createOutlet(form)),
    onSuccess: (o) => { toast.success(`${o.name} saved`); void qc.invalidateQueries({ queryKey: ['outlets'] }); onClose(); },
    onError: (e) => toast.error(e),
  });
  const hours = form.opening_hours ?? blank.opening_hours!;
  const setHours = (d: keyof OpeningHours, v: [string, string] | null) => setForm({ ...form, opening_hours: { ...hours, [d]: v } });
  const bank = form.bank_details ?? blankBank;
  const setBank = (k: keyof OutletBankDetails, v: string) => setForm({ ...form, bank_details: { ...blankBank, ...bank, [k]: v } });
  return (
    <>
      <DialogTitle id="outlet-title" sx={{ display: 'flex', alignItems: 'center', justifyContent: 'space-between', gap: 2 }}>
        <span>{outlet ? `Edit ${outlet.name}` : 'New outlet'}</span>
        {outlet && <Button component={Link} href={`/outlets/${outlet.id}/catalogue`} size="small" variant="outlined" startIcon={<MSymbol name="menu_book" size={18} />}>Catalogue</Button>}
      </DialogTitle>
      <DialogContent sx={{ display: 'grid', gridTemplateColumns: '1fr 1fr', gap: 1.5, pt: '8px !important' }}>
        <TextField label="Code" value={form.code ?? ''} onChange={(e) => setForm({ ...form, code: e.target.value.toUpperCase() })} size="small" required />
        <TextField label="Name" value={form.name ?? ''} onChange={(e) => setForm({ ...form, name: e.target.value })} size="small" required />
        <TextField label="Address" value={form.address_line ?? ''} onChange={(e) => setForm({ ...form, address_line: e.target.value })} size="small" sx={{ gridColumn: '1 / -1' }} />
        <TextField label="City" value={form.city ?? ''} onChange={(e) => setForm({ ...form, city: e.target.value })} size="small" />
        <TextField label="Province" value={form.province ?? ''} onChange={(e) => setForm({ ...form, province: e.target.value })} size="small" />
        <PhoneField label="Phone" kind="any" value={legacyPhone ? '' : form.phone ?? ''} onChange={(e164, meta) => { setForm({ ...form, phone: e164 || null }); setPhoneValid(e164 === '' || meta.valid); }} size="small" helperText={legacyPhone ? `On file: ${legacyPhone} — enter the main number to replace it` : 'Landline or mobile, with country code'} />
        <TextField label="E-mail" value={form.email ?? ''} onChange={(e) => setForm({ ...form, email: e.target.value })} size="small" />
        <TextField label="Bays" type="number" value={form.bay_count ?? 3} onChange={(e) => setForm({ ...form, bay_count: Number(e.target.value) })} size="small" slotProps={{ htmlInput: { min: 1 } }} />
        <TextField label="Slot minutes" type="number" value={form.slot_minutes ?? 30} onChange={(e) => setForm({ ...form, slot_minutes: Number(e.target.value) })} size="small" slotProps={{ htmlInput: { min: 10, max: 240 } }} />
        <Typography variant="h5" sx={{ gridColumn: '1 / -1', mt: 1 }}>Legal &amp; banking</Typography>
        <Typography variant="caption" color="text.secondary" sx={{ gridColumn: '1 / -1', mt: -1 }}>Printed on quotations — legal entity, VAT registration and the account customers pay into.</Typography>
        <TextField label="Legal name" value={form.legal_name ?? ''} onChange={(e) => setForm({ ...form, legal_name: e.target.value })} size="small" />
        <TextField label="Trading as" value={form.trading_as ?? ''} onChange={(e) => setForm({ ...form, trading_as: e.target.value })} size="small" />
        <TextField label="Company registration no" value={form.company_registration_no ?? ''} onChange={(e) => setForm({ ...form, company_registration_no: e.target.value })} size="small" />
        <TextField label="VAT number" value={form.vat_number ?? ''} onChange={(e) => setForm({ ...form, vat_number: e.target.value })} size="small" />
        <TextField label="Registered office" value={form.registered_office ?? ''} onChange={(e) => setForm({ ...form, registered_office: e.target.value })} size="small" sx={{ gridColumn: '1 / -1' }} />
        {BANK_FIELDS.map((f) => (
          <TextField key={f.key} label={f.label} value={bank[f.key] ?? ''} onChange={(e) => setBank(f.key, e.target.value)} size="small" />
        ))}
        <Typography variant="h5" sx={{ gridColumn: '1 / -1', mt: 1 }}>Opening hours</Typography>
        {DAYS.map((d) => {
          const v = hours[d];
          return (
            <Box key={d} sx={{ gridColumn: '1 / -1', display: 'flex', alignItems: 'center', gap: 1 }}>
              <Typography sx={{ width: 40, fontWeight: 600 }}>{DAY_LABEL[d]}</Typography>
              <M3Switch checked={Boolean(v)} onChange={(e) => setHours(d, e.target.checked ? ['08:00', '17:00'] : null)} slotProps={{ input: { 'aria-label': `${DAY_LABEL[d]} open` } }} />
              {v ? (
                <>
                  <TextField type="time" size="small" value={v[0]} onChange={(e) => setHours(d, [e.target.value, v[1]])} slotProps={{ htmlInput: { 'aria-label': `${DAY_LABEL[d]} opens` } }} />
                  <Typography color="text.secondary">–</Typography>
                  <TextField type="time" size="small" value={v[1]} onChange={(e) => setHours(d, [v[0], e.target.value])} slotProps={{ htmlInput: { 'aria-label': `${DAY_LABEL[d]} closes` } }} />
                </>
              ) : (
                <Typography color="text.secondary">Closed</Typography>
              )}
            </Box>
          );
        })}
        <FormControlLabel sx={{ gridColumn: '1 / -1' }} control={<M3Switch checked={form.is_active ?? true} onChange={(e) => setForm({ ...form, is_active: e.target.checked })} />} label={form.is_active ? 'Active — bookable by customers' : 'Inactive — hidden from booking flow'} />
      </DialogContent>
      <DialogActions sx={{ p: 2.5, pt: 0 }}>
        <Button onClick={onClose}>Cancel</Button>
        <Button variant="contained" color="secondary" disabled={m.isPending || !form.name || !form.code || !phoneValid} onClick={() => m.mutate()}>Save</Button>
      </DialogActions>
      <Toast toast={toast.toast} onClose={toast.close} />
    </>
  );
}

export default function OutletsPage() {
  const api = useApi();
  const { role } = useAuth();
  const q = useQuery({ queryKey: ['outlets'], queryFn: () => api.listOutlets() });
  const [edit, setEdit] = React.useState<Outlet | null>(null);
  const [open, setOpen] = React.useState(false);
  const manage = can(role, 'catalogue:manage');

  const columns = React.useMemo<GridColDef<Outlet>[]>(() => [
    { field: 'name', headerName: 'Outlet', flex: 1.8, minWidth: 300, renderCell: (p) => (
      <Box sx={{ display: 'flex', alignItems: 'center', gap: 1.25, minWidth: 0, py: 0.5 }}>
        <IconTile icon="storefront" tone={p.row.is_active ? 'primary' : 'neutral'} size={38} />
        <Box sx={{ minWidth: 0 }}>
          <Typography variant="body1" sx={{ fontWeight: 600, lineHeight: 1.25 }} noWrap>{p.row.name}</Typography>
          <Typography variant="caption" color="text.secondary" noWrap sx={{ display: 'block' }} title={p.row.address_line ?? ''}>{p.row.address_line}</Typography>
        </Box>
      </Box>
    ) },
    { field: 'code', headerName: 'Code', width: 80, cellClassName: 'mono' },
    { field: 'city', headerName: 'City', width: 140 },
    { field: 'province', headerName: 'Province', width: 140 },
    { field: 'bay_count', headerName: 'Bays', width: 70, align: 'center', headerAlign: 'center' },
    { field: 'opening_hours', headerName: 'Hours', flex: 1.2, minWidth: 220, sortable: false, valueGetter: (_v, r) => hoursSummary(r.opening_hours), renderCell: (p) => <Typography variant="body2" noWrap title={p.value as string}>{p.value as string}</Typography> },
    { field: 'phone', headerName: 'Contact', flex: 1, minWidth: 200, sortable: false, renderCell: (p) => (
      <Box sx={{ minWidth: 0 }}>
        <Typography variant="body2" noWrap>{formatPhone(p.row.phone) || '—'}</Typography>
        <Typography variant="caption" color="text.secondary" noWrap sx={{ display: 'block' }}>{p.row.email ?? ''}</Typography>
      </Box>
    ) },
    { field: 'legal_name', headerName: 'Legal entity', width: 150, renderCell: (p) => (p.row.legal_name ? <StatusChip tone="success" label="On file" title={`${p.row.legal_name} · VAT ${p.row.vat_number ?? '—'}`} /> : <StatusChip tone="warning" label="Not captured" title="Legal name, VAT number and banking are printed on quotations — add them in the editor" />) },
    { field: 'is_active', headerName: 'Status', width: 100, renderCell: (p) => <StatusChip tone={p.row.is_active ? 'success' : 'neutral'} label={p.row.is_active ? 'Active' : 'Inactive'} /> },
    { field: 'actions', headerName: '', width: manage ? 220 : 130, sortable: false, align: 'right', renderCell: (p) => (
      <Box sx={{ display: 'flex', gap: 0.75 }} onClick={(e) => e.stopPropagation()}>
        <Button component={Link} href={`/outlets/${p.row.id}/catalogue`} size="small" variant="outlined" startIcon={<MSymbol name="menu_book" size={18} />} aria-label={`Catalogue for ${p.row.name}`}>Catalogue</Button>
        {manage && <Button size="small" variant="text" onClick={() => { setEdit(p.row); setOpen(true); }} startIcon={<MSymbol name="edit" size={18} />} aria-label={`Edit ${p.row.name}`}>Edit</Button>}
      </Box>
    ) },
  ], [manage]);

  return (
    <>
      <PageHeader title="Configuration" subtitle="Outlets · addresses, opening hours, bays, legal & banking identity — and each outlet's own service catalogue" actions={manage ? <NavyPill icon="add_business" onClick={() => { setEdit(null); setOpen(true); }}>New outlet</NavyPill> : undefined} />
      <ConfigTabs />
      <SectionCard flush title="Outlets" subtitle={q.data ? `${q.data.length} outlets · ${new Set(q.data.map((o) => o.province)).size} provinces` : undefined}>
        {q.isLoading && <Box sx={{ px: 2.5, pb: 2.5 }}><LoadingRows rows={5} /></Box>}
        {q.error && <ErrorState error={q.error} onRetry={() => q.refetch()} />}
        {q.data && (
          <AdminGrid<Outlet>
            rows={q.data}
            columns={columns}
            getRowId={(r) => r.id}
            rowHeight={64}
            getRowClassName={() => (manage ? 'row-clickable' : '')}
            onRowClick={(p) => { if (manage) { setEdit(p.row); setOpen(true); } }}
            sx={{ px: 1, '& .mono': { fontFamily: fonts.mono, color: tk.onSurfaceVariant } }}
            aria-label="Outlets"
          />
        )}
      </SectionCard>
      <OutletDialog outlet={edit} open={open} onClose={() => setOpen(false)} />
    </>
  );
}
