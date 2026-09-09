'use client';
import * as React from 'react';
import Drawer from '@mui/material/Drawer';
import Box from '@mui/material/Box';
import Typography from '@mui/material/Typography';
import IconButton from '@mui/material/IconButton';
import Button from '@mui/material/Button';
import Divider from '@mui/material/Divider';
import Dialog from '@mui/material/Dialog';
import DialogTitle from '@mui/material/DialogTitle';
import DialogContent from '@mui/material/DialogContent';
import DialogActions from '@mui/material/DialogActions';
import TextField from '@mui/material/TextField';
import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query';
import MSymbol from '@/components/MSymbol';
import StatusChip from '@/components/ui/StatusChip';
import Tile from '@/components/ui/Tile';
import { ErrorState, LoadingRows } from '@/components/ui/States';
import Toast from '@/components/ui/Toast';
import { useApi, useAuth } from '@/lib/auth/AuthProvider';
import { can } from '@/lib/rbac';
import { useToast } from '@/lib/hooks';
import { fonts, tk } from '@/theme/tokens';
import { fmtDateTime, fmtTime, rands } from '@/lib/format';
import type { TimelineStage } from '@/lib/types';

function Row({ label, value, mono }: { label: string; value: React.ReactNode; mono?: boolean }) {
  return (
    <Box sx={{ display: 'flex', justifyContent: 'space-between', gap: 2, py: 0.75 }}>
      <Typography variant="body2" color="text.secondary">{label}</Typography>
      <Typography variant="body1" sx={{ fontWeight: 600, fontFamily: mono ? fonts.mono : undefined, textAlign: 'right' }}>{value}</Typography>
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
  const b = q.data;
  const canCancel = can(role, 'booking:cancel') && b && ['pending', 'confirmed'].includes(b.status);

  return (
    <>
      <Drawer anchor="right" open={Boolean(bookingId)} onClose={onClose} slotProps={{ paper: { sx: { width: { xs: '100%', sm: 460 }, borderRadius: { xs: 0, sm: '28px 0 0 28px' }, p: 3 } } }}>
        <Box sx={{ display: 'flex', alignItems: 'center', justifyContent: 'space-between', mb: 1 }}>
          <Typography variant="overline" color="text.secondary">Booking</Typography>
          <IconButton aria-label="Close booking details" onClick={onClose}><MSymbol name="close" /></IconButton>
        </Box>
        {q.isLoading && <LoadingRows rows={6} />}
        {q.error && <ErrorState error={q.error} onRetry={() => q.refetch()} />}
        {b && (
          <>
            <Box sx={{ display: 'flex', alignItems: 'center', gap: 1.5, mb: 0.5 }}>
              <Typography variant="h2" className="mono" sx={{ color: tk.primary }}>{b.ref}</Typography>
              <StatusChip status={b.status} />
            </Box>
            <Typography color="text.secondary">{b.customer.full_name} · {b.vehicle.make} {b.vehicle.model}</Typography>
            <Tile sx={{ mt: 2, flexDirection: 'column', alignItems: 'stretch', gap: 0 }}>
              <Row label="Service" value={b.service.name} />
              <Row label="Outlet" value={b.outlet.name} />
              <Row label="Slot" value={`${fmtDateTime(b.slot_start)} – ${fmtTime(b.slot_end)}`} />
              <Row label="Vehicle" value={b.vehicle.registration_no} mono />
              {b.work_order && <Row label="Work order" value={`${b.work_order.ref} · ${b.work_order.assignee_name ?? 'unassigned'}${b.work_order.bay ? ` · ${b.work_order.bay}` : ''}`} />}
            </Tile>
            <Typography variant="h4" sx={{ mt: 3, mb: 1 }}>Timeline</Typography>
            <Timeline stages={b.timeline} />
            <Typography variant="h4" sx={{ mt: 2, mb: 1 }}>Payment</Typography>
            <Tile sx={{ flexDirection: 'column', alignItems: 'stretch', gap: 0 }}>
              <Row label="Price" value={rands(b.price_cents, { decimals: true })} />
              {b.discount_cents > 0 && <Row label={b.discount_label ?? 'Discount'} value={<span style={{ color: tk.success }}>−{rands(b.discount_cents, { decimals: true })}</span>} />}
              <Divider sx={{ my: 0.5, borderStyle: 'dashed' }} />
              <Row label="Total" value={<span style={{ color: tk.primary, fontSize: 18 }}>{rands(b.total_cents, { decimals: true })}</span>} />
              <Row label="Payment" value={b.payment ? <StatusChip status={b.payment.status} /> : <StatusChip tone="neutral" label="Not started" />} />
              {b.payment?.receipt_no && <Row label="Receipt" value={b.payment.receipt_no} mono />}
              <Row label="Points pending" value={`+${b.points_pending} pts on completion`} />
            </Tile>
            {b.cancel_reason && <Typography variant="body2" sx={{ mt: 2, color: tk.error }}>Cancelled: {b.cancel_reason}</Typography>}
            <Box sx={{ flex: 1 }} />
            {canCancel && (
              <Button variant="outlined" color="error" sx={{ mt: 3 }} onClick={() => setCancelOpen(true)} startIcon={<MSymbol name="event_busy" size={20} />}>
                Cancel booking
              </Button>
            )}
          </>
        )}
      </Drawer>
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
      <Toast toast={toast.toast} onClose={toast.close} />
    </>
  );
}
