'use client';
import * as React from 'react';
import { useSearchParams } from 'next/navigation';
import Box from '@mui/material/Box';
import Paper from '@mui/material/Paper';
import Typography from '@mui/material/Typography';
import Button from '@mui/material/Button';
import Chip from '@mui/material/Chip';
import Dialog from '@mui/material/Dialog';
import DialogTitle from '@mui/material/DialogTitle';
import DialogContent from '@mui/material/DialogContent';
import DialogActions from '@mui/material/DialogActions';
import TextField from '@mui/material/TextField';
import Drawer from '@mui/material/Drawer';
import IconButton from '@mui/material/IconButton';
import Avatar from '@mui/material/Avatar';
import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query';
import PageHeader from '@/components/layout/PageHeader';
import { LiveChip, OutletPill } from '@/components/ui/Pills';
import StatusChip from '@/components/ui/StatusChip';
import LevelBar from '@/components/ui/LevelBar';
import Tile from '@/components/ui/Tile';
import Toast from '@/components/ui/Toast';
import MSymbol from '@/components/MSymbol';
import { LoadingRows } from '@/components/ui/States';
import { useApi, useAuth } from '@/lib/auth/AuthProvider';
import { useFilters } from '@/lib/filters';
import { useLive, useNow, useToast } from '@/lib/hooks';
import { can } from '@/lib/rbac';
import { fonts, tk } from '@/theme/tokens';
import { fmtDateTime, fmtTime, initials, statusLabel } from '@/lib/format';
import type { WorkOrder, WorkStatus } from '@/lib/types';

const COLUMNS: WorkStatus[] = ['queued', 'assigned', 'in_progress', 'blocked', 'completed', 'verified'];
const priorityTone = { 1: 'error', 2: 'gold', 3: 'neutral' } as const;

function WoCard({ w, onOpen, now }: { w: WorkOrder; onOpen: () => void; now: number }) {
  const overdue = w.due_at && new Date(w.due_at).getTime() < now && !['completed', 'verified', 'cancelled'].includes(w.status);
  return (
    <Paper
      component="button"
      type="button"
      onClick={onOpen}
      aria-label={`${w.ref} ${w.service.name} ${statusLabel(w.status)}`}
      sx={{ textAlign: 'left', p: 1.75, display: 'flex', flexDirection: 'column', gap: 1, cursor: 'pointer', width: '100%', fontFamily: 'inherit', borderRadius: '20px', ...(w.status === 'blocked' && { border: `2px solid color-mix(in srgb, ${tk.error} 55%, transparent)` }), ...(overdue && w.status !== 'blocked' && { border: `2px solid ${tk.gold}` }), '&:hover': { bgcolor: tk.surfaceContainer } }}
    >
      <Box sx={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', gap: 1 }}>
        <span className="mono" style={{ fontWeight: 700, color: tk.primary, fontSize: 13.5 }}>{w.ref}</span>
        <StatusChip tone={priorityTone[w.priority]} label={`P${w.priority}`} sx={{ height: 22, fontSize: 11 }} />
      </Box>
      <Typography variant="h5">{w.service.name}</Typography>
      <Typography variant="body2" color="text.secondary"><span className="mono">{w.vehicle.registration_no}</span>{w.bay ? ` · ${w.bay}` : ''} · {w.customer_name.split(' ')[0]}</Typography>
      {w.step_count > 0 && (
        <Box sx={{ display: 'flex', alignItems: 'center', gap: 1 }}>
          <LevelBar value={w.steps_done} max={w.step_count} tone={w.status === 'blocked' ? 'error' : 'primary'} height={6} label={`${w.steps_done} of ${w.step_count} steps`} />
          <Typography variant="caption" color="text.secondary" sx={{ whiteSpace: 'nowrap' }}>{w.steps_done}/{w.step_count}</Typography>
        </Box>
      )}
      {w.blocked_reason && <Typography variant="body2" sx={{ color: tk.error }}>{w.blocked_reason}</Typography>}
      <Box sx={{ display: 'flex', alignItems: 'center', gap: 1, mt: 0.25 }}>
        {w.assignee_name ? (
          <>
            <Avatar sx={{ width: 24, height: 24, fontSize: 10, bgcolor: tk.primaryContainer, color: tk.onPrimaryContainer, fontWeight: 700 }}>{initials(w.assignee_name)}</Avatar>
            <Typography variant="caption">{w.assignee_name}</Typography>
          </>
        ) : (
          <Typography variant="caption" color="text.secondary">Unassigned</Typography>
        )}
        <Box sx={{ flex: 1 }} />
        {w.eta_at && <Typography variant="caption" color={overdue ? tk.onWarningContainer : 'text.secondary'}>{overdue ? 'over SLA' : `ETA ${fmtTime(w.eta_at)}`}</Typography>}
      </Box>
    </Paper>
  );
}

function AssignDialog({ w, onClose }: { w: WorkOrder | null; onClose: () => void }) {
  return (
    <Dialog open={Boolean(w)} onClose={onClose} aria-labelledby="assign-title" fullWidth maxWidth="xs">
      {w && <AssignForm w={w} onClose={onClose} />}
    </Dialog>
  );
}

function AssignForm({ w, onClose }: { w: WorkOrder; onClose: () => void }) {
  const api = useApi();
  const qc = useQueryClient();
  const toast = useToast();
  const [assignee, setAssignee] = React.useState(w.assignee_id ?? '');
  const [reason, setReason] = React.useState('');
  const team = useQuery({ queryKey: ['team', w.outlet.id], queryFn: () => api.team({ outlet_id: w.outlet.id }) });
  const m = useMutation({
    mutationFn: () => api.assignTask(w.task_id, { assignee_id: assignee, reason: reason || undefined }),
    onSuccess: (res) => { toast.success(`${res.ref} assigned to ${res.assignee_name}`); void qc.invalidateQueries({ queryKey: ['work-orders'] }); onClose(); },
    onError: (e) => toast.error(e),
  });
  return (
    <>
      <DialogTitle id="assign-title">{w.assignee_id ? 'Reassign' : 'Assign'} {w.ref}</DialogTitle>
      <DialogContent sx={{ display: 'flex', flexDirection: 'column', gap: 1.25 }}>
        {team.isLoading && <LoadingRows rows={3} height={56} />}
        {(team.data ?? []).map((t) => {
          const full = t.active_tasks >= t.capacity;
          const selected = assignee === t.id;
          return (
            <Tile key={t.id} role="radio" aria-checked={selected} tabIndex={0} interactive onClick={() => !full && setAssignee(t.id)} onKeyDown={(e) => { if ((e.key === 'Enter' || e.key === ' ') && !full) { e.preventDefault(); setAssignee(t.id); } }} tone={selected ? 'primary' : 'default'} sx={{ opacity: full ? 0.55 : 1, border: selected ? `2px solid ${tk.primary}` : '2px solid transparent' }}>
              <Avatar sx={{ bgcolor: tk.secondaryContainer, color: tk.onSecondaryContainer, fontWeight: 700, fontSize: 13 }}>{initials(t.name)}</Avatar>
              <Box sx={{ flex: 1 }}>
                <Typography variant="h6">{t.name}</Typography>
                <Typography variant="caption" color="text.secondary">{full ? 'At capacity' : t.availability === 'available' ? 'Available' : t.availability} · {t.active_tasks}/{t.capacity} tasks</Typography>
              </Box>
              <Box sx={{ display: 'flex', gap: 0.5 }}>{t.skills.slice(0, 2).map((s) => <Chip key={s} size="small" label={s} sx={{ height: 20, fontSize: 10.5, bgcolor: 'rgba(0,0,0,0.06)', color: 'inherit' }} />)}</Box>
              <MSymbol name={selected ? 'radio_button_checked' : 'radio_button_unchecked'} filled={selected} size={22} />
            </Tile>
          );
        })}
        <TextField label="Reason (optional)" value={reason} onChange={(e) => setReason(e.target.value)} size="small" />
        <Typography variant="caption" color="text.secondary">Actor, time and reason are recorded in the task audit trail (STF-021/024).</Typography>
      </DialogContent>
      <DialogActions sx={{ p: 2.5, pt: 0 }}>
        <Button onClick={onClose}>Cancel</Button>
        <Button variant="contained" color="secondary" disabled={!assignee || m.isPending || assignee === w.assignee_id} onClick={() => m.mutate()}>Assign</Button>
      </DialogActions>
      <Toast toast={toast.toast} onClose={toast.close} />
    </>
  );
}

const NEXT: Partial<Record<WorkStatus, { to: WorkStatus; label: string; icon: string; needsReason?: boolean }[]>> = {
  assigned: [{ to: 'in_progress', label: 'Start', icon: 'play_arrow' }],
  in_progress: [{ to: 'blocked', label: 'Mark blocked', icon: 'block', needsReason: true }, { to: 'completed', label: 'Complete', icon: 'task_alt' }],
  blocked: [{ to: 'in_progress', label: 'Resume', icon: 'play_arrow' }],
  completed: [{ to: 'verified', label: 'Verify', icon: 'verified' }],
};

function WoDrawer({ w, onClose, onAssign }: { w: WorkOrder | null; onClose: () => void; onAssign: () => void }) {
  const api = useApi();
  const { role } = useAuth();
  const qc = useQueryClient();
  const toast = useToast();
  const [reasonFor, setReasonFor] = React.useState<WorkStatus | null>(null);
  const [reason, setReason] = React.useState('');
  const m = useMutation({
    mutationFn: (body: { to: WorkStatus; reason?: string }) => api.transitionTask(w!.task_id, body),
    onSuccess: (res) => { toast.success(`${res.ref} → ${statusLabel(res.status)}`); void qc.invalidateQueries({ queryKey: ['work-orders'] }); setReasonFor(null); setReason(''); },
    onError: (e) => toast.error(e),
  });
  const canAct = can(role, 'task:transition');
  return (
    <Drawer anchor="right" open={Boolean(w)} onClose={onClose} slotProps={{ paper: { sx: { width: { xs: '100%', sm: 460 }, borderRadius: { xs: 0, sm: '28px 0 0 28px' }, p: 3 } } }}>
      {w && (
        <>
          <Box sx={{ display: 'flex', alignItems: 'center', justifyContent: 'space-between' }}>
            <Typography variant="overline" color="text.secondary">Work order</Typography>
            <IconButton aria-label="Close" onClick={onClose}><MSymbol name="close" /></IconButton>
          </Box>
          <Box sx={{ display: 'flex', alignItems: 'center', gap: 1.5 }}>
            <Typography variant="h2" className="mono" sx={{ color: tk.primary }}>{w.ref}</Typography>
            <StatusChip status={w.status} />
            <StatusChip tone={priorityTone[w.priority]} label={`P${w.priority}`} />
          </Box>
          <Typography color="text.secondary">{w.service.name} · {w.vehicle.make} {w.vehicle.model} · <span className="mono">{w.vehicle.registration_no}</span></Typography>
          <Tile sx={{ mt: 2, flexDirection: 'column', alignItems: 'stretch', gap: 0.5 }}>
            <Typography variant="body2">{w.outlet.name}{w.bay ? ` · ${w.bay}` : ''} · {w.customer_name}</Typography>
            <Typography variant="body2">{w.booking_ref ? `Booking ${w.booking_ref}` : w.quotation_ref ? `Quotation ${w.quotation_ref}` : ''}</Typography>
            <Typography variant="body2">Assignee: <b>{w.assignee_name ?? 'unassigned'}</b>{w.eta_at ? ` · ETA ${fmtTime(w.eta_at)}` : ''}{w.due_at ? ` · due ${fmtTime(w.due_at)}` : ''}</Typography>
            <Box sx={{ display: 'flex', alignItems: 'center', gap: 1, mt: 0.5 }}>
              <LevelBar value={w.steps_done} max={w.step_count} tone={w.status === 'blocked' ? 'error' : 'primary'} height={8} label="Checklist progress" />
              <Typography variant="caption">{w.steps_done}/{w.step_count} steps</Typography>
            </Box>
            {w.blocked_reason && <Typography variant="body2" sx={{ color: tk.error, fontWeight: 600 }}>{w.blocked_reason}</Typography>}
          </Tile>
          {can(role, 'task:assign') && (
            <Button variant="outlined" sx={{ mt: 2 }} onClick={onAssign} startIcon={<MSymbol name="assignment_ind" size={20} />}>{w.assignee_id ? 'Reassign' : 'Assign'}</Button>
          )}
          {canAct && (NEXT[w.status] ?? []).length > 0 && (
            <Box sx={{ display: 'flex', gap: 1, mt: 1.5, flexWrap: 'wrap' }}>
              {(NEXT[w.status] ?? []).map((n) => (
                <Button key={n.to} variant={n.to === 'blocked' ? 'outlined' : 'contained'} color={n.to === 'blocked' ? 'error' : 'secondary'} size="small" startIcon={<MSymbol name={n.icon} size={18} />} onClick={() => (n.needsReason || (n.to === 'verified' && w.steps_done < w.step_count) ? setReasonFor(n.to) : m.mutate({ to: n.to }))} disabled={m.isPending}>
                  {n.label}
                </Button>
              ))}
            </Box>
          )}
          {reasonFor && (
            <Box sx={{ mt: 1.5, display: 'flex', flexDirection: 'column', gap: 1 }}>
              <TextField label={reasonFor === 'verified' ? 'Override reason (required steps incomplete)' : 'Reason'} value={reason} onChange={(e) => setReason(e.target.value)} size="small" autoFocus multiline />
              <Box sx={{ display: 'flex', gap: 1 }}>
                <Button size="small" onClick={() => setReasonFor(null)}>Cancel</Button>
                <Button size="small" variant="contained" color="secondary" disabled={!reason.trim()} onClick={() => m.mutate({ to: reasonFor, reason })}>Confirm</Button>
              </Box>
            </Box>
          )}
          <Typography variant="h4" sx={{ mt: 3, mb: 1 }}>Audit trail</Typography>
          <Box component="ol" sx={{ listStyle: 'none', m: 0, p: 0, display: 'flex', flexDirection: 'column', gap: 1 }}>
            {w.events.length === 0 && <Typography variant="body2" color="text.secondary">No events yet.</Typography>}
            {[...w.events].reverse().map((e) => (
              <Box component="li" key={e.id} sx={{ display: 'flex', gap: 1.5 }}>
                <MSymbol name={e.event === 'assigned' ? 'assignment_ind' : 'swap_horiz'} size={20} style={{ color: tk.onSurfaceVariant, marginTop: 2 }} />
                <Box>
                  <Typography variant="body2"><b>{e.actor_name}</b> {e.event === 'assigned' ? 'assigned' : `moved ${statusLabel(e.from_status ?? '')} → ${statusLabel(e.to_status ?? '')}`}</Typography>
                  <Typography variant="caption" color="text.secondary">{fmtDateTime(e.created_at)}{e.reason ? ` · ${e.reason}` : ''}</Typography>
                </Box>
              </Box>
            ))}
          </Box>
        </>
      )}
      <Toast toast={toast.toast} onClose={toast.close} />
    </Drawer>
  );
}

export default function WorkOrdersPage() {
  const api = useApi();
  const { outletId } = useFilters();
  const params = useSearchParams();
  const { updatedAt, mode } = useLive(['work-orders']);
  const now = useNow();
  const [focusId, setFocusId] = React.useState<string | null>(params.get('focus'));
  const [assigning, setAssigning] = React.useState(false);
  const [status, setStatus] = React.useState<WorkStatus | 'all'>('all');
  const q = useQuery({ queryKey: ['work-orders', outletId], queryFn: () => api.listWorkOrders({ outlet_id: outletId }) });
  const rows = q.data ?? [];
  const focus = rows.find((w) => w.id === focusId) ?? null;
  const visible = status === 'all' ? COLUMNS : [status];
  return (
    <>
      <PageHeader title="Work orders" subtitle={<LiveChip updatedAt={updatedAt} mode={mode} />} actions={<OutletPill />} />
      <Box sx={{ display: 'flex', gap: 1, flexWrap: 'wrap' }}>
        <Chip label="All" clickable onClick={() => setStatus('all')} sx={{ bgcolor: status === 'all' ? tk.secondary : tk.surfaceContainerHigh, color: status === 'all' ? tk.onSecondary : tk.onSurface }} aria-pressed={status === 'all'} />
        {COLUMNS.map((s) => (
          <Chip key={s} label={`${statusLabel(s)} · ${rows.filter((w) => w.status === s).length}`} clickable onClick={() => setStatus(s)} sx={{ bgcolor: status === s ? tk.secondary : tk.surfaceContainerHigh, color: status === s ? tk.onSecondary : tk.onSurface }} aria-pressed={status === s} />
        ))}
      </Box>
      <Box sx={{ display: 'grid', gridTemplateColumns: `repeat(${visible.length}, minmax(220px, 1fr))`, gap: '14px', overflowX: 'auto', pb: 1 }}>
        {visible.map((col) => {
          const items = rows.filter((w) => w.status === col);
          return (
            <Box key={col} component="section" aria-label={statusLabel(col)} sx={{ bgcolor: tk.surfaceContainer, borderRadius: '20px', p: 1.25, display: 'flex', flexDirection: 'column', gap: 1.25, minHeight: 240 }}>
              <Box sx={{ display: 'flex', alignItems: 'center', justifyContent: 'space-between', px: 0.75, pt: 0.5 }}>
                <Typography variant="overline" sx={{ color: col === 'blocked' ? tk.error : tk.onSurfaceVariant }}>{statusLabel(col)}</Typography>
                <Typography variant="caption" sx={{ fontWeight: 700 }}>{items.length}</Typography>
              </Box>
              {q.isLoading && <LoadingRows rows={2} height={120} />}
              {items.map((w) => <WoCard key={w.id} w={w} now={now} onOpen={() => setFocusId(w.id)} />)}
              {!q.isLoading && items.length === 0 && <Typography variant="caption" color="text.secondary" sx={{ px: 0.75, fontFamily: fonts.sans }}>Nothing here</Typography>}
            </Box>
          );
        })}
      </Box>
      <WoDrawer w={focus} onClose={() => setFocusId(null)} onAssign={() => setAssigning(true)} />
      <AssignDialog w={assigning ? focus : null} onClose={() => setAssigning(false)} />
    </>
  );
}
