'use client';
import Box from '@mui/material/Box';
import Typography from '@mui/material/Typography';
import Divider from '@mui/material/Divider';
import Avatar from '@mui/material/Avatar';
import Link from 'next/link';
import SectionCard from '@/components/ui/SectionCard';
import LevelBar from '@/components/ui/LevelBar';
import { tk } from '@/theme/tokens';
import { rands } from '@/lib/format';
import type { Kpis } from '@/lib/types';

const tierBg = { gold: tk.goldGradient, silver: tk.primaryContainer, bronze: tk.surfaceContainerHigh };
const tierFg = { gold: tk.onGold, silver: tk.onPrimaryContainer, bronze: tk.onSurfaceVariant };

/** Horizontal bars with azure gradient fills on tonal tracks + "Top staff" chips (README §3d). */
export default function RevenueByOutlet({ kpis }: { kpis: Kpis | undefined }) {
  const rows = kpis?.revenue_by_outlet ?? [];
  const max = Math.max(1, ...rows.map((r) => r.revenue_cents));
  const period = kpis?.period === 'today' ? 'today' : kpis?.period === 'week' ? 'this week' : 'this month';
  return (
    <SectionCard title={`Revenue by outlet · ${period}`} actions={<Typography variant="body2" color="text.secondary">R thousands</Typography>}>
      <Box sx={{ display: 'flex', flexDirection: 'column', gap: 2, mt: 0.5 }}>
        {rows.map((r) => (
          <Box key={r.outlet_id}>
            <Box sx={{ display: 'flex', justifyContent: 'space-between', mb: 0.75 }}>
              <Typography variant="h5" component="span">{r.name}</Typography>
              <Typography variant="h5" component="span" sx={{ color: tk.primary }}>{rands(r.revenue_cents, { compact: true })}</Typography>
            </Box>
            <LevelBar value={r.revenue_cents} max={max} tone="azure" height={14} label={`${r.name} revenue`} />
          </Box>
        ))}
      </Box>
      <Divider sx={{ my: 2.5 }} />
      <Box sx={{ display: 'flex', alignItems: 'center', justifyContent: 'space-between', gap: 2, flexWrap: 'wrap' }}>
        <Typography variant="h4" component="h3">Top staff {period}</Typography>
        <Box sx={{ display: 'flex', gap: 1, flexWrap: 'wrap' }}>
          {(kpis?.top_staff ?? []).map((s) => (
            <Box
              key={s.staff_id}
              component={Link}
              href="/staff/performance"
              sx={{ display: 'inline-flex', alignItems: 'center', gap: 1, pl: 0.5, pr: 2, py: 0.5, borderRadius: 999, bgcolor: tk.surfaceContainer, color: tk.onSurface, fontWeight: 600, fontSize: 14, '&:hover': { bgcolor: tk.surfaceContainerHigh } }}
            >
              <Avatar sx={{ width: 34, height: 34, background: tierBg[s.tier], color: tierFg[s.tier], fontSize: 13, fontWeight: 700 }}>{s.initials}</Avatar>
              {s.name} · {s.points.toLocaleString('en-ZA').replace(/,/g, ' ')}
            </Box>
          ))}
        </Box>
      </Box>
    </SectionCard>
  );
}
