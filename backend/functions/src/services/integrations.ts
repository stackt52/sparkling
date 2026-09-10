/**
 * ADM-040: integration status cards for the admin settings page. Reports
 * liveness/config only — never secrets (INT-006).
 */
import { config, FIREBASE_PROJECT_ID } from '../config.js';
import { getSupabase } from '../lib/supabase.js';
import { getFlags } from './flags.js';
import { getPaymentProvider } from './payments.js';

export type IntegrationKey = 'supabase' | 'firebase' | 'payments' | 'whatsapp';
export type IntegrationState = 'connected' | 'sandbox' | 'disabled' | 'error';

export interface IntegrationCard {
  key: IntegrationKey;
  name: string;
  status: IntegrationState;
  detail: string;
  icon: string;
  [extra: string]: unknown;
}

export async function integrationStatus(): Promise<IntegrationCard[]> {
  const db = getSupabase();
  const started = Date.now();
  let ok = true;
  let error: string | null = null;
  try {
    const res = await db.from('feature_flags').select('key').limit(1);
    if (res.error) {
      ok = false;
      error = res.error.message;
    }
  } catch (err) {
    ok = false;
    error = (err as Error).message;
  }
  const latency_ms = Date.now() - started;
  const flags = await getFlags(true);
  const provider = getPaymentProvider();
  const sandbox = provider.name === 'sandbox';
  const whatsappEnabled = flags.whatsapp_enabled === true;
  const whatsappProvider = config.whatsappProvider;
  const twilioConfigured = config.twilioConfigured;
  const messagingService = maskSid(config.twilioMessagingServiceSid);
  const statusCallback = config.publicApiBaseUrl.length > 0;
  const projectId = process.env.GCLOUD_PROJECT || process.env.GOOGLE_CLOUD_PROJECT || FIREBASE_PROJECT_ID;

  return [
    {
      key: 'supabase',
      name: 'Supabase Postgres + Realtime',
      status: ok ? 'connected' : 'error',
      detail: ok ? `Service-role client reachable · ${latency_ms} ms` : `Query failed: ${error ?? 'unknown error'}`,
      icon: 'database',
      ok,
      latency_ms,
      url: config.supabaseUrl,
    },
    {
      key: 'firebase',
      name: `Firebase Auth · ${projectId}`,
      status: 'connected',
      detail: config.isEmulator ? 'Emulator · Firebase ID tokens verified locally' : 'Firebase ID tokens verified via Admin SDK; custom claims role + outlet_ids',
      icon: 'verified_user',
      project_id: projectId,
      emulator: config.isEmulator,
    },
    {
      key: 'payments',
      name: 'Payments provider',
      status: sandbox ? 'sandbox' : 'connected',
      detail: sandbox ? `Sandbox adapter · webhook HMAC verified · no real charges${flags.payments_sandbox ? ' · sandbox-confirm enabled' : ''}` : `${provider.name} · webhook HMAC verified`,
      icon: 'payments',
      provider: provider.name,
      sandbox,
      sandbox_confirm_enabled: flags.payments_sandbox === true,
    },
    {
      key: 'whatsapp',
      name: 'WhatsApp Business (Twilio)',
      status: whatsappEnabled ? (whatsappProvider === 'twilio' && twilioConfigured ? 'connected' : 'sandbox') : 'disabled',
      detail: whatsappEnabled
        ? whatsappProvider === 'twilio' && twilioConfigured
          ? `Twilio Messaging Service ${messagingService} · Content templates${statusCallback ? ' · status callback on' : ' · no PUBLIC_API_BASE_URL (no delivery receipts)'}`
          : whatsappProvider === 'twilio'
            ? 'Flag on but TWILIO_ACCOUNT_SID / TWILIO_AUTH_TOKEN not set — sends fail'
            : 'Flag on · sandbox adapter logs only'
        : `Flag whatsapp_enabled off · notifications suppressed (provider ${whatsappProvider}${twilioConfigured ? ', Twilio configured' : ''})`,
      icon: 'chat',
      enabled: whatsappEnabled,
      provider: whatsappProvider,
      configured: twilioConfigured,
      messaging_service: messagingService,
      status_callback: statusCallback,
      /** @deprecated legacy Meta token flag */
    },
  ];
}

/** `MG4d8b…1660` — enough to recognise the SID in the Twilio console without exposing it. */
export function maskSid(sid: string | null | undefined): string | null {
  if (!sid) return null;
  if (sid.length <= 10) return `${sid.slice(0, 2)}…`;
  return `${sid.slice(0, 6)}…${sid.slice(-4)}`;
}
