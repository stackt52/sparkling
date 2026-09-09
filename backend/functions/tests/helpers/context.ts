import pino from 'pino';
import type { AuthContext, Profile, RequestContext, UserRole } from '../../src/types.js';

export function makeProfile(overrides: Partial<Profile> = {}): Profile {
  return {
    id: 'uid_test',
    role: 'customer',
    full_name: 'Test User',
    email: 'test@example.com',
    phone: '+27 82 000 0000',
    avatar_url: null,
    is_active: true,
    marketing_opt_in: false,
    whatsapp_opt_in: true,
    push_opt_in: true,
    locale: 'en-ZA',
    reduced_motion: false,
    haptics: true,
    last_seen_at: null,
    deactivated_at: null,
    created_at: new Date().toISOString(),
    updated_at: new Date().toISOString(),
    ...overrides,
  };
}

export function makeCtx(role: UserRole = 'customer', uid = 'uid_test', outletIds: string[] = []): RequestContext {
  const profile = makeProfile({ id: uid, role });
  const auth: AuthContext = { uid, email: profile.email, role, outletIds, profile, tokenClaims: {} };
  return { auth, correlationId: 'corr-test', log: pino({ level: 'silent' }), ip: '127.0.0.1', userAgent: 'vitest' };
}
