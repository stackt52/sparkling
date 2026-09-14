/** CUS-021/022: slot availability via the `get_available_slots` RPC. */
import { getSupabase, unwrap } from '../lib/supabase.js';
import { ApiError } from '../middleware/errors.js';

export interface Slot {
  slot_start: string;
  slot_end: string;
  capacity: number;
  booked: number;
  available: boolean;
}

export async function getSlots(outletId: string, serviceId: string, date: string): Promise<Slot[]> {
  const db = getSupabase();
  const res = await db.rpc('get_available_slots', { p_outlet: outletId, p_service: serviceId, p_date: date });
  return unwrap<Slot[]>(res, 'get_available_slots') ?? [];
}

/** Date (YYYY-MM-DD) of an instant in the outlet timezone. */
export function localDate(iso: string, timezone: string): string {
  const d = new Date(iso);
  const fmt = new Intl.DateTimeFormat('en-CA', { timeZone: timezone, year: 'numeric', month: '2-digit', day: '2-digit' });
  return fmt.format(d);
}

/**
 * Validates that `slotStart` is one of the generated, available slots.
 * Throws 409 `conflict` when the slot is full/past/non-existent.
 */
export async function assertSlotAvailable(outletId: string, serviceId: string, slotStart: string, timezone: string): Promise<Slot> {
  const date = localDate(slotStart, timezone);
  const slots = await getSlots(outletId, serviceId, date);
  const wanted = new Date(slotStart).getTime();
  const slot = slots.find((s) => new Date(s.slot_start).getTime() === wanted);
  if (!slot) throw ApiError.conflict('Slot is not offered at this outlet/time', { slot_start: slotStart });
  if (!slot.available) throw ApiError.conflict('Slot is no longer available', { slot_start: slotStart, booked: slot.booked, capacity: slot.capacity });
  return slot;
}

/** Offset (ms) between wall-clock time in `timeZone` and UTC at instant `at`. */
export function tzOffsetMs(at: Date, timeZone: string): number {
  const parts = new Intl.DateTimeFormat('en-US', { timeZone, hourCycle: 'h23', year: 'numeric', month: '2-digit', day: '2-digit', hour: '2-digit', minute: '2-digit', second: '2-digit' }).formatToParts(at);
  const get = (t: string) => Number(parts.find((p) => p.type === t)?.value ?? 0);
  const asUtc = Date.UTC(get('year'), get('month') - 1, get('day'), get('hour'), get('minute'), get('second'));
  return asUtc - Math.floor(at.getTime() / 1000) * 1000;
}

/**
 * Walk-in slot start: `now` rounded UP to the next multiple of `slotMinutes` on
 * the outlet's local clock. Always strictly after `now` so the slot is still
 * bookable (`get_available_slots` marks `slot_start <= now()` unavailable).
 */
export function roundUpToSlot(now: Date, slotMinutes: number, timeZone: string): Date {
  const step = Math.max(1, Math.floor(slotMinutes || 30)) * 60_000;
  const offset = tzOffsetMs(now, timeZone);
  const local = now.getTime() + offset;
  return new Date(Math.floor(local / step) * step + step - offset);
}

/**
 * Picks the walk-in slot: the first generated slot on the outlet grid at or
 * after `now` rounded up. 409 `conflict` when the outlet is closed for the rest
 * of the day or every bay is taken in that slot (capacity is enforced by the
 * same RPC as customer bookings).
 */
export async function findWalkInSlot(outlet: { id: string; timezone: string; slot_minutes: number }, serviceId: string, now = new Date()): Promise<Slot> {
  const candidate = roundUpToSlot(now, outlet.slot_minutes, outlet.timezone);
  const slots = await getSlots(outlet.id, serviceId, localDate(candidate.toISOString(), outlet.timezone));
  const wanted = candidate.getTime();
  const slot = [...slots].sort((a, b) => new Date(a.slot_start).getTime() - new Date(b.slot_start).getTime()).find((s) => new Date(s.slot_start).getTime() >= wanted);
  if (!slot) throw ApiError.conflict('No walk-in slot left today at this outlet', { slot_start: candidate.toISOString() });
  if (!slot.available) throw ApiError.conflict('All bays are busy for the next slot', { slot_start: slot.slot_start, booked: slot.booked, capacity: slot.capacity });
  return slot;
}
