'use client';
import * as React from 'react';
import Box from '@mui/material/Box';
import Typography from '@mui/material/Typography';
import Avatar from '@mui/material/Avatar';
import Button from '@mui/material/Button';
import TextField from '@mui/material/TextField';
import MenuItem from '@mui/material/MenuItem';
import InputAdornment from '@mui/material/InputAdornment';
import IconButton from '@mui/material/IconButton';
import Menu from '@mui/material/Menu';
import ListItemIcon from '@mui/material/ListItemIcon';
import type { GridColDef } from '@mui/x-data-grid';
import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query';
import SectionCard from '@/components/ui/SectionCard';
import AdminGrid from '@/components/ui/AdminGrid';
import StatusChip from '@/components/ui/StatusChip';
import TierChip from '@/components/ui/TierChip';
import MSymbol from '@/components/MSymbol';
import { NavyPill } from '@/components/ui/Pills';
import { ErrorState } from '@/components/ui/States';
import { useApi } from '@/lib/auth/AuthProvider';
import { tk } from '@/theme/tokens';
import { fmtDate, initials, rands } from '@/lib/format';
import { formatPhone } from '@/lib/phone';
import { MEMBERSHIP_STATUSES, type MembershipPlan, type MembershipRow, type MembershipStatus } from '@/lib/types';
import { STATUS_LABEL, STATUS_TONE, periodLabel } from './planFormat';
import { CancelMembershipDialog, RecordMembershipPaymentDialog, type CancelTarget, type PaymentTarget } from './MembershipDialogs';

function RowActions({ row, canManage, onPay, onCancel, onOpenCustomer }: { row: MembershipRow; canManage: boolean; onPay: () => void; onCancel: () => void; onOpenCustomer: () => void }) {
  const [anchor, setAnchor] = React.useState<null | HTMLElement>(null);
  const live = ['pending', 'active', 'past_due'].includes(row.status);
  return (
    <>
      <IconButton aria-label={`Actions for ${row.ref}`} onClick={(e) => setAnchor(e.currentTarget)} size="small"><MSymbol name="more_vert" size={22} /></IconButton>
      <Menu anchorEl={anchor} open={Boolean(anchor)} onClose={() => setAnchor(null)}>
        <MenuItem onClick={() => { setAnchor(null); onOpenCustomer(); }}><ListItemIcon><MSymbol name="person" size={20} /></ListItemIcon>Open customer</MenuItem>
        {canManage && row.open_invoice && <MenuItem onClick={() => { setAnchor(null); onPay(); }}><ListItemIcon><MSymbol name="point_of_sale" size={20} /></ListItemIcon>Record payment · {rands(row.open_invoice.amount_cents)}</MenuItem>}
        {canManage && live && !row.cancel_at_period_end && <MenuItem onClick={() => { setAnchor(null); onCancel(); }} sx={{ color: tk.error }}><ListItemIcon><MSymbol name="cancel" size={20} style={{ color: tk.error }} /></ListItemIcon>Cancel membership</MenuItem>}
      </Menu>
    </>
  );
}

/** Members tab: `GET /admin/memberships` grid with record-payment / cancel row actions and the renewals job. */
export default function MembersGrid({ plans, canManage, onToast, onOpenCustomer }: { plans: MembershipPlan[]; canManage: boolean; onToast: (kind: 'success' | 'error' | 'info', message: string | unknown) => void; onOpenCustomer: (customerId: string) => void }) {
  const api = useApi();
  const qc = useQueryClient();
  const [status, setStatus] = React.useState<MembershipStatus | 'all'>('all');
  const [planCode, setPlanCode] = React.useState<string>('');
  const [search, setSearch] = React.useState('');
  const [q, setQ] = React.useState('');
  React.useEffect(() => { const t = setTimeout(() => setQ(search.trim()), 250); return () => clearTimeout(t); }, [search]);
  const list = useQuery({ queryKey: ['memberships', status, planCode, q], queryFn: () => api.listMemberships({ status, plan_code: planCode || undefined, q: q || undefined, limit: 200 }) });
  const [payTarget, setPayTarget] = React.useState<PaymentTarget | null>(null);
  const [cancelTarget, setCancelTarget] = React.useState<CancelTarget | null>(null);
  const renewals = useMutation({
    mutationFn: () => api.runMembershipRenewals(),
    onSuccess: (r) => { void qc.invalidateQueries({ queryKey: ['memberships'] }); void qc.invalidateQueries({ queryKey: ['membership-plans'] }); void qc.invalidateQueries({ queryKey: ['kpis'] }); onToast('success', `Renewals run · ${r.invoiced} invoiced · ${r.renewed} renewed · ${r.past_due} past due · ${r.expired} expired`); },
    onError: (e) => onToast('error', e),
  });

  const columns: GridColDef<MembershipRow>[] = [
    { field: 'customer', headerName: 'Member', flex: 1.4, minWidth: 210, valueGetter: (_v, r) => r.customer.full_name, renderCell: (p) => (
      <Box sx={{ display: 'flex', alignItems: 'center', gap: 1.25, minWidth: 0 }}>
        <Avatar sx={{ width: 34, height: 34, fontSize: 13, fontWeight: 700, bgcolor: tk.secondaryContainer, color: tk.onSecondaryContainer }}>{initials(p.row.customer.full_name)}</Avatar>
        <Box sx={{ minWidth: 0 }}><Typography variant="h6" component="span" sx={{ display: 'block' }}>{p.row.customer.full_name}</Typography><Typography variant="caption" color="text.secondary"><span className="mono">{p.row.ref}</span> · {formatPhone(p.row.customer.phone)}</Typography></Box>
      </Box>
    ) },
    { field: 'plan', headerName: 'Plan', flex: 0.9, minWidth: 130, valueGetter: (_v, r) => r.plan.name, renderCell: (p) => <TierChip tier={p.row.plan.tier} label={`${p.row.plan.name} · ${rands(p.row.plan.monthly_fee_cents)}`} /> },
    { field: 'status', headerName: 'Status', flex: 0.8, minWidth: 120, renderCell: (p) => <StatusChip tone={STATUS_TONE[p.row.status]} label={p.row.cancel_at_period_end && p.row.status === 'active' ? `Ends ${fmtDate(p.row.current_period_end)}` : STATUS_LABEL[p.row.status]} /> },
    { field: 'period', headerName: 'Period', flex: 1, minWidth: 150, valueGetter: (_v, r) => r.current_period_start, renderCell: (p) => (
      <Box><Typography variant="body2">{periodLabel(p.row.current_period_start, p.row.current_period_end)}</Typography><Typography variant="caption" color="text.secondary">{Object.values(p.row.selections).join(' + ') || 'all included'} · pays by {p.row.payment_method}</Typography></Box>
    ) },
    { field: 'usage', headerName: 'Used / remaining', flex: 1, minWidth: 160, valueGetter: (_v, r) => r.remaining, renderCell: (p) => (
      <Box>
        <Typography variant="body2" sx={{ fontWeight: 700, fontVariantNumeric: 'tabular-nums' }}>{p.row.used} used · {p.row.remaining} left</Typography>
        <Typography variant="caption" color="text.secondary">{p.row.allowances.map((a) => `${a.entitlement_code} ${a.remaining}/${a.quantity}`).join(' · ')}</Typography>
      </Box>
    ) },
    { field: 'open_invoice', headerName: 'Open invoice', flex: 0.9, minWidth: 170, valueGetter: (_v, r) => r.open_invoice?.amount_cents ?? 0, renderCell: (p) => (p.row.open_invoice ? (
      <Box>
        <StatusChip tone={p.row.status === 'past_due' ? 'error' : 'warning'} label={`${rands(p.row.open_invoice.amount_cents)} · due ${fmtDate(p.row.open_invoice.due_at)}`} title={p.row.open_invoice.ref} />
        <Typography variant="caption" color="text.secondary" sx={{ display: 'block', mt: 0.25 }} className="mono">{p.row.open_invoice.ref}</Typography>
      </Box>
    ) : <Typography variant="body2" color="text.secondary">—</Typography>) },
    { field: 'actions', headerName: '', width: 56, sortable: false, align: 'right', renderCell: (p) => (
      <RowActions
        row={p.row}
        canManage={canManage}
        onOpenCustomer={() => onOpenCustomer(p.row.customer.id)}
        onPay={() => p.row.open_invoice && setPayTarget({ membershipId: p.row.id, customerId: p.row.customer.id, customerName: p.row.customer.full_name, planName: p.row.plan.name, invoice: p.row.open_invoice })}
        onCancel={() => setCancelTarget({ membershipId: p.row.id, customerId: p.row.customer.id, customerName: p.row.customer.full_name, planName: p.row.plan.name, periodEnd: p.row.current_period_end })}
      />
    ) },
  ];

  const rows = list.data?.data ?? [];
  return (
    <>
      <Box sx={{ display: 'flex', gap: 1.5, flexWrap: 'wrap', alignItems: 'center' }}>
        <TextField placeholder="Search members…" value={search} onChange={(e) => setSearch(e.target.value)} size="small" aria-label="Search members" sx={{ minWidth: 240 }} slotProps={{ input: { startAdornment: <InputAdornment position="start"><MSymbol name="search" size={20} /></InputAdornment> } }} />
        <TextField select label="Status" value={status} onChange={(e) => setStatus(e.target.value as MembershipStatus | 'all')} size="small" sx={{ minWidth: 150 }}>
          <MenuItem value="all">All statuses</MenuItem>
          {MEMBERSHIP_STATUSES.map((s) => <MenuItem key={s} value={s}>{STATUS_LABEL[s]}</MenuItem>)}
        </TextField>
        <TextField select label="Plan" value={planCode} onChange={(e) => setPlanCode(e.target.value)} size="small" sx={{ minWidth: 150 }}>
          <MenuItem value="">All plans</MenuItem>
          {plans.map((p) => <MenuItem key={p.code} value={p.code}>{p.name}</MenuItem>)}
        </TextField>
        <Box sx={{ flex: 1 }} />
        {canManage && <NavyPill icon="autorenew" onClick={() => renewals.mutate()} disabled={renewals.isPending}>{renewals.isPending ? 'Running…' : 'Run renewals'}</NavyPill>}
      </Box>
      <SectionCard flush title="Members" subtitle={list.data ? `${rows.length} membership${rows.length === 1 ? '' : 's'} · renewals invoiced 3 days ahead, past due when unpaid at period end` : undefined}>
        <Box sx={{ px: 1.5, pb: 1 }}>
          {list.error ? <ErrorState error={list.error} onRetry={() => list.refetch()} /> : (
            <AdminGrid<MembershipRow>
              rows={rows}
              columns={columns}
              loading={list.isLoading}
              getRowClassName={(p) => (p.row.status === 'past_due' ? 'row-error' : p.row.open_invoice ? 'row-warning' : '')}
              slots={{ noRowsOverlay: () => <Box sx={{ p: 4, textAlign: 'center' }}><Typography color="text.secondary">No memberships match.</Typography>{canManage && <Button size="small" sx={{ mt: 1 }} onClick={() => { setStatus('all'); setPlanCode(''); setSearch(''); }}>Clear filters</Button>}</Box> }}
            />
          )}
        </Box>
      </SectionCard>
      <RecordMembershipPaymentDialog target={payTarget} onClose={() => setPayTarget(null)} onDone={(m) => onToast('success', m)} onError={(e) => onToast('error', e)} />
      <CancelMembershipDialog target={cancelTarget} onClose={() => setCancelTarget(null)} onDone={(m) => onToast('info', m)} onError={(e) => onToast('error', e)} />
    </>
  );
}
