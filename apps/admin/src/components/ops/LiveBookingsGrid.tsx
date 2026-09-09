'use client';
import * as React from 'react';
import Box from '@mui/material/Box';
import Menu from '@mui/material/Menu';
import MenuItem from '@mui/material/MenuItem';
import Typography from '@mui/material/Typography';
import type { GridColDef } from '@mui/x-data-grid';
import SectionCard from '@/components/ui/SectionCard';
import AdminGrid from '@/components/ui/AdminGrid';
import StatusChip from '@/components/ui/StatusChip';
import { TonalPill } from '@/components/ui/Pills';
import { EmptyState } from '@/components/ui/States';
import { fonts, tk } from '@/theme/tokens';
import { fmtTime, rands, statusLabel } from '@/lib/format';
import type { Booking, BookingStatus } from '@/lib/types';

const STATUSES: (BookingStatus | 'all')[] = ['all', 'pending', 'confirmed', 'in_service', 'completed', 'cancelled'];

export const bookingColumns: GridColDef<Booking>[] = [
  { field: 'ref', headerName: 'Ref', flex: 1, minWidth: 130, renderCell: (p) => <span className="mono" style={{ color: tk.primary, fontWeight: 700 }}>{p.row.ref}</span> },
  { field: 'customer', headerName: 'Customer', flex: 1.3, minWidth: 150, valueGetter: (_v, r) => r.customer.full_name },
  { field: 'vehicle', headerName: 'Vehicle', flex: 1.1, minWidth: 130, valueGetter: (_v, r) => r.vehicle.registration_no, renderCell: (p) => <span className="mono">{p.row.vehicle.registration_no}</span> },
  { field: 'service', headerName: 'Service', flex: 1.3, minWidth: 150, valueGetter: (_v, r) => r.service.name, renderCell: (p) => <span>{p.row.quotation_id ? `Quote · ${p.row.service.name}` : p.row.service.name}</span> },
  { field: 'slot', headerName: 'Slot', flex: 0.8, minWidth: 90, valueGetter: (_v, r) => r.slot_start, renderCell: (p) => fmtTime(p.row.slot_start) },
  { field: 'status', headerName: 'Status', flex: 1, minWidth: 130, renderCell: (p) => <StatusChip status={p.row.status} /> },
  { field: 'amount', headerName: 'Amount', flex: 0.8, minWidth: 100, align: 'right', headerAlign: 'right', valueGetter: (_v, r) => r.total_cents, renderCell: (p) => <Box component="span" sx={{ fontWeight: 700, fontFamily: fonts.sans }}>{rands(p.row.total_cents)}</Box> },
];

export default function LiveBookingsGrid({ rows, loading, onOpen, title = 'Live bookings' }: { rows: Booking[] | undefined; loading?: boolean; onOpen: (b: Booking) => void; title?: string }) {
  const [status, setStatus] = React.useState<BookingStatus | 'all'>('all');
  const [anchor, setAnchor] = React.useState<null | HTMLElement>(null);
  const filtered = React.useMemo(() => (rows ?? []).filter((b) => status === 'all' || b.status === status), [rows, status]);
  return (
    <SectionCard
      title={title}
      flush
      actions={
        <>
          <TonalPill icon="filter_list" endIcon={null} onClick={(e) => setAnchor(e.currentTarget)} sx={{ bgcolor: 'transparent', color: tk.onSurfaceVariant }} aria-haspopup="menu" aria-expanded={Boolean(anchor)}>
            Status · {status === 'all' ? 'All' : statusLabel(status)}
          </TonalPill>
          <Menu anchorEl={anchor} open={Boolean(anchor)} onClose={() => setAnchor(null)}>
            {STATUSES.map((s) => (
              <MenuItem key={s} selected={s === status} onClick={() => { setStatus(s); setAnchor(null); }}>{s === 'all' ? 'All statuses' : statusLabel(s)}</MenuItem>
            ))}
          </Menu>
        </>
      }
    >
      <Box sx={{ px: 1.5, pb: 1 }}>
        {!loading && !filtered.length ? (
          <EmptyState icon="event_busy" title="No bookings" description="Nothing scheduled for this filter." />
        ) : (
          <AdminGrid<Booking>
            rows={filtered}
            columns={bookingColumns}
            loading={loading && !rows}
            getRowClassName={() => 'row-clickable'}
            onRowClick={(p) => onOpen(p.row)}
            initialState={{ sorting: { sortModel: [{ field: 'slot', sort: 'asc' }] } }}
            slots={{ noRowsOverlay: () => <Typography sx={{ p: 3 }} color="text.secondary">No bookings</Typography> }}
          />
        )}
      </Box>
    </SectionCard>
  );
}
