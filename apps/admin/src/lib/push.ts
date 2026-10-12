'use client';
import { env } from './env';
import type { AdminApi } from './api';

/** Push payload `{ type, <type>_id }` as `notify()` sends it (stringified data). */
export type PushData = Record<string, string | undefined>;

/** Dashboard path a push payload points at (mirrors `webLinkFor` on the API). */
export function pushTargetPath(data: PushData): string {
  const type = data.type ?? '';
  if (type === 'quotation' && data.quotation_id) return `/quotations?focus=${encodeURIComponent(data.quotation_id)}`;
  if ((type === 'booking' || type === 'payment' || type === 'loyalty') && data.booking_id) return `/bookings?focus=${encodeURIComponent(data.booking_id)}`;
  if ((type === 'work_order' || type === 'task') && data.work_order_id) return `/work-orders?focus=${encodeURIComponent(data.work_order_id)}`;
  return '/notifications';
}

/** React Query keys a push should refresh (the drawer / grid behind the notification). */
export function pushQueryKeys(data: PushData): string[][] {
  const keys: string[][] = [['notifications']];
  switch (data.type) {
    case 'quotation': keys.push(['quotations'], ['quotation', data.quotation_id ?? '']); break;
    case 'booking': case 'payment': case 'loyalty': keys.push(['bookings'], ['booking', data.booking_id ?? ''], ['kpis']); break;
    case 'work_order': case 'task': keys.push(['work-orders'], ['bookings']); break;
    default: break;
  }
  return keys;
}

export const SW_PATH = '/firebase-messaging-sw.js';

/** Browser push needs a secure context, service workers, the Notification API and a VAPID key. */
export async function webPushSupported(): Promise<boolean> {
  if (typeof window === 'undefined' || !window.isSecureContext || !('Notification' in window) || !('serviceWorker' in navigator) || !env.vapidKey) return false;
  const { isSupported } = await import('firebase/messaging');
  return isSupported();
}

export function pushPermission(): NotificationPermission | 'unsupported' {
  return typeof window !== 'undefined' && 'Notification' in window ? Notification.permission : 'unsupported';
}

/**
 * Registers the Firebase messaging service worker, obtains this browser's FCM token and stores it with
 * `POST /devices` (platform `web`, app `admin`). Returns the token, or null when permission is not granted.
 */
export async function registerWebPush(api: AdminApi): Promise<string | null> {
  if (!(await webPushSupported()) || Notification.permission !== 'granted') return null;
  const [{ getMessaging, getToken }, { getFirebaseApp }] = await Promise.all([import('firebase/messaging'), import('./firebase')]);
  const registration = await navigator.serviceWorker.register(SW_PATH);
  const token = await getToken(getMessaging(getFirebaseApp()), { vapidKey: env.vapidKey, serviceWorkerRegistration: registration });
  if (!token) return null;
  await api.registerDevice({ token, platform: 'web', app: 'admin' });
  return token;
}

/** Subscribes to pushes received while the dashboard tab is in the foreground. Returns the unsubscribe. */
export async function onForegroundPush(handler: (msg: { title: string | null; body: string | null; data: PushData }) => void): Promise<() => void> {
  if (!(await webPushSupported())) return () => {};
  const [{ getMessaging, onMessage }, { getFirebaseApp }] = await Promise.all([import('firebase/messaging'), import('./firebase')]);
  return onMessage(getMessaging(getFirebaseApp()), (payload) => {
    handler({ title: payload.notification?.title ?? null, body: payload.notification?.body ?? null, data: (payload.data ?? {}) as PushData });
  });
}
