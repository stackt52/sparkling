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
| GET | `/me` | any | `{ profile, outlets:[...], loyalty_account?, membership }` — `membership` is the short plan summary (`{ membership_id, plan_code, plan_name, tier, status, period_end, cancel_at_period_end, allowances[] } \| null`, see Memberships) |
| PATCH | `/me` | any | editable: full_name, phone, avatar_url, marketing_opt_in, whatsapp_opt_in, push_opt_in, locale, reduced_motion, haptics |
| POST | `/devices` | any | `{ token, platform, app }` register FCM token |
| DELETE | `/devices/:token` | any | |

### Catalogue
| GET | `/outlets` | any | active outlets, `?lat&lng` adds `distance_km` |
| GET | `/outlets/:id/services` | any | outlet services with effective `price_cents`, `points_estimate` |
| GET | `/availability?outlet_id&service_id&date=YYYY-MM-DD` | any | wraps `get_available_slots` |

### Catalogue pricing model (migration 0008; source: `backend/supabase/source/*.xlsx`, importer `tools/catalogue/import_catalogue.py`)
Services are canonical rows in `services` (`code`, `group_name` ∈ `Car Wash Options` | `Combinations` | `Auto Body Repair`, `category`, `pricing_mode` ∈ `from` | `fixed` | `by_quote`, `vat_mode` ∈ `incl` | `excl`, `price_small_cents`, `price_large_cents`, `price_general_cents`, `is_addon`, `addon_group_name`). Each outlet binds a service in `outlet_services` with its own `display_name`, prices, `pricing_mode`/`vat_mode` overrides (null = inherit), `sort_order`, `notes`, `is_available`. Composite membership lives in `service_components` (`parent_service_id`, `child_service_id`, `outlet_id` null = global default; outlet rows override the global set). Vehicles carry `size_class` (`small` | `large` | `bike`; null → small); disc descriptions map: hatch/sedan → small, station wagon/SUV/pick-up/bakkie/bus → large.

`GET /outlets/:id/services` now returns `{ data: [OutletServiceOffer], groups: ["Car Wash Options", …] }` where an offer is
`{ id (= service_id), service_id, code, name (display_name ?? name), service_name (canonical), display_name, description, group_name, category, duration_minutes, pricing_mode, vat_mode, pricing_mode_override, vat_mode_override (raw outlet overrides, null = inherit), is_quote_based, price_small_cents, price_large_cents, price_general_cents, price_from_cents (lowest non-null), price_for: { small, large, bike } (resolved per size, null when by-quote), is_addon, addon_group_name, includes: [{ service_id, code, name }], included_in: [service_id], components_source, is_available, sort_order, notes, points_estimate }`. Optional `?vehicle_size=small|large|bike` adds `price_cents` resolved for that size.

Pricing (server-side, `services/pricing.ts`): price = outlet override for the vehicle size (small/large; general when size-independent; bike uses small) → service default; `by_quote` → no price (booking refused with 409 `validation_error` `{ reason: 'by_quote' }`; clients route to a quotation request instead); `from` prices are minimums and are labelled "From R x"; add-ons (`is_addon`) may be attached to a booking of a service in `addon_group_name` via `addon_service_ids[]` and are priced the same way and summed into `addons_cents`; tier discount applies to the sum. `vat_mode: excl` prices are shown "excl. VAT" and VAT (15%) is added on the quotation/booking total; `incl` prices are final. Bookings record `vehicle_size`, `pricing_mode`, `vat_mode`, `addon_service_ids`, `addons_cents`.

Admin management: `GET/POST/PUT /admin/services` accept the fields above plus `components: [{ child_service_id, quantity, sort_order }]` (global default set); `PUT /admin/outlets/:id/services/:serviceId` accepts `display_name`, `price_small_cents`, `price_large_cents`, `price_general_cents`, `pricing_mode`, `vat_mode`, `is_available`, `sort_order`, `notes`, `components` (outlet-specific set; `null` = use global). `GET /admin/outlets/:id/services` lists the outlet's offers with resolved composition. All audited.

### Vehicles
| GET | `/vehicles` | customer (own) / staff | |
| POST | `/vehicles` | customer | `{ registration_no, vin?, make?, model?, colour?, year?, licence_no?, disc_expiry?, source, disc_hash?, size_class? }` → 201 (size defaults from the disc description when omitted); 409 `conflict` with `existing_vehicle_id` on duplicate reg/VIN (CUS-015) unless `force: true` |
| PATCH | `/vehicles/:id` | owner | |
| DELETE | `/vehicles/:id` | owner | soft (is_active=false) |
| POST | `/vehicles/parse-disc` | any | `{ raw }` → parsed fields (server-side validation of the SA disc PDF417 layout; on-device parser in `sparkling_core` is primary) |

### Bookings
| GET | `/bookings?status&limit&cursor` | customer (own) / staff (outlet) | expands `outlet`, `service`, `vehicle`, `work_order{status,stage,stage_count,eta_at,assignee_name}` |
| GET | `/bookings/:id` | owner/staff | plus `customer{id,full_name,email,phone}`, `payment` (incl. `method` for POS rows), `timeline` (derived from checklist template + results) and, for staff, `created_by_name` (who took a walk-in at the counter) |
| POST | `/bookings` | customer | `{ vehicle_id, outlet_id, service_id, slot_start, client_op_id, notes?, vehicle_size?, addon_service_ids? }` → 201 with price computed server-side (size-aware from-price + add-ons, tier discount from published loyalty config). 409 if slot full (CUS-022); 409 `validation_error` `{reason:'by_quote'}` for quote-only services |
| POST | `/bookings/:id/cancel` | owner/staff | `{ reason? }` allowed until `in_service` |
| POST | `/bookings/:id/reschedule` | owner | `{ slot_start }` revalidates |
| POST | `/bookings/:id/checkin` | staff | creates work order + task (if not already), status `in_service`, optional `{ bay, priority }` |

### Quotations
| GET | `/quotations?status&outlet_id&limit&cursor` | customer/staff | rows carry `customer_name`, `assessor_name` (flattened joins) |
| GET | `/quotations/:id` | | includes `attachments[]`, `customer_name`, `assessor_name`, `work_order {id, ref, status} \| null` and `work_order_ref` |
| POST | `/quotations` | customer | `{ vehicle_id, outlet_id, category, description, client_op_id, attachment_ids? }` → 201 |
| POST | `/quotations/:id/attachments` | owner/staff | `{ storage_path, mime_type, size_bytes, sha256? }` (file already uploaded to Cloud Storage) |
| POST | `/quotations/:id/quote` | supervisor/manager | `{ amount_cents, line_items[], valid_until, items_note? }` → status `quoted`, notifies customer. Every mutation (`quote`, `decision`, `share`, `convert`, staff `POST /quotations`) answers with the same presented quotation as `GET /quotations/:id` |
| POST | `/quotations/:id/decision` | owner | `{ decision: "accept"|"decline", note? }` (CUS-033) |
| POST | `/quotations/:id/convert` | supervisor/manager | accepted → `converted`; creates work order + task with `quotation_id` (CUS-034) → 201 `{ quotation (with work_order_ref), work_order, task }` |

### Payments
| GET | `/payments/methods` | customer | tokenised methods only |
| POST | `/payments/methods` | customer | `{ provider_token, brand, last4, label }` (token from provider SDK; never PAN) |
| POST | `/payments/intents` | customer | `{ booking_id, method_id?, idempotency_key }` → `{ payment, client_secret?, redirect_url? }` status `pending` |
| POST | `/payments/:id/sandbox-confirm` | customer (flag `payments_sandbox`) | simulates a signed provider webhook → `successful` |
| POST | `/payments/webhook` | provider (HMAC `X-Signature`) | idempotent via `payment_events`; sets `successful/failed/refunded`, posts receipt, notification |
| GET | `/payments/:id` | owner/finance | includes `receipt` |

### Loyalty
| GET | `/loyalty/account` | customer | `{ account, tier_config, tiers, next_tier{name, points_needed}, published_version, rules, membership }` — the tier **is** the membership plan (Silver = no plan); `next_tier` is informational only, there is no points-based promotion |
| GET | `/loyalty/ledger?limit&cursor` | customer | |
| GET | `/loyalty/rewards` | customer | eligible by tier |
| POST | `/loyalty/rewards/:id/redeem` | customer | idempotent by `Idempotency-Key`; ledger `redeem` + `reward_redemptions` |

### Memberships (docs/MEMBERSHIPS.md; migrations 0009/0010) A booking whose total is R 0 (covered service, no add-ons) is created `confirmed` with no payment; `POST /payments/intents` for it answers 409 `validation_error {reason:'nothing_to_pay'}`.

The loyalty tier is the membership plan: Gold / Platinum / Black are monthly subscriptions (`membership_plans` → `membership_plan_groups` (choose_one | all) → `membership_plan_entitlements` (quantity × month|year) → services). A customer without a live membership is Silver. `loyalty_configs.tiers[].discount_pct` is 0 — every discount comes from the plan. Benefits apply while `status = 'active'`; `past_due` keeps the tier label but pauses benefits.

**Pricing** (`priceService`, used by `POST /bookings`, walk-ins, sync-batch and `GET /outlets/:id/services?vehicle_size`): a service covered by one of the member's selected (or `all`-group) entitlements with allowance left → `membership_benefit = 'included'`, `discount_cents = base` for that vehicle size (larger vehicles are still covered), add-ons still charged (+ VAT on them when `excl`), `discount_label = "Included in Gold · 2 of 4 left"` (count **after** this booking). Otherwise the plan discount by scope: `plan_services` (selected services once the allowance is used up, e.g. `"Platinum −10%"`), `other_services` (any service that is not a plan service, e.g. `"Gold −10%"`), `all_services`, `none`. `by_quote` services still 409 `{reason:'by_quote'}`; a staff-raised quotation line whose service is covered (Black annual ceramic coating) is recorded at `amount_cents: 0` with `membership_benefit: 'included'` + `entitlement_id` and consumes the allowance (key `quotation:<id>:membership:<entitlement_id>`; not released on decline — TODO). Every quote carries `membership: { membership_id, plan_code, plan_name, benefit: 'included'|'discount'|null, entitlement_id, entitlement_code, remaining_after, period_end } | null` (null = no active plan).

**Allowances**: `remaining = quantity − Σ membership_usage.quantity` for rows whose `period_start` equals the entitlement's current period start. Monthly = the membership period `[current_period_start, +1 calendar month)`; annual (`period = 'year'`) = the membership year `[anniversary, +1 year)` (anniversary = `started_at` advanced by whole years to cover now). Unused allowance does not roll over. Booking create → usage `+1` (key `booking:<id>:membership`), cancel → `−1` release (key `booking:<id>:membership_release`); both idempotent; bookings store `membership_id`, `entitlement_id`, `membership_benefit`.

| Method | Path | Role | Notes |
|---|---|---|---|
| GET | `/memberships/plans` | customer | `{ data: Plan[], current_plan_code, current_status }` — `Plan = { id, code, tier, name, tagline, monthly_fee_cents, discount_pct, discount_scope, discount_note, color, groups: [{ id, code, name, selection, entitlements: [{ id, code, label, quantity, period, services: [{ id, code, name, is_primary }] }] }] }` |
| GET | `/memberships/me` | customer | `{ membership, plan, next_plan, selections: { [group_code]: entitlement_code }, allowances: [{ entitlement_id, entitlement_code, group_code, label, quantity, used, remaining, period, period_start, period_end }], open_invoice, invoices (last 12), next_renewal_at, benefits_summary }` — all null/empty without a live membership |
| POST | `/memberships` | customer | `{ plan_code, selections, payment_method: 'card', client_op_id }` → 201 `{ membership (pending), invoice (pending, key first:<membership_id>), payment: { …, client_secret } }`. Pay through `POST /payments/:id/sandbox-confirm` (or the provider webhook): a `successful` payment with `membership_invoice_id` marks the invoice paid, activates the membership (period = now → +1 month, `loyalty_accounts.tier` = plan tier) and sends `membership_activated`. 409 `conflict` when a live membership exists; 400 when a `choose_one` group has no valid option |
| POST | `/memberships/me/invoices/:id/pay` | customer | sandbox intent for a pending renewal/upgrade invoice → 201 `{ invoice, payment: {…, client_secret} }` (an open intent replays with 200 `duplicate:true`). On success the period rolls to the invoice period (`membership_renewed`); an invoice paid **before** the period ends is applied by the renewals job at period end so the current allowances are not reset early |
| PUT | `/memberships/me/selections` | customer | `{ selections }` → summary; 409 `{ used, period_end }` once anything was redeemed this period |
| POST | `/memberships/me/change-plan` | customer | `{ plan_code, selections }`. Upgrade (higher fee) → 201 `{ change:'upgrade', invoice (full fee, period now → +1 month), payment {client_secret} }`; the plan, the new selections and a fresh period apply when it is paid (`next_plan_id` until then; other pending invoices are voided). Downgrade → 200 `{ change:'downgrade', applies_at: current_period_end }`; `next_plan_id` (+ stored selections) applies at the next paid renewal, whose invoice is raised at the new plan's fee. 409 when already on the plan or not `active` |
| POST | `/memberships/me/cancel` | customer | `{ at_period_end: true (default), reason? }` → `cancel_at_period_end` (benefits continue, `next_renewal_at` null) or immediate `cancelled` (benefits stop, tier → silver, pending invoices void). `membership_cancelled` |
| GET | `/staff/customers/:id/membership` | staff | same shape as `/memberships/me` for that customer |
| POST | `/staff/customers/:id/membership` | staff | `{ plan_code, selections, payment_method: 'cash'\|'card_terminal'\|'eft', reference?, outlet_id?, client_op_id }` → 201 `{ membership (active now, period now → +1 month), invoice (paid), payment (provider `pos`, `method`, `recorded_by`, receipt from `next_receipt_no()`, `payment_events` `pos.recorded`), summary }`; `membership_activated`; audited `membership.enrol`. `card_terminal` is stored as `payment_method: 'card'` but counter members are never auto-charged. Sync-batch kind `membership.enrol` takes the same payload (+ `customer_id`) |
| POST | `/staff/memberships/:id/invoices/:invoiceId/record-payment` | staff | `{ method, reference?, outlet_id?, client_op_id }` → 201 `{ payment, invoice (paid), membership (period rolled, `active`) }`; 409 unless the invoice is pending; audited `membership.record_payment` |
| GET | `/staff/customers?search` | staff | `loyalty` gains `plan_code`, `plan_name`, `membership_status`, `included_remaining` (remaining monthly washes) so the walk-in step can show "Gold · 3 washes left" |
| GET | `/admin/memberships/plans` | manager/admin/finance | plans incl. inactive with `member_count` (active + past_due) and `mrr_cents` (Σ fee of active members) |
| PUT | `/admin/memberships/plans/:code` | manager/admin | `{ name, tagline, monthly_fee_cents, discount_pct, discount_scope, discount_note, color?, is_active?, groups: [{ code, name, selection, entitlements: [{ code, label, quantity, period, service_codes[] }] }] }` — full replace of groups/entitlements **by code** (ids kept when the code exists so usage rows stay valid; 409 when removing an entitlement that has usage; unknown service codes → 400). Fee changes apply from the next invoice; allowance changes are visible immediately. Audited `membership_plan.update` |
| GET | `/admin/memberships?status&plan_code&q&limit&cursor` | manager/admin/finance | `{ data:[{ membership, customer:{id,full_name,phone,email}, plan:{code,name,tier,monthly_fee_cents}, next_plan, selections:{[group_code]:entitlement_code}, allowances[], used, remaining (monthly washes this period), open_invoice }], next_cursor }` newest first; `q` matches name / phone / e-mail / ref |
| GET | `/admin/customers/:id` | manager/admin | adds `membership` (same as `/memberships/me`) |
| POST | `/admin/customers/:id/membership` | manager/admin | enrol at the counter (as the staff route) |
| POST | `/admin/memberships/:id/cancel` | manager/admin | `{ at_period_end?, reason? }` — audited |
| POST | `/admin/memberships/:id/invoices/:invoiceId/record-payment` | manager/admin | as the staff route |
| POST | `/admin/memberships/run-renewals` | manager/admin | runs the renewals job now → `{ ran_at, scanned, rolled, cancelled, expired, invoices_created, auto_charged, past_due, errors[] }`; audited |
| GET | `/admin/kpis` | manager/admin/finance | adds `active_members`, `membership_mrr_cents` (platform-wide) |
| GET | `/admin/exports/memberships.csv` | manager/admin/finance | `ref, customer_id, customer, plan, status, period_start, period_end, fee_cents, used, remaining, allowances, open_invoice_ref, open_invoice_due_at, cancel_at_period_end, created_at` |

**Scheduled function `membershipRenewals`** (`0 2 * * *` Africa/Johannesburg, `src/index.ts`; same logic as `POST /admin/memberships/run-renewals`), per live membership: (1) `cancel_at_period_end` and period ended → `cancelled` (`ended_at`, tier → silver); `past_due` for 30 days past the period end → `expired`. (2) `active`, period ends within 3 days, no invoice for the next period → invoice `[period_end, +1 month)` at the (next) plan's fee, `idempotency_key = renewal:<membership_id>:<period_start date>`, `membership_renewal_due`. (4) `payment_method = 'card'` with the sandbox provider (and no `pos` payment history) → the due invoice is auto-charged through a sandbox intent + signed event; success rolls the period. (3) period ended and the invoice still unpaid → `past_due`, `membership_past_due`. Step 4 runs before step 3 so a successful card charge is never flagged past_due. A renewal paid ahead of time is applied (period rolled, pending plan switch applied) once the period ends. Notification vars: `name, plan, amount ("R 295.00"), period_end ("5 Oct 2026"), benefits`.


### Staff — tasks & checklists
| GET | `/tasks?scope=mine|queue|done&outlet_id` | staff | expands work_order{ref, vehicle{registration_no, make, model}, service{name}, bay, priority, eta_at, progress{steps_done, step_count}, blocked_reason} |
| GET | `/work-orders/:id` | staff / customer(own) | `{ work_order, template{steps[]}, results[], events[], task }` |
| POST | `/tasks/:id/transition` | staff | `{ to: "in_progress"|"blocked"|"completed"|"verified", reason?, client_op_id, override?: {reason} }` (STF-023/033) |
| POST | `/tasks/:id/assign` | supervisor/manager | `{ assignee_id, reason? }` (STF-021) |
| POST | `/work-orders/:id/steps/:key` | staff | `{ status: "done"|"blocked"|"skipped", value?, attachment_id?, note?, client_op_id }` (numeric validated against min/max; photo requires attachment) |
| POST | `/work-orders/:id/pickup/verify` | staff (outlet) | `{ otp }` — customer presents the 5-digit collection OTP issued on `verified`; success sets `pickup_otp_verified_at/by` + `collected_at`, task_event `collected`, audited. Wrong OTP → 409 `invalid_otp` with `details.attempts_remaining`; after 5 failures (tracked in `task_events` `pickup_otp_failed`) → 409 `conflict` `{locked:true}` |
| POST | `/work-orders/:id/pickup/resend` | staff (outlet) | re-sends the **same** OTP via `pickup_otp` (push + WhatsApp Content template); 429 if sent < 1 min ago |
| POST | `/sync/batch` | any | `{ operations: [{ client_op_id, kind, payload, device_time }] }` → per-op `{ client_op_id, status: applied|conflict|rejected, result }` (ARC-004). Kinds: `task.transition`, `step.result`, `inventory.movement`, `booking.create`, `booking.create_walk_in` (staff; same payload as a walk-in `POST /bookings`), `payment.record` (staff; accepts `booking_client_op_id` instead of `booking_id` so a payment queued behind a not-yet-synced walk-in resolves to the booking created earlier in the same batch), `quotation.create`, `vehicle.create`, `membership.enrol` (staff; `{ customer_id, plan_code, selections, payment_method, reference?, outlet_id? }`) |

### Staff — walk-in customers & bookings (STF-010/012, CUS-020..025 on behalf of a customer)
| GET | `/staff/customers?search&limit` | staff | Search customers by name, phone, e-mail or plate (min 2 chars). → `{ data: [{ id, full_name, email, phone, marketing_opt_in, whatsapp_opt_in, loyalty: {tier, balance_points, discount_pct, plan_code, plan_name, membership_status, included_remaining} \| null, vehicles: [{ id, registration_no, make, model, colour, disc_verified }] }] }` |
| POST | `/staff/customers` | staff | Register a walk-in customer without an app account: `{ full_name, phone, email?, marketing_opt_in?, whatsapp_opt_in?, client_op_id }` → 201 customer (same shape as above). Profile id is `walkin_<uuid>`; when the person later signs up with the same e-mail **or phone**, `/auth/session` claims the profile (bookings, vehicles and points carry over). 409 `conflict` with `existing_customer` when the phone or e-mail is already registered. Audited (`customer.create`). |
| POST | `/staff/customers/:id/vehicles` | staff | Add a vehicle for that customer: same body as `POST /vehicles` (+ `client_op_id`). 409 `conflict` with `existing_vehicle_id` on duplicate plate/VIN unless `force: true`. |
| POST | `/bookings` (staff) | staff | Existing route; staff may pass `customer_id` and `walk_in: true`. Walk-in: `slot_start` may be omitted (defaults to now rounded to the outlet's slot grid, capacity still enforced; 409 `conflict` when all bays are busy); status starts `confirmed`; optional `checkin: { bay?, priority? }` creates the work order + task immediately (booking → `in_service`) and returns `work_order`. `outlet_id` must be one of the staff member's outlets. Pricing/tier discount identical to the customer flow. |
| POST | `/payments/record` | staff | In-person payment attestation for a booking at the staff member's outlet: `{ booking_id, method: "cash" \| "card_terminal", reference?, amount_cents, idempotency_key }`. Amount must equal the booking total. Creates a `payments` row `provider: "pos"`, status `successful`, `verified_at` = now, receipt number from `next_receipt_no()`, `payment_events` row `pos.recorded` with the actor, audit `payment.record`, and sends `payment_successful`. Idempotent on `idempotency_key`. (Provider payments remain webhook-verified per CUS-041; POS payments are staff-attested and audited instead.) |

### Staff-raised quotations, damage photos & public quote page (CUS-030..034, STF-010/012, INT-002)
Quotation `line_items` entries become `{ label, description?, category?, service_id?, amount_cents, quantity? }` — one item per attention area (dent, scratch, bumper…) optionally tied to an auto-body `service_id`. Quotations gain `items_note`, `public_token` (uuid, never listed for staff except via the share endpoint), `public_token_expires_at`, `decision_source` (`app` | `public_link` | `staff`), `decision_by_name`, `pdf_generated_at`. Attachments gain `kind` (`damage_photo` | `document`), `width`/`height`, and are served through the API (never a raw bucket URL).

| POST | `/quotations` (staff) | staff | Raise a quote for a walk-in customer in one step: `{ customer_id, vehicle_id, outlet_id, category, description, items: [{ label, description?, category?, service_id?, amount_cents }], valid_until, items_note?, client_op_id, send_to_customer?: true }` → 201 `{ quotation }` with status **`quoted`** (amount = sum of items), `assessor_id` = staff, a fresh `public_token` (valid 30 days), audit `quotation.raise`. When `send_to_customer` (default true) the customer gets `quote_ready` push + WhatsApp (Content variables `first_name`, `public_token`; body fallback includes the public link `${PUBLIC_WEB_BASE_URL}/q/<token>`). Outlet must be one of the staff member's. Customers keep the existing request shape (status `requested`). |
| POST | `/quotations/:id/photos` | staff / owning customer | `multipart/form-data` field `photo` (jpeg/png/heic ≤ 10 MB, up to 10 per quotation) + optional `caption` → 201 attachment `{ id, kind:'damage_photo', mime_type, size_bytes, width, height, caption, url }`. Stored in Cloud Storage `quotations/<quotation_id>/<attachment_id>.<ext>` via the Admin SDK; `url` = `/v1/quotations/:id/photos/:attachmentId` (signed-in) — SEC-010: type sniffed, EXIF stripped is NOT required. |
| GET | `/quotations/:id/photos/:attachmentId` | staff / owner | Streams the image (`Cache-Control: private, max-age=3600`). |
| DELETE | `/quotations/:id/photos/:attachmentId` | staff (before decision) | Removes object + row. |
| POST | `/quotations/:id/share` | staff | Rotates/creates the public token (`{ public_url, expires_at }`) and re-sends the `quote_ready` WhatsApp/push; rate-limited 1/min. Audited `quotation.share`. |
| GET | `/quotations/:id` | owner / staff | Now includes `items` (alias of `line_items`), `attachments[]` with `url` and `kind`, `decision_source`, `public_url` (staff only), `pdf_url` = `/v1/quotations/:id/pdf`, and `terms` (the standard quotation terms text). |
| GET | `/quotations/:id/pdf` | owner / staff | PDF (A4) laid out like the Sparkling paper quote: logo, QUOTE + outlet code, Date/Expiry/Quote Number/Reference/VAT Number, outlet legal block (`legal_name`, `trading_as`, address, tel, e-mail), customer + vehicle, items table (Description/Quantity/Unit Price/VAT/Amount ZAR, VAT-exclusive figures + 15% so TOTAL ZAR = stored total), Subtotal/TOTAL VAT/TOTAL ZAR, status line, **Terms**, signature line, **OUR BANKING DETAILS** (`outlets.bank_details`), QR of the public link, photo thumbnails, and a per-page footer with `company_registration_no` + `registered_office` (migration 0007). `Content-Disposition: attachment; filename="<ref>.pdf"`. |
| POST | `/quotations/:id/decision` | owner (customer app) | Unchanged shape; decision is **one-time**: any later call → 409 `conflict` `{ decided_at, status }`. Sets `decision_source:'app'`. |

**Public (unauthenticated, token-scoped, rate-limited by IP + token, no PII beyond what the quote needs):**
| GET | `/public/quotations/:token` | anyone with the link | `{ ref, status, outlet: {name, phone, address_line, city, legal_name, trading_as, company_registration_no, vat_number, registered_office, bank_details}, customer: { first_name }, vehicle: { registration_no, make, model, colour }, items[], amount_cents, currency, valid_until, quoted_at, decided_at, decision_source, expired: bool, can_decide: bool, attachments: [{ id, url, caption, width, height }], pdf_url, notes, terms }`. 404 `not_found` for unknown/expired tokens (expired → 410 `gone` with `{ ref, status }`). |
| GET | `/public/quotations/:token/photos/:attachmentId` | link holder | Streams the image. |
| GET | `/public/quotations/:token/pdf` | link holder | Same PDF as above. |
| POST | `/public/quotations/:token/decision` | link holder | `{ decision: "accept" \| "decline", note?, accepted_by_name? }` → the same one-time rule (409 when already decided, in-app or via link; 410 when expired); sets `decision_source:'public_link'`, `decision_by_name`, audit `quotation.decision_public` with IP + user agent, notifies the outlet (`quote_decided` push to assessor/supervisors) and the customer (`quote_decision_receipt` WhatsApp/push). Returns the public view. |

Config: `PUBLIC_WEB_BASE_URL` param (admin app origin, e.g. `https://sparkling-admin-….hosted.app`); public link = `${PUBLIC_WEB_BASE_URL}/q/<token>`. The Twilio Content template `quote_ready` button URL must point at `<PUBLIC_WEB_BASE_URL>/q/{{2}}` (variable 2 = `public_token`); the `provider_variables` binding is updated by migration 0006.

### Staff — ops, inventory, gamification
| GET | `/staff/ops-summary?outlet_id&date` | supervisor/manager | `{ counts{in_progress,queued,blocked,done}, needs_attention[], team_load[] }` (STF-060) |
| GET | `/staff/team?outlet_id` | supervisor/manager | staff with availability, skills, active task count (`name` / `active_tasks` are aliases of `full_name` / `active_task_count` for the admin dashboard) |
| GET | `/staff/leaderboard?outlet_id&period=week|month` | staff | `{ rows:[{staff_id,name,points,rank,delta}], me, badges:[{badge, earned_at?}] }` (STF-050/052) |
| GET | `/inventory?outlet_id` | staff | items + open alert, plus `outlet_name`, `capacity` (stock-bar ceiling ≥ on_hand) and `blocking_work_orders` (blocked work orders that logged usage of the item) |
| POST | `/inventory/:id/movements` | technician: usage/reorder_request; manager: all | `{ delta, reason, note?, work_order_id?, client_op_id }` (STF-042/043) |
| PATCH | `/inventory/:id` | manager | `{ reorder_threshold, name, unit }` audited |

### Admin
| GET | `/admin/kpis?outlet_id&period=today\|week\|month` or `&from&to` | manager/admin/finance | `period` = calendar preset (UTC: today, Monday→now, 1st→now); default last 7 days. `{ range, period, revenue_cents, revenue_previous_cents, revenue_trend_pct (null when no previous revenue), revenue_compare_label, bookings_today, bookings_count, bookings_completed, bookings_in_service (slots in range), on_time_pct, active_work_orders, completed_today, avg_cycle_minutes, cycle_delta_minutes (vs 7-day avg), quotes_total, quotes_accepted, exceptions_count, exceptions_breakdown:{blocked,overdue,low_stock,stock_alerts,failed_payments}, bookings_by_hour:[{hour,car_wash,auto_body,future}], revenue_by_outlet:[{outlet_id,name,revenue_cents}], top_staff:[{staff_id,name,initials,points,rank,tier:gold\|silver\|bronze}], services_count, outlets_count, active_members, membership_mrr_cents }` |
| GET | `/admin/exceptions?outlet_id` | manager/admin/finance | blocked work orders, overdue SLA, low/out stock, failed payments: `{ id, kind (= type), severity: error\|warning, priority: high\|medium\|low, title, subtitle (= detail ?? ''), icon, outlet_id, at (= created_at), link{type,id} }`, errors first |
| GET | `/admin/activity?outlet_id&limit` | manager/admin/finance | live feed derived from task_events/payment_events/loyalty_ledger/inventory_alerts: `{ id, type, kind: completed\|payment\|quote\|stock\|loyalty\|assigned\|blocked, at, title, subtitle, detail, icon, tone: success\|primary\|warning\|error\|neutral, outlet_id, link }` |
| GET | `/admin/bookings?outlet_id&date&status&search&limit&cursor` | manager/admin/finance | live table: `Booking` rows (`outlet`, `service`, `vehicle`, `customer`, `addons`, `price_label`) + one `work_order` summary (as `/bookings`), the latest `payment` (successful preferred: `{ id, status, receipt_no, amount_cents, method, provider, verified_at }`) and `created_by_name` for walk-ins; `search` matches ref, customer name or plate; `status` is a comma list |
| GET | `/admin/work-orders?outlet_id&status&done_since&limit` | manager/admin/finance | work-order board: active (`queued`, `assigned`, `in_progress`, `blocked`) plus `completed`/`verified` touched since `done_since` (default 00:00 UTC today); `status` (comma list) lists exactly those. Rows: `{ id, ref, outlet{id,name}, booking_id, booking_ref, quotation_id, quotation_ref, customer_id, customer_name, vehicle{id,registration_no,make,model}, service{id,name,category}, status, priority, bay, assignee_id, assignee_name, eta_at, due_at, started_at, completed_at, verified_at, blocked_reason, steps_done, step_count, progress_pct, task_id (first task — the id `/tasks/:id/assign|transition` act on), task_status, events:[{ id, task_id, actor_id, actor_name, event, from_status, to_status, reason, metadata, created_at }], created_at, updated_at }` sorted by priority, due time, creation |
| GET | `/admin/work-orders/:id` | manager/admin/finance | `{ work_order }` in the same shape (403 outside the caller's outlets) |
| CRUD | `/admin/outlets`, `/admin/services`, `/admin/outlets/:id/services/:serviceId` | admin (reads: manager/admin/finance) | audited. Outlet bodies also take the legal / banking identity (`legal_name`, `trading_as`, `company_registration_no`, `vat_number`, `registered_office`, `bank_details{financial_institution, account_name, branch, branch_code, account_number, account_type}`); blank strings are stored as null. Responses: `{ outlet }`, `{ service }`, `{ outlet_service }` |
| GET | `/admin/outlet-services?outlet_id` | manager/admin/finance | `{ data:[{ outlet_id, service_id, price_cents, is_available }] }` — whole matrix, or one outlet (must be visible to the caller); write via `PUT /admin/outlets/:id/services/:serviceId` |
| CRUD | `/admin/users` (`GET` manager/admin, `POST` invite, `PATCH` role/outlets/is_active — admin) | admin | `GET` rows flatten `outlet_ids`, `outlet_names`, `skills`; `POST` → 201 `{ profile, uid, temporary_password, invite_link }`; `PATCH` → `{ profile, outlet_ids }`; sets custom claims; `is_active=false` revokes refresh tokens (SEC-014) |
| GET | `/admin/customers?search&limit&cursor` | manager/admin/finance | access logged (ADM-024/041); `search` matches name, e-mail, phone or plate; rows = profile columns + `vehicle_count`, `booking_count`, `loyalty { tier, balance_points, lifetime_points, tier_since, plan_code, plan_name, membership_status, included_remaining } \| null` |
| GET | `/admin/customers/:id` | manager/admin/finance | `{ customer, vehicle_count, booking_count, loyalty, vehicles[], bookings[] (with outlet/service/vehicle), loyalty_account, ledger[], payments[], membership }` |
| GET | `/admin/loyalty/config` | manager/admin/finance | `{ published, draft }` (`PUT …/draft` → `{ draft }`, `POST …/publish` → `{ published, archived }`, `POST …/discard` → `{ discarded }`) |
| PUT | `/admin/loyalty/config/draft` | manager/admin | `{ tiers (silver/gold/platinum/black; `discount_pct` 0 — discounts live on the plans), rules, change_note }` |
| POST | `/admin/loyalty/config/publish` | admin | draft → published (previous → archived), audited |
| POST | `/admin/loyalty/config/discard` | manager/admin | |
| GET | `/admin/inventory?outlet_id&alerts_first=true\|false` | manager/admin/finance | items as `/inventory` (`outlet_name`, `capacity`, `blocking_work_orders`, `alert`) across the caller's outlets |
| GET | `/admin/staff/performance?outlet_id&period=today\|week\|month\|quarter` | manager/admin | `{ period, from, to, data:[{ staff_id, name, role, outlet_name, tasks_completed, tasks_verified, avg_cycle_minutes, checklist_compliance_pct (null without data), points (lifetime), points_period, rank, delta (rank change vs the previous period), badges:[{code,name,icon,colour,earned_at}] }] }` |
| GET | `/admin/templates`, `POST`, `PUT /:id` | admin (reads: manager/admin) | checklist templates → `{ template }`; `PUT` always creates a new version (`{ template, previous }`); `status` or the shorthand `publish: bool` (false → draft, else published; publishing archives the previous version and re-points services) |
| GET | `/admin/audit?entity_type&entity_id&actor_id&action&limit&cursor` | admin/finance (all), manager (own outlets) | rows gain `actor_name` |
| GET | `/admin/payments?outlet_id&from&to&status&limit&cursor` | manager/admin/finance | `{ range, data:[{ id, booking_id, booking_ref, outlet_id, outlet_name, customer_id, customer_name, provider, method_brand, method_last4, amount_cents, currency, status, receipt_no, failure_reason, verified_at, created_at }], next_cursor }` newest first; finance-safe — no provider tokens/refs or idempotency keys (ADM-061). Same rows as `payments.csv` for the same filters |
| GET | `/admin/reports/summary?outlet_id&from&to` | manager/admin/finance | `{ range, financial:{ revenue_cents, refunds_cents, payments_total, payments_successful, payments_failed, avg_ticket_cents, by_status, by_outlet:[{outlet_id,name,revenue_cents,bookings}], by_service:[{service_id,name,category,revenue_cents,count}] }, operational:{ bookings, created, pending, confirmed, in_service, completed, cancelled, work_orders_completed, on_time_pct, avg_cycle_minutes, checklist_compliance_pct, quotes:{requested,quoted,accepted,declined,expired,converted} }, loyalty:{ points_issued, points_redeemed, points_expired }, inventory:{ items_active, items_below_threshold, items_out_of_stock, open_alerts }, notifications:{ total, delivered, failed, suppressed, delivery_rate_pct } }` — computed from the same queries as the CSV exports so totals reconcile (REP-005). `loyalty`/`notifications` are platform-wide (`outlet_scoped:false`) |
| GET | `/admin/exports/:report.csv?…filters` | manager/admin/finance | `report ∈ bookings|payments|inventory|staff_performance|loyalty|memberships`; header rows include generated_at, filters, scope (REP-007) |
| GET | `/admin/integrations` | manager/admin | `{ data:[{ key, name, status, detail, icon, … }] }` — `supabase {ok, latency_ms}`, `firebase {project_id}`, `payments {provider, sandbox}`, `whatsapp {provider: twilio|sandbox, configured, messaging_service (masked `MG4d8b…1660`), status_callback, enabled}`; never secrets |
| GET | `/admin/notifications?status&channel&recipient_id&template_key&limit&cursor` | manager/admin/finance | delivery log: `{ data:[{ id, recipient_id, recipient_name, channel, template_key, title, body, status, provider_ref, provider_status, provider_error_code, error, attempts, sent_at, delivered_at, read_by_recipient_at, read_at, created_at }], next_cursor }` |
| POST | `/admin/notifications/:id/resend` | manager/admin | re-sends a `failed`/`suppressed` push or WhatsApp row from its stored template + `payload.vars`; bumps `attempts`; audited (`notification.resend`) → `{ notification, outcome:{channel,status} }`; 409 otherwise |
| GET | `/admin/flags`, `PATCH /admin/flags/:key` | `GET` manager/admin, `PATCH` admin | `{ data, effective }` / `{ flag }` |


**Dashboard windows.** `today` / `week` / `month` presets on `/admin/kpis`, `/admin/staff/performance`, `/admin/work-orders` (`done_since` default) and calendar-date filters (`/admin/bookings?date=`, report `from`/`to`) are resolved in the business timezone `Africa/Johannesburg`, not UTC: local midnight 17 Sep = `2026-09-16T22:00:00Z`. Hours in `bookings_by_hour` are bucketed per outlet timezone and cover the **selected period** (today / week / month), with `future` only set on today's chart.

**Keys collected.** `POST /work-orders/:id/pickup/verify` success also sends the customer a push `vehicle_collected` ("Your {{vehicle}} was collected from {{outlet}} at {{time}}", template in migration 0017; payload `{ type:'booking'|'work_order', booking_id, work_order_id, collected_at }`, one per work order). The customer app shows the collection on the booking detail ("Collected") and tracking screen ("Keys released HH:mm") from `booking.work_order.collected_at`.

**Checklist step photos.** Photo-proof steps upload first: `POST /work-orders/:id/photos` (multipart `photo` JPEG/PNG/HEIC/WebP ≤ 10 MB, optional `step_key`; staff of the outlet) → 201 `{ attachment: { id, kind:'step_photo', step_key, mime_type, size_bytes, width, height, url, created_at } }` (attachments row `entity_type:'checklist_step'`, `entity_id:` work order). Then `POST /work-orders/:id/steps/:key { status:'done', attachment_id }`; an unknown id or one belonging to another work order is a 400. `GET /work-orders/:id/photos/:attachmentId` streams the private object to outlet staff. (Multipart parsing reads `req.rawBody` on Cloud Functions, where the platform drains the request stream before the handler runs — the same path serves quotation photo uploads.)

**Work orders for every confirmed job.** A booking gets its work order the moment it is confirmed (walk-in / cash / covered bookings at creation; card bookings when the payment succeeds) with `checked_in_at: null`, so it is on the Work board as "awaiting check-in". `POST /bookings/:id/checkin` then confirms the car on site on that same work order (no duplicate; `created:false`). Accepting a quotation (in-app or via the public link) creates its work order immediately (`work_order_ref` on the quotation; status stays `accepted`); confirming the check-in (`POST /work-orders/:id/checkin`, or the manual `POST /quotations/:id/convert`) marks the quotation `converted`. Counter payments (`POST /payments/record`) accept `quotation_id` instead of `booking_id` (`amount_cents` must equal `quotations.amount_cents`; migration 0016 adds `payments.quotation_id`); `GET /quotations/:id` returns `payment` (successful counter payment) and `amount_due_cents`.

**Check-in gate & auto-assignment.** `work_orders.checked_in_at` / `checked_in_by` (migration 0015) record that the car is on site. Booking check-ins (`POST /bookings/:id/checkin`, walk-in `checkin`) set it at creation; work orders converted from quotations start unchecked and are confirmed with `POST /work-orders/:id/checkin { bay? }` → 201 `{ work_order, task, already }` (200 + `already:true` when repeated; task event `checked_in`, audit `work_order.check_in`). `POST /tasks/:id/assign` refuses unchecked work orders with 409 `validation_error {reason:'not_checked_in', work_order_id}`. Auto-assignment (feature flag `auto_assignment`, Admin → Config → Operations) runs only for checked-in work orders — at creation for booking check-ins, or when the check-in is confirmed. Admin work-order rows carry `checked_in_at` and `checked_in_by_name`.

**Cash on collection.** Feature flag `cash_on_collection` (Admin → Config → Payments; `GET /config` exposes it to the apps without auth alongside `payments_sandbox` / `whatsapp_enabled`). `POST /bookings` takes `payment_method: 'card'|'eft'|'cash'`; `cash` with a total > 0 creates the booking `confirmed` without a payment intent (409 `validation_error {reason:'cash_disabled'}` when the flag is off). `bookings.payment_method` (migration 0014) is returned on every booking shape; the work-order detail's `booking` and the `work_order.booking` expansion on `GET /tasks` carry `payment_method` and `paid` (`paid` is null for non-cash bookings). Staff record the cash at the counter with `POST /payments/record` (method `cash`); `POST /work-orders/:id/pickup/verify` refuses with 409 `validation_error {reason:'payment_due', amount_cents, booking_id, method:'cash'}` until then.

**Custom claims.** Firebase ID tokens carry `{ role: 'authenticated', app_role: <sparkling role>, outlet_ids: uuid[] }`. Supabase treats the reserved `role` claim as the Postgres role (so it must be `authenticated`; anything else breaks PostgREST / Realtime with `role "…" does not exist`); the Sparkling role lives in `app_role` and RLS `app.role()` reads it (migration 0013). `POST /auth/session` re-mints the claims when they drift and returns `claims_updated: true` so clients force-refresh the token.

**Presence.** `profiles.last_seen_at` is touched by any authenticated request (throttled to one write per 2 minutes). `PUT /staff/me/availability { status: available|busy|break|off }` → `{ availability }` upserts `staff_availability`; `GET /admin/users` returns `availability` per user. `profiles` and `staff_availability` are in the realtime publication so the admin Staff page updates live.

**Envelopes.** Single-entity responses are wrapped (`{ customer }`, `{ vehicle }`, `{ booking, duplicate }`, `{ quotation, … }`, `{ task }`, `{ profile }`, …); list responses use `{ data, next_cursor }`. The Dart client unwraps these with `SparklingApi._entity(d, key)` and the admin `HttpApi` per method — add the key when introducing a new route.

**Phone numbers.** Mobile numbers are stored and returned in E.164 (`+27821234567`). Every phone input (`POST /walk-in/customers`, `PATCH /me`, `POST/PATCH /admin/users`) accepts any country: the number should be entered **with its country code** (`+44 7911 123456`, `0044…`, `27 82…`); bare South African local numbers (`082 123 4567`) are still accepted for older clients. Numbers are validated with libphonenumber per country — an invalid number gets 400 `validation_error` with the message "Enter the mobile number with its country code, e.g. +27 82 123 4567". WhatsApp sends to any country Twilio supports.

**Staff accounts (ADM-010).** `POST /auth/session` with `app: 'staff' | 'admin'` never creates a profile: an account with no profile (or a customer profile) gets 403 `forbidden {reason:'not_staff'}`; only `app: 'customer'` auto-creates a customer profile.  `POST /admin/users` `{ email, full_name, role, phone?, outlet_ids[], skills[], invite?: 'password'|'link' }` creates (or reuses) the Firebase Auth user with a **temporary password**, the profile (`must_change_password = true`, migration 0012), outlet scope, skills and custom claims → `201 { profile, uid, temporary_password, invite_link|null }`. The admin hands the temporary password over; the staff app (any staff role) and the admin dashboard (manager/admin/finance/supervisor) both force a password change on the first sign-in: the client calls Firebase `updatePassword`, signs in again with the new password (fresh `auth_time`) and then `POST /auth/password-changed` → `{ profile }` (409 `{reason:'stale_session'}` when the token's `auth_time` is older than 15 min). `POST /admin/users/:id/reset-password` → `{ profile, temporary_password }` issues a new temporary password, revokes refresh tokens and re-flags the profile. `profile.must_change_password` is returned by `POST /auth/session` and `GET /me`.

### Notifications
| GET | `/notifications?limit&cursor` | any | own |
| POST | `/notifications/:id/read` | any | |
| POST | `/notifications/twilio/status` | Twilio (form-encoded, `X-Twilio-Signature`) | delivery receipts: maps `queued|accepted|sending→queued`, `sent→sent`, `delivered→delivered` (+`delivered_at`), `read→delivered` (+`read_by_recipient_at`), `failed|undelivered→failed` (+`ErrorCode`/`ErrorMessage` → `provider_error_code`/`error`); matched by `provider_ref = MessageSid`; idempotent (replays / stale / unknown SIDs → 200 `{ignored:true}`); 403 on a bad signature or when `TWILIO_AUTH_TOKEN` is unset |

**WhatsApp via Twilio (INT-002).** `notification_templates` rows with `provider='twilio'` + `provider_template_sid` (`HX…`) are sent as Content templates: `provider_variables` (`{"1":"first_name","2":"quotation_id"}`) is resolved against the render context. `quote_ready` supplies `first_name` (from the profile) + `quotation_id`; `service_ready`/`pickup_otp` supply `otp`, `vehicle`, `outlet`. The rendered `body` is still stored for the in-app inbox. Sending is gated by the `whatsapp_enabled` flag and `whatsapp_opt_in`; numbers are normalised to E.164 (`082…` → `+2782…`).

## Realtime channels (client-side, Supabase)

| Client | Subscription |
|---|---|
| Customer | `bookings` (customer_id=eq.<uid>), `work_orders` (customer_id), `checklist_step_results` (work_order_id in own), `loyalty_ledger`, `notifications`, `memberships`, `membership_usage`, `membership_invoices` (customer_id / own membership) |
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

## Reference payload — `GET /memberships/me` (Thabo, Gold / G1, 1 of 4 used)

```json
{
  "membership": { "id": "c4000000-…-0001", "ref": "MEM-2026-0001", "customer_id": "seed_thabo", "plan_id": "c1000000-…-0001", "status": "active",
                  "started_at": "2026-06-11T09:00:00Z", "current_period_start": "2026-09-09T09:00:00Z", "current_period_end": "2026-10-09T09:00:00Z",
                  "cancel_at_period_end": false, "cancelled_at": null, "ended_at": null, "next_plan_id": null, "payment_method": "card" },
  "plan": { "id": "c1000000-…-0001", "code": "gold", "tier": "gold", "name": "Gold", "tagline": "4 Sparkling Washes or 8 Exterior Washes a month",
            "monthly_fee_cents": 29500, "discount_pct": 10, "discount_scope": "other_services", "discount_note": "10% discount on any other Sparkling service", "color": "gold",
            "groups": [ { "id": "c2000000-…-0001", "code": "washes", "name": "Monthly washes", "selection": "choose_one",
                          "entitlements": [ { "id": "c3000000-…-0001", "code": "G1", "label": "4 × Sparkling Wash", "quantity": 4, "period": "month", "services": [ { "id": "…", "code": "SPARKLING_WASH", "name": "Sparkling Wash", "is_primary": true } ] },
                                            { "id": "c3000000-…-0002", "code": "G2", "label": "8 × Exterior Wash", "quantity": 8, "period": "month", "services": [ { "code": "EXT_WASH", "is_primary": true }, { "code": "EXT_WASH_TYRE", "is_primary": false }, { "code": "WASH_GO", "is_primary": false } ] } ] } ] },
  "next_plan": null,
  "selections": { "washes": "G1" },
  "allowances": [ { "entitlement_id": "c3000000-…-0001", "entitlement_code": "G1", "group_code": "washes", "label": "4 × Sparkling Wash", "quantity": 4, "used": 1, "remaining": 3,
                    "period": "month", "period_start": "2026-09-09T09:00:00Z", "period_end": "2026-10-09T09:00:00Z" } ],
  "open_invoice": null,
  "invoices": [ { "id": "c5000000-…-0101", "ref": "MINV-2026-0101", "period_start": "2026-09-09T09:00:00Z", "period_end": "2026-10-09T09:00:00Z", "amount_cents": 29500, "status": "paid", "due_at": "…", "paid_at": "…", "payment_id": "60000000-…-0101" } ],
  "next_renewal_at": "2026-10-09T09:00:00Z",
  "benefits_summary": "3 of 4 Sparkling Washes left · 10% discount on any other Sparkling service"
}
```

## Reference payload — pricing `membership` block (`POST /bookings`, Sparkling Wash + tyre shine, Thabo)

```json
{
  "price_cents": 18000, "base_cents": 15000, "addons_cents": 3000, "discount_cents": 15000, "vat_cents": 0, "total_cents": 3000,
  "discount_label": "Included in Gold · 2 of 4 left", "points_pending": 3, "tier": "gold",
  "membership": { "membership_id": "c4000000-…-0001", "plan_code": "gold", "plan_name": "Gold", "benefit": "included",
                  "entitlement_id": "c3000000-…-0001", "entitlement_code": "G1", "remaining_after": 2, "period_end": "2026-10-09T09:00:00Z" }
}
```

A Full Valet for the same member prices as `{ "discount_cents": 2200, "total_cents": 19800, "discount_label": "Gold −10%", "membership": { "benefit": "discount", "entitlement_code": null, "remaining_after": null, … } }`; once the four washes are used the wash prices at full (`"benefit": null`, Gold's discount covers *other* services only), while a Platinum member with an exhausted allowance gets `"Platinum −10%"` on the wash itself. A `past_due` member and a non-member both get `"membership": null`.
