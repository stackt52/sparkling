'use client';
import * as React from 'react';
import Link from 'next/link';
import Box from '@mui/material/Box';
import Typography from '@mui/material/Typography';
import Button from '@mui/material/Button';
import Chip from '@mui/material/Chip';
import Dialog from '@mui/material/Dialog';
import DialogTitle from '@mui/material/DialogTitle';
import DialogContent from '@mui/material/DialogContent';
import DialogActions from '@mui/material/DialogActions';
import TextField from '@mui/material/TextField';
import MenuItem from '@mui/material/MenuItem';
import Tabs from '@mui/material/Tabs';
import Tab from '@mui/material/Tab';
import Avatar from '@mui/material/Avatar';
import FormControlLabel from '@mui/material/FormControlLabel';
import type { GridColDef } from '@mui/x-data-grid';
import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query';
import PageHeader from '@/components/layout/PageHeader';
import SectionCard from '@/components/ui/SectionCard';
import AdminGrid from '@/components/ui/AdminGrid';
import StatusChip from '@/components/ui/StatusChip';
import M3Switch from '@/components/ui/M3Switch';
import Toast from '@/components/ui/Toast';
import MSymbol from '@/components/MSymbol';
import { NavyPill } from '@/components/ui/Pills';
import { useApi, useAuth } from '@/lib/auth/AuthProvider';
import { useToast } from '@/lib/hooks';
import { can, roleLabel } from '@/lib/rbac';
import { tk } from '@/theme/tokens';
import { fmtAgo, initials } from '@/lib/format';
import type { StaffUser, UserRole } from '@/lib/types';

const STAFF_ROLES: UserRole[] = ['technician', 'supervisor', 'manager', 'finance', 'admin'];

function UserDialog({ user, open, onClose }: { user: StaffUser | null; open: boolean; onClose: () => void }) {
  return (
    <Dialog open={open} onClose={onClose} fullWidth maxWidth="xs" aria-labelledby="user-title">
      {open && <UserForm user={user} onClose={onClose} />}
    </Dialog>
  );
}

function UserForm({ user, onClose }: { user: StaffUser | null; onClose: () => void }) {
  const api = useApi();
  const qc = useQueryClient();
  const toast = useToast();
  const outlets = useQuery({ queryKey: ['outlets'], queryFn: () => api.listOutlets() });
  const [form, setForm] = React.useState(() =>
    user ? { full_name: user.full_name, email: user.email ?? '', role: user.role, outlet_ids: user.outlet_ids, is_active: user.is_active } : { full_name: '', email: '', role: 'technician' as UserRole, outlet_ids: [] as string[], is_active: true },
  );
  const m = useMutation({
    mutationFn: () => (user ? api.updateUser(user.id, { role: form.role, outlet_ids: form.outlet_ids, is_active: form.is_active }) : api.inviteUser({ email: form.email, full_name: form.full_name, role: form.role, outlet_ids: form.outlet_ids })),
    onSuccess: (u) => { toast.success(user ? `${u.full_name} updated${!form.is_active ? ' · refresh tokens revoked' : ''}` : `Invite sent to ${u.email}`); void qc.invalidateQueries({ queryKey: ['users'] }); onClose(); },
    onError: (e) => toast.error(e),
  });
  return (
    <>
      <DialogTitle id="user-title">{user ? `Edit ${user.full_name}` : 'Invite staff member'}</DialogTitle>
      <DialogContent sx={{ display: 'flex', flexDirection: 'column', gap: 1.75, pt: '8px !important' }}>
        {!user && <TextField label="Full name" value={form.full_name} onChange={(e) => setForm({ ...form, full_name: e.target.value })} size="small" required />}
        {!user && <TextField label="E-mail" type="email" value={form.email} onChange={(e) => setForm({ ...form, email: e.target.value })} size="small" required helperText="They sign in with Firebase Auth; the profile is claimed by e-mail on first sign-in." />}
        <TextField select label="Role" value={form.role} onChange={(e) => setForm({ ...form, role: e.target.value as UserRole })} size="small">
          {STAFF_ROLES.map((r) => <MenuItem key={r} value={r}>{roleLabel[r]}</MenuItem>)}
        </TextField>
        <TextField select label="Outlets" value={form.outlet_ids} onChange={(e) => setForm({ ...form, outlet_ids: (typeof e.target.value === 'string' ? e.target.value.split(',') : e.target.value) as string[] })} size="small" slotProps={{ select: { multiple: true, renderValue: (v) => (v as string[]).map((id) => outlets.data?.find((o) => o.id === id)?.name.replace('Sparkling ', '')).join(', ') } }}>
          {(outlets.data ?? []).map((o) => <MenuItem key={o.id} value={o.id}>{o.name}</MenuItem>)}
        </TextField>
        {user && (
          <FormControlLabel control={<M3Switch checked={form.is_active} onChange={(e) => setForm({ ...form, is_active: e.target.checked })} />} label={form.is_active ? 'Active' : 'Deactivated — sign-in revoked (SEC-014)'} />
        )}
      </DialogContent>
      <DialogActions sx={{ p: 2.5, pt: 0 }}>
        <Button onClick={onClose}>Cancel</Button>
        <Button variant="contained" color="secondary" disabled={m.isPending || (!user && (!form.email || !form.full_name))} onClick={() => m.mutate()}>{user ? 'Save' : 'Send invite'}</Button>
      </DialogActions>
      <Toast toast={toast.toast} onClose={toast.close} />
    </>
  );
}

export default function StaffPage() {
  const api = useApi();
  const { role } = useAuth();
  const q = useQuery({ queryKey: ['users'], queryFn: () => api.listUsers() });
  const [edit, setEdit] = React.useState<StaffUser | null>(null);
  const [open, setOpen] = React.useState(false);
  const manage = can(role, 'user:manage');
  const columns: GridColDef<StaffUser>[] = [
    { field: 'full_name', headerName: 'Name', flex: 1.4, minWidth: 200, renderCell: (p) => (
      <Box sx={{ display: 'flex', alignItems: 'center', gap: 1.25 }}>
        <Avatar sx={{ width: 34, height: 34, fontSize: 13, fontWeight: 700, bgcolor: tk.primaryContainer, color: tk.onPrimaryContainer }}>{initials(p.row.full_name)}</Avatar>
        <Box><Typography variant="h6" component="span" sx={{ display: 'block' }}>{p.row.full_name}</Typography><Typography variant="caption" color="text.secondary">{p.row.email}</Typography></Box>
      </Box>
    ) },
    { field: 'role', headerName: 'Role', flex: 0.8, minWidth: 120, renderCell: (p) => <StatusChip tone={p.row.role === 'admin' ? 'primary' : p.row.role === 'manager' ? 'secondary' : 'neutral'} label={roleLabel[p.row.role]} /> },
    { field: 'outlet_names', headerName: 'Outlets', flex: 1.2, minWidth: 160, valueGetter: (_v, r) => r.outlet_names.join(', ') || '—' },
    { field: 'skills', headerName: 'Skills', flex: 1, minWidth: 140, sortable: false, renderCell: (p) => <Box sx={{ display: 'flex', gap: 0.5 }}>{p.row.skills.map((s) => <Chip key={s} size="small" label={s} sx={{ height: 22, fontSize: 11, bgcolor: tk.surfaceContainerHigh }} />)}</Box> },
    { field: 'last_seen_at', headerName: 'Last seen', flex: 0.8, minWidth: 110, renderCell: (p) => (p.row.last_seen_at ? fmtAgo(p.row.last_seen_at) : 'Never') },
    { field: 'is_active', headerName: 'Status', flex: 0.7, minWidth: 100, renderCell: (p) => <StatusChip tone={p.row.is_active ? 'success' : 'error'} label={p.row.is_active ? 'Active' : 'Inactive'} /> },
    { field: 'actions', headerName: '', width: 70, sortable: false, align: 'right', renderCell: (p) => manage ? <Button size="small" variant="text" onClick={(e) => { e.stopPropagation(); setEdit(p.row); setOpen(true); }} aria-label={`Edit ${p.row.full_name}`}><MSymbol name="edit" size={20} /></Button> : null },
  ];
  return (
    <>
      <PageHeader title="Staff" subtitle="Users, roles and outlet scope · performance & leaderboard" actions={manage ? <NavyPill icon="person_add" onClick={() => { setEdit(null); setOpen(true); }}>Invite</NavyPill> : undefined} />
      <Tabs value={0} aria-label="Staff sections">
        <Tab label="Users" />
        <Tab label="Performance" component={Link} href="/staff/performance" />
      </Tabs>
      <SectionCard flush title="Team" subtitle={`${q.data?.length ?? 0} staff accounts · role changes set Firebase custom claims`}>
        <Box sx={{ px: 1.5, pb: 1 }}>
          <AdminGrid<StaffUser> rows={q.data ?? []} columns={columns} loading={q.isLoading} getRowClassName={() => (manage ? 'row-clickable' : '')} onRowClick={(p) => manage && (setEdit(p.row), setOpen(true))} />
        </Box>
      </SectionCard>
      <UserDialog user={edit} open={open} onClose={() => setOpen(false)} />
    </>
  );
}
