'use client';
import * as React from 'react';
import { useSearchParams } from 'next/navigation';
import Box from '@mui/material/Box';
import TextField from '@mui/material/TextField';
import InputAdornment from '@mui/material/InputAdornment';
import MenuItem from '@mui/material/MenuItem';
import { useQuery } from '@tanstack/react-query';
import { format } from 'date-fns';
import PageHeader from '@/components/layout/PageHeader';
import { LiveChip, NavyPill, OutletPill } from '@/components/ui/Pills';
import LiveBookingsGrid from '@/components/ops/LiveBookingsGrid';
import BookingDrawer from '@/components/bookings/BookingDrawer';
import MSymbol from '@/components/MSymbol';
import { useApi, useAuth } from '@/lib/auth/AuthProvider';
import { useFilters } from '@/lib/filters';
import { useExport, useLive } from '@/lib/hooks';
import { can } from '@/lib/rbac';
import { statusLabel } from '@/lib/format';
import type { BookingStatus } from '@/lib/types';

const STATUSES: (BookingStatus | 'all')[] = ['all', 'pending', 'confirmed', 'in_service', 'completed', 'cancelled'];

export default function BookingsPage() {
  const api = useApi();
  const { role } = useAuth();
  const { outletId } = useFilters();
  const params = useSearchParams();
  const { updatedAt, mode } = useLive(['bookings']);
  const { exportCsv, busy } = useExport();
  const [date, setDate] = React.useState(format(new Date(), 'yyyy-MM-dd'));
  const [status, setStatus] = React.useState<BookingStatus | 'all'>('all');
  const [search, setSearch] = React.useState('');
  const [focus, setFocus] = React.useState<string | null>(params.get('focus'));

  const q = useQuery({ queryKey: ['bookings', outletId, date, status, search], queryFn: () => api.listBookings({ outlet_id: outletId, date, status, search, limit: 200 }) });

  return (
    <>
      <PageHeader
        title="Bookings"
        subtitle={<LiveChip updatedAt={updatedAt} mode={mode} />}
        actions={
          <>
            <OutletPill />
            {can(role, 'export:csv') && (
              <NavyPill icon="download" onClick={() => void exportCsv('bookings', { date, status: status === 'all' ? undefined : status })} disabled={busy === 'bookings'}>Export CSV</NavyPill>
            )}
          </>
        }
      />
      <Box sx={{ display: 'flex', gap: 1.5, flexWrap: 'wrap' }}>
        <TextField type="date" label="Date" value={date} onChange={(e) => setDate(e.target.value)} size="small" slotProps={{ inputLabel: { shrink: true } }} sx={{ minWidth: 180 }} />
        <TextField select label="Status" value={status} onChange={(e) => setStatus(e.target.value as BookingStatus | 'all')} size="small" sx={{ minWidth: 170 }}>
          {STATUSES.map((s) => <MenuItem key={s} value={s}>{s === 'all' ? 'All statuses' : statusLabel(s)}</MenuItem>)}
        </TextField>
        <TextField
          label="Search"
          placeholder="Ref, customer or plate"
          value={search}
          onChange={(e) => setSearch(e.target.value)}
          size="small"
          sx={{ minWidth: 260 }}
          slotProps={{ input: { startAdornment: <InputAdornment position="start"><MSymbol name="search" size={20} /></InputAdornment> } }}
        />
      </Box>
      <LiveBookingsGrid title={`Bookings · ${format(new Date(date + 'T00:00:00'), 'EEE d MMM')}`} rows={q.data?.data} loading={q.isLoading} onOpen={(b) => setFocus(b.id)} />
      <BookingDrawer bookingId={focus} onClose={() => setFocus(null)} />
    </>
  );
}
