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

# Dev — Firebase Auth + Cloud Functions emulator (10.0.2.2 = host from the AVD) + Supabase realtime
flutter run --dart-define-from-file=env/dev.json
```

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
lib/features/checklist     2b checklist execution, step inputs, blocked-reason sheet
lib/features/scanner       PDF417 scan (mobile_scanner), review + booking check-in
lib/features/ops           2c supervisor ops, 2d assign sheet
lib/features/leaderboard   2e podium, ranks, badges
lib/features/inventory     2f stock, usage sheet, manager threshold edit
lib/features/sync          sync centre (queued ops, retry, last sync)
lib/features/profile       outlets, availability, theme, motion/haptics, sign out
lib/widgets/               app-local widgets (ScreenHeader, SegmentedPills, KpiTile, AvatarTile …)
```

## Notes

* Every mutation goes through `Repositories` — offline they are queued with a
  `client_op_id` and replayed through `POST /sync/batch`; the header sync
  chip and the sync centre reflect the queue (STF-062, NFR-005).
* Server 409s (`conflict` / `invalid_transition`) open a dialog explaining the
  server state and refresh the screen (STF-035).
* Layouts switch to two-pane master-detail at ≥ 840 dp (UX-005).
