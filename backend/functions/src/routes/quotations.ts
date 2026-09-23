/** Quotations (CUS-030..034, STF-010/012): requests, staff-raised quotes, damage photos, share link, PDF, decisions. */
import { Router, type Request, type Response } from 'express';
import { z } from 'zod';
import { getSupabase, unwrap } from '../lib/supabase.js';
import { decodeCursor, pageResult } from '../lib/refs.js';
import { parseMultipart } from '../lib/multipart.js';
import { clientOpId, isoDate, pagination, parseBody, parseQuery, uuid } from '../lib/validate.js';
import { assertOutlet, assertOwnerOrOutletStaff, canSeeOutlet, isStaff, requireProfile, requireStaff, requireSupervisor } from '../middleware/auth.js';
import { ApiError, asyncHandler } from '../middleware/errors.js';
import { pdfFilename, renderQuotationPdf } from '../services/quotationPdf.js';
import { addPhoto, deletePhoto, MAX_PHOTO_BYTES, openPhoto, PHOTO_CACHE_CONTROL } from '../services/quotationPhotos.js';
import {
  assertCanReadQuotation,
  attachmentView,
  convert,
  createQuotation,
  decide,
  getQuotationOrThrow,
  loadQuotationAttachments,
  presentQuotation,
  quote,
  raiseQuotation,
  shareQuotation,
} from '../services/quotations.js';
import type { Attachment, Quotation } from '../types.js';

export const quotationsRouter = Router();
quotationsRouter.use('/quotations', requireProfile);

const EXPAND = '*, outlet:outlets(id, name), vehicle:vehicles(id, registration_no, make, model, colour), customer:profiles!quotations_customer_id_fkey(id, full_name, phone, email), assessor:profiles!quotations_assessor_id_fkey(id, full_name)';

/**
 * Re-reads a quotation with its joins, attachments and work order and presents
 * it for the caller — used by every mutation so responses carry the same
 * `customer_name` / `assessor_name` / `work_order_ref` fields as `GET /quotations/:id`.
 */
async function presentedQuotation(id: string, auth: NonNullable<Request['auth']>): Promise<Record<string, unknown>> {
  const db = getSupabase();
  const [row, attachments, workOrder] = await Promise.all([
    db.from('quotations').select(EXPAND).eq('id', id).maybeSingle(),
    loadQuotationAttachments([id]),
    db.from('work_orders').select('id, ref, status, checked_in_at').eq('quotation_id', id).maybeSingle(),
  ]);
  const q = unwrap<(Quotation & Record<string, unknown>) | null>(row, 'quotation');
  if (!q) throw ApiError.notFound('Quotation');
  // Names come from the embedded joins; fall back to direct lookups when a join was not resolved.
  if (!q.customer && q.customer_id) q.customer = unwrap<{ id: string; full_name: string } | null>(await db.from('profiles').select('id, full_name, phone, email').eq('id', q.customer_id).maybeSingle(), 'customer');
  if (!q.assessor && q.assessor_id) q.assessor = unwrap<{ id: string; full_name: string } | null>(await db.from('profiles').select('id, full_name').eq('id', q.assessor_id).maybeSingle(), 'assessor');
  const wo = unwrap<{ id: string; ref: string; status: string } | null>(workOrder, 'work order');
  const paid = unwrap<Array<{ id: string; receipt_no: string | null; amount_cents: number; method: string | null; verified_at: string | null }>>(
    await db.from('payments').select('id, receipt_no, amount_cents, method, verified_at').eq('quotation_id', id).eq('status', 'successful'),
    'payments',
  );
  const payment = paid[0] ?? null;
  return { ...presentQuotation(q, attachments, auth), work_order: wo, work_order_ref: wo?.ref ?? null, payment, amount_due_cents: payment ? 0 : (q.amount_cents ?? 0) };
}

quotationsRouter.get(
  '/quotations',
  asyncHandler(async (req, res) => {
    const q = parseQuery(pagination.extend({ status: z.string().optional(), outlet_id: uuid.optional() }), req.query);
    const auth = req.auth!;
    const db = getSupabase();
    const offset = decodeCursor(q.cursor);
    let query = db.from('quotations').select(EXPAND).order('created_at', { ascending: false }).range(offset, offset + q.limit);
    if (isStaff(auth.role)) {
      if (q.outlet_id) {
        if (!canSeeOutlet(auth, q.outlet_id)) throw ApiError.forbidden('Outlet is outside your scope');
        query = query.eq('outlet_id', q.outlet_id);
      } else if (auth.role !== 'admin' && auth.role !== 'finance') {
        if (auth.outletIds.length === 0) return res.json({ data: [], next_cursor: null });
        query = query.in('outlet_id', auth.outletIds);
      }
    } else {
      query = query.eq('customer_id', auth.uid);
    }
    if (q.status) query = query.in('status', q.status.split(','));
    const rows = unwrap<Array<Quotation & Record<string, unknown>>>(await query, 'quotations');
    const page = pageResult(rows, q.limit, offset);
    const attachments = await loadQuotationAttachments(page.data.map((r) => r.id));
    const byQuotation = new Map<string, Attachment[]>();
    for (const a of attachments) byQuotation.set(a.entity_id, [...(byQuotation.get(a.entity_id) ?? []), a]);
    res.json({ data: page.data.map((r) => presentQuotation(r, byQuotation.get(r.id) ?? [], auth)), next_cursor: page.next_cursor });
  }),
);

quotationsRouter.get(
  '/quotations/:id',
  asyncHandler(async (req, res) => {
    const id = uuid.parse(req.params.id);
    const db = getSupabase();
    const q = unwrap<Quotation | null>(await db.from('quotations').select('id, customer_id, outlet_id').eq('id', id).maybeSingle(), 'quotation');
    if (!q) throw ApiError.notFound('Quotation');
    assertCanReadQuotation(req.ctx, q);
    res.json(await presentedQuotation(id, req.auth!));
  }),
);

const category = z.enum(['Dent', 'Scratch', 'Bumper', 'Panel', 'Paint', 'Glass', 'Other']);

const createSchema = z.object({
  vehicle_id: uuid,
  outlet_id: uuid,
  category,
  description: z.string().trim().min(5).max(2000),
  client_op_id: clientOpId,
  attachment_ids: z.array(uuid).max(10).optional(),
});

const lineItemSchema = z.object({
  label: z.string().trim().min(1).max(200),
  description: z.string().trim().max(500).nullable().optional(),
  category: z.string().trim().max(60).nullable().optional(),
  service_id: uuid.nullable().optional(),
  amount_cents: z.number().int().min(0).max(100_000_000),
  quantity: z.number().int().min(1).max(999).nullable().optional(),
});

const todayUtc = () => new Date().toISOString().slice(0, 10);

const raiseSchema = z.object({
  customer_id: z.string().trim().min(1).max(128),
  vehicle_id: uuid,
  outlet_id: uuid,
  category,
  description: z.string().trim().min(5).max(2000),
  items: z.array(lineItemSchema).min(1).max(20),
  valid_until: isoDate.refine((d) => d >= todayUtc(), { message: 'valid_until must be today or later' }),
  items_note: z.string().trim().max(1000).nullable().optional(),
  client_op_id: clientOpId,
  send_to_customer: z.boolean().default(true),
});

quotationsRouter.post(
  '/quotations',
  asyncHandler(async (req, res) => {
    if (isStaff(req.auth!.role)) {
      const body = parseBody(raiseSchema, req.body);
      const { quotation, duplicate, notification } = await raiseQuotation(req.ctx, {
        customerId: body.customer_id,
        vehicleId: body.vehicle_id,
        outletId: body.outlet_id,
        category: body.category,
        description: body.description,
        items: body.items,
        validUntil: body.valid_until,
        itemsNote: body.items_note ?? null,
        clientOpId: body.client_op_id,
        sendToCustomer: body.send_to_customer,
      });
      return res.status(duplicate ? 200 : 201).json({ quotation: await presentedQuotation(quotation.id, req.auth!), duplicate, notification });
    }
    const body = parseBody(createSchema, req.body);
    const { quotation, duplicate } = await createQuotation(req.ctx, {
      vehicleId: body.vehicle_id,
      outletId: body.outlet_id,
      category: body.category,
      description: body.description,
      clientOpId: body.client_op_id,
      attachmentIds: body.attachment_ids,
    });
    res.status(duplicate ? 200 : 201).json({ quotation: presentQuotation(quotation, [], req.auth!), duplicate });
  }),
);

const attachmentSchema = z.object({
  storage_path: z.string().min(3).max(1024),
  mime_type: z.string().regex(/^[\w.+-]+\/[\w.+-]+$/),
  size_bytes: z.number().int().min(0).max(50 * 1024 * 1024),
  sha256: z.string().length(64).nullable().optional(),
});

quotationsRouter.post(
  '/quotations/:id/attachments',
  asyncHandler(async (req, res) => {
    const id = uuid.parse(req.params.id);
    const body = parseBody(attachmentSchema, req.body);
    const q = await getQuotationOrThrow(id);
    assertOwnerOrOutletStaff(req.auth!, q);
    const db = getSupabase();
    const att = unwrap<Record<string, unknown>>(
      await db.from('attachments').insert({ entity_type: 'quotation', entity_id: id, ...body, kind: 'document', uploaded_by: req.auth!.uid }).select('*').single(),
      'attachment',
    );
    res.status(201).json({ attachment: att });
  }),
);

// ---------------------------------------------------------------------------
// Damage photos (multipart; served through the API only)
// ---------------------------------------------------------------------------

quotationsRouter.post(
  '/quotations/:id/photos',
  asyncHandler(async (req, res) => {
    const id = uuid.parse(req.params.id);
    const q = await getQuotationOrThrow(id);
    assertOwnerOrOutletStaff(req.auth!, q);
    const form = await parseMultipart(req, { fileField: 'photo', maxFileBytes: MAX_PHOTO_BYTES });
    if (!form.file) throw ApiError.validation('Missing "photo" file field', [{ path: 'photo', message: 'required' }]);
    const caption = form.fields.caption ? z.string().trim().max(200).parse(form.fields.caption) : null;
    const att = await addPhoto(req.ctx, q, { buffer: form.file.buffer, caption });
    res.status(201).json({ attachment: attachmentView(att, `/v1/quotations/${id}`) });
  }),
);

export async function streamPhoto(res: Response, quotationId: string, attachmentId: string): Promise<void> {
  const { attachment, object } = await openPhoto(quotationId, attachmentId);
  res.setHeader('Content-Type', object.contentType ?? attachment.mime_type);
  res.setHeader('Cache-Control', PHOTO_CACHE_CONTROL);
  res.setHeader('X-Content-Type-Options', 'nosniff');
  if (object.size !== null) res.setHeader('Content-Length', String(object.size));
  await new Promise<void>((resolve, reject) => {
    object.stream.on('error', reject);
    object.stream.on('end', resolve);
    object.stream.pipe(res);
  });
}

export async function sendPdf(res: Response, q: Quotation): Promise<void> {
  const pdf = await renderQuotationPdf(q);
  res.setHeader('Content-Type', 'application/pdf');
  res.setHeader('Content-Disposition', `attachment; filename="${pdfFilename(q)}"`);
  res.setHeader('Cache-Control', 'private, no-store');
  res.setHeader('Content-Length', String(pdf.length));
  res.end(pdf);
}

quotationsRouter.get(
  '/quotations/:id/photos/:attachmentId',
  asyncHandler(async (req, res) => {
    const id = uuid.parse(req.params.id);
    const attachmentId = uuid.parse(req.params.attachmentId);
    const q = await getQuotationOrThrow(id);
    assertOwnerOrOutletStaff(req.auth!, q);
    await streamPhoto(res, id, attachmentId);
  }),
);

quotationsRouter.delete(
  '/quotations/:id/photos/:attachmentId',
  requireStaff,
  asyncHandler(async (req, res) => {
    const id = uuid.parse(req.params.id);
    const attachmentId = uuid.parse(req.params.attachmentId);
    const q = await getQuotationOrThrow(id);
    assertOutlet(req.auth!, q.outlet_id);
    await deletePhoto(req.ctx, q, attachmentId);
    res.status(204).end();
  }),
);

// ---------------------------------------------------------------------------
// Share link, PDF
// ---------------------------------------------------------------------------

quotationsRouter.post(
  '/quotations/:id/share',
  requireStaff,
  asyncHandler(async (req: Request, res) => {
    const id = uuid.parse(req.params.id);
    const out = await shareQuotation(req.ctx, id);
    res.json({ public_url: out.public_url, expires_at: out.expires_at, notification: out.notification, quotation: await presentedQuotation(id, req.auth!) });
  }),
);

quotationsRouter.get(
  '/quotations/:id/pdf',
  asyncHandler(async (req, res) => {
    const id = uuid.parse(req.params.id);
    const q = await getQuotationOrThrow(id);
    assertOwnerOrOutletStaff(req.auth!, q);
    await sendPdf(res, q);
  }),
);

// ---------------------------------------------------------------------------
// Quote / decision / convert
// ---------------------------------------------------------------------------

const quoteSchema = z.object({
  amount_cents: z.number().int().min(0),
  line_items: z.array(lineItemSchema).max(50).default([]),
  valid_until: isoDate,
  items_note: z.string().trim().max(1000).nullable().optional(),
});

quotationsRouter.post(
  '/quotations/:id/quote',
  requireSupervisor,
  asyncHandler(async (req, res) => {
    const id = uuid.parse(req.params.id);
    const body = parseBody(quoteSchema, req.body);
    await quote(req.ctx, id, body);
    res.json({ quotation: await presentedQuotation(id, req.auth!) });
  }),
);

quotationsRouter.post(
  '/quotations/:id/decision',
  asyncHandler(async (req, res) => {
    const id = uuid.parse(req.params.id);
    const body = parseBody(z.object({ decision: z.enum(['accept', 'decline']), note: z.string().trim().max(500).nullable().optional() }), req.body);
    await decide(req.ctx, id, body.decision, body.note);
    res.json({ quotation: await presentedQuotation(id, req.auth!) });
  }),
);

quotationsRouter.post(
  '/quotations/:id/convert',
  requireSupervisor,
  asyncHandler(async (req, res) => {
    const id = uuid.parse(req.params.id);
    const out = await convert(req.ctx, id);
    res.status(201).json({ ...out, quotation: await presentedQuotation(id, req.auth!) });
  }),
);
