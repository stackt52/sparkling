/**
 * BAR-00x: server-side validation of the South African vehicle licence disc
 * PDF417 payload. The on-device parser in `sparkling_core` is primary; this is
 * the authoritative fallback used by POST /v1/vehicles/parse-disc.
 *
 * Layout (percent-delimited, positional). Known public reverse-engineering of
 * the eNaTIS disc format — fields are tolerant to missing trailing values:
 *   0  ''             (leading delimiter)
 *   1  control/version   e.g. MVL1CC48
 *   2  '0148'
 *   3  disc/licence serial e.g. 4022M0CS
 *   4  '1'
 *   5  licence number      e.g. 4022027U1BF   (licence_no)
 *   6  registration number e.g. KL45MNGP      (registration_no)
 *   7  vehicle register no e.g. AAA123
 *   8  description         e.g. Sedan (closed top)
 *   9  make
 *   10 model / series
 *   11 colour
 *   12 VIN (17 chars)
 *   13 engine number
 *   14 expiry date  YYYY-MM-DD
 *   15 (optional) tare / extra
 */
import { createHash } from 'node:crypto';

export interface ParsedDisc {
  registration_no: string;
  licence_no: string | null;
  vehicle_register_no: string | null;
  description: string | null;
  make: string | null;
  model: string | null;
  colour: string | null;
  vin: string | null;
  engine_no: string | null;
  disc_expiry: string | null;
  disc_hash: string;
  warnings: string[];
}

export class DiscParseError extends Error {
  constructor(msg: string) {
    super(msg);
    this.name = 'DiscParseError';
  }
}

const VIN_RE = /^[A-HJ-NPR-Z0-9]{17}$/i;

function clean(v: string | undefined): string | null {
  if (v === undefined) return null;
  const t = v.trim();
  return t.length ? t : null;
}

export function formatRegistration(raw: string): string {
  const compact = raw.replace(/[^A-Za-z0-9]/g, '').toUpperCase();
  // Gauteng-style "KL45MNGP" → "KL 45 MN GP"; otherwise keep compact grouping.
  const m = /^([A-Z]{2})(\d{2})([A-Z]{2})(GP|MP|NW|L|FS|NC|WC|EC|ZN)$/.exec(compact);
  if (m) return `${m[1]} ${m[2]} ${m[3]} ${m[4]}`;
  const ca = /^(C[A-Z]{1,2})(\d{3,6})$/.exec(compact);
  if (ca) return `${ca[1]} ${ca[2]}`;
  return compact;
}

export function parseDisc(raw: string): ParsedDisc {
  if (typeof raw !== 'string' || raw.trim().length < 20) throw new DiscParseError('Payload too short to be a licence disc');
  const parts = raw.split('%');
  if (parts.length < 8) throw new DiscParseError('Payload does not match the SA licence disc layout');
  const warnings: string[] = [];
  const registration = clean(parts[6]);
  if (!registration) throw new DiscParseError('Registration number missing from disc payload');

  let vin = clean(parts[12]);
  if (vin && !VIN_RE.test(vin)) {
    warnings.push('VIN failed format validation');
    vin = vin.toUpperCase();
  }
  let expiry = clean(parts[14]);
  if (expiry) {
    const m = /^(\d{4})-(\d{2})-(\d{2})$/.exec(expiry);
    if (!m) {
      warnings.push('Expiry date not in YYYY-MM-DD form');
      expiry = null;
    } else {
      const d = new Date(`${expiry}T00:00:00Z`);
      if (Number.isNaN(d.getTime())) {
        warnings.push('Expiry date invalid');
        expiry = null;
      } else if (d.getTime() < Date.now()) {
        warnings.push('Licence disc has expired');
      }
    }
  }
  const control = clean(parts[1]);
  if (!control || !/^MVL/i.test(control)) warnings.push('Unrecognised control field; payload may not be an SA disc');

  return {
    registration_no: formatRegistration(registration),
    licence_no: clean(parts[5]),
    vehicle_register_no: clean(parts[7]),
    description: clean(parts[8]),
    make: clean(parts[9]),
    model: clean(parts[10]),
    colour: clean(parts[11]),
    vin: vin ? vin.toUpperCase() : null,
    engine_no: clean(parts[13]),
    disc_expiry: expiry,
    // BAR-004: the raw payload is never stored; only its hash.
    disc_hash: createHash('sha256').update(raw, 'utf8').digest('hex'),
    warnings,
  };
}
