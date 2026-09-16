/**
 * International phone numbers (E.164) — mirrors `backend/functions/src/lib/phone.ts`.
 *
 * Numbers are stored and sent as `+<country code><subscriber>` (`+27821234567`). Input may carry
 * the country code as `+27…`, `0027…` or `27…`; bare local numbers (`082 123 4567`) are read in
 * `defaultCountry` (South Africa unless told otherwise). Uses the `max` metadata build so the
 * per-country validation matches the API's.
 */
import { AsYouType, parsePhoneNumberFromString, type CountryCode, type PhoneNumber } from 'libphonenumber-js/max';
import { COUNTRIES, DEFAULT_COUNTRY } from './countries';

export { DEFAULT_COUNTRY };
export const E164 = /^\+[1-9]\d{6,14}$/;
/** The API's `validation_error` message for a bad number — reused by the demo API and the field. */
export const PHONE_HINT = 'Enter the mobile number with its country code, e.g. +27 82 123 4567';

const isCountry = (iso: string | null | undefined): iso is CountryCode => Boolean(iso) && COUNTRIES.some((c) => c.iso === iso);

/** Strips `whatsapp:` / `tel:` prefixes, spaces and punctuation; `00…` becomes `+…`. */
function clean(raw: string): string {
  let s = raw.trim().replace(/^(whatsapp|tel):/i, '').replace(/[\s\-().]/g, '');
  if (s.startsWith('00')) s = `+${s.slice(2)}`;
  return s;
}

function parse(raw: string | null | undefined, defaultCountry: string = DEFAULT_COUNTRY): PhoneNumber | null {
  if (!raw) return null;
  const s = clean(String(raw));
  if (!s) return null;
  const country = isCountry(defaultCountry) ? defaultCountry : DEFAULT_COUNTRY;
  // A number typed with its country code but no "+" (e.g. "27821234567") is tried as international first.
  const candidates = s.startsWith('+') ? [s] : [`+${s}`, s];
  for (const c of candidates) {
    const parsed = parsePhoneNumberFromString(c, country);
    if (parsed?.isValid()) return parsed;
  }
  return null;
}

/** Normalises to E.164, or `null` when the number is not valid anywhere. */
export function normalisePhone(raw: string | null | undefined, defaultCountry: string = DEFAULT_COUNTRY): string | null {
  return parse(raw, defaultCountry)?.number ?? null;
}

export function isValidPhone(raw: string | null | undefined, defaultCountry: string = DEFAULT_COUNTRY): boolean {
  return parse(raw, defaultCountry) !== null;
}

export function isE164(value: string | null | undefined): boolean {
  return Boolean(value) && E164.test(String(value).trim());
}

/**
 * `+27821234567` → `+27 82 123 4567`. Anything that is not a parseable international number
 * (legacy `012 348 4228 / 079 177 3146` outlet strings, free text) is returned unchanged.
 */
export function formatPhone(value: string | null | undefined): string {
  if (!value) return '';
  const s = clean(value);
  if (!/^\+\d{7,15}$/.test(s)) return value;
  const parsed = parsePhoneNumberFromString(s);
  return parsed && parsed.isPossible() ? parsed.formatInternational() : value;
}

/** ISO 3166-1 alpha-2 of the number's country (`ZA`, `GB`, …) or `null`. */
export function phoneCountry(value: string | null | undefined): string | null {
  const parsed = parse(value);
  return parsed?.country ?? null;
}

/** Country dial code without the `+` (`+27…` → `27`), also for numbers that are not (yet) valid. */
export function phoneDialCode(value: string | null | undefined): string | null {
  if (!value) return null;
  const s = clean(value);
  if (!s.startsWith('+')) return null;
  return parsePhoneNumberFromString(s)?.countryCallingCode ?? null;
}

/**
 * Splits an E.164 number into the picker country and the national (subscriber) digits.
 * `+27821234567` → `{ country: 'ZA', national: '821234567' }`. When several countries share the
 * calling code (`+1`, `+44`, …) `preferred` wins if it fits, so the picker does not jump about while typing.
 */
export function splitPhone(value: string | null | undefined, preferred?: string | null): { country: string; national: string } {
  if (!value) return { country: preferred && isCountry(preferred) ? preferred : DEFAULT_COUNTRY, national: '' };
  const s = clean(value);
  const parsed = parsePhoneNumberFromString(s.startsWith('+') ? s : `+${s}`);
  if (!parsed) return { country: preferred && isCountry(preferred) ? preferred : DEFAULT_COUNTRY, national: s.replace(/\D/g, '') };
  const dial = parsed.countryCallingCode;
  const preferredFits = preferred && isCountry(preferred) && COUNTRIES.find((c) => c.iso === preferred)?.dial === dial;
  const country = preferredFits ? preferred : parsed.country ?? COUNTRIES.find((c) => c.dial === dial)?.iso ?? DEFAULT_COUNTRY;
  return { country, national: parsed.nationalNumber };
}

/**
 * Formats the digits typed into a national-number box for `country` as they are typed
 * (`821234` → `82 123 4`, `0821234567` → `082 123 4567`, `7911123456` (GB) → `7911 123456`) and
 * returns the E.164 candidate plus whether it is a valid number.
 */
export function formatNational(country: string, digits: string): { display: string; e164: string; valid: boolean } {
  const iso: CountryCode = isCountry(country) ? country : DEFAULT_COUNTRY;
  const clean = digits.replace(/\D/g, '');
  if (!clean) return { display: '', e164: '', valid: false };
  const typer = new AsYouType(iso);
  const typed = typer.input(clean);
  const n = typer.getNumber();
  if (!n) return { display: typed, e164: '', valid: false };
  const valid = n.isValid();
  // Prefer the national formatting (keeps a typed trunk "0"); otherwise use the international grouping without the code.
  const display = typed !== clean ? typed : n.formatInternational().replace(/^\+\d+\s?/, '') || typed;
  return { display, e164: n.number, valid };
}

/** `+27 82 123 4567` style example for the placeholder of the selected country. */
export function countryDial(country: string): string {
  return COUNTRIES.find((c) => c.iso === country)?.dial ?? COUNTRIES.find((c) => c.iso === DEFAULT_COUNTRY)!.dial;
}

/** Normalises a search-box value when it looks like a phone number (`+…`, `00…`, `0…`), otherwise returns it as typed. */
export function normaliseSearch(raw: string): string {
  const s = raw.trim();
  if (!/^(\+|00|0)?[\d\s\-().]{6,}$/.test(s)) return s;
  return normalisePhone(s) ?? s;
}
