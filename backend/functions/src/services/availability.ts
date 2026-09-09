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
