/** Auth & profile: /auth/session, /me, /devices (CUS-001, STF-001, ADM-001). */
import { Router } from 'express';
import { z } from 'zod';
import { firebaseAuth } from '../lib/firebase.js';
import { getSupabase, unwrap } from '../lib/supabase.js';
import { parseBody } from '../lib/validate.js';
import { loadOutletIds, requireProfile } from '../middleware/auth.js';
import { ApiError, asyncHandler } from '../middleware/errors.js';
import { authLimiter } from '../middleware/rateLimit.js';
import type { AuthContext, Profile, UserRole } from '../types.js';
import { STAFF_ROLES } from '../types.js';
import { audit } from '../services/audit.js';
import { findProfileByContact, isClaimableProfileId, WALK_IN_PREFIX } from '../services/customers.js';
import { ledgerBalance } from '../services/loyalty.js';
import { membershipBrief } from '../services/memberships.js';
import { normalisePhone, optionalPhoneSchema } from '../lib/phone.js';

export const authRouter = Router();

const sessionSchema = z.object({
  app: z.enum(['customer', 'staff', 'admin']),
  full_name: z.string().trim().min(1).max(120).optional(),
  phone: z.string().trim().max(32).optional(),
});

/** Sets custom claims when they differ from the current token. */
export async function syncClaims(uid: string, role: UserRole, outletIds: string[], tokenClaims: Record<string, unknown>): Promise<boolean> {
  const currentRole = tokenClaims.role;
  const currentOutlets = Array.isArray(tokenClaims.outlet_ids) ? (tokenClaims.outlet_ids as string[]) : [];
  const same = currentRole === role && currentOutlets.length === outletIds.length && currentOutlets.every((o) => outletIds.includes(o));
  if (same) return false;
  await firebaseAuth().setCustomUserClaims(uid, { role, outlet_ids: outletIds });
  return true;
}

/**
 * Phone number for a first sign-in, normalised to E.164: the Firebase user
 * record (token claim, then Admin SDK lookup) wins over the request body.
 */
async function signUpPhone(auth: AuthContext, bodyPhone: string | undefined): Promise<string | null> {
  const claim = normalisePhone(auth.tokenClaims.phone_number as string | undefined);
  if (claim) return claim;
  try {
    const fbAuth = firebaseAuth() as { getUser?: (uid: string) => Promise<{ phoneNumber?: string | null }> };
    if (typeof fbAuth.getUser === 'function') {
      const user = await fbAuth.getUser(auth.uid);
      const fromRecord = normalisePhone(user?.phoneNumber);
      if (fromRecord) return fromRecord;
    }
  } catch {
    /* user record unavailable — fall back to the body */
  }
  return normalisePhone(bodyPhone);
}

authRouter.post(
  '/auth/session',
  authLimiter,
  asyncHandler(async (req, res) => {
    const body = parseBody(sessionSchema, req.body);
    const auth = req.auth!;
    const db = getSupabase();
    let profile = auth.profile;

    if (!profile) {
      // Claim a seeded (`seed_`) or walk-in (`walkin_`) profile by e-mail, else a walk-in by phone;
      // rewriting `profiles.id` cascades through every FK (bookings, vehicles, points carry over).
      let claimable: Profile | null = null;
      if (auth.email) {
        const byEmail = unwrap<Profile | null>(await db.from('profiles').select('*').ilike('email', auth.email).maybeSingle(), 'seed lookup');
        if (byEmail && isClaimableProfileId(byEmail.id)) claimable = byEmail;
        else if (byEmail) throw ApiError.conflict('E-mail already linked to another account');
      }
      const phone = await signUpPhone(auth, body.phone);
      if (!claimable && phone) claimable = await findProfileByContact(phone, null, { onlyPrefix: WALK_IN_PREFIX });
      if (claimable) {
        const patch: Partial<Profile> = { id: auth.uid, last_seen_at: new Date().toISOString() };
        if (auth.email) patch.email = auth.email;
        if (!claimable.phone && phone) patch.phone = phone;
        if (body.full_name && claimable.id.startsWith(WALK_IN_PREFIX)) patch.full_name = body.full_name;
        profile = unwrap<Profile>(await db.from('profiles').update(patch).eq('id', claimable.id).select('*').single(), 'claim profile');
        req.log.info({ claimed_id: claimable.id, by: claimable.email && auth.email && claimable.email.toLowerCase() === auth.email.toLowerCase() ? 'email' : 'phone' }, 'claimed profile');
      }
      if (!profile && body.app !== 'customer') {
        // Staff and admin accounts are provisioned by an admin (POST /admin/users); never auto-create a
        // customer profile for an unknown account that signed in through the staff or admin app.
        throw ApiError.forbidden('This account is not a Sparkling staff account. Ask your manager to add you in the admin dashboard.', { reason: 'not_staff' });
      }
      if (!profile) {
        const fullName = body.full_name ?? (auth.tokenClaims.name as string | undefined) ?? auth.email?.split('@')[0] ?? 'Sparkling customer';
        profile = unwrap<Profile>(
          await db
            .from('profiles')
            .insert({ id: auth.uid, role: 'customer', full_name: fullName, email: auth.email, phone: phone ?? body.phone ?? null, is_active: true, last_seen_at: new Date().toISOString() })
            .select('*')
            .single(),
          'create profile',
        );
      }
    } else {
      const patch: Partial<Profile> = { last_seen_at: new Date().toISOString() };
      if (body.full_name) patch.full_name = body.full_name;
      if (body.phone) patch.phone = normalisePhone(body.phone) ?? body.phone;
      if (!profile.email && auth.email) patch.email = auth.email;
      profile = unwrap<Profile>(await db.from('profiles').update(patch).eq('id', auth.uid).select('*').single(), 'update profile');
    }
    if (!profile.is_active) throw ApiError.forbidden('Account is deactivated');

    const role = profile.role;
    if (body.app === 'staff' && !STAFF_ROLES.includes(role)) throw ApiError.forbidden('This account is a customer account. Ask your manager to add you as staff in the admin dashboard.', { reason: 'not_staff' });
    if (body.app === 'admin' && !['manager', 'admin', 'finance'].includes(role)) throw ApiError.forbidden('Admin dashboard requires manager, admin or finance role');

    const outletIds = STAFF_ROLES.includes(role) ? await loadOutletIds(auth.uid) : [];
    const claimsUpdated = await syncClaims(auth.uid, role, outletIds, auth.tokenClaims);
    req.auth = { ...auth, profile, role, outletIds };
    req.ctx.auth = req.auth;
    await audit(req.ctx, { action: 'auth.session', entity_type: 'profile', entity_id: auth.uid, after: { app: body.app, claims_updated: claimsUpdated } });
    res.json({ profile, outlet_ids: outletIds, claims_updated: claimsUpdated });
  }),
);

/**
 * The client has just set a new password through Firebase Auth (`updatePassword`); clear the
 * first-sign-in flag. Requires a token minted after the change (`auth_time` within 15 minutes)
 * so a stale session cannot silently dismiss the requirement.
 */
authRouter.post(
  '/auth/password-changed',
  requireProfile,
  asyncHandler(async (req, res) => {
    const auth = req.auth!;
    const db = getSupabase();
    const authTime = Number(auth.tokenClaims.auth_time ?? 0) * 1000;
    if (!authTime || Date.now() - authTime > 15 * 60_000) {
      throw ApiError.validationConflict('Sign in again with the new password before confirming the change', { reason: 'stale_session' });
    }
    const profile = unwrap<Profile>(
      await db.from('profiles').update({ must_change_password: false, password_changed_at: new Date().toISOString() }).eq('id', auth.uid).select('*').single(),
      'password changed',
    );
    await audit(req.ctx, { action: 'auth.password_changed', entity_type: 'profile', entity_id: auth.uid });
    res.json({ profile });
  }),
);

authRouter.get(
  '/me',
  requireProfile,
  asyncHandler(async (req, res) => {
    const auth = req.auth!;
    const db = getSupabase();
    const outlets = auth.outletIds.length
      ? unwrap<unknown[]>(await db.from('outlets').select('id, code, name, city, timezone').in('id', auth.outletIds), 'outlets')
      : [];
    let loyalty_account: unknown = null;
    let membership: unknown = null;
    if (auth.role === 'customer') {
      const acct = unwrap<Record<string, unknown> | null>(await db.from('loyalty_accounts').select('*').eq('customer_id', auth.uid).maybeSingle(), 'account');
      if (acct) {
        const { balance, lifetime } = await ledgerBalance(auth.uid);
        loyalty_account = { ...acct, balance_points: balance, lifetime_points: lifetime };
      }
      membership = await membershipBrief(auth.uid);
    }
    res.json({ profile: auth.profile, outlets, loyalty_account, membership });
  }),
);

const meSchema = z
  .object({
    full_name: z.string().trim().min(1).max(120),
    phone: optionalPhoneSchema,
    avatar_url: z.string().url().max(2048).nullable(),
    marketing_opt_in: z.boolean(),
    whatsapp_opt_in: z.boolean(),
    push_opt_in: z.boolean(),
    locale: z.string().min(2).max(16),
    reduced_motion: z.boolean(),
    haptics: z.boolean(),
  })
  .partial()
  .strict();

authRouter.patch(
  '/me',
  requireProfile,
  asyncHandler(async (req, res) => {
    const patch = parseBody(meSchema, req.body);
    if (Object.keys(patch).length === 0) throw ApiError.validation('No editable fields supplied');
    const db = getSupabase();
    const before = req.auth!.profile!;
    const profile = unwrap<Profile>(await db.from('profiles').update(patch).eq('id', req.auth!.uid).select('*').single(), 'update profile');
    if ('marketing_opt_in' in patch && patch.marketing_opt_in !== before.marketing_opt_in) {
      await audit(req.ctx, { action: 'profile.consent', entity_type: 'profile', entity_id: req.auth!.uid, before: { marketing_opt_in: before.marketing_opt_in }, after: { marketing_opt_in: patch.marketing_opt_in } });
    }
    res.json({ profile });
  }),
);

const deviceSchema = z.object({
  token: z.string().min(10).max(4096),
  platform: z.enum(['android', 'ios', 'web']),
  app: z.enum(['customer', 'staff', 'admin']),
});

authRouter.post(
  '/devices',
  requireProfile,
  asyncHandler(async (req, res) => {
    const body = parseBody(deviceSchema, req.body);
    const db = getSupabase();
    const row = unwrap<Record<string, unknown>>(
      await db
        .from('device_tokens')
        .upsert({ profile_id: req.auth!.uid, token: body.token, platform: body.platform, app: body.app, updated_at: new Date().toISOString() }, { onConflict: 'token' })
        .select('*')
        .single(),
      'device token',
    );
    res.status(201).json({ device: row });
  }),
);

authRouter.delete(
  '/devices/:token',
  requireProfile,
  asyncHandler(async (req, res) => {
    const db = getSupabase();
    await db.from('device_tokens').delete().eq('token', req.params.token).eq('profile_id', req.auth!.uid);
    res.status(204).end();
  }),
);
