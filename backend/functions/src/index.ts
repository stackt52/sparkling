/**
 * Cloud Functions (2nd gen) entry point. Single HTTPS function `api` in
 * europe-west1 serving the Express app at /v1 (ARC-002, API-001).
 */
import { setGlobalOptions } from 'firebase-functions/v2';
import { onRequest } from 'firebase-functions/v2/https';
import { createApp } from './app.js';
import { paymentWebhookSecret, REGION, supabaseServiceRoleKey, whatsappToken } from './config.js';

setGlobalOptions({ region: REGION, maxInstances: 20 });

let app: ReturnType<typeof createApp> | null = null;

export const api = onRequest(
  {
    region: REGION,
    secrets: [supabaseServiceRoleKey, paymentWebhookSecret, whatsappToken],
    memory: '512MiB',
    timeoutSeconds: 60,
    minInstances: 0,
    concurrency: 80,
    cors: false,
  },
  (req, res) => {
    app ??= createApp();
    app(req, res);
  },
);
