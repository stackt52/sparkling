'use client';
import * as React from 'react';
import Box from '@mui/material/Box';
import Button from '@mui/material/Button';
import Dialog from '@mui/material/Dialog';
import DialogActions from '@mui/material/DialogActions';
import DialogContent from '@mui/material/DialogContent';
import DialogTitle from '@mui/material/DialogTitle';
import FormControlLabel from '@mui/material/FormControlLabel';
import InputBase from '@mui/material/InputBase';
import Link from '@mui/material/Link';
import TextField from '@mui/material/TextField';
import Typography from '@mui/material/Typography';
import { useMutation, useQueryClient } from '@tanstack/react-query';
import MSymbol from '@/components/MSymbol';
import Tile from '@/components/ui/Tile';
import M3Switch from '@/components/ui/M3Switch';
import RecordPaymentDialog, { type RecordPaymentTarget } from '@/components/payments/RecordPaymentDialog';
import CounterPaymentFields, { useCounterPayment } from '@/components/payments/CounterPaymentFields';
import { useApi, useAuth } from '@/lib/auth/AuthProvider';
import { ApiRequestError } from '@/lib/api';
import { rands } from '@/lib/format';
import { can } from '@/lib/rbac';
import { fonts, tk } from '@/theme/tokens';
import type { PickupIssueResult, PosPayment, WorkOrder } from '@/lib/types';

export const OTP_LENGTH = 5;
const EMPTY = (): string[] => Array.from({ length: OTP_LENGTH }, () => '');

/**
 * Five single-digit boxes for the collection OTP: digits only, auto-advance on input, Backspace steps back, arrow keys
 * move, and pasting (or typing several digits at once) fills the boxes from the current one. `value` always has
 * OTP_LENGTH entries ('' for empty).
 */
export function OtpInput({ value, onChange, onComplete, disabled, error, autoFocus, label = 'Collection OTP' }: { value: string[]; onChange: (digits: string[]) => void; onComplete?: () => void; disabled?: boolean; error?: boolean; autoFocus?: boolean; label?: string }) {
  const refs = React.useRef<(HTMLInputElement | null)[]>([]);
  const focus = (i: number) => refs.current[Math.max(0, Math.min(OTP_LENGTH - 1, i))]?.focus();
  const fill = (from: number, text: string) => {
    const next = value.slice();
    let k = 0;
    for (; k < text.length && from + k < OTP_LENGTH; k++) next[from + k] = text[k];
    onChange(next);
    focus(from + k);
  };
  return (
    <Box role="group" aria-label={label} sx={{ display: 'flex', gap: 1 }} data-testid="otp-input">
      {value.map((d, i) => (
        <InputBase
          key={i}
          inputRef={(el: HTMLInputElement | null) => { refs.current[i] = el; }}
          value={d}
          disabled={disabled}
          autoFocus={autoFocus && i === 0}
          inputProps={{ inputMode: 'numeric', pattern: '[0-9]*', autoComplete: 'one-time-code', 'aria-label': `Digit ${i + 1} of ${OTP_LENGTH}`, 'data-testid': `otp-digit-${i}` }}
          onFocus={(e) => e.target.select()}
          onChange={(e) => {
            const digits = e.target.value.replace(/\D/g, '');
            if (!digits) { const next = value.slice(); next[i] = ''; onChange(next); return; }
            fill(i, digits);
          }}
          onKeyDown={(e) => {
            if (e.key === 'Backspace') {
              e.preventDefault();
              const next = value.slice();
              if (next[i]) next[i] = '';
              else if (i > 0) { next[i - 1] = ''; focus(i - 1); }
              onChange(next);
            } else if (e.key === 'ArrowLeft') { e.preventDefault(); focus(i - 1); }
            else if (e.key === 'ArrowRight') { e.preventDefault(); focus(i + 1); }
            else if (e.key === 'Enter' && value.every(Boolean)) { e.preventDefault(); onComplete?.(); }
          }}
          onPaste={(e) => {
            const text = e.clipboardData.getData('text').replace(/\D/g, '').slice(0, OTP_LENGTH);
            if (!text) return;
            e.preventDefault();
            fill(text.length >= OTP_LENGTH ? 0 : i, text);
          }}
          sx={{
            width: 48, height: 58, borderRadius: '14px', bgcolor: tk.surfaceContainerHigh, color: tk.onSurface,
            border: `2px solid ${error ? tk.error : 'transparent'}`, transition: 'border-color 120ms',
            '&.Mui-focused': { borderColor: error ? tk.error : tk.primary }, '&.Mui-disabled': { opacity: 0.55 },
            '& input': { textAlign: 'center', fontFamily: fonts.mono, fontSize: 24, fontWeight: 700, p: 0, height: '100%' },
          }}
        />
      ))}
    </Box>
  );
}

type Feedback = { kind: 'error' | 'locked' | 'info'; text: string };

/**
 * "Hand over vehicle" for a `verified` work order that has not been collected: the customer reads out the 5-digit
 * collection OTP they received on push / WhatsApp, staff enter it and press **Release keys**
 * (`POST /work-orders/:id/pickup/verify`). Wrong codes show the attempts remaining (5, then the order is locked). While
 * the booking / quotation is unpaid (`amount_due_cents > 0`) the panel offers "Take payment now" — the counter payment
 * (stage `collection`) is sent with the OTP and recorded before it is checked; an unpaid cash-on-collection booking
 * verified without one (409 `payment_due`) switches the fields on and keeps the Record payment shortcut. **Resend OTP**
 * re-sends the same code with the API's cooldown counted down. **Generate new OTP** (`work_order:otp_issue`, manager and
 * up — `POST /work-orders/:id/pickup/issue`) replaces the code when the customer never received it or the order is locked:
 * the new code is shown here to be read out and, unless switched off, sent to the customer again. `onCollected` fires with
 * the `collected_at` stamp and the payment recorded in the same call, if any.
 */
export default function HandoverPanel({ w, onCollected }: { w: WorkOrder; onCollected: (collectedAt: string, payment?: PosPayment | null) => void }) {
  const api = useApi();
  const { role } = useAuth();
  const qc = useQueryClient();
  // Counter payment with the hand-over: offered while something is due; cash-on-collection starts switched on since the keys cannot go before it is paid.
  const canPay = can(role, 'payment:record') && w.amount_due_cents > 0 && (Boolean(w.booking_id) || Boolean(w.quotation_id));
  const pay = useCounterPayment(w.amount_due_cents, canPay && w.payment_method === 'cash');
  const [digits, setDigits] = React.useState<string[]>(EMPTY);
  const [feedback, setFeedback] = React.useState<Feedback | null>(null);
  const [locked, setLocked] = React.useState(false);
  const [cashDue, setCashDue] = React.useState<{ booking_id: string; amount_cents: number } | null>(null);
  const [payTarget, setPayTarget] = React.useState<RecordPaymentTarget | null>(null);
  const [resendUntil, setResendUntil] = React.useState(0);
  const [cooldown, setCooldown] = React.useState(0);
  // "Generate new OTP" (manager+): confirm dialog → the fresh code is shown here until the keys are released.
  const canIssue = can(role, 'work_order:otp_issue');
  const [issueOpen, setIssueOpen] = React.useState(false);
  const [issueReason, setIssueReason] = React.useState('');
  const [issueNotify, setIssueNotify] = React.useState(true);
  const [issued, setIssued] = React.useState<PickupIssueResult | null>(null);
  const otp = digits.join('');
  const complete = digits.every(Boolean);

  // Resend cooldown: a 1 s countdown while `resendUntil` is in the future.
  React.useEffect(() => {
    const tick = () => setCooldown(Math.max(0, Math.ceil((resendUntil - Date.now()) / 1000)));
    tick();
    if (resendUntil <= Date.now()) return;
    const t = setInterval(tick, 1000);
    return () => clearInterval(t);
  }, [resendUntil]);

  const refresh = () => {
    void qc.invalidateQueries({ queryKey: ['work-orders'] });
    void qc.invalidateQueries({ queryKey: ['bookings'] });
    void qc.invalidateQueries({ queryKey: ['booking'] });
    void qc.invalidateQueries({ queryKey: ['activity'] });
  };

  const verify = useMutation({
    mutationFn: () => api.verifyPickup(w.id, otp, canPay && pay.body ? pay.body : null),
    onSuccess: (res) => {
      refresh();
      if (res.payment) {
        void qc.invalidateQueries({ queryKey: ['payments'] });
        void qc.invalidateQueries({ queryKey: ['quotations'] });
      }
      onCollected(res.collected_at, res.payment);
    },
    onError: (e) => {
      const d = (e instanceof ApiRequestError && e.error.details && !Array.isArray(e.error.details) ? e.error.details : {}) as Record<string, unknown>;
      if (e instanceof ApiRequestError && e.error.code === 'invalid_otp') {
        const remaining = Number(d.attempts_remaining ?? 0);
        const isLocked = Boolean(d.locked) || remaining <= 0;
        setLocked(isLocked);
        setDigits(EMPTY());
        setFeedback(isLocked
          ? { kind: 'locked', text: 'Incorrect OTP — attempts exhausted. This work order is locked; a manager must re-issue the collection code.' }
          : { kind: 'error', text: `Incorrect OTP · ${remaining} attempt${remaining === 1 ? '' : 's'} remaining` });
        return;
      }
      if (e instanceof ApiRequestError && e.status === 409) {
        if (d.reason === 'payment_due') {
          setCashDue({ booking_id: String(d.booking_id ?? w.booking_id ?? ''), amount_cents: Number(d.amount_cents ?? 0) });
          if (canPay) pay.setTake(true);
          setFeedback(null);
          return;
        }
        if (d.locked) { setLocked(true); setFeedback({ kind: 'locked', text: `${e.message}. A manager must re-issue the collection code.` }); return; }
        if (typeof d.collected_at === 'string') { refresh(); onCollected(d.collected_at); return; }
      }
      setFeedback({ kind: 'error', text: e instanceof Error ? e.message : String(e) });
    },
  });

  const resend = useMutation({
    mutationFn: () => api.resendPickupOtp(w.id),
    onSuccess: (res) => {
      setResendUntil(Date.now() + (res.retry_after_seconds || 60) * 1000);
      const channels = res.notification.map((n) => (n.channel === 'whatsapp' ? 'WhatsApp' : n.channel)).join(' + ');
      setFeedback({ kind: 'info', text: `OTP re-sent to ${w.customer_name.split(' ')[0]}${channels ? ` on ${channels}` : ''}` });
      void qc.invalidateQueries({ queryKey: ['work-orders'] });
      void qc.invalidateQueries({ queryKey: ['notifications'] });
    },
    onError: (e) => {
      if (e instanceof ApiRequestError && e.status === 429) {
        const m = /in (\d+)\s*s/.exec(e.message);
        setResendUntil(Date.now() + (m ? Number(m[1]) : 60) * 1000);
      }
      setFeedback({ kind: 'error', text: e instanceof Error ? e.message : String(e) });
    },
  });

  const issue = useMutation({
    mutationFn: () => api.issuePickupOtp(w.id, { reason: issueReason.trim() || null, notify: issueNotify }),
    onSuccess: (res) => {
      setIssued(res);
      setIssueOpen(false);
      setIssueReason('');
      setLocked(false);
      setDigits(EMPTY());
      setResendUntil(res.notification.length ? Date.now() + (res.retry_after_seconds || 60) * 1000 : 0);
      const channels = res.notification.map((n) => (n.channel === 'whatsapp' ? 'WhatsApp' : n.channel)).join(' + ');
      setFeedback({ kind: 'info', text: res.notification.length ? `New code issued and sent to ${first} on ${channels}` : `New code issued — read it out to ${first}` });
      void qc.invalidateQueries({ queryKey: ['work-orders'] });
      void qc.invalidateQueries({ queryKey: ['notifications'] });
      void qc.invalidateQueries({ queryKey: ['activity'] });
      void qc.invalidateQueries({ queryKey: ['audit'] });
    },
    onError: (e) => {
      setIssueOpen(false);
      const d = (e instanceof ApiRequestError && e.error.details && !Array.isArray(e.error.details) ? e.error.details : {}) as Record<string, unknown>;
      if (e instanceof ApiRequestError && e.status === 409 && typeof d.collected_at === 'string') { refresh(); onCollected(d.collected_at); return; }
      setFeedback({ kind: 'error', text: e instanceof Error ? e.message : String(e) });
    },
  });

  const submit = () => { if (complete && !locked && !verify.isPending && pay.ready) verify.mutate(); };
  const first = w.customer_name.split(' ')[0];

  return (
    <>
      <Typography variant="h4" component="h3" sx={{ mt: 3, mb: 1 }}>Hand over vehicle</Typography>
      <Tile sx={{ flexDirection: 'column', alignItems: 'stretch', gap: 1.5 }} data-testid="handover-panel">
        <Typography variant="body2" color="text.secondary">
          Enter the 5-digit collection code {first} received by push / WhatsApp when {w.ref} was verified. The keys are released once it matches.
        </Typography>
        <OtpInput value={digits} onChange={(next) => { setDigits(next); if (feedback?.kind === 'error') setFeedback(null); }} onComplete={submit} disabled={locked || verify.isPending} error={feedback?.kind === 'error' || locked} autoFocus />
        {issued && (
          <Tile tone="warning" sx={{ alignItems: 'center', gap: 2 }} data-testid="handover-issued-otp">
            <MSymbol name="key" filled size={22} />
            <Box sx={{ minWidth: 0, flex: 1 }}>
              <Typography variant="subtitle2">New collection code for {first}</Typography>
              <Typography variant="body2">
                Issued {new Date(issued.issued_at).toLocaleTimeString('en-ZA', { hour: '2-digit', minute: '2-digit' })}
                {issued.notification.length ? ` · sent on ${issued.notification.map((n) => (n.channel === 'whatsapp' ? 'WhatsApp' : n.channel)).join(' + ')}` : ' · not sent — read it out to the customer'}. The previous code no longer works.
              </Typography>
            </Box>
            <Typography component="output" aria-label="New collection OTP" sx={{ fontFamily: fonts.sans, fontSize: 32, fontWeight: 700, letterSpacing: '0.25em', fontVariantNumeric: 'tabular-nums', whiteSpace: 'nowrap' }} data-testid="handover-issued-otp-code">
              {issued.otp}
            </Typography>
          </Tile>
        )}
        {feedback && (
          <Typography variant="body2" role={feedback.kind === 'info' ? 'status' : 'alert'} sx={{ fontWeight: 600, color: feedback.kind === 'info' ? tk.success : tk.error }} data-testid="handover-feedback" data-kind={feedback.kind}>
            {feedback.text}
          </Typography>
        )}
        {cashDue && (
          <Tile tone="warning" sx={{ alignItems: 'flex-start' }} data-testid="handover-cash-due">
            <MSymbol name="payments" filled size={22} />
            <Box sx={{ minWidth: 0, flex: 1 }}>
              <Typography variant="subtitle2">Cash on collection — {rands(cashDue.amount_cents, { decimals: true })} is due before the keys are released</Typography>
              <Typography variant="body2">{canPay ? 'Take the payment below together with the OTP, or record it separately first.' : 'Record the counter payment first, then enter the OTP again.'}</Typography>
              <Button size="small" variant="contained" color="secondary" sx={{ mt: 1 }} startIcon={<MSymbol name="point_of_sale" size={18} />} onClick={() => setPayTarget({ kind: 'booking', id: cashDue.booking_id, ref: w.booking_ref ?? w.ref, amount_cents: cashDue.amount_cents, customer_name: w.customer_name, stage: 'collection' })} data-testid="handover-record-payment">
                Record payment · {rands(cashDue.amount_cents)}
              </Button>
            </Box>
          </Tile>
        )}
        {canPay && <CounterPaymentFields state={pay} amountCents={w.amount_due_cents} switchTestId="handover-take-payment" testIdPrefix="handover-payment" disabled={locked || verify.isPending} hint={w.payment_method === 'cash' ? `Cash on collection — ${rands(w.amount_due_cents, { decimals: true })} is due before the keys are released.` : `${w.booking_ref ?? w.quotation_ref ?? w.ref} is unpaid — the payment is recorded with the OTP, before the keys are released.`} />}
        <Box sx={{ display: 'flex', alignItems: 'center', justifyContent: 'space-between', gap: 1.5, flexWrap: 'wrap' }}>
          <Button variant="contained" color="secondary" startIcon={<MSymbol name="key" filled size={20} />} disabled={!complete || locked || verify.isPending || !pay.ready} onClick={submit} data-testid="release-keys">
            {canPay && pay.take ? `Record ${rands(w.amount_due_cents)} & release keys` : 'Release keys'}
          </Button>
          {canIssue && (
            <Button variant="outlined" color="secondary" startIcon={<MSymbol name="autorenew" size={18} />} disabled={issue.isPending || verify.isPending} onClick={() => setIssueOpen(true)} data-testid="handover-issue-otp">
              {locked ? 'Unlock · generate new OTP' : 'Generate new OTP'}
            </Button>
          )}
          <Link component="button" type="button" underline="hover" disabled={cooldown > 0 || resend.isPending} onClick={() => resend.mutate()} sx={{ fontWeight: 600, color: cooldown > 0 ? tk.onSurfaceVariant : tk.primary, cursor: cooldown > 0 ? 'default' : 'pointer' }} aria-disabled={cooldown > 0} data-testid="resend-otp">
            {cooldown > 0 ? `Resend OTP in ${cooldown}s` : resend.isPending ? 'Sending…' : 'Resend OTP'}
          </Link>
        </Box>
      </Tile>
      <Dialog open={issueOpen} onClose={() => { if (!issue.isPending) setIssueOpen(false); }} maxWidth="xs" fullWidth aria-labelledby="issue-otp-title">
        <DialogTitle id="issue-otp-title">Generate a new collection code</DialogTitle>
        <DialogContent sx={{ display: 'flex', flexDirection: 'column', gap: 2, pt: '8px !important' }}>
          <Typography variant="body2" color="text.secondary">
            A fresh 5-digit code replaces the one {first} received when {w.ref} was verified — use it when the code never arrived, was lost, or the order is locked after five wrong attempts. The old code stops working at once and wrong-attempt counting restarts. The new code is shown to you and logged under your name.
          </Typography>
          <TextField label="Reason (optional)" placeholder="e.g. customer never received the WhatsApp" value={issueReason} onChange={(e) => setIssueReason(e.target.value)} inputProps={{ maxLength: 500 }} fullWidth multiline minRows={2} />
          <FormControlLabel control={<M3Switch checked={issueNotify} onChange={(e) => setIssueNotify(e.target.checked)} />} label={issueNotify ? `Also send the new code to ${first} (push / WhatsApp)` : 'Do not send it — I will read it out at the counter'} sx={{ m: 0 }} />
        </DialogContent>
        <DialogActions>
          <Button onClick={() => setIssueOpen(false)} disabled={issue.isPending}>Cancel</Button>
          <Button variant="contained" color="secondary" startIcon={<MSymbol name="key" filled size={18} />} onClick={() => issue.mutate()} disabled={issue.isPending} data-testid="handover-issue-otp-confirm">
            {issue.isPending ? 'Generating…' : 'Generate code'}
          </Button>
        </DialogActions>
      </Dialog>
      <RecordPaymentDialog
        target={payTarget}
        onClose={() => setPayTarget(null)}
        onRecorded={(p) => {
          setCashDue(null);
          pay.setTake(false);
          setFeedback({ kind: 'info', text: `Recorded · receipt ${p.receipt_no ?? p.id} — enter the OTP to release the keys` });
          void qc.invalidateQueries({ queryKey: ['bookings'] });
          void qc.invalidateQueries({ queryKey: ['booking'] });
        }}
      />
    </>
  );
}
