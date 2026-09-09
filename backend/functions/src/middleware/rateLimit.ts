/**
 * SEC-011: simple in-memory token bucket per uid (or ip when unauthenticated).
 * Good enough per instance; a shared store (Redis/Firestore) would be needed for
 * strict global limits across many function instances.
 */
import type { RequestHandler } from 'express';
import { ApiError } from './errors.js';

interface Bucket {
  tokens: number;
  updated: number;
}

export interface RateLimitOptions {
  /** bucket capacity (burst) */
  capacity: number;
  /** tokens refilled per second */
  refillPerSec: number;
  /** name for the bucket namespace */
  name: string;
}

const buckets = new Map<string, Bucket>();
const MAX_BUCKETS = 10_000;

export function rateLimit(opts: RateLimitOptions): RequestHandler {
  return (req, res, next) => {
    const principal = req.auth?.uid ?? req.ip ?? 'anon';
    const key = `${opts.name}:${principal}`;
    const now = Date.now();
    let b = buckets.get(key);
    if (!b) {
      if (buckets.size >= MAX_BUCKETS) buckets.clear();
      b = { tokens: opts.capacity, updated: now };
      buckets.set(key, b);
    }
    const elapsed = (now - b.updated) / 1000;
    b.tokens = Math.min(opts.capacity, b.tokens + elapsed * opts.refillPerSec);
    b.updated = now;
    if (b.tokens < 1) {
      const retryAfter = Math.ceil((1 - b.tokens) / opts.refillPerSec);
      res.setHeader('Retry-After', String(retryAfter));
      return next(ApiError.rateLimited());
    }
    b.tokens -= 1;
    res.setHeader('X-RateLimit-Limit', String(opts.capacity));
    res.setHeader('X-RateLimit-Remaining', String(Math.floor(b.tokens)));
    next();
  };
}

export function resetRateLimits(): void {
  buckets.clear();
}

export const authLimiter = rateLimit({ name: 'auth', capacity: 20, refillPerSec: 0.5 });
export const bookingLimiter = rateLimit({ name: 'booking', capacity: 15, refillPerSec: 0.25 });
export const paymentLimiter = rateLimit({ name: 'payment', capacity: 15, refillPerSec: 0.25 });
export const webhookLimiter = rateLimit({ name: 'webhook', capacity: 120, refillPerSec: 10 });
