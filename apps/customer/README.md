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

# Dev mode — live Firebase Auth (project sparkling-4e89d) + Cloud Functions emulator + Supabase realtime
flutter run --dart-define-from-file=env/dev.json

# Local auth — Firebase Auth *emulator* (no real accounts are created)
(cd ../.. && firebase emulators:start --only auth --project sparkling-4e89d)   # in another terminal
flutter run -d "iPhone 16" --dart-define-from-file=env/emulator.json           # iOS simulator / macOS
flutter run -d emulator-5554 --dart-define-from-file=env/emulator-android.json # Android AVD (10.0.2.2 = host)
```

`env/*.json` keys: `DEMO_MODE`, `APP_NAME`, `API_BASE_URL`, `SUPABASE_URL`,
`SUPABASE_ANON_KEY` (publishable key only — never a service role key),
`AUTH_EMULATOR_HOST` (`host:port` of the Firebase Auth emulator; empty = live
Firebase).

## Authentication

* Firebase Auth e-mail/password + Google (`signInWithProvider(GoogleAuthProvider())`,
  no extra plugin). iOS needs the two `CFBundleURLTypes` schemes in
  `ios/Runner/Info.plist` (reversed client id + `app-1-…` Firebase app id) and
  `GoogleService-Info.plist` embedded in the Runner target — both are in place.
  Android needs the debug/release SHA-1 registered in the Firebase console
  (`google-services.json` carries the resulting `oauth_client`).
* After sign-in the app calls `POST /auth/session` (mints `role` claims,
  returns the profile). If the API is down the user *stays signed in* and the
  home screen shows a "Couldn't reach Sparkling servers" banner with Retry.
* Google sign-in cannot complete on the iOS simulator / an AVD without Google
  Play; the app shows a clear "not available on this device" message.
* Password reset links from the Auth emulator are printed in the emulator's
  terminal log instead of being e-mailed.

## Verify

```sh
flutter analyze
flutter test
flutter build ios --simulator --no-codesign --dart-define-from-file=env/demo.json
flutter build apk --debug --dart-define-from-file=env/demo.json
```

### Licence-disc scanner (1d)

`lib/features/vehicles/scan_screen.dart` uses `mobile_scanner` restricted to
`BarcodeFormat.pdf417` with `cameraResolution: 1920×1080` (Android; iOS picks
its own preset) and a `scanWindow` that matches the viewfinder, so only the
disc area is decoded. Besides live scanning there is an **Import photo**
action (header tile next to the torch, and a text button in the failure /
no-camera states) that runs `MobileScannerController.analyzeImage` on a
gallery image and feeds the same parse → review flow. Photos without a
readable disc get the BAR-006 sheet ("Couldn't read the disc from that
photo…") with Retry / Enter manually. Real-disc layout and decode findings:
`docs/PDF417.md`.

On-device decoder test with the five real disc photos
(`integration_test/fixtures/disc_1…5.jpeg`, embedded as base64 in
`fixtures/disc_fixtures.dart` so nothing ships in the app bundle):

```sh
flutter test integration_test/disc_photo_decode_test.dart -d emulator-5554 --dart-define-from-file=env/demo.json   # Android / ML Kit
flutter test integration_test/disc_photo_decode_test.dart -d "iPhone 16" --dart-define-from-file=env/demo.json    # iOS — see note
```

Results per platform are in `integration_test/RESULTS.md`. Note that
`mobile_scanner` refuses `analyzeImage` on the iOS *Simulator*
(`MOBILE_SCANNER_UNSUPPORTED_OPERATION`); the test reports that and skips, so
the Apple Vision run needs a physical iPhone.

Screenshots of every screen (iPhone 16 simulator, demo mode) live in
`screenshots/`; `screenshots/auth-*.png` were taken against the Firebase Auth
emulator (`env/emulator.json`, API not running).

## Vehicle collection (pickup OTP)

When a supervisor verifies the work, the API issues a 5-digit **collection
OTP** to the customer by WhatsApp (Twilio) and push, and `GET /bookings/:id`
exposes it as `work_order.pickup_otp` — only to the owning customer, only
while the booking is `completed` and `collected_at` is null.

* **Home hero** — a booking awaiting collection beats the in-service / next
  booking heroes: "Ready for collection · OTP 73104" with a **Show OTP** CTA.
* **Tracking screen / booking detail** — `PickupOtpCard`
  (`lib/features/tracking/pickup_otp_card.dart`, `successContainer` tone)
  shows the code in large mono digits, "Show this at the counter to collect
  your keys", and notes that it was also sent by WhatsApp / push. Tapping the
  digits copies them. Once staff verify the code the card disappears, the
  timeline gains a "Keys released" entry and the detail shows **Collected**.
* **Notifications inbox** — rows whose provider reported delivery
  (`status=delivered`, `provider_status`, `delivered_at`) show a green
  double-tick; `pickup_otp` messages use a key icon.

Demo data: Thabo's `SPK-2026-0098` (Express Wash earlier today, verified) is
awaiting collection with OTP `73104`; `SPK-2026-0067` was collected weeks ago
and shows no OTP. `screenshots/pickup-otp.png` is the tracking screen.

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
lib/features/tracking         1h / 1l live timeline with offline degradation + pickup OTP card
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
