# sparkling_core

Shared domain for the Sparkling Flutter apps (SRS ARC-002/004, DAT-005, BAR-*):
hand-written models mirroring `backend/supabase/migrations/0001_schema.sql`, the
typed REST client for `docs/API.md`, Supabase realtime, the durable offline
queue, the PDF417 licence-disc parser and repositories (API-backed + demo).

```dart
import 'package:sparkling_core/sparkling_core.dart';

// Live: Firebase.initializeApp() first. Demo: --dart-define=DEMO_MODE=true
final repos = await SparklingCore.bootstrap();
runApp(RepositoriesScope(repositories: repos, child: const App()));

// After sign-in (live mode): mints/refreshes custom claims.
await repos.bootstrapSession(app: Env.appName);

final booking = await context.repositories.customer.booking(id);
repos.staff.watchTasks(scope: TaskScope.mine).listen(...);
```

Configuration via `--dart-define` / `--dart-define-from-file`: `API_BASE_URL`,
`SUPABASE_URL`, `SUPABASE_ANON_KEY`, `DEMO_MODE`, `APP_NAME`, `APP_VERSION` (see `Env`).

Demo mode (`DemoStore`) mirrors `backend/supabase/seed.sql` (Thabo Nkosi, Gold 1 450 pts,
SPK-…-0091 in service at Sparkling Sandton, WO-…-4821 4/7 steps, staff, inventory alerts,
leaderboard, rewards) and supports every mutation with the same server rules, so the apps
are fully navigable offline. Personas: `DemoPersonas.customer/technician/supervisor/manager`
(sign in with the seeded e-mails, any password).
