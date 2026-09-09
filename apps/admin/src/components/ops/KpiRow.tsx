'use client';
import Box from '@mui/material/Box';
import Paper from '@mui/material/Paper';
import Typography from '@mui/material/Typography';
import Chip from '@mui/material/Chip';
import Skeleton from '@mui/material/Skeleton';
import MSymbol from '@/components/MSymbol';
import { tk } from '@/theme/tokens';
import { num, rands } from '@/lib/format';
import type { Kpis } from '@/lib/types';

function StatCard({ label, value, sub, subTone = 'success', error }: { label: string; value: string; sub: string; subTone?: 'success' | 'neutral' | 'error'; error?: boolean }) {
  const subColor = subTone === 'success' ? tk.success : subTone === 'error' ? tk.onSurfaceVariant : tk.onSurfaceVariant;
  return (
    <Paper sx={{ p: 2.5, display: 'flex', flexDirection: 'column', gap: 1, minHeight: 150, ...(error && { border: `2px solid color-mix(in srgb, ${tk.error} 45%, transparent)` }) }}>
      <Typography variant="subtitle1" sx={{ color: error ? tk.error : tk.onSurfaceVariant, fontWeight: 500, fontSize: 15 }}>{label}</Typography>
      <Typography component="p" sx={{ fontSize: 38, fontWeight: 700, lineHeight: 1.1, color: error ? tk.error : tk.onSurface, letterSpacing: '-0.01em' }}>{value}</Typography>
      <Typography variant="body1" sx={{ color: subColor, fontSize: 14 }}>{sub}</Typography>
    </Paper>
  );
}

export default function KpiRow({ kpis }: { kpis: Kpis | undefined }) {
  if (!kpis) {
    return (
      <Box sx={{ display: 'grid', gridTemplateColumns: { xs: '1fr 1fr', md: 'repeat(3, 1fr)', lg: '1.5fr repeat(4, 1fr)' }, gap: '14px' }}>
        {Array.from({ length: 5 }).map((_, i) => <Skeleton key={i} variant="rounded" height={150} sx={{ borderRadius: '24px' }} />)}
      </Box>
    );
  }
  const periodWord = kpis.period === 'today' ? 'today' : kpis.period === 'week' ? 'this week' : 'this month';
  const ex = kpis.exceptions_breakdown;
  const exParts = [ex.blocked && `${ex.blocked} blocked`, ex.overdue && `${ex.overdue} overdue`, ex.low_stock && `${ex.low_stock} low stock`, ex.failed_payments && `${ex.failed_payments} failed payment${ex.failed_payments > 1 ? 's' : ''}`].filter(Boolean).join(' · ');
  return (
    <Box component="section" aria-label="Key performance indicators" sx={{ display: 'grid', gridTemplateColumns: { xs: '1fr 1fr', md: 'repeat(3, 1fr)', lg: '1.5fr repeat(4, 1fr)' }, gap: '14px' }}>
      <Paper sx={{ p: 2.5, gridColumn: { xs: '1 / -1', md: 'span 1', lg: 'span 1' }, background: tk.heroGradient, border: 'none', color: '#FFFFFF', display: 'flex', flexDirection: 'column', gap: 1, minHeight: 150 }}>
        <Box sx={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', gap: 1 }}>
          <Typography sx={{ color: '#8BD2FF', fontWeight: 500, fontSize: 15 }}>Revenue {periodWord}</Typography>
          <Chip
            size="small"
            icon={<MSymbol name="trending_up" size={16} style={{ color: '#6EE7A0' }} />}
            label={`${kpis.revenue_trend_pct >= 0 ? '+' : ''}${kpis.revenue_trend_pct}%`}
            sx={{ bgcolor: 'rgba(110,231,160,0.18)', color: '#6EE7A0', fontWeight: 700, '& .MuiChip-icon': { color: '#6EE7A0', ml: 1 } }}
          />
        </Box>
        <Typography component="p" sx={{ fontSize: 44, fontWeight: 700, lineHeight: 1.05, letterSpacing: '-0.01em' }}>{rands(kpis.revenue_cents, { decimals: false })}</Typography>
        <Typography sx={{ opacity: 0.85, fontSize: 14 }}>{kpis.revenue_compare_label}</Typography>
      </Paper>
      <StatCard label={`Bookings ${periodWord}`} value={num(kpis.bookings_count)} sub={kpis.period === 'today' ? `${num(kpis.bookings_completed)} completed · ${kpis.bookings_in_service} in service` : `${num(kpis.bookings_completed)} completed · ${kpis.on_time_pct}% on time`} />
      <StatCard label="Active work orders" value={num(kpis.active_work_orders)} sub={`${ex.blocked} blocked · avg cycle ${kpis.avg_cycle_minutes} min`} subTone="neutral" />
      <StatCard label="Completed today" value={num(kpis.completed_today)} sub={`${kpis.cycle_delta_minutes > 0 ? '+' : ''}${kpis.cycle_delta_minutes} min vs 7-day avg`} />
      <StatCard label="Open exceptions" value={num(kpis.exceptions_count)} sub={exParts || 'All clear'} subTone="error" error />
    </Box>
  );
}
