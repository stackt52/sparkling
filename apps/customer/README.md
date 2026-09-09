# Sparkling — Customer app

Flutter (Android + iOS) customer app for the Sparkling car-wash / auto-body
platform: bookings, licence-disc scanning (PDF417), live service tracking,
repair quotes and loyalty. Built on the shared `sparkling_ui` design system and
`sparkling_core` domain package (see `docs/ARCHITECTURE.md`).

## Run

```sh
export PATH="/opt/homebrew/bin:$PATH"
cd apps/customer
flutter pub get

# Demo mode — fully on-device data (Thabo Nkosi, Gold tier), no backend needed
flutter run -d "iPhone 16" --dart-define-from-file=env/demo.json

# Dev mode — Firebase Auth + Cloud Functions emulator + Supabase realtime
flutter run --dart-define-from-file=env/dev.json
```

`env/*.json` keys: `DEMO_MODE`, `APP_NAME`, `API_BASE_URL`, `SUPABASE_URL`,
`SUPABASE_ANON_KEY` (publishable key only — never a service role key).

## Verify

```sh
flutter analyze
flutter test
flutter build ios --simulator --no-codesign --dart-define-from-file=env/demo.json
flutter build apk --debug --dart-define-from-file=env/demo.json
```

Screenshots of every screen (iPhone 16 simulator, demo mode) live in
`screenshots/`.

## Structure

```
lib/main.dart                 Firebase init (live only) → SparklingCore.bootstrap → CustomerApp
lib/app/                      app widget, router (go_router), session (auth + profile),
                              settings (theme override), push registration
lib/widgets/                  shared chrome: ScreenHeader, BottomActionBar, AsyncView …
lib/features/auth             sign in / sign up / reset (+ "Continue as Thabo" in demo)
lib/features/home             1a / 1k home
lib/features/booking          1b service → 1c slot → 1f pay → 1g confirmed (persisted draft)
lib/features/bookings         list (paged) + detail (cancel / reschedule)
lib/features/tracking         1h / 1l live timeline with offline degradation
lib/features/vehicles         garage, manual form, 1d PDF417 scanner, 1e scan review
lib/features/quotes           1j request, list, detail (accept / decline)
lib/features/loyalty          1i rewards, redeem, ledger
lib/features/notifications    inbox
lib/features/profile          preferences (PATCH /me), appearance, sign out
lib/features/sync             sync chip + offline queue status
```

State is plain `ChangeNotifier` / streams from `sparkling_core` repositories;
no code generation. Booking and quote drafts persist in `DraftStore` (UX-009).

## App icon

Generated from `assets/icon/app_icon.png` (navy `#203060` + logo) with
`dart run flutter_launcher_icons`.
