'use client';
import * as React from 'react';
import Link from 'next/link';
import Box from '@mui/material/Box';
import Typography from '@mui/material/Typography';
import Tabs from '@mui/material/Tabs';
import Tab from '@mui/material/Tab';
import Avatar from '@mui/material/Avatar';
import Chip from '@mui/material/Chip';
import Tooltip from '@mui/material/Tooltip';
import type { GridColDef } from '@mui/x-data-grid';
import { useQuery } from '@tanstack/react-query';
import PageHeader from '@/components/layout/PageHeader';
import SectionCard from '@/components/ui/SectionCard';
import AdminGrid from '@/components/ui/AdminGrid';
import MSymbol from '@/components/MSymbol';
import { NavyPill, OutletPill, PeriodPill } from '@/components/ui/Pills';
import { useApi, useAuth } from '@/lib/auth/AuthProvider';
import { useFilters } from '@/lib/filters';
import { useExport } from '@/lib/hooks';
import { can } from '@/lib/rbac';
import { tk } from '@/theme/tokens';
import { initials, num } from '@/lib/format';
import type { StaffPerformanceRow } from '@/lib/types';

const podiumBg = [tk.goldGradient, tk.primaryContainer, tk.surfaceContainerHigh];
const podiumFg = [tk.onGold, tk.onPrimaryContainer, tk.onSurfaceVariant];

export default function PerformancePage() {
  const api = useApi();
  const { role } = useAuth();
  const { outletId, period } = useFilters();
  const { exportCsv, busy } = useExport();
  const q = useQuery({ queryKey: ['staff-performance', outletId, period], queryFn: () => api.staffPerformance({ outlet_id: outletId, period }) });
  const rows = q.data ?? [];
  const columns: GridColDef<StaffPerformanceRow>[] = [
    { field: 'rank', headerName: '#', width: 60, renderCell: (p) => <b>{p.row.rank}</b> },
    { field: 'name', headerName: 'Staff', flex: 1.3, minWidth: 190, renderCell: (p) => (
      <Box sx={{ display: 'flex', alignItems: 'center', gap: 1.25 }}>
        <Avatar sx={{ width: 34, height: 34, fontSize: 13, fontWeight: 700, background: podiumBg[Math.min(2, p.row.rank - 1)], color: podiumFg[Math.min(2, p.row.rank - 1)] }}>{initials(p.row.name)}</Avatar>
        <Box><Typography variant="h6" component="span" sx={{ display: 'block' }}>{p.row.name}</Typography><Typography variant="caption" color="text.secondary">{p.row.outlet_name}</Typography></Box>
      </Box>
    ) },
    { field: 'tasks_completed', headerName: 'Tasks', flex: 0.6, minWidth: 80, align: 'right', headerAlign: 'right' },
    { field: 'avg_cycle_minutes', headerName: 'Avg cycle', flex: 0.7, minWidth: 100, align: 'right', headerAlign: 'right', renderCell: (p) => `${p.row.avg_cycle_minutes} min` },
    { field: 'checklist_compliance_pct', headerName: 'Compliance', flex: 0.8, minWidth: 110, align: 'right', headerAlign: 'right', renderCell: (p) => <Box component="span" sx={{ color: p.row.checklist_compliance_pct >= 95 ? tk.success : tk.onWarningContainer, fontWeight: 600 }}>{p.row.checklist_compliance_pct}%</Box> },
    { field: 'points_period', headerName: 'Points', flex: 0.7, minWidth: 100, align: 'right', headerAlign: 'right', renderCell: (p) => <b>{num(p.row.points_period)}</b> },
    { field: 'delta', headerName: 'Δ', width: 70, align: 'center', headerAlign: 'center', renderCell: (p) => (
      <Box component="span" sx={{ display: 'inline-flex', alignItems: 'center', color: p.row.delta > 0 ? tk.success : p.row.delta < 0 ? tk.error : tk.onSurfaceVariant }} aria-label={`rank change ${p.row.delta}`}>
        <MSymbol name={p.row.delta > 0 ? 'arrow_upward' : p.row.delta < 0 ? 'arrow_downward' : 'remove'} size={18} />{p.row.delta !== 0 && Math.abs(p.row.delta)}
      </Box>
    ) },
    { field: 'badges', headerName: 'Badges', flex: 1.2, minWidth: 160, sortable: false, renderCell: (p) => (
      <Box sx={{ display: 'flex', gap: 0.75 }}>
        {p.row.badges.map((b) => (
          <Tooltip key={b.code} title={b.name}>
            <Box sx={{ width: 30, height: 30, borderRadius: '10px', bgcolor: tk.surfaceContainer, display: 'grid', placeItems: 'center' }} aria-label={b.name}>
              <MSymbol name={b.icon} filled size={18} style={{ color: b.colour }} />
            </Box>
          </Tooltip>
        ))}
      </Box>
    ) },
  ];
  const top = rows.slice(0, 3);
  return (
    <>
      <PageHeader
        title="Staff performance"
        subtitle="Tasks completed, cycle time, checklist compliance and gamification points (ADM-030/031)"
        actions={<><OutletPill /><PeriodPill />{can(role, 'export:csv') && <NavyPill icon="download" onClick={() => void exportCsv('staff_performance', { period })} disabled={busy === 'staff_performance'}>Export CSV</NavyPill>}</>}
      />
      <Tabs value={1} aria-label="Staff sections">
        <Tab label="Users" component={Link} href="/staff" />
        <Tab label="Performance" />
      </Tabs>
      <Box sx={{ display: 'grid', gridTemplateColumns: { xs: '1fr', lg: '1fr 2fr' }, gap: '14px', alignItems: 'start' }}>
        <SectionCard title="Leaderboard" subtitle={period === 'today' ? 'Today' : period === 'week' ? 'This week' : 'This month'}>
          <Box sx={{ display: 'flex', alignItems: 'flex-end', justifyContent: 'center', gap: 2, mt: 1, minHeight: 220 }}>
            {[top[1], top[0], top[2]].map((s, i) => {
              if (!s) return <Box key={i} sx={{ flex: 1 }} />;
              const rank = s.rank - 1;
              const height = rank === 0 ? 120 : rank === 1 ? 88 : 64;
              return (
                <Box key={s.staff_id} sx={{ flex: 1, display: 'flex', flexDirection: 'column', alignItems: 'center', gap: 1 }}>
                  <Box sx={{ position: 'relative' }}>
                    {rank === 0 && <MSymbol name="workspace_premium" filled size={24} style={{ color: tk.gold, position: 'absolute', top: -20, left: '50%', transform: 'translateX(-50%)' }} />}
                    <Avatar sx={{ width: rank === 0 ? 64 : 48, height: rank === 0 ? 64 : 48, background: podiumBg[rank], color: podiumFg[rank], fontWeight: 700, fontSize: rank === 0 ? 20 : 15, boxShadow: rank === 0 ? `0 8px 20px color-mix(in srgb, ${tk.gold} 45%, transparent)` : 'none' }}>{initials(s.name)}</Avatar>
                  </Box>
                  <Typography variant="h6" noWrap>{s.name.split(' ')[0]}</Typography>
                  <Box sx={{ width: '100%', height, borderRadius: '14px 14px 6px 6px', background: rank === 0 ? tk.azureGradient : tk.surfaceContainerHigh, color: rank === 0 ? '#fff' : tk.onSurface, display: 'flex', flexDirection: 'column', alignItems: 'center', justifyContent: 'flex-start', pt: 1 }}>
                    <Typography sx={{ fontWeight: 700, fontSize: 18 }}>{num(s.points_period)}</Typography>
                    <Typography variant="caption" sx={{ opacity: 0.8 }}>pts</Typography>
                  </Box>
                </Box>
              );
            })}
          </Box>
          <Box sx={{ display: 'flex', gap: 0.75, flexWrap: 'wrap', mt: 2 }}>
            <Chip size="small" label="task_completed +25" sx={{ bgcolor: tk.surfaceContainerHigh }} />
            <Chip size="small" label="checklist_compliant +10" sx={{ bgcolor: tk.surfaceContainerHigh }} />
            <Chip size="small" label="verified_first_time +15" sx={{ bgcolor: tk.surfaceContainerHigh }} />
            <Chip size="small" label="p1_on_time +20" sx={{ bgcolor: tk.surfaceContainerHigh }} />
          </Box>
          <Typography variant="caption" color="text.secondary" sx={{ mt: 1 }}>Gamification rules v3 · points ledger is append-only and idempotent (STF-053/054).</Typography>
        </SectionCard>
        <SectionCard flush title="Metrics">
          <Box sx={{ px: 1.5, pb: 1 }}>
            <AdminGrid<StaffPerformanceRow> rows={rows} columns={columns} loading={q.isLoading} getRowId={(r) => r.staff_id} />
          </Box>
        </SectionCard>
      </Box>
    </>
  );
}
