'use client';
import * as React from 'react';
import Box from '@mui/material/Box';
import Paper from '@mui/material/Paper';
import Typography from '@mui/material/Typography';
import Button from '@mui/material/Button';
import Dialog from '@mui/material/Dialog';
import DialogTitle from '@mui/material/DialogTitle';
import DialogContent from '@mui/material/DialogContent';
import DialogActions from '@mui/material/DialogActions';
import TextField from '@mui/material/TextField';
import FormControlLabel from '@mui/material/FormControlLabel';
import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query';
import PageHeader from '@/components/layout/PageHeader';
import ConfigTabs from '@/components/layout/ConfigTabs';
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
import type { OpeningHours, Outlet } from '@/lib/types';

const DAYS: (keyof OpeningHours)[] = ['mon', 'tue', 'wed', 'thu', 'fri', 'sat', 'sun'];
const DAY_LABEL: Record<keyof OpeningHours, string> = { mon: 'Mon', tue: 'Tue', wed: 'Wed', thu: 'Thu', fri: 'Fri', sat: 'Sat', sun: 'Sun' };
const blank: Partial<Outlet> = { code: '', name: '', address_line: '', city: '', province: 'Gauteng', phone: '', email: '', bay_count: 3, slot_minutes: 30, is_active: true, opening_hours: { mon: ['07:30', '17:30'], tue: ['07:30', '17:30'], wed: ['07:30', '17:30'], thu: ['07:30', '17:30'], fri: ['07:30', '17:30'], sat: ['08:00', '14:00'], sun: null } };

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
  const m = useMutation({
    mutationFn: () => (outlet ? api.updateOutlet(outlet.id, form) : api.createOutlet(form)),
    onSuccess: (o) => { toast.success(`${o.name} saved`); void qc.invalidateQueries({ queryKey: ['outlets'] }); onClose(); },
    onError: (e) => toast.error(e),
  });
  const hours = form.opening_hours ?? blank.opening_hours!;
  const setHours = (d: keyof OpeningHours, v: [string, string] | null) => setForm({ ...form, opening_hours: { ...hours, [d]: v } });
  return (
    <>
      <DialogTitle id="outlet-title">{outlet ? `Edit ${outlet.name}` : 'New outlet'}</DialogTitle>
      <DialogContent sx={{ display: 'grid', gridTemplateColumns: '1fr 1fr', gap: 1.5, pt: '8px !important' }}>
        <TextField label="Code" value={form.code ?? ''} onChange={(e) => setForm({ ...form, code: e.target.value.toUpperCase() })} size="small" required />
        <TextField label="Name" value={form.name ?? ''} onChange={(e) => setForm({ ...form, name: e.target.value })} size="small" required />
        <TextField label="Address" value={form.address_line ?? ''} onChange={(e) => setForm({ ...form, address_line: e.target.value })} size="small" sx={{ gridColumn: '1 / -1' }} />
        <TextField label="City" value={form.city ?? ''} onChange={(e) => setForm({ ...form, city: e.target.value })} size="small" />
        <TextField label="Province" value={form.province ?? ''} onChange={(e) => setForm({ ...form, province: e.target.value })} size="small" />
        <TextField label="Phone" value={form.phone ?? ''} onChange={(e) => setForm({ ...form, phone: e.target.value })} size="small" />
        <TextField label="E-mail" value={form.email ?? ''} onChange={(e) => setForm({ ...form, email: e.target.value })} size="small" />
        <TextField label="Bays" type="number" value={form.bay_count ?? 3} onChange={(e) => setForm({ ...form, bay_count: Number(e.target.value) })} size="small" slotProps={{ htmlInput: { min: 1 } }} />
        <TextField label="Slot minutes" type="number" value={form.slot_minutes ?? 30} onChange={(e) => setForm({ ...form, slot_minutes: Number(e.target.value) })} size="small" slotProps={{ htmlInput: { min: 10, max: 240 } }} />
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
        <Button variant="contained" color="secondary" disabled={m.isPending || !form.name || !form.code} onClick={() => m.mutate()}>Save</Button>
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
  return (
    <>
      <PageHeader title="Configuration" subtitle="Outlets · opening hours, bays and availability" actions={manage ? <NavyPill icon="add_business" onClick={() => { setEdit(null); setOpen(true); }}>New outlet</NavyPill> : undefined} />
      <ConfigTabs />
      {q.isLoading && <LoadingRows rows={3} height={140} />}
      <Box sx={{ display: 'grid', gridTemplateColumns: { xs: '1fr', md: 'repeat(2, 1fr)', xl: 'repeat(3, 1fr)' }, gap: '14px' }}>
        {(q.data ?? []).map((o) => (
          <Paper key={o.id} sx={{ p: 2.5, display: 'flex', flexDirection: 'column', gap: 1.25, opacity: o.is_active ? 1 : 0.7 }}>
            <Box sx={{ display: 'flex', alignItems: 'center', gap: 1.5 }}>
              <IconTile icon="storefront" tone={o.is_active ? 'primary' : 'neutral'} size={48} />
              <Box sx={{ flex: 1, minWidth: 0 }}>
                <Typography variant="h4">{o.name}</Typography>
                <Typography variant="body2" color="text.secondary">{o.address_line} · {o.city}</Typography>
              </Box>
              <StatusChip tone={o.is_active ? 'success' : 'neutral'} label={o.is_active ? 'Active' : 'Inactive'} />
            </Box>
            <Box sx={{ display: 'flex', gap: 2, flexWrap: 'wrap', color: tk.onSurfaceVariant, fontSize: 13.5 }}>
              <span><b style={{ color: tk.onSurface }}>{o.bay_count}</b> bays</span>
              <span><b style={{ color: tk.onSurface }}>{o.slot_minutes}</b> min slots</span>
              <span>★ <b style={{ color: tk.onSurface }}>{o.rating ?? '—'}</b></span>
              <span className="mono">{o.code}</span>
            </Box>
            <Box sx={{ display: 'grid', gridTemplateColumns: 'repeat(7, 1fr)', gap: 0.5 }}>
              {DAYS.map((d) => {
                const v = o.opening_hours[d];
                return (
                  <Box key={d} sx={{ textAlign: 'center', borderRadius: '10px', py: 0.5, bgcolor: v ? tk.surfaceContainer : 'transparent', color: v ? tk.onSurface : tk.onSurfaceVariant }}>
                    <Typography variant="caption" sx={{ fontWeight: 700, display: 'block' }}>{DAY_LABEL[d]}</Typography>
                    <Typography variant="caption" sx={{ fontSize: 10 }}>{v ? `${v[0]}–${v[1]}` : 'Closed'}</Typography>
                  </Box>
                );
              })}
            </Box>
            <Typography variant="caption" color="text.secondary">{o.phone} · {o.email}</Typography>
            {manage && <Button size="small" variant="outlined" onClick={() => { setEdit(o); setOpen(true); }} startIcon={<MSymbol name="edit" size={18} />} sx={{ alignSelf: 'flex-start' }}>Edit</Button>}
          </Paper>
        ))}
      </Box>
      <OutletDialog outlet={edit} open={open} onClose={() => setOpen(false)} />
    </>
  );
}
