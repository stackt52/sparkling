'use client';
import * as React from 'react';
import Box from '@mui/material/Box';
import Button from '@mui/material/Button';
import Dialog from '@mui/material/Dialog';
import DialogActions from '@mui/material/DialogActions';
import DialogContent from '@mui/material/DialogContent';
import DialogTitle from '@mui/material/DialogTitle';
import TextField from '@mui/material/TextField';
import Typography from '@mui/material/Typography';
import { useMutation, useQueryClient } from '@tanstack/react-query';
import MSymbol from '@/components/MSymbol';
import Toast from '@/components/ui/Toast';
import { POS_METHOD_LABEL, PosMethodToggle, counterPaymentReady, referenceLabel, referencePlaceholder } from '@/components/payments/CounterPaymentFields';
import { useApi } from '@/lib/auth/AuthProvider';
import { uuid } from '@/lib/api';
import { useToast } from '@/lib/hooks';
import { rands } from '@/lib/format';
import type { PaymentStage, PosPayment, PosPaymentMethod } from '@/lib/types';

/** What is being paid: a booking (`booking_id`) or an accepted quotation (`quotation_id`); the amount is fixed to its total. */
export interface RecordPaymentTarget {
  kind: 'booking' | 'quotation';
  id: string;
  ref: string;
  amount_cents: number;
  customer_name?: string | null;
  /** Where in the job the payment is taken (`checkin` / `collection`); the API infers it from the booking status when omitted. */
  stage?: PaymentStage;
}

export { POS_METHOD_LABEL };

/**
 * "Record payment" — counter attestation of a cash / card-terminal / EFT payment (`POST /payments/record`). The amount
 * is shown read-only (the API refuses anything but the booking / quotation total); an EFT needs its transfer reference;
 * the idempotency key is minted once per open dialog so a retried click cannot double-record. `stage` (or
 * `target.stage`) tags the payment as taken at check-in / collection. `onRecorded` receives the payment for the
 * caller's toast ("Recorded · receipt RCP-…") and cache invalidation.
 */
export default function RecordPaymentDialog({ target, stage, onClose, onRecorded }: { target: RecordPaymentTarget | null; stage?: PaymentStage; onClose: () => void; onRecorded: (payment: PosPayment) => void }) {
  return (
    <Dialog open={Boolean(target)} onClose={onClose} aria-labelledby="record-payment-title" fullWidth maxWidth="xs">
      {target && <RecordPaymentForm target={target} stage={stage ?? target.stage} onClose={onClose} onRecorded={onRecorded} />}
    </Dialog>
  );
}

function RecordPaymentForm({ target, stage, onClose, onRecorded }: { target: RecordPaymentTarget; stage?: PaymentStage; onClose: () => void; onRecorded: (payment: PosPayment) => void }) {
  const api = useApi();
  const qc = useQueryClient();
  const toast = useToast();
  const [method, setMethod] = React.useState<PosPaymentMethod>('cash');
  const [reference, setReference] = React.useState('');
  // One key per dialog instance: a retry after a network error replays as the same payment (200 `duplicate: true`).
  const [key] = React.useState(() => `pos-${uuid()}`);
  const ready = counterPaymentReady(method, reference);
  const m = useMutation({
    mutationFn: () =>
      api.recordPayment({
        ...(target.kind === 'booking' ? { booking_id: target.id } : { quotation_id: target.id }),
        method,
        reference: reference.trim() || null,
        amount_cents: target.amount_cents,
        idempotency_key: key,
        ...(stage ? { stage } : {}),
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
  const submit = () => { if (!m.isPending && ready) m.mutate(); };
  return (
    <>
      <DialogTitle id="record-payment-title">Record payment · {target.ref}</DialogTitle>
      <DialogContent sx={{ display: 'flex', flexDirection: 'column', gap: 1.75 }}>
        <Typography variant="body2" color="text.secondary">
          Attests that {target.customer_name ? `${target.customer_name} paid` : 'the customer paid'} at the counter. The receipt number is issued by the API and the payment is audited under your name.
        </Typography>
        <Box>
          <Typography component="span" id="record-payment-method" variant="caption" color="text.secondary" sx={{ display: 'block', mb: 0.5 }}>Method</Typography>
          <PosMethodToggle value={method} onChange={setMethod} labelledBy="record-payment-method" testIdPrefix="record-payment" />
        </Box>
        <TextField
          label="Amount"
          value={rands(target.amount_cents, { decimals: true })}
          size="small"
          slotProps={{ input: { readOnly: true }, htmlInput: { 'aria-readonly': true } }}
          helperText={`Fixed to the ${target.kind} total`}
        />
        <TextField
          label={referenceLabel(method)}
          placeholder={referencePlaceholder(method)}
          value={reference}
          onChange={(e) => setReference(e.target.value)}
          size="small"
          autoFocus
          required={method === 'eft'}
          helperText={method === 'eft' ? 'The transfer reference the customer shows — required for EFT' : undefined}
          slotProps={{ htmlInput: { maxLength: 64, 'data-testid': 'record-payment-reference' } }}
          onKeyDown={(e) => { if (e.key === 'Enter') { e.preventDefault(); submit(); } }}
        />
      </DialogContent>
      <DialogActions sx={{ p: 2.5, pt: 0 }}>
        <Button onClick={onClose}>Cancel</Button>
        <Button variant="contained" color="secondary" startIcon={<MSymbol name="point_of_sale" size={18} />} disabled={m.isPending || !ready} onClick={submit} data-testid="record-payment-confirm">
          Record {rands(target.amount_cents)} · {POS_METHOD_LABEL[method].toLowerCase()}
        </Button>
      </DialogActions>
      <Toast toast={toast.toast} onClose={toast.close} />
    </>
  );
}
