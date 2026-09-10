# Sparkling Staff (Outlet Staff app)

Flutter app for outlet technicians, supervisors and managers (SRS STF-*):
task list, checklist execution, PDF417 licence-disc scanning, supervisor
ops, leaderboard, inventory, offline queue and sync centre. Android phone +
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
                           "Import photo" via analyzeImage), review + booking check-in
lib/features/ops           2c supervisor ops, 2d assign sheet
lib/features/leaderboard   2e podium, ranks, badges
lib/features/inventory     2f stock, usage sheet, manager threshold edit
lib/features/sync          sync centre (queued ops, retry, last sync)
lib/features/profile       outlets, availability, theme, motion/haptics, sign out
lib/widgets/               app-local widgets (ScreenHeader, SegmentedPills, KpiTile, AvatarTile …)
```

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
