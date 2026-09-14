'use client';
import * as React from 'react';
import Box from '@mui/material/Box';
import Typography from '@mui/material/Typography';
import Button from '@mui/material/Button';
import Chip from '@mui/material/Chip';
import LinearProgress from '@mui/material/LinearProgress';
import MSymbol from '@/components/MSymbol';
import Tile from '@/components/ui/Tile';
import StatusChip from '@/components/ui/StatusChip';
import TierChip, { tierStyle } from '@/components/ui/TierChip';
import { EmptyState } from '@/components/ui/States';
import { tk } from '@/theme/tokens';
import { fmtDate, rands } from '@/lib/format';
import type { MembershipSummary } from '@/lib/types';
import { STATUS_LABEL, STATUS_TONE, allowanceLabel, discountRule, invoiceTone, periodLabel } from './planFormat';

/**
 * Customer-drawer membership block: plan, status, period, allowances and invoices, with the
 * enrol / record-payment / cancel actions handed in by the parent (permission-gated there).
 */
export default function MembershipBlock({ summary, onEnrol, onCancel, onRecordPayment, busy }: {
  summary: MembershipSummary | null | undefined;
  onEnrol?: () => void;
  onCancel?: () => void;
  onRecordPayment?: (invoiceId: string) => void;
  busy?: boolean;
}) {
  if (!summary) return null;
  const { membership: m, plan } = summary;
  if (!m || !plan) {
    return (
      <Box>
        <EmptyState icon="workspace_premium" title="No membership" description="Silver (free) — earns points only. Enrol the customer in Gold, Platinum or Black to include monthly washes and plan discounts." action={onEnrol && <Button variant="contained" color="secondary" onClick={onEnrol} startIcon={<MSymbol name="workspace_premium" size={20} />}>Enrol in a plan</Button>} />
        {summary.invoices.length > 0 && (
          <Box sx={{ mt: 1, display: 'flex', flexDirection: 'column', gap: 1 }}>
            <Typography variant="overline" color="text.secondary">Past invoices</Typography>
            {summary.invoices.map((i) => (
              <Tile key={i.id} sx={{ minHeight: 48, py: 1 }}>
                <Typography variant="body2" className="mono" sx={{ fontWeight: 700 }}>{i.ref}</Typography>
                <Typography variant="body2" color="text.secondary" sx={{ flex: 1 }}>{periodLabel(i.period_start, i.period_end)}</Typography>
                <StatusChip tone={invoiceTone(i)} label={`${i.status} · ${rands(i.amount_cents)}`} />
              </Tile>
            ))}
          </Box>
        )}
      </Box>
    );
  }
  const s = tierStyle[plan.tier];
  const open = summary.open_invoice;
  return (
    <Box sx={{ display: 'flex', flexDirection: 'column', gap: 1.5 }}>
      <Box sx={{ background: s.background, color: s.color, borderRadius: '18px', p: 2, display: 'flex', alignItems: 'flex-start', gap: 1.5 }}>
        <MSymbol name="workspace_premium" filled size={28} />
        <Box sx={{ flex: 1, minWidth: 0 }}>
          <Typography variant="h4" component="p" sx={{ color: 'inherit' }}>{plan.name} membership</Typography>
          <Typography variant="body2" sx={{ color: 'inherit', opacity: 0.85 }}>{summary.benefits_summary || plan.tagline}</Typography>
          <Typography variant="caption" sx={{ color: 'inherit', opacity: 0.85, display: 'block', mt: 0.5 }}><span className="mono">{m.ref}</span> · {rands(plan.monthly_fee_cents)} / month · pays by {m.payment_method.replace('_', ' ')} · member since {fmtDate(m.started_at, 'd MMM yyyy')}</Typography>
        </Box>
        <StatusChip tone={STATUS_TONE[m.status]} label={m.cancel_at_period_end && m.status === 'active' ? `Ends ${fmtDate(m.current_period_end)}` : STATUS_LABEL[m.status]} />
      </Box>

      <Tile sx={{ justifyContent: 'space-between', minHeight: 52 }}>
        <Box sx={{ display: 'flex', alignItems: 'center', gap: 1 }}>
          <MSymbol name="event_repeat" size={22} style={{ color: tk.primary }} />
          <Box>
            <Typography variant="body2" sx={{ fontWeight: 600 }}>Current period · {periodLabel(m.current_period_start, m.current_period_end)}</Typography>
            <Typography variant="caption" color="text.secondary">
              {m.cancel_at_period_end ? `Cancels on ${fmtDate(m.current_period_end)} — benefits until then` : m.status === 'past_due' ? 'Benefits paused until the open invoice is paid' : `Renews ${fmtDate(m.current_period_end)}${open ? ' · invoice open' : ''}`}
            </Typography>
          </Box>
        </Box>
        <TierChip tier={plan.tier} label={`Tier · ${plan.name}`} />
      </Tile>

      <Typography variant="overline" color="text.secondary">Allowances</Typography>
      {summary.allowances.map((a) => {
        const pct = a.quantity ? Math.round((a.remaining / a.quantity) * 100) : 0;
        return (
          <Tile key={a.entitlement_id} sx={{ flexDirection: 'column', alignItems: 'stretch', gap: 0.75, py: 1.25 }}>
            <Box sx={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', gap: 1 }}>
              <Box sx={{ display: 'flex', alignItems: 'center', gap: 1 }}>
                <Chip size="small" label={a.entitlement_code} sx={{ fontFamily: 'ui-monospace, Menlo, monospace', fontWeight: 700, bgcolor: tk.surfaceCard, height: 22 }} />
                <Typography variant="body2" sx={{ fontWeight: 600 }}>{a.label}</Typography>
              </Box>
              <Typography variant="body2" sx={{ fontWeight: 700, fontVariantNumeric: 'tabular-nums' }}>{a.used} used · {a.remaining} left</Typography>
            </Box>
            <LinearProgress variant="determinate" value={pct} aria-label={`${a.label}: ${a.remaining} of ${a.quantity} left`} sx={{ height: 8, borderRadius: 4, bgcolor: tk.track, '& .MuiLinearProgress-bar': { background: s.background, borderRadius: 4 } }} />
            <Typography variant="caption" color="text.secondary">{allowanceLabel(a)}{a.period === 'year' ? ' (membership year)' : ''}</Typography>
          </Tile>
        );
      })}
      <Tile tone={plan.discount_pct > 0 && plan.discount_scope !== 'none' ? 'gold' : 'default'} sx={{ minHeight: 48, py: 1 }}>
        <MSymbol name="sell" filled size={20} style={{ color: tk.onGold }} />
        <Typography variant="body2" sx={{ fontWeight: 600 }}>{discountRule(plan)}{m.status !== 'active' ? ' · paused' : ''}</Typography>
      </Tile>

      <Typography variant="overline" color="text.secondary">Invoices</Typography>
      {open && (
        <Tile tone="warning" sx={{ justifyContent: 'space-between', gap: 1.5 }}>
          <Box sx={{ minWidth: 0 }}>
            <Typography variant="body2" sx={{ fontWeight: 700 }}><span className="mono">{open.ref}</span> · {rands(open.amount_cents)} due {fmtDate(open.due_at)}</Typography>
            <Typography variant="caption">Renewal for {periodLabel(open.period_start, open.period_end)}</Typography>
          </Box>
          {onRecordPayment && <Button size="small" variant="contained" color="secondary" disabled={busy} onClick={() => onRecordPayment(open.id)} startIcon={<MSymbol name="point_of_sale" size={18} />}>Record payment</Button>}
        </Tile>
      )}
      {summary.invoices.filter((i) => i.id !== open?.id).map((i) => (
        <Tile key={i.id} sx={{ minHeight: 48, py: 1 }}>
          <Typography variant="body2" className="mono" sx={{ fontWeight: 700 }}>{i.ref}</Typography>
          <Typography variant="body2" color="text.secondary" sx={{ flex: 1 }}>{periodLabel(i.period_start, i.period_end)}{i.paid_at ? ` · paid ${fmtDate(i.paid_at)}` : ''}</Typography>
          <StatusChip tone={invoiceTone(i)} label={`${i.status} · ${rands(i.amount_cents)}`} />
        </Tile>
      ))}
      {summary.invoices.length === 0 && !open && <Typography variant="body2" color="text.secondary">No invoices yet.</Typography>}

      {onCancel && !m.cancel_at_period_end && (
        <Button variant="outlined" color="error" onClick={onCancel} disabled={busy} startIcon={<MSymbol name="cancel" size={18} />} sx={{ alignSelf: 'flex-start', mt: 0.5 }}>Cancel membership</Button>
      )}
    </Box>
  );
}
