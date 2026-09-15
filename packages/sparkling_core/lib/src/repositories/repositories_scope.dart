import 'package:flutter/widgets.dart';

import '../api/api_exception.dart';
import '../api/sparkling_api.dart';
import '../auth/auth_service.dart';
import '../models/profile.dart';
import '../offline/connectivity_service.dart';
import '../offline/draft_store.dart';
import '../offline/local_cache.dart';
import '../offline/offline_queue.dart';
import '../realtime/realtime_service.dart';
import 'demo_store.dart';
import 'repositories.dart';

/// Everything an app needs, built by `SparklingCore.bootstrap`.
class Repositories {
  const Repositories({
    required this.demo,
    required this.auth,
    required this.customer,
    required this.catalogue,
    required this.loyalty,
    required this.membership,
    required this.staff,
    required this.inventory,
    required this.notifications,
    required this.offlineQueue,
    required this.cache,
    required this.drafts,
    required this.connectivity,
    this.api,
    this.realtime,
    this.demoStore,
  });

  /// `true` when running on in-memory demo data.
  final bool demo;
  final AuthGateway auth;
  final CustomerRepository customer;
  final CatalogueRepository catalogue;
  final LoyaltyRepository loyalty;
  final MembershipRepository membership;
  final StaffRepository staff;
  final InventoryRepository inventory;
  final NotificationsRepository notifications;
  final OfflineQueue offlineQueue;
  final LocalCache cache;
  final DraftStore drafts;
  final ConnectivityService connectivity;

  /// Null in demo mode.
  final SparklingApi? api;

  /// Null in demo mode or when Supabase is not configured.
  final RealtimeService? realtime;

  /// The in-memory data source in demo mode (null in live mode).
  final DemoStore? demoStore;

  /// Runs `POST /auth/session` after sign-in and returns the server-side
  /// [Profile] (claims are refreshed when the API minted new ones).
  ///
  /// In demo mode there is no API: the persona's [DemoStore] profile is
  /// returned (`mustChangePassword` is set for the "new technician"
  /// persona), or `null` without a store. When `API_BASE_URL` is empty or
  /// the request fails with a network error / timeout, throws
  /// [ApiException] with `code == 'network'` so the app can show
  /// "Couldn't reach Sparkling servers" and retry without signing out.
  Future<Profile?> bootstrapSession({
    required String app,
    String? fullName,
    String? phone,
  }) async {
    final a = api;
    if (a == null) {
      final store = _syncedDemoStore();
      return store?.bootstrapSession();
    }
    if (!a.isConfigured) throw ApiException.unreachable();
    try {
      return await SessionBootstrap(
        api: a,
        auth: auth,
      ).run(app: app, fullName: fullName, phone: phone);
    } on ApiException catch (e) {
      if (e.isNetwork) throw ApiException.unreachable();
      rethrow;
    }
  }

  /// Completes the forced password change for a staff account created with
  /// a temporary password (ADM-010, `profile.mustChangePassword`):
  ///
  /// 1. `updatePassword(newPassword)` — re-authenticating with
  ///    [currentPassword] first when Firebase answers
  ///    `requires-recent-login`;
  /// 2. signs in again with the new password so the ID token carries a
  ///    fresh `auth_time` (the API rejects stale sessions with 409
  ///    `stale_session`);
  /// 3. `POST /auth/password-changed` → the updated [Profile]
  ///    (`mustChangePassword == false`).
  ///
  /// Throws [AuthException] (`weak-password`, `wrong-password` /
  /// `invalid-credential`, `network`, …) or [ApiException].
  Future<Profile> completePasswordChange({
    required String email,
    required String currentPassword,
    required String newPassword,
  }) async {
    try {
      await auth.updatePassword(newPassword);
    } on AuthException catch (e) {
      if (!e.requiresRecentLogin) rethrow;
      await auth.reauthenticateWithPassword(currentPassword);
      await auth.updatePassword(newPassword);
    }
    await auth.signInWithEmail(email, newPassword);
    final a = api;
    if (a == null) {
      final store = _syncedDemoStore();
      if (store == null) {
        throw const ApiException(
          code: 'internal',
          message: 'Password change is not available in this build.',
        );
      }
      return store.passwordChanged();
    }
    if (!a.isConfigured) throw ApiException.unreachable();
    try {
      return await a.passwordChanged();
    } on ApiException catch (e) {
      if (e.isNetwork) throw ApiException.unreachable();
      rethrow;
    }
  }

  /// Demo: the store follows the auth persona through a stream listener,
  /// which may not have fired yet right after a sign-in — sync it here.
  DemoStore? _syncedDemoStore() {
    final store = demoStore;
    final u = auth.currentUser;
    if (store != null && u != null && store.currentUser.uid != u.uid) {
      store.signInAs(u);
    }
    return store;
  }

  /// Clears user-scoped local state (call on sign-out).
  Future<void> clearLocalState({bool includeDrafts = false}) async {
    await cache.clear();
    await offlineQueue.clearAll();
    if (includeDrafts) await drafts.clear();
    await realtime?.dispose();
  }

  Future<void> dispose() async {
    await offlineQueue.close();
    await connectivity.dispose();
    await realtime?.dispose();
  }
}

/// Makes [Repositories] available to the widget tree.
///
/// ```dart
/// RepositoriesScope(repositories: repos, child: MaterialApp(...));
/// final repos = RepositoriesScope.of(context);
/// ```
class RepositoriesScope extends InheritedWidget {
  const RepositoriesScope({
    super.key,
    required this.repositories,
    required super.child,
  });

  final Repositories repositories;

  static Repositories of(BuildContext context) {
    final scope = context
        .dependOnInheritedWidgetOfExactType<RepositoriesScope>();
    assert(
      scope != null,
      'No RepositoriesScope found above this widget. Wrap your app with RepositoriesScope.',
    );
    return scope!.repositories;
  }

  static Repositories? maybeOf(BuildContext context) => context
      .dependOnInheritedWidgetOfExactType<RepositoriesScope>()
      ?.repositories;

  @override
  bool updateShouldNotify(RepositoriesScope oldWidget) =>
      oldWidget.repositories != repositories;
}

/// `context.repositories` shorthand.
extension RepositoriesContextX on BuildContext {
  Repositories get repositories => RepositoriesScope.of(this);
}
