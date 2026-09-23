'use client';
import * as React from 'react';
import Box from '@mui/material/Box';
import Button from '@mui/material/Button';
import InputBase from '@mui/material/InputBase';
import Link from '@mui/material/Link';
import Typography from '@mui/material/Typography';
import { useMutation, useQueryClient } from '@tanstack/react-query';
import MSymbol from '@/components/MSymbol';
import Tile from '@/components/ui/Tile';
import RecordPaymentDialog, { type RecordPaymentTarget } from '@/components/payments/RecordPaymentDialog';
import { useApi } from '@/lib/auth/AuthProvider';
import { ApiRequestError } from '@/lib/api';
import { rands } from '@/lib/format';
import { fonts, tk } from '@/theme/tokens';
import type { WorkOrder } from '@/lib/types';

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
 * (`POST /work-orders/:id/pickup/verify`). Wrong codes show the attempts remaining (5, then the order is locked);
 * an unpaid cash-on-collection booking (409 `payment_due`) surfaces a Record payment shortcut; **Resend OTP** re-sends
 * the same code with the API's cooldown counted down. `onCollected` fires with the `collected_at` stamp.
 */
export default function HandoverPanel({ w, onCollected }: { w: WorkOrder; onCollected: (collectedAt: string) => void }) {
  const api = useApi();
  const qc = useQueryClient();
  const [digits, setDigits] = React.useState<string[]>(EMPTY);
  const [feedback, setFeedback] = React.useState<Feedback | null>(null);
  const [locked, setLocked] = React.useState(false);
  const [cashDue, setCashDue] = React.useState<{ booking_id: string; amount_cents: number } | null>(null);
  const [payTarget, setPayTarget] = React.useState<RecordPaymentTarget | null>(null);
  const [resendUntil, setResendUntil] = React.useState(0);
  const [cooldown, setCooldown] = React.useState(0);
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
    mutationFn: () => api.verifyPickup(w.id, otp),
    onSuccess: (res) => {
      refresh();
      onCollected(res.collected_at);
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

  const submit = () => { if (complete && !locked && !verify.isPending) verify.mutate(); };
  const first = w.customer_name.split(' ')[0];

  return (
    <>
      <Typography variant="h4" component="h3" sx={{ mt: 3, mb: 1 }}>Hand over vehicle</Typography>
      <Tile sx={{ flexDirection: 'column', alignItems: 'stretch', gap: 1.5 }} data-testid="handover-panel">
        <Typography variant="body2" color="text.secondary">
          Enter the 5-digit collection code {first} received by push / WhatsApp when {w.ref} was verified. The keys are released once it matches.
        </Typography>
        <OtpInput value={digits} onChange={(next) => { setDigits(next); if (feedback?.kind === 'error') setFeedback(null); }} onComplete={submit} disabled={locked || verify.isPending} error={feedback?.kind === 'error' || locked} autoFocus />
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
              <Typography variant="body2">Record the counter payment first, then enter the OTP again.</Typography>
              <Button size="small" variant="contained" color="secondary" sx={{ mt: 1 }} startIcon={<MSymbol name="point_of_sale" size={18} />} onClick={() => setPayTarget({ kind: 'booking', id: cashDue.booking_id, ref: w.booking_ref ?? w.ref, amount_cents: cashDue.amount_cents, customer_name: w.customer_name })} data-testid="handover-record-payment">
                Record payment · {rands(cashDue.amount_cents)}
              </Button>
            </Box>
          </Tile>
        )}
        <Box sx={{ display: 'flex', alignItems: 'center', justifyContent: 'space-between', gap: 1.5, flexWrap: 'wrap' }}>
          <Button variant="contained" color="secondary" startIcon={<MSymbol name="key" filled size={20} />} disabled={!complete || locked || verify.isPending} onClick={submit} data-testid="release-keys">
            Release keys
          </Button>
          <Link component="button" type="button" underline="hover" disabled={cooldown > 0 || resend.isPending} onClick={() => resend.mutate()} sx={{ fontWeight: 600, color: cooldown > 0 ? tk.onSurfaceVariant : tk.primary, cursor: cooldown > 0 ? 'default' : 'pointer' }} aria-disabled={cooldown > 0} data-testid="resend-otp">
            {cooldown > 0 ? `Resend OTP in ${cooldown}s` : resend.isPending ? 'Sending…' : 'Resend OTP'}
          </Link>
        </Box>
      </Tile>
      <RecordPaymentDialog
        target={payTarget}
        onClose={() => setPayTarget(null)}
        onRecorded={(p) => {
          setCashDue(null);
          setFeedback({ kind: 'info', text: `Recorded · receipt ${p.receipt_no ?? p.id} — enter the OTP to release the keys` });
          void qc.invalidateQueries({ queryKey: ['bookings'] });
          void qc.invalidateQueries({ queryKey: ['booking'] });
        }}
      />
    </>
  );
}
