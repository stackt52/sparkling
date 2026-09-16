/**
 * International mobile numbers (E.164) via libphonenumber.
 *
 * Numbers are stored as `+<country code><subscriber>`. Input should carry the country code
 * (`+27 82 123 4567`, `0027…`, `27 82…`); bare South African local numbers (`082 123 4567`) are
 * still understood for backwards compatibility with older app builds and the offline queue.
 */
import { parsePhoneNumberFromString, type CountryCode } from 'libphonenumber-js/max';
import { z } from 'zod';

export const DEFAULT_COUNTRY: CountryCode = 'ZA';
export const E164 = /^\+[1-9]\d{6,14}$/;
export const PHONE_HINT = 'Enter the mobile number with its country code, e.g. +27 82 123 4567';

/** Normalises to E.164, or null when the number is not valid anywhere. */
export function normalisePhone(raw: string | null | undefined, defaultCountry: CountryCode = DEFAULT_COUNTRY): string | null {
  if (!raw) return null;
  let s = String(raw).trim().replace(/^whatsapp:/i, '').replace(/[\s\-().]/g, '');
  if (!s) return null;
  if (s.startsWith('00')) s = `+${s.slice(2)}`;
  // Country-code without "+" (e.g. "27821234567") — try it as international first.
  const candidates = s.startsWith('+') ? [s] : [`+${s}`, s];
  for (const c of candidates) {
    const parsed = parsePhoneNumberFromString(c, defaultCountry);
    if (parsed?.isValid()) return parsed.number;
  }
  return null;
}

export function isE164(value: string | null | undefined): boolean {
  return !!value && E164.test(value.trim());
}

/** `+27821234567` → `+27 82 123 4567`; unknown formats are returned unchanged. */
export function formatPhone(value: string | null | undefined): string {
  if (!value) return '';
  const parsed = parsePhoneNumberFromString(value);
  return parsed ? parsed.formatInternational() : value;
}

/** ISO 3166-1 alpha-2 of the number's country (`ZA`, `GB`, …) or null. */
export function phoneCountry(value: string | null | undefined): string | null {
  if (!value) return null;
  return parsePhoneNumberFromString(value)?.country ?? null;
}

/** zod schema: accepts any valid international number and outputs E.164. */
export const phoneSchema = z
  .string()
  .trim()
  .min(6, PHONE_HINT)
  .max(32, PHONE_HINT)
  .transform((v, ctx) => {
    const e164 = normalisePhone(v);
    if (!e164) {
      ctx.addIssue({ code: z.ZodIssueCode.custom, message: PHONE_HINT });
      return z.NEVER;
    }
    return e164;
  });

/** Like [phoneSchema] but `null` / empty string clear the number. */
export const optionalPhoneSchema = z
  .union([z.literal(''), z.null(), phoneSchema])
  .transform((v) => (v === '' ? null : v));
