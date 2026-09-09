/** In-app notification inbox (NOT-003). */
import { Router } from 'express';
import { getSupabase, unwrap } from '../lib/supabase.js';
import { decodeCursor, pageResult } from '../lib/refs.js';
import { pagination, parseQuery, uuid } from '../lib/validate.js';
import { requireProfile } from '../middleware/auth.js';
import { ApiError, asyncHandler } from '../middleware/errors.js';

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
