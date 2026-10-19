'use client';
import * as React from 'react';
import Box from '@mui/material/Box';
import FormControlLabel from '@mui/material/FormControlLabel';
import TextField from '@mui/material/TextField';
import ToggleButton from '@mui/material/ToggleButton';
import ToggleButtonGroup from '@mui/material/ToggleButtonGroup';
import Typography from '@mui/material/Typography';
import MSymbol from '@/components/MSymbol';
import M3Switch from '@/components/ui/M3Switch';
import { uuid } from '@/lib/api';
import { rands } from '@/lib/format';
import { tk } from '@/theme/tokens';
import type { CounterPaymentInput, PosPaymentMethod } from '@/lib/types';

export const POS_METHOD_LABEL: Record<PosPaymentMethod, string> = { cash: 'Cash', card_terminal: 'Card terminal', eft: 'EFT' };

/** Short lower-case method word for toasts / chips ("Paid · cash", "Paid · card", "Paid · EFT"). */
export function posMethodShort(method: PosPaymentMethod | null | undefined): string {
  return method === 'card_terminal' ? 'card' : method === 'eft' ? 'EFT' : 'cash';
}

/** The reference field's label per method — an EFT needs the transfer reference (the API refuses `eft` without one). */
export function referenceLabel(method: PosPaymentMethod): string {
  return method === 'eft' ? 'EFT reference' : method === 'card_terminal' ? 'Terminal slip / auth code (optional)' : 'Reference (optional)';
}

export function referencePlaceholder(method: PosPaymentMethod): string {
  return method === 'eft' ? 'e.g. FNB 7731 Nkosi' : method === 'card_terminal' ? 'e.g. 048213' : 'e.g. till 2';
}

/** True when the fields can be sent: everything but `eft` is fine without a reference. */
export function counterPaymentReady(method: PosPaymentMethod, reference: string): boolean {
  return method !== 'eft' || reference.trim().length > 0;
}

const TOGGLE_SX = { bgcolor: tk.surfaceContainerHigh, borderRadius: 999, p: 0.5, gap: 0.5, '& .MuiToggleButton-root': { border: 0, borderRadius: '999px !important', px: 1.75, py: 0.6, fontWeight: 600, color: tk.onSurfaceVariant, gap: 0.75, '&.Mui-selected': { bgcolor: tk.secondary, color: tk.onSecondary, '&:hover': { bgcolor: tk.secondary } } } } as const;

/** Cash / Card terminal / EFT pill toggle; test ids are `<testIdPrefix>-cash|card|eft`. */
export function PosMethodToggle({ value, onChange, labelledBy, testIdPrefix = 'pos-method', disabled }: { value: PosPaymentMethod; onChange: (method: PosPaymentMethod) => void; labelledBy?: string; testIdPrefix?: string; disabled?: boolean }) {
  return (
    <ToggleButtonGroup exclusive value={value} onChange={(_e, v: PosPaymentMethod | null) => { if (v) onChange(v); }} aria-labelledby={labelledBy} disabled={disabled} sx={TOGGLE_SX}>
      <ToggleButton value="cash" data-testid={`${testIdPrefix}-cash`}><MSymbol name="payments" size={18} filled />Cash</ToggleButton>
      <ToggleButton value="card_terminal" data-testid={`${testIdPrefix}-card`}><MSymbol name="credit_card" size={18} filled />Card terminal</ToggleButton>
      <ToggleButton value="eft" data-testid={`${testIdPrefix}-eft`}><MSymbol name="account_balance" size={18} filled />EFT</ToggleButton>
    </ToggleButtonGroup>
  );
}

export interface CounterPaymentState {
  /** "Take payment now" switch. */
  take: boolean;
  setTake: (take: boolean) => void;
  method: PosPaymentMethod;
  setMethod: (method: PosPaymentMethod) => void;
  reference: string;
  setReference: (reference: string) => void;
  /** Idempotency key minted once per `reset()` (per open dialog) so a retried click replays as the same payment. */
  key: string;
  /** False while the switch is on but an EFT has no reference yet — the caller disables its confirm button. */
  ready: boolean;
  /** The `payment` body to send with the check-in / hand-over, `null` while the switch is off. */
  body: CounterPaymentInput | null;
  /** Clears the fields and mints a fresh idempotency key — call when the dialog (re)opens. */
  reset: (take?: boolean) => void;
}

/**
 * State for a counter payment taken together with a check-in or hand-over: method, reference, the "take payment now"
 * switch and one `pos-<uuid>` idempotency key per open form. `amountCents` is the amount still due; the body is
 * `null` while the switch is off so callers can spread it straight into the request.
 */
export function useCounterPayment(amountCents: number, initialTake = false): CounterPaymentState {
  const [take, setTake] = React.useState(initialTake);
  const [method, setMethod] = React.useState<PosPaymentMethod>('cash');
  const [reference, setReference] = React.useState('');
  const [key, setKey] = React.useState(() => `pos-${uuid()}`);
  const reset = React.useCallback((nextTake = false) => { setTake(nextTake); setMethod('cash'); setReference(''); setKey(`pos-${uuid()}`); }, []);
  const ready = !take || counterPaymentReady(method, reference);
  const body = take ? { method, reference: reference.trim() || null, amount_cents: amountCents, idempotency_key: key } : null;
  return { take, setTake, method, setMethod, reference, setReference, key, ready, body, reset };
}

/**
 * "Take payment now · R x" switch that reveals the method toggle and reference field (required for EFT). Used by the
 * check-in dialogs and the hand-over panel; the switch's test id is `switchTestId`, the toggles `<testIdPrefix>-cash|card|eft`
 * and the reference field `<testIdPrefix>-reference`.
 */
export default function CounterPaymentFields({ state, amountCents, switchTestId = 'take-payment', testIdPrefix = 'counter-payment', disabled, hint }: { state: CounterPaymentState; amountCents: number; switchTestId?: string; testIdPrefix?: string; disabled?: boolean; hint?: React.ReactNode }) {
  const labelId = `${testIdPrefix}-method-label`;
  return (
    <Box sx={{ display: 'flex', flexDirection: 'column', gap: 1.25, p: 1.5, borderRadius: '16px', bgcolor: tk.surfaceContainer }} data-testid={`${testIdPrefix}-fields`}>
      <Box sx={{ display: 'flex', alignItems: 'center', justifyContent: 'space-between', gap: 1.5 }}>
        <Box sx={{ minWidth: 0 }}>
          <Typography variant="h6" component="p">Take payment now · {rands(amountCents, { decimals: true })}</Typography>
          <Typography variant="body2" color="text.secondary">{hint ?? 'Records the counter payment first; the receipt is issued by the API and audited under your name.'}</Typography>
        </Box>
        <FormControlLabel control={<M3Switch checked={state.take} onChange={(e) => state.setTake(e.target.checked)} disabled={disabled} slotProps={{ input: { 'data-testid': switchTestId } as React.InputHTMLAttributes<HTMLInputElement> }} />} label="Take payment now" sx={{ m: 0, '& .MuiFormControlLabel-label': { position: 'absolute', width: '1px', height: '1px', overflow: 'hidden', clip: 'rect(0 0 0 0)', whiteSpace: 'nowrap' } }} />
      </Box>
      {state.take && (
        <>
          <Box>
            <Typography component="span" id={labelId} variant="caption" color="text.secondary" sx={{ display: 'block', mb: 0.5 }}>Method</Typography>
            <PosMethodToggle value={state.method} onChange={state.setMethod} labelledBy={labelId} testIdPrefix={testIdPrefix} disabled={disabled} />
          </Box>
          <TextField
            label={referenceLabel(state.method)}
            placeholder={referencePlaceholder(state.method)}
            value={state.reference}
            onChange={(e) => state.setReference(e.target.value)}
            size="small"
            required={state.method === 'eft'}
            helperText={state.method === 'eft' ? 'The transfer reference the customer shows — required for EFT' : undefined}
            disabled={disabled}
            slotProps={{ htmlInput: { maxLength: 64, 'data-testid': `${testIdPrefix}-reference` } }}
          />
        </>
      )}
    </Box>
  );
}
