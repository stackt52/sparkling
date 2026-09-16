# Sparkling Admin Dashboard

Responsive web dashboard for the Sparkling multi-outlet car-wash / auto-body platform (SRS v1.0). Built with Next.js (App Router, TypeScript), MUI v7 (Material 3 Expressive tokens from `design_handoff_sparkling_apps/README.md`), MUI X Data Grid + Charts, Firebase Auth, Supabase Realtime and TanStack Query.

## Run

```bash
npm install
cp .env.local.example .env.local   # optional — defaults come from .env.development
npm run dev                        # http://localhost:3000
```

Demo mode is **on by default** (`NEXT_PUBLIC_DEMO_MODE=true`): an in-memory `DemoApi` mirrors `backend/supabase/seed.sql` (Sandton / Rosebank / Centurion, Thabo Nkosi's in-service Full Valet, the blocked WO-2026-4823, loyalty v14 + v15 draft, inventory alerts…) with working mutations and a synthetic live tick. On `/login` press **Continue with demo admin** (or pick another role to see RBAC).

Checks:

```bash
npm run lint
npx tsc --noEmit
npm run build
```

## Membership plans (`/loyalty`, "Memberships" in the rail)

Tier = plan (docs/MEMBERSHIPS.md): Gold R295 · Platinum R475 · Black R850 per month; a customer without a
live membership is Silver (free, earns points only) and every tier's booking discount is 0 % — discounts and
included washes come from the plan.

* **Plans tab** — one card per plan (`GET /admin/memberships/plans`): fee, entitlement groups with their
  options (OR = choose one, AND = all included), the discount rule and scope, live member count and MRR. **Edit
  plan** (`memberships:manage`, manager+) opens a drawer (`PUT /admin/memberships/plans/:code`): name, tagline,
  fee, discount % / scope / note, active flag, and groups → options with quantity, month/year period and a
  service picker from the catalogue (first service = primary). Options that members have already redeemed
  cannot be deleted (409). The earn rules card keeps points per R1, expiry, referral / birthday bonuses and the
  per-tier earn multiplier (versioned draft → publish flow as before); the per-tier "Qualify" / "Booking
  discount" rows are replaced by "Tier = plan" copy.
* **Members tab** — `GET /admin/memberships?status&plan_code&q` grid: member, plan chip, status chip, period +
  selections, washes used / remaining per entitlement, open invoice. Row actions **Record payment**
  (`…/invoices/:id/record-payment`, cash / card terminal / EFT — rolls the period, lifts past-due) and
  **Cancel** (at period end or immediately). **Run renewals** calls `POST /admin/memberships/run-renewals`
  (expire cancel-at-period-end, invoice 3 days ahead, mark past due, sandbox card auto-charge).
* **Customers** — the grid shows the plan ("Gold · 3 left"); the drawer's first tab is **Membership**: plan
  header in the plan colour, status, period, allowance bars per entitlement, discount rule, invoices, with
  **Enrol in a plan** (plan → option picker → cash / card terminal / EFT, `POST /admin/customers/:id/membership`),
  Record payment and Cancel.
* **Walk-in** — the customer step shows the plan pill ("Gold · 3 washes left"); the service step marks covered
  services **Included in Gold · 2 of 4 left** (R 0, add-ons still charged) and the plan discount ("Gold −10%")
  on eligible services per scope; payment / summary / success reflect the R 0 base (no counter payment is
  recorded when nothing is due); non-members get an **Enrol in a plan** shortcut on the payment step.
* **Overview** adds "Active members" and "Membership MRR" tiles; **Reports → Exports** adds the memberships CSV.
* Demo API: the three plans (stable ids from migration 0010), Thabo Gold/G1, Naledi Gold/G2 (cash), Sipho
  Platinum/P1, Zanele Black/B1+B3+B5 (renewal due in 3 days) with usage, invoices and payments; pricing follows
  the doc's rules (included → discount = base, scope discounts, past_due = no benefits) and posts / releases
  usage on booking create / cancel; loyalty tiers are derived from the memberships.
* Tokens: `tk.platinumGradient`, `tk.blackGradient` (navy → black) + `tk.onBlack` (gold text); `TierChip`
  paints Silver / Gold / Platinum / Black.

## Staff accounts (`/staff`, ADM-010)

Admins (`user:manage`) create staff accounts from the dashboard; the account gets a **temporary password** that
works in the Sparkling Staff app (any staff role) and in this dashboard (manager / admin / finance / supervisor),
and the first sign-in forces a password change.

* **Add staff member** (header pill) — full name, e-mail, phone (`PhoneField`, any country → E.164), role, outlets and an optional "Also generate a
  reset link" → `POST /admin/users` `{ email, full_name, role, phone?, outlet_ids[], invite: 'password'|'link' }`.
  On `201` the form is replaced by a **Credentials** panel: e-mail and temporary password in monospace with copy
  buttons, a copy-all **Send these details** text, the Firebase reset link when requested, and the note that
  they'll be asked to choose a new password on their first sign-in. The password is shown once — it is not
  retrievable later.
* **Reset password** — row action (lock-reset icon) or the button in the edit dialog → confirm →
  `POST /admin/users/:id/reset-password` → the same credentials panel (the old password stops working and refresh
  tokens are revoked server-side). Rows whose profile carries `must_change_password` show a
  **Must change password** chip next to the status.
* **First-sign-in gate** — `AuthProvider` reports status `password_change` when `POST /auth/session` returns
  `profile.must_change_password` (checked *before* the role check, so a technician who opens the dashboard sets a
  password first and then sees the not-authorised page). `(dashboard)/layout.tsx` and `/login` redirect to
  **`/change-password`**: new password + confirm (≥ 10 characters with a letter and a digit, strength hint), a
  "Sign out" link. `changePassword()` runs Firebase `updatePassword`; on `auth/requires-recent-login` the page asks
  for the current (temporary) password and re-authenticates with `reauthenticateWithCredential`; it then signs in
  again with the new password (fresh `auth_time`) and calls `POST /auth/password-changed` (409 `stale_session` →
  "sign in again" message). Password rules live in `src/lib/password.ts`.
* **Demo mode** — "Continue with demo admin" never hits the gate. `DemoApi.inviteUser` / `resetUserPassword`
  return fake `Spk-…` passwords and flag the row; `/change-password` renders as a preview and "Set password" just
  returns to the dashboard.

## Phone numbers (any country, E.164)

Every phone typed in the dashboard goes through **`PhoneField`** (`src/components/ui/PhoneField.tsx`) and is sent to
the API as **E.164** (`+27821234567`); the API rejects anything else with `400 validation_error`
"Enter the mobile number with its country code, e.g. +27 82 123 4567".

* **`PhoneField`** — a country picker (MUI `Autocomplete`: flag · name · `+dial`, searchable by name, dial code or
  ISO code, default `ZA`, last choice remembered in `localStorage` `sparkling.phone.country`) as the start adornment
  of a `tel` input that formats the national number as you type (`libphonenumber-js/max` `AsYouType`). Props:
  `value` (E.164 or `''`), `onChange(e164, { valid, country, national })`, `label`, `required`, `helperText`, `size`,
  `disabled`, `autoFocus`, `error`, `kind` (`mobile` | `any` — only changes the error wording; outlets allow landlines).
  A `value` from another country moves the picker; pasting a full `+44 …` / `0044 …` number into the number box
  switches the country automatically. Invalid + non-empty (after blur) → red with "Enter a valid *Country* mobile
  number". Used by the walk-in **Register customer** form, Staff → **Add staff member** / edit dialog (`PATCH
  /admin/users` now carries `phone`) and the **Outlets** editor (legacy free-text numbers stay on file until replaced).
* **`src/lib/phone.ts`** — `normalisePhone(raw, 'ZA')` (accepts `+27…`, `0027…`, `27…` and bare ZA `082…`),
  `isValidPhone`, `formatPhone('+27821234567') → '+27 82 123 4567'` (non-E.164 strings are returned unchanged),
  `phoneCountry`, `splitPhone`, `formatNational`, `normaliseSearch` (the customer / walk-in search boxes normalise a
  pasted number before querying). Same rules and `max` metadata as `backend/functions/src/lib/phone.ts`.
* Phones are displayed with `formatPhone` everywhere (customer grid + drawer, walk-in cards / summary / success,
  staff grid, memberships grid, raise-quote dialog, public quote page footer + `tel:` link, demo PDF).
* Demo API: `createWalkInCustomer`, `inviteUser` and `updateUser` validate with `normalisePhone` and throw the API's
  400 shape; duplicates are matched on E.164. Seed phones are E.164 and include one international customer, **Priya
  Naidoo** `+447911123456` (renders as `+44 7911 123456`).

## Messages (notifications) and WhatsApp

* **/notifications** ("Messages" in the rail, under Loyalty) — DataGrid of
  `GET /admin/notifications?status&channel&limit&cursor`: recipient, channel
  chip (WhatsApp / push icon), template key, status chip with the provider
  status (Twilio `queued / sent / delivered / read / undelivered`), attempts,
  sent / delivered times and the provider error (`63016` = free-form message
  outside the 24 h WhatsApp session). Status / channel filters, cursor paging,
  and a **Resend** row action (`POST /admin/notifications/:id/resend`, confirm
  dialog, audited as `notification.resend`) for managers / admins. Finance
  sees the page read-only (`view:notifications` without
  `notification:resend`).
* **Settings → Integrations** — the WhatsApp card reads the `whatsapp` entry
  of `GET /admin/integrations` (`provider`, `configured`, masked
  `messaging_service` "MG…7660", `enabled`) and carries the `whatsapp_enabled`
  flag switch (admin only, audited like every flag).
* Demo API: seed-mirroring rows plus one failed WhatsApp row (`63016 outside
  24h session`) that Resend flips to `sent`.

## Public quotation page (`/q/<token>`)

The link customers receive on WhatsApp (`quote_ready`) opens **this app's** origin at `/q/<public_token>` — a
standalone, unauthenticated route outside the `(dashboard)` group (no Firebase sign-in, no nav rail, mobile-first).
It talks only to the token-scoped public API (`GET|POST /v1/public/quotations/:token[/decision|/photos/:id|/pdf]`)
through `publicFetch` in `src/lib/api.ts`, never with a staff token. States: loading, not found (404), expired (410),
quoted (accept / decline — one-time, 409 refreshes to the decided view), decided (accepted / declined / converted),
plus "Download PDF", photo lightbox, `tel:` link and "Save link".

* **Backend config:** the API's `PUBLIC_WEB_BASE_URL` must be this app's origin (e.g.
  `https://sparkling-admin-….hosted.app`, or `http://localhost:3000` against the emulator) — the public link is
  `${PUBLIC_WEB_BASE_URL}/q/<token>`.
* **Twilio:** the `quote_ready` Content template's button URL must be `<PUBLIC_WEB_BASE_URL>/q/{{2}}`
  (variable 2 = `public_token`; migration 0006 updates the `provider_variables` binding).
* **Routing:** there is no `src/middleware.ts`; auth gating lives in `src/app/(dashboard)/layout.tsx`, so `/q/*`
  needs no exclusion. `AuthProvider` skips Firebase initialisation on `/q/*`. If a middleware or redirect rule is
  added later, keep `/q/:path*` (and `/demo/*` assets) public.
* **Demo mode:** `/q/demo-quoted`, `/q/demo-accepted`, `/q/demo-expired` and `/q/demo-missing` are served from
  `src/lib/demo/publicQuotes.ts` (mirrors QT-2026-0041 for Thabo, placeholder photos in `public/demo/`). Decisions
  persist in `localStorage`, so the dashboard drawer shows "Accepted via link by …" after a reload; the PDF is
  generated client-side with `jspdf` (demo only — live mode streams the API's PDF).

## Quotations (dashboard)

* **Drawer:** items with category chips + descriptions, dashed total, damage-photo grid (images are fetched
  through `GET /quotations/:id/photos/:attachmentId` with the bearer token → object URLs, never a bucket URL),
  decision line ("Accepted via link by Thabo N. on …"), **Public link** row (Copy · Open · Resend WhatsApp →
  `POST /quotations/:id/share`, 60 s cooldown / 429-aware), **Download PDF** (`GET /quotations/:id/pdf`).
* **Quote form:** per-item category chips, description, optional auto-body service (outlet services filtered to
  `auto_body`), amount; notes; photo dropzone (`multipart/form-data` → `POST /quotations/:id/photos`).
* **Raise quote** (header pill, `quote:write`): customer search / register and vehicle pick / add reuse the walk-in
  components, then items + photos + validity → `POST /quotations` (staff shape, `send_to_customer`) → success with
  the public link.

## Environment

| Variable | Purpose |
|---|---|
| `NEXT_PUBLIC_DEMO_MODE` | `true` = in-memory demo API; `false` = real REST API + Firebase Auth + Supabase realtime |
| `NEXT_PUBLIC_API_BASE_URL` | Cloud Functions REST base without `/v1` (emulator: `http://127.0.0.1:5001/sparkling-4e89d/europe-west1/api`). Also used, without a token, by the public quote page |
| `NEXT_PUBLIC_SUPABASE_URL` | Supabase project URL (default `https://uicqczgpiqkczwyssdft.supabase.co`) |
| `NEXT_PUBLIC_SUPABASE_ANON_KEY` | Supabase anon key — realtime subscriptions use the Firebase ID token via Third-Party Auth |

Firebase web config for `sparkling-4e89d` is committed in `src/lib/firebaseConfig.ts` (public by design).

## Structure

```
src/app/login                 Firebase Auth (email/password + Google) → POST /v1/auth/session → role gate
src/app/(dashboard)/…         Authenticated routes: /, bookings, quotations, work-orders, staff, staff/performance,
                              customers, outlets, services, templates, loyalty (Membership plans), notifications, inventory, reports, audit, settings
src/components/memberships    PlanCard, PlanEditorDrawer, MembersGrid, EnrolDialog, MembershipBlock, record-payment / cancel dialogs
src/app/q/[token]             Public quotation page (unauthenticated; see above) → src/components/public, src/lib/publicQuote.ts
src/theme                     tokens.ts (design tokens → CSS variables), theme.ts (MUI colorSchemes light/dark)
src/components                MSymbol (Material Symbols Rounded), layout (nav rail / drawer / header), ui, ops
src/lib/api.ts                AdminApi interface + HttpApi (error envelope, Idempotency-Key, X-Correlation-Id, X-Client-App)
src/lib/demo                  DemoApi + seed-mirroring dataset
src/lib/supabase.ts           Supabase client with accessToken = Firebase ID token; admin realtime channels
src/lib/rbac.ts               UI capability matrix (admin / manager / finance / supervisor) — server enforces too
```

## Deploy (Firebase App Hosting)

```bash
firebase login
firebase apphosting:backends:create --project sparkling-4e89d   # pick region, connect the GitHub repo, root dir apps/admin
# App Hosting builds on every push to the configured branch using apphosting.yaml.
# Set real values for NEXT_PUBLIC_* in apphosting.yaml (or per-environment overrides) and NEXT_PUBLIC_DEMO_MODE=false.
```

`apphosting.yaml` uses `runConfig.minInstances: 0` and exposes the `NEXT_PUBLIC_*` variables with `BUILD` + `RUNTIME` availability; secret references are shown commented out. The default Next.js output is used (App Hosting does not require `output: 'standalone'`).

Before going live, enable **Supabase → Authentication → Third-Party Auth → Firebase** for project `sparkling-4e89d` so RLS-scoped realtime subscriptions accept Firebase ID tokens.

## Screenshots

`screenshots/` (demo mode, dark scheme, 1440×1000):

| File | What it shows |
|---|---|
| `memberships-plans.png` | Membership plans — Gold / Platinum / Black cards with OR / AND entitlement groups, discount rule, members and MRR |
| `memberships-editor.png` | Plan editor drawer — fee, discount scope, groups → options → service picker |
| `memberships-members.png` | Members tab after "Run renewals" — Zanele's renewal invoice open, row actions |
| `memberships-customer.png` | Customer drawer → Membership tab (Black plan: allowances, invoices, enrol / cancel) |
| `memberships-walkin.png` | Walk-in service step for a Gold member — "Included in Gold · 2 of 4 left" at R 0, plan discount on other services |
| `phone-field.png` | Walk-in register form — `PhoneField` with the country picker open (search "united") |
| `phone-field-invalid.png` | The same field after blur with a too-short UK number — "Enter a valid United Kingdom mobile number" |
| `staff-add.png` | Add staff member dialog — name, e-mail, phone, role, outlets, "Also generate a reset link" |
| `staff-credentials.png` | Credentials panel after creation — e-mail, temporary password, reset link, "Send these details"; the new row carries the "Must change password" chip |
| `change-password.png` | First-sign-in gate (`/change-password`) — rules checklist and strength hint |
| `walkin-*.png`, `catalogue-*.png`, `drawer-*.png`, `public-quote-*.png`, `raise-quote*.png` | Earlier flows (walk-in booking, catalogue, drawers, public quotation page, raise quote) |

## Branding
Favicon family (`favicon.ico`, `public/icon.svg`, `icon-192/512.png`, `apple-touch-icon.png`) is generated — see `docs/branding/README.md`.
