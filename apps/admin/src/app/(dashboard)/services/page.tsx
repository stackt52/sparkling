'use client';
import * as React from 'react';
import Box from '@mui/material/Box';
import Typography from '@mui/material/Typography';
import Tabs from '@mui/material/Tabs';
import Tab from '@mui/material/Tab';
import Chip from '@mui/material/Chip';
import type { GridColDef } from '@mui/x-data-grid';
import { useQuery } from '@tanstack/react-query';
import PageHeader from '@/components/layout/PageHeader';
import ConfigTabs from '@/components/layout/ConfigTabs';
import SectionCard from '@/components/ui/SectionCard';
import AdminGrid from '@/components/ui/AdminGrid';
import StatusChip from '@/components/ui/StatusChip';
import IconTile from '@/components/ui/IconTile';
import Toast from '@/components/ui/Toast';
import MSymbol from '@/components/MSymbol';
import { NavyPill } from '@/components/ui/Pills';
import { EmptyState, ErrorState, LoadingRows } from '@/components/ui/States';
import ServiceEditorDrawer from '@/components/catalogue/ServiceEditorDrawer';
import { GROUP_HINT, GROUP_ICON, PricingModeChip, VatChip, isSizePriced, priceText } from '@/components/catalogue/pricing';
import { useApi, useAuth } from '@/lib/auth/AuthProvider';
import { useToast } from '@/lib/hooks';
import { can } from '@/lib/rbac';
import { fonts, tk } from '@/theme/tokens';
import { SERVICE_GROUPS, type Service, type ServiceGroup } from '@/lib/types';

function IncludesChips({ service, byId }: { service: Service; byId: Map<string, Service> }) {
  const rows = [...service.components].sort((a, b) => a.sort_order - b.sort_order);
  if (!rows.length) return <Typography variant="body2" color="text.secondary">—</Typography>;
  const shown = rows.slice(0, 3);
  return (
    <Box sx={{ display: 'flex', gap: 0.5, flexWrap: 'wrap', py: 0.5 }} title={rows.map((c) => byId.get(c.child_service_id)?.name ?? c.child_service_id).join(', ')}>
      {shown.map((c) => <Chip key={c.child_service_id} size="small" label={`${byId.get(c.child_service_id)?.code ?? '?'}${c.quantity > 1 ? ` ×${c.quantity}` : ''}`} sx={{ bgcolor: tk.secondaryContainer, color: tk.onSecondaryContainer, fontFamily: fonts.mono, fontSize: 11.5, height: 22 }} />)}
      {rows.length > shown.length && <Chip size="small" label={`+${rows.length - shown.length}`} sx={{ bgcolor: tk.surfaceContainerHigh, height: 22 }} />}
    </Box>
  );
}

export default function ServicesPage() {
  const api = useApi();
  const { role } = useAuth();
  const toast = useToast();
  const services = useQuery({ queryKey: ['services'], queryFn: () => api.listServices() });
  const [tab, setTab] = React.useState<ServiceGroup>('Car Wash Options');
  const [editorOpen, setEditorOpen] = React.useState(false);
  const [editId, setEditId] = React.useState<string | null>(null);
  const manage = can(role, 'service:manage');
  const all = React.useMemo(() => services.data ?? [], [services.data]);
  const byId = React.useMemo(() => new Map(all.map((s) => [s.id, s])), [all]);
  const rows = React.useMemo(() => all.filter((s) => s.group_name === tab), [all, tab]);
  const editing = editId ? byId.get(editId) ?? null : null;
  const sizePriced = isSizePriced(tab);

  const columns = React.useMemo<GridColDef<Service>[]>(() => [
    { field: 'name', headerName: 'Service', flex: 1.6, minWidth: 260, renderCell: (p) => (
      <Box sx={{ display: 'flex', alignItems: 'center', gap: 1.25, minWidth: 0, py: 0.5 }}>
        <IconTile icon={p.row.icon || 'local_car_wash'} tone={p.row.category === 'auto_body' ? 'neutral' : 'primary'} size={36} />
        <Box sx={{ minWidth: 0 }}>
          <Typography variant="body1" sx={{ fontWeight: 600, lineHeight: 1.25 }} noWrap>{p.row.name}</Typography>
          <Typography variant="caption" color="text.secondary" noWrap sx={{ display: 'block' }}>{p.row.description || `${p.row.duration_minutes} min`}</Typography>
        </Box>
      </Box>
    ) },
    { field: 'code', headerName: 'Code', width: 175, cellClassName: 'mono', renderCell: (p) => <span style={{ fontSize: 12.5 }}>{p.value}</span> },
    { field: 'pricing_mode', headerName: 'Pricing', width: 110, renderCell: (p) => <PricingModeChip mode={p.row.pricing_mode} /> },
    { field: 'vat_mode', headerName: 'VAT', width: 110, renderCell: (p) => <VatChip mode={p.row.vat_mode} /> },
    ...(sizePriced ? [
      { field: 'price_small_cents', headerName: 'Small', width: 100, align: 'right', headerAlign: 'right', valueFormatter: (v: number | null) => priceText(v) } as GridColDef<Service>,
      { field: 'price_large_cents', headerName: 'Large', width: 100, align: 'right', headerAlign: 'right', valueFormatter: (v: number | null) => priceText(v) } as GridColDef<Service>,
    ] : [
      { field: 'price_general_cents', headerName: 'General', width: 110, align: 'right', headerAlign: 'right', valueFormatter: (v: number | null) => priceText(v) } as GridColDef<Service>,
    ]),
    { field: 'components', headerName: 'Includes', flex: 1.2, minWidth: 220, sortable: false, renderCell: (p) => <IncludesChips service={p.row} byId={byId} /> },
    { field: 'is_addon', headerName: 'Add-on', width: 130, renderCell: (p) => (p.row.is_addon ? <StatusChip tone="gold" label={p.row.addon_group_name ? `Add-on · ${p.row.addon_group_name.split(' ')[0]}` : 'Add-on'} icon={<MSymbol name="add_circle" size={14} filled />} /> : <Typography variant="body2" color="text.secondary">—</Typography>) },
    { field: 'is_active', headerName: 'Active', width: 100, renderCell: (p) => <StatusChip tone={p.row.is_active ? 'success' : 'neutral'} label={p.row.is_active ? 'Active' : 'Inactive'} /> },
  ], [sizePriced, byId]);

  return (
    <>
      <PageHeader
        title="Configuration"
        subtitle="Services · canonical catalogue: groups, pricing modes, per-size defaults and composites. Outlets bind services and set their own prices under Outlets → Catalogue."
        actions={manage ? <NavyPill icon="add" onClick={() => { setEditId(null); setEditorOpen(true); }}>New service</NavyPill> : undefined}
      />
      <ConfigTabs />
      <SectionCard flush>
        <Box sx={{ px: 2.5, pt: 1, borderBottom: `1px solid ${tk.outlineVariant}` }}>
          <Tabs value={tab} onChange={(_e, v: ServiceGroup) => setTab(v)} aria-label="Service groups" variant="scrollable" allowScrollButtonsMobile>
            {SERVICE_GROUPS.map((g) => (
              <Tab key={g} value={g} icon={<MSymbol name={GROUP_ICON[g]} size={20} filled={tab === g} />} iconPosition="start" label={<Box sx={{ display: 'inline-flex', alignItems: 'center', gap: 1 }}>{g}<Chip size="small" label={all.filter((s) => s.group_name === g).length} sx={{ height: 20, bgcolor: tk.surfaceContainerHigh, color: tk.onSurfaceVariant }} /></Box>} sx={{ minHeight: 56 }} />
            ))}
          </Tabs>
        </Box>
        <Typography variant="body2" color="text.secondary" sx={{ px: 2.5, py: 1.5 }}>{GROUP_HINT[tab]} · {manage ? 'Click a row to edit.' : 'Click a row to view (read-only).'}</Typography>
        {services.isLoading && <Box sx={{ px: 2.5, pb: 2.5 }}><LoadingRows rows={6} /></Box>}
        {services.error && <ErrorState error={services.error} onRetry={() => services.refetch()} />}
        {services.isSuccess && (rows.length ? (
          <AdminGrid<Service>
            rows={rows}
            columns={columns}
            getRowId={(r) => r.id}
            rowHeight={64}
            getRowClassName={() => 'row-clickable'}
            onRowClick={(p) => { setEditId(p.row.id); setEditorOpen(true); }}
            sx={{ px: 1 }}
            aria-label={`${tab} services`}
          />
        ) : <EmptyState icon={GROUP_ICON[tab]} title={`No services in ${tab}`} description={manage ? 'Create one with "New service".' : undefined} />)}
      </SectionCard>

      <ServiceEditorDrawer
        open={editorOpen}
        service={editing}
        services={all}
        readOnly={!manage}
        onClose={() => setEditorOpen(false)}
        onSaved={(s, created) => { toast.success(created ? `${s.name} created` : `${s.name} saved`); setEditId(s.id); if (created) setTab(s.group_name); setEditorOpen(false); }}
        onError={toast.error}
      />
      <Toast toast={toast.toast} onClose={toast.close} />
    </>
  );
}
