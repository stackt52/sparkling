/**
 * SEC-003: verify Firebase ID token, load `profiles` row, enforce role/outlet/ownership.
 */
import type { RequestHandler } from 'express';
import { firebaseAuth } from '../lib/firebase.js';
import { getSupabase, unwrap } from '../lib/supabase.js';
import { ApiError, asyncHandler } from './errors.js';
import type { AuthContext, Profile, RequestContext, UserRole } from '../types.js';
import { MANAGER_ROLES, STAFF_ROLES, SUPERVISOR_ROLES } from '../types.js';

export async function loadProfile(uid: string): Promise<Profile | null> {
  const db = getSupabase();
  const res = await db.from('profiles').select('*').eq('id', uid).maybeSingle();
  return unwrap<Profile | null>(res, 'load profile');
}

export async function loadOutletIds(uid: string): Promise<string[]> {
  const db = getSupabase();
  const rows = unwrap<Array<{ outlet_id: string }>>(
    await db.from('staff_outlets').select('outlet_id').eq('profile_id', uid),
    'load staff outlets',
  );
  return rows.map((r) => r.outlet_id);
}

/**
 * Verifies the bearer token and attaches `req.auth`. The profile may be null
 * (first sign-in) — `requireProfile` guards routes that need one.
 */
export const authenticate: RequestHandler = asyncHandler(async (req, _res, next) => {
  const header = req.header('Authorization') ?? '';
  const match = /^Bearer\s+(.+)$/i.exec(header);
  if (!match) throw ApiError.unauthenticated('Missing bearer token');
  let decoded;
  try {
    decoded = await firebaseAuth().verifyIdToken(match[1], false);
  } catch {
    throw ApiError.unauthenticated('Invalid or expired token');
  }
  const uid = decoded.uid;
  const profile = await loadProfile(uid);
  if (profile && !profile.is_active) throw ApiError.forbidden('Account is deactivated');
  const role: UserRole = profile?.role ?? 'customer';
  const outletIds = profile && STAFF_ROLES.includes(role) ? await loadOutletIds(uid) : [];
  const auth: AuthContext = {
    uid,
    email: decoded.email ?? profile?.email ?? null,
    role,
    outletIds,
    profile,
    tokenClaims: decoded as unknown as Record<string, unknown>,
  };
  req.auth = auth;
  req.ctx = buildContext(req, auth);
  req.log = req.log.child({ uid, role });
  next();
});

export function buildContext(req: import('express').Request, auth: AuthContext): RequestContext {
  return {
    auth,
    correlationId: req.correlationId,
    log: req.log,
    ip: req.ip,
    userAgent: req.header('User-Agent') ?? undefined,
  };
}

export const requireProfile: RequestHandler = (req, _res, next) => {
  if (!req.auth) return next(ApiError.unauthenticated());
  if (!req.auth.profile) return next(ApiError.forbidden('No profile yet — call POST /v1/auth/session first'));
  next();
};

export function requireRole(...roles: UserRole[]): RequestHandler {
  return (req, _res, next) => {
    if (!req.auth) return next(ApiError.unauthenticated());
    if (!roles.includes(req.auth.role)) return next(ApiError.forbidden(`Requires role: ${roles.join(', ')}`));
    next();
  };
}

export const requireStaff = requireRole(...STAFF_ROLES);
export const requireSupervisor = requireRole(...SUPERVISOR_ROLES);
export const requireManager = requireRole(...MANAGER_ROLES);
export const requireAdmin = requireRole('admin');

export function isStaff(role: UserRole): boolean {
  return STAFF_ROLES.includes(role);
}
export function isSupervisor(role: UserRole): boolean {
  return SUPERVISOR_ROLES.includes(role);
}
export function isManager(role: UserRole): boolean {
  return MANAGER_ROLES.includes(role);
}

/** Admin and finance see every outlet; other staff only their assigned ones. */
export function canSeeOutlet(auth: AuthContext, outletId: string | null | undefined): boolean {
  if (auth.role === 'admin' || auth.role === 'finance') return true;
  if (!outletId) return false;
  return auth.outletIds.includes(outletId);
}

export function assertOutlet(auth: AuthContext, outletId: string | null | undefined): void {
  if (!canSeeOutlet(auth, outletId)) throw ApiError.forbidden('Outlet is outside your scope');
}

/** Middleware form: outlet id from query/body/params. */
export function requireOutlet(source: 'query' | 'body' | 'params' = 'query', field = 'outlet_id'): RequestHandler {
  return (req, _res, next) => {
    if (!req.auth) return next(ApiError.unauthenticated());
    const raw = (req as any)[source]?.[field];
    if (!raw) return next(ApiError.validation(`${field} is required`));
    if (!canSeeOutlet(req.auth, String(raw))) return next(ApiError.forbidden('Outlet is outside your scope'));
    next();
  };
}

/** Ownership check: customer owns the row, or staff may see the outlet. */
export function assertOwnerOrOutletStaff(auth: AuthContext, row: { customer_id?: string | null; outlet_id?: string | null }): void {
  if (row.customer_id === auth.uid) return;
  if (isStaff(auth.role) && canSeeOutlet(auth, row.outlet_id)) return;
  throw ApiError.forbidden();
}

export function assertOwner(auth: AuthContext, row: { customer_id?: string | null }): void {
  if (row.customer_id !== auth.uid) throw ApiError.forbidden();
}
