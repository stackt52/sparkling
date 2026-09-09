/**
 * NOT-001..004: template rendering, `notifications` rows with dedupe keys,
 * push via FCM, WhatsApp via adapter (flag `whatsapp_enabled`), promotional
 * suppression when `marketing_opt_in=false`.
 */
import { sendPush } from '../lib/fcm.js';
import { getSupabase, PG_UNIQUE_VIOLATION } from '../lib/supabase.js';
import { getWhatsAppAdapter } from '../lib/whatsapp.js';
import { logger } from '../middleware/correlation.js';
import type { NotifyChannel, NotifyStatus, Profile } from '../types.js';
import { flagEnabled } from './flags.js';

export interface TemplateRow {
  key: string;
  channel: NotifyChannel;
  version: number;
  title: string | null;
  body: string;
  is_promotional: boolean;
  is_active: boolean;
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

  for (const tpl of wanted) {
    const title = tpl.title ? renderTemplate(tpl.title, input.vars) : null;
    const body = renderTemplate(tpl.body, input.vars);
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
        payload: input.payload ?? {},
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

    let finalStatus: NotifyStatus = 'failed';
    let providerRef: string | null = null;
    let errorText: string | null = null;

    if (tpl.channel === 'push') {
      const { data: tokens } = await db.from('device_tokens').select('token').eq('profile_id', input.recipientId);
      const list = ((tokens ?? []) as Array<{ token: string }>).map((t) => t.token);
      const res = await sendPush(list, {
        title: title ?? 'Sparkling',
        body,
        data: stringifyData({ template: tpl.key, notification_id: id, ...(input.payload ?? {}) }),
      });
      if (res.invalidTokens.length) await db.from('device_tokens').delete().in('token', res.invalidTokens);
      if (list.length === 0) {
        finalStatus = 'queued'; // no device yet: stays in-app only
      } else if (res.sent > 0) {
        finalStatus = 'sent';
      } else {
        finalStatus = 'failed';
        errorText = res.error ?? 'no token accepted';
      }
    } else if (tpl.channel === 'whatsapp') {
      if (!whatsappOn) {
        finalStatus = 'suppressed';
        errorText = 'whatsapp_enabled flag off';
      } else {
        try {
          const r = await getWhatsAppAdapter(true).send(recipient.phone!, body, { template: tpl.key });
          finalStatus = r.status;
          providerRef = r.provider_ref;
          errorText = r.error ?? null;
        } catch (err) {
          finalStatus = 'failed';
          errorText = (err as Error).message;
        }
      }
    } else {
      finalStatus = 'suppressed';
      errorText = `channel ${tpl.channel} not implemented`;
    }

    await db
      .from('notifications')
      .update({
        status: finalStatus,
        provider_ref: providerRef,
        error: errorText,
        attempts: 1,
        sent_at: (['sent', 'delivered'] as NotifyStatus[]).includes(finalStatus) ? new Date().toISOString() : null,
      })
      .eq('id', id);
    outcomes.push({ channel: tpl.channel, status: finalStatus, id });
  }
  return outcomes;
}

function stringifyData(obj: Record<string, unknown>): Record<string, string> {
  const out: Record<string, string> = {};
  for (const [k, v] of Object.entries(obj)) {
    if (v === undefined || v === null) continue;
    out[k] = typeof v === 'string' ? v : JSON.stringify(v);
  }
  return out;
}
