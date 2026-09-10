/**
 * API-010: correlation ids + structured logging (pino).
 */
import { randomUUID } from 'node:crypto';
import type { RequestHandler } from 'express';
import pino from 'pino';
import { config } from '../config.js';

export const logger = pino({
  level: process.env.LOG_LEVEL ?? (config.nodeEnv === 'test' ? 'silent' : 'info'),
  base: { service: 'sparkling-api', version: process.env.API_VERSION ?? '1.0.0' },
  messageKey: 'message',
  formatters: {
    level: (label) => ({ severity: label.toUpperCase(), level: label }),
  },
  timestamp: pino.stdTimeFunctions.isoTime,
});

export const correlation: RequestHandler = (req, res, next) => {
  const incoming = req.header('X-Correlation-Id');
  const id = incoming && /^[A-Za-z0-9._:-]{4,128}$/.test(incoming) ? incoming : randomUUID();
  req.correlationId = id;
  res.setHeader('X-Correlation-Id', id);
  req.log = logger.child({
    correlation_id: id,
    method: req.method,
    path: req.originalUrl.split('?')[0],
    client_app: req.header('X-Client-App') ?? undefined,
    client_version: req.header('X-Client-Version') ?? undefined,
  });
  const started = Date.now();
  res.on('finish', () => {
    req.log.info({ status: res.statusCode, duration_ms: Date.now() - started, uid: req.auth?.uid }, 'request');
  });
  next();
};
