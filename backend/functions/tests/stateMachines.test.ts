import { describe, expect, it } from 'vitest';
import {
  bookingIsCancellable,
  canTransition,
  canTransitionBooking,
  canTransitionPayment,
  canTransitionQuotation,
  canTransitionWork,
} from '../src/domain/stateMachines.js';

describe('booking state machine (CUS-025)', () => {
  it('follows draft → pending → confirmed → in_service → completed', () => {
    expect(canTransitionBooking('draft', 'pending')).toBe(true);
    expect(canTransitionBooking('pending', 'confirmed')).toBe(true);
    expect(canTransitionBooking('confirmed', 'in_service')).toBe(true);
    expect(canTransitionBooking('in_service', 'completed')).toBe(true);
  });
  it('allows cancel only before in_service', () => {
    expect(bookingIsCancellable('pending')).toBe(true);
    expect(bookingIsCancellable('confirmed')).toBe(true);
    expect(bookingIsCancellable('in_service')).toBe(false);
    expect(bookingIsCancellable('completed')).toBe(false);
  });
  it('rejects skipping states', () => {
    expect(canTransitionBooking('pending', 'in_service')).toBe(false);
    expect(canTransitionBooking('completed', 'pending')).toBe(false);
  });
});

describe('quotation state machine (CUS-033/034)', () => {
  it('requested → quoted → accepted → converted', () => {
    expect(canTransitionQuotation('requested', 'quoted')).toBe(true);
    expect(canTransitionQuotation('quoted', 'accepted')).toBe(true);
    expect(canTransitionQuotation('accepted', 'converted')).toBe(true);
  });
  it('declined/expired/converted are terminal', () => {
    expect(canTransitionQuotation('declined', 'quoted')).toBe(false);
    expect(canTransitionQuotation('converted', 'accepted')).toBe(false);
    expect(canTransitionQuotation('expired', 'accepted')).toBe(false);
  });
});

describe('work/task state machine (STF-023)', () => {
  it('queued → assigned → in_progress ⇄ blocked → completed → verified', () => {
    expect(canTransitionWork('queued', 'assigned')).toBe(true);
    expect(canTransitionWork('assigned', 'in_progress')).toBe(true);
    expect(canTransitionWork('in_progress', 'blocked')).toBe(true);
    expect(canTransitionWork('blocked', 'in_progress')).toBe(true);
    expect(canTransitionWork('in_progress', 'completed')).toBe(true);
    expect(canTransitionWork('completed', 'verified')).toBe(true);
  });
  it('cannot verify from in_progress or re-open verified', () => {
    expect(canTransitionWork('in_progress', 'verified')).toBe(false);
    expect(canTransitionWork('verified', 'in_progress')).toBe(false);
    expect(canTransitionWork('blocked', 'completed')).toBe(false);
  });
});

describe('payment state machine (CUS-041)', () => {
  it('initiated → pending → successful → refunded', () => {
    expect(canTransitionPayment('initiated', 'pending')).toBe(true);
    expect(canTransitionPayment('pending', 'successful')).toBe(true);
    expect(canTransitionPayment('successful', 'refunded')).toBe(true);
  });
  it('failed is terminal; successful cannot fail', () => {
    expect(canTransitionPayment('failed', 'successful')).toBe(false);
    expect(canTransitionPayment('successful', 'failed')).toBe(false);
  });
});

describe('generic canTransition', () => {
  it('dispatches by machine and rejects unknown states', () => {
    expect(canTransition('booking', 'pending', 'confirmed')).toBe(true);
    expect(canTransition('work', 'nope', 'assigned')).toBe(false);
    expect(canTransition('payment', 'pending', 'bogus')).toBe(false);
  });
});
