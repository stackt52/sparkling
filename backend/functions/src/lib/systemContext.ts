import type { RequestContext } from '../types.js';
import { logger } from '../middleware/correlation.js';

export const SYSTEM_UID = 'system';

/** Request context for server-initiated work (webhooks, public quote decisions): acts as an outlet-unscoped admin. */
export function systemContext(correlationId = 'system', log = logger): RequestContext {
  return {
    auth: { uid: SYSTEM_UID, email: null, role: 'admin', outletIds: [], profile: null, tokenClaims: {} },
    correlationId,
    log: log.child({ actor: SYSTEM_UID, correlation_id: correlationId }),
  };
}
