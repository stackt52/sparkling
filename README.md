# Sparkling Platform

Multi-outlet car-wash and auto-body service platform (SRS v1.0, 28 Aug 2026): a **Customer app** and an **Outlet Staff app** (Flutter, Material 3 Expressive), an **Admin Dashboard** (Next.js on Firebase App Hosting), a **REST backend** (Firebase Cloud Functions) and a **Supabase Postgres** database.

```
apps/customer            Flutter — Android + iOS customer app (booking, PDF417 disc scan, payment, tracking, loyalty, quotes)
apps/staff               Flutter — Android staff app (tasks, checklists, supervisor ops, leaderboard, inventory, offline sync)
apps/admin               Next.js + MUI — admin dashboard (ops, loyalty config, inventory, users, reports, audit)
packages/sparkling_ui    Flutter design system: tokens, M3 theme, shared widgets
packages/sparkling_core  Flutter shared domain: models, API client, realtime, offline queue, PDF417 parser, demo data
backend/functions        Cloud Functions (Node 22 / TypeScript / Express) — versioned REST API `/v1` + OpenAPI
backend/supabase         SQL migrations (clean-slate schema, RLS, realtime publication) + demo seed + apply script
docs/                    ARCHITECTURE.md · API.md · RUNBOOK.md
design_handoff_sparkling_apps/   Hi-fi mockups and design tokens the apps are built from
```

## Quick start (demo mode, no backend needed)
```bash
# Admin dashboard
cd apps/admin && npm install && npm run dev            # http://localhost:3000 (NEXT_PUBLIC_DEMO_MODE=true)

# Customer app / Staff app
cd apps/customer && flutter run --dart-define-from-file=env/demo.json
cd apps/staff    && flutter run --dart-define-from-file=env/demo.json
```

## Real environment
1. Apply the database: `SUPABASE_DB_URL=… ./backend/supabase/apply.sh` (see `docs/RUNBOOK.md`).
2. Set secrets and deploy the API: `firebase deploy --only functions --project sparkling-4e89d`.
3. Point the apps at it (`env/dev.json`, `apps/admin/.env.local`).

Firebase project: **sparkling-4e89d** (700174326619). Supabase project: **uicqczgpiqkczwyssdft**.

See `docs/ARCHITECTURE.md` for technology decisions, data ownership and state machines, and `docs/API.md` for the API contract.
