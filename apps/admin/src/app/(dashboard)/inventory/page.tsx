'use client';
import * as React from 'react';
import { useSearchParams } from 'next/navigation';
import Box from '@mui/material/Box';
import Paper from '@mui/material/Paper';
import Typography from '@mui/material/Typography';
import Chip from '@mui/material/Chip';
import TextField from '@mui/material/TextField';
import InputAdornment from '@mui/material/InputAdornment';
import Dialog from '@mui/material/Dialog';
import DialogTitle from '@mui/material/DialogTitle';
import DialogContent from '@mui/material/DialogContent';
import DialogActions from '@mui/material/DialogActions';
import Button from '@mui/material/Button';
import MenuItem from '@mui/material/MenuItem';
import type { GridColDef } from '@mui/x-data-grid';
import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query';
import PageHeader from '@/components/layout/PageHeader';
import SectionCard from '@/components/ui/SectionCard';
import AdminGrid from '@/components/ui/AdminGrid';
import StatusChip from '@/components/ui/StatusChip';
import LevelBar from '@/components/ui/LevelBar';
import IconTile from '@/components/ui/IconTile';
import Toast from '@/components/ui/Toast';
import MSymbol from '@/components/MSymbol';
import { LiveChip, NavyPill, OutletPill } from '@/components/ui/Pills';
import { EmptyState } from '@/components/ui/States';
import { useApi, useAuth } from '@/lib/auth/AuthProvider';
import { useFilters } from '@/lib/filters';
import { useExport, useLive, useToast } from '@/lib/hooks';
import { can } from '@/lib/rbac';
import { tk } from '@/theme/tokens';
import { num } from '@/lib/format';
import type { InventoryItem } from '@/lib/types';

function SummaryCard({ icon, tone, value, label, border }: { icon: string; tone: 'primary' | 'warning' | 'error'; value: number; label: string; border?: 'gold' | 'error' }) {
  return (
    <Paper sx={{ p: 2.5, display: 'flex', alignItems: 'center', gap: 2, minHeight: 124, ...(border === 'gold' && { border: `2px solid ${tk.gold}` }), ...(border === 'error' && { border: `2px solid color-mix(in srgb, ${tk.error} 45%, transparent)` }) }}>
      <IconTile icon={icon} tone={tone} size={64} />
      <Box>
        <Typography sx={{ fontSize: 34, fontWeight: 700, lineHeight: 1.1, color: tone === 'error' ? tk.error : tone === 'warning' ? tk.onWarningContainer : tk.onSurface }}>{num(value)}</Typography>
        <Typography variant="body1" color="text.secondary" sx={{ fontSize: 14.5 }}>{label}</Typography>
      </Box>
    </Paper>
  );
}

function ThresholdDialog({ item, onClose }: { item: InventoryItem | null; onClose: () => void }) {
  return (
    <Dialog open={Boolean(item)} onClose={onClose} aria-labelledby="inv-title" fullWidth maxWidth="xs">
      {item && <ThresholdForm item={item} onClose={onClose} />}
    </Dialog>
  );
}

function ThresholdForm({ item, onClose }: { item: InventoryItem; onClose: () => void }) {
  const api = useApi();
  const { role } = useAuth();
  const qc = useQueryClient();
  const toast = useToast();
  const [threshold, setThreshold] = React.useState(String(item.reorder_threshold));
  const [delta, setDelta] = React.useState('');
  const [reason, setReason] = React.useState<'receive' | 'usage' | 'adjust' | 'count' | 'reorder_request'>('receive');
  const [note, setNote] = React.useState('');
  const canThreshold = can(role, 'inventory:threshold');
  const canMove = can(role, 'inventory:movement');
  const saveThreshold = useMutation({ mutationFn: () => api.updateInventoryItem(item.id, { reorder_threshold: Number(threshold) }), onSuccess: () => { toast.success('Threshold updated (audited)'); void qc.invalidateQueries({ queryKey: ['inventory'] }); onClose(); }, onError: (e) => toast.error(e) });
  const move = useMutation({ mutationFn: () => api.addMovement(item.id, { delta: reason === 'usage' ? -Math.abs(Number(delta)) : reason === 'reorder_request' ? 0 : Number(delta), reason, note: note || undefined }), onSuccess: (i) => { toast.success(`${i.name}: now ${i.on_hand} ${i.unit}`); void qc.invalidateQueries({ queryKey: ['inventory'] }); onClose(); }, onError: (e) => toast.error(e) });
  return (
    <>
      <DialogTitle id="inv-title">{item.name} · {item.outlet_name}</DialogTitle>
      <DialogContent sx={{ display: 'flex', flexDirection: 'column', gap: 2 }}>
        <Typography variant="body2" color="text.secondary">On hand {item.on_hand} {item.unit} · SKU <span className="mono">{item.sku}</span></Typography>
        <Box sx={{ display: 'flex', gap: 1, alignItems: 'center' }}>
          <TextField label="Reorder threshold" type="number" value={threshold} onChange={(e) => setThreshold(e.target.value)} size="small" disabled={!canThreshold} sx={{ flex: 1 }} slotProps={{ htmlInput: { min: 0 } }} />
          <Button variant="contained" color="secondary" size="small" disabled={!canThreshold || saveThreshold.isPending || Number(threshold) === item.reorder_threshold} onClick={() => saveThreshold.mutate()}>Save</Button>
        </Box>
        {!canThreshold && <Typography variant="caption" color="text.secondary">Reorder & threshold edits are manager-only (STF-042).</Typography>}
        {canMove && (
          <>
            <Typography variant="h5">Log movement</Typography>
            <TextField select label="Reason" value={reason} onChange={(e) => setReason(e.target.value as typeof reason)} size="small">
              <MenuItem value="receive">Receive stock</MenuItem>
              <MenuItem value="usage">Log usage</MenuItem>
              <MenuItem value="adjust">Adjust</MenuItem>
              <MenuItem value="count">Stock count (no change)</MenuItem>
              <MenuItem value="reorder_request">Request reorder</MenuItem>
            </TextField>
            {reason !== 'reorder_request' && reason !== 'count' && <TextField label={`Quantity (${item.unit})`} type="number" value={delta} onChange={(e) => setDelta(e.target.value)} size="small" slotProps={{ htmlInput: { step: 1 } }} />}
            <TextField label="Note" value={note} onChange={(e) => setNote(e.target.value)} size="small" />
            <Button variant="outlined" disabled={move.isPending || (reason !== 'reorder_request' && reason !== 'count' && !delta)} onClick={() => move.mutate()}>Apply movement</Button>
          </>
        )}
      </DialogContent>
      <DialogActions sx={{ p: 2.5, pt: 0 }}><Button onClick={onClose}>Close</Button></DialogActions>
      <Toast toast={toast.toast} onClose={toast.close} />
    </>
  );
}

export default function InventoryPage() {
  const api = useApi();
  const { role } = useAuth();
  const { outletId } = useFilters();
  const params = useSearchParams();
  const { updatedAt, mode } = useLive(['inventory']);
  const { exportCsv, busy } = useExport();
  const [alertsFirst, setAlertsFirst] = React.useState(true);
  const [search, setSearch] = React.useState('');
  const [focusId, setFocusId] = React.useState<string | null>(params.get('focus'));
  const q = useQuery({ queryKey: ['inventory', outletId, alertsFirst], queryFn: () => api.listInventory({ outlet_id: outletId, alerts_first: alertsFirst }) });
  const outlets = useQuery({ queryKey: ['outlets'], queryFn: () => api.listOutlets() });
  const rows = React.useMemo(() => (q.data ?? []).filter((i) => !search || i.name.toLowerCase().includes(search.toLowerCase()) || i.sku.toLowerCase().includes(search.toLowerCase())), [q.data, search]);
  const focus = React.useMemo(() => (focusId ? (q.data ?? []).find((i) => i.id === focusId) ?? null : null), [focusId, q.data]);

  const all = q.data ?? [];
  const below = all.filter((i) => i.alert?.level === 'low').length;
  const out = all.filter((i) => i.alert?.level === 'out');
  const blocking = out.reduce((s, i) => s + i.blocking_work_orders, 0);
  const outletCount = outletId ? 1 : (outlets.data?.length ?? 3);

  const columns: GridColDef<InventoryItem>[] = [
    { field: 'name', headerName: 'Item', flex: 1.6, minWidth: 200, renderCell: (p) => <b>{p.row.name}</b> },
    { field: 'outlet_name', headerName: 'Outlet', flex: 1, minWidth: 120 },
    { field: 'level', headerName: 'Level', flex: 1.4, minWidth: 180, sortable: false, renderCell: (p) => (
      <Box sx={{ width: '100%', pr: 2 }}>
        <LevelBar value={p.row.on_hand} max={p.row.capacity} tone={p.row.alert?.level === 'out' ? 'error' : p.row.alert?.level === 'low' ? 'warning' : 'success'} height={12} label={`${p.row.name} level`} />
      </Box>
    ) },
    { field: 'on_hand', headerName: 'On hand', flex: 0.8, minWidth: 100, renderCell: (p) => <Box component="span" sx={{ fontWeight: 700, color: p.row.alert?.level === 'out' ? tk.error : p.row.alert?.level === 'low' ? tk.onWarningContainer : tk.onSurface }}>{p.row.on_hand} / {p.row.capacity}</Box> },
    { field: 'reorder_threshold', headerName: 'Threshold', flex: 0.8, minWidth: 100 },
    { field: 'status', headerName: 'Status', flex: 0.8, minWidth: 100, valueGetter: (_v, r) => r.alert?.level ?? 'ok', renderCell: (p) => (p.row.alert?.level === 'out' ? <StatusChip tone="errorSolid" label="Out" /> : p.row.alert?.level === 'low' ? <StatusChip tone="warning" label="Low" /> : <StatusChip tone="success" label="OK" />) },
  ];

  return (
    <>
      <PageHeader
        title="Inventory"
        subtitle={<Box sx={{ display: 'flex', gap: 1.5, alignItems: 'center', flexWrap: 'wrap' }}><span>Basic stock monitoring · thresholds configurable per outlet</span><LiveChip updatedAt={updatedAt} mode={mode} /></Box>}
        actions={
          <>
            <OutletPill />
            {can(role, 'export:csv') && <NavyPill icon="download" onClick={() => void exportCsv('inventory')} disabled={busy === 'inventory'}>Export CSV</NavyPill>}
          </>
        }
      />
      <Box sx={{ display: 'grid', gridTemplateColumns: { xs: '1fr', md: 'repeat(3, 1fr)' }, gap: '14px' }}>
        <SummaryCard icon="category" tone="primary" value={all.length} label={`Tracked items · ${outletCount} outlet${outletCount === 1 ? '' : 's'}`} />
        <SummaryCard icon="notification_important" tone="warning" value={below} label="Below threshold" border="gold" />
        <SummaryCard icon="remove_shopping_cart" tone="error" value={out.length} label={`Out of stock${blocking ? ` · ${blocking} blocking work` : ''}`} border="error" />
      </Box>
      <SectionCard
        flush
        title={
          <Box sx={{ display: 'flex', alignItems: 'center', gap: 1.5 }}>
            <Typography variant="h4" component="h2">Stock levels</Typography>
            <Chip label="Alerts first" clickable onClick={() => setAlertsFirst((v) => !v)} aria-pressed={alertsFirst} icon={alertsFirst ? <MSymbol name="check" size={16} style={{ color: 'inherit' }} /> : undefined} sx={{ bgcolor: alertsFirst ? tk.errorContainer : tk.surfaceContainerHigh, color: alertsFirst ? tk.onErrorContainer : tk.onSurfaceVariant, '& .MuiChip-icon': { color: 'inherit' } }} />
          </Box>
        }
        actions={
          <TextField placeholder="Search items…" value={search} onChange={(e) => setSearch(e.target.value)} size="small" aria-label="Search items" slotProps={{ input: { startAdornment: <InputAdornment position="start"><MSymbol name="search" size={20} /></InputAdornment> } }} sx={{ '& .MuiOutlinedInput-root': { bgcolor: 'transparent' }, minWidth: 220 }} />
        }
      >
        <Box sx={{ px: 1.5, pb: 1 }}>
          {!q.isLoading && !rows.length ? <EmptyState icon="inventory_2" title="No items" /> : (
            <AdminGrid<InventoryItem>
              rows={rows}
              columns={columns}
              loading={q.isLoading}
              getRowClassName={(p) => `row-clickable ${p.row.alert?.level === 'out' ? 'row-error' : p.row.alert?.level === 'low' ? 'row-warning' : ''}`}
              onRowClick={(p) => setFocusId(p.row.id)}
            />
          )}
        </Box>
      </SectionCard>
      <ThresholdDialog item={focus} onClose={() => setFocusId(null)} />
    </>
  );
}
