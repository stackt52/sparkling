# Sparkling — Customer app

Flutter (Android + iOS) customer app for the Sparkling car-wash / auto-body
platform: bookings, licence-disc scanning (PDF417), live service tracking,
repair quotes, membership plans and loyalty points. Built on the shared
`sparkling_ui` design system and `sparkling_core` domain package (see
`docs/ARCHITECTURE.md`).

## Run

```sh
export PATH="/opt/homebrew/bin:$PATH"
cd apps/customer
flutter pub get

# Boot the simulator first whenever it's shut down.
xcrun simctl boot "iPhone 16" && open -a Simulator

# Demo mode — fully on-device data (Thabo Nkosi, Gold member), no backend needed
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

## Mobile number (any country)

**Profile → Your details** edits the name and mobile number with
`PhoneNumberField` (sparkling_ui): a country chip (flag + `+27`) opens a
searchable sheet of all countries (default South Africa), the national
number is grouped live (`82 123 4567`), a leading trunk `0` is dropped and
pasting a full `+44 7400 123456` switches the country. The number is saved
as E.164 (`PATCH /me` `phone: "+447400123456"`); anything that is not a
mobile number for the chosen country shows "Enter a valid <Country> mobile
number" inline, and the API / demo store reject it with 400
`validation_error` "Enter the mobile number with its country code, e.g.
+27 82 123 4567". Numbers are displayed with `Phone.format`
(`+27 83 111 2222`). `test/profile_test.dart` saves a UK number and checks
the validation; screenshot: `screenshots/phone-field.png` (the details
sheet with the country picker open).

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

Demo data: Thabo's `SPK-2026-0098` (exterior wash earlier today, verified) is
awaiting collection with OTP `73104`; `SPK-2026-0067` was collected weeks ago
and shows no OTP. `screenshots/pickup-otp.png` is the tracking screen.

## Outlet catalogue & pricing (docs/API.md "Catalogue pricing model")

The demo store mirrors the real catalogue (`backend/supabase/seed_catalogue.sql`,
generated into `packages/sparkling_core/lib/src/repositories/demo_catalogue.dart`):
five outlets — **Menlyn** (MEN), **Glen Village** (GLV), **Potchefstroom**
(POT), **Amanzimtoti** (TOT), **Rustenburg** (RUS) — and 43 canonical
services in the groups *Car Wash Options*, *Combinations* and *Auto Body
Repair*, each outlet with its own wording and small / large / general prices.

* **Vehicle size** — the add-vehicle form and the scan review carry a
  **Small / Large / Bike** selector (prefilled from the disc description:
  hatch / sedan → small, station wagon / SUV / bakkie / bus → large,
  motorcycle → bike) and vehicle cards show the size chip. It is sent as
  `size_class` and picks the small / large price.
* **Service select (1b)** — offers are grouped under section headers,
  prices are resolved for the selected vehicle's size ("From R 150"),
  composites show "Includes: a · b · c", auto-body offers carry the
  "excl. VAT" note, **by-quote** cards open the quote request with the
  service preselected, and choosing a service in a group with add-ons
  (Combinations → *Add to any Combo: Odour Removal*) shows an **Add-ons**
  section of checkbox cards. The bottom bar totals base + add-ons (+ 15 % VAT
  on `excl` offers).
* **Payment / confirmation / detail / tracking** list the add-ons, a VAT
  line and the tier discount on base + add-ons; `POST /bookings` carries
  `vehicle_size` + `addon_service_ids`, and a 409 `validation_error`
  `{reason:'by_quote'}` routes to the quote request.

Demo: Thabo's Corolla Cross is **large**; Glen Village *Auto Detailing
Interior* (R 700) + odour add-on (R 180) = R 880 before the Gold plan's −10 %
on other services (R 792).
`test/catalogue_test.dart` covers that flow, the by-quote routing, the VAT
total and the size selector. Screenshots:
`screenshots/catalogue-{services,addons,payment}.png`.

## Membership plans (docs/MEMBERSHIPS.md)

The loyalty tier **is** the membership plan: Silver = no plan (points only),
Gold / Platinum / Black = a live monthly subscription. Points earning, the
ledger and rewards are unchanged; every tier's `discount_pct` is 0 — all
discounts come from the plan.

* **Membership tab** (`lib/features/membership/`, replaces the Rewards tab,
  route `/membership`, legacy alias `/loyalty`) — members see their plan card
  in the plan colour (`PlanCard` from `sparkling_ui`: gold gradient, platinum
  steel, black navy with gold text) with an `AllowanceRing` per entitlement
  ("Sparkling Washes · 3 of 4 left · resets 9 Oct"), the discount note, the
  renewal date / open invoice and **Pay now** (sandbox intent via
  `POST /memberships/me/invoices/:id/pay` → confirm) when a renewal is due or
  the plan is `past_due` ("Benefits paused" banner). **Change option** opens
  a sheet with the `choose_one` groups (409 once anything was used this
  month), **Change plan** lists the other plans (upgrade = pay now,
  downgrade = at renewal) and **Cancel membership** offers "stop renewing on
  <date>" or "cancel now". Non-members see the three plan cards (tagline,
  fee, OR / AND entitlements, discount note) → `SubscribeScreen`
  (`/membership/subscribe`): option radio cards, tokenised payment method,
  **Pay R 295 securely** → `POST /memberships` (pending) → sandbox confirm →
  "Gold membership active". Points balance, redeemable rewards and the
  ledger stay below as **Points & rewards** (`points_section.dart`).
* **Booking flow** — `BookingFlowController` loads `GET /memberships/me`
  and mirrors the server pricing rules: a covered service shows
  **Included in your plan · 3 of 4 left** with the base struck through and
  **R 0**; other services carry the plan discount tag ("Gold −10%" —
  Gold discounts *other* services, Platinum / Black the *selected* plan
  services). The payment step lists "Included in your plan · 2 of 4 left"
  as the discount line, and a fully covered booking has nothing to pay:
  the CTA becomes **Confirm booking · included**, no payment intent is
  created and the booking is confirmed straight away. Confirmation and
  booking detail show the plan benefit ("Gold plan · 2 washes left this
  month" / `discount_label`).
* **Home** — the tier pill reads "Gold · 3 washes left" (falls back to the
  points balance without a plan) and opens the Membership tab.

Demo data (`DemoStore`, mirrors `backend/supabase/seed_memberships.sql`):
Thabo Gold / G1 (1 of 4 used, card), Naledi Gold / G2 (2 of 8, cash),
Sipho Platinum / P1 (3 of 8), Zanele Black / B1 + B3 + B5 (2 washes + the
detail used, renewal invoice `MINV-2026-0105` due in 3 days). Cancelling
Thabo's plan drops him to Silver and shows the plan picker; subscribing
again activates through the sandbox payment. `test/membership_test.dart`
covers the member view (allowances, 409 on option change), the non-member
subscribe → activated flow and a covered Sparkling Wash booked at R 0.
Screenshots: `screenshots/membership-{member,plans,booking}.png`.

## Repair quotes (CUS-030..034)

`lib/features/quotes/`: the customer-raised request flow (1j) is unchanged;
staff-raised quotes arrive as `quoted` with `items[]`, damage photos and a
public link (sent on WhatsApp). The quotes list shows the amount and an
**Action needed** chip while a decision is pending. The detail screen
shows the items with category chips, descriptions and amounts, the items
note, the assessor + outlet, **valid until** with "expires in N days" (or
the expired state), the damage-photo grid (`AuthedImage` fetches
`/v1/quotations/:id/photos/:attachmentId` with the bearer token; demo
`demo://photo/<id>` bytes come from memory), **Download PDF**
(`GET /quotations/:id/pdf` → share sheet via `share_plus`) and the one-time
**Accept** / **Decline** with confirm sheets (decline takes an optional
note). After the decision the screen locks — "Accepted on 12 Sep in app" /
"… via link" — with no buttons; a `409 conflict` (decided elsewhere) shows
"Already decided" and refreshes the quote; `410 gone` explains the expiry.
Demo: Thabo's `QT-2026-0041` (R 3 850, two items, two photos).
`test/quote_detail_test.dart` covers the list chip, accept → locked, the
409 path and decline with a note. Screenshots:
`screenshots/quote-detail-{quoted,accepted}.png`.

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
lib/features/quotes           1j request, list, detail (items, photos, one-time accept / decline, PDF)
lib/features/membership       Membership tab: plan card + allowances, subscribe / change / cancel,
                              points & rewards section (redeem, ledger)
lib/features/notifications    inbox
lib/features/profile          preferences (PATCH /me), appearance, sign out
lib/features/sync             sync chip + offline queue status
```

State is plain `ChangeNotifier` / streams from `sparkling_core` repositories;
no code generation. Booking and quote drafts persist in `DraftStore` (UX-009).

## App icon

Generated from `assets/icon/app_icon.png` (navy `#203060` + logo) with
`dart run flutter_launcher_icons`.

## Branding
App icon ("car swoosh") and native splash are generated — see `docs/branding/README.md`.
