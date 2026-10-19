/** Work orders, checklist steps (STF-030..035) and vehicle collection OTP. */
import { Router } from 'express';
import { z } from 'zod';
import { PICKUP_OTP_PATTERN } from '../lib/otp.js';
import { getSupabase, unwrap } from '../lib/supabase.js';
import { clientOpId, counterPayment, parseBody, uuid } from '../lib/validate.js';
import { assertOwnerOrOutletStaff, requireManager, requireProfile, requireStaff } from '../middleware/auth.js';
import { ApiError, asyncHandler } from '../middleware/errors.js';
import { issuePickupOtp, redactPickupOtp, resendPickupOtp, verifyPickup } from '../services/pickup.js';
import { buildTimeline, checkInWorkOrder, loadStepResults, loadTemplateForWorkOrder, progress, recordStep } from '../services/workflow.js';
import { addStepPhoto, MAX_STEP_PHOTO_BYTES, openStepPhoto, stepPhotoView } from '../services/stepPhotos.js';
import { parseMultipart } from '../lib/multipart.js';
import { assertOutlet } from '../middleware/auth.js';
import type { Task, WorkOrder } from '../types.js';

export const workOrdersRouter = Router();
workOrdersRouter.use('/work-orders', requireProfile);

workOrdersRouter.get(
  '/work-orders/:id',
  asyncHandler(async (req, res) => {
    const id = uuid.parse(req.params.id);
    const db = getSupabase();
    const wo = unwrap<(WorkOrder & Record<string, unknown>) | null>(
      await db
        .from('work_orders')
        .select('*, vehicle:vehicles(id, registration_no, make, model, colour), service:services(id, name, category, duration_minutes), outlet:outlets(id, name), customer:profiles!work_orders_customer_id_fkey(id, full_name, phone), assignee:profiles!work_orders_assignee_id_fkey(id, full_name), booking:bookings(id, ref, status, slot_start, slot_end, total_cents, payment_method, pay_at)')
        .eq('id', id)
        .maybeSingle(),
      'work order',
    );
    if (!wo) throw ApiError.notFound('Work order');
    assertOwnerOrOutletStaff(req.auth!, wo);
    const isCustomer = req.auth!.role === 'customer';
    const [template, results, task, events] = await Promise.all([
      loadTemplateForWorkOrder(wo),
      loadStepResults(id),
      db.from('tasks').select('*').eq('work_order_id', id).order('seq').limit(1).maybeSingle(),
      isCustomer ? Promise.resolve({ data: [] }) : db.from('task_events').select('*').eq('work_order_id', id).order('created_at', { ascending: false }).limit(100),
    ]);
    const steps = template?.steps ?? [];
    if (isCustomer) delete (wo as Record<string, unknown>).customer;
    // The collection OTP is only ever shown to the owning customer while the vehicle is ready and uncollected.
    // Cash-on-collection: tell staff whether the counter payment has been recorded yet.
    const bk = wo.booking as ({ id: string; payment_method?: string | null } & Record<string, unknown>) | null;
    if (bk?.id) {
      const paid = unwrap<{ id: string }[]>(await db.from('payments').select('id').eq('booking_id', bk.id).eq('status', 'successful'), 'payments');
      (wo as Record<string, unknown>).booking = { ...bk, paid: paid.length > 0 };
    }
    const safe = redactPickupOtp(req.auth!, wo, (wo.booking as { status?: string } | null)?.status ?? null);
    res.json({
      work_order: { ...safe, ...progress(steps, results) },
      template: template ? { id: template.id, name: template.name, version: template.version, steps } : null,
      results,
      events: (events.data ?? []) as unknown[],
      task: (task.data as Task | null) ?? null,
      timeline: buildTimeline(wo, steps, results),
    });
  }),
);

const stepSchema = z.object({
  status: z.enum(['done', 'blocked', 'skipped']),
  value: z.unknown().optional(),
  attachment_id: uuid.nullable().optional(),
  note: z.string().trim().max(500).nullable().optional(),
  client_op_id: clientOpId.optional(),
});

workOrdersRouter.post(
  '/work-orders/:id/steps/:key',
  requireStaff,
  asyncHandler(async (req, res) => {
    const id = uuid.parse(req.params.id);
    const key = z.string().regex(/^[a-z0-9_]{1,64}$/).parse(req.params.key);
    const body = parseBody(stepSchema, req.body);
    const result = await recordStep(req.ctx, id, key, { status: body.status, value: body.value, attachmentId: body.attachment_id, note: body.note, clientOpId: body.client_op_id });
    res.json(result);
  }),
);

// ---------------------------------------------------------------------------
// Vehicle collection OTP (legacy car pick-up flow)
// ---------------------------------------------------------------------------

const pickupVerifySchema = z.object({
  otp: z.union([z.string(), z.number()]).transform((v) => String(v).trim()).pipe(z.string().regex(PICKUP_OTP_PATTERN, 'OTP is 5 digits')),
  /** Counter payment taken at hand-over (stage `collection`) — recorded before the OTP is checked. */
  payment: counterPayment.nullable().optional(),
});

/** Staff at the outlet confirm the OTP the customer presents; marks the vehicle collected. */
workOrdersRouter.post(
  '/work-orders/:id/pickup/verify',
  requireStaff,
  asyncHandler(async (req, res) => {
    const id = uuid.parse(req.params.id);
    const body = parseBody(pickupVerifySchema, req.body);
    const out = await verifyPickup(req.ctx, id, body.otp, { payment: body.payment ? { method: body.payment.method, reference: body.payment.reference ?? null, amountCents: body.payment.amount_cents, idempotencyKey: body.payment.idempotency_key } : null });
    res.json({ ...out, collected: true });
  }),
);

/** Re-sends the same OTP to the customer (push + WhatsApp); 1/min per work order. */
workOrdersRouter.post(
  '/work-orders/:id/pickup/resend',
  requireStaff,
  asyncHandler(async (req, res) => {
    const id = uuid.parse(req.params.id);
    const out = await resendPickupOtp(req.ctx, id);
    res.json(out);
  }),
);

const pickupIssueSchema = z.object({
  /** Why a new code was generated (customer never got it, lost phone, order locked…) — kept on the audit trail. */
  reason: z.string().trim().max(500).nullable().optional(),
  /** Send the new code to the customer (push + WhatsApp); default true. False when the admin reads it out instead. */
  notify: z.boolean().optional(),
});

/** Manager / admin / director generate a fresh collection OTP (dashboard); the code is returned so it can be read out. */
workOrdersRouter.post(
  '/work-orders/:id/pickup/issue',
  requireManager,
  asyncHandler(async (req, res) => {
    const id = uuid.parse(req.params.id);
    const body = parseBody(pickupIssueSchema, req.body);
    const out = await issuePickupOtp(req.ctx, id, { reason: body.reason ?? null, notify: body.notify });
    res.json(out);
  }),
);

const checkinSchema = z.object({
  bay: z.string().trim().max(32).nullable().optional(),
  /** Counter payment taken at check-in (stage `checkin`) for the booking / quotation. */
  payment: counterPayment.nullable().optional(),
});

/** Staff / admin confirm the vehicle is on site (required before the work order can be assigned), optionally taking payment. */
workOrdersRouter.post(
  '/work-orders/:id/checkin',
  requireStaff,
  asyncHandler(async (req, res) => {
    const id = uuid.parse(req.params.id);
    const body = parseBody(checkinSchema, req.body ?? {});
    const out = await checkInWorkOrder(req.ctx, id, { bay: body.bay, payment: body.payment ? { method: body.payment.method, reference: body.payment.reference ?? null, amountCents: body.payment.amount_cents, idempotencyKey: body.payment.idempotency_key } : null });
    res.status(out.already ? 200 : 201).json({ work_order: redactPickupOtp(req.auth!, out.work_order), task: out.task, already: out.already, payment: out.payment });
  }),
);

// ---------------------------------------------------------------------------
// Checklist step photos (STF-006): upload first, then submit the step with `attachment_id`.
// ---------------------------------------------------------------------------

async function loadWorkOrderForStaff(req: import('express').Request, id: string): Promise<WorkOrder> {
  const wo = unwrap<WorkOrder | null>(await getSupabase().from('work_orders').select('*').eq('id', id).maybeSingle(), 'work order');
  if (!wo) throw ApiError.notFound('Work order');
  assertOutlet(req.auth!, wo.outlet_id);
  return wo;
}

/** Multipart `photo` (JPEG/PNG/HEIC/WebP ≤ 10 MB) + optional `step_key` → `{ attachment }` with a private `url`. */
workOrdersRouter.post(
  '/work-orders/:id/photos',
  requireStaff,
  asyncHandler(async (req, res) => {
    const id = uuid.parse(req.params.id);
    const wo = await loadWorkOrderForStaff(req, id);
    const form = await parseMultipart(req, { fileField: 'photo', maxFileBytes: MAX_STEP_PHOTO_BYTES });
    if (!form.file) throw ApiError.validation('Missing "photo" file field', [{ path: 'photo', message: 'required' }]);
    const stepKey = form.fields.step_key ? z.string().regex(/^[a-z0-9_]{1,64}$/).parse(form.fields.step_key) : null;
    const att = await addStepPhoto(req.ctx, wo, { buffer: form.file.buffer, stepKey });
    res.status(201).json({ attachment: stepPhotoView(att, `/v1/work-orders/${id}`) });
  }),
);

workOrdersRouter.get(
  '/work-orders/:id/photos/:attachmentId',
  requireStaff,
  asyncHandler(async (req, res) => {
    const id = uuid.parse(req.params.id);
    const attachmentId = uuid.parse(req.params.attachmentId);
    await loadWorkOrderForStaff(req, id);
    const { attachment, object } = await openStepPhoto(id, attachmentId);
    res.setHeader('Content-Type', object.contentType ?? attachment.mime_type);
    if (object.size != null) res.setHeader('Content-Length', String(object.size));
    res.setHeader('Cache-Control', 'private, max-age=3600');
    object.stream.pipe(res);
  }),
);
