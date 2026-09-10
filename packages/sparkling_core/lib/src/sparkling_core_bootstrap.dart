import 'package:dio/dio.dart';

import 'api/sparkling_api.dart';
import 'auth/auth_service.dart';
import 'env/env.dart';
import 'models/models.dart';
import 'offline/connectivity_service.dart';
import 'offline/draft_store.dart';
import 'offline/hive_store.dart';
import 'offline/local_cache.dart';
import 'offline/offline_queue.dart';
import 'realtime/realtime_service.dart';
import 'repositories/api_repositories.dart';
import 'repositories/demo_repositories.dart';
import 'repositories/demo_store.dart';
import 'repositories/repositories_scope.dart';

/// Entry point: wires auth, API, realtime, offline storage and repositories.
abstract final class SparklingCore {
  /// Builds the [Repositories] bundle.
  ///
  /// * `demo` defaults to [Env.demoMode]. In demo mode nothing touches the
  ///   network or Firebase; data comes from [DemoStore] (mirrors seed.sql).
  /// * In live mode the app must have called `Firebase.initializeApp()` first
  ///   (or pass a ready [auth]). When [authEmulatorHost] (default
  ///   [Env.authEmulatorHost]) is non-empty, Firebase Auth is pointed at the
  ///   local Auth emulator before any auth call is made.
  /// * [hivePath] is for tests (uses `Hive.init(path)` instead of `initFlutter`).
  static Future<Repositories> bootstrap({
    bool? demo,
    String? clientApp,
    String? clientVersion,
    String? apiBaseUrl,
    String? supabaseUrl,
    String? supabaseAnonKey,
    String? authEmulatorHost,
    AuthGateway? auth,
    Dio? dio,
    String? hivePath,
    AuthUser? demoUser,
    DemoStore? demoStore,
    ConnectivityService? connectivity,
    void Function()? onUnauthenticated,
  }) async {
    final isDemo = demo ?? Env.demoMode;
    final app = clientApp ?? Env.appName;
    final version = clientVersion ?? Env.appVersion;

    await HiveStore.ensureInitialized(path: hivePath);
    final cache = await LocalCache.open();
    final drafts = await DraftStore.open();

    if (isDemo) {
      final store =
          demoStore ??
          DemoStore(currentUser: demoUser ?? _defaultDemoUser(app));
      final demoAuth =
          auth ??
          DemoAuthService(initialUser: demoUser ?? _defaultDemoUser(app));
      // Keep the store's persona in sync with the demo sign-in state.
      demoAuth.authStateChanges.listen((u) {
        if (u != null && u.uid != store.currentUser.uid) store.signInAs(u);
      });
      final queue = await OfflineQueue.open(
        poster: (ops) async =>
            store.applySyncBatch(ops.map((o) => o.toSyncJson()).toList()),
      );
      final conn = connectivity ?? ConnectivityService.alwaysOnline();
      return Repositories(
        demo: true,
        auth: demoAuth,
        customer: DemoCustomerRepository(store),
        catalogue: DemoCatalogueRepository(store),
        loyalty: DemoLoyaltyRepository(store),
        staff: DemoStaffRepository(store),
        inventory: DemoInventoryRepository(store),
        notifications: DemoNotificationsRepository(store),
        offlineQueue: queue,
        cache: cache,
        drafts: drafts,
        connectivity: conn,
      );
    }

    final liveAuth =
        auth ??
        await AuthService.create(
          emulatorHost: authEmulatorHost ?? Env.authEmulatorHost,
        );
    final api = SparklingApi(
      baseUrl: apiBaseUrl ?? Env.apiBaseUrl,
      tokenProvider: () => liveAuth.idToken(),
      clientApp: app,
      clientVersion: version,
      dio: dio,
      onUnauthenticated: onUnauthenticated,
    );
    final sbUrl = supabaseUrl ?? Env.supabaseUrl;
    final sbKey = supabaseAnonKey ?? Env.supabaseAnonKey;
    final realtime = (sbUrl.isNotEmpty && sbKey.isNotEmpty)
        ? RealtimeService(
            supabaseUrl: sbUrl,
            anonKey: sbKey,
            accessToken: () => liveAuth.idToken(),
          )
        : null;
    final conn = connectivity ?? ConnectivityService();
    final queue = await OfflineQueue.open(
      poster: (ops) => api.syncBatch(ops.map((o) => o.toSyncJson()).toList()),
    );
    queue.autoSyncWhenOnline(conn);

    String? uid() => liveAuth.currentUser?.uid;

    return Repositories(
      demo: false,
      auth: liveAuth,
      api: api,
      realtime: realtime,
      customer: ApiCustomerRepository(
        api: api,
        realtime: realtime,
        cache: cache,
        queue: queue,
        connectivity: conn,
        uidProvider: uid,
      ),
      catalogue: ApiCatalogueRepository(
        api: api,
        cache: cache,
        uidProvider: uid,
      ),
      loyalty: ApiLoyaltyRepository(
        api: api,
        realtime: realtime,
        cache: cache,
        uidProvider: uid,
      ),
      staff: ApiStaffRepository(
        api: api,
        realtime: realtime,
        cache: cache,
        queue: queue,
        connectivity: conn,
        uidProvider: uid,
      ),
      inventory: ApiInventoryRepository(
        api: api,
        realtime: realtime,
        cache: cache,
        queue: queue,
        connectivity: conn,
        uidProvider: uid,
      ),
      notifications: ApiNotificationsRepository(
        api: api,
        realtime: realtime,
        cache: cache,
        uidProvider: uid,
      ),
      offlineQueue: queue,
      cache: cache,
      drafts: drafts,
      connectivity: conn,
    );
  }

  static AuthUser _defaultDemoUser(String app) => switch (app) {
    'staff' => DemoAuthService.demoTechnician,
    'admin' => DemoAuthService.demoManager,
    _ => DemoAuthService.demoCustomer,
  };
}

/// Re-exported for convenience so apps can switch demo personas.
typedef DemoPersona = AuthUser;

/// The demo personas (mirroring seed.sql profiles).
abstract final class DemoPersonas {
  static const AuthUser customer = DemoAuthService.demoCustomer;
  static const AuthUser technician = DemoAuthService.demoTechnician;
  static const AuthUser supervisor = DemoAuthService.demoSupervisor;
  static const AuthUser manager = DemoAuthService.demoManager;

  static UserRole roleOf(AuthUser u) => u.role;
}
