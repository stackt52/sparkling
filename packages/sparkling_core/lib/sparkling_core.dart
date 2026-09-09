/// Sparkling shared domain: models, REST client, Supabase realtime, offline
/// queue, PDF417 disc parser and repositories (SRS ARC-002/004, DAT-005, BAR-*).
///
/// ```dart
/// final repos = await SparklingCore.bootstrap(); // honours --dart-define DEMO_MODE
/// runApp(RepositoriesScope(repositories: repos, child: const App()));
/// ```
library;

export 'src/api/api_exception.dart';
export 'src/api/sparkling_api.dart';
export 'src/auth/auth_service.dart';
export 'src/env/env.dart';
export 'src/models/models.dart';
export 'src/offline/connectivity_service.dart';
export 'src/offline/draft_store.dart';
export 'src/offline/hive_store.dart';
export 'src/offline/local_cache.dart';
export 'src/offline/offline_queue.dart';
export 'src/realtime/realtime_service.dart';
export 'src/repositories/api_repositories.dart';
export 'src/repositories/demo_repositories.dart';
export 'src/repositories/demo_store.dart';
export 'src/repositories/repositories.dart';
export 'src/repositories/repositories_scope.dart';
export 'src/scanning/pdf417_disc_parser.dart';
export 'src/sparkling_core_bootstrap.dart';
