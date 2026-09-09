/**
 * INT-003: push via Firebase Cloud Messaging. Errors are swallowed and reported
 * back so the notifications service can mark rows `failed`.
 */
import { firebaseMessaging } from './firebase.js';

export interface PushMessage {
  title: string;
  body: string;
  data?: Record<string, string>;
}

export interface PushResult {
  sent: number;
  failed: number;
  invalidTokens: string[];
  error?: string;
}

export async function sendPush(tokens: string[], msg: PushMessage): Promise<PushResult> {
  if (tokens.length === 0) return { sent: 0, failed: 0, invalidTokens: [] };
  try {
    const res = await firebaseMessaging().sendEachForMulticast({
      tokens,
      notification: { title: msg.title, body: msg.body },
      data: msg.data,
      android: { priority: 'high', notification: { channelId: 'sparkling_default' } },
      apns: { payload: { aps: { sound: 'default' } } },
    });
    const invalid: string[] = [];
    res.responses.forEach((r, i) => {
      const code = r.error?.code ?? '';
      if (code === 'messaging/registration-token-not-registered' || code === 'messaging/invalid-registration-token') {
        invalid.push(tokens[i]);
      }
    });
    return { sent: res.successCount, failed: res.failureCount, invalidTokens: invalid };
  } catch (err) {
    return { sent: 0, failed: tokens.length, invalidTokens: [], error: (err as Error).message };
  }
}
