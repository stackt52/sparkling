'use client';
import * as React from 'react';
import Box from '@mui/material/Box';
import Typography from '@mui/material/Typography';
import Button from '@mui/material/Button';
import Dialog from '@mui/material/Dialog';
import DialogTitle from '@mui/material/DialogTitle';
import DialogContent from '@mui/material/DialogContent';
import DialogActions from '@mui/material/DialogActions';
import TextField from '@mui/material/TextField';
import MenuItem from '@mui/material/MenuItem';
import FormControlLabel from '@mui/material/FormControlLabel';
import Table from '@mui/material/Table';
import TableHead from '@mui/material/TableHead';
import TableRow from '@mui/material/TableRow';
import TableCell from '@mui/material/TableCell';
import TableBody from '@mui/material/TableBody';
import IconButton from '@mui/material/IconButton';
import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query';
import PageHeader from '@/components/layout/PageHeader';
import ConfigTabs from '@/components/layout/ConfigTabs';
import SectionCard from '@/components/ui/SectionCard';
import StatusChip from '@/components/ui/StatusChip';
import M3Switch from '@/components/ui/M3Switch';
import IconTile from '@/components/ui/IconTile';
import Toast from '@/components/ui/Toast';
import MSymbol from '@/components/MSymbol';
import { NavyPill } from '@/components/ui/Pills';
import { LoadingRows } from '@/components/ui/States';
import { useApi, useAuth } from '@/lib/auth/AuthProvider';
import { useToast } from '@/lib/hooks';
import { can } from '@/lib/rbac';
import { tk } from '@/theme/tokens';
import { rands } from '@/lib/format';
import type { Service, ServiceCategory } from '@/lib/types';

const blankService: Partial<Service> = { code: '', name: '', description: '', category: 'car_wash', duration_minutes: 30, base_price_cents: 0, is_quote_based: false, icon: 'local_car_wash', checklist_template_id: null, is_active: true };

function ServiceDialog({ service, open, onClose }: { service: Service | null; open: boolean; onClose: () => void }) {
  return (
    <Dialog open={open} onClose={onClose} fullWidth maxWidth="sm" aria-labelledby="svc-title">
      {open && <ServiceForm service={service} onClose={onClose} />}
    </Dialog>
  );
}

function ServiceForm({ service, onClose }: { service: Service | null; onClose: () => void }) {
  const api = useApi();
  const qc = useQueryClient();
  const toast = useToast();
  const templates = useQuery({ queryKey: ['templates'], queryFn: () => api.listTemplates() });
  const [form, setForm] = React.useState<Partial<Service>>(() => (service ? { ...service } : { ...blankService }));
  const m = useMutation({
    mutationFn: () => (service ? api.updateService(service.id, form) : api.createService(form)),
    onSuccess: (s) => { toast.success(`${s.name} saved`); void qc.invalidateQueries({ queryKey: ['services'] }); onClose(); },
    onError: (e) => toast.error(e),
  });
  return (
    <>
      <DialogTitle id="svc-title">{service ? `Edit ${service.name}` : 'New service'}</DialogTitle>
      <DialogContent sx={{ display: 'grid', gridTemplateColumns: '1fr 1fr', gap: 1.5, pt: '8px !important' }}>
        <TextField label="Code" value={form.code ?? ''} onChange={(e) => setForm({ ...form, code: e.target.value.toUpperCase() })} size="small" required />
        <TextField label="Name" value={form.name ?? ''} onChange={(e) => setForm({ ...form, name: e.target.value })} size="small" required />
        <TextField label="Description" value={form.description ?? ''} onChange={(e) => setForm({ ...form, description: e.target.value })} size="small" sx={{ gridColumn: '1 / -1' }} />
        <TextField select label="Category" value={form.category ?? 'car_wash'} onChange={(e) => setForm({ ...form, category: e.target.value as ServiceCategory })} size="small">
          <MenuItem value="car_wash">Car wash</MenuItem>
          <MenuItem value="auto_body">Auto body</MenuItem>
        </TextField>
        <TextField label="Icon (Material Symbol)" value={form.icon ?? ''} onChange={(e) => setForm({ ...form, icon: e.target.value })} size="small" />
        <TextField label="Duration (min)" type="number" value={form.duration_minutes ?? 30} onChange={(e) => setForm({ ...form, duration_minutes: Number(e.target.value) })} size="small" />
        <TextField label="Base price (R)" type="number" value={(form.base_price_cents ?? 0) / 100} onChange={(e) => setForm({ ...form, base_price_cents: Math.round(Number(e.target.value) * 100) })} size="small" disabled={form.is_quote_based} />
        <TextField select label="Checklist template" value={form.checklist_template_id ?? ''} onChange={(e) => setForm({ ...form, checklist_template_id: e.target.value || null })} size="small" sx={{ gridColumn: '1 / -1' }}>
          <MenuItem value="">None</MenuItem>
          {(templates.data ?? []).filter((t) => t.status === 'published').map((t) => <MenuItem key={t.id} value={t.id}>{t.name} · v{t.version}</MenuItem>)}
        </TextField>
        <FormControlLabel control={<M3Switch checked={form.is_quote_based ?? false} onChange={(e) => setForm({ ...form, is_quote_based: e.target.checked })} />} label="Quote-based" />
        <FormControlLabel control={<M3Switch checked={form.is_active ?? true} onChange={(e) => setForm({ ...form, is_active: e.target.checked })} />} label="Active" />
      </DialogContent>
      <DialogActions sx={{ p: 2.5, pt: 0 }}>
        <Button onClick={onClose}>Cancel</Button>
        <Button variant="contained" color="secondary" disabled={m.isPending || !form.name || !form.code} onClick={() => m.mutate()}>Save</Button>
      </DialogActions>
      <Toast toast={toast.toast} onClose={toast.close} />
    </>
  );
}

export default function ServicesPage() {
  const api = useApi();
  const { role } = useAuth();
  const qc = useQueryClient();
  const toast = useToast();
  const services = useQuery({ queryKey: ['services'], queryFn: () => api.listServices() });
  const outlets = useQuery({ queryKey: ['outlets'], queryFn: () => api.listOutlets() });
  const matrix = useQuery({ queryKey: ['outlet-services'], queryFn: () => api.listOutletServices() });
  const [edit, setEdit] = React.useState<Service | null>(null);
  const [open, setOpen] = React.useState(false);
  const [priceEdit, setPriceEdit] = React.useState<{ outletId: string; serviceId: string; value: string } | null>(null);
  const manage = can(role, 'catalogue:manage');
  const setCell = useMutation({
    mutationFn: (v: { outletId: string; serviceId: string; patch: { is_available?: boolean; price_cents?: number | null } }) => api.setOutletService(v.outletId, v.serviceId, v.patch),
    onSuccess: () => { void qc.invalidateQueries({ queryKey: ['outlet-services'] }); setPriceEdit(null); },
    onError: (e) => toast.error(e),
  });
  const cell = (o: string, s: string) => matrix.data?.find((x) => x.outlet_id === o && x.service_id === s);
  return (
    <>
      <PageHeader title="Configuration" subtitle="Services · catalogue, per-outlet availability and price overrides (ADM-021/022)" actions={manage ? <NavyPill icon="add" onClick={() => { setEdit(null); setOpen(true); }}>New service</NavyPill> : undefined} />
      <ConfigTabs />
      <SectionCard title="Catalogue">
        {services.isLoading && <LoadingRows rows={4} />}
        <Box sx={{ display: 'grid', gridTemplateColumns: { xs: '1fr', md: 'repeat(2, 1fr)', xl: 'repeat(4, 1fr)' }, gap: '12px' }}>
          {(services.data ?? []).map((s) => (
            <Box key={s.id} sx={{ display: 'flex', gap: 1.5, alignItems: 'center', p: 1.5, borderRadius: '18px', bgcolor: tk.surfaceContainer, opacity: s.is_active ? 1 : 0.6 }}>
              <IconTile icon={s.icon} tone={s.category === 'auto_body' ? 'neutral' : 'primary'} />
              <Box sx={{ flex: 1, minWidth: 0 }}>
                <Typography variant="h6" noWrap>{s.name}</Typography>
                <Typography variant="caption" color="text.secondary">{s.is_quote_based ? 'Quote-based' : rands(s.base_price_cents)} · {s.duration_minutes} min</Typography>
              </Box>
              {manage && <IconButton size="small" aria-label={`Edit ${s.name}`} onClick={() => { setEdit(s); setOpen(true); }}><MSymbol name="edit" size={18} /></IconButton>}
            </Box>
          ))}
        </Box>
      </SectionCard>
      <SectionCard title="Availability & price overrides" subtitle="Toggle availability per outlet; click a price to override the base price (blank = inherit).">
        <Box sx={{ overflowX: 'auto' }}>
          <Table size="small" aria-label="Outlet service matrix">
            <TableHead>
              <TableRow>
                <TableCell>Service</TableCell>
                {(outlets.data ?? []).map((o) => <TableCell key={o.id} align="center">{o.name.replace('Sparkling ', '')}</TableCell>)}
              </TableRow>
            </TableHead>
            <TableBody>
              {(services.data ?? []).map((s) => (
                <TableRow key={s.id}>
                  <TableCell><b>{s.name}</b><Typography variant="caption" color="text.secondary" sx={{ display: 'block' }}>{s.is_quote_based ? 'quote' : `base ${rands(s.base_price_cents)}`}</Typography></TableCell>
                  {(outlets.data ?? []).map((o) => {
                    const c = cell(o.id, s.id);
                    const editing = priceEdit && priceEdit.outletId === o.id && priceEdit.serviceId === s.id;
                    return (
                      <TableCell key={o.id} align="center">
                        <Box sx={{ display: 'inline-flex', alignItems: 'center', gap: 1 }}>
                          <M3Switch checked={c?.is_available ?? true} disabled={!manage} onChange={(e) => setCell.mutate({ outletId: o.id, serviceId: s.id, patch: { is_available: e.target.checked } })} slotProps={{ input: { 'aria-label': `${s.name} available at ${o.name}` } }} />
                          {!s.is_quote_based && (editing ? (
                            <TextField size="small" type="number" autoFocus value={priceEdit.value} onChange={(e) => setPriceEdit({ ...priceEdit, value: e.target.value })} onBlur={() => setCell.mutate({ outletId: o.id, serviceId: s.id, patch: { price_cents: priceEdit.value === '' ? null : Math.round(Number(priceEdit.value) * 100) } })} onKeyDown={(e) => { if (e.key === 'Enter') (e.target as HTMLInputElement).blur(); if (e.key === 'Escape') setPriceEdit(null); }} sx={{ width: 96 }} slotProps={{ htmlInput: { 'aria-label': `${s.name} price at ${o.name}` } }} />
                          ) : (
                            <Button size="small" variant="text" disabled={!manage} onClick={() => setPriceEdit({ outletId: o.id, serviceId: s.id, value: c?.price_cents != null ? String(c.price_cents / 100) : '' })} sx={{ minWidth: 0, px: 1, color: c?.price_cents != null ? tk.primary : tk.onSurfaceVariant, fontWeight: c?.price_cents != null ? 700 : 500 }}>
                              {c?.price_cents != null ? rands(c.price_cents) : 'inherit'}
                            </Button>
                          ))}
                          {!(c?.is_available ?? true) && <StatusChip tone="neutral" label="Off" sx={{ height: 22, fontSize: 11 }} />}
                        </Box>
                      </TableCell>
                    );
                  })}
                </TableRow>
              ))}
            </TableBody>
          </Table>
        </Box>
      </SectionCard>
      <ServiceDialog service={edit} open={open} onClose={() => setOpen(false)} />
      <Toast toast={toast.toast} onClose={toast.close} />
    </>
  );
}
