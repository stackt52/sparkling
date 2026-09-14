/**
 * Public quote page API (unauthenticated, token-scoped). Mounted at
 * `/v1/public/quotations` BEFORE the auth middleware (like the payment
 * webhook). Every route is rate-limited per IP + token; responses never carry
 * customer PII beyond a first name. CORS: the page lives on the admin app
 * origin, so GET/POST are allowed from any origin (app-level `cors`).
 */
import cors from 'cors';
import { json, Router } from 'express';
import { z } from 'zod';
import { uuid } from '../lib/validate.js';
import { ApiError, asyncHandler } from '../middleware/errors.js';
import { publicQuoteLimiter } from '../middleware/rateLimit.js';
import { decidePublic, getQuotationByPublicToken, publicQuotationView } from '../services/quotations.js';
import { sendPdf, streamPhoto } from './quotations.js';

export const publicQuotationsRouter = Router();

publicQuotationsRouter.use(cors({ origin: true, credentials: false, methods: ['GET', 'POST', 'OPTIONS'], allowedHeaders: ['Content-Type', 'X-Correlation-Id', 'X-Client-App', 'X-Client-Version'], maxAge: 600 }));
publicQuotationsRouter.use(json({ limit: '64kb' }));

const tokenParam = z.string().trim().min(8).max(128);

publicQuotationsRouter.get(
  '/:token',
  publicQuoteLimiter,
  asyncHandler(async (req, res) => {
    const token = tokenParam.parse(req.params.token);
    const q = await getQuotationByPublicToken(token);
    res.setHeader('Cache-Control', 'private, no-store');
    res.json(await publicQuotationView(q));
  }),
);

publicQuotationsRouter.get(
  '/:token/photos/:attachmentId',
  publicQuoteLimiter,
  asyncHandler(async (req, res) => {
    const token = tokenParam.parse(req.params.token);
    const attachmentId = uuid.parse(req.params.attachmentId);
    const q = await getQuotationByPublicToken(token);
    await streamPhoto(res, q.id, attachmentId);
  }),
);

publicQuotationsRouter.get(
  '/:token/pdf',
  publicQuoteLimiter,
  asyncHandler(async (req, res) => {
    const token = tokenParam.parse(req.params.token);
    const q = await getQuotationByPublicToken(token);
    await sendPdf(res, q);
  }),
);

const decisionSchema = z.object({
  decision: z.enum(['accept', 'decline']),
  note: z.string().trim().max(500).nullable().optional(),
  accepted_by_name: z.string().trim().min(1).max(120).nullable().optional(),
});

publicQuotationsRouter.post(
  '/:token/decision',
  publicQuoteLimiter,
  asyncHandler(async (req, res) => {
    const token = tokenParam.parse(req.params.token);
    const r = decisionSchema.safeParse(req.body ?? {});
    if (!r.success) throw ApiError.validation('Request validation failed', r.error.issues.map((i) => ({ path: i.path.join('.'), message: i.message, code: i.code })));
    const updated = await decidePublic(token, r.data, { ip: req.ip, userAgent: req.header('User-Agent') ?? undefined, correlationId: req.correlationId, log: req.log });
    res.setHeader('Cache-Control', 'private, no-store');
    res.json(await publicQuotationView(updated));
  }),
);

/** Anything else under /public/quotations is a 404 here (never falls through to the auth middleware). */
publicQuotationsRouter.use((_req, _res, next) => next(ApiError.notFound('Route')));
