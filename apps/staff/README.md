# Sparkling Staff (Outlet Staff app)

Flutter app for outlet technicians, supervisors and managers (SRS STF-*):
task list, checklist execution, PDF417 licence-disc scanning, walk-in
customer registration + booking, membership enrolment at the counter,
staff-raised repair quotes with damage photos, supervisor ops, leaderboard,
inventory, offline queue and sync centre. Android phone +
tablet, dark-first, built on `packages/sparkling_ui` (design system) and
`packages/sparkling_core` (models, API, offline queue, realtime).

## Run

```sh
export PATH=/opt/homebrew/bin:$PATH
cd apps/staff
flutter pub get

# Demo mode — in-memory data, no Firebase / network (persona picker on sign-out)
flutter run --dart-define-from-file=env/demo.json

# Dev — live Firebase Auth + Cloud Functions emulator (10.0.2.2 = host from the AVD) + Supabase realtime
flutter run --dart-define-from-file=env/dev.json

# Local auth — Firebase Auth *emulator*, no real accounts
(cd ../.. && firebase emulators:start --only auth --project sparkling-4e89d)   # in another terminal
flutter run -d emulator-5554 --dart-define-from-file=env/emulator-android.json # AVD → 10.0.2.2:9099
flutter run -d macos --dart-define-from-file=env/emulator.json                 # host → 127.0.0.1:9099
```

`env/*.json` keys: `DEMO_MODE`, `APP_NAME`, `API_BASE_URL`, `SUPABASE_URL`,
`SUPABASE_ANON_KEY`, `AUTH_EMULATOR_HOST` (empty = live Firebase).

## Authentication (STF-001 / STF-004)

Sign in with e-mail/password or Google. The order is *sign in → `POST
/auth/session` → check the returned profile's role*: the API mints the
`role` / `outlet_ids` custom claims during that call, so a first sign-in has
no claims yet. Accounts whose profile is not staff (or that cannot be
verified because the API is unreachable and no claims are cached) are signed
out with "This account is not an outlet staff account." — which is exactly
what you see on the Auth emulator without the Functions emulator running.
Idle lock re-authenticates with the password, or re-runs the Google flow for
Google-only accounts.

Demo personas: **Pieter** (technician), **Johan** (supervisor), **Ayesha**
(manager). Any password works in demo mode; the seeded e-mails
(`pieter@sparkling.co.za`, …) also work in the sign-in form.

## Verify

```sh
flutter analyze
flutter test
flutter build apk --debug --dart-define-from-file=env/demo.json
```

Widget tests run on the demo repositories (`SparklingTypography.useGoogleFonts = false`).

## Structure

```
lib/main.dart              Firebase init (live only) → SparklingCore.bootstrap → StaffApp
lib/app/                   StaffApp (theme, motion scope), router (go_router), session
                           (auth, idle lock, FCM), sync status, device settings
lib/features/auth          sign-in + demo persona picker, session-timeout lock (STF-004)
lib/features/tasks         2a/2g task list, task card, tablet master-detail
lib/features/checklist     2b checklist execution, step inputs, blocked-reason sheet, hand-over (OTP) sheet
lib/features/scanner       PDF417 scan (mobile_scanner, 1080p + viewfinder scanWindow,
                           "Import photo" via analyzeImage), review + booking check-in;
                           `ScanScreen(pickResult: true)` pops with the DiscScanResult (walk-in)
lib/features/walk_in       walk-in booking flow: WalkInFlowController (draft in DraftStore
                           `walk_in_draft`), 4 steps (customer / vehicle / service & time /
                           payment & confirm), confirmation, shared booking widgets;
                           CustomerStep / VehicleStep are shared with the quote flow
                           through the `CustomerVehicleFlow` base; membership_sheet.dart
                           = the customer's Membership tile / sheet + "Enrol in a plan"
lib/features/quote         raise-quote flow: RaiseQuoteController (draft `raise_quote_draft`),
                           items step (attention items, damage photos, validity), review &
                           send, confirmation (public link / PDF), staff quote detail,
                           AuthedImage (bearer-authed attachment loader)
lib/features/ops           2c supervisor ops, 2d assign sheet
lib/features/leaderboard   2e podium, ranks, badges
lib/features/inventory     2f stock, usage sheet, manager threshold edit
lib/features/sync          sync centre (queued ops, retry, last sync)
lib/features/profile       outlets, availability, theme, motion/haptics, sign out
lib/widgets/               app-local widgets (ScreenHeader, SegmentedPills, KpiTile, AvatarTile …)
```

## Walk-in booking (STF-010/012)

Staff can register a customer at the counter and book (and check in) a
wash without the customer app. Entry points: the **Walk-in booking** FAB on
the task list (above "Scan disc"), **Create walk-in booking** on the scan
review screen when the plate has no booking today (the scanned disc is
carried into the flow), and the **Walk-in booking** quick action on the
supervisor ops screen. Route `/walk-in` (+ `/walk-in/scan`,
`/walk-in/confirmation/:bookingId`); all staff roles may use it.

Four steps (`lib/features/walk_in/`, `Step n of 4` header + progress strip,
mirroring the customer booking flow 1b/1c/1f/1g):

1. **Customer** — search by name / phone / e-mail / plate
   (`GET /staff/customers?search`, 300 ms debounce, ≥ 2 chars) or **Register
   new customer** (`POST /staff/customers`: name, `+27`-normalised mobile,
   optional e-mail, WhatsApp opt-in on / marketing off, POPIA note). A `409
   conflict` opens the "Already registered" sheet offering the existing
   customer (`ApiException.existingCustomer`).
2. **Vehicle** — the customer's vehicles, **Scan disc** (returns a
   `DiscScanResult`) or **Add manually** →
   `POST /staff/customers/:id/vehicles`; a duplicate 409 selects the existing
   vehicle.
3. **Service & time** — the staff member's outlet (navy card, picker only
   when they work at several), the outlet catalogue grouped (Car Wash
   Options / Combinations / Auto Body Repair) with prices resolved for the
   customer's vehicle size ("From R 150", "excl. VAT" for auto body),
   "Includes: …" on composites, **Add-ons** checkbox cards for the chosen
   group, **Raise quote instead** on by-quote offers (jumps to the raise-quote
   flow with customer + vehicle carried over), "Earn N pts", **Now (walk-in)**
   or **Pick a slot** (date chips + slot grid from `GET /availability`),
   summary banner with the membership benefit estimate (see below).
4. **Payment & confirm** — order summary, **Cash** / **Card terminal**
   (optional slip reference) / **Customer pays in app**, **Check in now**
   switch with bay + P1/P2/P3, then `POST /bookings` (`walk_in: true`,
   optional `checkin`) → `POST /payments/record` (cash / card). The
   confirmation shows the ref, receipt number, work order and **Open
   checklist**. "No bay free" (409) sends the flow back to the slot picker.

The draft (`DraftStore` key `walk_in_draft`) keeps a stable `client_op_id`
and payment `idempotency_key`, so retries are idempotent and a killed app
resumes at the furthest completed step. Offline, the booking and payment are
queued (`booking.create_walk_in`, `payment.record`; the payment carries
`booking_client_op_id` so the batch can resolve the booking created just
before it) and the confirmation shows the queued state.

The vehicle step's manual form has a **Small / Large / Bike** selector and a
scanned disc derives the size from its description (`size_class`); vehicle
cards show the size chip. The payment step and confirmation list add-ons and
a VAT line; the plan discount applies to base + add-ons.

Demo: the persona outlet is **Sparkling Auto Care Centre Menlyn**. Search
"Thabo" (Gold · 3 washes left, two plates), register anyone with a fresh
phone number, book **Exterior wash only** now, pay cash → receipt
`RCP-7xxxx`; `test/walk_in_test.dart` walks the whole flow plus the capacity
error and `test/catalogue_test.dart` books Sipho's Hilux (large) for *Auto
Detailing Interior* + odour add-on (no plan discount — Platinum discounts
only its selected plan services), checks the VAT total on an auto-body offer
and the by-quote → raise-quote jump. Screenshots:
`screenshots/walkin-{1-customer,1-register,2-vehicle,3-service,4-payment,5-confirmation}.png`,
`screenshots/catalogue-walkin-services.png`.

## Membership plans at the counter (docs/MEMBERSHIPS.md)

The loyalty tier is the customer's membership plan (Silver = none). In the
walk-in flow:

* **Customer step** — search results and the customer card show the plan
  pill with the remaining washes ("Gold · 3 washes left", from
  `loyalty.plan_code / plan_name / included_remaining`). Below the card a
  **Membership** tile (`CustomerMembershipTile`) summarises the plan
  ("Black member · 8 of 10 sparkling washes · 0 of 1 auto detail complete ·
  renews 17 Sep") or offers **Enrol** for customers without one; tapping it
  opens the **Membership** sheet: plan card with allowance rings, renewal /
  open invoice and **Record renewal payment · R 850** (cash / card terminal /
  EFT → `POST /staff/memberships/:id/invoices/:invoiceId/record-payment`,
  rolls the period) or **Enrol in a plan**.
* **Enrol in a plan** sheet — pick Gold / Platinum / Black (plan cards in the
  plan colour), the `choose_one` options (e.g. B1 washes + B3 detail; the
  annual coating is listed as included), **Cash / Card terminal / EFT**,
  then **Enrol · R 850.00 cash** → `POST /staff/customers/:id/membership`.
  The membership is active immediately with a paid invoice and a POS
  payment / receipt; offline it is queued as `membership.enrol`.
* **Service step** — covered services show **Included in plan · 3 of 4
  left** with the base struck through and **R 0**; other services carry the
  plan discount tag ("Gold −10%"). The bottom bar and summary banner use the
  same estimate ("Included in Gold · 2 of 4 left").
* **Payment step** — the summary shows the benefit line; a fully covered
  wash has **Nothing to pay** (no payment options, no `payment.record`), a
  covered detail with an odour add-on totals the add-on only (R 180). The
  confirmation lists the benefit and "Nothing to pay · included in plan".

Demo: "Zanele" is Black (renewal due in 3 days → record it at the counter),
"Thabo" Gold (Sparkling Wash included), a newly registered customer can be
enrolled in Black and booked for *Auto detailing complete & polish* + odour
add-on at R 180. `test/membership_test.dart` covers the customer step's
pill / tile / renewal payment, enrol → covered detail at add-on price and
the covered Sparkling Wash with nothing to pay. Screenshots:
`screenshots/membership-enrol.png`, `screenshots/membership-enrol-plan.png`.

## Raise quote (STF-010/012, CUS-030..034)

Staff can raise an itemised repair quote for a walk-in customer in one
step — no customer request needed. Entry points: the **Raise quote** FAB on
the task list (speed-dial column above Walk-in booking / Scan disc), the
**Raise quote** quick action on the supervisor ops screen, **Raise quote** on
the scan review screen when the plate has no booking (disc carried over),
and **Raise a quote for this vehicle** on the walk-in confirmation (customer
+ vehicle prefilled). Routes: `/quote/new`, `/quote/confirmation/:id`,
`/quotes/:id`.

Four steps (`lib/features/quote/`, `Step n of 4` header + progress strip):

1. **Customer** and 2. **Vehicle** — the walk-in steps (search / register,
   pick / scan / add), reused via `CustomerVehicleFlow`. The item sheet's
   service picker lists the outlet's Auto Body offers with "From R x excl.
   VAT" and picking one prefills the amount VAT-inclusive (price × 1.15);
   category chips link the matching catalogue code (Dent → `PDR`, Scratch /
   Panel → `SPOT_REPAIR`, Bumper → `BUMPER_SCUFF`, Paint → `FLAT_POLISH`,
   Glass → `WINDSHIELD_REPAIR`).
3. **What needs attention** — attention items (sheet: category chips Dent /
   Scratch / Bumper / Panel / Paint / Glass / Other, title, description,
   optional auto-body service from `outletServices` filtered to
   `auto_body`, amount in rand; picking a category suggests the title and
   service), running total, overall description, **damage photos** (camera
   or gallery via `image_picker`, per-photo caption sheet, remove badge,
   max 10, 88 px striped tiles per mockup 1j), a note for the customer and
   **valid until** (7 / 14 / 30 day chips + date picker, default +14 days).
4. **Review & send** — summary card (customer, mono plate, outlet, items
   table, total, validity), photo thumbnails, **Send to customer now (push +
   WhatsApp)** switch (default on), CTA **Raise quote · R x** →
   `POST /quotations` (`items[]`, `valid_until`, `items_note`,
   `send_to_customer`, `client_op_id`) → sequential
   `POST /quotations/:id/photos` (multipart `photo` + `caption`; failures
   are skipped and reported) → confirmation.

The confirmation shows the ref, total, "Sent to <first name> on WhatsApp",
the public link (`public_url`, staff only) with **Copy link** / **Share**
(`share_plus`), **Resend WhatsApp** (`POST /quotations/:id/share`, rotates
the token, 60 s cooldown → `rate_limited`), **Download PDF**
(`GET /quotations/:id/pdf` → temp file → share sheet), **View quote**,
**New quote** and **Done**. The staff quote detail (`/quotes/:id`, also from
the **Quotes** section on the ops screen) lists items, the damage-photo grid
(`AuthedImage` fetches bytes with the bearer token; removable until the
customer decides), a status timeline (raised → sent → decided with the
`decision_source` label "Accepted via link by <name>" / "Accepted in app"
→ work order), link / PDF actions and **Convert to work order** for
supervisors and managers once accepted.

The draft (`DraftStore` key `raise_quote_draft`) keeps a stable
`client_op_id` (idempotent retries) and survives restarts; photo file paths
are kept, in-memory bytes are not. Offline, the quote is queued as
`quotation.raise` and the photos stay on the device (`LocalCache`
`deferred_photos:<op>`) until the sync batch applies the operation — the
repository then uploads them best-effort.

Demo: raise a quote for any customer → `QT-2026-00xx`, public link
`https://demo.sparkling.local/q/<token>`, photos served from memory
(`demo://photo/<id>`), placeholder PDF. `test/raise_quote_test.dart` walks
the whole flow (register → vehicle → item with service → photo → raise →
confirmation → detail) plus the ops entry points and convert.
Screenshots: `screenshots/quote-{1-customer,3-items,3-photos,4-review,5-confirmation,6-detail}.png`.

## Vehicle hand-over (collection OTP)

Verified work orders wait for the customer to collect. The customer reads
their 5-digit OTP (sent by WhatsApp / push and shown in the customer app) at
the counter; staff type it into the **Hand over vehicle** sheet
(`lib/features/checklist/handover_sheet.dart`) which calls
`POST /work-orders/:id/pickup/verify { otp }`:

* success → green check state "Keys released · collected at HH:MM" and the
  task / checklist show the release time (`collected_at`);
* `409 invalid_otp` → error with `details.attempts_left`;
* `429 rate_limited` after five wrong codes → explains the lock and offers
  **Resend OTP to customer** (`POST /work-orders/:id/pickup/resend`, 60 s
  cooldown, issues a fresh code by WhatsApp).

The sheet opens from the task card in the **Done** list, from the checklist
screen of a verified work order (also in the tablet detail pane), and from the
supervisor ops screen's **Done today** list. Verification is never queued
offline. Demo: `WO-2026-4822` (Naledi) verifies with `48213`; Thabo's
`WO-2026-4820` with `73104`. `screenshots/handover-otp.png` shows a
successful verification.

## Notes

* Disc scanning (`lib/features/scanner/scan_screen.dart`): `mobile_scanner`
  PDF417-only, `cameraResolution` 1920×1080 on Android, `scanWindow` matched to
  the viewfinder. **Import photo** (tile next to the torch; text button in the
  error / no-camera states) decodes a gallery image with
  `MobileScannerController.analyzeImage` and reuses the parse → review flow;
  unreadable photos show the BAR-006 sheet with Retry / Enter manually. The
  on-device decode results for the real sample photos are in
  `apps/customer/integration_test/RESULTS.md`; see `docs/PDF417.md`.
* Every mutation goes through `Repositories` — offline they are queued with a
  `client_op_id` and replayed through `POST /sync/batch`; the header sync
  chip and the sync centre reflect the queue (STF-062, NFR-005).
* Server 409s (`conflict` / `invalid_transition`) open a dialog explaining the
  server state and refresh the screen (STF-035).
* Layouts switch to two-pane master-detail at ≥ 840 dp (UX-005).
