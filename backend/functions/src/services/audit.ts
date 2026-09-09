/**
 * ADM-003 / SEC-006: append-only audit trail. Failures are logged, never thrown,
 * so an audit outage cannot block business writes (the row is still attempted).
 */
import { getSupabase } from '../lib/supabase.js';
import type { RequestContext } from '../types.js';

export interface AuditInput {
  action: string;
  entity_type: string;
  entity_id?: string | null;
  outlet_id?: string | null;
  before?: unknown;
  after?: unknown;
  outcome?: string;
}

export async function audit(ctx: RequestContext, input: AuditInput): Promise<void> {
  const db = getSupabase();
  const { error } = await db.from('audit_events').insert({
    actor_id: ctx.auth.uid,
    actor_role: ctx.auth.role,
    action: input.action,
    entity_type: input.entity_type,
    entity_id: input.entity_id ?? null,
    outlet_id: input.outlet_id ?? null,
    before: input.before ?? null,
    after: input.after ?? null,
    correlation_id: ctx.correlationId,
    ip: ctx.ip && /^[0-9a-f.:]+$/i.test(ctx.ip) ? ctx.ip : null,
    user_agent: ctx.userAgent?.slice(0, 500) ?? null,
    outcome: input.outcome ?? 'ok',
  });
  if (error) ctx.log.error({ err: error, action: input.action }, 'audit write failed');
}
