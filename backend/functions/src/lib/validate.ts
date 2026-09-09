/** API-005: zod validation helpers shared by all routes. */
import { z, type ZodTypeAny } from 'zod';
import { ApiError } from '../middleware/errors.js';

export function parseBody<T extends ZodTypeAny>(schema: T, body: unknown): z.infer<T> {
  const r = schema.safeParse(body ?? {});
  if (!r.success) {
    throw ApiError.validation(
      'Request validation failed',
      r.error.issues.map((i) => ({ path: i.path.join('.'), message: i.message, code: i.code })),
    );
  }
  return r.data;
}

export function parseQuery<T extends ZodTypeAny>(schema: T, query: unknown): z.infer<T> {
  return parseBody(schema, query);
}

export const uuid = z.string().uuid();
export const isoDateTime = z.string().datetime({ offset: true });
export const isoDate = z.string().regex(/^\d{4}-\d{2}-\d{2}$/, 'Expected YYYY-MM-DD');
export const clientOpId = z.string().min(6).max(128);
export const pagination = z.object({
  limit: z.coerce.number().int().min(1).max(100).default(25),
  cursor: z.string().optional(),
  sort: z.string().optional(),
});
export const nonEmpty = z.string().trim().min(1);
