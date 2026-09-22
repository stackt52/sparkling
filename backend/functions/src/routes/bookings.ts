/** Bookings (CUS-020..026). */
import { Router } from 'express';
import { z } from 'zod';
import { getSupabase, unwrap } from '../lib/supabase.js';
import { decodeCursor, pageResult, parseSort } from '../lib/refs.js';
import { clientOpId, isoDateTime, pagination, parseBody, parseQuery, uuid, vehicleSize } from '../lib/validate.js';
import { assertOwnerOrOutletStaff, canSeeOutlet, isStaff, requireProfile, requireStaff } from '../middleware/auth.js';
import { ApiError, asyncHandler } from '../middleware/errors.js';
import { bookingLimiter } from '../middleware/rateLimit.js';
import { attachPricing, cancelBooking, checkInBooking, createBooking, rescheduleBooking } from '../services/bookings.js';
import { canSeePickupOtp } from '../services/pickup.js';
import { buildTimeline, loadStepResults, loadTemplateForWorkOrder, progress } from '../services/workflow.js';
import type { Booking, Payment, Task, WorkOrder } from '../types.js';

export const bookingsRouter = Router();
bookingsRouter.use('/bookings', requireProfile);

export const BOOKING_EXPAND = '*, outlet:outlets(id, name, rating, city, timezone), service:services(id, name, duration_minutes, category, icon), vehicle:vehicles(id, registration_no, make, model, colour), customer:profiles!bookings_customer_id_fkey(id, full_name, email, phone)';
const EXPAND = BOOKING_EXPAND;

/** Adds the `work_order` summary (progress, assignee, bay) and pricing decorations to booking rows. */
export async function attachWorkOrders(rows: Array<Booking & Record<string, unknown>>): Promise<Array<Booking & Record<string, unknown>>> {
  if (rows.length === 0) return rows;
  const db = getSupabase();
  const ids = rows.map((r) => r.id);
  const wos = unwrap<Array<WorkOrder & { assignee: { full_name: string } | null }>>(
    await db.from('work_orders').select('*, assignee:profiles!work_orders_assignee_id_fkey(full_name)').in('booking_id', ids),
    'work orders',
  );
  const byBooking = new Map(wos.map((w) => [w.booking_id, w]));
  const results = wos.length ? unwrap<Array<{ work_order_id: string; status: string; step_key: string }>>(await db.from('checklist_step_results').select('work_order_id, status, step_key').in('work_order_id', wos.map((w) => w.id)), 'results') : [];
  const templateIds = [...new Set(wos.map((w) => w.checklist_template_id).filter(Boolean))] as string[];
  const templates = templateIds.length ? unwrap<Array<{ id: string; steps: unknown[] }>>(await db.from('checklist_templates').select('id, steps').in('id', templateIds), 'templates') : [];
  const stepCount = new Map(templates.map((t) => [t.id, t.steps.length]));
  const priced = await attachPricing(rows);
  return priced.map((b) => {
    const w = byBooking.get(b.id);
    if (!w) return { ...b, work_order: null };
    const done = results.filter((r) => r.work_order_id === w.id && r.status === 'done').length;
    const count = w.checklist_template_id ? (stepCount.get(w.checklist_template_id) ?? 0) : 0;
    return {
      ...b,
      work_order: {
        id: w.id,
        ref: w.ref,
        status: w.status,
        stage: Math.min(count, done + 1),
        stage_count: count,
        progress_pct: count ? Math.round((done / count) * 100) : 0,
        eta_at: w.eta_at,
        assignee_id: w.assignee_id ?? null,
        assignee_name: w.assignee?.full_name ?? null,
        bay: w.bay,
        blocked_reason: w.blocked_reason,
        verified_at: w.verified_at ?? null,
        pickup_otp_verified_at: w.pickup_otp_verified_at ?? null,
        collected_at: w.collected_at ?? null,
        updated_at: w.updated_at,
      },
    };
  });
}

bookingsRouter.get(
  '/bookings',
  asyncHandler(async (req, res) => {
    const q = parseQuery(pagination.extend({ status: z.string().optional(), outlet_id: uuid.optional(), customer_id: z.string().optional(), from: isoDateTime.optional(), to: isoDateTime.optional() }), req.query);
    const auth = req.auth!;
    const db = getSupabase();
    const offset = decodeCursor(q.cursor);
    const sort = parseSort(q.sort, ['slot_start', 'created_at', 'status'], { column: 'slot_start', ascending: false });
    let query = db.from('bookings').select(EXPAND).order(sort.column, { ascending: sort.ascending }).range(offset, offset + q.limit);
    if (isStaff(auth.role)) {
      if (q.outlet_id) {
        if (!canSeeOutlet(auth, q.outlet_id)) throw ApiError.forbidden('Outlet is outside your scope');
        query = query.eq('outlet_id', q.outlet_id);
      } else if (auth.role !== 'admin' && auth.role !== 'finance') {
        if (auth.outletIds.length === 0) return res.json({ data: [], next_cursor: null });
        query = query.in('outlet_id', auth.outletIds);
      }
      if (q.customer_id) query = query.eq('customer_id', q.customer_id);
    } else {
      query = query.eq('customer_id', auth.uid);
    }
    if (q.status) query = query.in('status', q.status.split(','));
    if (q.from) query = query.gte('slot_start', q.from);
    if (q.to) query = query.lte('slot_start', q.to);
    const rows = unwrap<Array<Booking & Record<string, unknown>>>(await query, 'bookings');
    const page = pageResult(rows, q.limit, offset);
    res.json({ data: await attachWorkOrders(page.data), next_cursor: page.next_cursor });
  }),
);

bookingsRouter.get(
  '/bookings/:id',
  asyncHandler(async (req, res) => {
    const id = uuid.parse(req.params.id);
    const db = getSupabase();
    const booking = unwrap<(Booking & Record<string, unknown>) | null>(await db.from('bookings').select(EXPAND).eq('id', id).maybeSingle(), 'booking');
    if (!booking) throw ApiError.notFound('Booking');
    assertOwnerOrOutletStaff(req.auth!, booking);
    const [withWo] = await attachWorkOrders([booking]);
    const payment = unwrap<Payment | null>(
      await db.from('payments').select('id, status, receipt_no, amount_cents, provider, method, created_at, verified_at').eq('booking_id', id).order('created_at', { ascending: false }).limit(1).maybeSingle(),
      'payment',
    );
    let timeline: unknown[] = [];
    if (withWo.work_order) {
      const wo = unwrap<WorkOrder>(await db.from('work_orders').select('*').eq('id', (withWo.work_order as { id: string }).id).single(), 'work order');
      const template = await loadTemplateForWorkOrder(wo);
      const results = await loadStepResults(wo.id);
      timeline = buildTimeline(wo, template?.steps ?? [], results, booking);
      Object.assign(withWo.work_order as object, progress(template?.steps ?? [], results));
      // Collection OTP: only the owning customer, only while completed and not yet collected (never staff).
      if (canSeePickupOtp(req.auth!, wo, booking.status)) Object.assign(withWo.work_order as object, { pickup_otp: wo.pickup_otp, pickup_otp_issued_at: wo.pickup_otp_issued_at });
    } else {
      timeline = [{ key: 'booked', title: 'Booked', state: 'done', at: booking.created_at }, { key: 'checked_in', title: 'Checked in', state: booking.status === 'cancelled' ? 'skipped' : 'pending' }];
    }
    // Staff see who took a walk-in at the counter.
    let created_by_name: string | null = null;
    if (isStaff(req.auth!.role) && booking.created_by && booking.created_by !== booking.customer_id) {
      created_by_name = unwrap<{ full_name: string } | null>(await db.from('profiles').select('full_name').eq('id', booking.created_by).maybeSingle(), 'creator')?.full_name ?? null;
    }
    res.json({ ...withWo, payment: payment ?? null, timeline, created_by_name });
  }),
);

const checkinSchema = z.object({ bay: z.string().trim().max(32).nullable().optional(), priority: z.number().int().min(1).max(3).optional() });

const createSchema = z.object({
  vehicle_id: uuid,
  outlet_id: uuid,
  service_id: uuid,
  /** Optional for staff walk-ins (defaults to now rounded up to the outlet slot grid). */
  slot_start: isoDateTime.optional(),
  client_op_id: clientOpId,
  notes: z.string().trim().max(500).nullable().optional(),
  customer_id: z.string().min(1).max(128).optional(),
  walk_in: z.boolean().optional(),
  /** Staff only: check the walk-in in immediately (work order + task). */
  checkin: checkinSchema.optional(),
  /** Pricing size; defaults to the vehicle's size_class (null → small). */
  vehicle_size: vehicleSize.optional(),
  /** Add-ons (`is_addon`, same group as the service) priced into the booking. */
  addon_service_ids: z.array(uuid).max(10).optional(),
  /** How the customer intends to pay; `cash` (feature flag `cash_on_collection`) confirms the booking without an online payment. */
  payment_method: z.enum(['card', 'eft', 'cash']).optional(),
});

bookingsRouter.post(
  '/bookings',
  bookingLimiter,
  asyncHandler(async (req, res) => {
    const body = parseBody(createSchema, req.body);
    const staff = isStaff(req.auth!.role);
    if ((body.walk_in || body.checkin) && !staff) throw ApiError.forbidden('walk_in and checkin are staff-only options');
    const created = await createBooking(req.ctx, {
      vehicleId: body.vehicle_id,
      outletId: body.outlet_id,
      serviceId: body.service_id,
      slotStart: body.slot_start ?? null,
      clientOpId: body.client_op_id,
      notes: body.notes,
      customerId: body.customer_id,
      walkIn: body.walk_in,
      vehicleSize: body.vehicle_size,
      addonServiceIds: body.addon_service_ids,
      paymentMethod: body.payment_method,
    });
    let booking: Booking = created.booking;
    let work_order: WorkOrder | null = null;
    let task: Task | null = null;
    if (body.checkin && ['pending', 'confirmed', 'in_service'].includes(booking.status)) {
      const checked = await checkInBooking(req.ctx, booking.id, body.checkin);
      booking = checked.booking;
      work_order = checked.work_order;
      task = checked.task;
    }
    const db = getSupabase();
    const full = unwrap<Booking & Record<string, unknown>>(await db.from('bookings').select(EXPAND).eq('id', booking.id).single(), 'booking');
    const [expanded] = await attachWorkOrders([full]);
    res.status(created.duplicate ? 200 : 201).json({ booking: expanded, duplicate: created.duplicate, ...(body.checkin ? { work_order, task } : {}) });
  }),
);

bookingsRouter.post(
  '/bookings/:id/cancel',
  asyncHandler(async (req, res) => {
    const id = uuid.parse(req.params.id);
    const body = parseBody(z.object({ reason: z.string().trim().max(500).nullable().optional() }), req.body);
    res.json({ booking: await cancelBooking(req.ctx, id, body.reason) });
  }),
);

bookingsRouter.post(
  '/bookings/:id/reschedule',
  bookingLimiter,
  asyncHandler(async (req, res) => {
    const id = uuid.parse(req.params.id);
    const body = parseBody(z.object({ slot_start: isoDateTime }), req.body);
    res.json({ booking: await rescheduleBooking(req.ctx, id, body.slot_start) });
  }),
);

bookingsRouter.post(
  '/bookings/:id/checkin',
  requireStaff,
  asyncHandler(async (req, res) => {
    const id = uuid.parse(req.params.id);
    const body = parseBody(checkinSchema, req.body);
    const result = await checkInBooking(req.ctx, id, body);
    res.status(result.created ? 201 : 200).json(result);
  }),
);
