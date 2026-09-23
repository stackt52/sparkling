'use client';
import * as React from 'react';
import Box from '@mui/material/Box';
import Typography from '@mui/material/Typography';
import Button from '@mui/material/Button';
import Divider from '@mui/material/Divider';
import Dialog from '@mui/material/Dialog';
import DialogTitle from '@mui/material/DialogTitle';
import DialogContent from '@mui/material/DialogContent';
import DialogActions from '@mui/material/DialogActions';
import TextField from '@mui/material/TextField';
import ToggleButton from '@mui/material/ToggleButton';
import ToggleButtonGroup from '@mui/material/ToggleButtonGroup';
import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query';
import MSymbol from '@/components/MSymbol';
import DetailDrawer from '@/components/ui/DetailDrawer';
import StatusChip from '@/components/ui/StatusChip';
import Tile from '@/components/ui/Tile';
import CashChip, { cashDue } from '@/components/bookings/CashChip';
import RecordPaymentDialog, { type RecordPaymentTarget } from '@/components/payments/RecordPaymentDialog';
import { ErrorState, LoadingRows } from '@/components/ui/States';
import Toast from '@/components/ui/Toast';
import { useApi, useAuth } from '@/lib/auth/AuthProvider';
import { can } from '@/lib/rbac';
import { useToast } from '@/lib/hooks';
import { fonts, tk } from '@/theme/tokens';
import { fmtDateTime, fmtTime, rands } from '@/lib/format';
import { SIZE_LABEL } from '@/components/catalogue/pricing';
import type { TimelineStage, WalkInPriority } from '@/lib/types';

function Row({ label, value, mono }: { label: string; value: React.ReactNode; mono?: boolean }) {
  return (
    <Box sx={{ display: 'flex', justifyContent: 'space-between', gap: 2, py: 0.75 }}>
      <Typography variant="body2" color="text.secondary">{label}</Typography>
      {/* component="div": values can be chips or other block elements, which HTML forbids inside a <p>. */}
      <Typography variant="body1" component="div" sx={{ fontWeight: 600, fontFamily: mono ? fonts.mono : undefined, textAlign: 'right' }}>{value}</Typography>
    </Box>
  );
}

function Timeline({ stages }: { stages: TimelineStage[] }) {
  return (
    <Box component="ol" sx={{ listStyle: 'none', m: 0, p: 0, display: 'flex', flexDirection: 'column' }}>
      {stages.map((s, i) => {
        const last = i === stages.length - 1;
        const dot = s.state === 'done' ? { bg: tk.primary, fg: tk.onPrimary, icon: 'check' } : s.state === 'current' ? { bg: tk.primaryContainer, fg: tk.primary, icon: 'radio_button_checked' } : s.state === 'blocked' ? { bg: tk.errorContainer, fg: tk.onErrorContainer, icon: 'block' } : { bg: tk.surfaceContainerHigh, fg: tk.onSurfaceVariant, icon: 'circle' };
        return (
          <Box component="li" key={s.key} sx={{ display: 'flex', gap: 1.5, minHeight: 52 }}>
            <Box sx={{ display: 'flex', flexDirection: 'column', alignItems: 'center' }}>
              <Box sx={{ width: 28, height: 28, borderRadius: '50%', bgcolor: dot.bg, color: dot.fg, display: 'grid', placeItems: 'center', flexShrink: 0 }}>
                <MSymbol name={dot.icon} size={16} filled />
              </Box>
              {!last && <Box sx={{ width: 3, flex: 1, bgcolor: s.state === 'done' ? tk.primary : tk.outlineVariant, borderRadius: 2, my: 0.5 }} />}
            </Box>
            <Box sx={{ pb: 1.5 }}>
              <Typography variant="h6" component="p" sx={{ color: s.state === 'current' ? tk.primary : s.state === 'blocked' ? tk.error : tk.onSurface }}>{s.title}</Typography>
              <Typography variant="body2" color="text.secondary">
                {s.state === 'done' ? `${fmtTime(s.at)}${s.actor ? ` · ${s.actor}` : ''}` : s.state === 'current' ? 'In progress' : s.state === 'blocked' ? 'Blocked' : 'Pending'}
              </Typography>
            </Box>
          </Box>
        );
      })}
    </Box>
  );
}

export default function BookingDrawer({ bookingId, onClose }: { bookingId: string | null; onClose: () => void }) {
  const api = useApi();
  const { role } = useAuth();
  const qc = useQueryClient();
  const toast = useToast();
  const [cancelOpen, setCancelOpen] = React.useState(false);
  const [reason, setReason] = React.useState('');
  const [checkinOpen, setCheckinOpen] = React.useState(false);
  const [bay, setBay] = React.useState('');
  const [priority, setPriority] = React.useState<WalkInPriority>(2);
  const [payTarget, setPayTarget] = React.useState<RecordPaymentTarget | null>(null);
  const q = useQuery({ queryKey: ['booking', bookingId], queryFn: () => api.getBooking(bookingId!), enabled: Boolean(bookingId) });
  const cancel = useMutation({
    mutationFn: () => api.cancelBooking(bookingId!, reason),
    onSuccess: () => {
      toast.success('Booking cancelled');
      setCancelOpen(false);
      void qc.invalidateQueries({ queryKey: ['bookings'] });
      void qc.invalidateQueries({ queryKey: ['booking', bookingId] });
    },
    onError: (e) => toast.error(e),
  });
  // Explicit "car checked in" (`POST /bookings/:id/checkin`): stamps the booking's existing work order (created when it was confirmed) and auto-assigns it when the flag is on.
  const checkin = useMutation({
    mutationFn: () => api.checkinBooking(bookingId!, { bay: bay.trim() || null, priority }),
    onSuccess: (res) => {
      const auto = res.work_order?.assignee_name ? ` · auto-assigned to ${res.work_order.assignee_name}` : '';
      toast.success(`Checked in · ${res.work_order?.ref ?? 'work order'}${res.created ? ' created' : ''}${auto}`);
      setCheckinOpen(false);
      setBay('');
      void qc.invalidateQueries({ queryKey: ['bookings'] });
      void qc.invalidateQueries({ queryKey: ['booking', bookingId] });
      void qc.invalidateQueries({ queryKey: ['work-orders'] });
    },
    onError: (e) => toast.error(e),
  });
  const b = q.data;
  const canCancel = can(role, 'booking:cancel') && b && ['pending', 'confirmed'].includes(b.status);
  // The work order exists from confirmation; the button stays until the car is actually checked in on it.
  const canCheckin = can(role, 'work_order:checkin') && b && ['pending', 'confirmed'].includes(b.status) && !b.work_order?.checked_in_at;
  // Counter payment (cash / card terminal) for anything still unpaid — cash-on-collection bookings, or a card booking whose customer pays at the desk instead.
  const canRecordPayment = can(role, 'payment:record') && b && ['confirmed', 'in_service', 'completed'].includes(b.status) && b.total_cents > 0 && b.payment?.status !== 'successful';
  const workOrderLine = b?.work_order
    ? `${b.work_order.ref} · ${b.work_order.checked_in_at ? `checked in ${fmtTime(b.work_order.checked_in_at)}` : 'awaiting check-in'}${b.work_order.assignee_name ? ` · ${b.work_order.assignee_name}` : ''}${b.work_order.bay ? ` · ${b.work_order.bay}` : ''}`
    : null;

  return (
    <>
      <DetailDrawer
        open={Boolean(bookingId)}
        onClose={onClose}
        label="Booking"
        closeLabel="Close booking details"
        titleId="booking-drawer-title"
        title={b && (
          <>
            <Typography variant="h2" className="mono" sx={{ color: tk.primary }}>{b.ref}</Typography>
            <StatusChip status={b.status} />
          </>
        )}
        subtitle={b && (
          <>
            {b.customer.full_name} · {b.vehicle.make} {b.vehicle.model}
            {b.walk_in && <> · <Box component="span" sx={{ color: tk.secondary, fontWeight: 600 }}>Walk-in</Box>{b.created_by_name ? ` · created by ${b.created_by_name}` : ''}</>}
          </>
        )}
        footer={(canCheckin || canCancel || canRecordPayment) && (
          <Box sx={{ display: 'flex', flexDirection: 'column', gap: 1.5 }}>
            {canRecordPayment && (
              <Button variant={canCheckin ? 'outlined' : 'contained'} color="secondary" fullWidth onClick={() => setPayTarget({ kind: 'booking', id: b.id, ref: b.ref, amount_cents: b.total_cents, customer_name: b.customer.full_name })} startIcon={<MSymbol name="point_of_sale" size={20} />} data-testid="booking-record-payment">
                Record payment · {rands(b.total_cents)}
              </Button>
            )}
            {canCheckin && (
              <Button variant="contained" color="secondary" fullWidth onClick={() => setCheckinOpen(true)} startIcon={<MSymbol name="login" size={20} />} data-testid="booking-confirm-checkin">
                Confirm check-in
              </Button>
            )}
            {canCancel && (
              <Button variant="outlined" color="error" fullWidth onClick={() => setCancelOpen(true)} startIcon={<MSymbol name="event_busy" size={20} />}>
                Cancel booking
              </Button>
            )}
          </Box>
        )}
      >
        {q.isLoading && <LoadingRows rows={6} />}
        {q.error && <ErrorState error={q.error} onRetry={() => q.refetch()} />}
        {b && (
          <>
            <Tile sx={{ flexDirection: 'column', alignItems: 'stretch', gap: 0 }}>
              <Row label="Service" value={b.service.name} />
              <Row label="Outlet" value={b.outlet.name} />
              <Row label="Slot" value={`${fmtDateTime(b.slot_start)} – ${fmtTime(b.slot_end)}`} />
              <Row label="Vehicle" value={b.vehicle.registration_no} mono />
              {b.vehicle_size && <Row label="Vehicle size" value={`${SIZE_LABEL[b.vehicle_size]}${b.price_label ? ` · ${b.price_label}` : ''}`} />}
              {b.addons && b.addons.length > 0 && <Row label="Add-ons" value={b.addons.map((a) => a.name).join(', ')} />}
              {workOrderLine && <Row label="Work order" value={<span data-testid="booking-work-order">{workOrderLine}</span>} />}
            </Tile>

            <Typography variant="h4" component="h3" sx={{ mt: 4, mb: 1.5 }}>Timeline</Typography>
            <Timeline stages={b.timeline} />

            <Typography variant="h4" component="h3" sx={{ mt: 3, mb: 1.5 }}>Payment</Typography>
            <Tile sx={{ flexDirection: 'column', alignItems: 'stretch', gap: 0 }}>
              <Row label={b.addons?.length ? b.service.name : 'Price'} value={rands(b.price_cents - (b.addons_cents ?? 0), { decimals: true })} />
              {(b.addons ?? []).map((a) => <Row key={a.service_id} label={`+ ${a.name}`} value={rands(a.price_cents, { decimals: true })} />)}
              {b.discount_cents > 0 && <Row label={b.discount_label ?? 'Discount'} value={<span style={{ color: tk.success }}>−{rands(b.discount_cents, { decimals: true })}</span>} />}
              {(b.vat_cents ?? 0) > 0 && <Row label="VAT 15 % (excl. price)" value={rands(b.vat_cents!, { decimals: true })} />}
              <Divider sx={{ my: 0.5, borderStyle: 'dashed' }} />
              <Row label="Total" value={<span style={{ color: tk.primary, fontSize: 18 }}>{rands(b.total_cents, { decimals: true })}</span>} />
              {/* Cash-on-collection bookings keep the cash chip: "Cash due R x" → "Paid · cash" once recorded. */}
              <Row label="Payment" value={b.payment_method === 'cash' && b.payment?.status !== 'failed' ? <CashChip booking={b} size="medium" /> : b.payment ? <StatusChip status={b.payment.status} /> : <StatusChip tone="neutral" label="Not started" />} />
              {b.payment?.method ? (
                <Row label="Method" value={b.payment.method === 'cash' ? (b.payment_method === 'cash' ? 'Cash on collection (counter)' : 'Cash (counter)') : 'Card terminal'} />
              ) : b.payment_method ? (
                <Row label="Method" value={{ cash: 'Cash on collection', card: 'Card (online)', eft: 'Instant EFT' }[b.payment_method]} />
              ) : null}
              {b.payment?.receipt_no && <Row label="Receipt" value={b.payment.receipt_no} mono />}
              <Row label="Points pending" value={`+${b.points_pending} pts on completion`} />
            </Tile>
            {cashDue(b) && (
              <Tile tone="warning" sx={{ mt: 1.5, alignItems: 'flex-start' }} data-testid="cash-due-note">
                <MSymbol name="payments" filled size={22} />
                <Box sx={{ minWidth: 0 }}>
                  <Typography variant="subtitle2">Cash on collection — record the payment at the counter before hand-over</Typography>
                  <Typography variant="body2">{rands(b.total_cents, { decimals: true })} due in cash. Collection is refused until the payment is recorded.</Typography>
                </Box>
              </Tile>
            )}
            {b.cancel_reason && <Typography variant="body2" sx={{ mt: 2, color: tk.error }}>Cancelled: {b.cancel_reason}</Typography>}
          </>
        )}
      </DetailDrawer>
      <Dialog open={cancelOpen} onClose={() => setCancelOpen(false)} aria-labelledby="cancel-title">
        <DialogTitle id="cancel-title">Cancel {b?.ref}?</DialogTitle>
        <DialogContent>
          <Typography variant="body2" color="text.secondary" sx={{ mb: 2 }}>The customer is notified and any pending payment is voided. This is recorded in the audit log.</Typography>
          <TextField label="Reason" fullWidth multiline minRows={2} value={reason} onChange={(e) => setReason(e.target.value)} autoFocus />
        </DialogContent>
        <DialogActions sx={{ p: 2.5, pt: 0 }}>
          <Button onClick={() => setCancelOpen(false)}>Keep booking</Button>
          <Button variant="contained" color="error" disabled={!reason.trim() || cancel.isPending} onClick={() => cancel.mutate()}>Cancel booking</Button>
        </DialogActions>
      </Dialog>
      <Dialog open={checkinOpen} onClose={() => setCheckinOpen(false)} aria-labelledby="booking-checkin-title" fullWidth maxWidth="xs">
        <DialogTitle id="booking-checkin-title">Confirm check-in · {b?.ref}</DialogTitle>
        <DialogContent sx={{ display: 'flex', flexDirection: 'column', gap: 1.5 }}>
          <Typography variant="body2" color="text.secondary">
            Confirms that <span className="mono">{b?.vehicle.registration_no}</span> is on site: the booking moves to in service and its work order{b?.work_order ? ` ${b.work_order.ref}` : ''} is checked in — assigned automatically when auto-assignment is on, otherwise by a supervisor.
          </Typography>
          <TextField label="Bay (optional)" placeholder="e.g. Bay 2" value={bay} onChange={(e) => setBay(e.target.value)} size="small" autoFocus onKeyDown={(e) => { if (e.key === 'Enter' && !checkin.isPending) { e.preventDefault(); checkin.mutate(); } }} />
          <Box>
            <Typography component="span" id="booking-checkin-priority" variant="caption" color="text.secondary" sx={{ display: 'block', mb: 0.5 }}>Priority</Typography>
            <ToggleButtonGroup
              exclusive
              value={priority}
              onChange={(_e, v: WalkInPriority | null) => { if (v) setPriority(v); }}
              aria-labelledby="booking-checkin-priority"
              sx={{ bgcolor: tk.surfaceContainerHigh, borderRadius: 999, p: 0.5, gap: 0.5, '& .MuiToggleButton-root': { border: 0, borderRadius: '999px !important', px: 1.75, py: 0.6, fontWeight: 600, color: tk.onSurfaceVariant, '&.Mui-selected': { bgcolor: tk.secondary, color: tk.onSecondary, '&:hover': { bgcolor: tk.secondary } } } }}
            >
              <ToggleButton value={1}>P1 · urgent</ToggleButton>
              <ToggleButton value={2}>P2</ToggleButton>
              <ToggleButton value={3}>P3</ToggleButton>
            </ToggleButtonGroup>
          </Box>
        </DialogContent>
        <DialogActions sx={{ p: 2.5, pt: 0 }}>
          <Button onClick={() => setCheckinOpen(false)}>Not yet</Button>
          <Button variant="contained" color="secondary" startIcon={<MSymbol name="login" size={18} />} disabled={checkin.isPending} onClick={() => checkin.mutate()}>Confirm check-in</Button>
        </DialogActions>
      </Dialog>
      <RecordPaymentDialog
        target={payTarget}
        onClose={() => setPayTarget(null)}
        onRecorded={(p) => {
          toast.success(`Recorded · receipt ${p.receipt_no ?? p.id}`);
          void qc.invalidateQueries({ queryKey: ['booking', bookingId] });
        }}
      />
      <Toast toast={toast.toast} onClose={toast.close} />
    </>
  );
}
