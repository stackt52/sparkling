'use client';
import * as React from 'react';
import Button from '@mui/material/Button';
import Menu from '@mui/material/Menu';
import MenuItem from '@mui/material/MenuItem';
import ListItemIcon from '@mui/material/ListItemIcon';
import Chip from '@mui/material/Chip';
import Box from '@mui/material/Box';
import { useQuery } from '@tanstack/react-query';
import MSymbol from '@/components/MSymbol';
import { tk } from '@/theme/tokens';
import { useApi } from '@/lib/auth/AuthProvider';
import { useFilters } from '@/lib/filters';
import type { Period } from '@/lib/types';
import { format } from 'date-fns';

/** Tonal pill button (surfaceContainerHigh) used for header filters. */
export function TonalPill({ icon, children, endIcon = 'unfold_more', ...rest }: { icon?: string; children: React.ReactNode; endIcon?: string | null } & Omit<React.ComponentProps<typeof Button>, 'children'>) {
  return (
    <Button
      variant="text"
      startIcon={icon ? <MSymbol name={icon} filled size={20} /> : undefined}
      endIcon={endIcon ? <MSymbol name={endIcon} size={18} /> : undefined}
      sx={{ bgcolor: tk.surfaceContainerHigh, color: tk.onSurface, px: 2.25, fontWeight: 600, '&:hover': { bgcolor: tk.outline } }}
      {...rest}
    >
      {children}
    </Button>
  );
}

/** Navy pill (secondary) used for primary header actions like Export CSV. */
export function NavyPill({ icon, children, ...rest }: { icon?: string; children: React.ReactNode } & Omit<React.ComponentProps<typeof Button>, 'children'>) {
  return (
    <Button variant="contained" color="secondary" startIcon={icon ? <MSymbol name={icon} size={20} /> : undefined} sx={{ px: 2.5 }} {...rest}>
      {children}
    </Button>
  );
}

export function OutletPill() {
  const api = useApi();
  const { outletId, setOutletId } = useFilters();
  const { data: outlets } = useQuery({ queryKey: ['outlets'], queryFn: () => api.listOutlets() });
  const [anchor, setAnchor] = React.useState<null | HTMLElement>(null);
  const current = outlets?.find((o) => o.id === outletId);
  const label = outletId ? (current?.name ?? 'Outlet') : 'All outlets';
  return (
    <>
      <TonalPill icon="storefront" onClick={(e) => setAnchor(e.currentTarget)} aria-haspopup="menu" aria-expanded={Boolean(anchor)} aria-label={`Outlet filter: ${label}`}>
        {label}
      </TonalPill>
      <Menu anchorEl={anchor} open={Boolean(anchor)} onClose={() => setAnchor(null)}>
        <MenuItem selected={!outletId} onClick={() => { setOutletId(null); setAnchor(null); }}>
          <ListItemIcon><MSymbol name="apps" size={20} /></ListItemIcon>All outlets
        </MenuItem>
        {(outlets ?? []).map((o) => (
          <MenuItem key={o.id} selected={o.id === outletId} onClick={() => { setOutletId(o.id); setAnchor(null); }}>
            <ListItemIcon><MSymbol name="storefront" size={20} filled={o.id === outletId} /></ListItemIcon>{o.name}
          </MenuItem>
        ))}
      </Menu>
    </>
  );
}

const periodLabels: Record<Period, string> = { today: `Today · ${format(new Date(), 'd MMM')}`, week: 'This week', month: 'This month' };

export function PeriodPill() {
  const { period, setPeriod } = useFilters();
  const [anchor, setAnchor] = React.useState<null | HTMLElement>(null);
  return (
    <>
      <TonalPill icon="calendar_today" endIcon={null} onClick={(e) => setAnchor(e.currentTarget)} aria-haspopup="menu" aria-expanded={Boolean(anchor)} aria-label={`Period: ${periodLabels[period]}`}>
        {periodLabels[period]}
      </TonalPill>
      <Menu anchorEl={anchor} open={Boolean(anchor)} onClose={() => setAnchor(null)}>
        {(Object.keys(periodLabels) as Period[]).map((p) => (
          <MenuItem key={p} selected={p === period} onClick={() => { setPeriod(p); setAnchor(null); }}>{periodLabels[p]}</MenuItem>
        ))}
      </Menu>
    </>
  );
}

/** "Live · updated hh:mm:ss" / "Polling" chip. */
export function LiveChip({ updatedAt, mode }: { updatedAt: Date | null; mode: 'realtime' | 'polling' | 'demo' }) {
  const [, force] = React.useReducer((x: number) => x + 1, 0);
  React.useEffect(() => {
    const t = setInterval(force, 1000);
    return () => clearInterval(t);
  }, []);
  const label = updatedAt ? `Live · updated ${format(updatedAt, 'HH:mm:ss')}` : 'Connecting…';
  return (
    <Box component="span" sx={{ display: 'inline-flex', alignItems: 'center', gap: 0.75, color: tk.onSurfaceVariant, fontSize: 14 }} aria-live="off" title={mode === 'realtime' ? 'Supabase realtime' : mode === 'polling' ? 'Polling every 30 s' : 'Demo live tick'}>
      <Box component="span" sx={{ width: 8, height: 8, borderRadius: '50%', bgcolor: tk.success, boxShadow: `0 0 0 3px color-mix(in srgb, ${tk.success} 25%, transparent)` }} />
      {label}
    </Box>
  );
}

export function LegendDot({ color, label }: { color: string; label: string }) {
  return (
    <Box component="span" sx={{ display: 'inline-flex', alignItems: 'center', gap: 0.75, fontSize: 13.5, fontWeight: 500, color: tk.onSurface }}>
      <Box component="span" sx={{ width: 12, height: 12, borderRadius: '50%', bgcolor: color }} />
      {label}
    </Box>
  );
}

export function CountChip({ label, count }: { label: string; count: number }) {
  return <Chip size="small" label={`${label} · ${count}`} sx={{ bgcolor: tk.surfaceContainerHigh, color: tk.onSurfaceVariant }} />;
}
