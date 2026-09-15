/** Admin dashboard (ADM-001..042, REP-001..007). */
import { randomBytes } from 'node:crypto';
import { Router } from 'express';
import { z } from 'zod';
import { firebaseAuth } from '../lib/firebase.js';
import { getSupabase, unwrap } from '../lib/supabase.js';
import { decodeCursor, pageResult } from '../lib/refs.js';
import { isoDate, isoDateTime, pagination, parseBody, parseQuery, pricingMode, uuid, vatMode } from '../lib/validate.js';
import { canSeeOutlet, requireAdmin, requireProfile, requireRole } from '../middleware/auth.js';
import { ApiError, asyncHandler } from '../middleware/errors.js';
import { audit } from '../services/audit.js';
import { buildReport, computeActivity, computeExceptions, computeKpis, computeSummary, listAdminPayments, periodRange, REPORTS, staffPerformance, todayRangeUtc, type ReportName } from '../services/admin.js';
import { getAdminWorkOrder, listAdminWorkOrders } from '../services/adminWorkOrders.js';
import { createService, deleteOutletService, listAdminOutletOffers, listServicesWithComponents, updateService, upsertOutletService } from '../services/catalogueAdmin.js';
import { integrationStatus } from '../services/integrations.js';
import { getFlags, invalidateFlags } from '../services/flags.js';
import { resendNotification } from '../services/notifications.js';
import { attachWorkOrders, BOOKING_EXPAND } from './bookings.js';
import { listInventory } from './inventory.js';
import { enrolSchema, recordPaymentSchema } from './staffMemberships.js';
import { cancelMembership, enrolAtCounter, includedRemaining, listMembers, loadPlans, membershipBriefs, membershipSummary, planStats, recordInvoicePayment, runRenewals, updatePlan } from '../services/memberships.js';
import type { LoyaltyConfig, MembershipStatus, Profile, UserRole, WorkStatus } from '../types.js';
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

const kpiPeriod = z.enum(['today', 'week', 'month']);

/** `period=today|week|month` (calendar presets) or explicit `from`/`to`; default: last 7 days. */
adminRouter.get(
  '/admin/kpis',
  managerFinance,
  asyncHandler(async (req, res) => {
    const q = parseQuery(z.object({ outlet_id: uuid.optional(), period: kpiPeriod.optional(), from: isoDateTime.optional(), to: isoDateTime.optional() }), req.query);
    let from: string;
    let to: string;
    let period: 'today' | 'week' | 'month' | 'custom' = 'custom';
    if (q.period && !q.from && !q.to) {
      ({ from, to } = periodRange(q.period));
      period = q.period;
    } else {
      to = q.to ?? new Date().toISOString();
      from = q.from ?? new Date(new Date(to).getTime() - 7 * 86400_000).toISOString();
    }
    if (new Date(from) > new Date(to)) throw ApiError.validation('from must be before to');
    res.json(await computeKpis({ from, to, outletIds: scopeFor(req, q.outlet_id), period }));
  }),
);

adminRouter.get(
  '/admin/exceptions',
  managerFinance,
  asyncHandler(async (req, res) => {
    const q = parseQuery(z.object({ outlet_id: uuid.optional() }), req.query);
    res.json({ data: await computeExceptions(scopeFor(req, q.outlet_id)) });
  }),
);

adminRouter.get(
  '/admin/activity',
  managerFinance,
  asyncHandler(async (req, res) => {
    const q = parseQuery(z.object({ outlet_id: uuid.optional(), limit: z.coerce.number().int().min(1).max(100).default(30) }), req.query);
    res.json({ data: await computeActivity(scopeFor(req, q.outlet_id), q.limit) });
  }),
);

/** PostgREST `or()` filter matching a free-text search against the ref, customer name or plate (ids resolved first). */
async function bookingSearchFilter(search: string): Promise<string | null> {
  const s = search.replace(/[%_,()"\\]/g, '').trim();
  if (!s) return null;
  const db = getSupabase();
  const [customers, vehicles] = await Promise.all([
    db.from('profiles').select('id').eq('role', 'customer').ilike('full_name', `%${s}%`).limit(100),
    db.from('vehicles').select('id').ilike('registration_no', `%${s}%`).limit(100),
  ]);
  const parts = [`ref.ilike.%${s}%`];
  const customerIds = unwrap<Array<{ id: string }>>(customers, 'customers').map((c) => c.id);
  const vehicleIds = unwrap<Array<{ id: string }>>(vehicles, 'vehicles').map((v) => v.id);
  if (customerIds.length) parts.push(`customer_id.in.(${customerIds.join(',')})`);
  if (vehicleIds.length) parts.push(`vehicle_id.in.(${vehicleIds.join(',')})`);
  return parts.join(',');
}

/** Latest payment per booking (a successful one wins) in the finance-safe shape the drawer shows. */
async function attachPayments<T extends { id: string }>(rows: T[]): Promise<Array<T & { payment: Record<string, unknown> | null }>> {
  if (rows.length === 0) return [];
  const pays = unwrap<Array<Record<string, any>>>(
    await getSupabase().from('payments').select('id, booking_id, status, receipt_no, amount_cents, method, provider, created_at, verified_at').in('booking_id', rows.map((r) => r.id)),
    'payments',
  );
  const best = new Map<string, Record<string, any>>();
  for (const p of pays.sort((a, b) => String(b.created_at).localeCompare(String(a.created_at)))) {
    const cur = best.get(p.booking_id);
    if (!cur || (cur.status !== 'successful' && p.status === 'successful')) best.set(p.booking_id, p);
  }
  return rows.map((r) => {
    const p = best.get(r.id);
    return { ...r, payment: p ? { id: p.id, status: p.status, receipt_no: p.receipt_no ?? null, amount_cents: Number(p.amount_cents), method: p.method ?? null, provider: p.provider, verified_at: p.verified_at ?? null } : null };
  });
}

/** Names of the staff members who created walk-ins (`created_by_name`). */
async function attachCreators<T extends { created_by?: string | null; customer_id: string }>(rows: T[]): Promise<Array<T & { created_by_name: string | null }>> {
  const ids = [...new Set(rows.map((r) => r.created_by).filter((id): id is string => Boolean(id)))];
  const names = ids.length ? new Map(unwrap<Array<{ id: string; full_name: string }>>(await getSupabase().from('profiles').select('id, full_name').in('id', ids), 'creators').map((p) => [p.id, p.full_name])) : new Map<string, string>();
  return rows.map((r) => ({ ...r, created_by_name: r.created_by && r.created_by !== r.customer_id ? (names.get(r.created_by) ?? null) : null }));
}

adminRouter.get(
  '/admin/bookings',
  managerFinance,
  asyncHandler(async (req, res) => {
    const q = parseQuery(pagination.extend({ outlet_id: uuid.optional(), date: isoDate.optional(), status: z.string().optional(), search: z.string().max(60).optional() }), req.query);
    const db = getSupabase();
    const offset = decodeCursor(q.cursor);
    const scope = scopeFor(req, q.outlet_id);
    let query = db.from('bookings').select(BOOKING_EXPAND).order('slot_start', { ascending: true }).range(offset, offset + q.limit);
    if (scope) query = query.in('outlet_id', scope);
    if (q.date) query = query.gte('slot_start', `${q.date}T00:00:00Z`).lt('slot_start', `${q.date}T23:59:59.999Z`);
    if (q.status) query = query.in('status', q.status.split(','));
    if (q.search) {
      const filter = await bookingSearchFilter(q.search);
      if (filter) query = query.or(filter);
    }
    const page = pageResult(unwrap<any[]>(await query, 'bookings'), q.limit, offset);
    const data = await attachCreators(await attachPayments(await attachWorkOrders(page.data)));
    res.json({ data, next_cursor: page.next_cursor });
  }),
);

// ---------------------------------------------------------------------------
// Work-order board (admin shape: names, refs, progress, task id, audit trail)
// ---------------------------------------------------------------------------

const workStatusEnum = z.enum(['queued', 'assigned', 'in_progress', 'blocked', 'completed', 'verified', 'cancelled']);

/** Active work orders + those finished since `done_since` (default: start of today, UTC); `status` (comma list) lists exactly those statuses. */
adminRouter.get(
  '/admin/work-orders',
  managerFinance,
  asyncHandler(async (req, res) => {
    const q = parseQuery(z.object({ outlet_id: uuid.optional(), status: z.string().optional(), done_since: isoDateTime.optional(), limit: z.coerce.number().int().min(1).max(500).default(200) }), req.query);
    const statuses = q.status ? q.status.split(',').map((s) => workStatusEnum.parse(s.trim()) as WorkStatus) : null;
    const data = await listAdminWorkOrders({ outletIds: scopeFor(req, q.outlet_id), statuses, doneSince: q.done_since ?? todayRangeUtc().from, limit: q.limit });
    res.json({ data });
  }),
);

adminRouter.get(
  '/admin/work-orders/:id',
  managerFinance,
  asyncHandler(async (req, res) => {
    const id = uuid.parse(req.params.id);
    const wo = await getAdminWorkOrder(id);
    if (!wo) throw ApiError.notFound('Work order');
    if (!canSeeOutlet(req.auth!, wo.outlet.id)) throw ApiError.forbidden('Outlet is outside your scope');
    res.json({ work_order: wo });
  }),
);

// ---------------------------------------------------------------------------
// Catalogue CRUD (admin, audited)
// ---------------------------------------------------------------------------

/** Form inputs arrive as '' for "not set"; store null. */
const blankToNull = (v: unknown) => (typeof v === 'string' && v.trim() === '' ? null : v);
const optionalText = (max: number) => z.preprocess(blankToNull, z.string().trim().max(max).nullable().optional());

const bankDetailsSchema = z
  .object({
    financial_institution: optionalText(120),
    account_name: optionalText(120),
    branch: optionalText(120),
    branch_code: optionalText(32),
    account_number: optionalText(64),
    account_type: optionalText(64),
  })
  .nullable()
  .optional();

const outletSchema = z.object({
  code: z.string().trim().min(2).max(8).toUpperCase(),
  name: z.string().trim().min(2).max(80),
  address_line: optionalText(200),
  city: optionalText(80),
  province: optionalText(80),
  country: z.string().length(2).default('ZA'),
  latitude: z.number().min(-90).max(90).nullable().optional(),
  longitude: z.number().min(-180).max(180).nullable().optional(),
  phone: optionalText(32),
  email: z.preprocess(blankToNull, z.string().trim().email().nullable().optional()),
  timezone: z.string().min(3).max(64).default('Africa/Johannesburg'),
  opening_hours: z.record(z.tuple([z.string(), z.string()]).nullable()).optional(),
  slot_minutes: z.number().int().min(10).max(240).optional(),
  bay_count: z.number().int().min(1).max(50).optional(),
  rating: z.number().min(0).max(5).nullable().optional(),
  is_active: z.boolean().optional(),
  /** Legal / billing identity printed on quotations (migration 0007). */
  legal_name: optionalText(160),
  trading_as: optionalText(160),
  company_registration_no: optionalText(64),
  vat_number: optionalText(32),
  registered_office: optionalText(300),
  bank_details: bankDetailsSchema,
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

const componentInput = z.object({ child_service_id: uuid, quantity: z.number().int().min(1).max(99).optional(), sort_order: z.number().int().optional() });
const serviceGroup = z.enum(['Car Wash Options', 'Combinations', 'Auto Body Repair']);
const priceCents = z.number().int().min(0).max(100_000_000).nullable();

/** Canonical service fields (catalogue pricing model, migration 0008). `components` replaces the global composition set. */
const serviceSchema = z.object({
  code: z.string().trim().min(2).max(40).toUpperCase(),
  name: z.string().trim().min(2).max(120),
  description: z.string().trim().max(500).nullable().optional(),
  category: z.enum(['car_wash', 'auto_body']),
  duration_minutes: z.number().int().min(5).max(24 * 60),
  base_price_cents: z.number().int().min(0).optional(),
  is_quote_based: z.boolean().optional(),
  points_per_rand: z.number().min(0).max(10).optional(),
  icon: z.string().max(60).nullable().optional(),
  checklist_template_id: uuid.nullable().optional(),
  is_active: z.boolean().optional(),
  sort_order: z.number().int().optional(),
  group_name: serviceGroup.optional(),
  pricing_mode: pricingMode.optional(),
  vat_mode: vatMode.optional(),
  price_small_cents: priceCents.optional(),
  price_large_cents: priceCents.optional(),
  price_general_cents: priceCents.optional(),
  is_addon: z.boolean().optional(),
  addon_group_name: serviceGroup.nullable().optional(),
  notes: z.string().trim().max(500).nullable().optional(),
  components: z.array(componentInput).max(50).nullable().optional(),
});

adminRouter.get('/admin/services', managerFinance, asyncHandler(async (_req, res) => {
  res.json({ data: await listServicesWithComponents() });
}));

adminRouter.post('/admin/services', requireAdmin, asyncHandler(async (req, res) => {
  const { components, ...fields } = parseBody(serviceSchema, req.body);
  res.status(201).json({ service: await createService(req.ctx, fields, components) });
}));

const updateService_ = asyncHandler(async (req, res) => {
  const id = uuid.parse(req.params.id);
  const { components, ...fields } = parseBody(serviceSchema.partial(), req.body);
  res.json({ service: await updateService(req.ctx, id, fields, components) });
});
adminRouter.put('/admin/services/:id', requireAdmin, updateService_);
adminRouter.patch('/admin/services/:id', requireAdmin, updateService_);

adminRouter.delete('/admin/services/:id', requireAdmin, asyncHandler(async (req, res) => {
  const id = uuid.parse(req.params.id);
  await getSupabase().from('services').update({ is_active: false }).eq('id', id);
  await audit(req.ctx, { action: 'service.deactivate', entity_type: 'service', entity_id: id });
  res.status(204).end();
}));

/** Outlet offers incl. unavailable bindings, composition resolved (`components_source: outlet|global|none`). */
adminRouter.get('/admin/outlets/:id/services', managerFinance, asyncHandler(async (req, res) => {
  const id = uuid.parse(req.params.id);
  if (!canSeeOutlet(req.auth!, id)) throw ApiError.forbidden('Outlet is outside your scope');
  const { offers, groups } = await listAdminOutletOffers(id);
  res.json({ data: offers, groups });
}));

/** Whole outlet × service matrix (catalogue data). `outlet_id` narrows to one visible outlet. */
adminRouter.get('/admin/outlet-services', managerFinance, asyncHandler(async (req, res) => {
  const q = parseQuery(z.object({ outlet_id: uuid.optional() }), req.query);
  if (q.outlet_id && !canSeeOutlet(req.auth!, q.outlet_id)) throw ApiError.forbidden('Outlet is outside your scope');
  let query = getSupabase().from('outlet_services').select('outlet_id, service_id, price_cents, is_available, display_name, price_small_cents, price_large_cents, price_general_cents, pricing_mode, vat_mode, sort_order').order('outlet_id').order('service_id');
  if (q.outlet_id) query = query.eq('outlet_id', q.outlet_id);
  res.json({ data: unwrap<unknown[]>(await query, 'outlet services') });
}));

const outletServiceSchema = z.object({
  display_name: z.string().trim().min(1).max(160).nullable().optional(),
  price_small_cents: priceCents.optional(),
  price_large_cents: priceCents.optional(),
  price_general_cents: priceCents.optional(),
  pricing_mode: pricingMode.nullable().optional(),
  vat_mode: vatMode.nullable().optional(),
  is_available: z.boolean().optional(),
  sort_order: z.number().int().nullable().optional(),
  notes: z.string().trim().max(500).nullable().optional(),
  /** Legacy single price (pre-0008 admin clients). */
  price_cents: priceCents.optional(),
  /** Outlet-specific composition; `null` drops the outlet set so the global default applies. */
  components: z.array(componentInput).max(50).nullable().optional(),
});

adminRouter.put('/admin/outlets/:id/services/:serviceId', requireAdmin, asyncHandler(async (req, res) => {
  const outletId = uuid.parse(req.params.id);
  const serviceId = uuid.parse(req.params.serviceId);
  const { components, ...fields } = parseBody(outletServiceSchema, req.body);
  res.json({ outlet_service: await upsertOutletService(req.ctx, outletId, serviceId, fields, components) });
}));

adminRouter.delete('/admin/outlets/:id/services/:serviceId', requireAdmin, asyncHandler(async (req, res) => {
  const outletId = uuid.parse(req.params.id);
  const serviceId = uuid.parse(req.params.serviceId);
  await deleteOutletService(req.ctx, outletId, serviceId);
  res.status(204).end();
}));

// ---------------------------------------------------------------------------
// Users (ADM-020..023, SEC-014)
// ---------------------------------------------------------------------------

adminRouter.get('/admin/users', managerPlus, asyncHandler(async (req, res) => {
  const q = parseQuery(pagination.extend({ role: z.string().optional(), search: z.string().max(80).optional(), outlet_id: uuid.optional() }), req.query);
  const db = getSupabase();
  const offset = decodeCursor(q.cursor);
  let query = db.from('profiles').select('*, staff_outlets(outlet_id, is_primary, outlet:outlets(id, name)), staff_skills(skill)').neq('role', 'customer').order('full_name').range(offset, offset + q.limit);
  if (q.role) query = query.in('role', q.role.split(','));
  if (q.search) {
    const s = q.search.replace(/[%_,()]/g, '');
    query = query.or(`full_name.ilike.%${s}%,email.ilike.%${s}%`);
  }
  let rows = unwrap<any[]>(await query, 'users');
  if (q.outlet_id) rows = rows.filter((r) => (r.staff_outlets ?? []).some((o: any) => o.outlet_id === q.outlet_id));
  // Flatten the joins into the admin `StaffUser` shape (outlet_ids / outlet_names / skills).
  const users = rows.map(({ staff_outlets, staff_skills, ...profile }) => ({
    ...profile,
    outlet_ids: (staff_outlets ?? []).map((o: any) => o.outlet_id),
    outlet_names: (staff_outlets ?? []).map((o: any) => o.outlet?.name ?? '').filter(Boolean),
    skills: (staff_skills ?? []).map((k: any) => k.skill),
  }));
  res.json(pageResult(users, q.limit, offset));
}));

const roleEnum = z.enum(['customer', 'technician', 'supervisor', 'manager', 'admin', 'finance']);
const createUserSchema = z.object({
  email: z.string().email(),
  full_name: z.string().trim().min(2).max(120),
  role: roleEnum,
  phone: z.string().trim().max(32).nullable().optional(),
  outlet_ids: z.array(uuid).max(20).default([]),
  skills: z.array(z.string().trim().min(1).max(32)).max(20).default([]),
  /** 'password' (default) returns a temporary password the admin hands over; 'link' also returns a password-reset link. */
  invite: z.enum(['password', 'link']).default('password'),
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
  // Always issue a temporary password (shown once to the admin); the account is flagged so the
  // staff or admin app forces a password change on the first sign-in (`must_change_password`).
  const password = tempPassword();
  if (!user) {
    user = await auth.createUser({ email: body.email, displayName: body.full_name, password, emailVerified: false });
  } else {
    await auth.updateUser(user.uid, { password, displayName: body.full_name, disabled: false });
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
    profile = unwrap<Profile>(await db.from('profiles').update({ id: user.uid, role: body.role, full_name: body.full_name, phone: body.phone ?? null, is_active: true, must_change_password: true, deactivated_at: null }).eq('id', existingProfile.id).select('*').single(), 'claim profile');
  } else {
    profile = unwrap<Profile>(
      await db.from('profiles').upsert({ id: user.uid, role: body.role, full_name: body.full_name, email: body.email, phone: body.phone ?? null, is_active: true, must_change_password: true }, { onConflict: 'id' }).select('*').single(),
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
  res.status(201).json({ profile, uid: user.uid, temporary_password: password, invite_link: inviteLink });
}));

/**
 * Issues a fresh temporary password for a staff member (forgotten password, locked out). The
 * account must change it on the next sign-in; existing sessions are revoked.
 */
adminRouter.post('/admin/users/:id/reset-password', requireAdmin, asyncHandler(async (req, res) => {
  const id = z.string().min(1).parse(req.params.id);
  const db = getSupabase();
  const profile = unwrap<Profile | null>(await db.from('profiles').select('*').eq('id', id).maybeSingle(), 'profile');
  if (!profile) throw ApiError.notFound('User');
  if (profile.role === 'customer') throw ApiError.validation('Customers reset their own password from the app');
  if (!profile.email) throw ApiError.validation('User has no e-mail address');
  const fb = firebaseAuth();
  const password = tempPassword();
  try {
    await fb.updateUser(id, { password, disabled: false });
    await fb.revokeRefreshTokens(id);
  } catch (err) {
    req.log.error({ err, uid: id }, 'firebase password reset failed');
    throw ApiError.internal('Could not reset the password in Firebase Auth');
  }
  const updated = unwrap<Profile>(
    await db.from('profiles').update({ must_change_password: true, password_changed_at: null }).eq('id', id).select('*').single(),
    'flag password change',
  );
  await audit(req.ctx, { action: 'user.reset_password', entity_type: 'profile', entity_id: id, after: { email: profile.email } });
  res.json({ profile: updated, temporary_password: password });
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

const CUSTOMER_COLUMNS = 'id, role, full_name, email, phone, avatar_url, is_active, marketing_opt_in, whatsapp_opt_in, push_opt_in, last_seen_at, created_at';

/** Loyalty summary on customer rows: the account plus the live plan (docs/MEMBERSHIPS.md "customer summary"). */
async function customerSummaries<T extends { id: string }>(rows: T[]): Promise<Array<T & { vehicle_count: number; booking_count: number; loyalty: Record<string, unknown> | null }>> {
  if (rows.length === 0) return [];
  const db = getSupabase();
  const ids = rows.map((r) => r.id);
  const [vehicles, bookings, accounts, briefs] = await Promise.all([
    db.from('vehicles').select('customer_id').in('customer_id', ids).eq('is_active', true),
    db.from('bookings').select('customer_id').in('customer_id', ids),
    db.from('loyalty_accounts').select('*').in('customer_id', ids),
    membershipBriefs(ids),
  ]);
  const count = (xs: Array<{ customer_id: string }>) => {
    const m = new Map<string, number>();
    for (const x of xs) m.set(x.customer_id, (m.get(x.customer_id) ?? 0) + 1);
    return m;
  };
  const vehicleCount = count(unwrap<Array<{ customer_id: string }>>(vehicles, 'vehicles'));
  const bookingCount = count(unwrap<Array<{ customer_id: string }>>(bookings, 'bookings'));
  const account = new Map(unwrap<Array<Record<string, any>>>(accounts, 'loyalty accounts').map((a) => [a.customer_id as string, a]));
  return rows.map((r) => {
    const a = account.get(r.id);
    const brief = briefs.get(r.id) ?? null;
    const loyalty = a || brief
      ? { customer_id: r.id, tier: brief?.tier ?? a?.tier ?? 'silver', balance_points: Number(a?.balance_points ?? 0), lifetime_points: Number(a?.lifetime_points ?? 0), tier_since: a?.tier_since ?? a?.updated_at ?? null, plan_code: brief?.plan_code ?? null, plan_name: brief?.plan_name ?? null, membership_status: brief?.status ?? null, included_remaining: includedRemaining(brief) }
      : null;
    return { ...r, vehicle_count: vehicleCount.get(r.id) ?? 0, booking_count: bookingCount.get(r.id) ?? 0, loyalty };
  });
}

/** `search` matches name, e-mail, phone or number plate. Rows carry `vehicle_count`, `booking_count` and the `loyalty` summary. */
adminRouter.get('/admin/customers', managerFinance, asyncHandler(async (req, res) => {
  const q = parseQuery(pagination.extend({ search: z.string().max(80).optional() }), req.query);
  const db = getSupabase();
  const offset = decodeCursor(q.cursor);
  let query = db.from('profiles').select(CUSTOMER_COLUMNS).eq('role', 'customer').order('full_name').range(offset, offset + q.limit);
  const s = q.search?.replace(/[%_,()"\\]/g, '').trim();
  if (s) {
    const plates = unwrap<Array<{ customer_id: string }>>(await db.from('vehicles').select('customer_id').ilike('registration_no', `%${s}%`).limit(100), 'vehicles');
    const parts = [`full_name.ilike.%${s}%`, `email.ilike.%${s}%`, `phone.ilike.%${s}%`];
    const ids = [...new Set(plates.map((v) => v.customer_id))];
    if (ids.length) parts.push(`id.in.(${ids.join(',')})`);
    query = query.or(parts.join(','));
  }
  const page = pageResult(unwrap<any[]>(await query, 'customers'), q.limit, offset);
  await audit(req.ctx, { action: 'customer.search', entity_type: 'profile', after: { search: q.search ?? null, count: page.data.length } });
  res.json({ data: await customerSummaries(page.data), next_cursor: page.next_cursor });
}));

adminRouter.get('/admin/customers/:id', managerFinance, asyncHandler(async (req, res) => {
  const id = z.string().min(1).parse(req.params.id);
  const db = getSupabase();
  const row = unwrap<Profile | null>(await db.from('profiles').select(CUSTOMER_COLUMNS).eq('id', id).eq('role', 'customer').maybeSingle(), 'customer');
  if (!row) throw ApiError.notFound('Customer');
  const [vehicles, bookings, account, ledger, payments, membership, [summary]] = await Promise.all([
    db.from('vehicles').select('*').eq('customer_id', id).eq('is_active', true),
    db.from('bookings').select('*, outlet:outlets(id, name), service:services(id, name, category, duration_minutes), vehicle:vehicles(id, registration_no, make, model)').eq('customer_id', id).order('slot_start', { ascending: false }).limit(20),
    db.from('loyalty_accounts').select('*').eq('customer_id', id).maybeSingle(),
    db.from('loyalty_ledger').select('*').eq('customer_id', id).order('created_at', { ascending: false }).limit(20),
    db.from('payments').select('id, status, amount_cents, receipt_no, created_at, booking_id, membership_invoice_id').eq('customer_id', id).order('created_at', { ascending: false }).limit(20),
    membershipSummary(id),
    customerSummaries([row]),
  ]);
  await audit(req.ctx, { action: 'customer.view', entity_type: 'profile', entity_id: id });
  const { vehicle_count, booking_count, loyalty, ...customer } = summary;
  res.json({ customer, vehicle_count, booking_count, loyalty, vehicles: vehicles.data ?? [], bookings: bookings.data ?? [], loyalty_account: account.data ?? null, ledger: ledger.data ?? [], payments: payments.data ?? [], membership });
}));

// ---------------------------------------------------------------------------
// Loyalty config (ADM-025)
// ---------------------------------------------------------------------------

const tierSchema = z.object({
  tier: z.enum(['silver', 'gold', 'platinum', 'black']),
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

adminRouter.get('/admin/loyalty/config', managerFinance, asyncHandler(async (_req, res) => {
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
// Membership plans & members (docs/MEMBERSHIPS.md — admin; every write audited)
// ---------------------------------------------------------------------------

const membershipStatusEnum = z.enum(['pending', 'active', 'past_due', 'cancelled', 'expired']);
const planEntitlementSchema = z.object({
  code: z.string().trim().min(1).max(16),
  label: z.string().trim().min(1).max(120),
  quantity: z.number().int().min(1).max(999),
  period: z.enum(['month', 'year']).default('month'),
  sort_order: z.number().int().optional(),
  service_codes: z.array(z.string().trim().min(1).max(40).toUpperCase()).min(1).max(20),
});
const planGroupSchema = z.object({
  code: z.string().trim().min(1).max(40),
  name: z.string().trim().min(1).max(120),
  selection: z.enum(['choose_one', 'all']).default('choose_one'),
  sort_order: z.number().int().optional(),
  entitlements: z.array(planEntitlementSchema).min(1).max(20),
});
const planSchema = z.object({
  name: z.string().trim().min(2).max(60),
  tagline: z.string().trim().max(200).nullable().optional(),
  monthly_fee_cents: z.number().int().min(1).max(100_000_000),
  discount_pct: z.number().min(0).max(100),
  discount_scope: z.enum(['plan_services', 'other_services', 'all_services', 'none']),
  discount_note: z.string().trim().max(200).nullable().optional(),
  color: z.string().trim().max(40).nullable().optional(),
  sort_order: z.number().int().optional(),
  is_active: z.boolean().optional(),
  groups: z.array(planGroupSchema).max(10),
});

adminRouter.get('/admin/memberships/plans', managerFinance, asyncHandler(async (_req, res) => {
  const [plans, stats] = await Promise.all([loadPlans({ includeInactive: true }), planStats()]);
  res.json({ data: plans.map((p) => ({ ...p, ...(stats.get(p.id) ?? { member_count: 0, mrr_cents: 0 }) })) });
}));

adminRouter.put('/admin/memberships/plans/:code', managerPlus, asyncHandler(async (req, res) => {
  const code = z.string().trim().min(2).max(40).toLowerCase().parse(req.params.code);
  const body = parseBody(planSchema, req.body);
  const plan = await updatePlan(req.ctx, code, body);
  const stats = (await planStats()).get(plan.id) ?? { member_count: 0, mrr_cents: 0 };
  res.json({ plan: { ...plan, ...stats } });
}));

adminRouter.get('/admin/memberships', managerFinance, asyncHandler(async (req, res) => {
  const q = parseQuery(pagination.extend({ status: z.string().optional(), plan_code: z.string().max(40).optional(), q: z.string().max(80).optional() }), req.query);
  const statuses = q.status ? q.status.split(',').map((s) => membershipStatusEnum.parse(s.trim()) as MembershipStatus) : undefined;
  const offset = decodeCursor(q.cursor);
  const rows = await listMembers({ status: statuses, planCode: q.plan_code, q: q.q });
  res.json(pageResult(rows.slice(offset, offset + q.limit + 1), q.limit, offset));
}));

adminRouter.post('/admin/memberships/run-renewals', managerPlus, asyncHandler(async (req, res) => {
  const result = await runRenewals();
  await audit(req.ctx, { action: 'membership.run_renewals', entity_type: 'membership', after: { ...result, errors: result.errors.length } });
  res.json(result);
}));

adminRouter.post('/admin/customers/:id/membership', managerPlus, asyncHandler(async (req, res) => {
  const id = z.string().min(1).max(128).parse(req.params.id);
  const body = parseBody(enrolSchema, req.body);
  const customer = unwrap<Profile | null>(await getSupabase().from('profiles').select('*').eq('id', id).eq('role', 'customer').maybeSingle(), 'customer');
  if (!customer || !customer.is_active) throw ApiError.notFound('Customer');
  const r = await enrolAtCounter(req.ctx, { customerId: customer.id, planCode: body.plan_code, selections: body.selections, paymentMethod: body.payment_method, clientOpId: body.client_op_id, reference: body.reference ?? null, outletId: body.outlet_id ?? null });
  res.status(r.duplicate ? 200 : 201).json({ membership: r.membership, invoice: r.invoice, payment: r.payment, duplicate: r.duplicate, summary: await membershipSummary(customer.id) });
}));

adminRouter.post('/admin/memberships/:id/cancel', managerPlus, asyncHandler(async (req, res) => {
  const id = uuid.parse(req.params.id);
  const body = parseBody(z.object({ at_period_end: z.boolean().default(true), reason: z.string().trim().max(500).nullable().optional() }), req.body);
  res.json({ membership: await cancelMembership(req.ctx, id, { atPeriodEnd: body.at_period_end, reason: body.reason ?? null }) });
}));

adminRouter.post('/admin/memberships/:id/invoices/:invoiceId/record-payment', managerPlus, asyncHandler(async (req, res) => {
  const id = uuid.parse(req.params.id);
  const invoiceId = uuid.parse(req.params.invoiceId);
  const body = parseBody(recordPaymentSchema, req.body);
  const r = await recordInvoicePayment(req.ctx, id, invoiceId, { method: body.method, clientOpId: body.client_op_id, reference: body.reference ?? null, outletId: body.outlet_id ?? null });
  res.status(r.duplicate ? 200 : 201).json(r);
}));

// ---------------------------------------------------------------------------
// Inventory, staff performance, templates, audit, exports, flags
// ---------------------------------------------------------------------------

/** Query-string booleans (`z.coerce.boolean()` would read "false" as true). */
const queryBool = (fallback: boolean) => z.enum(['true', 'false', '1', '0']).optional().transform((v) => (v === undefined ? fallback : v === 'true' || v === '1'));

adminRouter.get('/admin/inventory', managerFinance, asyncHandler(async (req, res) => {
  const q = parseQuery(z.object({ outlet_id: uuid.optional(), alerts_first: queryBool(true) }), req.query);
  const scope = scopeFor(req, q.outlet_id);
  const outletIds = scope ?? unwrap<Array<{ id: string }>>(await getSupabase().from('outlets').select('id'), 'outlets').map((o) => o.id);
  res.json({ data: await listInventory(outletIds, q.alerts_first) });
}));

/** `period`: `today` (since 00:00 UTC), `week` (7 days), `month` (30 days), `quarter` (90 days). */
adminRouter.get('/admin/staff/performance', managerPlus, asyncHandler(async (req, res) => {
  const q = parseQuery(z.object({ outlet_id: uuid.optional(), period: z.enum(['today', 'week', 'month', 'quarter']).default('month') }), req.query);
  const to = new Date().toISOString();
  const days = q.period === 'week' ? 7 : q.period === 'month' ? 30 : 90;
  const from = q.period === 'today' ? todayRangeUtc().from : new Date(Date.now() - days * 86400_000).toISOString();
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
  status: z.enum(['draft', 'published']).optional(),
  /** Shorthand for `status`: `true` → published, `false` → draft (published when neither is given). */
  publish: z.boolean().optional(),
});

const templateStatus = (body: { status?: 'draft' | 'published'; publish?: boolean }): 'draft' | 'published' => body.status ?? (body.publish === false ? 'draft' : 'published');

adminRouter.get('/admin/templates', managerPlus, asyncHandler(async (_req, res) => {
  res.json({ data: unwrap<unknown[]>(await getSupabase().from('checklist_templates').select('*').order('name').order('version', { ascending: false }), 'templates') });
}));

adminRouter.post('/admin/templates', requireAdmin, asyncHandler(async (req, res) => {
  const { publish: _publish, ...body } = parseBody(templateSchema, req.body);
  const keys = new Set(body.steps.map((s) => s.key));
  if (keys.size !== body.steps.length) throw ApiError.validation('Step keys must be unique');
  const row = unwrap<Record<string, unknown>>(await getSupabase().from('checklist_templates').insert({ ...body, status: templateStatus({ ...body, publish: _publish }), version: 1, created_by: req.auth!.uid }).select('*').single(), 'create template');
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
    await db.from('checklist_templates').insert({ name, category: body.category ?? prev.category, steps: body.steps, outlet_id: body.outlet_id === undefined ? prev.outlet_id : body.outlet_id, status: templateStatus(body), version: (latest?.version ?? prev.version) + 1, created_by: req.auth!.uid }).select('*').single(),
    'new template version',
  );
  if (row.status === 'published') {
    await db.from('checklist_templates').update({ status: 'archived' }).eq('id', id);
    await db.from('services').update({ checklist_template_id: row.id }).eq('checklist_template_id', id);
  }
  await audit(req.ctx, { action: 'template.version', entity_type: 'checklist_template', entity_id: String(row.id), outlet_id: row.outlet_id ?? null, before: { id, version: prev.version }, after: { version: row.version } });
  res.status(201).json({ template: row, previous: { id, version: prev.version } });
}));

/** Admin and finance read everything; managers only events scoped to their outlets. Rows gain `actor_name`. */
adminRouter.get('/admin/audit', managerFinance, asyncHandler(async (req, res) => {
  const q = parseQuery(pagination.extend({ entity_type: z.string().max(40).optional(), entity_id: z.string().max(80).optional(), actor_id: z.string().max(128).optional(), action: z.string().max(60).optional() }), req.query);
  const db = getSupabase();
  const offset = decodeCursor(q.cursor);
  let query = db.from('audit_events').select('*').order('created_at', { ascending: false }).range(offset, offset + q.limit);
  if (req.auth!.role !== 'admin' && req.auth!.role !== 'finance') {
    if (!req.auth!.outletIds.length) return res.json({ data: [], next_cursor: null });
    query = query.in('outlet_id', req.auth!.outletIds);
  }
  if (q.entity_type) query = query.eq('entity_type', q.entity_type);
  if (q.entity_id) query = query.eq('entity_id', q.entity_id);
  if (q.actor_id) query = query.eq('actor_id', q.actor_id);
  if (q.action) query = query.ilike('action', `${q.action.replace(/[%_]/g, '')}%`);
  const page = pageResult(unwrap<Array<Record<string, any>>>(await query, 'audit'), q.limit, offset);
  const actorIds = [...new Set(page.data.map((e) => e.actor_id).filter((id): id is string => Boolean(id)))];
  const names = actorIds.length ? new Map(unwrap<Array<{ id: string; full_name: string }>>(await db.from('profiles').select('id, full_name').in('id', actorIds), 'actors').map((p) => [p.id, p.full_name])) : new Map<string, string>();
  res.json({ data: page.data.map((e) => ({ ...e, actor_name: e.actor_id ? (names.get(e.actor_id) ?? null) : null })), next_cursor: page.next_cursor });
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

adminRouter.get('/admin/flags', managerPlus, asyncHandler(async (_req, res) => {
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

// ---------------------------------------------------------------------------
// Notifications (delivery log + resend)
// ---------------------------------------------------------------------------

const notifyStatusEnum = z.enum(['queued', 'sent', 'delivered', 'failed', 'suppressed']);
const notifyChannelEnum = z.enum(['push', 'whatsapp', 'sms', 'email']);

adminRouter.get('/admin/notifications', managerFinance, asyncHandler(async (req, res) => {
  const q = parseQuery(
    pagination.extend({ status: z.string().optional(), channel: z.string().optional(), recipient_id: z.string().optional(), template_key: z.string().max(64).optional() }),
    req.query,
  );
  const statuses = q.status ? q.status.split(',').map((s) => notifyStatusEnum.parse(s.trim())) : null;
  const channels = q.channel ? q.channel.split(',').map((s) => notifyChannelEnum.parse(s.trim())) : null;
  const offset = decodeCursor(q.cursor);
  const db = getSupabase();
  let query = db
    .from('notifications')
    .select('id, recipient_id, channel, template_key, title, body, status, provider_ref, provider_status, provider_error_code, error, attempts, sent_at, delivered_at, read_by_recipient_at, read_at, created_at')
    .order('created_at', { ascending: false })
    .range(offset, offset + q.limit);
  if (statuses) query = query.in('status', statuses);
  if (channels) query = query.in('channel', channels);
  if (q.recipient_id) query = query.eq('recipient_id', q.recipient_id);
  if (q.template_key) query = query.eq('template_key', q.template_key);
  const rows = unwrap<Array<Record<string, unknown> & { recipient_id: string }>>(await query, 'notifications');
  const ids = [...new Set(rows.map((r) => r.recipient_id))];
  const names = ids.length ? unwrap<Array<{ id: string; full_name: string }>>(await db.from('profiles').select('id, full_name').in('id', ids), 'recipients') : [];
  const byId = new Map(names.map((n) => [n.id, n.full_name]));
  res.json(pageResult(rows.map((r) => ({ ...r, recipient_name: byId.get(r.recipient_id) ?? null })), q.limit, offset));
}));

adminRouter.post('/admin/notifications/:id/resend', managerPlus, asyncHandler(async (req, res) => {
  const id = uuid.parse(req.params.id);
  const out = await resendNotification(req.ctx, id);
  res.json(out);
}));

export type { UserRole };
