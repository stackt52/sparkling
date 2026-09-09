/** Admin dashboard (ADM-001..042, REP-001..007). */
import { randomBytes } from 'node:crypto';
import { Router } from 'express';
import { z } from 'zod';
import { firebaseAuth } from '../lib/firebase.js';
import { getSupabase, unwrap } from '../lib/supabase.js';
import { decodeCursor, pageResult } from '../lib/refs.js';
import { isoDate, isoDateTime, pagination, parseBody, parseQuery, uuid } from '../lib/validate.js';
import { canSeeOutlet, requireAdmin, requireProfile, requireRole } from '../middleware/auth.js';
import { ApiError, asyncHandler } from '../middleware/errors.js';
import { audit } from '../services/audit.js';
import { buildReport, computeActivity, computeExceptions, computeKpis, computeSummary, listAdminPayments, REPORTS, staffPerformance, type ReportName } from '../services/admin.js';
import { integrationStatus } from '../services/integrations.js';
import { getFlags, invalidateFlags } from '../services/flags.js';
import { listInventory } from './inventory.js';
import type { LoyaltyConfig, Profile, UserRole } from '../types.js';
import { STAFF_ROLES } from '../types.js';

export const adminRouter = Router();
adminRouter.use('/admin', requireProfile);

const managerPlus = requireRole('manager', 'admin');
const managerFinance = requireRole('manager', 'admin', 'finance');

/** Resolve outlet scope: explicit outlet (must be visible) or the caller's visible set (null = all). */
function scopeFor(req: import('express').Request, outletId?: string): string[] | null {
  const auth = req.auth!;
  if (outletId) {
    if (!canSeeOutlet(auth, outletId)) throw ApiError.forbidden('Outlet is outside your scope');
    return [outletId];
  }
  if (auth.role === 'admin' || auth.role === 'finance') return null;
  return auth.outletIds;
}

/** Report filters accept `YYYY-MM-DD` (whole days, UTC) or full ISO timestamps. */
const dateOrDateTime = z.union([isoDate, isoDateTime]);
const reportFilterSchema = z.object({ outlet_id: uuid.optional(), from: dateOrDateTime.optional(), to: dateOrDateTime.optional() });

export function reportBounds(from: string | undefined, to: string | undefined, defaultDays = 30): { from: string; to: string } {
  const toIso = to ? (to.length === 10 ? `${to}T23:59:59.999Z` : new Date(to).toISOString()) : new Date().toISOString();
  const fromIso = from ? (from.length === 10 ? `${from}T00:00:00.000Z` : new Date(from).toISOString()) : new Date(new Date(toIso).getTime() - defaultDays * 86400_000).toISOString();
  if (new Date(fromIso) > new Date(toIso)) throw ApiError.validation('from must be before to');
  return { from: fromIso, to: toIso };
}

// ---------------------------------------------------------------------------
// Overview
// ---------------------------------------------------------------------------

adminRouter.get(
  '/admin/kpis',
  managerFinance,
  asyncHandler(async (req, res) => {
    const q = parseQuery(z.object({ outlet_id: uuid.optional(), from: isoDateTime.optional(), to: isoDateTime.optional() }), req.query);
    const to = q.to ?? new Date().toISOString();
    const from = q.from ?? new Date(new Date(to).getTime() - 7 * 86400_000).toISOString();
    if (new Date(from) >= new Date(to)) throw ApiError.validation('from must be before to');
    res.json(await computeKpis({ from, to, outletIds: scopeFor(req, q.outlet_id) }));
  }),
);

adminRouter.get(
  '/admin/exceptions',
  managerPlus,
  asyncHandler(async (req, res) => {
    const q = parseQuery(z.object({ outlet_id: uuid.optional() }), req.query);
    res.json({ data: await computeExceptions(scopeFor(req, q.outlet_id)) });
  }),
);

adminRouter.get(
  '/admin/activity',
  managerPlus,
  asyncHandler(async (req, res) => {
    const q = parseQuery(z.object({ outlet_id: uuid.optional(), limit: z.coerce.number().int().min(1).max(100).default(30) }), req.query);
    res.json({ data: await computeActivity(scopeFor(req, q.outlet_id), q.limit) });
  }),
);

adminRouter.get(
  '/admin/bookings',
  managerFinance,
  asyncHandler(async (req, res) => {
    const q = parseQuery(pagination.extend({ outlet_id: uuid.optional(), date: isoDate.optional(), status: z.string().optional(), search: z.string().max(60).optional() }), req.query);
    const db = getSupabase();
    const offset = decodeCursor(q.cursor);
    const scope = scopeFor(req, q.outlet_id);
    let query = db
      .from('bookings')
      .select('*, outlet:outlets(id, name), service:services(id, name, category), vehicle:vehicles(id, registration_no, make, model), customer:profiles!bookings_customer_id_fkey(id, full_name, phone), work_order:work_orders(id, ref, status, bay, assignee:profiles!work_orders_assignee_id_fkey(full_name)), payments(id, status, receipt_no, amount_cents)')
      .order('slot_start', { ascending: true })
      .range(offset, offset + q.limit);
    if (scope) query = query.in('outlet_id', scope);
    if (q.date) query = query.gte('slot_start', `${q.date}T00:00:00Z`).lt('slot_start', `${q.date}T23:59:59.999Z`);
    if (q.status) query = query.in('status', q.status.split(','));
    if (q.search) query = query.ilike('ref', `%${q.search.replace(/[%_]/g, '')}%`);
    const rows = unwrap<any[]>(await query, 'bookings');
    res.json(pageResult(rows, q.limit, offset));
  }),
);

// ---------------------------------------------------------------------------
// Catalogue CRUD (admin, audited)
// ---------------------------------------------------------------------------

const outletSchema = z.object({
  code: z.string().trim().min(2).max(8).toUpperCase(),
  name: z.string().trim().min(2).max(80),
  address_line: z.string().trim().max(200).nullable().optional(),
  city: z.string().trim().max(80).nullable().optional(),
  province: z.string().trim().max(80).nullable().optional(),
  country: z.string().length(2).default('ZA'),
  latitude: z.number().min(-90).max(90).nullable().optional(),
  longitude: z.number().min(-180).max(180).nullable().optional(),
  phone: z.string().trim().max(32).nullable().optional(),
  email: z.string().email().nullable().optional(),
  timezone: z.string().min(3).max(64).default('Africa/Johannesburg'),
  opening_hours: z.record(z.tuple([z.string(), z.string()]).nullable()).optional(),
  slot_minutes: z.number().int().min(10).max(240).optional(),
  bay_count: z.number().int().min(1).max(50).optional(),
  rating: z.number().min(0).max(5).nullable().optional(),
  is_active: z.boolean().optional(),
});

adminRouter.get('/admin/outlets', managerFinance, asyncHandler(async (_req, res) => {
  res.json({ data: unwrap<unknown[]>(await getSupabase().from('outlets').select('*').order('name'), 'outlets') });
}));

adminRouter.post('/admin/outlets', requireAdmin, asyncHandler(async (req, res) => {
  const body = parseBody(outletSchema, req.body);
  const row = unwrap<Record<string, unknown>>(await getSupabase().from('outlets').insert(body).select('*').single(), 'create outlet');
  await audit(req.ctx, { action: 'outlet.create', entity_type: 'outlet', entity_id: String(row.id), outlet_id: String(row.id), after: body });
  res.status(201).json({ outlet: row });
}));

adminRouter.patch('/admin/outlets/:id', requireAdmin, asyncHandler(async (req, res) => {
  const id = uuid.parse(req.params.id);
  const body = parseBody(outletSchema.partial(), req.body);
  const db = getSupabase();
  const before = unwrap<Record<string, unknown> | null>(await db.from('outlets').select('*').eq('id', id).maybeSingle(), 'outlet');
  if (!before) throw ApiError.notFound('Outlet');
  const row = unwrap<Record<string, unknown>>(await db.from('outlets').update(body).eq('id', id).select('*').single(), 'update outlet');
  await audit(req.ctx, { action: 'outlet.update', entity_type: 'outlet', entity_id: id, outlet_id: id, before, after: body });
  res.json({ outlet: row });
}));

adminRouter.delete('/admin/outlets/:id', requireAdmin, asyncHandler(async (req, res) => {
  const id = uuid.parse(req.params.id);
  await getSupabase().from('outlets').update({ is_active: false }).eq('id', id);
  await audit(req.ctx, { action: 'outlet.deactivate', entity_type: 'outlet', entity_id: id, outlet_id: id });
  res.status(204).end();
}));

const serviceSchema = z.object({
  code: z.string().trim().min(2).max(16).toUpperCase(),
  name: z.string().trim().min(2).max(80),
  description: z.string().trim().max(500).nullable().optional(),
  category: z.enum(['car_wash', 'auto_body']),
  duration_minutes: z.number().int().min(5).max(24 * 60),
  base_price_cents: z.number().int().min(0),
  is_quote_based: z.boolean().default(false),
  points_per_rand: z.number().min(0).max(10).optional(),
  icon: z.string().max(60).nullable().optional(),
  checklist_template_id: uuid.nullable().optional(),
  is_active: z.boolean().optional(),
  sort_order: z.number().int().optional(),
});

adminRouter.get('/admin/services', managerFinance, asyncHandler(async (_req, res) => {
  res.json({ data: unwrap<unknown[]>(await getSupabase().from('services').select('*').order('sort_order'), 'services') });
}));

adminRouter.post('/admin/services', requireAdmin, asyncHandler(async (req, res) => {
  const body = parseBody(serviceSchema, req.body);
  const row = unwrap<Record<string, unknown>>(await getSupabase().from('services').insert(body).select('*').single(), 'create service');
  await audit(req.ctx, { action: 'service.create', entity_type: 'service', entity_id: String(row.id), after: body });
  res.status(201).json({ service: row });
}));

adminRouter.patch('/admin/services/:id', requireAdmin, asyncHandler(async (req, res) => {
  const id = uuid.parse(req.params.id);
  const body = parseBody(serviceSchema.partial(), req.body);
  const db = getSupabase();
  const before = unwrap<Record<string, unknown> | null>(await db.from('services').select('*').eq('id', id).maybeSingle(), 'service');
  if (!before) throw ApiError.notFound('Service');
  const row = unwrap<Record<string, unknown>>(await db.from('services').update(body).eq('id', id).select('*').single(), 'update service');
  await audit(req.ctx, { action: 'service.update', entity_type: 'service', entity_id: id, before, after: body });
  res.json({ service: row });
}));

adminRouter.delete('/admin/services/:id', requireAdmin, asyncHandler(async (req, res) => {
  const id = uuid.parse(req.params.id);
  await getSupabase().from('services').update({ is_active: false }).eq('id', id);
  await audit(req.ctx, { action: 'service.deactivate', entity_type: 'service', entity_id: id });
  res.status(204).end();
}));

adminRouter.get('/admin/outlets/:id/services', managerFinance, asyncHandler(async (req, res) => {
  const id = uuid.parse(req.params.id);
  res.json({ data: unwrap<unknown[]>(await getSupabase().from('outlet_services').select('*, service:services(*)').eq('outlet_id', id), 'outlet services') });
}));

/** Whole outlet × service matrix (catalogue data). `outlet_id` narrows to one visible outlet. */
adminRouter.get('/admin/outlet-services', managerFinance, asyncHandler(async (req, res) => {
  const q = parseQuery(z.object({ outlet_id: uuid.optional() }), req.query);
  if (q.outlet_id && !canSeeOutlet(req.auth!, q.outlet_id)) throw ApiError.forbidden('Outlet is outside your scope');
  let query = getSupabase().from('outlet_services').select('outlet_id, service_id, price_cents, is_available').order('outlet_id').order('service_id');
  if (q.outlet_id) query = query.eq('outlet_id', q.outlet_id);
  res.json({ data: unwrap<unknown[]>(await query, 'outlet services') });
}));

adminRouter.put('/admin/outlets/:id/services/:serviceId', requireAdmin, asyncHandler(async (req, res) => {
  const outletId = uuid.parse(req.params.id);
  const serviceId = uuid.parse(req.params.serviceId);
  const body = parseBody(z.object({ price_cents: z.number().int().min(0).nullable().optional(), is_available: z.boolean().optional() }), req.body);
  const db = getSupabase();
  const before = await db.from('outlet_services').select('*').eq('outlet_id', outletId).eq('service_id', serviceId).maybeSingle();
  const row = unwrap<Record<string, unknown>>(
    await db.from('outlet_services').upsert({ outlet_id: outletId, service_id: serviceId, ...body }, { onConflict: 'outlet_id,service_id' }).select('*').single(),
    'outlet service',
  );
  await audit(req.ctx, { action: 'outlet_service.upsert', entity_type: 'outlet_service', entity_id: `${outletId}:${serviceId}`, outlet_id: outletId, before: before.data ?? null, after: body });
  res.json({ outlet_service: row });
}));

adminRouter.delete('/admin/outlets/:id/services/:serviceId', requireAdmin, asyncHandler(async (req, res) => {
  const outletId = uuid.parse(req.params.id);
  const serviceId = uuid.parse(req.params.serviceId);
  await getSupabase().from('outlet_services').delete().eq('outlet_id', outletId).eq('service_id', serviceId);
  await audit(req.ctx, { action: 'outlet_service.delete', entity_type: 'outlet_service', entity_id: `${outletId}:${serviceId}`, outlet_id: outletId });
  res.status(204).end();
}));

// ---------------------------------------------------------------------------
// Users (ADM-020..023, SEC-014)
// ---------------------------------------------------------------------------

adminRouter.get('/admin/users', requireAdmin, asyncHandler(async (req, res) => {
  const q = parseQuery(pagination.extend({ role: z.string().optional(), search: z.string().max(80).optional(), outlet_id: uuid.optional() }), req.query);
  const db = getSupabase();
  const offset = decodeCursor(q.cursor);
  let query = db.from('profiles').select('*, staff_outlets(outlet_id, is_primary), staff_skills(skill)').neq('role', 'customer').order('full_name').range(offset, offset + q.limit);
  if (q.role) query = query.in('role', q.role.split(','));
  if (q.search) {
    const s = q.search.replace(/[%_,()]/g, '');
    query = query.or(`full_name.ilike.%${s}%,email.ilike.%${s}%`);
  }
  let rows = unwrap<any[]>(await query, 'users');
  if (q.outlet_id) rows = rows.filter((r) => (r.staff_outlets ?? []).some((o: any) => o.outlet_id === q.outlet_id));
  res.json(pageResult(rows, q.limit, offset));
}));

const roleEnum = z.enum(['customer', 'technician', 'supervisor', 'manager', 'admin', 'finance']);
const createUserSchema = z.object({
  email: z.string().email(),
  full_name: z.string().trim().min(2).max(120),
  role: roleEnum,
  phone: z.string().trim().max(32).nullable().optional(),
  outlet_ids: z.array(uuid).max(20).default([]),
  skills: z.array(z.string().trim().min(1).max(32)).max(20).default([]),
  /** 'password' returns a temporary password; 'link' returns a password-reset link */
  invite: z.enum(['password', 'link']).default('link'),
});

function tempPassword(): string {
  return `Spk-${randomBytes(9).toString('base64url')}`;
}

adminRouter.post('/admin/users', requireAdmin, asyncHandler(async (req, res) => {
  const body = parseBody(createUserSchema, req.body);
  const db = getSupabase();
  const auth = firebaseAuth();
  const existingProfile = unwrap<Profile | null>(await db.from('profiles').select('*').ilike('email', body.email).maybeSingle(), 'profile');
  if (existingProfile && !existingProfile.id.startsWith('seed_')) throw ApiError.conflict('A profile with this e-mail already exists', { profile_id: existingProfile.id });

  let user;
  try {
    user = await auth.getUserByEmail(body.email);
  } catch {
    user = null;
  }
  const password = body.invite === 'password' ? tempPassword() : undefined;
  if (!user) {
    user = await auth.createUser({ email: body.email, displayName: body.full_name, password: password ?? tempPassword(), emailVerified: false });
  }
  let inviteLink: string | null = null;
  if (body.invite === 'link') {
    try {
      inviteLink = await auth.generatePasswordResetLink(body.email);
    } catch (err) {
      req.log.warn({ err }, 'could not generate invite link');
    }
  }
  let profile: Profile;
  if (existingProfile) {
    profile = unwrap<Profile>(await db.from('profiles').update({ id: user.uid, role: body.role, full_name: body.full_name, phone: body.phone ?? null, is_active: true }).eq('id', existingProfile.id).select('*').single(), 'claim profile');
  } else {
    profile = unwrap<Profile>(
      await db.from('profiles').upsert({ id: user.uid, role: body.role, full_name: body.full_name, email: body.email, phone: body.phone ?? null, is_active: true }, { onConflict: 'id' }).select('*').single(),
      'create profile',
    );
  }
  await db.from('staff_outlets').delete().eq('profile_id', user.uid);
  if (STAFF_ROLES.includes(body.role) && body.outlet_ids.length) {
    await db.from('staff_outlets').insert(body.outlet_ids.map((o, i) => ({ profile_id: user.uid, outlet_id: o, is_primary: i === 0 })));
    await db.from('staff_availability').upsert({ profile_id: user.uid, status: 'available' }, { onConflict: 'profile_id' });
  }
  await db.from('staff_skills').delete().eq('profile_id', user.uid);
  if (body.skills.length) await db.from('staff_skills').insert(body.skills.map((skill) => ({ profile_id: user.uid, skill })));
  await auth.setCustomUserClaims(user.uid, { role: body.role, outlet_ids: STAFF_ROLES.includes(body.role) ? body.outlet_ids : [] });
  await audit(req.ctx, { action: 'user.create', entity_type: 'profile', entity_id: user.uid, after: { role: body.role, outlet_ids: body.outlet_ids, invite: body.invite } });
  res.status(201).json({ profile, uid: user.uid, temporary_password: password ?? null, invite_link: inviteLink });
}));

const patchUserSchema = z.object({
  role: roleEnum.optional(),
  outlet_ids: z.array(uuid).max(20).optional(),
  skills: z.array(z.string().trim().min(1).max(32)).max(20).optional(),
  is_active: z.boolean().optional(),
  full_name: z.string().trim().min(2).max(120).optional(),
  phone: z.string().trim().max(32).nullable().optional(),
}).strict();

adminRouter.patch('/admin/users/:id', requireAdmin, asyncHandler(async (req, res) => {
  const id = z.string().min(1).parse(req.params.id);
  const body = parseBody(patchUserSchema, req.body);
  const db = getSupabase();
  const before = unwrap<Profile | null>(await db.from('profiles').select('*').eq('id', id).maybeSingle(), 'profile');
  if (!before) throw ApiError.notFound('User');
  if (id === req.auth!.uid && (body.is_active === false || (body.role && body.role !== 'admin'))) throw ApiError.validation('You cannot deactivate or demote yourself');
  const patch: Partial<Profile> = {};
  if (body.role) patch.role = body.role;
  if (body.full_name) patch.full_name = body.full_name;
  if (body.phone !== undefined) patch.phone = body.phone;
  if (body.is_active !== undefined) {
    patch.is_active = body.is_active;
    patch.deactivated_at = body.is_active ? null : new Date().toISOString();
  }
  const profile = Object.keys(patch).length ? unwrap<Profile>(await db.from('profiles').update(patch).eq('id', id).select('*').single(), 'update profile') : before;
  if (body.outlet_ids) {
    await db.from('staff_outlets').delete().eq('profile_id', id);
    if (body.outlet_ids.length) await db.from('staff_outlets').insert(body.outlet_ids.map((o, i) => ({ profile_id: id, outlet_id: o, is_primary: i === 0 })));
  }
  if (body.skills) {
    await db.from('staff_skills').delete().eq('profile_id', id);
    if (body.skills.length) await db.from('staff_skills').insert(body.skills.map((skill) => ({ profile_id: id, skill })));
  }
  const outletIds = STAFF_ROLES.includes(profile.role) ? unwrap<Array<{ outlet_id: string }>>(await db.from('staff_outlets').select('outlet_id').eq('profile_id', id), 'outlets').map((o) => o.outlet_id) : [];
  const fb = firebaseAuth();
  if (!id.startsWith('seed_')) {
    try {
      if (profile.is_active) {
        await fb.setCustomUserClaims(id, { role: profile.role, outlet_ids: outletIds });
        if (before.is_active === false) await fb.updateUser(id, { disabled: false });
      } else {
        await fb.setCustomUserClaims(id, {});
        await fb.revokeRefreshTokens(id);
        await fb.updateUser(id, { disabled: true });
      }
    } catch (err) {
      req.log.warn({ err, uid: id }, 'firebase user update failed');
    }
  }
  await audit(req.ctx, { action: profile.is_active === false && before.is_active ? 'user.deactivate' : 'user.update', entity_type: 'profile', entity_id: id, before: { role: before.role, is_active: before.is_active }, after: { ...patch, outlet_ids: body.outlet_ids, skills: body.skills } });
  res.json({ profile, outlet_ids: outletIds });
}));

// ---------------------------------------------------------------------------
// Customers (ADM-024/041: access logged)
// ---------------------------------------------------------------------------

adminRouter.get('/admin/customers', managerPlus, asyncHandler(async (req, res) => {
  const q = parseQuery(pagination.extend({ search: z.string().max(80).optional() }), req.query);
  const db = getSupabase();
  const offset = decodeCursor(q.cursor);
  let query = db.from('profiles').select('id, full_name, email, phone, is_active, marketing_opt_in, created_at, last_seen_at, loyalty_accounts(tier, balance_points, lifetime_points)').eq('role', 'customer').order('full_name').range(offset, offset + q.limit);
  if (q.search) {
    const s = q.search.replace(/[%_,()]/g, '');
    query = query.or(`full_name.ilike.%${s}%,email.ilike.%${s}%,phone.ilike.%${s}%`);
  }
  const rows = unwrap<any[]>(await query, 'customers');
  await audit(req.ctx, { action: 'customer.search', entity_type: 'profile', after: { search: q.search ?? null, count: rows.length } });
  res.json(pageResult(rows, q.limit, offset));
}));

adminRouter.get('/admin/customers/:id', managerPlus, asyncHandler(async (req, res) => {
  const id = z.string().min(1).parse(req.params.id);
  const db = getSupabase();
  const customer = unwrap<Profile | null>(await db.from('profiles').select('*').eq('id', id).eq('role', 'customer').maybeSingle(), 'customer');
  if (!customer) throw ApiError.notFound('Customer');
  const [vehicles, bookings, account, ledger, payments] = await Promise.all([
    db.from('vehicles').select('*').eq('customer_id', id).eq('is_active', true),
    db.from('bookings').select('*, outlet:outlets(name), service:services(name)').eq('customer_id', id).order('slot_start', { ascending: false }).limit(20),
    db.from('loyalty_accounts').select('*').eq('customer_id', id).maybeSingle(),
    db.from('loyalty_ledger').select('*').eq('customer_id', id).order('created_at', { ascending: false }).limit(20),
    db.from('payments').select('id, status, amount_cents, receipt_no, created_at, booking_id').eq('customer_id', id).order('created_at', { ascending: false }).limit(20),
  ]);
  await audit(req.ctx, { action: 'customer.view', entity_type: 'profile', entity_id: id });
  res.json({ customer, vehicles: vehicles.data ?? [], bookings: bookings.data ?? [], loyalty_account: account.data ?? null, ledger: ledger.data ?? [], payments: payments.data ?? [] });
}));

// ---------------------------------------------------------------------------
// Loyalty config (ADM-025)
// ---------------------------------------------------------------------------

const tierSchema = z.object({
  tier: z.enum(['silver', 'gold', 'platinum']),
  name: z.string().trim().min(1).max(40),
  min_points: z.number().int().min(0),
  max_points: z.number().int().min(0).nullable(),
  earn_multiplier: z.number().min(0).max(10),
  discount_pct: z.number().min(0).max(100),
});
const rulesSchema = z.object({
  points_per_rand: z.number().min(0).max(10),
  award_on: z.enum(['completion', 'payment']).default('completion'),
  idempotent_award: z.boolean().default(true),
  expiry_months: z.number().int().min(1).max(120).nullable().optional(),
  birthday_bonus: z.object({ enabled: z.boolean(), points: z.number().int().min(0), reason: z.string().optional() }).optional(),
  referral_bonus: z.object({ enabled: z.boolean(), points: z.number().int().min(0) }).optional(),
}).passthrough();
const draftSchema = z.object({ tiers: z.array(tierSchema).min(1).max(5), rules: rulesSchema, change_note: z.string().trim().max(500).optional() });

async function loadConfigs() {
  const db = getSupabase();
  const [pub, draft] = await Promise.all([
    db.from('loyalty_configs').select('*').eq('status', 'published').maybeSingle(),
    db.from('loyalty_configs').select('*').eq('status', 'draft').order('version', { ascending: false }).limit(1).maybeSingle(),
  ]);
  return { published: unwrap<LoyaltyConfig | null>(pub, 'published'), draft: unwrap<LoyaltyConfig | null>(draft, 'draft') };
}

adminRouter.get('/admin/loyalty/config', managerPlus, asyncHandler(async (_req, res) => {
  res.json(await loadConfigs());
}));

adminRouter.put('/admin/loyalty/config/draft', managerPlus, asyncHandler(async (req, res) => {
  const body = parseBody(draftSchema, req.body);
  const tiers = [...body.tiers].sort((a, b) => a.min_points - b.min_points);
  for (let i = 1; i < tiers.length; i++) if (tiers[i].min_points <= tiers[i - 1].min_points) throw ApiError.validation('Tier min_points must be strictly increasing');
  const db = getSupabase();
  const { draft } = await loadConfigs();
  let row: LoyaltyConfig;
  if (draft) {
    row = unwrap<LoyaltyConfig>(await db.from('loyalty_configs').update({ tiers, rules: body.rules, change_note: body.change_note ?? draft.change_note, created_by: req.auth!.uid }).eq('id', draft.id).select('*').single(), 'update draft');
  } else {
    const maxVer = unwrap<{ version: number } | null>(await db.from('loyalty_configs').select('version').order('version', { ascending: false }).limit(1).maybeSingle(), 'version');
    row = unwrap<LoyaltyConfig>(await db.from('loyalty_configs').insert({ version: (maxVer?.version ?? 0) + 1, status: 'draft', tiers, rules: body.rules, change_note: body.change_note ?? null, created_by: req.auth!.uid }).select('*').single(), 'create draft');
  }
  await audit(req.ctx, { action: 'loyalty_config.draft', entity_type: 'loyalty_config', entity_id: row.id, after: { version: row.version, change_note: row.change_note } });
  res.json({ draft: row });
}));

adminRouter.post('/admin/loyalty/config/publish', requireAdmin, asyncHandler(async (req, res) => {
  const db = getSupabase();
  const { published, draft } = await loadConfigs();
  if (!draft) throw ApiError.conflict('No draft to publish');
  if (published) await db.from('loyalty_configs').update({ status: 'archived' }).eq('id', published.id);
  const row = unwrap<LoyaltyConfig>(await db.from('loyalty_configs').update({ status: 'published', published_by: req.auth!.uid, published_at: new Date().toISOString() }).eq('id', draft.id).select('*').single(), 'publish');
  await audit(req.ctx, { action: 'loyalty_config.publish', entity_type: 'loyalty_config', entity_id: row.id, before: published ? { version: published.version } : null, after: { version: row.version, change_note: row.change_note } });
  res.json({ published: row, archived: published ? { id: published.id, version: published.version } : null });
}));

adminRouter.post('/admin/loyalty/config/discard', managerPlus, asyncHandler(async (req, res) => {
  const db = getSupabase();
  const { draft } = await loadConfigs();
  if (!draft) throw ApiError.notFound('Draft');
  await db.from('loyalty_configs').delete().eq('id', draft.id);
  await audit(req.ctx, { action: 'loyalty_config.discard', entity_type: 'loyalty_config', entity_id: draft.id, before: { version: draft.version } });
  res.json({ discarded: { id: draft.id, version: draft.version } });
}));

// ---------------------------------------------------------------------------
// Inventory, staff performance, templates, audit, exports, flags
// ---------------------------------------------------------------------------

adminRouter.get('/admin/inventory', managerPlus, asyncHandler(async (req, res) => {
  const q = parseQuery(z.object({ outlet_id: uuid.optional(), alerts_first: z.coerce.boolean().default(true) }), req.query);
  const scope = scopeFor(req, q.outlet_id);
  const outletIds = scope ?? unwrap<Array<{ id: string }>>(await getSupabase().from('outlets').select('id'), 'outlets').map((o) => o.id);
  res.json({ data: await listInventory(outletIds, q.alerts_first) });
}));

adminRouter.get('/admin/staff/performance', managerPlus, asyncHandler(async (req, res) => {
  const q = parseQuery(z.object({ outlet_id: uuid.optional(), period: z.enum(['week', 'month', 'quarter']).default('month') }), req.query);
  const days = q.period === 'week' ? 7 : q.period === 'month' ? 30 : 90;
  const to = new Date().toISOString();
  const from = new Date(Date.now() - days * 86400_000).toISOString();
  res.json({ period: q.period, from, to, data: await staffPerformance(scopeFor(req, q.outlet_id), from, to) });
}));

const stepSchema = z.object({
  key: z.string().regex(/^[a-z0-9_]{1,64}$/),
  title: z.string().trim().min(1).max(120),
  type: z.enum(['confirm', 'text', 'numeric', 'select', 'photo', 'ack', 'supervisor_verify']),
  required: z.boolean().default(true),
  hint: z.string().max(200).optional(),
  options: z.array(z.string().max(60)).max(20).optional(),
  unit: z.string().max(12).optional(),
  min: z.number().optional(),
  max: z.number().optional(),
  photo_required: z.boolean().optional(),
});
const templateSchema = z.object({
  name: z.string().trim().min(2).max(80),
  category: z.enum(['car_wash', 'auto_body']),
  steps: z.array(stepSchema).min(1).max(50),
  outlet_id: uuid.nullable().optional(),
  status: z.enum(['draft', 'published']).default('published'),
});

adminRouter.get('/admin/templates', managerPlus, asyncHandler(async (_req, res) => {
  res.json({ data: unwrap<unknown[]>(await getSupabase().from('checklist_templates').select('*').order('name').order('version', { ascending: false }), 'templates') });
}));

adminRouter.post('/admin/templates', requireAdmin, asyncHandler(async (req, res) => {
  const body = parseBody(templateSchema, req.body);
  const keys = new Set(body.steps.map((s) => s.key));
  if (keys.size !== body.steps.length) throw ApiError.validation('Step keys must be unique');
  const row = unwrap<Record<string, unknown>>(await getSupabase().from('checklist_templates').insert({ ...body, version: 1, created_by: req.auth!.uid }).select('*').single(), 'create template');
  await audit(req.ctx, { action: 'template.create', entity_type: 'checklist_template', entity_id: String(row.id), outlet_id: body.outlet_id ?? null, after: { name: body.name, version: 1 } });
  res.status(201).json({ template: row });
}));

/** PUT creates a new version (published templates are immutable snapshots for work orders). */
adminRouter.put('/admin/templates/:id', requireAdmin, asyncHandler(async (req, res) => {
  const id = uuid.parse(req.params.id);
  const body = parseBody(templateSchema.partial({ name: true, category: true }), req.body);
  const db = getSupabase();
  const prev = unwrap<Record<string, any> | null>(await db.from('checklist_templates').select('*').eq('id', id).maybeSingle(), 'template');
  if (!prev) throw ApiError.notFound('Template');
  const keys = new Set(body.steps.map((s) => s.key));
  if (keys.size !== body.steps.length) throw ApiError.validation('Step keys must be unique');
  const name = body.name ?? prev.name;
  const latest = unwrap<{ version: number } | null>(await db.from('checklist_templates').select('version').eq('name', name).eq('outlet_key', prev.outlet_key).order('version', { ascending: false }).limit(1).maybeSingle(), 'version');
  const row = unwrap<Record<string, any>>(
    await db.from('checklist_templates').insert({ name, category: body.category ?? prev.category, steps: body.steps, outlet_id: body.outlet_id === undefined ? prev.outlet_id : body.outlet_id, status: body.status ?? 'published', version: (latest?.version ?? prev.version) + 1, created_by: req.auth!.uid }).select('*').single(),
    'new template version',
  );
  if (row.status === 'published') {
    await db.from('checklist_templates').update({ status: 'archived' }).eq('id', id);
    await db.from('services').update({ checklist_template_id: row.id }).eq('checklist_template_id', id);
  }
  await audit(req.ctx, { action: 'template.version', entity_type: 'checklist_template', entity_id: String(row.id), outlet_id: row.outlet_id ?? null, before: { id, version: prev.version }, after: { version: row.version } });
  res.status(201).json({ template: row, previous: { id, version: prev.version } });
}));

adminRouter.get('/admin/audit', managerPlus, asyncHandler(async (req, res) => {
  const q = parseQuery(pagination.extend({ entity_type: z.string().max(40).optional(), entity_id: z.string().max(80).optional(), actor_id: z.string().max(128).optional(), action: z.string().max(60).optional() }), req.query);
  const db = getSupabase();
  const offset = decodeCursor(q.cursor);
  let query = db.from('audit_events').select('*').order('created_at', { ascending: false }).range(offset, offset + q.limit);
  if (req.auth!.role !== 'admin') {
    if (!req.auth!.outletIds.length) return res.json({ data: [], next_cursor: null });
    query = query.in('outlet_id', req.auth!.outletIds);
  }
  if (q.entity_type) query = query.eq('entity_type', q.entity_type);
  if (q.entity_id) query = query.eq('entity_id', q.entity_id);
  if (q.actor_id) query = query.eq('actor_id', q.actor_id);
  if (q.action) query = query.ilike('action', `${q.action.replace(/[%_]/g, '')}%`);
  res.json(pageResult(unwrap<unknown[]>(await query, 'audit'), q.limit, offset));
}));

adminRouter.get('/admin/exports/:report', managerFinance, asyncHandler(async (req, res) => {
  const name = String(req.params.report).replace(/\.csv$/i, '') as ReportName;
  if (!REPORTS.includes(name)) throw ApiError.notFound('Report');
  const q = parseQuery(reportFilterSchema, req.query);
  const csv = await buildReport(name, req.auth!, { ...q, ...reportBounds(q.from, q.to) }, scopeFor(req, q.outlet_id));
  await audit(req.ctx, { action: 'export.csv', entity_type: 'report', entity_id: name, outlet_id: q.outlet_id ?? null, after: q });
  res.setHeader('Content-Type', 'text/csv; charset=utf-8');
  res.setHeader('Content-Disposition', `attachment; filename="sparkling-${name}-${new Date().toISOString().slice(0, 10)}.csv"`);
  res.send(csv);
}));

adminRouter.get('/admin/flags', requireAdmin, asyncHandler(async (_req, res) => {
  res.json({ data: unwrap<unknown[]>(await getSupabase().from('feature_flags').select('*').order('key'), 'flags'), effective: await getFlags(true) });
}));

adminRouter.patch('/admin/flags/:key', requireAdmin, asyncHandler(async (req, res) => {
  const key = z.string().regex(/^[a-z0-9_]{2,64}$/).parse(req.params.key);
  const body = parseBody(z.object({ enabled: z.boolean(), description: z.string().max(200).optional() }), req.body);
  const db = getSupabase();
  const before = await db.from('feature_flags').select('*').eq('key', key).maybeSingle();
  if (!before.data) throw ApiError.notFound('Flag');
  const row = unwrap<Record<string, unknown>>(await db.from('feature_flags').update({ ...body, updated_at: new Date().toISOString() }).eq('key', key).select('*').single(), 'flag');
  invalidateFlags();
  await audit(req.ctx, { action: 'flag.update', entity_type: 'feature_flag', entity_id: key, before: before.data, after: body });
  res.json({ flag: row });
}));

// ---------------------------------------------------------------------------
// Payments (ADM-061), report summary (REP-005), integrations (ADM-040)
// ---------------------------------------------------------------------------

const paymentStatusEnum = z.enum(['initiated', 'pending', 'successful', 'failed', 'cancelled', 'refunded']);

adminRouter.get('/admin/payments', managerFinance, asyncHandler(async (req, res) => {
  const q = parseQuery(reportFilterSchema.extend({ status: z.string().optional(), limit: z.coerce.number().int().min(1).max(200).default(50), cursor: z.string().optional() }), req.query);
  const statuses = q.status ? q.status.split(',').map((s) => paymentStatusEnum.parse(s.trim())) : undefined;
  const range = reportBounds(q.from, q.to);
  const offset = decodeCursor(q.cursor);
  const page = await listAdminPayments({ ...range, outletIds: scopeFor(req, q.outlet_id) }, statuses, q.limit, offset);
  res.json({ range, ...page });
}));

adminRouter.get('/admin/reports/summary', managerFinance, asyncHandler(async (req, res) => {
  const q = parseQuery(reportFilterSchema, req.query);
  const range = reportBounds(q.from, q.to);
  res.json(await computeSummary({ ...range, outletIds: scopeFor(req, q.outlet_id) }));
}));

adminRouter.get('/admin/integrations', managerPlus, asyncHandler(async (_req, res) => {
  res.json({ data: await integrationStatus() });
}));

export type { UserRole };
