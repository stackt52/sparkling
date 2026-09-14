'use client';
import * as React from 'react';
import Box from '@mui/material/Box';
import Typography from '@mui/material/Typography';
import Button from '@mui/material/Button';
import Dialog from '@mui/material/Dialog';
import DialogTitle from '@mui/material/DialogTitle';
import DialogContent from '@mui/material/DialogContent';
import DialogActions from '@mui/material/DialogActions';
import CircularProgress from '@mui/material/CircularProgress';
import Chip from '@mui/material/Chip';
import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query';
import MSymbol from '@/components/MSymbol';
import IconTile from '@/components/ui/IconTile';
import Tile from '@/components/ui/Tile';
import { LoadingRows } from '@/components/ui/States';
import TierChip, { tierStyle } from '@/components/ui/TierChip';
import RadioCards from '@/components/bookings/walkin/RadioCards';
import { useApi } from '@/lib/auth/AuthProvider';
import { uuid } from '@/lib/api';
import { rands } from '@/lib/format';
import { tk } from '@/theme/tokens';
import type { CounterPaymentMethod, MembershipPlan, MembershipSummary } from '@/lib/types';
import { PERIOD_LABEL, SELECTION_JOINER, discountRule } from './planFormat';

const METHODS: { key: CounterPaymentMethod; label: string; hint: string; icon: string }[] = [
  { key: 'cash', label: 'Cash', hint: 'First month paid at the counter', icon: 'payments' },
  { key: 'card_terminal', label: 'Card terminal', hint: 'Tap / chip on the counter terminal', icon: 'credit_card' },
  { key: 'eft', label: 'EFT', hint: 'Proof of payment seen', icon: 'account_balance' },
];

/** Plan + option picker + counter payment → `POST /admin/customers/:id/membership`. */
export default function EnrolDialog({ customerId, customerName, open, onClose, onEnrolled, onError }: { customerId: string | null; customerName?: string | null; open: boolean; onClose: () => void; onEnrolled: (s: MembershipSummary) => void; onError: (e: unknown) => void }) {
  const api = useApi();
  const qc = useQueryClient();
  const plansQ = useQuery({ queryKey: ['membership-plans'], queryFn: () => api.membershipPlans(), enabled: open });
  const plans = React.useMemo(() => (plansQ.data ?? []).filter((p) => p.is_active), [plansQ.data]);
  const [planCode, setPlanCode] = React.useState<string | null>(null);
  const [selections, setSelections] = React.useState<Record<string, string>>({});
  const [method, setMethod] = React.useState<CounterPaymentMethod>('cash');
  const [opId, setOpId] = React.useState(() => uuid());
  const plan = plans.find((p) => p.code === planCode) ?? null;

  // Reset the picker each time the dialog opens (state derived during render, no effect).
  const [wasOpen, setWasOpen] = React.useState(open);
  if (open !== wasOpen) { setWasOpen(open); if (open) { setPlanCode(null); setSelections({}); setMethod('cash'); setOpId(uuid()); } }
  const pick = (p: MembershipPlan) => {
    setPlanCode(p.code);
    // Default every "choose one" group to its first option.
    setSelections(Object.fromEntries(p.groups.filter((g) => g.selection === 'choose_one' && g.entitlements.length).map((g) => [g.code, g.entitlements[0].code])));
  };
  const complete = Boolean(plan) && plan!.groups.every((g) => g.selection === 'all' || Boolean(selections[g.code]));

  const enrol = useMutation({
    mutationFn: () => api.enrolMembership(customerId!, { plan_code: plan!.code, selections, payment_method: method, client_op_id: opId }),
    onSuccess: (s) => {
      void qc.invalidateQueries({ queryKey: ['customer', customerId] });
      void qc.invalidateQueries({ queryKey: ['customers'] });
      void qc.invalidateQueries({ queryKey: ['customer-membership', customerId] });
      void qc.invalidateQueries({ queryKey: ['memberships'] });
      void qc.invalidateQueries({ queryKey: ['membership-plans'] });
      void qc.invalidateQueries({ queryKey: ['kpis'] });
      void qc.invalidateQueries({ queryKey: ['walkin-customers'] });
      onEnrolled(s);
    },
    onError,
  });

  return (
    <Dialog open={open} onClose={() => !enrol.isPending && onClose()} aria-labelledby="enrol-title" fullWidth maxWidth="md">
      <DialogTitle id="enrol-title">Enrol {customerName ? customerName.split(' ')[0] : 'customer'} in a plan</DialogTitle>
      <DialogContent>
        <Typography variant="body2" color="text.secondary" sx={{ mb: 2 }}>The membership starts now, the first month is paid at the counter and the loyalty tier follows the plan. Renewals are invoiced 3 days before the period ends.</Typography>
        {plansQ.isLoading && <LoadingRows rows={3} height={80} />}
        {plansQ.isSuccess && (
          <RadioCards
            label="Plan"
            items={plans}
            getKey={(p) => p.code}
            selected={planCode}
            onSelect={pick}
            columns={{ xs: '1fr', md: 'repeat(3, 1fr)' }}
            render={(p) => (
              <Box sx={{ display: 'flex', flexDirection: 'column', gap: 0.75, minWidth: 0, flex: 1 }}>
                <Box sx={{ display: 'flex', alignItems: 'center', gap: 1 }}>
                  <Box component="span" aria-hidden sx={{ width: 14, height: 14, borderRadius: '50%', background: tierStyle[p.tier].background, flexShrink: 0 }} />
                  <Typography variant="h5" component="span">{p.name}</Typography>
                </Box>
                <Typography sx={{ fontWeight: 700, fontSize: 20, lineHeight: 1.1 }}>{rands(p.monthly_fee_cents)}<Typography component="span" variant="caption" color="text.secondary"> / month</Typography></Typography>
                <Typography variant="body2" sx={{ color: tk.onSurfaceVariant }}>{p.groups.map((g) => g.entitlements.map((e) => e.label).join(` ${SELECTION_JOINER[g.selection].toLowerCase()} `)).join(' · ')}</Typography>
                <Typography variant="caption" sx={{ color: tk.onSurfaceVariant }}>{discountRule(p)}</Typography>
              </Box>
            )}
          />
        )}
        {plan && (
          <Box sx={{ mt: 2.5, display: 'flex', flexDirection: 'column', gap: 2 }}>
            {plan.groups.map((g) => (
              <Box key={g.id}>
                <Box sx={{ display: 'flex', alignItems: 'center', gap: 1, mb: 1 }}>
                  <Typography variant="h5" component="h3">{g.name}</Typography>
                  <Chip size="small" label={g.selection === 'all' ? 'Included' : 'Choose one'} sx={{ height: 22, bgcolor: tk.surfaceContainerHigh }} />
                </Box>
                {g.selection === 'all' ? (
                  <Box sx={{ display: 'flex', gap: 1, flexWrap: 'wrap' }}>
                    {g.entitlements.map((e) => <Tile key={e.id} tone="success" sx={{ minHeight: 44, py: 0.75 }}><MSymbol name="check_circle" filled size={20} /><Typography variant="body2" sx={{ fontWeight: 600 }}>{e.label} · {PERIOD_LABEL[e.period]}</Typography></Tile>)}
                  </Box>
                ) : (
                  <RadioCards
                    label={g.name}
                    items={g.entitlements}
                    getKey={(e) => e.code}
                    selected={selections[g.code] ?? null}
                    onSelect={(e) => setSelections({ ...selections, [g.code]: e.code })}
                    columns={{ xs: '1fr', md: 'repeat(2, 1fr)' }}
                    render={(e) => (
                      <>
                        <Chip size="small" label={e.code} sx={{ fontFamily: 'ui-monospace, Menlo, monospace', fontWeight: 700, bgcolor: tk.surfaceCard }} />
                        <Box sx={{ minWidth: 0 }}>
                          <Typography variant="body1" sx={{ fontWeight: 600 }}>{e.label}</Typography>
                          <Typography variant="caption" sx={{ color: tk.onSurfaceVariant }}>{PERIOD_LABEL[e.period]} · {e.services.map((s) => s.name).join(' / ')}</Typography>
                        </Box>
                      </>
                    )}
                  />
                )}
              </Box>
            ))}
            <Box>
              <Typography variant="h5" component="h3" sx={{ mb: 1 }}>First month · {rands(plan.monthly_fee_cents)}</Typography>
              <RadioCards
                label="Payment method"
                items={METHODS}
                getKey={(m) => m.key}
                selected={method}
                onSelect={(m) => setMethod(m.key)}
                columns={{ xs: '1fr', md: 'repeat(3, 1fr)' }}
                render={(m) => (
                  <>
                    <IconTile icon={m.icon} tone="primary" size={40} />
                    <Box sx={{ minWidth: 0 }}>
                      <Typography variant="body1" sx={{ fontWeight: 600, display: 'block' }}>{m.label}</Typography>
                      <Typography variant="caption" sx={{ color: tk.onSurfaceVariant }}>{m.hint}</Typography>
                    </Box>
                  </>
                )}
              />
            </Box>
            <Tile sx={{ gap: 1.5 }}>
              <TierChip tier={plan.tier} />
              <Typography variant="body2" color="text.secondary">Tier becomes {plan.name} immediately · benefits apply to the next booking · audited under your name.</Typography>
            </Tile>
          </Box>
        )}
      </DialogContent>
      <DialogActions sx={{ p: 2.5, pt: 0 }}>
        <Button onClick={onClose} disabled={enrol.isPending}>Cancel</Button>
        <Button variant="contained" color="secondary" onClick={() => enrol.mutate()} disabled={!complete || !customerId || enrol.isPending} startIcon={enrol.isPending ? <CircularProgress size={16} color="inherit" /> : <MSymbol name="workspace_premium" size={20} />}>
          {plan ? `Enrol · ${rands(plan.monthly_fee_cents)}` : 'Enrol'}
        </Button>
      </DialogActions>
    </Dialog>
  );
}
