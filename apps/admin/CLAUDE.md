# apps/admin — Sparkling Admin Dashboard

Next.js 16 (App Router, `src/`), TypeScript, MUI v7 with `cssVariables` + `colorSchemes`, MUI X (DataGrid, Charts), TanStack Query, Firebase Auth, Supabase realtime.

## Commands

```bash
npm run dev          # dev server (add -- --port 3100 to change port)
npm run lint         # eslint
npx tsc --noEmit     # type-check
npm run build        # production build
```

## Conventions

- Colours only via `tk.*` from `src/theme/tokens.ts` (CSS variables) — never hard-code hex in components (UX-001).
- Icons: `<MSymbol name="…" filled />` (Material Symbols Rounded). Buttons/chips are pill-shaped; cards 24px radius.
- Data access goes through the `AdminApi` interface (`src/lib/api.ts`). `DemoApi` (`src/lib/demo`) must stay in sync with any new method.
- Pages are client components under `src/app/(dashboard)`; RBAC via `can(role, capability)` from `src/lib/rbac.ts`.
- Next.js 16 docs live in `node_modules/next/dist/docs/` — check them before using an API from memory.
