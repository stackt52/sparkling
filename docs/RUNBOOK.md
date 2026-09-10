# Sparkling — setup & operations runbook

## 0. Prerequisites
- Node 22+, npm, Firebase CLI (`npm i -g firebase-tools`, logged in with access to project **sparkling-4e89d** / number 700174326619)
- Flutter 3.47+ stable (`brew install --cask flutter`), Xcode 16+, Android SDK 36 (`flutter doctor --android-licenses` once)
- `psql` 15+ for applying the Supabase migrations

## 1. Database (Supabase project `uicqczgpiqkczwyssdft`)
**Status: applied 8–9 Sep 2026** — migrations `0001_sparkling_schema`, `0002_receipt_rpc`, `0003_hardening`, `0004_whatsapp_twilio` plus the demo seed are live (applied through the Supabase MCP server; they appear under Database → Migrations). The previous `stores/orders/work_items…` tables were removed as requested.

The schema is a **clean-slate** migration: it drops every object in `public` and recreates everything. To re-apply or reseed later:

```bash
# Connection string: Supabase dashboard → Project settings → Database → URI (use the session pooler or direct 5432)
export SUPABASE_DB_URL='postgresql://postgres.<ref>:<password>@aws-0-<region>.pooler.supabase.com:5432/postgres'
./backend/supabase/apply.sh            # migrations + demo seed
./backend/supabase/apply.sh --no-seed  # migrations only
```
Alternative: paste `backend/supabase/migrations/0001_schema.sql` then `backend/supabase/seed.sql` into the Supabase SQL editor, or authenticate the Supabase MCP server listed in `SUPABASE.md` and ask Claude to apply them.

Then enable **Authentication → Third-Party Auth → Firebase** in the Supabase dashboard with project id `sparkling-4e89d`. This lets the mobile/web clients query PostgREST and subscribe to Realtime with a Firebase ID token; RLS policies read the `role` / `outlet_ids` custom claims that the API mints.

Verify: `select count(*) from public.outlets;` → 3.

Client credentials (publishable, safe in apps): URL `https://uicqczgpiqkczwyssdft.supabase.co`, anon key = Supabase dashboard → Project settings → API (also pre-filled in `apps/*/env/dev.json` and `apps/admin/.env.local.example`).

## 2. Firebase project `sparkling-4e89d`
Already registered apps:
| App | Id | Config file |
|---|---|---|
| Android customer | `za.co.sparkling.customer` | `apps/customer/android/app/google-services.json` |
| iOS customer | `za.co.sparkling.customer` | `apps/customer/ios/Runner/GoogleService-Info.plist` |
| Android staff | `za.co.sparkling.staff` | `apps/staff/android/app/google-services.json` |
| Web admin | `1:700174326619:web:bc3dca8003ddeb15c5587e` | `apps/admin/src/lib/firebaseConfig.ts` |

One-time console steps: enable **Authentication → Sign-in method → Email/Password** (and Google if wanted); enable **Cloud Storage**; upgrade to Blaze for Cloud Functions + App Hosting.

Secrets (never in the repo — INT-006):
```bash
firebase functions:secrets:set SUPABASE_SERVICE_ROLE_KEY --project sparkling-4e89d      # Supabase → Project Settings → API Keys → secret / service_role
openssl rand -hex 32 | firebase functions:secrets:set PAYMENT_WEBHOOK_SECRET --project sparkling-4e89d --data-file=-   # random HMAC secret for the sandbox provider
```
Secret Manager rejects empty values, so set every secret **before** `firebase deploy`; the deploy prompt only appears for secrets that have no version yet. Check with `firebase functions:secrets:access PAYMENT_WEBHOOK_SECRET --project sparkling-4e89d`.
```bash```

WhatsApp via **Twilio** (credentials carried over from the legacy `sparkling-admin/.env`; they are in `backend/functions/.secret.local` for the emulator — never commit them):
```bash
firebase functions:secrets:set TWILIO_ACCOUNT_SID --project sparkling-4e89d   # paste the AC… sid
firebase functions:secrets:set TWILIO_AUTH_TOKEN  --project sparkling-4e89d
# params (non-secret) live in backend/functions/.env: TWILIO_MESSAGING_SERVICE_SID=MG4d8b6037dc3b183f43b2622307271660, PUBLIC_API_BASE_URL=https://<region>-sparkling-4e89d.cloudfunctions.net/api
```
Then in the Twilio console set the Messaging Service status callback to `${PUBLIC_API_BASE_URL}/v1/notifications/twilio/status` and, once the sender is confirmed, flip the `whatsapp_enabled` feature flag in Admin → Settings (it ships **off** so seeded demo numbers never receive real messages). Approved Content templates reused from the old project: quote ready `HX011c7f1b31697f8e21d36ff6b4d02b06`, collection OTP card `HX63a748f8b6680eac890e0137dfcf0fdb` (bound in `notification_templates.provider_template_sid`, migration 0004).

## 3. Backend API
```bash
cd backend/functions && npm install && npm run build && npm test
firebase emulators:start --project sparkling-4e89d      # API at http://127.0.0.1:5001/sparkling-4e89d/europe-west1/api/v1
firebase deploy --only functions --project sparkling-4e89d
```
Local secrets for the emulator go in `backend/functions/.secret.local` (see `.env.example`).

## 4. Admin dashboard
```bash
cd apps/admin && npm install
cp .env.local.example .env.local     # NEXT_PUBLIC_DEMO_MODE=true works with no backend
npm run dev                          # http://localhost:3000
firebase apphosting:backends:create --project sparkling-4e89d   # once; connects the GitHub repo, root dir apps/admin
```
Set `NEXT_PUBLIC_DEMO_MODE=false`, `NEXT_PUBLIC_API_BASE_URL`, `NEXT_PUBLIC_SUPABASE_ANON_KEY` in `apps/admin/apphosting.yaml` for a real environment.

## 5. Mobile apps
Each app reads `--dart-define-from-file`:
```bash
cd apps/customer
flutter run --dart-define-from-file=env/demo.json    # no backend needed, seeded demo data
flutter run --dart-define-from-file=env/dev.json     # real Firebase Auth + API + Supabase realtime
cd ../staff && flutter run -d <android-device> --dart-define-from-file=env/demo.json
```
`env/dev.json` keys: `API_BASE_URL`, `SUPABASE_URL`, `SUPABASE_ANON_KEY`, `DEMO_MODE=false`.

Android note: `flutter_secure_storage` requires `compileSdk 37`. Gradle downloads it as `platforms/android-37.0` but AGP looks for `platforms/android-37`; on this machine a symlink `~/Library/Android/sdk/platforms/android-37 → android-37.0` was created. On CI, install platform 37 through `sdkmanager "platforms;android-37"` instead. Run `flutter doctor --android-licenses` once if Gradle asks for licence acceptance.
Demo sign-in accounts (after seeding and creating the users in Firebase Auth with the same e-mails): `thabo@example.com` (customer, Gold), `pieter@sparkling.co.za` (technician), `johan@sparkling.co.za` (supervisor), `ayesha@sparkling.co.za` (manager), `admin@sparkling.co.za` (admin). The API claims the seeded profile by e-mail on first sign-in.

## 6. Quality gates (ENG-002)
```bash
cd backend/functions && npm run lint && npm test
cd apps/admin && npm run lint && npx tsc --noEmit && npm run build
for p in packages/sparkling_ui packages/sparkling_core apps/customer apps/staff; do (cd $p && flutter analyze && flutter test); done
```

## 7. Rollback (ENG-004)
- Functions: `firebase functions:rollback` is not available for 2nd gen; redeploy the previous git tag (`git checkout <tag> && firebase deploy --only functions`).
- App Hosting: roll back to a previous rollout in the Firebase console.
- Database: migrations are forward-only; keep `pg_dump` backups before applying (`pg_dump "$SUPABASE_DB_URL" > backup.sql`).
