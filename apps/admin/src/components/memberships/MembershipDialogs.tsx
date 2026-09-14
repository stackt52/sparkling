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
import ToggleButton from '@mui/material/ToggleButton';
import ToggleButtonGroup from '@mui/material/ToggleButtonGroup';
import CircularProgress from '@mui/material/CircularProgress';
import { useMutation, useQueryClient } from '@tanstack/react-query';
import MSymbol from '@/components/MSymbol';
import IconTile from '@/components/ui/IconTile';
import RadioCards from '@/components/bookings/walkin/RadioCards';
import { useApi } from '@/lib/auth/AuthProvider';
import { uuid } from '@/lib/api';
import { fmtDate, rands } from '@/lib/format';
import { tk } from '@/theme/tokens';
import type { CounterPaymentMethod, MembershipInvoice } from '@/lib/types';
import { periodLabel } from './planFormat';

const METHODS: { key: CounterPaymentMethod; label: string; icon: string }[] = [
  { key: 'cash', label: 'Cash', icon: 'payments' },
  { key: 'card_terminal', label: 'Card terminal', icon: 'credit_card' },
  { key: 'eft', label: 'EFT', icon: 'account_balance' },
];

function invalidateMemberships(qc: ReturnType<typeof useQueryClient>, customerId: string | null | undefined) {
  void qc.invalidateQueries({ queryKey: ['memberships'] });
  void qc.invalidateQueries({ queryKey: ['membership-plans'] });
  void qc.invalidateQueries({ queryKey: ['kpis'] });
  void qc.invalidateQueries({ queryKey: ['payments'] });
  void qc.invalidateQueries({ queryKey: ['customers'] });
  if (customerId) { void qc.invalidateQueries({ queryKey: ['customer', customerId] }); void qc.invalidateQueries({ queryKey: ['customer-membership', customerId] }); }
}

export interface PaymentTarget { membershipId: string; customerId: string; customerName: string; planName: string; invoice: MembershipInvoice }

/** Records a counter payment for a pending renewal invoice (`…/invoices/:id/record-payment`). */
export function RecordMembershipPaymentDialog({ target, onClose, onDone, onError }: { target: PaymentTarget | null; onClose: () => void; onDone: (message: string) => void; onError: (e: unknown) => void }) {
  const api = useApi();
  const qc = useQueryClient();
  const [method, setMethod] = React.useState<CounterPaymentMethod>('cash');
  const [opId, setOpId] = React.useState(() => uuid());
  const [seededFor, setSeededFor] = React.useState(target);
  if (target !== seededFor) { setSeededFor(target); if (target) { setMethod('cash'); setOpId(uuid()); } }
  const pay = useMutation({
    mutationFn: () => api.recordMembershipPayment(target!.membershipId, target!.invoice.id, { method, client_op_id: opId }),
    onSuccess: (r) => { invalidateMemberships(qc, target?.customerId); onDone(`${r.invoice.ref} paid · ${target?.planName} renewed to ${fmtDate(r.invoice.period_end)}`); onClose(); },
    onError,
  });
  return (
    <Dialog open={Boolean(target)} onClose={() => !pay.isPending && onClose()} aria-labelledby="mpay-title" fullWidth maxWidth="sm">
      <DialogTitle id="mpay-title">Record renewal payment</DialogTitle>
      <DialogContent>
        {target && (
          <>
            <Typography variant="body2" color="text.secondary" sx={{ mb: 2 }}>
              <b>{target.customerName}</b> · {target.planName} · <span className="mono">{target.invoice.ref}</span> for {periodLabel(target.invoice.period_start, target.invoice.period_end)}. Paying rolls the period and lifts a past-due pause.
            </Typography>
            <Typography sx={{ fontSize: 30, fontWeight: 700, color: tk.primary, mb: 2 }}>{rands(target.invoice.amount_cents, { decimals: true })}</Typography>
            <RadioCards
              label="Payment method"
              items={METHODS}
              getKey={(m) => m.key}
              selected={method}
              onSelect={(m) => setMethod(m.key)}
              columns="repeat(3, 1fr)"
              render={(m) => (<><IconTile icon={m.icon} tone="primary" size={40} /><Typography variant="body1" sx={{ fontWeight: 600 }}>{m.label}</Typography></>)}
            />
          </>
        )}
      </DialogContent>
      <DialogActions sx={{ p: 2.5, pt: 0 }}>
        <Button onClick={onClose} disabled={pay.isPending}>Cancel</Button>
        <Button variant="contained" color="secondary" onClick={() => pay.mutate()} disabled={pay.isPending} startIcon={pay.isPending ? <CircularProgress size={16} color="inherit" /> : <MSymbol name="point_of_sale" size={20} />}>Record payment</Button>
      </DialogActions>
    </Dialog>
  );
}

export interface CancelTarget { membershipId: string; customerId: string; customerName: string; planName: string; periodEnd: string }

/** Cancels at period end (default) or immediately (`POST /admin/memberships/:id/cancel`). */
export function CancelMembershipDialog({ target, onClose, onDone, onError }: { target: CancelTarget | null; onClose: () => void; onDone: (message: string) => void; onError: (e: unknown) => void }) {
  const api = useApi();
  const qc = useQueryClient();
  const [mode, setMode] = React.useState<'period_end' | 'now'>('period_end');
  const [reason, setReason] = React.useState('');
  const [seededFor, setSeededFor] = React.useState(target);
  if (target !== seededFor) { setSeededFor(target); if (target) { setMode('period_end'); setReason(''); } }
  const cancel = useMutation({
    mutationFn: () => api.cancelMembership(target!.membershipId, { at_period_end: mode === 'period_end', reason: reason.trim() || undefined }),
    onSuccess: () => { invalidateMemberships(qc, target?.customerId); onDone(mode === 'period_end' ? `${target?.planName} membership ends on ${fmtDate(target!.periodEnd)}` : `${target?.planName} membership cancelled · tier back to Silver`); onClose(); },
    onError,
  });
  return (
    <Dialog open={Boolean(target)} onClose={() => !cancel.isPending && onClose()} aria-labelledby="mcancel-title" fullWidth maxWidth="sm">
      <DialogTitle id="mcancel-title">Cancel {target?.planName} membership?</DialogTitle>
      <DialogContent>
        <Typography variant="body2" color="text.secondary" sx={{ mb: 2 }}>{target?.customerName}: choose whether the benefits run until the paid period ends or stop right away (the tier drops to Silver immediately).</Typography>
        <ToggleButtonGroup exclusive value={mode} onChange={(_e, v: 'period_end' | 'now' | null) => { if (v) setMode(v); }} aria-label="When to cancel" sx={{ bgcolor: tk.surfaceContainerHigh, borderRadius: 999, p: 0.5, gap: 0.5, mb: 2, '& .MuiToggleButton-root': { border: 0, borderRadius: '999px !important', px: 2, py: 0.75, fontWeight: 600, color: tk.onSurfaceVariant, '&.Mui-selected': { bgcolor: tk.secondary, color: tk.onSecondary, '&:hover': { bgcolor: tk.secondary } } } }}>
          <ToggleButton value="period_end"><MSymbol name="event_available" size={18} style={{ marginRight: 6 }} />At period end{target ? ` · ${fmtDate(target.periodEnd)}` : ''}</ToggleButton>
          <ToggleButton value="now"><MSymbol name="block" size={18} style={{ marginRight: 6 }} />Immediately</ToggleButton>
        </ToggleButtonGroup>
        <TextField label="Reason (optional)" value={reason} onChange={(e) => setReason(e.target.value)} fullWidth multiline minRows={2} />
        <Box sx={{ mt: 1.5 }}><Typography variant="caption" color="text.secondary">Audited as <span className="mono">membership.cancel</span>; the customer is notified (membership_cancelled).</Typography></Box>
      </DialogContent>
      <DialogActions sx={{ p: 2.5, pt: 0 }}>
        <Button onClick={onClose} disabled={cancel.isPending}>Keep membership</Button>
        <Button variant="contained" color="error" onClick={() => cancel.mutate()} disabled={cancel.isPending} startIcon={cancel.isPending ? <CircularProgress size={16} color="inherit" /> : <MSymbol name="cancel" size={20} />}>{mode === 'period_end' ? 'Cancel at period end' : 'Cancel now'}</Button>
      </DialogActions>
    </Dialog>
  );
}
