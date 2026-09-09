# SRS v1.0 → implementation traceability

Where each requirement group and release acceptance criterion (SRS §18) lives in this repository. "API" = `backend/functions/src`, "DB" = `backend/supabase/migrations`, "core" = `packages/sparkling_core`, "ui" = `packages/sparkling_ui`.

## Release acceptance criteria

| AC | Condition | Implementation | Status |
|---|---|---|---|
| AC-01 | Register/sign in, add vehicle by PDF417 or manual, book, confirm, history | Customer app auth + vehicles + scanner + booking flow; `POST /vehicles`, `POST /bookings`, `GET /bookings`; `core/scanning/Pdf417DiscParser` | Built; end-to-end verified in demo mode |
| AC-02 | Submit quotation request and track status | Customer app quotations; `POST /quotations`, `GET /quotations/:id`, decision endpoint | Built |
| AC-03 | Staff receive/execute tasks and complete a configured checklist | Staff app tasks + checklist; `GET /tasks`, `POST /work-orders/:id/steps/:key`, `POST /tasks/:id/transition`; templates in `checklist_templates` | Built |
| AC-04 | Offline continuation and safe sync (no duplicates/loss) | `core/offline/OfflineQueue` (durable Hive queue, op ids), `POST /sync/batch` (dedupe on `client_op_id`, conflict responses), unique `client_op_id` columns | Built; unit-tested (queue + batch dedupe) |
| AC-05 | Customer timeline reflects staff progress in near real time | Supabase Realtime publication (13 tables) + RLS; `core/realtime/RealtimeService`; customer tracking screen | Built; needs Supabase Third-Party Auth (Firebase) enabled (runbook §1) |
| AC-06 | Payment verified server-side; duplicate callbacks don't duplicate settlement/points | `services/payments.ts` webhook (HMAC + `payment_events` unique), `loyalty_ledger.idempotency_key`, `staff_points_ledger.idempotency_key` | Built; unit-tested (duplicate webhook, idempotent award) |
| AC-07 | Silver/Gold/Platinum configurable; balances reconcile to ledger | `loyalty_configs` (versioned draft/publish), append-only `loyalty_ledger` + trigger-maintained cache; admin `/loyalty` page | Built |
| AC-08 | Supervisor/manager dashboards, staff performance, low-stock alerts | Staff app ops screen (`/staff/ops-summary`), admin overview + `/staff/performance` + `/inventory`; `inventory_alerts` trigger | Built |
| AC-09 | Admin manages outlets, services, users/roles, loyalty, workflow/assignment parameters | Admin pages outlets/services/staff/loyalty/templates/settings; `/admin/*` routes with audit rows | Built |
| AC-10 | Financial/operational reports filterable and exportable within scope | `/admin/exports/:report.csv` (metadata header rows), `/admin/reports/summary`; admin `/reports` | Built |
| AC-11 | Role/outlet/customer boundaries verified by negative tests | RLS policies (DB §16) + API `requireRole`/`requireOutlet`/ownership middleware; vitest auth tests | Built; RLS negative tests to be added against a Supabase branch |
| AC-12 | Staff app phone + tablet; customer app Android + iOS; admin tablet + desktop | Staff app two-pane ≥840dp; customer app both platforms registered in Firebase; admin rail→drawer <900px | Built; iOS simulator + Android emulator + browser verified |
| AC-13 | M3 Expressive theming, motion, responsive, accessibility/reduced motion | `ui/tokens`, `SparklingTheme`, `SparklingMotion.reducedMotion`, admin `prefers-reduced-motion` CSS, ≥44/48px targets | Built |
| AC-14 | Observability, backup/recovery, environment separation, rollback documented | `docs/RUNBOOK.md` §6–7, pino structured logs with correlation ids, Secret Manager secrets | Documented; production monitoring dashboards are an ops task |

## Requirement groups

| Group | IDs | Where |
|---|---|---|
| Architecture | ARC-001…008 | Flutter apps + shared packages; single versioned API `/v1`; Realtime; offline queue; RLS; App Hosting config; ownership matrix in `docs/ARCHITECTURE.md` |
| UX / M3 | UX-001…012 | `packages/sparkling_ui` tokens/theme; admin `src/theme`; reduced-motion scopes; scanner overlay with permission guidance; `DraftStore` for form persistence; `ApiException` plain-language errors |
| Customer | CUS-001…072 | Customer app features; API routes auth/me/vehicles/bookings/quotations/payments/loyalty/notifications |
| Staff | STF-001…062 | Staff app features; API tasks/work-orders/staff/inventory/sync; `task_events` audit; auto-assignment in `services/workflow.ts` |
| Admin | ADM-001…063 | Admin app; `/admin/*` routes; `audit_events` |
| API | API-001…012 | Express app, zod schemas, error envelope, idempotency middleware, pagination cursors, `openapi.yaml`, pino correlation ids |
| Data | DAT-001…007 | uuid PKs, `created_at/updated_at` triggers, soft-delete (`is_active`), timestamptz UTC, `sync_operations`, `attachments` metadata, retention documented in runbook |
| Integration | INT-001…007 | Payment provider adapter (sandbox), WhatsApp adapter (flag), FCM via `device_tokens`, on-device PDF417 decode, secrets in Secret Manager |
| Security | SEC-001…014 | HTTPS only (Cloud Functions), secure storage (`flutter_secure_storage`), server-side authz, append-only audit triggers, tokenised payment methods, rate limiting, deactivation revokes refresh tokens |
| NFR | NFR-001…015 | Offline/degraded states, idempotent retries, structured logging, env-specific dart-defines/`apphosting.yaml`, text-scaling-safe layouts |
| Reporting | REP-001…007 | `/admin/kpis`, `/admin/reports/summary`, CSV exports with generated_at/filters/scope |
| Barcode | BAR-001…010 | `mobile_scanner` restricted to PDF417, `Pdf417DiscParser` (documented field assumption), `ScanDebouncer`, controller disposal, parser unit tests |
| Notifications | NOT-001…006 | `notification_templates` (versioned), event-driven from server state, `notifications` log with provider refs, `dedupe_key`, promotional suppression on opt-out |
| Engineering | ENG-001…007 | Monorepo with lint/test gates (`docs/RUNBOOK.md` §6), versioned SQL migrations, client version headers |

## Open decisions carried from SRS §11.2 / §20
- Payment gateway: sandbox adapter shipped; real provider adapter to be added behind the same interface.
- WhatsApp Business provider/templates: adapter + templates table ready; provider client and opt-in model pending.
- PDF417 disc schema: parser implements the documented `%`-delimited layout as an assumption; confirm with sample discs before production acceptance.
- Financial system interface: CSV export + `/admin/payments` reconcile view; transport/mapping to the finance system pending.
