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
import IconButton from '@mui/material/IconButton';
import Tooltip from '@mui/material/Tooltip';
import Checkbox from '@mui/material/Checkbox';
import FormControlLabel from '@mui/material/FormControlLabel';
import Alert from '@mui/material/Alert';
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
import PhoneField from '@/components/ui/PhoneField';
import { useApi, useAuth } from '@/lib/auth/AuthProvider';
import { useToast } from '@/lib/hooks';
import { can, roleLabel } from '@/lib/rbac';
import { copyText } from '@/lib/clipboard';
import { fonts, tk } from '@/theme/tokens';
import { fmtAgo, initials } from '@/lib/format';
import { formatPhone } from '@/lib/phone';
import { ADMIN_ROLES, type CreateStaffResult, type Profile, type StaffUser, type UserRole } from '@/lib/types';

const STAFF_ROLES: UserRole[] = ['technician', 'supervisor', 'manager', 'finance', 'admin'];

const FIRST_SIGN_IN_NOTE = "They'll be asked to choose a new password the first time they sign in to the Sparkling Staff app or this dashboard.";

/* ------------------------------------------------------------------ credentials panel */

interface Credentials {
  profile: Profile;
  temporary_password: string;
  invite_link?: string | null;
}

/** Copies `text`; the button flips to a check mark for a moment. */
function CopyButton({ text, label, size = 'small' }: { text: string; label: string; size?: 'small' | 'medium' }) {
  const [done, setDone] = React.useState(false);
  return (
    <Tooltip title={done ? 'Copied' : label}>
      <IconButton
        size={size}
        aria-label={label}
        onClick={() => void copyText(text).then((ok) => { if (ok) { setDone(true); setTimeout(() => setDone(false), 1600); } })}
      >
        <MSymbol name={done ? 'check' : 'content_copy'} size={18} />
      </IconButton>
    </Tooltip>
  );
}

function CredentialRow({ label, value, mono = true, small = false }: { label: string; value: string; mono?: boolean; small?: boolean }) {
  return (
    <Box>
      <Typography variant="overline" color="text.secondary" component="div">{label}</Typography>
      <Box sx={{ display: 'flex', alignItems: 'center', gap: 1, px: 1.5, py: 1, borderRadius: '14px', bgcolor: tk.surfaceContainerHigh, minWidth: 0 }}>
        <Typography component="code" sx={{ fontFamily: mono ? fonts.mono : fonts.sans, fontSize: small ? 12.5 : mono ? 15 : 14, fontWeight: 600, flex: 1, minWidth: 0, overflowWrap: 'anywhere', userSelect: 'all' }}>{value}</Typography>
        <CopyButton text={value} label={`Copy ${label.toLowerCase()}`} />
      </Box>
    </Box>
  );
}

/** Shown once after "Add staff member" or "Reset password" — the temporary password is not retrievable later. */
function CredentialsPanel({ creds, title }: { creds: Credentials; title: string }) {
  const email = creds.profile.email ?? '';
  const dashboardUser = ADMIN_ROLES.includes(creds.profile.role);
  const shareText = [
    `Hi ${creds.profile.full_name.split(' ')[0]}, here are your Sparkling sign-in details.`,
    `E-mail: ${email}`,
    `Temporary password: ${creds.temporary_password}`,
    dashboardUser ? 'Sign in to the Sparkling Staff app or the admin dashboard with these details.' : 'Sign in to the Sparkling Staff app with these details.',
    "You'll be asked to choose a new password the first time you sign in.",
    creds.invite_link ? `Prefer to set it yourself first? ${creds.invite_link}` : null,
  ].filter(Boolean).join('\n');
  const [copiedAll, setCopiedAll] = React.useState(false);
  return (
    <Box sx={{ display: 'flex', flexDirection: 'column', gap: 2 }} data-testid="credentials-panel">
      <Alert severity="warning" icon={<MSymbol name="visibility" size={20} />} sx={{ borderRadius: '14px' }}>
        {title} — this temporary password is shown <strong>once</strong>. Hand it over now; you can issue a new one later with <strong>Reset password</strong>.
      </Alert>
      <CredentialRow label="E-mail" value={email} mono={false} />
      <CredentialRow label="Temporary password" value={creds.temporary_password} />
      {creds.invite_link && <CredentialRow label="Reset link (optional)" value={creds.invite_link} small />}
      <Button
        variant="outlined"
        startIcon={<MSymbol name={copiedAll ? 'check' : 'forward_to_inbox'} size={20} />}
        onClick={() => void copyText(shareText).then((ok) => { if (ok) { setCopiedAll(true); setTimeout(() => setCopiedAll(false), 1600); } })}
        aria-label="Copy sign-in details to send to the staff member"
      >
        {copiedAll ? 'Copied' : 'Send these details'}
      </Button>
      <Typography variant="body2" color="text.secondary">{FIRST_SIGN_IN_NOTE}</Typography>
    </Box>
  );
}

/* ------------------------------------------------------------------ add staff member */

function AddStaffDialog({ open, onClose }: { open: boolean; onClose: () => void }) {
  return (
    <Dialog open={open} onClose={onClose} fullWidth maxWidth="xs" aria-labelledby="add-staff-title">
      {open && <AddStaffForm onClose={onClose} />}
    </Dialog>
  );
}

function AddStaffForm({ onClose }: { onClose: () => void }) {
  const api = useApi();
  const qc = useQueryClient();
  const toast = useToast();
  const outlets = useQuery({ queryKey: ['outlets'], queryFn: () => api.listOutlets() });
  // `phone` is E.164 or '' (PhoneField); `phoneValid` gates the submit when a number was typed.
  const [form, setForm] = React.useState({ full_name: '', email: '', phone: '', phoneValid: false, role: 'technician' as UserRole, outlet_ids: [] as string[], link: false });
  const [result, setResult] = React.useState<CreateStaffResult | null>(null);
  const m = useMutation({
    mutationFn: () => api.inviteUser({ email: form.email.trim(), full_name: form.full_name.trim(), phone: form.phone || null, role: form.role, outlet_ids: form.outlet_ids, invite: form.link ? 'link' : 'password' }),
    onSuccess: (r) => { setResult(r); void qc.invalidateQueries({ queryKey: ['users'] }); },
    onError: (e) => toast.error(e),
  });
  const ready = Boolean(form.email.trim() && form.full_name.trim()) && (form.phone === '' || form.phoneValid);
  return (
    <>
      <DialogTitle id="add-staff-title">{result ? 'Credentials' : 'Add staff member'}</DialogTitle>
      <DialogContent sx={{ display: 'flex', flexDirection: 'column', gap: 1.75, pt: '8px !important' }}>
        {result ? (
          <CredentialsPanel creds={result} title={`${result.profile.full_name} added as ${roleLabel[result.profile.role].toLowerCase()}`} />
        ) : (
          <>
            <TextField label="Full name" value={form.full_name} onChange={(e) => setForm({ ...form, full_name: e.target.value })} size="small" required autoFocus />
            <TextField label="E-mail" type="email" value={form.email} onChange={(e) => setForm({ ...form, email: e.target.value })} size="small" required helperText="Creates the Firebase Auth account with a temporary password." />
            <PhoneField label="Mobile number" value={form.phone} onChange={(e164, meta) => setForm({ ...form, phone: e164, phoneValid: meta.valid })} size="small" helperText="Optional · any country" />
            <TextField select label="Role" value={form.role} onChange={(e) => setForm({ ...form, role: e.target.value as UserRole })} size="small" helperText={ADMIN_ROLES.includes(form.role) ? 'Can sign in to the Staff app and this dashboard.' : 'Signs in to the Staff app only.'}>
              {STAFF_ROLES.map((r) => <MenuItem key={r} value={r}>{roleLabel[r]}</MenuItem>)}
            </TextField>
            <TextField select label="Outlets" value={form.outlet_ids} onChange={(e) => setForm({ ...form, outlet_ids: (typeof e.target.value === 'string' ? e.target.value.split(',') : e.target.value) as string[] })} size="small" slotProps={{ select: { multiple: true, renderValue: (v) => (v as string[]).map((id) => outlets.data?.find((o) => o.id === id)?.name.replace('Sparkling ', '')).join(', ') } }}>
              {(outlets.data ?? []).map((o) => <MenuItem key={o.id} value={o.id}>{o.name}</MenuItem>)}
            </TextField>
            <FormControlLabel control={<Checkbox checked={form.link} onChange={(e) => setForm({ ...form, link: e.target.checked })} />} label={<Typography variant="body2">Also generate a reset link</Typography>} />
          </>
        )}
      </DialogContent>
      <DialogActions sx={{ p: 2.5, pt: 0 }}>
        {result ? (
          <Button variant="contained" color="secondary" onClick={onClose}>Done</Button>
        ) : (
          <>
            <Button onClick={onClose}>Cancel</Button>
            <Button variant="contained" color="secondary" disabled={m.isPending || !ready} onClick={() => m.mutate()} startIcon={<MSymbol name="person_add" size={20} />}>Create account</Button>
          </>
        )}
      </DialogActions>
      <Toast toast={toast.toast} onClose={toast.close} />
    </>
  );
}

/* ------------------------------------------------------------------ edit */

function EditUserDialog({ user, open, onClose, onResetPassword }: { user: StaffUser | null; open: boolean; onClose: () => void; onResetPassword: (u: StaffUser) => void }) {
  return (
    <Dialog open={open} onClose={onClose} fullWidth maxWidth="xs" aria-labelledby="user-title">
      {open && user && <EditUserForm user={user} onClose={onClose} onResetPassword={() => onResetPassword(user)} />}
    </Dialog>
  );
}

function EditUserForm({ user, onClose, onResetPassword }: { user: StaffUser; onClose: () => void; onResetPassword: () => void }) {
  const api = useApi();
  const qc = useQueryClient();
  const toast = useToast();
  const outlets = useQuery({ queryKey: ['outlets'], queryFn: () => api.listOutlets() });
  const [form, setForm] = React.useState(() => ({ role: user.role, outlet_ids: user.outlet_ids, is_active: user.is_active, phone: user.phone ?? '', phoneValid: Boolean(user.phone) }));
  const phoneChanged = form.phone !== (user.phone ?? '');
  const m = useMutation({
    mutationFn: () => api.updateUser(user.id, { role: form.role, outlet_ids: form.outlet_ids, is_active: form.is_active, ...(phoneChanged ? { phone: form.phone || null } : {}) }),
    onSuccess: (u) => { toast.success(`${u.full_name} updated${!form.is_active ? ' · refresh tokens revoked' : ''}`); void qc.invalidateQueries({ queryKey: ['users'] }); onClose(); },
    onError: (e) => toast.error(e),
  });
  return (
    <>
      <DialogTitle id="user-title">Edit {user.full_name}</DialogTitle>
      <DialogContent sx={{ display: 'flex', flexDirection: 'column', gap: 1.75, pt: '8px !important' }}>
        <Typography variant="body2" color="text.secondary">{user.email ?? '—'}</Typography>
        {user.must_change_password && <Alert severity="info" sx={{ borderRadius: '14px' }}>Has a temporary password — must choose a new one on the next sign-in.</Alert>}
        <PhoneField label="Mobile number" value={form.phone} onChange={(e164, meta) => setForm({ ...form, phone: e164, phoneValid: meta.valid })} size="small" helperText={user.phone ? `On file: ${formatPhone(user.phone)}` : 'Optional · any country'} />
        <TextField select label="Role" value={form.role} onChange={(e) => setForm({ ...form, role: e.target.value as UserRole })} size="small">
          {STAFF_ROLES.map((r) => <MenuItem key={r} value={r}>{roleLabel[r]}</MenuItem>)}
        </TextField>
        <TextField select label="Outlets" value={form.outlet_ids} onChange={(e) => setForm({ ...form, outlet_ids: (typeof e.target.value === 'string' ? e.target.value.split(',') : e.target.value) as string[] })} size="small" slotProps={{ select: { multiple: true, renderValue: (v) => (v as string[]).map((id) => outlets.data?.find((o) => o.id === id)?.name.replace('Sparkling ', '')).join(', ') } }}>
          {(outlets.data ?? []).map((o) => <MenuItem key={o.id} value={o.id}>{o.name}</MenuItem>)}
        </TextField>
        <FormControlLabel control={<M3Switch checked={form.is_active} onChange={(e) => setForm({ ...form, is_active: e.target.checked })} />} label={form.is_active ? 'Active' : 'Deactivated — sign-in revoked (SEC-014)'} />
        <Button variant="outlined" onClick={onResetPassword} startIcon={<MSymbol name="lock_reset" size={20} />} sx={{ alignSelf: 'flex-start' }}>Reset password</Button>
      </DialogContent>
      <DialogActions sx={{ p: 2.5, pt: 0 }}>
        <Button onClick={onClose}>Cancel</Button>
        <Button variant="contained" color="secondary" disabled={m.isPending || (form.phone !== '' && !form.phoneValid)} onClick={() => m.mutate()}>Save</Button>
      </DialogActions>
      <Toast toast={toast.toast} onClose={toast.close} />
    </>
  );
}

/* ------------------------------------------------------------------ reset password */

function ResetPasswordDialog({ user, onClose }: { user: StaffUser | null; onClose: () => void }) {
  return (
    <Dialog open={Boolean(user)} onClose={onClose} fullWidth maxWidth="xs" aria-labelledby="reset-password-title">
      {user && <ResetPasswordBody user={user} onClose={onClose} />}
    </Dialog>
  );
}

function ResetPasswordBody({ user, onClose }: { user: StaffUser; onClose: () => void }) {
  const api = useApi();
  const qc = useQueryClient();
  const toast = useToast();
  const [creds, setCreds] = React.useState<Credentials | null>(null);
  const m = useMutation({
    mutationFn: () => api.resetUserPassword(user.id),
    onSuccess: (r) => { setCreds(r); void qc.invalidateQueries({ queryKey: ['users'] }); },
    onError: (e) => toast.error(e),
  });
  return (
    <>
      <DialogTitle id="reset-password-title">{creds ? 'Credentials' : `Reset password for ${user.full_name}?`}</DialogTitle>
      <DialogContent sx={{ display: 'flex', flexDirection: 'column', gap: 1.5, pt: '8px !important' }}>
        {creds ? (
          <CredentialsPanel creds={creds} title={`Password reset for ${user.full_name}`} />
        ) : (
          <>
            <Typography variant="body2" color="text.secondary">
              A new temporary password is issued for <strong>{user.email ?? user.full_name}</strong>. Their current password stops working immediately and every signed-in device is signed out.
            </Typography>
            <Typography variant="body2" color="text.secondary">{FIRST_SIGN_IN_NOTE}</Typography>
          </>
        )}
      </DialogContent>
      <DialogActions sx={{ p: 2.5, pt: 0 }}>
        {creds ? (
          <Button variant="contained" color="secondary" onClick={onClose}>Done</Button>
        ) : (
          <>
            <Button onClick={onClose} disabled={m.isPending}>Cancel</Button>
            <Button variant="contained" color="secondary" disabled={m.isPending} onClick={() => m.mutate()} startIcon={<MSymbol name="lock_reset" size={20} />}>Reset password</Button>
          </>
        )}
      </DialogActions>
      <Toast toast={toast.toast} onClose={toast.close} />
    </>
  );
}

/* ------------------------------------------------------------------ page */

export default function StaffPage() {
  const api = useApi();
  const { role } = useAuth();
  const q = useQuery({ queryKey: ['users'], queryFn: () => api.listUsers() });
  const [edit, setEdit] = React.useState<StaffUser | null>(null);
  const [editOpen, setEditOpen] = React.useState(false);
  const [addOpen, setAddOpen] = React.useState(false);
  const [reset, setReset] = React.useState<StaffUser | null>(null);
  const manage = can(role, 'user:manage');
  const openEdit = (u: StaffUser) => { setEdit(u); setEditOpen(true); };
  const columns: GridColDef<StaffUser>[] = [
    { field: 'full_name', headerName: 'Name', flex: 1.4, minWidth: 200, renderCell: (p) => (
      <Box sx={{ display: 'flex', alignItems: 'center', gap: 1.25, minWidth: 0, width: '100%' }}>
        <Avatar sx={{ width: 34, height: 34, fontSize: 13, fontWeight: 700, bgcolor: tk.primaryContainer, color: tk.onPrimaryContainer, flexShrink: 0 }}>{initials(p.row.full_name)}</Avatar>
        <Box sx={{ minWidth: 0 }}>
          <Typography variant="h6" component="span" noWrap sx={{ display: 'block', lineHeight: 1.3 }} title={p.row.full_name}>{p.row.full_name}</Typography>
          <Typography variant="caption" component="span" noWrap color="text.secondary" sx={{ display: 'block', lineHeight: 1.3 }} title={[p.row.email, formatPhone(p.row.phone)].filter(Boolean).join(' · ') || undefined}>{p.row.email ?? '—'}{p.row.phone ? ` · ${formatPhone(p.row.phone)}` : ''}</Typography>
        </Box>
      </Box>
    ) },
    { field: 'role', headerName: 'Role', flex: 0.8, minWidth: 120, renderCell: (p) => <StatusChip tone={p.row.role === 'admin' ? 'primary' : p.row.role === 'manager' ? 'secondary' : 'neutral'} label={roleLabel[p.row.role]} /> },
    { field: 'outlet_names', headerName: 'Outlets', flex: 1.2, minWidth: 160, valueGetter: (_v, r) => r.outlet_names.join(', ') || '—' },
    { field: 'skills', headerName: 'Skills', flex: 1, minWidth: 140, sortable: false, renderCell: (p) => <Box sx={{ display: 'flex', gap: 0.5 }}>{p.row.skills.map((s) => <Chip key={s} size="small" label={s} sx={{ height: 22, fontSize: 11, bgcolor: tk.surfaceContainerHigh }} />)}</Box> },
    { field: 'last_seen_at', headerName: 'Last seen', flex: 0.8, minWidth: 110, renderCell: (p) => (p.row.last_seen_at ? fmtAgo(p.row.last_seen_at) : 'Never') },
    { field: 'is_active', headerName: 'Status', flex: 1.2, minWidth: 240, renderCell: (p) => (
      <Box sx={{ display: 'flex', gap: 0.5, alignItems: 'center', flexWrap: 'wrap' }}>
        <StatusChip tone={p.row.is_active ? 'success' : 'error'} label={p.row.is_active ? 'Active' : 'Inactive'} />
        {p.row.must_change_password && <StatusChip tone="warning" label="Must change password" icon={<MSymbol name="lock_reset" size={16} />} sx={{ height: 22, fontSize: 11, '& .MuiChip-icon': { color: 'inherit', ml: 0.75 } }} />}
      </Box>
    ) },
    { field: 'actions', headerName: '', width: 100, sortable: false, align: 'right', renderCell: (p) => manage ? (
      <Box sx={{ display: 'flex', gap: 0.25 }}>
        <Tooltip title="Reset password"><IconButton size="small" onClick={(e) => { e.stopPropagation(); setReset(p.row); }} aria-label={`Reset password for ${p.row.full_name}`}><MSymbol name="lock_reset" size={20} /></IconButton></Tooltip>
        <Tooltip title="Edit"><IconButton size="small" onClick={(e) => { e.stopPropagation(); openEdit(p.row); }} aria-label={`Edit ${p.row.full_name}`}><MSymbol name="edit" size={20} /></IconButton></Tooltip>
      </Box>
    ) : null },
  ];
  return (
    <>
      <PageHeader title="Staff" subtitle="Users, roles and outlet scope · performance & leaderboard" actions={manage ? <NavyPill icon="person_add" onClick={() => setAddOpen(true)}>Add staff member</NavyPill> : undefined} />
      <Tabs value={0} aria-label="Staff sections">
        <Tab label="Users" />
        <Tab label="Performance" component={Link} href="/staff/performance" />
      </Tabs>
      <SectionCard flush title="Team" subtitle={`${q.data?.length ?? 0} staff accounts · role changes set Firebase custom claims · new accounts get a temporary password`}>
        <Box sx={{ px: 1.5, pb: 1 }}>
          <AdminGrid<StaffUser> rows={q.data ?? []} columns={columns} loading={q.isLoading} getRowClassName={() => (manage ? 'row-clickable' : '')} onRowClick={(p) => manage && openEdit(p.row)} />
        </Box>
      </SectionCard>
      <AddStaffDialog open={addOpen} onClose={() => setAddOpen(false)} />
      <EditUserDialog user={edit} open={editOpen} onClose={() => setEditOpen(false)} onResetPassword={(u) => { setEditOpen(false); setReset(u); }} />
      <ResetPasswordDialog user={reset} onClose={() => setReset(null)} />
    </>
  );
}
