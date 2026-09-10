/**
 * NOT-001..004: template rendering, `notifications` rows with dedupe keys,
 * push via FCM, WhatsApp via adapter (flag `whatsapp_enabled`), promotional
 * suppression when `marketing_opt_in=false`.
 *
 * WhatsApp templates bound to a Twilio Content SID (`provider='twilio'`,
 * `provider_template_sid`) are sent as template messages: the positional
 * `provider_variables` map (`{"1":"first_name"}`) is resolved against the
 * render context; the free-form `body` is still rendered for the in-app row.
 * Render vars are persisted in `payload.vars` so a failed/suppressed row can
 * be re-sent later (admin resend) and Twilio status callbacks update the row
 * by `provider_ref` (Message SID).
 */
import { sendPush } from '../lib/fcm.js';
import { getSupabase, PG_UNIQUE_VIOLATION, unwrap } from '../lib/supabase.js';
import { getWhatsAppAdapter, twilioStatusCallbackUrl } from '../lib/whatsapp.js';
import { logger } from '../middleware/correlation.js';
import { ApiError } from '../middleware/errors.js';
import type { Notification, NotifyChannel, NotifyStatus, Profile, RequestContext } from '../types.js';
import { audit } from './audit.js';
import { flagEnabled } from './flags.js';

export interface TemplateRow {
  key: string;
  channel: NotifyChannel;
  version: number;
  title: string | null;
  body: string;
  is_promotional: boolean;
  is_active: boolean;
  provider?: string | null;
  provider_template_sid?: string | null;
  provider_variables?: Record<string, string> | null;
}

/** `{{var}}` substitution; unknown vars render as empty strings. */
export function renderTemplate(text: string | null | undefined, vars: Record<string, unknown>): string {
  if (!text) return '';
  return text.replace(/\{\{\s*([a-zA-Z0-9_.]+)\s*\}\}/g, (_m, key: string) => {
    const v = vars[key];
    if (v === undefined || v === null) return '';
    return String(v);
  });
}

export function formatRand(cents: number): string {
  const rand = Math.floor(cents / 100);
  const c = Math.abs(cents % 100);
  const grouped = String(rand).replace(/\B(?=(\d{3})+(?!\d))/g, ' ');
  return `${grouped}.${String(c).padStart(2, '0')}`;
}

/** Legacy `capitalize`: first letter upper, rest as-is. */
export function firstName(fullName: string | null | undefined): string {
  const first = (fullName ?? '').trim().split(/\s+/)[0] ?? '';
  return first ? first.charAt(0).toUpperCase() + first.slice(1) : '';
}

/**
 * Resolves a Twilio Content template's positional variables
 * (`{"1":"first_name","2":"quotation_id"}`) from the render context. Missing
 * vars render as empty strings so the template still sends; the caller logs
 * them.
 */
export function buildContentVariables(mapping: Record<string, string> | null | undefined, vars: Record<string, unknown>): { variables: Record<string, string>; missing: string[] } {
  const variables: Record<string, string> = {};
  const missing: string[] = [];
  for (const [slot, name] of Object.entries(mapping ?? {})) {
    const v = vars[name];
    if (v === undefined || v === null || v === '') missing.push(name);
    variables[slot] = v === undefined || v === null ? '' : String(v);
  }
  return { variables, missing };
}

export function usesProviderTemplate(tpl: Pick<TemplateRow, 'provider' | 'provider_template_sid'>): boolean {
  return tpl.provider === 'twilio' && !!tpl.provider_template_sid;
}

export interface NotifyInput {
  recipientId: string;
  templateKey: string;
  vars: Record<string, unknown>;
  /** Stable key so retries never double-send (NOT-004). */
  dedupeKey: string;
  payload?: Record<string, unknown>;
  channels?: NotifyChannel[];
}

export interface NotifyOutcome {
  channel: NotifyChannel;
  status: NotifyStatus | 'duplicate' | 'no_template';
  id?: string;
}

async function loadTemplates(key: string): Promise<TemplateRow[]> {
  const db = getSupabase();
  const { data, error } = await db.from('notification_templates').select('*').eq('key', key).eq('is_active', true);
  if (error) {
    logger.warn({ err: error, key }, 'template lookup failed');
    return [];
  }
  return (data ?? []) as TemplateRow[];
}

interface DeliveryResult {
  status: NotifyStatus;
  provider_ref: string | null;
  error: string | null;
  provider_status: string | null;
  provider_error_code: string | null;
}

/** Delivers one rendered notification on its channel. Never throws. */
async function deliver(tpl: TemplateRow, recipient: Profile, id: string, title: string | null, body: string, vars: Record<string, unknown>, payload: Record<string, unknown>, whatsappOn: boolean): Promise<DeliveryResult> {
  const db = getSupabase();
  const out: DeliveryResult = { status: 'failed', provider_ref: null, error: null, provider_status: null, provider_error_code: null };

  if (tpl.channel === 'push') {
    const { data: tokens } = await db.from('device_tokens').select('token').eq('profile_id', recipient.id);
    const list = ((tokens ?? []) as Array<{ token: string }>).map((t) => t.token);
    const { vars: _vars, ...data } = payload;
    const res = await sendPush(list, { title: title ?? 'Sparkling', body, data: stringifyData({ template: tpl.key, notification_id: id, ...data }) });
    if (res.invalidTokens.length) await db.from('device_tokens').delete().in('token', res.invalidTokens);
    if (list.length === 0) {
      out.status = 'queued'; // no device yet: stays in-app only
    } else if (res.sent > 0) {
      out.status = 'sent';
    } else {
      out.status = 'failed';
      out.error = res.error ?? 'no token accepted';
    }
    return out;
  }

  if (tpl.channel === 'whatsapp') {
    if (!whatsappOn) {
      out.status = 'suppressed';
      out.error = 'whatsapp_enabled flag off';
      return out;
    }
    if (!recipient.phone) {
      out.status = 'failed';
      out.error = 'Customer phone number missing';
      return out;
    }
    try {
      const templated = usesProviderTemplate(tpl);
      const content = templated ? buildContentVariables(tpl.provider_variables, vars) : null;
      if (content?.missing.length) logger.warn({ template: tpl.key, missing: content.missing }, 'content template variables missing from render context');
      const r = await getWhatsAppAdapter(true).send({
        to: recipient.phone,
        body,
        contentSid: templated ? tpl.provider_template_sid : null,
        contentVariables: content?.variables ?? null,
        statusCallback: twilioStatusCallbackUrl(),
        meta: { template: tpl.key, notification_id: id },
      });
      out.status = r.status;
      out.provider_ref = r.provider_ref;
      out.provider_status = r.provider_status ?? null;
      out.provider_error_code = r.provider_error_code ?? null;
      out.error = r.error ?? (r.warning ? `warning: ${r.warning}` : null);
    } catch (err) {
      out.status = 'failed';
      out.error = (err as Error).message;
    }
    return out;
  }

  out.status = 'suppressed';
  out.error = `channel ${tpl.channel} not implemented`;
  return out;
}

function deliveryPatch(r: DeliveryResult, attempts: number) {
  return {
    status: r.status,
    provider_ref: r.provider_ref,
    provider_status: r.provider_status,
    provider_error_code: r.provider_error_code,
    error: r.error,
    attempts,
    sent_at: (['sent', 'delivered'] as NotifyStatus[]).includes(r.status) ? new Date().toISOString() : null,
  };
}

/**
 * Sends a notification on every channel for which an active template exists
 * (or only `channels` when given). Never throws — delivery failures are
 * recorded on the row.
 */
export async function notify(input: NotifyInput): Promise<NotifyOutcome[]> {
  const db = getSupabase();
  const outcomes: NotifyOutcome[] = [];
  const templates = await loadTemplates(input.templateKey);
  const wanted = templates.filter((t) => !input.channels || input.channels.includes(t.channel));
  if (wanted.length === 0) return [{ channel: 'push', status: 'no_template' }];

  const { data: profile } = await db.from('profiles').select('*').eq('id', input.recipientId).maybeSingle();
  const recipient = profile as Profile | null;
  if (!recipient) return [{ channel: 'push', status: 'failed' }];

  const whatsappOn = await flagEnabled('whatsapp_enabled');
  const vars: Record<string, unknown> = { first_name: firstName(recipient.full_name), name: recipient.full_name, ...input.vars };
  const payload: Record<string, unknown> = { ...(input.payload ?? {}), vars: serialisableVars(vars) };

  for (const tpl of wanted) {
    const title = tpl.title ? renderTemplate(tpl.title, vars) : null;
    const body = renderTemplate(tpl.body, vars);
    const dedupe = `${input.dedupeKey}:${tpl.channel}`;

    let status: NotifyStatus = 'queued';
    if (tpl.is_promotional && !recipient.marketing_opt_in) status = 'suppressed';
    else if (tpl.channel === 'push' && !recipient.push_opt_in) status = 'suppressed';
    else if (tpl.channel === 'whatsapp' && (!recipient.whatsapp_opt_in || !recipient.phone)) status = 'suppressed';

    const inserted = await db
      .from('notifications')
      .insert({
        recipient_id: input.recipientId,
        channel: tpl.channel,
        template_key: tpl.key,
        title,
        body,
        payload,
        status,
        dedupe_key: dedupe,
      })
      .select('id')
      .single();
    if (inserted.error) {
      if (inserted.error.code === PG_UNIQUE_VIOLATION) {
        outcomes.push({ channel: tpl.channel, status: 'duplicate' });
        continue;
      }
      logger.error({ err: inserted.error }, 'notification insert failed');
      outcomes.push({ channel: tpl.channel, status: 'failed' });
      continue;
    }
    const id = (inserted.data as { id: string }).id;
    if (status === 'suppressed') {
      outcomes.push({ channel: tpl.channel, status, id });
      continue;
    }

    const result = await deliver(tpl, recipient, id, title, body, vars, payload, whatsappOn);
    await db.from('notifications').update(deliveryPatch(result, 1)).eq('id', id);
    outcomes.push({ channel: tpl.channel, status: result.status, id });
  }
  return outcomes;
}

// ---------------------------------------------------------------------------
// Admin resend (ADM / NOT-004)
// ---------------------------------------------------------------------------

export const RESENDABLE_STATUSES: NotifyStatus[] = ['failed', 'suppressed'];

/**
 * Re-sends a failed/suppressed push or WhatsApp notification using the stored
 * template and `payload.vars`. Consent gates still apply; the flag gate is
 * re-evaluated (a row suppressed while `whatsapp_enabled` was off can be sent
 * once it is on).
 */
export async function resendNotification(ctx: RequestContext, id: string): Promise<{ notification: Notification; outcome: NotifyOutcome }> {
  const db = getSupabase();
  const row = unwrap<Notification | null>(await db.from('notifications').select('*').eq('id', id).maybeSingle(), 'notification');
  if (!row) throw ApiError.notFound('Notification');
  if (row.channel !== 'whatsapp' && row.channel !== 'push') throw ApiError.conflict(`Resend is not supported for channel ${row.channel}`);
  if (!RESENDABLE_STATUSES.includes(row.status)) throw ApiError.conflict(`Only failed or suppressed notifications can be re-sent (status is ${row.status})`, { status: row.status });

  const tpl = unwrap<TemplateRow | null>(
    await db.from('notification_templates').select('*').eq('key', row.template_key).eq('channel', row.channel).eq('is_active', true).maybeSingle(),
    'template',
  );
  if (!tpl) throw ApiError.conflict(`No active ${row.channel} template for ${row.template_key}`);
  const recipient = unwrap<Profile | null>(await db.from('profiles').select('*').eq('id', row.recipient_id).maybeSingle(), 'recipient');
  if (!recipient) throw ApiError.notFound('Recipient profile');

  const storedVars = (row.payload?.vars ?? {}) as Record<string, unknown>;
  const vars: Record<string, unknown> = { first_name: firstName(recipient.full_name), name: recipient.full_name, ...storedVars };
  const payload: Record<string, unknown> = { ...(row.payload ?? {}), vars: serialisableVars(vars) };
  const title = tpl.title ? renderTemplate(tpl.title, vars) : null;
  const body = renderTemplate(tpl.body, vars);

  let result: DeliveryResult;
  if (tpl.is_promotional && !recipient.marketing_opt_in) result = { status: 'suppressed', provider_ref: null, error: 'marketing_opt_in=false', provider_status: null, provider_error_code: null };
  else if (tpl.channel === 'push' && !recipient.push_opt_in) result = { status: 'suppressed', provider_ref: null, error: 'push_opt_in=false', provider_status: null, provider_error_code: null };
  else if (tpl.channel === 'whatsapp' && !recipient.whatsapp_opt_in) result = { status: 'suppressed', provider_ref: null, error: 'whatsapp_opt_in=false', provider_status: null, provider_error_code: null };
  else result = await deliver(tpl, recipient, row.id, title, body, vars, payload, await flagEnabled('whatsapp_enabled'));

  const attempts = (row.attempts ?? 0) + 1;
  const updated = unwrap<Notification>(
    await db
      .from('notifications')
      .update({ ...deliveryPatch(result, attempts), title, body, payload, delivered_at: null, read_by_recipient_at: null })
      .eq('id', row.id)
      .select('*')
      .single(),
    'notification resend',
  );
  await audit(ctx, {
    action: 'notification.resend',
    entity_type: 'notification',
    entity_id: row.id,
    before: { status: row.status, attempts: row.attempts ?? 0 },
    after: { status: result.status, attempts, provider_ref: result.provider_ref, error: result.error },
    outcome: result.status === 'failed' ? 'failed' : 'ok',
  });
  return { notification: updated, outcome: { channel: row.channel, status: result.status, id: row.id } };
}

// ---------------------------------------------------------------------------
// Twilio status callback
// ---------------------------------------------------------------------------

export interface TwilioStatusParams {
  MessageSid?: string;
  MessageStatus?: string;
  SmsStatus?: string;
  ErrorCode?: string;
  ErrorMessage?: string;
  [k: string]: unknown;
}

export interface TwilioStatusOutcome {
  ignored: boolean;
  reason?: string;
  notification_id?: string;
  status?: NotifyStatus;
  provider_status?: string;
}

const PROVIDER_RANK: Record<string, number> = { queued: 0, accepted: 0, scheduled: 0, sending: 0, sent: 1, delivered: 2, read: 3, undelivered: 4, failed: 4 };

/** Maps a raw Twilio message status to our row status. */
export function mapTwilioStatus(raw: string): NotifyStatus | null {
  switch (raw.toLowerCase()) {
    case 'queued':
    case 'accepted':
    case 'scheduled':
    case 'sending':
      return 'queued';
    case 'sent':
      return 'sent';
    case 'delivered':
    case 'read':
      return 'delivered';
    case 'failed':
    case 'undelivered':
      return 'failed';
    default:
      return null;
  }
}

/**
 * Applies a delivery receipt to the notification whose `provider_ref` is the
 * Message SID. Idempotent: replays and out-of-order (older) statuses are
 * ignored; a late `failed` never overwrites `delivered`.
 */
export async function applyTwilioStatus(params: TwilioStatusParams): Promise<TwilioStatusOutcome> {
  const sid = typeof params.MessageSid === 'string' ? params.MessageSid.trim() : '';
  const raw = String(params.MessageStatus ?? params.SmsStatus ?? '').trim().toLowerCase();
  if (!sid) return { ignored: true, reason: 'missing MessageSid' };
  const mapped = mapTwilioStatus(raw);
  if (!mapped) return { ignored: true, reason: `unknown status ${raw || '(empty)'}` };

  const db = getSupabase();
  const row = unwrap<Notification | null>(await db.from('notifications').select('*').eq('provider_ref', sid).maybeSingle(), 'notification by provider_ref');
  if (!row) return { ignored: true, reason: 'unknown MessageSid' };

  const current = (row.provider_status ?? '').toLowerCase();
  const currentRank = PROVIDER_RANK[current] ?? -1;
  const newRank = PROVIDER_RANK[raw] ?? 0;
  const alreadyDelivered = row.status === 'delivered';
  if (current === raw) return { ignored: true, reason: 'duplicate', notification_id: row.id, status: row.status, provider_status: current };
  if (newRank < currentRank) return { ignored: true, reason: 'stale', notification_id: row.id, status: row.status, provider_status: current };
  if (mapped === 'failed' && alreadyDelivered) return { ignored: true, reason: 'already delivered', notification_id: row.id, status: row.status, provider_status: current };

  const now = new Date().toISOString();
  const patch: Record<string, unknown> = { provider_status: raw, status: mapped };
  if (mapped === 'sent' && !row.sent_at) patch.sent_at = now;
  if (raw === 'delivered') {
    patch.delivered_at = row.delivered_at ?? now;
    if (!row.sent_at) patch.sent_at = now;
  }
  if (raw === 'read') {
    patch.delivered_at = row.delivered_at ?? now;
    patch.read_by_recipient_at = row.read_by_recipient_at ?? now;
    if (!row.sent_at) patch.sent_at = now;
  }
  if (mapped === 'failed') {
    const code = params.ErrorCode ? String(params.ErrorCode) : null;
    patch.provider_error_code = code;
    const msg = typeof params.ErrorMessage === 'string' && params.ErrorMessage.trim() ? params.ErrorMessage.trim() : null;
    patch.error = code || msg ? [code ? `Twilio ${code}` : null, msg].filter(Boolean).join(': ') : `Twilio reported ${raw}`;
  }
  await db.from('notifications').update(patch).eq('id', row.id);
  return { ignored: false, notification_id: row.id, status: mapped, provider_status: raw };
}

// ---------------------------------------------------------------------------
// helpers
// ---------------------------------------------------------------------------

function stringifyData(obj: Record<string, unknown>): Record<string, string> {
  const out: Record<string, string> = {};
  for (const [k, v] of Object.entries(obj)) {
    if (v === undefined || v === null) continue;
    out[k] = typeof v === 'string' ? v : JSON.stringify(v);
  }
  return out;
}

/** Keeps only JSON-safe scalar vars for `payload.vars` (so resend can re-render). */
function serialisableVars(vars: Record<string, unknown>): Record<string, unknown> {
  const out: Record<string, unknown> = {};
  for (const [k, v] of Object.entries(vars)) {
    if (v === undefined) continue;
    out[k] = v === null || ['string', 'number', 'boolean'].includes(typeof v) ? v : String(v);
  }
  return out;
}
