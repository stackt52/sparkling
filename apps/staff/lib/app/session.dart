import 'dart:async';
import 'dart:io' show Platform;

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:sparkling_core/sparkling_core.dart';

/// Signed-in staff session: auth state, role/outlet helpers, idle timeout
/// with re-authentication (STF-001, STF-004) and FCM registration.
class SessionController extends ChangeNotifier {
  SessionController(
    this.repositories, {
    this.idleTimeout = const Duration(minutes: 30),
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now {
    _user = repositories.auth.currentUser;
    _sub = repositories.auth.authStateChanges.listen(_onAuth);
    _touch();
  }

  final Repositories repositories;

  /// Inactivity window before the app locks and asks for the password again.
  final Duration idleTimeout;
  final DateTime Function() _clock;

  AuthUser? _user;
  bool _locked = false;
  bool _busy = false;
  bool _authenticating = false;
  String? _error;
  DateTime? _lastActivity;
  Timer? _idleTimer;
  StreamSubscription<AuthUser?>? _sub;

  static const String notStaffMessage =
      'This account is not an outlet staff account.';
  static const String notStaffOfflineMessage =
      'This account is not an outlet staff account. Sparkling servers '
      "couldn't be reached to verify staff access — try again when you're "
      'online.';

  AuthUser? get user => _user;

  /// `false` while a sign-in is still being verified against the API so the
  /// router does not flash the task list before the staff check completes.
  bool get isSignedIn => _user != null && !_authenticating;
  bool get locked => _locked;
  bool get busy => _busy;
  String? get error => _error;
  bool get demo => repositories.demo;

  /// The signed-in account has no password (Google-only): unlocking must go
  /// through [unlockWithGoogle] instead of [unlock].
  bool get usesProviderReauth => _user?.requiresProviderReauth ?? false;
  bool get usesGoogle => _user?.hasGoogleProvider ?? false;

  UserRole get role => _user?.role ?? UserRole.technician;
  bool get canSupervise => role.canSupervise;
  bool get isManager => role.isManager;

  /// Primary outlet for the session (first claim). Falls back to the seeded
  /// Sandton outlet so demo screens always have data.
  String get outletId =>
      _user?.outletIds.firstOrNull ?? 'a0000000-0000-4000-8000-000000000001';
  List<String> get outletIds => _user?.outletIds ?? const [];

  String get displayName => _user?.displayName ?? _user?.email ?? 'Staff';

  void _onAuth(AuthUser? u) {
    final changed =
        u?.uid != _user?.uid ||
        u?.role != _user?.role ||
        !listEquals(u?.outletIds, _user?.outletIds);
    _user = u;
    if (u == null) _locked = false;
    if (changed) notifyListeners();
  }

  // ---- Activity / lock -------------------------------------------------------

  /// Call on any user interaction to keep the session alive.
  void touch() {
    if (_locked) return;
    _touch();
  }

  void _touch() {
    _lastActivity = _clock();
    _idleTimer?.cancel();
    _idleTimer = Timer(idleTimeout, lock);
  }

  /// Called when the app returns to the foreground.
  void resumed() {
    final last = _lastActivity;
    if (last != null && _clock().difference(last) >= idleTimeout) {
      lock();
    } else {
      _touch();
    }
  }

  void lock() {
    if (!isSignedIn || _locked) return;
    _idleTimer?.cancel();
    _locked = true;
    notifyListeners();
  }

  /// Re-authenticates with the existing e-mail + password (STF-004).
  Future<bool> unlock(String password) async {
    final email = _user?.email;
    if (email == null) {
      await signOut();
      return false;
    }
    if (usesProviderReauth) return unlockWithGoogle();
    return _run(() async {
      await repositories.auth.signInWithEmail(email, password);
      _locked = false;
      _touch();
    });
  }

  /// Re-authenticates a Google account by running the provider flow again.
  /// Picking a different Google account signs the session out.
  Future<bool> unlockWithGoogle() => _run(() async {
    final before = _user?.uid;
    final u = await repositories.auth.signInWithGoogle();
    if (before != null && u.uid != before) {
      await repositories.auth.signOut();
      _user = null;
      _locked = false;
      throw const AuthException(
        'wrong_account',
        'That is a different Google account. Sign in again to continue.',
      );
    }
    _locked = false;
    _touch();
  });

  // ---- Sign in / out ---------------------------------------------------------

  Future<bool> signIn(String email, String password) =>
      _authenticate(() => repositories.auth.signInWithEmail(email, password));

  /// Google sign-in (same staff verification as e-mail).
  Future<bool> signInWithGoogle() =>
      _authenticate(repositories.auth.signInWithGoogle);

  /// sign in → `POST /auth/session` → check the server profile's role.
  ///
  /// Order matters (STF-001): the API mints the `role` / `outlet_ids` custom
  /// claims *during* the session call, so a first-time staff sign-in has no
  /// claims yet. Anything that fails after Firebase sign-in signs out again so
  /// a non-staff (or unverifiable) account never reaches the task list.
  Future<bool> _authenticate(Future<AuthUser> Function() method) =>
      _run(() async {
        _authenticating = true;
        try {
          final signedIn = await method();
          try {
            _user = await _verifyStaff(signedIn);
          } catch (_) {
            await repositories.auth.signOut();
            _user = null;
            rethrow;
          }
          _touch();
          unawaited(_registerPush());
        } finally {
          _authenticating = false;
        }
      });

  Future<AuthUser> _verifyStaff(AuthUser signedIn) async {
    Profile? profile;
    var unreachable = false;
    try {
      profile = await repositories.bootstrapSession(app: 'staff');
    } on ApiException catch (e) {
      // Offline / API down: fall back to claims cached in the ID token
      // (returning staff keep working; brand-new accounts cannot be verified).
      if (!e.isNetwork) rethrow;
      unreachable = true;
    }
    final current = repositories.auth.currentUser ?? signedIn;
    final role = profile?.role ?? current.role;
    if (!role.isStaff) {
      throw AuthException(
        'not_staff',
        unreachable ? notStaffOfflineMessage : notStaffMessage,
      );
    }
    if (profile == null) return current;
    // The server profile is authoritative even if the token refresh lagged.
    return current.copyWith(
      claims: {
        ...current.claims,
        'role': profile.role.db,
        'outlet_ids': profile.outletIds.isNotEmpty
            ? profile.outletIds
            : current.outletIds,
      },
    );
  }

  /// Demo mode only: sign in as one of the seeded personas.
  Future<bool> signInAs(AuthUser persona) =>
      signIn(persona.email ?? '', 'demo');

  Future<void> signOut() async {
    _idleTimer?.cancel();
    await repositories.auth.signOut();
    await repositories.clearLocalState();
    _locked = false;
    _user = null;
    notifyListeners();
  }

  Future<bool> _run(Future<void> Function() body) async {
    _busy = true;
    _error = null;
    notifyListeners();
    try {
      await body();
      return true;
    } on AuthException catch (e) {
      _error = e.message;
      return false;
    } on ApiException catch (e) {
      _error = e.message;
      return false;
    } catch (e) {
      _error = 'Sign-in failed. Please try again.';
      return false;
    } finally {
      _busy = false;
      notifyListeners();
    }
  }

  /// Registers the FCM token with `POST /devices` (INT-003). No-op in demo.
  Future<void> _registerPush() async {
    final api = repositories.api;
    if (api == null || kIsWeb) return;
    try {
      final messaging = FirebaseMessaging.instance;
      await messaging.requestPermission();
      final token = await messaging.getToken();
      if (token == null) return;
      await api.registerDevice(
        DeviceTokenInput(
          token: token,
          platform: Platform.isIOS ? 'ios' : 'android',
          app: 'staff',
        ),
      );
    } catch (_) {
      // Push registration is best-effort; the app works without it.
    }
  }

  @override
  void dispose() {
    _idleTimer?.cancel();
    _sub?.cancel();
    super.dispose();
  }
}
