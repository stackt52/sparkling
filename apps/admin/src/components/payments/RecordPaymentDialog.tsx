'use client';
import * as React from 'react';
import Box from '@mui/material/Box';
import Button from '@mui/material/Button';
import Dialog from '@mui/material/Dialog';
import DialogActions from '@mui/material/DialogActions';
import DialogContent from '@mui/material/DialogContent';
import DialogTitle from '@mui/material/DialogTitle';
import TextField from '@mui/material/TextField';
import ToggleButton from '@mui/material/ToggleButton';
import ToggleButtonGroup from '@mui/material/ToggleButtonGroup';
import Typography from '@mui/material/Typography';
import { useMutation, useQueryClient } from '@tanstack/react-query';
import MSymbol from '@/components/MSymbol';
import Toast from '@/components/ui/Toast';
import { useApi } from '@/lib/auth/AuthProvider';
import { uuid } from '@/lib/api';
import { useToast } from '@/lib/hooks';
import { rands } from '@/lib/format';
import { tk } from '@/theme/tokens';
import type { PosPayment, PosPaymentMethod } from '@/lib/types';

/** What is being paid: a booking (`booking_id`) or an accepted quotation (`quotation_id`); the amount is fixed to its total. */
export interface RecordPaymentTarget {
  kind: 'booking' | 'quotation';
  id: string;
  ref: string;
  amount_cents: number;
  customer_name?: string | null;
}

export const POS_METHOD_LABEL: Record<PosPaymentMethod, string> = { cash: 'Cash', card_terminal: 'Card terminal' };

/**
 * "Record payment" — counter attestation of a cash / card-terminal payment (`POST /payments/record`). The amount is
 * shown read-only (the API refuses anything but the booking / quotation total); the idempotency key is minted once
 * per open dialog so a retried click cannot double-record. `onRecorded` receives the payment for the caller's toast
 * ("Recorded · receipt RCP-…") and cache invalidation.
 */
export default function RecordPaymentDialog({ target, onClose, onRecorded }: { target: RecordPaymentTarget | null; onClose: () => void; onRecorded: (payment: PosPayment) => void }) {
  return (
    <Dialog open={Boolean(target)} onClose={onClose} aria-labelledby="record-payment-title" fullWidth maxWidth="xs">
      {target && <RecordPaymentForm target={target} onClose={onClose} onRecorded={onRecorded} />}
    </Dialog>
  );
}

function RecordPaymentForm({ target, onClose, onRecorded }: { target: RecordPaymentTarget; onClose: () => void; onRecorded: (payment: PosPayment) => void }) {
  const api = useApi();
  const qc = useQueryClient();
  const toast = useToast();
  const [method, setMethod] = React.useState<PosPaymentMethod>('cash');
  const [reference, setReference] = React.useState('');
  // One key per dialog instance: a retry after a network error replays as the same payment (200 `duplicate: true`).
  const [key] = React.useState(() => `pos-${uuid()}`);
  const m = useMutation({
    mutationFn: () =>
      api.recordPayment({
        ...(target.kind === 'booking' ? { booking_id: target.id } : { quotation_id: target.id }),
        method,
        reference: reference.trim() || null,
        amount_cents: target.amount_cents,
        idempotency_key: key,
      }),
    onSuccess: (payment) => {
      void qc.invalidateQueries({ queryKey: ['bookings'] });
      void qc.invalidateQueries({ queryKey: ['booking'] });
      void qc.invalidateQueries({ queryKey: ['quotations'] });
      void qc.invalidateQueries({ queryKey: ['quotation'] });
      void qc.invalidateQueries({ queryKey: ['work-orders'] });
      void qc.invalidateQueries({ queryKey: ['payments'] });
      void qc.invalidateQueries({ queryKey: ['activity'] });
      onClose();
      onRecorded(payment);
    },
    onError: (e) => toast.error(e),
  });
  const submit = () => { if (!m.isPending) m.mutate(); };
  return (
    <>
      <DialogTitle id="record-payment-title">Record payment · {target.ref}</DialogTitle>
      <DialogContent sx={{ display: 'flex', flexDirection: 'column', gap: 1.75 }}>
        <Typography variant="body2" color="text.secondary">
          Attests that {target.customer_name ? `${target.customer_name} paid` : 'the customer paid'} at the counter. The receipt number is issued by the API and the payment is audited under your name.
        </Typography>
        <Box>
          <Typography component="span" id="record-payment-method" variant="caption" color="text.secondary" sx={{ display: 'block', mb: 0.5 }}>Method</Typography>
          <ToggleButtonGroup
            exclusive
            value={method}
            onChange={(_e, v: PosPaymentMethod | null) => { if (v) setMethod(v); }}
            aria-labelledby="record-payment-method"
            sx={{ bgcolor: tk.surfaceContainerHigh, borderRadius: 999, p: 0.5, gap: 0.5, '& .MuiToggleButton-root': { border: 0, borderRadius: '999px !important', px: 1.75, py: 0.6, fontWeight: 600, color: tk.onSurfaceVariant, gap: 0.75, '&.Mui-selected': { bgcolor: tk.secondary, color: tk.onSecondary, '&:hover': { bgcolor: tk.secondary } } } }}
          >
            <ToggleButton value="cash" data-testid="record-payment-cash"><MSymbol name="payments" size={18} filled />Cash</ToggleButton>
            <ToggleButton value="card_terminal" data-testid="record-payment-card"><MSymbol name="credit_card" size={18} filled />Card terminal</ToggleButton>
          </ToggleButtonGroup>
        </Box>
        <TextField
          label="Amount"
          value={rands(target.amount_cents, { decimals: true })}
          size="small"
          slotProps={{ input: { readOnly: true }, htmlInput: { 'aria-readonly': true } }}
          helperText={`Fixed to the ${target.kind} total`}
        />
        <TextField
          label={method === 'cash' ? 'Reference (optional)' : 'Terminal slip / auth code (optional)'}
          placeholder={method === 'cash' ? 'e.g. till 2' : 'e.g. 048213'}
          value={reference}
          onChange={(e) => setReference(e.target.value)}
          size="small"
          autoFocus
          slotProps={{ htmlInput: { maxLength: 64 } }}
          onKeyDown={(e) => { if (e.key === 'Enter') { e.preventDefault(); submit(); } }}
        />
      </DialogContent>
      <DialogActions sx={{ p: 2.5, pt: 0 }}>
        <Button onClick={onClose}>Cancel</Button>
        <Button variant="contained" color="secondary" startIcon={<MSymbol name="point_of_sale" size={18} />} disabled={m.isPending} onClick={submit} data-testid="record-payment-confirm">
          Record {rands(target.amount_cents)} · {POS_METHOD_LABEL[method].toLowerCase()}
        </Button>
      </DialogActions>
      <Toast toast={toast.toast} onClose={toast.close} />
    </>
  );
}
