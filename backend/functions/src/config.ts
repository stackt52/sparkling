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

// INT-002: WhatsApp via Twilio (Messaging Service + approved Content templates).
export const twilioAccountSid = defineSecret('TWILIO_ACCOUNT_SID');
export const twilioAuthToken = defineSecret('TWILIO_AUTH_TOKEN');
export const DEFAULT_TWILIO_MESSAGING_SERVICE_SID = 'MG4d8b6037dc3b183f43b2622307271660';
export const twilioMessagingServiceSidParam = defineString('TWILIO_MESSAGING_SERVICE_SID', { default: DEFAULT_TWILIO_MESSAGING_SERVICE_SID });
/** Optional `whatsapp:+…` sender; only used when no Messaging Service SID is configured. */
export const twilioWhatsAppFromParam = defineString('TWILIO_WHATSAPP_FROM', { default: '' });
/** Public base URL of this API (e.g. https://europe-west1-<project>.cloudfunctions.net/api); empty → no status callback. */
export const publicApiBaseUrlParam = defineString('PUBLIC_API_BASE_URL', { default: '' });
/** `twilio` | `sandbox`; defaults to twilio when the Twilio secrets are set, else sandbox. */
export const whatsappProviderParam = defineString('WHATSAPP_PROVIDER', { default: '' });

/** True while the Firebase CLI loads the code to discover functions (no runtime values exist yet). */
const isDeployDiscovery = (): boolean => process.env.FUNCTIONS_CONTROL_API === 'true';

function readParam(name: string, fallback: string, param?: { value(): string }): string {
  const env = process.env[name];
  if (env && env.length > 0) return env;
  if (isDeployDiscovery()) return fallback;
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
  get twilioAccountSid(): string {
    return readParam('TWILIO_ACCOUNT_SID', '', twilioAccountSid);
  },
  get twilioAuthToken(): string {
    return readParam('TWILIO_AUTH_TOKEN', '', twilioAuthToken);
  },
  get twilioMessagingServiceSid(): string {
    return readParam('TWILIO_MESSAGING_SERVICE_SID', DEFAULT_TWILIO_MESSAGING_SERVICE_SID, twilioMessagingServiceSidParam);
  },
  get twilioWhatsAppFrom(): string {
    return readParam('TWILIO_WHATSAPP_FROM', '', twilioWhatsAppFromParam);
  },
  get publicApiBaseUrl(): string {
    return readParam('PUBLIC_API_BASE_URL', '', publicApiBaseUrlParam).replace(/\/+$/, '');
  },
  get twilioConfigured(): boolean {
    return this.twilioAccountSid.length > 0 && this.twilioAuthToken.length > 0;
  },
  get whatsappProvider(): 'twilio' | 'sandbox' {
    const raw = readParam('WHATSAPP_PROVIDER', '', whatsappProviderParam).trim().toLowerCase();
    if (raw === 'twilio' || raw === 'sandbox') return raw;
    return this.twilioConfigured ? 'twilio' : 'sandbox';
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
