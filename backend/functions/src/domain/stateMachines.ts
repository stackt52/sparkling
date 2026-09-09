/**
 * Server-validated state machines (ARCHITECTURE.md "State machines").
 * Pure functions: no I/O, fully unit-tested.
 */
import type { BookingStatus, PaymentStatus, QuotationStatus, WorkStatus } from '../types.js';

type Transitions<S extends string> = Record<S, readonly S[]>;

export const BOOKING_TRANSITIONS: Transitions<BookingStatus> = {
  draft: ['pending', 'cancelled'],
  pending: ['confirmed', 'cancelled'],
  confirmed: ['in_service', 'cancelled'],
  in_service: ['completed'],
  completed: [],
  cancelled: [],
};

export const QUOTATION_TRANSITIONS: Transitions<QuotationStatus> = {
  requested: ['assessing', 'quoted', 'declined', 'expired'],
  assessing: ['quoted', 'declined', 'expired'],
  quoted: ['accepted', 'declined', 'expired'],
  accepted: ['converted', 'expired'],
  declined: [],
  expired: [],
  converted: [],
};

/** Work orders and tasks share the same lifecycle. */
export const WORK_TRANSITIONS: Transitions<WorkStatus> = {
  queued: ['assigned', 'in_progress', 'cancelled'],
  assigned: ['in_progress', 'queued', 'cancelled'],
  in_progress: ['blocked', 'completed', 'cancelled'],
  blocked: ['in_progress', 'cancelled'],
  completed: ['verified', 'in_progress'],
  verified: [],
  cancelled: [],
};

export const PAYMENT_TRANSITIONS: Transitions<PaymentStatus> = {
  initiated: ['pending', 'failed', 'cancelled'],
  pending: ['successful', 'failed', 'cancelled'],
  successful: ['refunded'],
  failed: [],
  cancelled: [],
  refunded: [],
};

function makeCan<S extends string>(table: Transitions<S>) {
  return (from: S, to: S): boolean => {
    const allowed = table[from];
    return Array.isArray(allowed) && allowed.includes(to);
  };
}

export const canTransitionBooking = makeCan(BOOKING_TRANSITIONS);
export const canTransitionQuotation = makeCan(QUOTATION_TRANSITIONS);
export const canTransitionWork = makeCan(WORK_TRANSITIONS);
export const canTransitionPayment = makeCan(PAYMENT_TRANSITIONS);

export type Machine = 'booking' | 'quotation' | 'work' | 'payment';

export function canTransition(machine: Machine, from: string, to: string): boolean {
  switch (machine) {
    case 'booking':
      return canTransitionBooking(from as BookingStatus, to as BookingStatus);
    case 'quotation':
      return canTransitionQuotation(from as QuotationStatus, to as QuotationStatus);
    case 'work':
      return canTransitionWork(from as WorkStatus, to as WorkStatus);
    case 'payment':
      return canTransitionPayment(from as PaymentStatus, to as PaymentStatus);
    default:
      return false;
  }
}

/** Booking may be cancelled by customer/staff until it enters service (CUS-025). */
export function bookingIsCancellable(status: BookingStatus): boolean {
  return canTransitionBooking(status, 'cancelled');
}

export const TERMINAL_WORK_STATUSES: readonly WorkStatus[] = ['verified', 'cancelled'];
export const ACTIVE_WORK_STATUSES: readonly WorkStatus[] = ['assigned', 'in_progress', 'blocked'];
export const OPEN_WORK_STATUSES: readonly WorkStatus[] = ['queued', 'assigned', 'in_progress', 'blocked', 'completed'];
