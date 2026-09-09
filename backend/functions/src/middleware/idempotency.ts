/**
 * API-003: replay protection for mutating routes.
 * Key = Idempotency-Key header or body.client_op_id, scoped by uid + method + path.
 * First response (status + JSON body) is cached in `idempotency_keys`; replays
 * return it verbatim with `Idempotent-Replayed: true`.
 */
import type { RequestHandler } from 'express';
import { getSupabase, PG_UNIQUE_VIOLATION } from '../lib/supabase.js';
import { asyncHandler } from './errors.js';

const MUTATING = new Set(['POST', 'PUT', 'PATCH', 'DELETE']);

export function extractIdempotencyKey(req: { header(n: string): string | undefined; body?: any }): string | null {
  const h = req.header('Idempotency-Key');
  if (h && h.trim()) return h.trim();
  const b = req.body?.client_op_id;
  if (typeof b === 'string' && b.trim()) return b.trim();
  return null;
}

export function scopedKey(uid: string, method: string, path: string, key: string): string {
  return `${uid}:${method.toUpperCase()}:${path}:${key}`;
}

export const idempotency: RequestHandler = asyncHandler(async (req, res, next) => {
  if (!MUTATING.has(req.method) || !req.auth) return next();
  const key = extractIdempotencyKey(req);
  if (!key) return next();
  const db = getSupabase();
  const path = req.baseUrl + req.path;
  const scoped = scopedKey(req.auth.uid, req.method, path, key);

  const existing = await db.from('idempotency_keys').select('status_code, response').eq('key', scoped).maybeSingle();
  if (existing.error) {
    req.log.warn({ err: existing.error }, 'idempotency lookup failed; continuing without cache');
    return next();
  }
  if (existing.data) {
    res.setHeader('Idempotent-Replayed', 'true');
    res.status(existing.data.status_code).json(existing.data.response);
    return;
  }

  const originalJson = res.json.bind(res);
  res.json = ((body: unknown) => {
    const status = res.statusCode;
    // Only cache successful / deterministic outcomes; 5xx and 429 should be retried.
    if (status < 500 && status !== 429) {
      void db
        .from('idempotency_keys')
        .insert({ key: scoped, profile_id: req.auth?.uid ?? null, method: req.method, path, status_code: status, response: body })
        .then(({ error }) => {
          if (error && error.code !== PG_UNIQUE_VIOLATION) req.log.warn({ err: error }, 'idempotency store failed');
        });
    }
    return originalJson(body);
  }) as typeof res.json;
  next();
});
