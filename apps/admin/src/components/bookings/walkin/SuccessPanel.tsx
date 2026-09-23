'use client';
import * as React from 'react';
import Box from '@mui/material/Box';
import Typography from '@mui/material/Typography';
import Button from '@mui/material/Button';
import MSymbol from '@/components/MSymbol';
import SectionCard from '@/components/ui/SectionCard';
import StatusChip from '@/components/ui/StatusChip';
import Tile from '@/components/ui/Tile';
import type { WalkInResult } from './useWalkInDraft';
import { fmtDateTime, fmtTime, rands } from '@/lib/format';
import { formatPhone } from '@/lib/phone';
import { fonts, tk } from '@/theme/tokens';

function Row({ icon, label, value }: { icon: string; label: string; value: React.ReactNode }) {
  return (
    <Box sx={{ display: 'flex', alignItems: 'center', gap: 1.5, py: 1 }}>
      <MSymbol name={icon} filled size={22} style={{ color: tk.primary }} />
      <Typography variant="body2" color="text.secondary" sx={{ width: 110, flexShrink: 0 }}>{label}</Typography>
      <Typography component="div" sx={{ fontWeight: 600, minWidth: 0 }}>{value}</Typography>
    </Box>
  );
}

export default function SuccessPanel({ result, onOpenBooking, onNew, onDone }: { result: WalkInResult; onOpenBooking: () => void; onNew: () => void; onDone: () => void }) {
  const { booking: b, payment, work_order: wo } = result;
  const headingRef = React.useRef<HTMLHeadingElement>(null);
  React.useEffect(() => {
    document.getElementById('main')?.scrollTo({ top: 0 });
    headingRef.current?.focus({ preventScroll: true });
  }, []);
  const methodLabel = payment ? (payment.method === 'cash' ? 'Cash' : 'Card terminal') : b.total_cents === 0 && b.membership_benefit === 'included' ? `included in ${b.membership?.plan_name ?? 'the plan'}` : 'Customer pays in app';
  return (
    <SectionCard component="section" sx={{ maxWidth: 720, mx: 'auto', width: '100%', alignItems: 'center', textAlign: 'center', gap: 2, py: 5 }}>
      <Box sx={{ position: 'relative', width: 128, height: 128, borderRadius: '50%', bgcolor: tk.primaryContainer, display: 'grid', placeItems: 'center' }} aria-hidden>
        <Box sx={{ width: 96, height: 96, borderRadius: '50%', bgcolor: tk.primary, color: tk.onPrimary, display: 'grid', placeItems: 'center' }}>
          <MSymbol name="check" size={56} weight={700} />
        </Box>
        <Box sx={{ position: 'absolute', top: 6, right: 6, width: 14, height: 14, borderRadius: '50%', bgcolor: tk.azure }} />
        <Box sx={{ position: 'absolute', bottom: 12, left: -4, width: 12, height: 12, borderRadius: '50%', bgcolor: tk.gold }} />
      </Box>
      <Box>
        <Typography ref={headingRef} tabIndex={-1} variant="h1" component="h2" sx={{ fontSize: 30, outline: 'none' }}>Walk-in confirmed</Typography>
        <Typography color="text.secondary" sx={{ mt: 1 }}>
          {b.outlet.name} is expecting {b.customer.full_name.split(' ')[0]}’s {[b.vehicle.make, b.vehicle.model].filter(Boolean).join(' ') || b.vehicle.registration_no}.
        </Typography>
        <Typography component="div" sx={{ mt: 1, display: 'flex', gap: 1, justifyContent: 'center', alignItems: 'center', flexWrap: 'wrap' }}>
          <span>Reference</span>
          <Box component="span" className="mono" sx={{ fontWeight: 700, fontSize: 18, color: tk.primary }}>{b.ref}</Box>
          {payment?.receipt_no && (
            <>
              <span>· Receipt</span>
              <Box component="span" className="mono" sx={{ fontWeight: 700, fontSize: 18 }}>{payment.receipt_no}</Box>
            </>
          )}
          <StatusChip status={b.status} />
          <StatusChip tone="secondary" label="Walk-in" />
        </Typography>
      </Box>

      <Tile sx={{ flexDirection: 'column', alignItems: 'stretch', gap: 0, width: '100%', textAlign: 'left', px: 2.5 }}>
        <Row icon="person" label="Customer" value={<>{b.customer.full_name}{b.customer.phone ? <Typography component="span" variant="body2" color="text.secondary"> · {formatPhone(b.customer.phone)}</Typography> : null}</>} />
        <Row icon="directions_car" label="Vehicle" value={<><span style={{ fontFamily: fonts.mono }}>{b.vehicle.registration_no}</span>{b.vehicle.make ? ` · ${b.vehicle.make} ${b.vehicle.model ?? ''}` : ''}</>} />
        <Row icon="event" label="Slot" value={`${fmtDateTime(b.slot_start)} – ${fmtTime(b.slot_end)} · ${b.outlet.name}`} />
        <Row icon="local_car_wash" label="Service" value={`${b.service.name} · ${payment ? `paid ${rands(payment.amount_cents, { decimals: true })} (${methodLabel})` : `${rands(b.total_cents, { decimals: true })} · ${methodLabel}`}`} />
        {b.discount_cents > 0 && <Row icon="sell" label="Discount" value={`${b.discount_label ?? 'Discount'} · −${rands(b.discount_cents, { decimals: true })}`} />}
        {wo && <Row icon="checklist" label="Work order" value={<><span style={{ fontFamily: fonts.mono }}>{wo.ref}</span>{wo.bay ? ` · ${wo.bay}` : ''} · {wo.checked_in_at === null ? 'awaiting check-in' : (wo.assignee_name ?? 'unassigned')}</>} />}
        <Row icon="loyalty" label="Points" value={`+${b.points_pending} pts pending completion`} />
      </Tile>

      <Tile tone="navy" sx={{ width: '100%', textAlign: 'left', gap: 1.5 }}>
        <MSymbol name="notifications_active" filled size={22} />
        <Typography variant="body2" sx={{ color: 'inherit' }}>
          {b.customer.phone ? 'The customer is notified on WhatsApp / push when the wash starts and when the car is ready.' : 'No phone on file — tell the customer when the car is ready.'}
        </Typography>
      </Tile>

      <Box sx={{ display: 'flex', gap: 1.5, flexWrap: 'wrap', justifyContent: 'center', mt: 1 }}>
        <Button variant="outlined" onClick={onDone} sx={{ px: 3 }}>Done</Button>
        <Button variant="outlined" onClick={onNew} startIcon={<MSymbol name="person_add" size={20} />} sx={{ px: 3 }}>New walk-in</Button>
        <Button variant="contained" color="secondary" onClick={onOpenBooking} startIcon={<MSymbol name="open_in_new" size={20} />} sx={{ px: 3 }}>Open booking</Button>
      </Box>
    </SectionCard>
  );
}
