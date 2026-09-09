'use client';
import * as React from 'react';
import { useSearchParams } from 'next/navigation';
import Box from '@mui/material/Box';
import Typography from '@mui/material/Typography';
import Button from '@mui/material/Button';
import TextField from '@mui/material/TextField';
import Tabs from '@mui/material/Tabs';
import Tab from '@mui/material/Tab';
import type { GridColDef } from '@mui/x-data-grid';
import { useQuery } from '@tanstack/react-query';
import { format, startOfMonth } from 'date-fns';
import PageHeader from '@/components/layout/PageHeader';
import SectionCard from '@/components/ui/SectionCard';
import AdminGrid from '@/components/ui/AdminGrid';
import StatusChip from '@/components/ui/StatusChip';
import LevelBar from '@/components/ui/LevelBar';
import Tile from '@/components/ui/Tile';
import MSymbol from '@/components/MSymbol';
import { NavyPill, OutletPill } from '@/components/ui/Pills';
import { LoadingRows } from '@/components/ui/States';
import { useApi, useAuth } from '@/lib/auth/AuthProvider';
import { useFilters } from '@/lib/filters';
import { useExport } from '@/lib/hooks';
import { can } from '@/lib/rbac';
import { tk } from '@/theme/tokens';
import { fmtDateTime, num, rands } from '@/lib/format';
import type { Payment, ReportKind } from '@/lib/types';

const EXPORTS: { report: ReportKind; label: string; icon: string; desc: string }[] = [
  { report: 'bookings', label: 'Bookings', icon: 'calendar_month', desc: 'Every booking in range with service, slot, status and totals' },
  { report: 'payments', label: 'Payments', icon: 'payments', desc: 'Provider, amount, status, receipt and verification time' },
  { report: 'inventory', label: 'Inventory', icon: 'inventory_2', desc: 'Stock on hand vs thresholds per outlet' },
  { report: 'staff_performance', label: 'Staff performance', icon: 'groups', desc: 'Tasks, cycle time, compliance and points' },
  { report: 'loyalty', label: 'Loyalty', icon: 'loyalty', desc: 'Members by tier with balances' },
];

function Stat({ label, value, sub }: { label: string; value: string; sub?: string }) {
  return (
    <Tile sx={{ flexDirection: 'column', alignItems: 'flex-start', gap: 0.25, minHeight: 92 }}>
      <Typography variant="body2" color="text.secondary">{label}</Typography>
      <Typography sx={{ fontSize: 28, fontWeight: 700, lineHeight: 1.1 }}>{value}</Typography>
      {sub && <Typography variant="caption" color="text.secondary">{sub}</Typography>}
    </Tile>
  );
}

const paymentColumns: GridColDef<Payment>[] = [
  { field: 'created_at', headerName: 'When', flex: 1, minWidth: 130, renderCell: (p) => fmtDateTime(p.row.created_at) },
  { field: 'booking_ref', headerName: 'Booking', flex: 1, minWidth: 130, renderCell: (p) => <span className="mono" style={{ color: tk.primary, fontWeight: 700 }}>{p.row.booking_ref}</span> },
  { field: 'customer_name', headerName: 'Customer', flex: 1.2, minWidth: 150 },
  { field: 'provider', headerName: 'Provider', flex: 0.7, minWidth: 90 },
  { field: 'receipt_no', headerName: 'Receipt', flex: 0.9, minWidth: 110, renderCell: (p) => <span className="mono">{p.row.receipt_no ?? '—'}</span> },
  { field: 'status', headerName: 'Status', flex: 0.9, minWidth: 120, renderCell: (p) => <StatusChip status={p.row.status} /> },
  { field: 'amount_cents', headerName: 'Amount', flex: 0.8, minWidth: 100, align: 'right', headerAlign: 'right', renderCell: (p) => <b>{rands(p.row.amount_cents, { decimals: true })}</b> },
];

export default function ReportsPage() {
  const api = useApi();
  const { role } = useAuth();
  const { outletId } = useFilters();
  const params = useSearchParams();
  const { exportCsv, busy } = useExport();
  const [tab, setTab] = React.useState(params.get('tab') === 'payments' ? 1 : 0);
  const [from, setFrom] = React.useState(format(startOfMonth(new Date()), 'yyyy-MM-dd'));
  const [to, setTo] = React.useState(format(new Date(), 'yyyy-MM-dd'));
  const summary = useQuery({ queryKey: ['report-summary', outletId, from, to], queryFn: () => api.reportSummary({ outlet_id: outletId, from, to }) });
  const payments = useQuery({ queryKey: ['payments', outletId], queryFn: () => api.listPayments({ outlet_id: outletId }), enabled: tab === 1 });
  const s = summary.data;
  const canExport = can(role, 'export:csv');
  const maxOutlet = Math.max(1, ...(s?.financial.by_outlet.map((o) => o.revenue_cents) ?? [1]));
  return (
    <>
      <PageHeader title="Reports" subtitle="Financial and operational summaries · CSV exports include generated_at, filters and scope (REP-007)" actions={<OutletPill />} />
      <Box sx={{ display: 'flex', gap: 1.5, alignItems: 'center', flexWrap: 'wrap' }}>
        <TextField type="date" label="From" value={from} onChange={(e) => setFrom(e.target.value)} size="small" slotProps={{ inputLabel: { shrink: true } }} />
        <TextField type="date" label="To" value={to} onChange={(e) => setTo(e.target.value)} size="small" slotProps={{ inputLabel: { shrink: true } }} />
        <Tabs value={tab} onChange={(_e, v) => setTab(v)} sx={{ ml: 'auto' }} aria-label="Report sections">
          <Tab label="Summary" />
          <Tab label="Payments" />
          <Tab label="Exports" />
        </Tabs>
      </Box>
      {tab === 0 && (
        <Box sx={{ display: 'grid', gridTemplateColumns: { xs: '1fr', lg: '1fr 1fr' }, gap: '14px', alignItems: 'start' }}>
          <SectionCard title="Financial" actions={canExport && <Button size="small" variant="outlined" onClick={() => void exportCsv('payments', { from, to })} disabled={busy === 'payments'} startIcon={<MSymbol name="download" size={18} />}>Payments CSV</Button>}>
            {!s ? <LoadingRows rows={3} /> : (
              <>
                <Box sx={{ display: 'grid', gridTemplateColumns: 'repeat(auto-fit, minmax(150px, 1fr))', gap: 1.25 }}>
                  <Stat label="Revenue" value={rands(s.financial.revenue_cents)} sub={`${from} → ${to}`} />
                  <Stat label="Avg ticket" value={rands(s.financial.avg_ticket_cents)} />
                  <Stat label="Payments" value={num(s.financial.payments_successful)} sub={`${s.financial.payments_failed} failed`} />
                  <Stat label="Refunds" value={rands(s.financial.refunds_cents)} />
                </Box>
                <Typography variant="h5" sx={{ mt: 2.5, mb: 1 }}>By outlet</Typography>
                <Box sx={{ display: 'flex', flexDirection: 'column', gap: 1.5 }}>
                  {s.financial.by_outlet.map((o) => (
                    <Box key={o.name}>
                      <Box sx={{ display: 'flex', justifyContent: 'space-between', mb: 0.5 }}><Typography variant="h6">{o.name}</Typography><Typography variant="h6" sx={{ color: tk.primary }}>{rands(o.revenue_cents)} · {o.bookings} bookings</Typography></Box>
                      <LevelBar value={o.revenue_cents} max={maxOutlet} tone="azure" height={10} label={`${o.name} revenue`} />
                    </Box>
                  ))}
                </Box>
                <Typography variant="h5" sx={{ mt: 2.5, mb: 1 }}>By service</Typography>
                <Box component="table" sx={{ width: '100%', borderCollapse: 'collapse', '& td, & th': { py: 0.75, borderBottom: `1px solid ${tk.outlineVariant}`, textAlign: 'left', fontSize: 13.5 }, '& th': { color: tk.onSurfaceVariant, fontSize: 11, textTransform: 'uppercase', letterSpacing: '0.06em' } }}>
                  <thead><tr><th>Service</th><th style={{ textAlign: 'right' }}>Count</th><th style={{ textAlign: 'right' }}>Revenue</th></tr></thead>
                  <tbody>{s.financial.by_service.map((x) => <tr key={x.name}><td>{x.name}</td><td style={{ textAlign: 'right' }}>{x.count}</td><td style={{ textAlign: 'right', fontWeight: 700 }}>{rands(x.revenue_cents)}</td></tr>)}</tbody>
                </Box>
              </>
            )}
          </SectionCard>
          <SectionCard title="Operational" actions={canExport && <Button size="small" variant="outlined" onClick={() => void exportCsv('bookings', { from, to })} disabled={busy === 'bookings'} startIcon={<MSymbol name="download" size={18} />}>Bookings CSV</Button>}>
            {!s ? <LoadingRows rows={3} /> : (
              <>
                <Box sx={{ display: 'grid', gridTemplateColumns: 'repeat(auto-fit, minmax(150px, 1fr))', gap: 1.25 }}>
                  <Stat label="Bookings" value={num(s.operational.bookings)} sub={`${s.operational.completed} completed · ${s.operational.cancelled} cancelled`} />
                  <Stat label="On time" value={`${s.operational.on_time_pct}%`} />
                  <Stat label="Avg cycle" value={`${s.operational.avg_cycle_minutes} min`} />
                  <Stat label="Checklist compliance" value={`${s.operational.checklist_compliance_pct}%`} />
                </Box>
                <Typography variant="h5" sx={{ mt: 2.5, mb: 1 }}>Quote funnel</Typography>
                <Box sx={{ display: 'flex', flexDirection: 'column', gap: 1 }}>
                  {[['Requested', s.operational.quotes.requested], ['Quoted', s.operational.quotes.quoted], ['Accepted', s.operational.quotes.accepted], ['Converted', s.operational.quotes.converted]].map(([label, v]) => (
                    <Box key={label} sx={{ display: 'flex', alignItems: 'center', gap: 1.5 }}>
                      <Typography variant="body2" sx={{ width: 90 }}>{label}</Typography>
                      <LevelBar value={Number(v)} max={Math.max(1, s.operational.quotes.requested)} tone="primary" height={10} label={`${label} quotes`} />
                      <Typography variant="h6" sx={{ width: 30, textAlign: 'right' }}>{v}</Typography>
                    </Box>
                  ))}
                </Box>
              </>
            )}
          </SectionCard>
        </Box>
      )}
      {tab === 1 && (
        <SectionCard flush title="Payments" subtitle="Webhook-verified statuses · only the provider webhook can mark a payment successful (CUS-041)" actions={canExport && <NavyPill icon="download" onClick={() => void exportCsv('payments')} disabled={busy === 'payments'}>Export CSV</NavyPill>}>
          <Box sx={{ px: 1.5, pb: 1 }}>
            <AdminGrid<Payment> rows={payments.data ?? []} columns={paymentColumns} loading={payments.isLoading} getRowClassName={(p) => (p.row.status === 'failed' ? 'row-error' : p.row.id === params.get('focus') ? 'row-warning' : '')} />
          </Box>
        </SectionCard>
      )}
      {tab === 2 && (
        <Box sx={{ display: 'grid', gridTemplateColumns: { xs: '1fr', md: 'repeat(2, 1fr)', xl: 'repeat(3, 1fr)' }, gap: '14px' }}>
          {EXPORTS.map((e) => (
            <Tile key={e.report} sx={{ alignItems: 'flex-start', minHeight: 120 }}>
              <MSymbol name={e.icon} filled size={28} style={{ color: tk.primary }} />
              <Box sx={{ flex: 1 }}>
                <Typography variant="h5">{e.label}</Typography>
                <Typography variant="body2" color="text.secondary" sx={{ mb: 1.5 }}>{e.desc}</Typography>
                <Button size="small" variant="contained" color="secondary" disabled={!canExport || busy === e.report} onClick={() => void exportCsv(e.report, { from, to })} startIcon={<MSymbol name="download" size={18} />}>
                  {busy === e.report ? 'Generating…' : 'Export CSV'}
                </Button>
              </Box>
            </Tile>
          ))}
        </Box>
      )}
    </>
  );
}
