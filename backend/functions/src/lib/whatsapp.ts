/**
 * INT-002: WhatsApp Business provider adapter. The sandbox adapter only logs;
 * a real provider (Meta Cloud API / Twilio) plugs in behind the same interface.
 */
import { config } from '../config.js';
import { logger } from '../middleware/correlation.js';

export interface WhatsAppAdapter {
  readonly name: string;
  send(to: string, body: string, meta?: Record<string, unknown>): Promise<{ provider_ref: string | null; status: 'sent' | 'failed' | 'suppressed'; error?: string }>;
}

export class SandboxWhatsAppAdapter implements WhatsAppAdapter {
  readonly name = 'sandbox';
  async send(to: string, body: string, meta?: Record<string, unknown>) {
    logger.info({ to: maskPhone(to), body_len: body.length, ...meta }, 'whatsapp sandbox send (no-op)');
    return { provider_ref: `wa_sbx_${Date.now()}`, status: 'sent' as const };
  }
}

export class NoopWhatsAppAdapter implements WhatsAppAdapter {
  readonly name = 'noop';
  async send() {
    return { provider_ref: null, status: 'suppressed' as const };
  }
}

let adapter: WhatsAppAdapter | null = null;

export function getWhatsAppAdapter(enabled: boolean): WhatsAppAdapter {
  if (adapter) return adapter;
  if (!enabled) return new NoopWhatsAppAdapter();
  // A real adapter would use config.whatsappToken; until then sandbox logging.
  void config.whatsappToken;
  return new SandboxWhatsAppAdapter();
}

export function setWhatsAppAdapterForTests(a: WhatsAppAdapter | null): void {
  adapter = a;
}

export function maskPhone(phone: string): string {
  return phone.replace(/\d(?=\d{3})/g, '*');
}
