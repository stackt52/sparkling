# Sparkling Platform — Architecture

Implements SRS v1.0 (28 Aug 2026). Three clients, one versioned backend, one authoritative database.

```
apps/customer   Flutter (Android + iOS)      Customer app
apps/staff      Flutter (Android phone/tab)  Outlet staff app
apps/admin      Next.js 15 + TypeScript      Admin dashboard (Firebase App Hosting)
packages/sparkling_ui    Flutter design system: M3 Expressive tokens, theme, shared widgets (UX-001)
packages/sparkling_core  Flutter shared domain: models, REST client, Supabase realtime, offline queue, PDF417 parser
backend/functions        Firebase Cloud Functions (Node 22, TypeScript, Express) — REST API /v1 (ARC-002)
backend/supabase         Versioned SQL migrations + demo seed (ENG-006)
docs/                    This file, API contract, runbooks
```

## Technology decisions

| Concern | Decision | SRS |
|---|---|---|
| Identity | **Firebase Auth** (email/password + Google). Custom claims `role`, `outlet_ids` are minted by the API and mirrored from `profiles`. | CUS-001, STF-001, ADM-001 |
| Database (authoritative) | **Supabase Postgres** project `uicqczgpiqkczwyssdft`. Every business entity lives here; see ownership matrix. | ARC-007 |
| Files | **Cloud Storage for Firebase** (`sparkling-4e89d.firebasestorage.app`). Metadata row in `attachments`. | DAT-006 |
| REST API | Cloud Functions 2nd gen, single Express app exported as `api`, mounted at `/v1`. Uses the Supabase **service role** key from Secret Manager. | API-001..012 |
| Real-time | **Supabase Realtime** (`postgres_changes`) consumed directly by clients using the Firebase ID token through Supabase *Third-Party Auth (Firebase)*. RLS policies (migration 0001 §16) are therefore identical for REST reads and subscriptions. | ARC-003, API-007/008 |
| Push | Firebase Cloud Messaging via `device_tokens`. | INT-003 |
| WhatsApp | Provider adapter behind `notifications` table; sandbox adapter logs only (flag `whatsapp_enabled`). | INT-002 |
| Payments | Provider adapter interface; **sandbox adapter** ships (flag `payments_sandbox`). Webhook verified by HMAC + `payment_events(provider, provider_event_id)` uniqueness for replay protection. | CUS-040..045, API-009 |
| Offline | Client-side durable queue (Hive) of operations with `client_op_id`; server dedupes via unique `client_op_id` / `sync_operations`. | ARC-004, DAT-005 |

## Data ownership matrix (ARC-007)

| Entity | Write master | Readers |
|---|---|---|
| Identity (uid, email, password) | Firebase Auth | API (verify token) |
| Profile, roles, outlet scope | Supabase `profiles`, `staff_outlets` (API writes; claims mirrored to Firebase) | all |
| Vehicles | Supabase (customer may insert/update own via RLS; API for staff) | customer, staff |
| Bookings / quotations / work orders / tasks / checklist results | Supabase via API only | RLS-scoped |
| Payments | Supabase via API + provider webhook | customer (own), finance |
| Loyalty | `loyalty_ledger` append-only via API; `loyalty_accounts` is a trigger-maintained cache | customer (own), managers |
| Inventory | `inventory_movements` append-only via API; `inventory_items.on_hand` trigger-maintained | staff (outlet scope) |
| Files | Cloud Storage objects; `attachments` rows via API | RLS-scoped |
| Audit | `audit_events` append-only via API | admin / manager (outlet scope) |

## Auth flow

1. Client signs in with Firebase Auth and obtains an ID token.
2. Client calls `POST /v1/auth/session`. The API upserts `profiles` (claiming a seeded profile with the same e-mail on first sign-in), computes `role` + `outlet_ids`, sets them as Firebase custom claims, and returns the profile. Client refreshes the ID token so claims are present. If the API cannot be reached the client keeps the Firebase session and surfaces `ApiException(code: 'network')` ("Couldn't reach Sparkling servers") with a retry; the staff app additionally requires the *returned profile* (or cached claims when offline) to have a staff role before entering the app, since a first sign-in has no claims until this call completes.
3. Every API call carries `Authorization: Bearer <idToken>`. Middleware verifies it, loads the profile, and enforces role/outlet/ownership (SEC-003).
4. Clients create a Supabase client with `accessToken: () => firebaseUser.getIdToken()`. Supabase must have Third-Party Auth → Firebase enabled for project `sparkling-4e89d` (one-time dashboard step; documented in `docs/RUNBOOK.md`). RLS helper `app.role()` reads the `role` claim, `app.outlet_ids()` the `outlet_ids` claim.

## State machines (server-validated)

- Booking: `draft → pending → confirmed → in_service → completed`, any pre-`in_service` state → `cancelled` (CUS-025).
- Quotation: `requested → assessing → quoted → accepted | declined | expired`; `accepted → converted` (creates a work order, keeps `quotation_id`) (CUS-033/034).
- Work order / task: `queued → assigned → in_progress ⇄ blocked → completed → verified`; supervisors may `verified` only when all required steps are `done` or an override is recorded in `task_events` (STF-023/033).
- Payment: `initiated → pending → successful | failed | cancelled`; `successful → refunded`. Only the webhook (or sandbox confirm endpoint which simulates it) can set `successful` (CUS-041).

Loyalty tier rule: a customer's tier is qualified on **lifetime earned points** (sum of positive ledger entries) against the published tier floors, so redeeming never demotes; `balance_points` is the spendable balance. "N pts to <tier>" therefore counts from lifetime points.

Side effects on `work_order → verified`: booking → `completed`, loyalty `earn` ledger entry with idempotency key `booking:<id>:earn`, staff points `task_completed` with key `task:<id>:completed`, customer notification `service_ready`.

## Environments (SEC-012, NFR-014)

| | Firebase | Supabase | Config |
|---|---|---|---|
| dev | `sparkling-4e89d` | `uicqczgpiqkczwyssdft` | `.env.local`, `--dart-define-from-file=env/dev.json` |
| prod | (create separate project) | (create separate project) | Secret Manager + App Hosting `apphosting.yaml` |
| local auth | Firebase Auth emulator (`firebase emulators:start --only auth`, port 9099) | — | `--dart-define-from-file=env/emulator.json` (`AUTH_EMULATOR_HOST=127.0.0.1:9099`; Android AVD: `env/emulator-android.json` → `10.0.2.2:9099`) |

Secrets (`SUPABASE_SERVICE_ROLE_KEY`, `PAYMENT_WEBHOOK_SECRET`, `WHATSAPP_TOKEN`) live in Secret Manager and are never in client bundles (INT-006).

## Design system

`packages/sparkling_ui` and `apps/admin/src/theme` both derive from the same token sheet (`design_handoff_sparkling_apps/README.md`): Sparkling primary `#006398`, brand navy `#203060`, azure `#00A0E0`, gold gradient, Outfit type ramp, pill shapes, M3 Expressive motion tokens (spring ~400 ms, reduced-motion aware).
