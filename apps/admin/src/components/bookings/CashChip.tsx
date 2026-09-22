'use client';
import MSymbol from '@/components/MSymbol';
import StatusChip from '@/components/ui/StatusChip';
import { rands } from '@/lib/format';
import type { Booking } from '@/lib/types';

/** True while a cash-on-collection booking still has to be paid at the counter. */
export function cashDue(b: Pick<Booking, 'payment_method' | 'payment' | 'total_cents' | 'status'>): boolean {
  return b.payment_method === 'cash' && b.total_cents > 0 && b.payment?.status !== 'successful' && b.status !== 'cancelled';
}

/**
 * "Cash due R x" (warning) while a cash-on-collection booking is unpaid, "Paid · cash" once the counter payment
 * is recorded. Renders nothing for other payment methods.
 */
export default function CashChip({ booking, size = 'small' }: { booking: Pick<Booking, 'payment_method' | 'payment' | 'total_cents' | 'status'>; size?: 'small' | 'medium' }) {
  if (booking.payment_method !== 'cash') return null;
  const due = cashDue(booking);
  const paid = booking.payment?.status === 'successful';
  const label = paid ? 'Paid · cash' : due ? `Cash due ${rands(booking.total_cents)}` : 'Cash';
  const dims = size === 'small' ? { height: 20, fontSize: 11 } : { height: 24, fontSize: 12 };
  return (
    <StatusChip
      tone={paid ? 'success' : due ? 'warning' : 'neutral'}
      label={label}
      icon={<MSymbol name="payments" filled size={size === 'small' ? 14 : 16} style={{ color: 'inherit' }} />}
      sx={{ ...dims, '& .MuiChip-icon': { color: 'inherit', ml: '6px' } }}
      data-testid="cash-chip"
    />
  );
}
