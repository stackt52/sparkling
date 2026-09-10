/**
 * Twilio webhook signature (X-Twilio-Signature): base64(HMAC-SHA1(authToken,
 * fullUrl + concat(sorted POST params as key+value))). See
 * https://www.twilio.com/docs/usage/webhooks/webhooks-security
 */
import { createHmac, timingSafeEqual } from 'node:crypto';

export type TwilioParams = Record<string, string | string[] | undefined>;

export function computeTwilioSignature(authToken: string, url: string, params: TwilioParams = {}): string {
  const keys = Object.keys(params).sort();
  let data = url;
  for (const k of keys) {
    const v = params[k];
    if (v === undefined) continue;
    // Repeated keys: Twilio concatenates key + each value, values sorted.
    const values = Array.isArray(v) ? [...v].sort() : [v];
    for (const val of values) data += k + val;
  }
  return createHmac('sha1', authToken).update(data, 'utf8').digest('base64');
}

/**
 * Constant-time check. Returns false when the token or signature is missing.
 * Twilio may sign the URL with or without the port (and with `http` behind a
 * TLS-terminating proxy), so callers can pass several candidate URLs.
 */
export function validateTwilioSignature(authToken: string | null | undefined, signature: string | null | undefined, urls: string | string[], params: TwilioParams = {}): boolean {
  if (!authToken || !signature) return false;
  const candidates = Array.isArray(urls) ? urls : [urls];
  const given = Buffer.from(signature, 'utf8');
  for (const url of candidates) {
    const expected = Buffer.from(computeTwilioSignature(authToken, url, params), 'utf8');
    if (expected.length === given.length && timingSafeEqual(expected, given)) return true;
  }
  return false;
}
