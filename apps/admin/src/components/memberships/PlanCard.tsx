'use client';
import * as React from 'react';
import Box from '@mui/material/Box';
import Paper from '@mui/material/Paper';
import Typography from '@mui/material/Typography';
import Button from '@mui/material/Button';
import Chip from '@mui/material/Chip';
import MSymbol from '@/components/MSymbol';
import Tile from '@/components/ui/Tile';
import StatusChip from '@/components/ui/StatusChip';
import TierChip, { TierDot, tierStyle } from '@/components/ui/TierChip';
import { tk } from '@/theme/tokens';
import { num, rands } from '@/lib/format';
import { PERIOD_LABEL, SELECTION_JOINER, SELECTION_LABEL, discountRule } from './planFormat';
import type { MembershipPlan, PlanGroup } from '@/lib/types';

function GroupBlock({ g }: { g: PlanGroup }) {
  return (
    <Box>
      <Box sx={{ display: 'flex', alignItems: 'center', gap: 1, mb: 0.75 }}>
        <Typography variant="overline" color="text.secondary">{g.name}</Typography>
        <Chip size="small" label={SELECTION_LABEL[g.selection]} sx={{ height: 20, fontSize: 11, bgcolor: tk.surfaceContainerHigh, color: tk.onSurfaceVariant }} />
      </Box>
      <Box sx={{ display: 'flex', flexDirection: 'column', gap: 0.5 }}>
        {g.entitlements.map((e, i) => (
          <React.Fragment key={e.id}>
            {i > 0 && <Typography variant="caption" sx={{ color: tk.onSurfaceVariant, fontWeight: 700, letterSpacing: '0.08em', pl: 1.5 }}>{SELECTION_JOINER[g.selection]}</Typography>}
            <Tile sx={{ minHeight: 48, py: 1, gap: 1.25 }}>
              <Chip size="small" label={e.code} sx={{ fontFamily: 'ui-monospace, Menlo, monospace', fontWeight: 700, bgcolor: tk.surfaceCard, height: 22 }} />
              <Box sx={{ flex: 1, minWidth: 0 }}>
                <Typography variant="body1" sx={{ fontWeight: 600 }}>{e.label}</Typography>
                <Typography variant="caption" color="text.secondary" sx={{ display: 'block' }}>
                  {num(e.quantity)} {PERIOD_LABEL[e.period]} · {e.services.map((s) => s.name).join(' / ') || 'no service mapped'}
                </Typography>
              </Box>
            </Tile>
          </React.Fragment>
        ))}
      </Box>
    </Box>
  );
}

/** Plan card: fee, entitlement groups (OR / AND), discount rule, members and MRR. */
export default function PlanCard({ plan, onEdit, canEdit }: { plan: MembershipPlan; onEdit?: () => void; canEdit?: boolean }) {
  const s = tierStyle[plan.tier];
  return (
    <Paper component="article" aria-labelledby={`plan-${plan.code}-title`} sx={{ p: 0, overflow: 'hidden', display: 'flex', flexDirection: 'column', opacity: plan.is_active ? 1 : 0.7 }}>
      <Box sx={{ background: s.background, color: s.color, px: 2.5, py: 2, display: 'flex', alignItems: 'flex-start', gap: 1.5 }}>
        <TierDot tier={plan.tier} size={14} />
        <Box sx={{ flex: 1, minWidth: 0 }}>
          <Typography id={`plan-${plan.code}-title`} variant="h3" component="h2" sx={{ color: 'inherit', fontSize: 22, lineHeight: 1.2 }}>{plan.name}</Typography>
          {plan.tagline && <Typography variant="body2" sx={{ color: 'inherit', opacity: 0.85 }}>{plan.tagline}</Typography>}
        </Box>
        <Box sx={{ textAlign: 'right' }}>
          <Typography sx={{ fontSize: 26, fontWeight: 700, lineHeight: 1.1, color: 'inherit', letterSpacing: '-0.01em' }}>{rands(plan.monthly_fee_cents)}</Typography>
          <Typography variant="caption" sx={{ color: 'inherit', opacity: 0.85 }}>per month</Typography>
        </Box>
      </Box>
      <Box sx={{ p: 2.5, display: 'flex', flexDirection: 'column', gap: 2, flex: 1 }}>
        <Box sx={{ display: 'flex', gap: 1, flexWrap: 'wrap', alignItems: 'center' }}>
          <TierChip tier={plan.tier} label={`Tier · ${plan.tier.replace(/^\w/, (c) => c.toUpperCase())}`} />
          {!plan.is_active && <StatusChip tone="neutral" label="Inactive · not offered" />}
          <Chip size="small" icon={<MSymbol name="group" size={16} filled />} label={`${num(plan.member_count ?? 0)} member${plan.member_count === 1 ? '' : 's'}`} sx={{ bgcolor: tk.surfaceContainerHigh }} />
          <Chip size="small" icon={<MSymbol name="payments" size={16} filled />} label={`MRR ${rands(plan.mrr_cents ?? 0)}`} sx={{ bgcolor: tk.surfaceContainerHigh }} />
        </Box>
        {plan.groups.map((g) => <GroupBlock key={g.id} g={g} />)}
        <Tile tone={plan.discount_pct > 0 && plan.discount_scope !== 'none' ? 'gold' : 'default'} sx={{ minHeight: 52 }}>
          <MSymbol name="sell" filled size={22} style={{ color: tk.onGold }} />
          <Box sx={{ flex: 1, minWidth: 0 }}>
            <Typography variant="body1" sx={{ fontWeight: 600 }}>{discountRule(plan)}</Typography>
            {plan.discount_note && <Typography variant="caption" color="text.secondary">{plan.discount_note}</Typography>}
          </Box>
        </Tile>
        {canEdit && onEdit && (
          <Button variant="outlined" onClick={onEdit} startIcon={<MSymbol name="edit" size={18} />} sx={{ alignSelf: 'flex-start' }}>Edit plan</Button>
        )}
      </Box>
    </Paper>
  );
}
