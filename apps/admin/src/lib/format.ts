import { format, formatDistanceToNowStrict, isToday, isValid, parseISO } from 'date-fns';
import type { BookingStatus, PaymentStatus, QuotationStatus, WorkStatus } from './types';

/** ZAR with thin-space thousands: 18420 cents → "R 184.20"; whole rands → "R 18 420". */
export function rands(cents: number, opts: { compact?: boolean; decimals?: boolean } = {}): string {
  const value = cents / 100;
  if (opts.compact && Math.abs(value) >= 1000) {
    return `R ${(value / 1000).toFixed(1).replace(/\.0$/, '')}k`;
  }
  const showDecimals = opts.decimals ?? value % 1 !== 0;
  const fixed = showDecimals ? value.toFixed(2) : Math.round(value).toString();
  const [int, dec] = fixed.split('.');
  const grouped = int.replace(/\B(?=(\d{3})+(?!\d))/g, ' ');
  return `R ${grouped}${dec ? `.${dec}` : ''}`;
}

export function num(n: number): string {
  return Math.round(n).toString().replace(/\B(?=(\d{3})+(?!\d))/g, ' ');
}

export function toDate(iso: string | null | undefined): Date | null {
  if (!iso) return null;
  const d = parseISO(iso);
  return isValid(d) ? d : null;
}

export function fmtTime(iso: string | null | undefined): string {
  const d = toDate(iso);
  return d ? format(d, 'HH:mm') : '—';
}

export function fmtClock(d: Date): string {
  return format(d, 'HH:mm:ss');
}

export function fmtDate(iso: string | null | undefined, pattern = 'd MMM'): string {
  const d = toDate(iso);
  return d ? format(d, pattern) : '—';
}

export function fmtDateTime(iso: string | null | undefined): string {
  const d = toDate(iso);
  if (!d) return '—';
  return isToday(d) ? `Today ${format(d, 'HH:mm')}` : format(d, 'd MMM HH:mm');
}

export function fmtAgo(iso: string | null | undefined): string {
  const d = toDate(iso);
  return d ? `${formatDistanceToNowStrict(d)} ago` : '—';
}

export function initials(name: string): string {
  return name
    .split(/\s+/)
    .filter(Boolean)
    .slice(0, 2)
    .map((p) => p[0]?.toUpperCase() ?? '')
    .join('');
}

const labels: Record<string, string> = {
  draft: 'Draft',
  pending: 'Pending',
  confirmed: 'Confirmed',
  in_service: 'In service',
  completed: 'Completed',
  cancelled: 'Cancelled',
  requested: 'Requested',
  assessing: 'Assessing',
  quoted: 'Quote sent',
  accepted: 'Accepted',
  declined: 'Declined',
  expired: 'Expired',
  converted: 'Converted',
  queued: 'Queued',
  assigned: 'Assigned',
  in_progress: 'In progress',
  blocked: 'Blocked',
  verified: 'Verified',
  initiated: 'Initiated',
  successful: 'Successful',
  failed: 'Failed',
  refunded: 'Refunded',
};

export function statusLabel(s: BookingStatus | QuotationStatus | WorkStatus | PaymentStatus | string): string {
  return labels[s] ?? s.replace(/_/g, ' ');
}

export function titleCase(s: string): string {
  return s.replace(/_/g, ' ').replace(/\b\w/g, (c) => c.toUpperCase());
}
