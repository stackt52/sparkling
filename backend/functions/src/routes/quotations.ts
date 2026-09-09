/** Quotations (CUS-030..034). */
import { Router } from 'express';
import { z } from 'zod';
import { getSupabase, unwrap } from '../lib/supabase.js';
import { decodeCursor, pageResult } from '../lib/refs.js';
import { clientOpId, isoDate, pagination, parseBody, parseQuery, uuid } from '../lib/validate.js';
import { assertOwnerOrOutletStaff, canSeeOutlet, isStaff, requireProfile, requireSupervisor } from '../middleware/auth.js';
import { ApiError, asyncHandler } from '../middleware/errors.js';
import { assertCanReadQuotation, convert, createQuotation, decide, getQuotationOrThrow, quote } from '../services/quotations.js';
import type { Quotation } from '../types.js';

export const quotationsRouter = Router();
quotationsRouter.use('/quotations', requireProfile);

const EXPAND = '*, outlet:outlets(id, name), vehicle:vehicles(id, registration_no, make, model), assessor:profiles!quotations_assessor_id_fkey(id, full_name)';

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
    const rows = unwrap<Quotation[]>(await query, 'quotations');
    res.json(pageResult(rows, q.limit, offset));
  }),
);

quotationsRouter.get(
  '/quotations/:id',
  asyncHandler(async (req, res) => {
    const id = uuid.parse(req.params.id);
    const db = getSupabase();
    const q = unwrap<(Quotation & Record<string, unknown>) | null>(await db.from('quotations').select(EXPAND).eq('id', id).maybeSingle(), 'quotation');
    if (!q) throw ApiError.notFound('Quotation');
    assertCanReadQuotation(req.ctx, q);
    const attachments = unwrap<unknown[]>(await db.from('attachments').select('*').eq('entity_type', 'quotation').eq('entity_id', id).order('created_at'), 'attachments');
    const workOrder = unwrap<{ id: string; ref: string; status: string } | null>(await db.from('work_orders').select('id, ref, status').eq('quotation_id', id).maybeSingle(), 'work order');
    res.json({ ...q, attachments, work_order: workOrder });
  }),
);

const createSchema = z.object({
  vehicle_id: uuid,
  outlet_id: uuid,
  category: z.enum(['Dent', 'Scratch', 'Bumper', 'Panel', 'Paint', 'Glass', 'Other']),
  description: z.string().trim().min(5).max(2000),
  client_op_id: clientOpId,
  attachment_ids: z.array(uuid).max(10).optional(),
});

quotationsRouter.post(
  '/quotations',
  asyncHandler(async (req, res) => {
    const body = parseBody(createSchema, req.body);
    const { quotation, duplicate } = await createQuotation(req.ctx, {
      vehicleId: body.vehicle_id,
      outletId: body.outlet_id,
      category: body.category,
      description: body.description,
      clientOpId: body.client_op_id,
      attachmentIds: body.attachment_ids,
    });
    res.status(duplicate ? 200 : 201).json({ quotation, duplicate });
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
      await db.from('attachments').insert({ entity_type: 'quotation', entity_id: id, ...body, uploaded_by: req.auth!.uid }).select('*').single(),
      'attachment',
    );
    res.status(201).json({ attachment: att });
  }),
);

const quoteSchema = z.object({
  amount_cents: z.number().int().min(0),
  line_items: z.array(z.object({ label: z.string().trim().min(1).max(200), amount_cents: z.number().int().min(0) })).max(50).default([]),
  valid_until: isoDate,
});

quotationsRouter.post(
  '/quotations/:id/quote',
  requireSupervisor,
  asyncHandler(async (req, res) => {
    const id = uuid.parse(req.params.id);
    const body = parseBody(quoteSchema, req.body);
    res.json({ quotation: await quote(req.ctx, id, body) });
  }),
);

quotationsRouter.post(
  '/quotations/:id/decision',
  asyncHandler(async (req, res) => {
    const id = uuid.parse(req.params.id);
    const body = parseBody(z.object({ decision: z.enum(['accept', 'decline']), note: z.string().trim().max(500).nullable().optional() }), req.body);
    res.json({ quotation: await decide(req.ctx, id, body.decision, body.note) });
  }),
);

quotationsRouter.post(
  '/quotations/:id/convert',
  requireSupervisor,
  asyncHandler(async (req, res) => {
    const id = uuid.parse(req.params.id);
    res.status(201).json(await convert(req.ctx, id));
  }),
);
