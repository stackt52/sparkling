/**
 * INT-002: WhatsApp Business provider adapters.
 *
 * - `TwilioWhatsAppAdapter` — Twilio Messaging Service + approved Content
 *   templates (replicates the legacy sparkling-admin flow). Talks to the REST
 *   API with `fetch` (Basic auth, form-encoded); no SDK dependency.
 * - `SandboxWhatsAppAdapter` — logs only (local/dev).
 * - `NoopWhatsAppAdapter` — used when the `whatsapp_enabled` flag is off.
 *
 * `getWhatsAppAdapter()` picks by `config.whatsappProvider`.
 */
import { config } from '../config.js';
import { logger } from '../middleware/correlation.js';

export type WhatsAppSendStatus = 'sent' | 'failed' | 'suppressed';

export interface WhatsAppSendInput {
  /** Destination in any common SA/international format; normalised to E.164. */
  to: string;
  /** Rendered free-form text (used as `Body` when no template SID is given). */
  body: string;
  /** Twilio Content SID (`HX…`) of an approved WhatsApp template. */
  contentSid?: string | null;
  /** Positional template variables, e.g. `{ "1": "Thabo", "2": "QT-2026-1001" }`. */
  contentVariables?: Record<string, string> | null;
  /** Absolute URL Twilio posts delivery receipts to. */
  statusCallback?: string | null;
  /** Free-form context for logs (never sent to the provider). */
  meta?: Record<string, unknown>;
}

export interface WhatsAppSendResult {
  provider_ref: string | null;
  status: WhatsAppSendStatus;
  /** Raw provider status at accept time (`queued`, `accepted`, …). */
  provider_status?: string | null;
  error?: string;
  provider_error_code?: string | null;
  /** Non-fatal note, e.g. free-form body sent outside a template. */
  warning?: string;
}

export interface WhatsAppAdapter {
  readonly name: string;
  send(input: WhatsAppSendInput): Promise<WhatsAppSendResult>;
}

// ---------------------------------------------------------------------------
// Phone numbers
// ---------------------------------------------------------------------------

export const E164 = /^\+[1-9]\d{6,14}$/;

/**
 * Normalises a phone number to E.164. South African local numbers
 * (`0xx xxx xxxx`) become `+27xx…`; spaces, dashes and brackets are stripped;
 * a `whatsapp:` prefix or `00` international prefix is accepted. Returns null
 * when the result is not a valid E.164 number.
 */
export function normalisePhone(raw: string | null | undefined): string | null {
  if (!raw) return null;
  let s = String(raw).trim().replace(/^whatsapp:/i, '').replace(/[\s\-().]/g, '');
  if (s.startsWith('00')) s = `+${s.slice(2)}`;
  if (/^0\d{9}$/.test(s)) s = `+27${s.slice(1)}`;
  else if (/^27\d{9}$/.test(s)) s = `+${s}`;
  return E164.test(s) ? s : null;
}

export function isE164(value: string | null | undefined): boolean {
  return !!value && E164.test(value.trim());
}

export function maskPhone(phone: string): string {
  return phone.replace(/\d(?=\d{3})/g, '*');
}

// ---------------------------------------------------------------------------
// Twilio
// ---------------------------------------------------------------------------

/** Friendly messages for the Twilio error codes we expect to see. */
export const TWILIO_ERROR_MESSAGES: Record<string, string> = {
  '20003': 'Twilio authentication failed (check TWILIO_ACCOUNT_SID / TWILIO_AUTH_TOKEN)',
  '21211': 'Invalid destination phone number',
  '21408': 'Messaging to this region is not enabled on the Twilio account',
  '21606': 'The WhatsApp sender is not enabled for this channel',
  '21608': 'Destination is not a verified number on this trial Twilio account',
  '21610': 'Recipient has unsubscribed (STOP) from this sender',
  '21614': 'Destination is not a valid mobile number',
  '63003': 'Recipient has not opted in to WhatsApp messages from this sender',
  '63007': 'WhatsApp sender is not registered on this Messaging Service',
  '63013': 'Message rejected by WhatsApp channel policy',
  '63015': 'Recipient could not be reached on WhatsApp',
  '63016': 'Outside the 24-hour customer session; only approved Content templates can be sent',
  '63024': 'Invalid message recipient',
  '63032': 'Recipient does not have WhatsApp',
  '63049': 'Message rejected by Meta (template quality / pause)',
};

export function describeTwilioError(code: string | number | null | undefined, providerMessage?: string | null): string {
  const key = code === null || code === undefined ? '' : String(code);
  const friendly = TWILIO_ERROR_MESSAGES[key];
  if (friendly) return providerMessage ? `${friendly} (${key}: ${providerMessage})` : `${friendly} (${key})`;
  if (providerMessage) return key ? `${providerMessage} (${key})` : providerMessage;
  return key ? `Twilio error ${key}` : 'Twilio request failed';
}

export const FREEFORM_WARNING = 'Free-form WhatsApp body sent without a Content template; delivery only succeeds inside a 24-hour customer session';

export interface TwilioAdapterOptions {
  accountSid: string;
  authToken: string;
  messagingServiceSid?: string | null;
  from?: string | null;
  /** Injectable for tests. */
  fetchImpl?: typeof fetch;
  timeoutMs?: number;
  /** Extra attempts on 5xx / network failure (INT-007). */
  retries?: number;
  baseUrl?: string;
}

export class TwilioWhatsAppAdapter implements WhatsAppAdapter {
  readonly name = 'twilio';
  private readonly opts: Required<Pick<TwilioAdapterOptions, 'accountSid' | 'authToken' | 'timeoutMs' | 'retries' | 'baseUrl'>> & TwilioAdapterOptions;

  constructor(opts: TwilioAdapterOptions) {
    this.opts = { timeoutMs: 10_000, retries: 1, baseUrl: 'https://api.twilio.com', ...opts };
  }

  get messagesUrl(): string {
    return `${this.opts.baseUrl}/2010-04-01/Accounts/${encodeURIComponent(this.opts.accountSid)}/Messages.json`;
  }

  /** Builds the form-encoded request body (exposed for tests). */
  buildParams(input: WhatsAppSendInput, to: string): URLSearchParams {
    const params = new URLSearchParams();
    params.set('To', `whatsapp:${to}`);
    if (this.opts.messagingServiceSid) params.set('MessagingServiceSid', this.opts.messagingServiceSid);
    else if (this.opts.from) params.set('From', this.opts.from.startsWith('whatsapp:') ? this.opts.from : `whatsapp:${this.opts.from}`);
    if (input.contentSid) {
      params.set('ContentSid', input.contentSid);
      params.set('ContentVariables', JSON.stringify(input.contentVariables ?? {}));
    } else {
      params.set('Body', input.body);
    }
    if (input.statusCallback) params.set('StatusCallback', input.statusCallback);
    return params;
  }

  async send(input: WhatsAppSendInput): Promise<WhatsAppSendResult> {
    const to = normalisePhone(input.to);
    if (!to) {
      return { provider_ref: null, status: 'failed', error: describeTwilioError('21211', 'number must be E.164 (+27…)'), provider_error_code: '21211' };
    }
    if (!this.opts.accountSid || !this.opts.authToken) {
      return { provider_ref: null, status: 'failed', error: 'Twilio is not configured (TWILIO_ACCOUNT_SID / TWILIO_AUTH_TOKEN)', provider_error_code: 'not_configured' };
    }
    if (!this.opts.messagingServiceSid && !this.opts.from) {
      return { provider_ref: null, status: 'failed', error: 'No Twilio sender: set TWILIO_MESSAGING_SERVICE_SID or TWILIO_WHATSAPP_FROM', provider_error_code: 'not_configured' };
    }
    const params = this.buildParams(input, to);
    const warning = input.contentSid ? undefined : FREEFORM_WARNING;
    const log = logger.child({ to: maskPhone(to), template: input.contentSid ?? null, ...(input.meta ?? {}) });

    let lastError = 'Twilio request failed';
    let lastCode: string | null = 'network';
    for (let attempt = 0; attempt <= this.opts.retries; attempt++) {
      const res = await this.post(params);
      if (res.kind === 'ok') {
        log.info({ sid: res.sid, provider_status: res.status, attempt }, 'twilio whatsapp accepted');
        return { provider_ref: res.sid, status: 'sent', provider_status: res.status, warning };
      }
      if (res.kind === 'client_error') {
        log.warn({ code: res.code, attempt }, 'twilio whatsapp rejected');
        return { provider_ref: null, status: 'failed', error: describeTwilioError(res.code, res.message), provider_error_code: res.code, warning };
      }
      lastError = res.message;
      lastCode = res.code;
      log.warn({ code: res.code, attempt, retry: attempt < this.opts.retries }, 'twilio whatsapp transient failure');
    }
    return { provider_ref: null, status: 'failed', error: lastError, provider_error_code: lastCode, warning };
  }

  private async post(params: URLSearchParams): Promise<
    { kind: 'ok'; sid: string; status: string | null } | { kind: 'client_error'; code: string; message: string } | { kind: 'transient'; code: string; message: string }
  > {
    const fetchImpl = this.opts.fetchImpl ?? fetch;
    const controller = new AbortController();
    const timer = setTimeout(() => controller.abort(), this.opts.timeoutMs);
    try {
      const auth = Buffer.from(`${this.opts.accountSid}:${this.opts.authToken}`).toString('base64');
      const res = await fetchImpl(this.messagesUrl, {
        method: 'POST',
        headers: { Authorization: `Basic ${auth}`, 'Content-Type': 'application/x-www-form-urlencoded', Accept: 'application/json' },
        body: params.toString(),
        signal: controller.signal,
      });
      let json: Record<string, unknown> = {};
      try {
        json = (await res.json()) as Record<string, unknown>;
      } catch {
        json = {};
      }
      if (res.ok) {
        const sid = typeof json.sid === 'string' ? json.sid : null;
        if (!sid) return { kind: 'transient', code: 'bad_response', message: 'Twilio response had no message SID' };
        return { kind: 'ok', sid, status: typeof json.status === 'string' ? json.status : null };
      }
      const code = json.code !== undefined && json.code !== null ? String(json.code) : String(res.status);
      const message = typeof json.message === 'string' ? json.message : `HTTP ${res.status}`;
      if (res.status >= 500) return { kind: 'transient', code, message: describeTwilioError(code, message) };
      return { kind: 'client_error', code, message };
    } catch (err) {
      const e = err as Error;
      const timedOut = e.name === 'AbortError';
      return { kind: 'transient', code: timedOut ? 'timeout' : 'network', message: timedOut ? `Twilio request timed out after ${this.opts.timeoutMs} ms` : `Twilio request failed: ${e.message}` };
    } finally {
      clearTimeout(timer);
    }
  }
}

// ---------------------------------------------------------------------------
// Sandbox / noop
// ---------------------------------------------------------------------------

export class SandboxWhatsAppAdapter implements WhatsAppAdapter {
  readonly name = 'sandbox';
  async send(input: WhatsAppSendInput): Promise<WhatsAppSendResult> {
    const to = normalisePhone(input.to);
    if (!to) return { provider_ref: null, status: 'failed', error: describeTwilioError('21211', 'number must be E.164 (+27…)'), provider_error_code: '21211' };
    logger.info({ to: maskPhone(to), body_len: input.body.length, template: input.contentSid ?? null, ...(input.meta ?? {}) }, 'whatsapp sandbox send (no-op)');
    return { provider_ref: `wa_sbx_${Date.now()}`, status: 'sent', provider_status: 'queued' };
  }
}

export class NoopWhatsAppAdapter implements WhatsAppAdapter {
  readonly name = 'noop';
  async send(): Promise<WhatsAppSendResult> {
    return { provider_ref: null, status: 'suppressed' };
  }
}

let adapterOverride: WhatsAppAdapter | null = null;

export function getWhatsAppAdapter(enabled: boolean): WhatsAppAdapter {
  if (adapterOverride) return adapterOverride;
  if (!enabled) return new NoopWhatsAppAdapter();
  if (config.whatsappProvider === 'twilio') {
    return new TwilioWhatsAppAdapter({
      accountSid: config.twilioAccountSid,
      authToken: config.twilioAuthToken,
      messagingServiceSid: config.twilioMessagingServiceSid || null,
      from: config.twilioWhatsAppFrom || null,
    });
  }
  return new SandboxWhatsAppAdapter();
}

export function setWhatsAppAdapterForTests(a: WhatsAppAdapter | null): void {
  adapterOverride = a;
}

/** Absolute URL Twilio should post status callbacks to, or null when PUBLIC_API_BASE_URL is unset. */
export function twilioStatusCallbackUrl(): string | null {
  const base = config.publicApiBaseUrl;
  if (!base) return null;
  return `${base}/v1/notifications/twilio/status`;
}
