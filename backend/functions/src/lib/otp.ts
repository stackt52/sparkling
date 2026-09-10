/** Vehicle-collection OTP helpers (replicates the legacy 5-digit car pick-up OTP). */
import { randomInt, timingSafeEqual } from 'node:crypto';
import type { AuthContext, WorkOrder } from '../types.js';

export const PICKUP_OTP_MIN = 10_000;
export const PICKUP_OTP_MAX = 99_999;
export const PICKUP_OTP_PATTERN = /^\d{5}$/;

/** Cryptographically random 5-digit OTP in `10000–99999`. */
export function generatePickupOtp(): string {
  return String(randomInt(PICKUP_OTP_MIN, PICKUP_OTP_MAX + 1));
}

/** Constant-time OTP comparison. */
export function otpMatches(expected: string | null | undefined, given: string | null | undefined): boolean {
  if (!expected || !given) return false;
  const a = Buffer.from(String(expected).trim(), 'utf8');
  const b = Buffer.from(String(given).trim(), 'utf8');
  return a.length === b.length && timingSafeEqual(a, b);
}

export type OtpVisibilityRow = Pick<WorkOrder, 'customer_id' | 'status' | 'collected_at' | 'pickup_otp'>;

/**
 * Whether `auth` may see the work order's OTP: only the owning customer,
 * only while the vehicle is ready (booking `completed` / work order
 * `verified`) and not yet collected. Staff never see it.
 */
export function canSeePickupOtp(auth: AuthContext, wo: OtpVisibilityRow, bookingStatus?: string | null): boolean {
  if (auth.role !== 'customer' || wo.customer_id !== auth.uid) return false;
  if (!wo.pickup_otp || wo.collected_at) return false;
  return bookingStatus ? bookingStatus === 'completed' : wo.status === 'verified';
}

/** Strips the OTP from a work-order row unless the viewer is allowed to see it. */
export function redactPickupOtp<T extends OtpVisibilityRow>(auth: AuthContext, wo: T, bookingStatus?: string | null): T {
  if (canSeePickupOtp(auth, wo, bookingStatus)) return wo;
  return { ...wo, pickup_otp: null };
}
