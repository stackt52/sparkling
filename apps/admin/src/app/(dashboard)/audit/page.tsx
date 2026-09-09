'use client';
import * as React from 'react';
import { useSearchParams } from 'next/navigation';
import Box from '@mui/material/Box';
import Typography from '@mui/material/Typography';
import Button from '@mui/material/Button';
import TextField from '@mui/material/TextField';
import MenuItem from '@mui/material/MenuItem';
import Collapse from '@mui/material/Collapse';
import type { GridColDef } from '@mui/x-data-grid';
import { useQuery } from '@tanstack/react-query';
import PageHeader from '@/components/layout/PageHeader';
import ConfigTabs from '@/components/layout/ConfigTabs';
import SectionCard from '@/components/ui/SectionCard';
import AdminGrid from '@/components/ui/AdminGrid';
import StatusChip from '@/components/ui/StatusChip';
import MSymbol from '@/components/MSymbol';
import { useApi } from '@/lib/auth/AuthProvider';
import { fonts, tk } from '@/theme/tokens';
import { fmtDateTime } from '@/lib/format';
import type { AuditEvent } from '@/lib/types';

const ENTITIES = ['', 'loyalty_config', 'task', 'inventory_item', 'profile', 'feature_flag', 'booking', 'quotation', 'outlet', 'service', 'checklist_template', 'outlet_service'];

export default function AuditPage() {
  const api = useApi();
  const params = useSearchParams();
  const [entity, setEntity] = React.useState(params.get('entity_type') ?? '');
  const [action, setAction] = React.useState('');
  const [actor, setActor] = React.useState('');
  const [cursor, setCursor] = React.useState<string | null>(null);
  const [selected, setSelected] = React.useState<AuditEvent | null>(null);
  const q = useQuery({ queryKey: ['audit', entity, action, actor, cursor], queryFn: () => api.listAudit({ entity_type: entity || undefined, action: action || undefined, actor: actor || undefined, cursor, limit: 25 }) });
  const [history, setHistory] = React.useState<(string | null)[]>([]);
  const columns: GridColDef<AuditEvent>[] = [
    { field: 'created_at', headerName: 'When', flex: 0.9, minWidth: 130, renderCell: (p) => fmtDateTime(p.row.created_at) },
    { field: 'actor_name', headerName: 'Actor', flex: 1, minWidth: 150, renderCell: (p) => <span>{p.row.actor_name ?? p.row.actor_id} <Typography component="span" variant="caption" color="text.secondary">· {p.row.actor_role}</Typography></span> },
    { field: 'action', headerName: 'Action', flex: 1.1, minWidth: 160, renderCell: (p) => <span className="mono" style={{ fontWeight: 600 }}>{p.row.action}</span> },
    { field: 'entity_type', headerName: 'Entity', flex: 1, minWidth: 150, renderCell: (p) => <span>{p.row.entity_type}{p.row.entity_id ? <Typography component="span" variant="caption" color="text.secondary" className="mono"> · {p.row.entity_id.slice(0, 12)}…</Typography> : null}</span> },
    { field: 'outcome', headerName: 'Outcome', flex: 0.6, minWidth: 90, renderCell: (p) => <StatusChip tone={p.row.outcome === 'ok' ? 'success' : 'error'} label={p.row.outcome} /> },
    { field: 'correlation_id', headerName: 'Correlation', flex: 0.9, minWidth: 120, renderCell: (p) => <span className="mono" style={{ color: tk.onSurfaceVariant, fontSize: 12 }}>{p.row.correlation_id}</span> },
  ];
  return (
    <>
      <PageHeader title="Configuration" subtitle="Audit log · append-only record of every privileged action (ADM-003 / SEC-006)" />
      <ConfigTabs />
      <Box sx={{ display: 'flex', gap: 1.5, flexWrap: 'wrap' }}>
        <TextField select label="Entity" value={entity} onChange={(e) => { setEntity(e.target.value); setCursor(null); setHistory([]); }} size="small" sx={{ minWidth: 190 }}>
          {ENTITIES.map((e) => <MenuItem key={e} value={e}>{e || 'All entities'}</MenuItem>)}
        </TextField>
        <TextField label="Action prefix" placeholder="e.g. loyalty_config." value={action} onChange={(e) => { setAction(e.target.value); setCursor(null); setHistory([]); }} size="small" sx={{ minWidth: 200 }} />
        <TextField label="Actor" value={actor} onChange={(e) => { setActor(e.target.value); setCursor(null); setHistory([]); }} size="small" sx={{ minWidth: 180 }} />
      </Box>
      <SectionCard flush title="Events" subtitle={q.data ? `Page of ${q.data.data.length} · ${q.data.next_cursor ? 'more available' : 'end of log'}` : undefined}>
        <Box sx={{ px: 1.5, pb: 1 }}>
          <AdminGrid<AuditEvent> rows={q.data?.data ?? []} columns={columns} loading={q.isLoading} getRowClassName={(p) => (p.row.id === selected?.id ? 'row-clickable row-warning' : 'row-clickable')} onRowClick={(p) => setSelected(selected?.id === p.row.id ? null : p.row)} />
          <Collapse in={Boolean(selected)}>
            {selected && (
              <Box sx={{ m: 1.5, p: 2, borderRadius: '18px', bgcolor: tk.surfaceContainer, display: 'grid', gridTemplateColumns: { xs: '1fr', md: '1fr 1fr' }, gap: 2 }}>
                <Box>
                  <Typography variant="overline" color="text.secondary">Before</Typography>
                  <Box component="pre" sx={{ m: 0, fontFamily: fonts.mono, fontSize: 12, whiteSpace: 'pre-wrap' }}>{JSON.stringify(selected.before, null, 2) ?? 'null'}</Box>
                </Box>
                <Box>
                  <Typography variant="overline" color="text.secondary">After</Typography>
                  <Box component="pre" sx={{ m: 0, fontFamily: fonts.mono, fontSize: 12, whiteSpace: 'pre-wrap' }}>{JSON.stringify(selected.after, null, 2) ?? 'null'}</Box>
                </Box>
                <Typography variant="caption" color="text.secondary" sx={{ gridColumn: '1 / -1' }}>Entity id <span className="mono">{selected.entity_id}</span> · outlet {selected.outlet_id ?? '—'} · correlation <span className="mono">{selected.correlation_id}</span></Typography>
              </Box>
            )}
          </Collapse>
          <Box sx={{ display: 'flex', justifyContent: 'flex-end', gap: 1, p: 1.5 }}>
            <Button size="small" variant="outlined" disabled={history.length === 0} onClick={() => { const prev = [...history]; const c = prev.pop() ?? null; setHistory(prev); setCursor(c); }} startIcon={<MSymbol name="chevron_left" size={18} />}>Previous</Button>
            <Button size="small" variant="outlined" disabled={!q.data?.next_cursor} onClick={() => { setHistory([...history, cursor]); setCursor(q.data!.next_cursor); }} endIcon={<MSymbol name="chevron_right" size={18} />}>Next</Button>
          </Box>
        </Box>
      </SectionCard>
    </>
  );
}
