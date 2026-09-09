'use client';
import * as React from 'react';
import Box from '@mui/material/Box';
import { useQuery } from '@tanstack/react-query';
import PageHeader from '@/components/layout/PageHeader';
import { LiveChip, NavyPill, OutletPill, PeriodPill } from '@/components/ui/Pills';
import KpiRow from '@/components/ops/KpiRow';
import BookingsByHourChart from '@/components/ops/BookingsByHourChart';
import RevenueByOutlet from '@/components/ops/RevenueByOutlet';
import ExceptionsList from '@/components/ops/ExceptionsList';
import ActivityFeed from '@/components/ops/ActivityFeed';
import LiveBookingsGrid from '@/components/ops/LiveBookingsGrid';
import BookingDrawer from '@/components/bookings/BookingDrawer';
import { useApi, useAuth } from '@/lib/auth/AuthProvider';
import { useFilters } from '@/lib/filters';
import { useExport, useLive } from '@/lib/hooks';
import { can } from '@/lib/rbac';

export default function OverviewPage() {
  const api = useApi();
  const { role } = useAuth();
  const { outletId, period } = useFilters();
  const { updatedAt, mode } = useLive(['kpis', 'exceptions', 'activity', 'bookings']);
  const { exportCsv, busy } = useExport();
  const [focus, setFocus] = React.useState<string | null>(null);

  const kpis = useQuery({ queryKey: ['kpis', outletId, period], queryFn: () => api.kpis({ outlet_id: outletId, period }) });
  const exceptions = useQuery({ queryKey: ['exceptions', outletId], queryFn: () => api.exceptions({ outlet_id: outletId }) });
  const activity = useQuery({ queryKey: ['activity', outletId], queryFn: () => api.activity({ outlet_id: outletId, limit: 6 }) });
  const bookings = useQuery({ queryKey: ['bookings', outletId, 'today'], queryFn: () => api.listBookings({ outlet_id: outletId, limit: 100 }) });

  return (
    <>
      <PageHeader
        title="Operations overview"
        subtitle={<LiveChip updatedAt={updatedAt} mode={mode} />}
        actions={
          <>
            <OutletPill />
            <PeriodPill />
            {can(role, 'export:csv') && (
              <NavyPill icon="download" onClick={() => void exportCsv('bookings', { date: new Date().toISOString().slice(0, 10) })} disabled={busy === 'bookings'}>
                Export CSV
              </NavyPill>
            )}
          </>
        }
      />
      <KpiRow kpis={kpis.data} />
      <Box sx={{ display: 'grid', gridTemplateColumns: { xs: '1fr', lg: '1.6fr 1fr' }, gap: '14px' }}>
        <BookingsByHourChart data={kpis.data?.bookings_by_hour} />
        <ExceptionsList items={exceptions.data} loading={exceptions.isLoading} />
      </Box>
      <Box sx={{ display: 'grid', gridTemplateColumns: { xs: '1fr', lg: '1.6fr 1fr' }, gap: '14px' }}>
        <RevenueByOutlet kpis={kpis.data} />
        <ActivityFeed items={activity.data} />
      </Box>
      <LiveBookingsGrid rows={bookings.data?.data} loading={bookings.isLoading} onOpen={(b) => setFocus(b.id)} />
      <BookingDrawer bookingId={focus} onClose={() => setFocus(null)} />
    </>
  );
}
