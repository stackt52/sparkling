/**
 * Runtime configuration. Params/secrets are declared with firebase-functions
 * `params` so the CLI prompts for / stores them; values are read lazily so the
 * module can be imported in tests and the emulator without Secret Manager.
 */
import { defineSecret, defineString } from 'firebase-functions/params';

export const REGION = 'europe-west1';
export const FIREBASE_PROJECT_ID = 'sparkling-4e89d';
export const DEFAULT_SUPABASE_URL = 'https://uicqczgpiqkczwyssdft.supabase.co';

export const supabaseUrlParam = defineString('SUPABASE_URL', { default: DEFAULT_SUPABASE_URL });
export const apiVersionParam = defineString('API_VERSION', { default: '1.0.0' });

export const supabaseServiceRoleKey = defineSecret('SUPABASE_SERVICE_ROLE_KEY');
export const paymentWebhookSecret = defineSecret('PAYMENT_WEBHOOK_SECRET');
export const whatsappToken = defineSecret('WHATSAPP_TOKEN');

function readParam(name: string, fallback: string, param?: { value(): string }): string {
  const env = process.env[name];
  if (env && env.length > 0) return env;
  try {
    const v = param?.value();
    if (v && v.length > 0) return v;
  } catch {
    /* outside function runtime (tests) */
  }
  return fallback;
}

export const config = {
  get supabaseUrl(): string {
    return readParam('SUPABASE_URL', DEFAULT_SUPABASE_URL, supabaseUrlParam);
  },
  get supabaseServiceRoleKey(): string {
    return readParam('SUPABASE_SERVICE_ROLE_KEY', '', supabaseServiceRoleKey);
  },
  get paymentWebhookSecret(): string {
    return readParam('PAYMENT_WEBHOOK_SECRET', 'sandbox-dev-secret', paymentWebhookSecret);
  },
  get whatsappToken(): string {
    return readParam('WHATSAPP_TOKEN', '', whatsappToken);
  },
  get apiVersion(): string {
    return readParam('API_VERSION', '1.0.0', apiVersionParam);
  },
  get isEmulator(): boolean {
    return process.env.FUNCTIONS_EMULATOR === 'true';
  },
  get nodeEnv(): string {
    return process.env.NODE_ENV ?? 'production';
  },
};
