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
import Tooltip from '@mui/material/Tooltip';
import Avatar from '@mui/material/Avatar';
import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query';
import PageHeader from '@/components/layout/PageHeader';
import DetailDrawer from '@/components/ui/DetailDrawer';
import { LiveChip, OutletPill } from '@/components/ui/Pills';
import StatusChip from '@/components/ui/StatusChip';
import LevelBar from '@/components/ui/LevelBar';
import Tile from '@/components/ui/Tile';
import Toast from '@/components/ui/Toast';
import MSymbol from '@/components/MSymbol';
import { LoadingRows } from '@/components/ui/States';
import HandoverPanel from '@/components/work/HandoverPanel';
import { useApi, useAuth } from '@/lib/auth/AuthProvider';
import { conflictDetail } from '@/lib/api';
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
      {/* Both booking- and quote-based orders start awaiting check-in; the chip clears once the car is confirmed on site. */}
      {!w.checked_in_at && <AwaitingCheckinChip />}
      {/* Verified: the customer holds the collection OTP until the keys are released at the counter. */}
      {w.status === 'verified' && (w.collected_at ? <CollectedChip at={w.collected_at} /> : <ReadyForCollectionChip />)}
      <Typography variant="body2" color="text.secondary"><span className="mono">{w.vehicle.registration_no}</span>{w.bay ? ` · ${w.bay}` : ''} · {w.customer_name.split(' ')[0]}</Typography>
      {(w.booking_ref || w.quotation_ref) && (
        <Typography variant="caption" color="text.secondary" sx={{ mt: -0.5 }} data-testid="wo-source-ref">
          {w.booking_ref ? 'Booking ' : 'Quote '}<span className="mono">{w.booking_ref ?? w.quotation_ref}</span>
        </Typography>
      )}
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

/** Shown while `checked_in_at` is null — the car is not on site yet, so the work order cannot be assigned. */
function AwaitingCheckinChip({ size = 'small' }: { size?: 'small' | 'medium' }) {
  return (
    <StatusChip
      tone="warning"
      label="Awaiting check-in"
      icon={<MSymbol name="garage" filled size={size === 'small' ? 15 : 18} />}
      data-testid="awaiting-checkin"
      sx={{ alignSelf: 'flex-start', ...(size === 'small' && { height: 22, fontSize: 11 }), '& .MuiChip-icon': { color: 'inherit', ml: 0.75, mr: -0.25 } }}
    />
  );
}

/** Shown on a `verified` order until the OTP is verified — the customer still has to collect the keys. */
function ReadyForCollectionChip({ size = 'small' }: { size?: 'small' | 'medium' }) {
  return (
    <StatusChip
      tone="secondary"
      label="Ready for collection"
      icon={<MSymbol name="key" filled size={size === 'small' ? 15 : 18} />}
      data-testid="ready-for-collection"
      sx={{ alignSelf: 'flex-start', ...(size === 'small' && { height: 22, fontSize: 11 }), '& .MuiChip-icon': { color: 'inherit', ml: 0.75, mr: -0.25 } }}
    />
  );
}

/** "Collected HH:mm" — `collected_at` set by `POST /work-orders/:id/pickup/verify`. */
function CollectedChip({ at, size = 'small' }: { at: string; size?: 'small' | 'medium' }) {
  return (
    <StatusChip
      tone="success"
      label={`Collected ${fmtTime(at)}`}
      icon={<MSymbol name="key" filled size={size === 'small' ? 15 : 18} />}
      data-testid="collected-chip"
      sx={{ alignSelf: 'flex-start', ...(size === 'small' && { height: 22, fontSize: 11 }), '& .MuiChip-icon': { color: 'inherit', ml: 0.75, mr: -0.25 } }}
    />
  );
}

/**
 * "Confirm check-in" — the explicit "car is on site" step (`POST /work-orders/:id/checkin`). The bay is optional.
 * After success the board is refreshed; the toast names the auto-assigned technician when the flag handed it out.
 */
function CheckinDialog({ w, onClose, onDone }: { w: WorkOrder | null; onClose: () => void; onDone: (message: string) => void }) {
  return (
    <Dialog open={Boolean(w)} onClose={onClose} aria-labelledby="checkin-title" fullWidth maxWidth="xs">
      {w && <CheckinForm w={w} onClose={onClose} onDone={onDone} />}
    </Dialog>
  );
}

/** `onDone` carries the success message to the page's toast — the dialog (and its own toast) unmounts on close. */
function CheckinForm({ w, onClose, onDone }: { w: WorkOrder; onClose: () => void; onDone: (message: string) => void }) {
  const api = useApi();
  const qc = useQueryClient();
  const toast = useToast();
  const [bay, setBay] = React.useState(w.bay ?? '');
  const m = useMutation({
    mutationFn: () => api.checkinWorkOrder(w.id, { bay: bay.trim() || null }),
    onSuccess: (res) => {
      void qc.invalidateQueries({ queryKey: ['work-orders'] });
      void qc.invalidateQueries({ queryKey: ['bookings'] });
      void qc.invalidateQueries({ queryKey: ['booking'] });
      // A quote-based order's check-in marks its quotation `converted`.
      void qc.invalidateQueries({ queryKey: ['quotations'] });
      void qc.invalidateQueries({ queryKey: ['quotation'] });
      onClose();
      const converted = w.quotation_ref ? ` · ${w.quotation_ref} converted` : '';
      onDone(res.assignee_name && !w.assignee_name ? `Checked in · auto-assigned to ${res.assignee_name}${converted}` : `Checked in${converted}`);
    },
    onError: (e) => toast.error(e),
  });
  return (
    <>
      <DialogTitle id="checkin-title">Confirm check-in · {w.ref}</DialogTitle>
      <DialogContent sx={{ display: 'flex', flexDirection: 'column', gap: 1.5 }}>
        <Typography variant="body2" color="text.secondary">
          Confirms that <b>{w.vehicle.registration_no}</b> is on site. The work order can then be assigned — automatically when auto-assignment is on, otherwise by a supervisor.
        </Typography>
        <TextField label="Bay (optional)" placeholder="e.g. Body 1" value={bay} onChange={(e) => setBay(e.target.value)} size="small" autoFocus onKeyDown={(e) => { if (e.key === 'Enter' && !m.isPending) { e.preventDefault(); m.mutate(); } }} />
      </DialogContent>
      <DialogActions sx={{ p: 2.5, pt: 0 }}>
        <Button onClick={onClose}>Cancel</Button>
        <Button variant="contained" color="secondary" startIcon={<MSymbol name="login" size={18} />} disabled={m.isPending} onClick={() => m.mutate()}>Confirm check-in</Button>
      </DialogActions>
      <Toast toast={toast.toast} onClose={toast.close} />
    </>
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
    mutationFn: () => api.assignTask(w.task_id!, { assignee_id: assignee, reason: reason || undefined }),
    onSuccess: (res) => { toast.success(`${res.ref} assigned to ${res.assignee_name}`); void qc.invalidateQueries({ queryKey: ['work-orders'] }); onClose(); },
    // 409 `not_checked_in`: the API refuses assignment until the car is checked in — surface its message and refresh the card.
    onError: (e) => { toast.error(e); if (conflictDetail<string>(e, 'reason') === 'not_checked_in') void qc.invalidateQueries({ queryKey: ['work-orders'] }); },
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
        <Button variant="contained" color="secondary" disabled={!assignee || !w.task_id || m.isPending || assignee === w.assignee_id} onClick={() => m.mutate()}>Assign</Button>
      </DialogActions>
      <Toast toast={toast.toast} onClose={toast.close} />
    </>
  );
}

/** Audit-trail icons per task event (`transition` and anything unknown fall back to swap_horiz). */
const EVENT_ICON: Record<string, string> = { assigned: 'assignment_ind', checked_in: 'login', collected: 'key', pickup_otp_failed: 'password', pickup_otp_resent: 'send' };

const NEXT: Partial<Record<WorkStatus, { to: WorkStatus; label: string; icon: string; needsReason?: boolean }[]>> = {
  assigned: [{ to: 'in_progress', label: 'Start', icon: 'play_arrow' }],
  in_progress: [{ to: 'blocked', label: 'Mark blocked', icon: 'block', needsReason: true }, { to: 'completed', label: 'Complete', icon: 'task_alt' }],
  blocked: [{ to: 'in_progress', label: 'Resume', icon: 'play_arrow' }],
  completed: [{ to: 'verified', label: 'Verify', icon: 'verified' }],
};

function WoDrawer({ w, onClose, onAssign, onCheckin }: { w: WorkOrder | null; onClose: () => void; onAssign: () => void; onCheckin: () => void }) {
  const api = useApi();
  const { role } = useAuth();
  const qc = useQueryClient();
  const toast = useToast();
  const [reasonFor, setReasonFor] = React.useState<WorkStatus | null>(null);
  const [reason, setReason] = React.useState('');
  const m = useMutation({
    mutationFn: (body: { to: WorkStatus; reason?: string }) => api.transitionTask(w!.task_id!, body),
    onSuccess: (res) => { toast.success(`${res.ref} → ${statusLabel(res.status)}`); void qc.invalidateQueries({ queryKey: ['work-orders'] }); setReasonFor(null); setReason(''); },
    onError: (e) => toast.error(e),
  });
  // Actions act on the work order's task; legacy rows without one are read-only.
  const canAct = can(role, 'task:transition') && Boolean(w?.task_id);
  const canAssign = can(role, 'task:assign') && Boolean(w?.task_id);
  const checkedIn = Boolean(w?.checked_in_at);
  const collected = Boolean(w?.collected_at);
  const canCheckin = can(role, 'work_order:checkin') && Boolean(w) && !checkedIn && !['verified', 'cancelled'].includes(w!.status);
  // Hand-over: a verified order whose keys have not been released yet (`work_order:handover` — the check-in roles).
  const canHandover = can(role, 'work_order:handover') && w?.status === 'verified' && !collected;
  const transitions = w ? NEXT[w.status] ?? [] : [];
  // Once collected the job is closed — no more assignment / transitions.
  const hasFooter = Boolean(w) && !collected && (canAssign || canCheckin || (canAct && transitions.length > 0) || Boolean(reasonFor));
  return (
    <DetailDrawer
      open={Boolean(w)}
      onClose={onClose}
      label="Work order"
      titleId="work-order-drawer-title"
      title={w && (
        <>
          <Typography variant="h2" className="mono" sx={{ color: tk.primary }}>{w.ref}</Typography>
          <StatusChip status={w.status} />
          <StatusChip tone={priorityTone[w.priority]} label={`P${w.priority}`} />
          {!w.checked_in_at && <AwaitingCheckinChip size="medium" />}
          {w.status === 'verified' && (w.collected_at ? <CollectedChip at={w.collected_at} size="medium" /> : <ReadyForCollectionChip size="medium" />)}
        </>
      )}
      subtitle={w && (
        <>
          {w.service.name} · {w.vehicle.make} {w.vehicle.model} · <span className="mono">{w.vehicle.registration_no}</span>
          {w.checked_in_at && <> · Checked in {fmtTime(w.checked_in_at)}{w.checked_in_by_name ? ` by ${w.checked_in_by_name}` : ''}</>}
          {w.collected_at && <> · Collected {fmtTime(w.collected_at)}</>}
        </>
      )}
      footer={w && hasFooter && (
        <Box sx={{ display: 'flex', flexDirection: 'column', gap: 1.5 }}>
          {canCheckin && (
            <Button variant="contained" color="secondary" fullWidth onClick={onCheckin} startIcon={<MSymbol name="login" size={20} />} data-testid="confirm-checkin">Confirm check-in</Button>
          )}
          {canAssign && (
            <Tooltip title={checkedIn ? '' : 'Check the car in first'} placement="left">
              <span style={{ display: 'block' }}>
                <Button variant="outlined" fullWidth disabled={!checkedIn} onClick={onAssign} startIcon={<MSymbol name="assignment_ind" size={20} />} data-testid="assign-button">{w.assignee_id ? 'Reassign' : 'Assign'}</Button>
              </span>
            </Tooltip>
          )}
          {canAct && transitions.length > 0 && (
            <Box sx={{ display: 'flex', gap: 1, flexWrap: 'wrap' }}>
              {transitions.map((n) => (
                <Button key={n.to} variant={n.to === 'blocked' ? 'outlined' : 'contained'} color={n.to === 'blocked' ? 'error' : 'secondary'} size="small" startIcon={<MSymbol name={n.icon} size={18} />} onClick={() => (n.needsReason || (n.to === 'verified' && w.steps_done < w.step_count) ? setReasonFor(n.to) : m.mutate({ to: n.to }))} disabled={m.isPending}>
                  {n.label}
                </Button>
              ))}
            </Box>
          )}
          {reasonFor && (
            <Box sx={{ display: 'flex', flexDirection: 'column', gap: 1 }}>
              <TextField label={reasonFor === 'verified' ? 'Override reason (required steps incomplete)' : 'Reason'} value={reason} onChange={(e) => setReason(e.target.value)} size="small" autoFocus multiline />
              <Box sx={{ display: 'flex', gap: 1 }}>
                <Button size="small" onClick={() => setReasonFor(null)}>Cancel</Button>
                <Button size="small" variant="contained" color="secondary" disabled={!reason.trim()} onClick={() => m.mutate({ to: reasonFor, reason })}>Confirm</Button>
              </Box>
            </Box>
          )}
        </Box>
      )}
    >
      {w && (
        <>
          <Tile sx={{ flexDirection: 'column', alignItems: 'stretch', gap: 0.5 }}>
            <Typography variant="body2">{w.outlet.name}{w.bay ? ` · ${w.bay}` : ''} · {w.customer_name}</Typography>
            <Typography variant="body2">{w.booking_ref ? `Booking ${w.booking_ref}` : w.quotation_ref ? `Quotation ${w.quotation_ref}` : ''}</Typography>
            <Typography variant="body2">Assignee: <b>{w.assignee_name ?? 'unassigned'}</b>{w.eta_at ? ` · ETA ${fmtTime(w.eta_at)}` : ''}{w.due_at ? ` · due ${fmtTime(w.due_at)}` : ''}</Typography>
            <Box sx={{ display: 'flex', alignItems: 'center', gap: 1, mt: 0.5 }}>
              <LevelBar value={w.steps_done} max={w.step_count} tone={w.status === 'blocked' ? 'error' : 'primary'} height={8} label="Checklist progress" />
              <Typography variant="caption">{w.steps_done}/{w.step_count} steps</Typography>
            </Box>
            {w.blocked_reason && <Typography variant="body2" sx={{ color: tk.error, fontWeight: 600 }}>{w.blocked_reason}</Typography>}
          </Tile>
          {/* Keyed on the work order so a fresh OTP form (attempts, cooldown) opens per card. */}
          {canHandover && <HandoverPanel key={w.id} w={w} onCollected={(at) => toast.success(`Keys released · collected ${fmtTime(at)}`)} />}
          <Typography variant="h4" sx={{ mt: 3, mb: 1 }}>Audit trail</Typography>
          <Box component="ol" sx={{ listStyle: 'none', m: 0, p: 0, display: 'flex', flexDirection: 'column', gap: 1 }}>
            {w.events.length === 0 && <Typography variant="body2" color="text.secondary">No events yet.</Typography>}
            {[...w.events].reverse().map((e) => (
              <Box component="li" key={e.id} sx={{ display: 'flex', gap: 1.5 }}>
                <MSymbol name={EVENT_ICON[e.event] ?? 'swap_horiz'} size={20} style={{ color: e.event === 'pickup_otp_failed' ? tk.error : tk.onSurfaceVariant, marginTop: 2 }} />
                <Box>
                  <Typography variant="body2">
                    {e.event === 'checked_in' ? <>Checked in · <b>{e.actor_name ?? 'staff'}</b></>
                      : e.event === 'collected' ? <>Keys released · OTP verified by <b>{e.actor_name ?? 'staff'}</b></>
                      : e.event === 'pickup_otp_failed' ? <>Incorrect collection OTP entered · <b>{e.actor_name ?? 'staff'}</b></>
                      : e.event === 'pickup_otp_resent' ? <>Collection OTP re-sent · <b>{e.actor_name ?? 'staff'}</b></>
                      : <><b>{e.actor_name}</b> {e.event === 'assigned' ? 'assigned' : `moved ${statusLabel(e.from_status ?? '')} → ${statusLabel(e.to_status ?? '')}`}</>}
                  </Typography>
                  <Typography variant="caption" color="text.secondary">{fmtDateTime(e.created_at)}{e.reason ? ` · ${e.reason}` : ''}</Typography>
                </Box>
              </Box>
            ))}
          </Box>
        </>
      )}
      <Toast toast={toast.toast} onClose={toast.close} />
    </DetailDrawer>
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
  const [checkingIn, setCheckingIn] = React.useState(false);
  const toast = useToast();
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
      <WoDrawer w={focus} onClose={() => setFocusId(null)} onAssign={() => setAssigning(true)} onCheckin={() => setCheckingIn(true)} />
      <AssignDialog w={assigning ? focus : null} onClose={() => setAssigning(false)} />
      <CheckinDialog w={checkingIn ? focus : null} onClose={() => setCheckingIn(false)} onDone={(message) => toast.success(message)} />
      <Toast toast={toast.toast} onClose={toast.close} />
    </>
  );
}
