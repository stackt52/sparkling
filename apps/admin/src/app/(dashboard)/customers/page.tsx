'use client';
import * as React from 'react';
import Box from '@mui/material/Box';
import Typography from '@mui/material/Typography';
import TextField from '@mui/material/TextField';
import InputAdornment from '@mui/material/InputAdornment';
import Drawer from '@mui/material/Drawer';
import IconButton from '@mui/material/IconButton';
import Avatar from '@mui/material/Avatar';
import Chip from '@mui/material/Chip';
import Alert from '@mui/material/Alert';
import Tabs from '@mui/material/Tabs';
import Tab from '@mui/material/Tab';
import type { GridColDef } from '@mui/x-data-grid';
import { useQuery } from '@tanstack/react-query';
import PageHeader from '@/components/layout/PageHeader';
import SectionCard from '@/components/ui/SectionCard';
import AdminGrid from '@/components/ui/AdminGrid';
import StatusChip from '@/components/ui/StatusChip';
import Tile from '@/components/ui/Tile';
import MSymbol from '@/components/MSymbol';
import { ErrorState, LoadingRows } from '@/components/ui/States';
import { useApi } from '@/lib/auth/AuthProvider';
import { tk } from '@/theme/tokens';
import { fmtDate, fmtDateTime, initials, num, rands } from '@/lib/format';
import type { CustomerSummary } from '@/lib/types';

const tierTone = { silver: 'neutral', gold: 'gold', platinum: 'secondary' } as const;

function CustomerDrawer({ id, onClose }: { id: string | null; onClose: () => void }) {
  const api = useApi();
  const [tab, setTab] = React.useState(0);
  const q = useQuery({ queryKey: ['customer', id], queryFn: () => api.getCustomer(id!), enabled: Boolean(id) });
  const c = q.data;
  return (
    <Drawer anchor="right" open={Boolean(id)} onClose={onClose} slotProps={{ paper: { sx: { width: { xs: '100%', sm: 520 }, borderRadius: { xs: 0, sm: '28px 0 0 28px' }, p: 3 } } }}>
      <Box sx={{ display: 'flex', alignItems: 'center', justifyContent: 'space-between' }}>
        <Typography variant="overline" color="text.secondary">Customer</Typography>
        <IconButton aria-label="Close" onClick={onClose}><MSymbol name="close" /></IconButton>
      </Box>
      {q.isLoading && <LoadingRows rows={5} />}
      {q.error && <ErrorState error={q.error} />}
      {c && (
        <>
          <Box sx={{ display: 'flex', alignItems: 'center', gap: 1.5 }}>
            <Avatar sx={{ width: 52, height: 52, bgcolor: tk.secondaryContainer, color: tk.onSecondaryContainer, fontWeight: 700 }}>{initials(c.full_name)}</Avatar>
            <Box>
              <Typography variant="h2">{c.full_name}</Typography>
              <Typography color="text.secondary">{c.email} · {c.phone}</Typography>
            </Box>
          </Box>
          <Box sx={{ display: 'flex', gap: 1, mt: 1.5, flexWrap: 'wrap' }}>
            {c.loyalty && <StatusChip tone={tierTone[c.loyalty.tier]} label={`${c.loyalty.tier.replace(/^\w/, (x) => x.toUpperCase())} · ${num(c.loyalty.balance_points)} pts`} />}
            <Chip size="small" label={c.marketing_opt_in ? 'Marketing opt-in' : 'No marketing consent'} sx={{ bgcolor: tk.surfaceContainerHigh }} />
            <Chip size="small" label={c.whatsapp_opt_in ? 'WhatsApp on' : 'WhatsApp off'} sx={{ bgcolor: tk.surfaceContainerHigh }} />
          </Box>
          <Alert severity="info" icon={<MSymbol name="policy" size={20} />} sx={{ mt: 2, bgcolor: tk.secondaryContainer, color: tk.onSecondaryContainer }}>
            This access is logged in the audit trail with your identity and timestamp (ADM-024/041).
          </Alert>
          <Tabs value={tab} onChange={(_e, v) => setTab(v)} sx={{ mt: 1.5 }} aria-label="Customer sections">
            <Tab label={`Vehicles · ${c.vehicles.length}`} />
            <Tab label={`History · ${c.bookings.length}`} />
            <Tab label={`Loyalty · ${c.ledger.length}`} />
          </Tabs>
          <Box sx={{ mt: 1.5, display: 'flex', flexDirection: 'column', gap: 1 }}>
            {tab === 0 && c.vehicles.map((v) => (
              <Tile key={v.id}>
                <MSymbol name="directions_car" filled size={24} style={{ color: tk.primary }} />
                <Box sx={{ flex: 1 }}>
                  <Typography variant="h6"><span className="mono">{v.registration_no}</span> · {v.make} {v.model}</Typography>
                  <Typography variant="caption" color="text.secondary">{v.colour} · {v.year} · disc expires {fmtDate(v.disc_expiry, 'MMM yyyy')}</Typography>
                </Box>
                <StatusChip tone={v.disc_verified ? 'success' : 'neutral'} label={v.disc_verified ? 'Disc verified' : 'Manual entry'} />
              </Tile>
            ))}
            {tab === 1 && c.bookings.map((b) => (
              <Tile key={b.id}>
                <Box sx={{ flex: 1 }}>
                  <Typography variant="h6"><span className="mono" style={{ color: tk.primary }}>{b.ref}</span> · {b.service.name}</Typography>
                  <Typography variant="caption" color="text.secondary">{fmtDateTime(b.slot_start)} · {b.outlet.name.replace('Sparkling ', '')} · {rands(b.total_cents)}</Typography>
                </Box>
                <StatusChip status={b.status} />
              </Tile>
            ))}
            {tab === 2 && c.ledger.map((l) => (
              <Tile key={l.id}>
                <MSymbol name={l.delta >= 0 ? 'add_circle' : 'do_not_disturb_on'} filled size={24} style={{ color: l.delta >= 0 ? tk.success : tk.error }} />
                <Box sx={{ flex: 1 }}>
                  <Typography variant="h6">{l.description}</Typography>
                  <Typography variant="caption" color="text.secondary"><span className="mono">{l.reference}</span> · {fmtDate(l.created_at, 'd MMM yyyy')} · {l.type}</Typography>
                </Box>
                <Typography sx={{ fontWeight: 700, color: l.delta >= 0 ? tk.success : tk.error }}>{l.delta >= 0 ? '+' : ''}{num(l.delta)}</Typography>
              </Tile>
            ))}
            {tab === 2 && <Typography variant="caption" color="text.secondary">Append-only ledger · balance is derived from entries (CUS-063).</Typography>}
          </Box>
        </>
      )}
    </Drawer>
  );
}

export default function CustomersPage() {
  const api = useApi();
  const [search, setSearch] = React.useState('');
  const [debounced, setDebounced] = React.useState('');
  const [focus, setFocus] = React.useState<string | null>(null);
  React.useEffect(() => { const t = setTimeout(() => setDebounced(search), 250); return () => clearTimeout(t); }, [search]);
  const q = useQuery({ queryKey: ['customers', debounced], queryFn: () => api.searchCustomers(debounced) });
  const columns: GridColDef<CustomerSummary>[] = [
    { field: 'full_name', headerName: 'Customer', flex: 1.4, minWidth: 200, renderCell: (p) => (
      <Box sx={{ display: 'flex', alignItems: 'center', gap: 1.25 }}>
        <Avatar sx={{ width: 34, height: 34, fontSize: 13, fontWeight: 700, bgcolor: tk.secondaryContainer, color: tk.onSecondaryContainer }}>{initials(p.row.full_name)}</Avatar>
        <Box><Typography variant="h6" component="span" sx={{ display: 'block' }}>{p.row.full_name}</Typography><Typography variant="caption" color="text.secondary">{p.row.email}</Typography></Box>
      </Box>
    ) },
    { field: 'phone', headerName: 'Phone', flex: 0.9, minWidth: 140, renderCell: (p) => <span className="mono">{p.row.phone}</span> },
    { field: 'tier', headerName: 'Tier', flex: 0.8, minWidth: 120, valueGetter: (_v, r) => r.loyalty?.tier ?? '', renderCell: (p) => (p.row.loyalty ? <StatusChip tone={tierTone[p.row.loyalty.tier]} label={p.row.loyalty.tier.replace(/^\w/, (x) => x.toUpperCase())} /> : '—') },
    { field: 'points', headerName: 'Points', flex: 0.7, minWidth: 90, align: 'right', headerAlign: 'right', valueGetter: (_v, r) => r.loyalty?.balance_points ?? 0, renderCell: (p) => <b>{num(p.row.loyalty?.balance_points ?? 0)}</b> },
    { field: 'vehicle_count', headerName: 'Vehicles', flex: 0.6, minWidth: 90, align: 'right', headerAlign: 'right' },
    { field: 'booking_count', headerName: 'Bookings', flex: 0.6, minWidth: 90, align: 'right', headerAlign: 'right' },
    { field: 'marketing_opt_in', headerName: 'Consent', flex: 0.8, minWidth: 120, renderCell: (p) => <StatusChip tone={p.row.marketing_opt_in ? 'success' : 'neutral'} label={p.row.marketing_opt_in ? 'Marketing' : 'Service only'} /> },
  ];
  return (
    <>
      <PageHeader title="Customers" subtitle="Search by name, e-mail, phone or plate · profile access is audited" />
      <TextField placeholder="Search customers…" value={search} onChange={(e) => setSearch(e.target.value)} aria-label="Search customers" sx={{ maxWidth: 420 }} slotProps={{ input: { startAdornment: <InputAdornment position="start"><MSymbol name="search" size={22} /></InputAdornment> } }} />
      <SectionCard flush title="Customers" subtitle={q.data ? `${q.data.length} result${q.data.length === 1 ? '' : 's'}` : undefined}>
        <Box sx={{ px: 1.5, pb: 1 }}>
          {q.error ? <ErrorState error={q.error} /> : <AdminGrid<CustomerSummary> rows={q.data ?? []} columns={columns} loading={q.isLoading} getRowClassName={() => 'row-clickable'} onRowClick={(p) => setFocus(p.row.id)} />}
        </Box>
      </SectionCard>
      <CustomerDrawer id={focus} onClose={() => setFocus(null)} />
    </>
  );
}
