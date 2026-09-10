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

## Environment

| Variable | Purpose |
|---|---|
| `NEXT_PUBLIC_DEMO_MODE` | `true` = in-memory demo API; `false` = real REST API + Firebase Auth + Supabase realtime |
| `NEXT_PUBLIC_API_BASE_URL` | Cloud Functions REST base without `/v1` (emulator: `http://127.0.0.1:5001/sparkling-4e89d/europe-west1/api`) |
| `NEXT_PUBLIC_SUPABASE_URL` | Supabase project URL (default `https://uicqczgpiqkczwyssdft.supabase.co`) |
| `NEXT_PUBLIC_SUPABASE_ANON_KEY` | Supabase anon key — realtime subscriptions use the Firebase ID token via Third-Party Auth |

Firebase web config for `sparkling-4e89d` is committed in `src/lib/firebaseConfig.ts` (public by design).

## Structure

```
src/app/login                 Firebase Auth (email/password + Google) → POST /v1/auth/session → role gate
src/app/(dashboard)/…         Authenticated routes: /, bookings, quotations, work-orders, staff, staff/performance,
                              customers, outlets, services, templates, loyalty, notifications, inventory, reports, audit, settings
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
