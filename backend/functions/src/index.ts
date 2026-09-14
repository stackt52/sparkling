/**
 * Cloud Functions (2nd gen) entry point. HTTPS function `api` in europe-west1
 * serving the Express app at /v1 (ARC-002, API-001) plus the daily
 * `membershipRenewals` schedule (docs/MEMBERSHIPS.md).
 */
import { setGlobalOptions } from 'firebase-functions/v2';
import { onRequest } from 'firebase-functions/v2/https';
import { onSchedule } from 'firebase-functions/v2/scheduler';
import { createApp } from './app.js';
import { paymentWebhookSecret, REGION, supabaseServiceRoleKey, twilioAccountSid, twilioAuthToken } from './config.js';
import { logger } from './middleware/correlation.js';
import { runRenewals } from './services/memberships.js';

setGlobalOptions({ region: REGION, maxInstances: 20 });

let app: ReturnType<typeof createApp> | null = null;

export const api = onRequest(
  {
    region: REGION,
    secrets: [supabaseServiceRoleKey, paymentWebhookSecret, twilioAccountSid, twilioAuthToken],
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

/** Membership renewals: invoices 3 days ahead, sandbox card auto-charge, past_due, expiry (02:00 SAST daily). */
export const membershipRenewals = onSchedule(
  {
    schedule: '0 2 * * *',
    timeZone: 'Africa/Johannesburg',
    region: REGION,
    secrets: [supabaseServiceRoleKey, paymentWebhookSecret, twilioAccountSid, twilioAuthToken],
    memory: '512MiB',
    timeoutSeconds: 300,
    retryCount: 1,
  },
  async () => {
    const result = await runRenewals();
    logger.info({ ...result, errors: result.errors.length }, 'membership renewals run');
    if (result.errors.length) logger.warn({ errors: result.errors }, 'membership renewals had errors');
  },
);
