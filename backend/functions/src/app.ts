/**
 * Express app for the Sparkling REST API v1 (API-001..012).
 * Exported separately from the Cloud Function so tests can drive it in-process.
 */
import cors from 'cors';
import express, { type Express } from 'express';
import { config } from './config.js';
import { authenticate } from './middleware/auth.js';
import { correlation } from './middleware/correlation.js';
import { errorHandler, notFoundHandler } from './middleware/errors.js';
import { idempotency } from './middleware/idempotency.js';
import { adminRouter } from './routes/admin.js';
import { authRouter } from './routes/auth.js';
import { bookingsRouter } from './routes/bookings.js';
import { catalogueRouter } from './routes/catalogue.js';
import { inventoryRouter } from './routes/inventory.js';
import { loyaltyRouter } from './routes/loyalty.js';
import { notificationsRouter } from './routes/notifications.js';
import { paymentsRouter, paymentsWebhookRouter } from './routes/payments.js';
import { quotationsRouter } from './routes/quotations.js';
import { staffRouter } from './routes/staff.js';
import { syncRouter } from './routes/sync.js';
import { tasksRouter } from './routes/tasks.js';
import { vehiclesRouter } from './routes/vehicles.js';
import { workOrdersRouter } from './routes/workOrders.js';

export function createApp(): Express {
  const app = express();
  app.set('trust proxy', true);
  app.disable('x-powered-by');
  app.use(correlation);
  app.use(
    cors({
      origin: true,
      credentials: false,
      allowedHeaders: ['Authorization', 'Content-Type', 'Idempotency-Key', 'X-Correlation-Id', 'X-Client-App', 'X-Client-Version', 'X-Signature'],
      exposedHeaders: ['X-Correlation-Id', 'Idempotent-Replayed', 'X-RateLimit-Limit', 'X-RateLimit-Remaining', 'Retry-After'],
      maxAge: 600,
    }),
  );

  const v1 = express.Router();

  // Public routes (no auth): health + provider webhook (raw body for HMAC).
  v1.get('/health', (_req, res) => {
    res.json({ ok: true, version: config.apiVersion, service: 'sparkling-api', time: new Date().toISOString() });
  });
  v1.use(paymentsWebhookRouter);

  // Everything else: JSON body, Firebase auth, idempotency.
  v1.use(express.json({ limit: '1mb' }));
  v1.use(authenticate);
  v1.use(idempotency);
  v1.use(authRouter);
  v1.use(catalogueRouter);
  v1.use(vehiclesRouter);
  v1.use(bookingsRouter);
  v1.use(quotationsRouter);
  v1.use(paymentsRouter);
  v1.use(loyaltyRouter);
  v1.use(tasksRouter);
  v1.use(workOrdersRouter);
  v1.use(staffRouter);
  v1.use(inventoryRouter);
  v1.use(adminRouter);
  v1.use(notificationsRouter);
  v1.use(syncRouter);

  app.use('/v1', v1);
  // The Cloud Functions URL includes the function name; support both mounts.
  app.use('/api/v1', v1);
  app.use(notFoundHandler);
  app.use(errorHandler);
  return app;
}
