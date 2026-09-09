/**
 * Supabase service-role client (server only — never shipped to clients, INT-006).
 * `setSupabaseClient` lets tests inject an in-memory stub.
 */
import { createClient, type SupabaseClient } from '@supabase/supabase-js';
import { config } from '../config.js';

// The API is intentionally untyped against generated DB types: the schema is
// authoritative in SQL and we read/write rows as plain snake_case objects.
export type Db = SupabaseClient<any, any, any>;

let client: Db | null = null;

export function getSupabase(): Db {
  if (client) return client;
  const key = config.supabaseServiceRoleKey;
  if (!key) {
    throw new Error('SUPABASE_SERVICE_ROLE_KEY is not configured');
  }
  client = createClient(config.supabaseUrl, key, {
    auth: { persistSession: false, autoRefreshToken: false },
    global: { headers: { 'x-client-info': 'sparkling-functions' } },
  });
  return client;
}

export function setSupabaseClient(c: Db | null): void {
  client = c;
}

/** Throws a wrapped error for a PostgREST error result. */
export interface DbError {
  code?: string;
  message: string;
  details?: string | null;
  hint?: string | null;
}

export class DatabaseError extends Error {
  code?: string;
  details?: string | null;
  constructor(err: DbError, context?: string) {
    super(context ? `${context}: ${err.message}` : err.message);
    this.name = 'DatabaseError';
    this.code = err.code;
    this.details = err.details;
  }
}

/** Unwrap `{data,error}` responses, throwing DatabaseError on error. */
export function unwrap<T>(res: { data: unknown; error: DbError | null }, context?: string): T {
  if (res.error) throw new DatabaseError(res.error, context);
  return res.data as T;
}

export const PG_UNIQUE_VIOLATION = '23505';
export const PG_CHECK_VIOLATION = '23514';
export const PG_FK_VIOLATION = '23503';
