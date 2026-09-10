# Sparkling REST API v1 — contract

Base URL (dev): `https://<region>-sparkling-4e89d.cloudfunctions.net/api/v1` (Cloud Functions 2nd gen `api`).
Local: `http://127.0.0.1:5001/sparkling-4e89d/europe-west1/api/v1` (emulator).

All JSON, snake_case, timestamps ISO-8601 UTC, money in integer cents (`ZAR`).

## Conventions

- **Auth**: `Authorization: Bearer <Firebase ID token>` on every route except `/health`, `/payments/webhook` and `/notifications/twilio/status` (provider-signed).
- **Idempotency** (API-003): mutating routes accept `Idempotency-Key: <uuid>` (or `client_op_id` in the body). Replays return the cached first response (`idempotency_keys`).
- **Errors** (API-004):
  ```json
  { "error": { "code": "validation_error", "message": "Slot is no longer available", "details": [...], "correlation_id": "..." } }
  ```
  Codes: `unauthenticated` 401, `forbidden` 403, `not_found` 404, `validation_error` 400, `conflict` 409, `invalid_transition` 409, `rate_limited` 429, `internal` 500.
- **Report ranges**: `/admin/exports`, `/admin/payments` and `/admin/reports/summary` accept `from`/`to` as `YYYY-MM-DD` (whole UTC days: `from` 00:00:00Z, `to` 23:59:59.999Z) or full ISO timestamps; default last 30 days.
- **Pagination** (API-006): `?limit=25&cursor=<opaque>` → `{ "data": [...], "next_cursor": "..." | null }`. Filters as query params; `sort=field:asc|desc`.
- **Correlation**: `X-Correlation-Id` echoed in responses and logged (API-010).
- **Versioning**: path `/v1`; clients send `X-Client-App: customer|staff|admin` and `X-Client-Version: 1.0.0+1` (ENG-005).

## Routes

### Auth & profile
| Method | Path | Roles | Notes |
|---|---|---|---|
| POST | `/auth/session` | any signed-in | Upsert profile, claim seed profile by e-mail, set custom claims. Body `{ app, full_name?, phone? }` → `{ profile, claims_updated: bool }` |
| GET | `/me` | any | `{ profile, outlets:[...], loyalty_account? }` |
| PATCH | `/me` | any | editable: full_name, phone, avatar_url, marketing_opt_in, whatsapp_opt_in, push_opt_in, locale, reduced_motion, haptics |
| POST | `/devices` | any | `{ token, platform, app }` register FCM token |
| DELETE | `/devices/:token` | any | |

### Catalogue
| GET | `/outlets` | any | active outlets, `?lat&lng` adds `distance_km` |
| GET | `/outlets/:id/services` | any | outlet services with effective `price_cents`, `points_estimate` |
| GET | `/availability?outlet_id&service_id&date=YYYY-MM-DD` | any | wraps `get_available_slots` |

### Vehicles
| GET | `/vehicles` | customer (own) / staff | |
| POST | `/vehicles` | customer | `{ registration_no, vin?, make?, model?, colour?, year?, licence_no?, disc_expiry?, source, disc_hash? }` → 201; 409 `conflict` with `existing_vehicle_id` on duplicate reg/VIN (CUS-015) unless `force: true` |
| PATCH | `/vehicles/:id` | owner | |
| DELETE | `/vehicles/:id` | owner | soft (is_active=false) |
| POST | `/vehicles/parse-disc` | any | `{ raw }` → parsed fields (server-side validation of the SA disc PDF417 layout; on-device parser in `sparkling_core` is primary) |

### Bookings
| GET | `/bookings?status&limit&cursor` | customer (own) / staff (outlet) | expands `outlet`, `service`, `vehicle`, `work_order{status,stage,stage_count,eta_at,assignee_name}` |
| GET | `/bookings/:id` | owner/staff | plus `payment`, `timeline` (derived from checklist template + results) |
| POST | `/bookings` | customer | `{ vehicle_id, outlet_id, service_id, slot_start, client_op_id, notes? }` → 201 with price computed server-side (tier discount from published loyalty config). 409 if slot full (CUS-022) |
| POST | `/bookings/:id/cancel` | owner/staff | `{ reason? }` allowed until `in_service` |
| POST | `/bookings/:id/reschedule` | owner | `{ slot_start }` revalidates |
| POST | `/bookings/:id/checkin` | staff | creates work order + task (if not already), status `in_service`, optional `{ bay, priority }` |

### Quotations
| GET | `/quotations` | customer/staff | |
| GET | `/quotations/:id` | | includes `attachments[]` |
| POST | `/quotations` | customer | `{ vehicle_id, outlet_id, category, description, client_op_id, attachment_ids? }` → 201 |
| POST | `/quotations/:id/attachments` | owner/staff | `{ storage_path, mime_type, size_bytes, sha256? }` (file already uploaded to Cloud Storage) |
| POST | `/quotations/:id/quote` | supervisor/manager | `{ amount_cents, line_items[], valid_until }` → status `quoted`, notifies customer |
| POST | `/quotations/:id/decision` | owner | `{ decision: "accept"|"decline", note? }` (CUS-033) |
| POST | `/quotations/:id/convert` | supervisor/manager | accepted → `converted`; creates work order + task with `quotation_id` (CUS-034) |

### Payments
| GET | `/payments/methods` | customer | tokenised methods only |
| POST | `/payments/methods` | customer | `{ provider_token, brand, last4, label }` (token from provider SDK; never PAN) |
| POST | `/payments/intents` | customer | `{ booking_id, method_id?, idempotency_key }` → `{ payment, client_secret?, redirect_url? }` status `pending` |
| POST | `/payments/:id/sandbox-confirm` | customer (flag `payments_sandbox`) | simulates a signed provider webhook → `successful` |
| POST | `/payments/webhook` | provider (HMAC `X-Signature`) | idempotent via `payment_events`; sets `successful/failed/refunded`, posts receipt, notification |
| GET | `/payments/:id` | owner/finance | includes `receipt` |

### Loyalty
| GET | `/loyalty/account` | customer | `{ account, tier_config, next_tier{name, points_needed}, published_version }` |
| GET | `/loyalty/ledger?limit&cursor` | customer | |
| GET | `/loyalty/rewards` | customer | eligible by tier |
| POST | `/loyalty/rewards/:id/redeem` | customer | idempotent by `Idempotency-Key`; ledger `redeem` + `reward_redemptions` |

### Staff — tasks & checklists
| GET | `/tasks?scope=mine|queue|done&outlet_id` | staff | expands work_order{ref, vehicle{registration_no, make, model}, service{name}, bay, priority, eta_at, progress{steps_done, step_count}, blocked_reason} |
| GET | `/work-orders/:id` | staff / customer(own) | `{ work_order, template{steps[]}, results[], events[], task }` |
| POST | `/tasks/:id/transition` | staff | `{ to: "in_progress"|"blocked"|"completed"|"verified", reason?, client_op_id, override?: {reason} }` (STF-023/033) |
| POST | `/tasks/:id/assign` | supervisor/manager | `{ assignee_id, reason? }` (STF-021) |
| POST | `/work-orders/:id/steps/:key` | staff | `{ status: "done"|"blocked"|"skipped", value?, attachment_id?, note?, client_op_id }` (numeric validated against min/max; photo requires attachment) |
| POST | `/work-orders/:id/pickup/verify` | staff (outlet) | `{ otp }` — customer presents the 5-digit collection OTP issued on `verified`; success sets `pickup_otp_verified_at/by` + `collected_at`, task_event `collected`, audited. Wrong OTP → 409 `invalid_otp` with `details.attempts_remaining`; after 5 failures (tracked in `task_events` `pickup_otp_failed`) → 409 `conflict` `{locked:true}` |
| POST | `/work-orders/:id/pickup/resend` | staff (outlet) | re-sends the **same** OTP via `pickup_otp` (push + WhatsApp Content template); 429 if sent < 1 min ago |
| POST | `/sync/batch` | any | `{ operations: [{ client_op_id, kind, payload, device_time }] }` → per-op `{ client_op_id, status: applied|conflict|rejected, result }` (ARC-004) |

### Staff — ops, inventory, gamification
| GET | `/staff/ops-summary?outlet_id&date` | supervisor/manager | `{ counts{in_progress,queued,blocked,done}, needs_attention[], team_load[] }` (STF-060) |
| GET | `/staff/team?outlet_id` | supervisor/manager | staff with availability, skills, active task count |
| GET | `/staff/leaderboard?outlet_id&period=week|month` | staff | `{ rows:[{staff_id,name,points,rank,delta}], me, badges:[{badge, earned_at?}] }` (STF-050/052) |
| GET | `/inventory?outlet_id` | staff | items + open alert |
| POST | `/inventory/:id/movements` | technician: usage/reorder_request; manager: all | `{ delta, reason, note?, work_order_id?, client_op_id }` (STF-042/043) |
| PATCH | `/inventory/:id` | manager | `{ reorder_threshold, name, unit }` audited |

### Admin
| GET | `/admin/kpis?outlet_id&from&to` | manager/admin/finance | `{ revenue_cents, revenue_trend_pct, bookings_today, active_work_orders, completed_today, exceptions_count, bookings_by_hour:[{hour,car_wash,auto_body}], revenue_by_outlet:[...], top_staff:[...] }` |
| GET | `/admin/exceptions?outlet_id` | manager/admin | blocked work orders, overdue SLA, low/out stock, failed payments — each with `link{type,id}` |
| GET | `/admin/activity?outlet_id&limit` | manager/admin | live feed derived from task_events/payment_events/loyalty_ledger/inventory_alerts |
| GET | `/admin/bookings?outlet_id&date&status&limit&cursor` | manager/admin/finance | live table |
| CRUD | `/admin/outlets`, `/admin/services`, `/admin/outlets/:id/services/:serviceId` | admin | audited |
| GET | `/admin/outlet-services?outlet_id` | manager/admin/finance | `{ data:[{ outlet_id, service_id, price_cents, is_available }] }` — whole matrix, or one outlet (must be visible to the caller); write via `PUT /admin/outlets/:id/services/:serviceId` |
| CRUD | `/admin/users` (`GET`, `POST` invite, `PATCH` role/outlets/is_active) | admin | sets custom claims; `is_active=false` revokes refresh tokens (SEC-014) |
| GET | `/admin/customers?search`, `/admin/customers/:id` | manager/admin | access logged (ADM-024/041) |
| GET | `/admin/loyalty/config` | manager/admin | `{ published, draft }` |
| PUT | `/admin/loyalty/config/draft` | manager/admin | `{ tiers, rules, change_note }` |
| POST | `/admin/loyalty/config/publish` | admin | draft → published (previous → archived), audited |
| POST | `/admin/loyalty/config/discard` | manager/admin | |
| GET | `/admin/inventory?outlet_id&alerts_first=true` | manager/admin | |
| GET | `/admin/staff/performance?outlet_id&period` | manager/admin | tasks completed, cycle time, checklist compliance, points |
| GET | `/admin/templates`, `POST`, `PUT /:id` | admin | checklist templates (new version on publish) |
| GET | `/admin/audit?entity_type&limit&cursor` | admin/manager | |
| GET | `/admin/payments?outlet_id&from&to&status&limit&cursor` | manager/admin/finance | `{ range, data:[{ id, booking_id, booking_ref, outlet_id, outlet_name, customer_id, customer_name, provider, method_brand, method_last4, amount_cents, currency, status, receipt_no, failure_reason, verified_at, created_at }], next_cursor }` newest first; finance-safe — no provider tokens/refs or idempotency keys (ADM-061). Same rows as `payments.csv` for the same filters |
| GET | `/admin/reports/summary?outlet_id&from&to` | manager/admin/finance | `{ range, financial:{ revenue_cents, refunds_cents, payments_total, payments_successful, payments_failed, avg_ticket_cents, by_status, by_outlet:[{outlet_id,name,revenue_cents,bookings}], by_service:[{service_id,name,category,revenue_cents,count}] }, operational:{ bookings, created, pending, confirmed, in_service, completed, cancelled, work_orders_completed, on_time_pct, avg_cycle_minutes, checklist_compliance_pct, quotes:{requested,quoted,accepted,declined,expired,converted} }, loyalty:{ points_issued, points_redeemed, points_expired }, inventory:{ items_active, items_below_threshold, items_out_of_stock, open_alerts }, notifications:{ total, delivered, failed, suppressed, delivery_rate_pct } }` — computed from the same queries as the CSV exports so totals reconcile (REP-005). `loyalty`/`notifications` are platform-wide (`outlet_scoped:false`) |
| GET | `/admin/exports/:report.csv?…filters` | manager/admin/finance | `report ∈ bookings|payments|inventory|staff_performance|loyalty`; header rows include generated_at, filters, scope (REP-007) |
| GET | `/admin/integrations` | manager/admin | `{ data:[{ key, name, status, detail, icon, … }] }` — `supabase {ok, latency_ms}`, `firebase {project_id}`, `payments {provider, sandbox}`, `whatsapp {provider: twilio|sandbox, configured, messaging_service (masked `MG4d8b…1660`), status_callback, enabled}`; never secrets |
| GET | `/admin/notifications?status&channel&recipient_id&template_key&limit&cursor` | manager/admin | delivery log: `{ data:[{ id, recipient_id, recipient_name, channel, template_key, title, body, status, provider_ref, provider_status, provider_error_code, error, attempts, sent_at, delivered_at, read_by_recipient_at, read_at, created_at }], next_cursor }` |
| POST | `/admin/notifications/:id/resend` | manager/admin | re-sends a `failed`/`suppressed` push or WhatsApp row from its stored template + `payload.vars`; bumps `attempts`; audited (`notification.resend`) → `{ notification, outcome:{channel,status} }`; 409 otherwise |
| GET | `/admin/flags`, `PATCH /admin/flags/:key` | admin | |

### Notifications
| GET | `/notifications?limit&cursor` | any | own |
| POST | `/notifications/:id/read` | any | |
| POST | `/notifications/twilio/status` | Twilio (form-encoded, `X-Twilio-Signature`) | delivery receipts: maps `queued|accepted|sending→queued`, `sent→sent`, `delivered→delivered` (+`delivered_at`), `read→delivered` (+`read_by_recipient_at`), `failed|undelivered→failed` (+`ErrorCode`/`ErrorMessage` → `provider_error_code`/`error`); matched by `provider_ref = MessageSid`; idempotent (replays / stale / unknown SIDs → 200 `{ignored:true}`); 403 on a bad signature or when `TWILIO_AUTH_TOKEN` is unset |

**WhatsApp via Twilio (INT-002).** `notification_templates` rows with `provider='twilio'` + `provider_template_sid` (`HX…`) are sent as Content templates: `provider_variables` (`{"1":"first_name","2":"quotation_id"}`) is resolved against the render context. `quote_ready` supplies `first_name` (from the profile) + `quotation_id`; `service_ready`/`pickup_otp` supply `otp`, `vehicle`, `outlet`. The rendered `body` is still stored for the in-app inbox. Sending is gated by the `whatsapp_enabled` flag and `whatsapp_opt_in`; numbers are normalised to E.164 (`082…` → `+2782…`).

## Realtime channels (client-side, Supabase)

| Client | Subscription |
|---|---|
| Customer | `bookings` (customer_id=eq.<uid>), `work_orders` (customer_id), `checklist_step_results` (work_order_id in own), `loyalty_ledger`, `notifications` |
| Staff | `tasks`, `work_orders`, `checklist_step_results`, `inventory_items`, `inventory_alerts`, `staff_availability` filtered by `outlet_id` |
| Admin | `bookings`, `work_orders`, `payments`, `inventory_alerts`, `task_events` per selected outlet |

## Reference payload — `GET /bookings/:id`

```json
{
  "id": "1000…0001", "ref": "SPK-2026-0091", "status": "in_service",
  "slot_start": "2026-09-08T08:00:00Z", "slot_end": "2026-09-08T09:00:00Z",
  "price_cents": 22000, "discount_cents": 2200, "total_cents": 19800, "discount_label": "Gold −10%", "points_pending": 20,
  "outlet": { "id": "…", "name": "Sparkling Sandton", "rating": 4.8 },
  "service": { "id": "…", "name": "Full Valet", "duration_minutes": 60, "category": "car_wash" },
  "vehicle": { "id": "…", "registration_no": "KL 45 MN GP", "make": "Toyota", "model": "Corolla Cross" },
  "work_order": { "id": "…", "ref": "WO-2026-4821", "status": "in_progress", "stage": 3, "stage_count": 6, "progress_pct": 58,
                  "assignee_name": "Pieter van der Merwe", "bay": "Bay 2", "eta_at": "…", "updated_at": "…",
                  "verified_at": null, "pickup_otp_verified_at": null, "collected_at": null },
  "timeline": [ { "key": "checked_in", "title": "Checked in", "state": "done", "at": "…" },
                { "key": "prewash", "title": "Pre-wash inspection", "state": "done", "at": "…" },
                { "key": "exterior", "title": "Exterior wash & rinse", "state": "current" },
                { "key": "interior", "title": "Interior vacuum & dash", "state": "pending" } ],
  "payment": { "id": "…", "status": "successful", "receipt_no": "RCP-70001", "amount_cents": 19800 }
}
```

Once the work order is `verified` (booking `completed`) and until `collected_at` is set, the **owning customer's** `work_order` additionally carries `"pickup_otp": "48213", "pickup_otp_issued_at": "…"` — the 5-digit collection code (also pushed / WhatsApped). Staff never receive `pickup_otp`; they see `pickup_otp_verified_at` / `collected_at` after `POST /work-orders/:id/pickup/verify`.
