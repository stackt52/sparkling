'use client';
import * as React from 'react';
import Box from '@mui/material/Box';
import Typography from '@mui/material/Typography';
import TextField from '@mui/material/TextField';
import Button from '@mui/material/Button';
import Divider from '@mui/material/Divider';
import FormControlLabel from '@mui/material/FormControlLabel';
import ToggleButton from '@mui/material/ToggleButton';
import ToggleButtonGroup from '@mui/material/ToggleButtonGroup';
import CircularProgress from '@mui/material/CircularProgress';
import { useMutation, useQueryClient } from '@tanstack/react-query';
import { format } from 'date-fns';
import MSymbol from '@/components/MSymbol';
import IconTile from '@/components/ui/IconTile';
import M3Switch from '@/components/ui/M3Switch';
import Tile from '@/components/ui/Tile';
import RadioCards from './RadioCards';
import EnrolDialog from '@/components/memberships/EnrolDialog';
import { SIZE_LABEL } from '@/components/catalogue/pricing';
import { pricing, type WalkInDraft, type WalkInPaymentChoice, type WalkInResult } from './useWalkInDraft';
import { useApi, useAuth } from '@/lib/auth/AuthProvider';
import { ApiRequestError } from '@/lib/api';
import { can } from '@/lib/rbac';
import { fmtTime, rands } from '@/lib/format';
import { tk } from '@/theme/tokens';
import type { WalkInPriority } from '@/lib/types';

const METHODS: { key: WalkInPaymentChoice; label: string; hint: string; icon: string }[] = [
  { key: 'cash', label: 'Cash', hint: 'Recorded under your name · receipt sent by WhatsApp / push', icon: 'payments' },
  { key: 'card_terminal', label: 'Card terminal', hint: 'Tap / chip on the counter terminal · add the slip reference', icon: 'credit_card' },
  { key: 'in_app', label: 'Customer pays in app', hint: 'Nothing recorded now · booking stays pending payment', icon: 'phone_iphone' },
];

function SummaryRow({ label, value, tone }: { label: React.ReactNode; value: React.ReactNode; tone?: 'success' | 'primary' }) {
  return (
    <Box sx={{ display: 'flex', justifyContent: 'space-between', gap: 2, py: 0.6, color: tone === 'success' ? tk.success : tone === 'primary' ? tk.primary : tk.onSurface }}>
      <Typography component="span" variant="body1" sx={{ color: 'inherit', display: 'inline-flex', alignItems: 'center', gap: 0.75 }}>{label}</Typography>
      <Typography component="span" variant="body1" sx={{ color: 'inherit', fontWeight: 600, fontVariantNumeric: 'tabular-nums' }}>{value}</Typography>
    </Box>
  );
}

export default function PaymentStep({ draft, patch, onSuccess, onConflict, onError }: {
  draft: WalkInDraft;
  patch: (p: Partial<WalkInDraft>) => void;
  onSuccess: (r: WalkInResult) => void;
  onConflict: (message: string) => void;
  onError: (e: unknown) => void;
}) {
  const api = useApi();
  const { profile, role } = useAuth();
  const qc = useQueryClient();
  const p = pricing(draft);
  const { discount, total } = p;
  const outletName = draft.created?.booking.outlet.name;
  const [enrolOpen, setEnrolOpen] = React.useState(false);
  const canEnrol = can(role, 'memberships:manage') && !draft.membership?.membership && !draft.created;
  /** Fully covered by the plan (no add-ons) — nothing to record at the counter. */
  const nothingToPay = (draft.created ? draft.created.booking.total_cents : total) === 0;

  const confirm = useMutation({
    mutationFn: async (): Promise<WalkInResult> => {
      // 1) booking (skipped when a previous attempt already created it — same client_op_id either way)
      let created = draft.created;
      if (!created) {
        const res = await api.createWalkInBooking({
          customer_id: draft.customer!.id,
          vehicle_id: draft.vehicle!.id,
          outlet_id: draft.outlet_id!,
          service_id: draft.service!.service_id ?? draft.service!.id,
          walk_in: true,
          vehicle_size: draft.vehicle_size,
          addon_service_ids: draft.addons.map((a) => a.service_id ?? a.id),
          ...(draft.book_now ? {} : { slot_start: draft.slot_start! }),
          notes: draft.notes.trim() || null,
          client_op_id: draft.client_op_id,
          ...(draft.check_in ? { checkin: { bay: draft.bay.trim() || null, priority: draft.priority } } : {}),
        });
        created = { booking: res.booking, work_order: res.work_order ?? res.booking.work_order ?? null };
        patch({ created });
      }
      // 2) in-person payment attestation (amount must equal the server-side total); skipped when the plan covers everything
      let payment = null;
      if (draft.payment !== 'in_app' && created.booking.total_cents > 0) {
        payment = await api.recordPayment({ booking_id: created.booking.id, method: draft.payment, reference: draft.reference.trim() || null, amount_cents: created.booking.total_cents, idempotency_key: draft.payment_key });
      }
      return { booking: created.booking, payment, work_order: created.work_order };
    },
    onSuccess: (r) => {
      void qc.invalidateQueries({ queryKey: ['bookings'] });
      void qc.invalidateQueries({ queryKey: ['kpis'] });
      void qc.invalidateQueries({ queryKey: ['activity'] });
      void qc.invalidateQueries({ queryKey: ['work-orders'] });
      onSuccess(r);
    },
    onError: (e) => {
      if (e instanceof ApiRequestError && e.status === 409 && e.error.code === 'conflict' && !draft.created) onConflict(e.error.message);
      else onError(e);
    },
  });

  const canConfirm = Boolean(draft.customer && draft.vehicle && draft.outlet_id && draft.service && (draft.book_now || draft.slot_start)) && !confirm.isPending;

  return (
    <Box sx={{ display: 'grid', gridTemplateColumns: { xs: '1fr', lg: '1.1fr 1fr' }, gap: 3, alignItems: 'start' }}>
      {/* Order summary (1f) */}
      <Tile sx={{ flexDirection: 'column', alignItems: 'stretch', gap: 0, p: 2.5 }} component="section" aria-labelledby="walkin-order-title">
        <Box sx={{ display: 'flex', gap: 1.5, alignItems: 'center', pb: 2, borderBottom: `1px solid ${tk.outlineVariant}`, mb: 1.5 }}>
          <IconTile icon={draft.service?.icon || 'local_car_wash'} tone="primary" size={52} />
          <Box sx={{ minWidth: 0 }}>
            <Typography id="walkin-order-title" variant="h4" component="h3">{draft.service?.name} · {[draft.vehicle?.make, draft.vehicle?.model].filter(Boolean).join(' ') || draft.vehicle?.registration_no}</Typography>
            <Typography variant="body2" color="text.secondary">
              {draft.customer?.full_name} · {draft.book_now ? 'Now (walk-in)' : draft.slot_start ? `${format(new Date(draft.slot_start), 'EEE d MMM')}, ${fmtTime(draft.slot_start)}` : ''}
            </Typography>
          </Box>
        </Box>
        <SummaryRow label={<>{draft.service?.name}<Typography component="span" variant="body2" sx={{ color: tk.onSurfaceVariant }}> · {SIZE_LABEL[p.size]}{draft.service?.pricing_mode === 'from' ? ' · from' : ''}</Typography></>} value={rands(p.base, { decimals: true })} />
        {p.addons.map((a) => <SummaryRow key={a.service_id} label={<><MSymbol name="add_circle" size={16} filled />{a.name}</>} value={rands(a.cents, { decimals: true })} />)}
        {discount > 0 && p.discount_label && <SummaryRow label={<><MSymbol name={p.member?.benefit === 'included' ? 'workspace_premium' : 'sell'} size={16} filled />{p.discount_label}</>} value={`− ${rands(discount, { decimals: true })}`} tone="success" />}
        {p.vat_mode === 'excl' && <SummaryRow label="VAT 15 % (price excl. VAT)" value={rands(p.vat, { decimals: true })} />}
        <Divider sx={{ my: 1, borderStyle: 'dashed' }} />
        <Box sx={{ display: 'flex', justifyContent: 'space-between', alignItems: 'baseline', pt: 0.5 }} aria-live="polite">
          <Typography variant="h4" component="p">Total due{p.vat_mode === 'incl' && <Typography component="span" variant="body2" color="text.secondary"> · incl. VAT</Typography>}</Typography>
          <Typography component="p" sx={{ color: tk.primary, fontWeight: 700, fontSize: 26, fontVariantNumeric: 'tabular-nums' }}>{rands(total, { decimals: true })}</Typography>
        </Box>
        {draft.created && (
          <Typography variant="body2" sx={{ mt: 1.5, color: tk.onSurfaceVariant }}>
            Booking <span className="mono" style={{ fontWeight: 700 }}>{draft.created.booking.ref}</span> is already created{outletName ? ` at ${outletName}` : ''} — confirming again only records the payment.
          </Typography>
        )}
        {p.member?.benefit === 'included' && (
          <Typography variant="body2" sx={{ mt: 1, color: tk.onSurfaceVariant, display: 'flex', gap: 0.75, alignItems: 'center' }}>
            <MSymbol name="info" size={16} />
            Base covered by the plan{p.addons.length ? ' — add-ons are still charged' : ''}; the allowance is used when the booking is created and released if it is cancelled.
          </Typography>
        )}
        {canEnrol && (
          <Tile tone="gold" sx={{ mt: 2, justifyContent: 'space-between', gap: 1.5 }}>
            <Box sx={{ minWidth: 0 }}>
              <Typography variant="body1" sx={{ fontWeight: 600 }}>Not a member yet</Typography>
              <Typography variant="body2" sx={{ color: tk.onSurfaceVariant }}>Gold from R 295 / month includes 4 Sparkling Washes — this wash would be included.</Typography>
            </Box>
            <Button size="small" variant="contained" color="secondary" onClick={() => setEnrolOpen(true)} startIcon={<MSymbol name="workspace_premium" size={18} />} sx={{ whiteSpace: 'nowrap' }}>Enrol in a plan</Button>
          </Tile>
        )}
        <TextField label="Notes for the team (optional)" value={draft.notes} onChange={(e) => patch({ notes: e.target.value })} multiline minRows={2} sx={{ mt: 2.5, '& .MuiOutlinedInput-root': { bgcolor: tk.surfaceCard } }} disabled={Boolean(draft.created)} />
      </Tile>
      <EnrolDialog
        customerId={draft.customer?.id ?? null}
        customerName={draft.customer?.full_name}
        open={enrolOpen}
        onClose={() => setEnrolOpen(false)}
        onEnrolled={(s) => {
          setEnrolOpen(false);
          const plan = s.plan;
          patch({ membership: s, ...(draft.customer && plan ? { customer: { ...draft.customer, loyalty: { ...(draft.customer.loyalty ?? { balance_points: 0, discount_pct: 0 }), tier: plan.tier, discount_pct: 0, plan_code: plan.code, plan_name: plan.name, included_remaining: s.allowances.filter((a) => a.period === 'month').reduce((sum, a) => sum + a.remaining, 0) } } } : {}) });
        }}
        onError={onError}
      />

      <Box sx={{ display: 'flex', flexDirection: 'column', gap: 3 }}>
        {nothingToPay ? (
          <Tile tone="success" sx={{ gap: 1.5, py: 2 }} role="status">
            <MSymbol name="workspace_premium" filled size={26} />
            <Box>
              <Typography variant="h5" component="h3">Nothing to pay</Typography>
              <Typography variant="body2" sx={{ color: 'inherit', opacity: 0.85 }}>{p.discount_label ?? 'Covered by the plan'} — no counter payment is recorded; the allowance is redeemed on confirm.</Typography>
            </Box>
          </Tile>
        ) : (
        <Box>
          <Typography variant="h4" component="h3" sx={{ mb: 1.5 }}>Payment method</Typography>
          <RadioCards
            label="Payment method"
            items={METHODS}
            getKey={(m) => m.key}
            selected={draft.payment}
            onSelect={(m) => patch({ payment: m.key })}
            render={(m) => (
              <>
                <IconTile icon={m.icon} tone={m.key === 'in_app' ? 'neutral' : 'primary'} size={44} />
                <Box sx={{ minWidth: 0 }}>
                  <Typography variant="h5" component="span" sx={{ display: 'block' }}>{m.label}</Typography>
                  <Typography variant="body2" component="span" sx={{ color: tk.onSurfaceVariant }}>{m.hint}</Typography>
                </Box>
              </>
            )}
          />
          {draft.payment === 'card_terminal' && (
            <TextField label="Terminal reference (optional)" placeholder="e.g. slip 4471" value={draft.reference} onChange={(e) => patch({ reference: e.target.value })} fullWidth sx={{ mt: 1.5 }} />
          )}
        </Box>
        )}

        <Box>
          <Typography variant="h4" component="h3" sx={{ mb: 1.5 }}>Check-in</Typography>
          <Tile sx={{ justifyContent: 'space-between', mb: 1.5 }}>
            <Box>
              <Typography variant="h6" component="p">Check in now</Typography>
              <Typography variant="body2" color="text.secondary">Creates the work order and checklist task immediately</Typography>
            </Box>
            <FormControlLabel control={<M3Switch checked={draft.check_in} onChange={(e) => patch({ check_in: e.target.checked })} disabled={Boolean(draft.created)} />} label="Check in now" sx={{ m: 0, '& .MuiFormControlLabel-label': { position: 'absolute', width: '1px', height: '1px', overflow: 'hidden', clip: 'rect(0 0 0 0)', whiteSpace: 'nowrap' } }} />
          </Tile>
          {draft.check_in && (
            <Box sx={{ display: 'grid', gridTemplateColumns: { xs: '1fr', sm: '1fr auto' }, gap: 1.5, alignItems: 'center' }}>
              <TextField label="Bay" placeholder="e.g. Bay 2" value={draft.bay} onChange={(e) => patch({ bay: e.target.value })} disabled={Boolean(draft.created)} />
              <Box>
                <Typography component="span" id="walkin-priority-label" variant="caption" color="text.secondary" sx={{ display: 'block', mb: 0.5 }}>Priority</Typography>
                <ToggleButtonGroup
                  exclusive
                  value={draft.priority}
                  onChange={(_e, v: WalkInPriority | null) => { if (v) patch({ priority: v }); }}
                  aria-labelledby="walkin-priority-label"
                  disabled={Boolean(draft.created)}
                  sx={{ bgcolor: tk.surfaceContainerHigh, borderRadius: 999, p: 0.5, gap: 0.5, '& .MuiToggleButton-root': { border: 0, borderRadius: '999px !important', px: 1.75, py: 0.6, fontWeight: 600, color: tk.onSurfaceVariant, '&.Mui-selected': { bgcolor: tk.secondary, color: tk.onSecondary, '&:hover': { bgcolor: tk.secondary } } } }}
                >
                  <ToggleButton value={1}>P1 · urgent</ToggleButton>
                  <ToggleButton value={2}>P2</ToggleButton>
                  <ToggleButton value={3}>P3</ToggleButton>
                </ToggleButtonGroup>
              </Box>
            </Box>
          )}
        </Box>

        <Typography variant="body2" color="text.secondary" sx={{ display: 'flex', gap: 1, alignItems: 'flex-start' }}>
          <MSymbol name="shield" size={18} />
          <span>{nothingToPay ? 'The wash is included in the membership; the booking is confirmed as paid by the plan and the customer gets the confirmation by WhatsApp / push.' : draft.payment === 'in_app' ? 'The customer pays from the Sparkling app; the booking shows “pending payment” until then.' : `Cash and terminal payments are attested by ${profile?.full_name ?? 'you'} and audited. The customer gets the receipt by WhatsApp / push.`}</span>
        </Typography>

        <Button
          variant="contained"
          size="large"
          fullWidth
          disabled={!canConfirm}
          onClick={() => confirm.mutate()}
          startIcon={confirm.isPending ? <CircularProgress size={18} color="inherit" /> : <MSymbol name="check_circle" size={22} filled />}
          sx={{ py: 1.5, fontSize: 16 }}
        >
          {confirm.isPending ? 'Confirming…' : nothingToPay ? `Confirm walk-in · ${p.member?.benefit === 'included' ? `included in ${p.member.plan_name}` : 'nothing to pay'}` : `Confirm walk-in · ${rands(draft.created?.booking.total_cents ?? total, { decimals: true })}`}
        </Button>
      </Box>
    </Box>
  );
}
