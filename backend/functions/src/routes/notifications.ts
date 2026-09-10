/** In-app notification inbox (NOT-003) + Twilio delivery-status callback (INT-002). */
import { Router, urlencoded } from 'express';
import { config } from '../config.js';
import { getSupabase, unwrap } from '../lib/supabase.js';
import { decodeCursor, pageResult } from '../lib/refs.js';
import { validateTwilioSignature } from '../lib/twilioSignature.js';
import { pagination, parseQuery, uuid } from '../lib/validate.js';
import { twilioStatusCallbackUrl } from '../lib/whatsapp.js';
import { requireProfile } from '../middleware/auth.js';
import { ApiError, asyncHandler } from '../middleware/errors.js';
import { webhookLimiter } from '../middleware/rateLimit.js';
import { applyTwilioStatus } from '../services/notifications.js';

/**
 * Unauthenticated Twilio status-callback router (mounted before auth, like the
 * payments webhook). Twilio posts `application/x-www-form-urlencoded` and signs
 * the exact callback URL + params with the account auth token.
 */
export const twilioStatusRouter = Router();

/** URLs Twilio may have signed: the configured public callback URL first, then what the proxy saw. */
export function twilioCandidateUrls(req: import('express').Request): string[] {
  const urls: string[] = [];
  const query = req.originalUrl.includes('?') ? req.originalUrl.slice(req.originalUrl.indexOf('?')) : '';
  const configured = twilioStatusCallbackUrl();
  if (configured) urls.push(`${configured}${query}`);
  const host = req.get('host');
  if (host) {
    for (const proto of [req.protocol, 'https', 'http']) {
      const u = `${proto}://${host}${req.originalUrl}`;
      if (!urls.includes(u)) urls.push(u);
    }
  }
  return urls;
}

twilioStatusRouter.post(
  '/notifications/twilio/status',
  webhookLimiter,
  urlencoded({ extended: false, limit: '64kb' }),
  asyncHandler(async (req, res) => {
    const token = config.twilioAuthToken;
    if (!token) {
      req.log.warn('twilio status callback received but TWILIO_AUTH_TOKEN is not configured');
      throw ApiError.forbidden('Twilio callbacks are not configured');
    }
    const params = (req.body ?? {}) as Record<string, string | string[] | undefined>;
    if (!validateTwilioSignature(token, req.header('X-Twilio-Signature'), twilioCandidateUrls(req), params)) {
      req.log.warn({ sid: params.MessageSid ?? null }, 'twilio signature invalid');
      throw ApiError.forbidden('Invalid Twilio signature');
    }
    const outcome = await applyTwilioStatus(params);
    res.json(outcome);
  }),
);

export const notificationsRouter = Router();
notificationsRouter.use('/notifications', requireProfile);

notificationsRouter.get(
  '/notifications',
  asyncHandler(async (req, res) => {
    const q = parseQuery(pagination, req.query);
    const offset = decodeCursor(q.cursor);
    const db = getSupabase();
    const rows = unwrap<unknown[]>(
      await db
        .from('notifications')
        .select('id, channel, template_key, title, body, payload, status, read_at, sent_at, created_at')
        .eq('recipient_id', req.auth!.uid)
        .neq('status', 'suppressed')
        .order('created_at', { ascending: false })
        .range(offset, offset + q.limit),
      'notifications',
    );
    res.json(pageResult(rows, q.limit, offset));
  }),
);

notificationsRouter.post(
  '/notifications/:id/read',
  asyncHandler(async (req, res) => {
    const id = uuid.parse(req.params.id);
    const db = getSupabase();
    const row = unwrap<{ id: string; read_at: string | null } | null>(
      await db.from('notifications').update({ read_at: new Date().toISOString() }).eq('id', id).eq('recipient_id', req.auth!.uid).select('id, read_at').maybeSingle(),
      'mark read',
    );
    if (!row) throw ApiError.notFound('Notification');
    res.json({ notification: row });
  }),
);
