/**
 * CUS-020..026: booking creation (server-side pricing + slot validation),
 * cancel, reschedule, staff check-in.
 */
import { canTransitionBooking } from '../domain/stateMachines.js';
import { DatabaseError, getSupabase, PG_UNIQUE_VIOLATION, unwrap } from '../lib/supabase.js';
import { assertOutlet, assertOwner, assertOwnerOrOutletStaff, isStaff } from '../middleware/auth.js';
import { ApiError } from '../middleware/errors.js';
import type { Booking, RequestContext, Task, Vehicle, WorkOrder } from '../types.js';
import { audit } from './audit.js';
import { assertSlotAvailable } from './availability.js';
import { priceService } from './pricing.js';
import { createWorkOrderWithTask } from './workflow.js';

export interface CreateBookingInput {
  vehicleId: string;
  outletId: string;
  serviceId: string;
  slotStart: string;
  clientOpId: string;
  notes?: string | null;
  /** staff may create on behalf of a customer */
  customerId?: string;
}

export async function createBooking(ctx: RequestContext, input: CreateBookingInput): Promise<{ booking: Booking; duplicate: boolean }> {
  const db = getSupabase();
  const existing = await db.from('bookings').select('*').eq('client_op_id', input.clientOpId).maybeSingle();
  if (existing.data) return { booking: existing.data as Booking, duplicate: true };

  const customerId = input.customerId && isStaff(ctx.auth.role) ? input.customerId : ctx.auth.uid;
  const vehicle = unwrap<Vehicle | null>(await db.from('vehicles').select('*').eq('id', input.vehicleId).maybeSingle(), 'vehicle');
  if (!vehicle || !vehicle.is_active) throw ApiError.notFound('Vehicle');
  if (vehicle.customer_id !== customerId) throw ApiError.forbidden('Vehicle belongs to another customer');

  const { quote, service, outlet } = await priceService(input.outletId, input.serviceId, customerId);
  if (service.is_quote_based) throw ApiError.validation('This service requires a quotation; use POST /v1/quotations');
  const slot = await assertSlotAvailable(input.outletId, input.serviceId, input.slotStart, outlet.timezone);

  const res = await db
    .from('bookings')
    .insert({
      customer_id: customerId,
      vehicle_id: vehicle.id,
      outlet_id: outlet.id,
      service_id: service.id,
      slot_start: slot.slot_start,
      slot_end: slot.slot_end,
      status: 'pending',
      price_cents: quote.price_cents,
      discount_cents: quote.discount_cents,
      total_cents: quote.total_cents,
      discount_label: quote.discount_label,
      points_pending: quote.points_pending,
      notes: input.notes ?? null,
      client_op_id: input.clientOpId,
      created_by: ctx.auth.uid,
    })
    .select('*')
    .single();
  if (res.error) {
    if (res.error.code === PG_UNIQUE_VIOLATION) {
      const dup = unwrap<Booking>(await db.from('bookings').select('*').eq('client_op_id', input.clientOpId).single(), 'booking');
      return { booking: dup, duplicate: true };
    }
    throw new DatabaseError(res.error, 'create booking');
  }
  const booking = res.data as Booking;
  await audit(ctx, { action: 'booking.create', entity_type: 'booking', entity_id: booking.id, outlet_id: booking.outlet_id, after: { ref: booking.ref, total_cents: booking.total_cents } });
  return { booking, duplicate: false };
}

export async function getBookingOrThrow(id: string): Promise<Booking> {
  const b = unwrap<Booking | null>(await getSupabase().from('bookings').select('*').eq('id', id).maybeSingle(), 'booking');
  if (!b) throw ApiError.notFound('Booking');
  return b;
}

export async function cancelBooking(ctx: RequestContext, id: string, reason?: string | null): Promise<Booking> {
  const db = getSupabase();
  const booking = await getBookingOrThrow(id);
  assertOwnerOrOutletStaff(ctx.auth, booking);
  if (!canTransitionBooking(booking.status, 'cancelled')) throw ApiError.invalidTransition(booking.status, 'cancelled', 'booking');
  const updated = unwrap<Booking>(
    await db.from('bookings').update({ status: 'cancelled', cancel_reason: reason ?? null }).eq('id', id).select('*').single(),
    'cancel booking',
  );
  await db.from('work_orders').update({ status: 'cancelled' }).eq('booking_id', id).in('status', ['queued', 'assigned']);
  await audit(ctx, { action: 'booking.cancel', entity_type: 'booking', entity_id: id, outlet_id: booking.outlet_id, before: { status: booking.status }, after: { status: 'cancelled', reason } });
  return updated;
}

export async function rescheduleBooking(ctx: RequestContext, id: string, slotStart: string): Promise<Booking> {
  const db = getSupabase();
  const booking = await getBookingOrThrow(id);
  assertOwner(ctx.auth, booking);
  if (!['pending', 'confirmed'].includes(booking.status)) throw ApiError.invalidTransition(booking.status, booking.status, 'booking (reschedule)');
  const outlet = unwrap<{ timezone: string } | null>(await db.from('outlets').select('timezone').eq('id', booking.outlet_id).maybeSingle(), 'outlet');
  const slot = await assertSlotAvailable(booking.outlet_id, booking.service_id, slotStart, outlet?.timezone ?? 'Africa/Johannesburg');
  const updated = unwrap<Booking>(
    await db.from('bookings').update({ slot_start: slot.slot_start, slot_end: slot.slot_end }).eq('id', id).select('*').single(),
    'reschedule',
  );
  await db.from('work_orders').update({ eta_at: slot.slot_end, due_at: slot.slot_end }).eq('booking_id', id).in('status', ['queued', 'assigned']);
  await audit(ctx, { action: 'booking.reschedule', entity_type: 'booking', entity_id: id, outlet_id: booking.outlet_id, before: { slot_start: booking.slot_start }, after: { slot_start: slot.slot_start } });
  return updated;
}

export async function checkInBooking(ctx: RequestContext, id: string, opts: { bay?: string | null; priority?: number }): Promise<{ booking: Booking; work_order: WorkOrder; task: Task; created: boolean }> {
  const db = getSupabase();
  const booking = await getBookingOrThrow(id);
  assertOutlet(ctx.auth, booking.outlet_id);
  const service = unwrap<import('../types.js').Service>(await db.from('services').select('*').eq('id', booking.service_id).single(), 'service');
  let current = booking;
  if (current.status === 'pending' && canTransitionBooking(current.status, 'confirmed')) {
    // Walk-in check-in of an unpaid booking confirms it first.
    current = unwrap<Booking>(await db.from('bookings').update({ status: 'confirmed' }).eq('id', id).select('*').single(), 'confirm');
  }
  if (current.status !== 'in_service') {
    if (!canTransitionBooking(current.status, 'in_service')) throw ApiError.invalidTransition(current.status, 'in_service', 'booking');
    current = unwrap<Booking>(await db.from('bookings').update({ status: 'in_service' }).eq('id', id).select('*').single(), 'check in');
  }
  const eta = new Date(new Date(current.slot_start).getTime() + service.duration_minutes * 60_000).toISOString();
  const created = await createWorkOrderWithTask(ctx, {
    outletId: current.outlet_id,
    bookingId: current.id,
    vehicleId: current.vehicle_id,
    customerId: current.customer_id,
    service,
    bay: opts.bay ?? null,
    priority: opts.priority ?? 2,
    etaAt: eta,
    dueAt: eta,
  });
  if (!created.created && (opts.bay || opts.priority)) {
    await db.from('work_orders').update({ bay: opts.bay ?? created.work_order.bay, priority: opts.priority ?? created.work_order.priority }).eq('id', created.work_order.id);
    created.work_order.bay = opts.bay ?? created.work_order.bay;
  }
  await audit(ctx, { action: 'booking.checkin', entity_type: 'booking', entity_id: id, outlet_id: current.outlet_id, after: { work_order_id: created.work_order.id, bay: opts.bay ?? null } });
  return { booking: current, ...created };
}
