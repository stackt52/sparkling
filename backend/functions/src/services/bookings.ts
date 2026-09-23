/**
 * CUS-020..026: booking creation (server-side pricing + slot validation),
 * cancel, reschedule, staff check-in.
 */
import { canTransitionBooking } from '../domain/stateMachines.js';
import { DatabaseError, getSupabase, PG_UNIQUE_VIOLATION, unwrap } from '../lib/supabase.js';
import { assertOutlet, assertOwner, assertOwnerOrOutletStaff, isStaff } from '../middleware/auth.js';
import { ApiError } from '../middleware/errors.js';
import type { Booking, RequestContext, Task, Vehicle, VehicleSize, WorkOrder } from '../types.js';
import { audit } from './audit.js';
import { flagEnabled } from './flags.js';
import { assertSlotAvailable, findWalkInSlot } from './availability.js';
import { listOutletOffers, priceLabel, resolveOfferPrice, resolveVehicleSize } from './catalogue.js';
import { loadContext, redeemForBooking, releaseForBooking } from './memberships.js';
import { priceService } from './pricing.js';
import { checkInWorkOrder, createWorkOrderWithTask } from './workflow.js';

export interface CreateBookingInput {
  vehicleId: string;
  outletId: string;
  serviceId: string;
  /** Required for app bookings; optional for walk-ins (defaults to the next slot on the outlet grid). */
  slotStart?: string | null;
  clientOpId: string;
  notes?: string | null;
  /** staff may create on behalf of a customer */
  customerId?: string;
  /** Staff counter booking (STF-012): starts `confirmed`, slot defaults to now rounded up to the grid. */
  walkIn?: boolean;
  /** Pricing size; defaults to the vehicle's size_class (null → small). */
  vehicleSize?: VehicleSize | null;
  /** `cash` = pay at the counter on collection (requires feature flag `cash_on_collection`). */
  paymentMethod?: 'card' | 'eft' | 'cash' | null;
  /** Add-on services (`is_addon`, same `addon_group_name` as the service's group) priced into the booking. */
  addonServiceIds?: string[] | null;
}

export async function createBooking(ctx: RequestContext, input: CreateBookingInput): Promise<{ booking: Booking; duplicate: boolean }> {
  const db = getSupabase();
  const existing = await db.from('bookings').select('*').eq('client_op_id', input.clientOpId).maybeSingle();
  if (existing.data) return { booking: existing.data as Booking, duplicate: true };

  const staff = isStaff(ctx.auth.role);
  const walkIn = !!input.walkIn;
  if (walkIn && !staff) throw ApiError.forbidden('Walk-in bookings can only be created by staff');
  if (staff && !input.customerId) throw ApiError.validation('customer_id is required when staff create a booking', [{ path: 'customer_id', message: 'Required' }]);
  if (!walkIn && !input.slotStart) throw ApiError.validation('slot_start is required unless walk_in is true', [{ path: 'slot_start', message: 'Required' }]);
  if (walkIn) assertOutlet(ctx.auth, input.outletId);

  const customerId = staff && input.customerId ? input.customerId : ctx.auth.uid;
  const vehicle = unwrap<Vehicle | null>(await db.from('vehicles').select('*').eq('id', input.vehicleId).maybeSingle(), 'vehicle');
  if (!vehicle || !vehicle.is_active) throw ApiError.notFound('Vehicle');
  if (vehicle.customer_id !== customerId) throw ApiError.forbidden('Vehicle belongs to another customer');

  const vehicleSize = input.vehicleSize ?? resolveVehicleSize(vehicle);
  const membership = await loadContext(customerId);
  const { quote, service, outlet } = await priceService(input.outletId, input.serviceId, customerId, { vehicleSize, addonServiceIds: input.addonServiceIds ?? [], membership });
  const slot = input.slotStart
    ? await assertSlotAvailable(input.outletId, input.serviceId, input.slotStart, outlet.timezone)
    : await findWalkInSlot(outlet, service.id);
  const cash = input.paymentMethod === 'cash' && quote.total_cents > 0;
  if (cash && !(await flagEnabled('cash_on_collection'))) {
    throw ApiError.validationConflict('Cash on collection is not available at the moment — please pay by card or instant EFT', { reason: 'cash_disabled' });
  }

  const res = await db
    .from('bookings')
    .insert({
      customer_id: customerId,
      vehicle_id: vehicle.id,
      outlet_id: outlet.id,
      service_id: service.id,
      slot_start: slot.slot_start,
      slot_end: slot.slot_end,
      // Walk-ins are confirmed at the counter; a booking fully covered by a membership has nothing to pay, so it is confirmed at once too.
      // Walk-ins, fully covered bookings and cash-on-collection bookings need no online payment → confirmed at once.
      status: walkIn || quote.total_cents === 0 || cash ? 'confirmed' : 'pending',
      payment_method: input.paymentMethod ?? null,
      price_cents: quote.price_cents,
      discount_cents: quote.discount_cents,
      total_cents: quote.total_cents,
      discount_label: quote.discount_label,
      points_pending: quote.points_pending,
      vehicle_size: quote.vehicle_size,
      pricing_mode: quote.pricing_mode,
      vat_mode: quote.vat_mode,
      addon_service_ids: quote.addons.map((a) => a.service_id),
      addons_cents: quote.addons_cents,
      membership_id: quote.membership?.benefit ? quote.membership.membership_id : null,
      entitlement_id: quote.membership?.benefit === 'included' ? quote.membership.entitlement_id : null,
      membership_benefit: quote.membership?.benefit ?? null,
      notes: input.notes ?? null,
      client_op_id: input.clientOpId,
      created_by: ctx.auth.uid,
      walk_in: walkIn,
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
  // Covered by the plan → consume one allowance (+1 usage row, idempotent per booking).
  if (booking.membership_benefit === 'included' && booking.entitlement_id && membership) {
    const allowance = membership.allowances.find((a) => a.entitlement_id === booking.entitlement_id);
    if (allowance) await redeemForBooking(booking, { period_start: allowance.period_start, period_end: allowance.period_end }, ctx.auth.uid);
  }
  // A confirmed booking is visible on the work-order board straight away (awaiting check-in);
  // pending (unpaid) bookings get theirs when the payment succeeds.
  if (booking.status === 'confirmed') await ensureWorkOrderForBooking(ctx, booking);
  await audit(ctx, {
    action: walkIn ? 'booking.create_walk_in' : 'booking.create',
    entity_type: 'booking',
    entity_id: booking.id,
    outlet_id: booking.outlet_id,
    after: { ref: booking.ref, total_cents: booking.total_cents, customer_id: booking.customer_id, slot_start: booking.slot_start, status: booking.status, walk_in: walkIn, on_behalf: booking.customer_id !== ctx.auth.uid, vehicle_size: quote.vehicle_size, addons_cents: quote.addons_cents, addon_service_ids: quote.addons.map((a) => a.service_id), membership_benefit: booking.membership_benefit ?? null, entitlement_id: booking.entitlement_id ?? null },
  });
  return { booking, duplicate: false };
}

export interface BookingAddon {
  service_id: string;
  name: string;
  price_cents: number | null;
}

/**
 * Decorates booking rows with `addons` (name + price, resolved from the outlet
 * catalogue for the booking's vehicle size) and `price_label`.
 */
export async function attachPricing<T extends Pick<Booking, 'outlet_id' | 'pricing_mode' | 'vat_mode' | 'total_cents' | 'addon_service_ids' | 'addons_cents' | 'vehicle_size'>>(
  rows: T[],
): Promise<Array<T & { addons: BookingAddon[]; price_label: string }>> {
  const outletIds = [...new Set(rows.filter((r) => (r.addon_service_ids ?? []).length > 0).map((r) => r.outlet_id))];
  const offersByOutlet = new Map(await Promise.all(outletIds.map(async (id) => [id, (await listOutletOffers(id, { includeUnavailable: true })).offers] as const)));
  return rows.map((b) => {
    const ids = b.addon_service_ids ?? [];
    const offers = offersByOutlet.get(b.outlet_id) ?? [];
    const size = b.vehicle_size ?? 'small';
    let addons: BookingAddon[] = ids.map((id) => {
      const o = offers.find((x) => x.service_id === id);
      return { service_id: id, name: o?.name ?? id, price_cents: o ? resolveOfferPrice(o, size) : null };
    });
    // A single add-on is exactly what was charged; keep the stored figure authoritative.
    if (addons.length === 1) addons = [{ ...addons[0], price_cents: b.addons_cents ?? addons[0].price_cents }];
    return { ...b, addons, price_label: priceLabel(b.pricing_mode ?? 'fixed', b.total_cents, b.vat_mode ?? 'incl') };
  });
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
  // Give the plan allowance back (−1 release row; idempotent, no-op when nothing was redeemed).
  if (booking.membership_benefit === 'included') await releaseForBooking(id, ctx.auth.uid);
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

/**
 * Every confirmed booking has a work order on the board (awaiting check-in until the car is confirmed on site).
 * Idempotent: returns the existing work order when one is already linked to the booking.
 */
export async function ensureWorkOrderForBooking(
  ctx: RequestContext,
  booking: Booking,
  opts: { checkedIn?: boolean; bay?: string | null; priority?: number } = {},
): Promise<{ work_order: WorkOrder; task: Task; created: boolean }> {
  const db = getSupabase();
  const service = unwrap<import('../types.js').Service>(await db.from('services').select('*').eq('id', booking.service_id).single(), 'service');
  const eta = new Date(new Date(booking.slot_start).getTime() + service.duration_minutes * 60_000).toISOString();
  return createWorkOrderWithTask(ctx, {
    checkedIn: !!opts.checkedIn,
    outletId: booking.outlet_id,
    bookingId: booking.id,
    vehicleId: booking.vehicle_id,
    customerId: booking.customer_id,
    service,
    bay: opts.bay ?? null,
    priority: opts.priority,
    etaAt: eta,
    dueAt: eta,
  });
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
  const existing = unwrap<WorkOrder | null>(await db.from('work_orders').select('*').eq('booking_id', current.id).maybeSingle(), 'work order');
  if (existing) {
    // The work order was created when the booking was confirmed; confirming the check-in marks the car on site.
    if (opts.priority && opts.priority !== existing.priority) {
      await db.from('work_orders').update({ priority: opts.priority }).eq('id', existing.id);
      await db.from('tasks').update({ priority: opts.priority }).eq('work_order_id', existing.id);
    }
    const checked = await checkInWorkOrder(ctx, existing.id, { bay: opts.bay ?? existing.bay ?? null });
    const task = checked.task ?? unwrap<Task>(await db.from('tasks').select('*').eq('work_order_id', existing.id).order('seq').limit(1).single(), 'task');
    await audit(ctx, { action: 'booking.checkin', entity_type: 'booking', entity_id: current.id, outlet_id: current.outlet_id, after: { work_order_id: existing.id, bay: opts.bay ?? existing.bay ?? null, priority: opts.priority ?? existing.priority, already_checked_in: checked.already } });
    return { booking: current, work_order: checked.work_order, task, created: false };
  }
  const eta = new Date(new Date(current.slot_start).getTime() + service.duration_minutes * 60_000).toISOString();
  const created = await createWorkOrderWithTask(ctx, {
    checkedIn: true,
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
