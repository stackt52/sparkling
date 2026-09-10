/**
 * API-004 error envelope. Never leaks stack traces.
 * { error: { code, message, details, correlation_id } }
 */
import type { ErrorRequestHandler, RequestHandler } from 'express';
import { ZodError } from 'zod';
import { DatabaseError, PG_CHECK_VIOLATION, PG_FK_VIOLATION, PG_UNIQUE_VIOLATION } from '../lib/supabase.js';

export type ErrorCode =
  | 'unauthenticated'
  | 'forbidden'
  | 'not_found'
  | 'validation_error'
  | 'conflict'
  | 'invalid_transition'
  | 'invalid_otp'
  | 'rate_limited'
  | 'internal';

const STATUS: Record<ErrorCode, number> = {
  unauthenticated: 401,
  forbidden: 403,
  not_found: 404,
  validation_error: 400,
  conflict: 409,
  invalid_transition: 409,
  invalid_otp: 409,
  rate_limited: 429,
  internal: 500,
};

export class ApiError extends Error {
  readonly code: ErrorCode;
  readonly status: number;
  readonly details?: unknown;
  constructor(code: ErrorCode, message: string, details?: unknown) {
    super(message);
    this.name = 'ApiError';
    this.code = code;
    this.status = STATUS[code];
    this.details = details;
  }
  static unauthenticated(msg = 'Authentication required') {
    return new ApiError('unauthenticated', msg);
  }
  static forbidden(msg = 'You do not have access to this resource') {
    return new ApiError('forbidden', msg);
  }
  static notFound(what = 'Resource') {
    return new ApiError('not_found', `${what} not found`);
  }
  static validation(msg: string, details?: unknown) {
    return new ApiError('validation_error', msg, details);
  }
  static conflict(msg: string, details?: unknown) {
    return new ApiError('conflict', msg, details);
  }
  static invalidTransition(from: string, to: string, entity = 'entity') {
    return new ApiError('invalid_transition', `Cannot move ${entity} from '${from}' to '${to}'`, { from, to });
  }
  static invalidOtp(msg = 'Incorrect OTP', details?: unknown) {
    return new ApiError('invalid_otp', msg, details);
  }
  static rateLimited(msg = 'Too many requests') {
    return new ApiError('rate_limited', msg);
  }
  static internal(msg = 'Internal error') {
    return new ApiError('internal', msg);
  }
}

export function toApiError(err: unknown): ApiError {
  if (err instanceof ApiError) return err;
  if (err instanceof ZodError) {
    return ApiError.validation(
      'Request validation failed',
      err.issues.map((i) => ({ path: i.path.join('.'), message: i.message, code: i.code })),
    );
  }
  if (err instanceof DatabaseError) {
    if (err.code === PG_UNIQUE_VIOLATION) return ApiError.conflict('Duplicate record', { constraint: err.details ?? undefined });
    if (err.code === PG_CHECK_VIOLATION) return ApiError.conflict('Constraint violated', { constraint: err.details ?? undefined });
    if (err.code === PG_FK_VIOLATION) return ApiError.validation('Referenced record does not exist', { constraint: err.details ?? undefined });
    if (err.code === 'PGRST116') return ApiError.notFound();
    if (err.code === '22P02') return ApiError.validation('Invalid identifier format');
  }
  const anyErr = err as { type?: string; status?: number };
  if (anyErr?.type === 'entity.parse.failed') return ApiError.validation('Malformed JSON body');
  if (anyErr?.type === 'entity.too.large') return ApiError.validation('Request body too large');
  return ApiError.internal();
}

export const errorHandler: ErrorRequestHandler = (err, req, res, _next) => {
  const apiErr = toApiError(err);
  const correlationId = req.correlationId ?? res.getHeader('X-Correlation-Id')?.toString() ?? '';
  if (apiErr.status >= 500) {
    req.log?.error({ err, correlation_id: correlationId }, 'unhandled error');
  } else {
    req.log?.warn({ code: apiErr.code, message: apiErr.message, correlation_id: correlationId }, 'request failed');
  }
  if (res.headersSent) return;
  res.status(apiErr.status).json({
    error: {
      code: apiErr.code,
      message: apiErr.message,
      details: apiErr.details ?? [],
      correlation_id: correlationId,
    },
  });
};

export const notFoundHandler: RequestHandler = (_req, _res, next) => {
  next(ApiError.notFound('Route'));
};

/** Wrap async handlers so rejections reach the error middleware (Express 4). */
export function asyncHandler(
  fn: (req: import('express').Request, res: import('express').Response, next: import('express').NextFunction) => Promise<unknown>,
): RequestHandler {
  return (req, res, next) => {
    fn(req, res, next).catch(next);
  };
}
