/**
 * Firebase Admin singleton (Auth + FCM). Tests can inject fakes via setters.
 */
import { getApps, initializeApp, type App } from 'firebase-admin/app';
import { getAuth, type Auth } from 'firebase-admin/auth';
import { getMessaging, type Messaging } from 'firebase-admin/messaging';
import { FIREBASE_PROJECT_ID } from '../config.js';

let app: App | null = null;
let authOverride: Auth | null = null;
let messagingOverride: Messaging | null = null;

export function getFirebaseApp(): App {
  if (app) return app;
  app = getApps()[0] ?? initializeApp({ projectId: process.env.GCLOUD_PROJECT ?? FIREBASE_PROJECT_ID });
  return app;
}

export function firebaseAuth(): Auth {
  return authOverride ?? getAuth(getFirebaseApp());
}

export function firebaseMessaging(): Messaging {
  return messagingOverride ?? getMessaging(getFirebaseApp());
}

export function setFirebaseAuthForTests(a: Auth | null): void {
  authOverride = a;
}
export function setFirebaseMessagingForTests(m: Messaging | null): void {
  messagingOverride = m;
}
