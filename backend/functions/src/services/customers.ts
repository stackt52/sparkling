/**
 * Walk-in customers (STF-010/012): staff search, counter registration without an
 * app account (`walkin_<uuid>` profiles) and the helpers `/auth/session` uses to
 * claim such a profile when the person later signs up.
 */
import { randomUUID } from 'node:crypto';
import { normalisePhone } from '../lib/whatsapp.js';
import { DatabaseError, getSupabase, PG_UNIQUE_VIOLATION, unwrap } from '../lib/supabase.js';
import { ApiError } from '../middleware/errors.js';
import type { LoyaltyTier, Profile, RequestContext, Vehicle } from '../types.js';
import { audit } from './audit.js';
import { normaliseReg } from './vehicles.js';
import { getPublishedLoyaltyConfig, tierFor } from './pricing.js';
import { includedRemaining, membershipBriefs } from './memberships.js';

export const WALK_IN_PREFIX = 'walkin_';
export const SEED_PREFIX = 'seed_';
export const CUSTOMER_SEARCH_DEFAULT_LIMIT = 10;
export const CUSTOMER_SEARCH_MAX_LIMIT = 25;

export interface CustomerSummary {
  id: string;
  full_name: string;
  email: string | null;
  phone: string | null;
  marketing_opt_in: boolean;
  whatsapp_opt_in: boolean;
  /** `plan_*` / `included_remaining` come from the live membership (docs/MEMBERSHIPS.md); null plan = Silver (no plan). */
  loyalty: { tier: LoyaltyTier; balance_points: number; discount_pct: number; plan_code: string | null; plan_name: string | null; membership_status: string | null; included_remaining: number } | null;
  vehicles: Array<Pick<Vehicle, 'id' | 'registration_no' | 'make' | 'model' | 'colour' | 'disc_verified'>>;
}

export interface CreateCustomerInput {
  full_name: string;
  phone: string;
  email?: string | null;
  marketing_opt_in?: boolean;
  whatsapp_opt_in?: boolean;
  /** Outlet the customer was registered at (for the audit row). */
  outlet_id?: string | null;
}

/** True for profiles that were created without a Firebase account and can be claimed on sign-up. */
export function isClaimableProfileId(id: string): boolean {
  return id.startsWith(SEED_PREFIX) || id.startsWith(WALK_IN_PREFIX);
}

/** Digits only, without a leading `+`/`00`/`0` trunk prefix — the part that survives any formatting. */
export function phoneDigits(raw: string): string {
  return raw.replace(/\D/g, '');
}

/**
 * Builds an ILIKE pattern that matches a phone number regardless of how it was
 * stored (`+27831112222`, `+27 83 111 2222`, `083 111 2222`, `083-111-2222`).
 * South African numbers are grouped as 2-3-4 (`%83%111%2222%`); other numbers
 * as one digit run. Returns null when the term does not look like a phone number.
 */
export function phoneSearchPattern(term: string): string | null {
  const e164 = normalisePhone(term);
  let digits: string;
  if (e164) {
    digits = e164.startsWith('+27') ? e164.slice(3) : e164.slice(1);
  } else {
    digits = phoneDigits(term);
    if (digits.length < 4 || digits.length < term.replace(/[\s\-().+]/g, '').length) return null;
    if (digits.startsWith('27') && digits.length > 9) digits = digits.slice(2);
    if (digits.startsWith('0')) digits = digits.slice(1);
  }
  if (!digits) return null;
  const groups = digits.length === 9 ? [digits.slice(0, 2), digits.slice(2, 5), digits.slice(5)] : [digits];
  return `%${groups.join('%')}%`;
}

/** Two phone values refer to the same number (both normalised to E.164). */
export function samePhone(a: string | null | undefined, b: string | null | undefined): boolean {
  const x = normalisePhone(a);
  const y = normalisePhone(b);
  return !!x && !!y && x === y;
}

/** Strips PostgREST `or()` syntax characters (and `+`, which the phone pattern covers) from a search term. */
function escapeOr(s: string): string {
  return s.replace(/[%_,()"\\+*?[\]{}|^$]/g, '');
}

async function summarise(profiles: Profile[]): Promise<CustomerSummary[]> {
  if (profiles.length === 0) return [];
  const db = getSupabase();
  const ids = profiles.map((p) => p.id);
  const [accounts, vehicles] = await Promise.all([
    db.from('loyalty_accounts').select('customer_id, tier, balance_points').in('customer_id', ids),
    db.from('vehicles').select('id, customer_id, registration_no, make, model, colour, disc_verified, created_at').in('customer_id', ids).eq('is_active', true).order('created_at', { ascending: false }),
  ]);
  const [loyaltyCfg, briefs] = await Promise.all([getPublishedLoyaltyConfig(), membershipBriefs(ids)]);
  const acct = new Map((unwrap<Array<{ customer_id: string; tier: LoyaltyTier; balance_points: number }>>(accounts, 'loyalty accounts') ?? []).map((a) => [a.customer_id, a]));
  const vehByCustomer = new Map<string, CustomerSummary['vehicles']>();
  for (const v of unwrap<Array<Vehicle>>(vehicles, 'vehicles') ?? []) {
    const list = vehByCustomer.get(v.customer_id) ?? [];
    list.push({ id: v.id, registration_no: v.registration_no, make: v.make ?? null, model: v.model ?? null, colour: v.colour ?? null, disc_verified: !!v.disc_verified });
    vehByCustomer.set(v.customer_id, list);
  }
  return profiles.map((p) => {
    const a = acct.get(p.id);
    const brief = briefs.get(p.id) ?? null;
    return {
      id: p.id,
      full_name: p.full_name,
      email: p.email ?? null,
      phone: p.phone ?? null,
      marketing_opt_in: !!p.marketing_opt_in,
      whatsapp_opt_in: !!p.whatsapp_opt_in,
      loyalty: a || brief
        ? { tier: brief?.tier ?? a?.tier ?? 'silver', balance_points: a?.balance_points ?? 0, discount_pct: tierFor(loyaltyCfg, brief?.tier ?? a?.tier ?? 'silver')?.discount_pct ?? 0, plan_code: brief?.plan_code ?? null, plan_name: brief?.plan_name ?? null, membership_status: brief?.status ?? null, included_remaining: includedRemaining(brief) }
        : null,
      vehicles: vehByCustomer.get(p.id) ?? [],
    };
  });
}

export async function customerSummary(profile: Profile): Promise<CustomerSummary> {
  const [row] = await summarise([profile]);
  return row;
}

/**
 * Search active customers by name, e-mail, phone (any formatting; `083…` finds
 * `+2783…`) or number plate (alphanumerics only). Audited once per search.
 */
export async function searchCustomers(ctx: RequestContext, search: string, limit = CUSTOMER_SEARCH_DEFAULT_LIMIT): Promise<CustomerSummary[]> {
  const db = getSupabase();
  const term = search.trim();
  const safe = escapeOr(term);
  const max = Math.min(Math.max(1, limit), CUSTOMER_SEARCH_MAX_LIMIT);

  const clauses: string[] = [];
  if (safe) clauses.push(`full_name.ilike.%${safe}%`, `email.ilike.%${safe}%`, `phone.ilike.%${safe}%`);
  const phonePattern = phoneSearchPattern(term);
  if (phonePattern) clauses.push(`phone.ilike.${phonePattern}`);

  const found = new Map<string, Profile>();
  if (clauses.length) {
    const rows = unwrap<Profile[]>(
      await db.from('profiles').select('*').eq('role', 'customer').eq('is_active', true).or(clauses.join(',')).order('full_name').limit(max),
      'customer search',
    );
    for (const r of rows) found.set(r.id, r);
  }

  // Plate match: loose ILIKE on the raw column, then exact substring on the normalised value.
  const plate = normaliseReg(term);
  if (plate.length >= 2 && found.size < max) {
    const pattern = `%${plate.split('').join('%')}%`;
    const vehicles = unwrap<Array<{ customer_id: string; registration_no: string }>>(
      await db.from('vehicles').select('customer_id, registration_no').eq('is_active', true).ilike('registration_no', pattern).limit(max * 4),
      'plate search',
    );
    const ownerIds = [...new Set(vehicles.filter((v) => normaliseReg(v.registration_no).includes(plate)).map((v) => v.customer_id))].filter((id) => !found.has(id));
    if (ownerIds.length) {
      const owners = unwrap<Profile[]>(await db.from('profiles').select('*').in('id', ownerIds).eq('role', 'customer').eq('is_active', true), 'plate owners');
      for (const o of owners) if (found.size < max) found.set(o.id, o);
    }
  }

  const data = await summarise([...found.values()].slice(0, max));
  await audit(ctx, { action: 'customer.search', entity_type: 'profile', outlet_id: ctx.auth.outletIds[0] ?? null, after: { search: term, count: data.length, source: 'staff' } });
  return data;
}

/** Finds any profile with the same normalised phone or (case-insensitive) e-mail. */
export async function findProfileByContact(phone: string | null | undefined, email: string | null | undefined, opts: { onlyPrefix?: string } = {}): Promise<Profile | null> {
  const db = getSupabase();
  const e164 = normalisePhone(phone);
  if (email) {
    const wanted = email.trim().toLowerCase();
    const rows = unwrap<Profile[]>(await db.from('profiles').select('*').ilike('email', wanted.replace(/[%,()"\\]/g, '')).limit(5), 'email lookup');
    const hit = rows.find((r) => (r.email ?? '').toLowerCase() === wanted && (!opts.onlyPrefix || r.id.startsWith(opts.onlyPrefix)));
    if (hit) return hit;
  }
  if (e164) {
    const pattern = phoneSearchPattern(e164);
    if (pattern) {
      const rows = unwrap<Profile[]>(await db.from('profiles').select('*').ilike('phone', pattern).limit(50), 'phone lookup');
      const hit = rows.find((r) => samePhone(r.phone, e164) && (!opts.onlyPrefix || r.id.startsWith(opts.onlyPrefix)));
      if (hit) return hit;
    }
  }
  return null;
}

/**
 * Registers a walk-in customer (no Firebase account). 409 `conflict` with
 * `existing_customer` when the phone or e-mail is already registered.
 */
export async function createWalkInCustomer(ctx: RequestContext, input: CreateCustomerInput): Promise<CustomerSummary> {
  const db = getSupabase();
  const phone = normalisePhone(input.phone);
  if (!phone) throw ApiError.validation('phone must be a valid South African or E.164 number', [{ path: 'phone', message: 'Invalid phone number' }]);
  const email = input.email ? input.email.trim().toLowerCase() : null;

  const existing = await findProfileByContact(phone, email);
  if (existing) {
    throw ApiError.conflict('A customer with this phone or e-mail is already registered', { existing_customer: await customerSummary(existing), field: samePhone(existing.phone, phone) ? 'phone' : 'email' });
  }

  const id = `${WALK_IN_PREFIX}${randomUUID()}`;
  const res = await db
    .from('profiles')
    .insert({
      id,
      role: 'customer',
      full_name: input.full_name.trim(),
      email,
      phone,
      is_active: true,
      marketing_opt_in: input.marketing_opt_in ?? false,
      whatsapp_opt_in: input.whatsapp_opt_in ?? true,
      last_seen_at: null,
    })
    .select('*')
    .single();
  if (res.error) {
    if (res.error.code === PG_UNIQUE_VIOLATION) {
      const clash = await findProfileByContact(phone, email);
      throw ApiError.conflict('A customer with this phone or e-mail is already registered', { existing_customer: clash ? await customerSummary(clash) : null });
    }
    throw new DatabaseError(res.error, 'create walk-in customer');
  }
  const profile = res.data as Profile;
  const acct = await db.from('loyalty_accounts').insert({ customer_id: profile.id, tier: 'silver', balance_points: 0, lifetime_points: 0 });
  if (acct.error && acct.error.code !== PG_UNIQUE_VIOLATION) throw new DatabaseError(acct.error, 'create loyalty account');

  const outletId = input.outlet_id ?? ctx.auth.outletIds[0] ?? null;
  await audit(ctx, {
    action: 'customer.create',
    entity_type: 'profile',
    entity_id: profile.id,
    outlet_id: outletId,
    after: { full_name: profile.full_name, phone: profile.phone, email: profile.email, marketing_opt_in: profile.marketing_opt_in, whatsapp_opt_in: profile.whatsapp_opt_in, walk_in: true, registered_by: ctx.auth.uid },
  });
  return customerSummary(profile);
}

/** Loads an active customer profile or throws 404. */
export async function getCustomerOrThrow(id: string): Promise<Profile> {
  const db = getSupabase();
  const profile = unwrap<Profile | null>(await db.from('profiles').select('*').eq('id', id).eq('role', 'customer').maybeSingle(), 'customer');
  if (!profile || !profile.is_active) throw ApiError.notFound('Customer');
  return profile;
}
