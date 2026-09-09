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
  String? _error;
  DateTime? _lastActivity;
  Timer? _idleTimer;
  StreamSubscription<AuthUser?>? _sub;

  AuthUser? get user => _user;
  bool get isSignedIn => _user != null;
  bool get locked => _locked;
  bool get busy => _busy;
  String? get error => _error;
  bool get demo => repositories.demo;

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
    final changed = u?.uid != _user?.uid;
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

  /// Re-authenticates with the existing e-mail (STF-004).
  Future<bool> unlock(String password) async {
    final email = _user?.email;
    if (email == null) {
      await signOut();
      return false;
    }
    return _run(() async {
      await repositories.auth.signInWithEmail(email, password);
      _locked = false;
      _touch();
    });
  }

  // ---- Sign in / out ---------------------------------------------------------

  Future<bool> signIn(String email, String password) => _run(() async {
    final u = await repositories.auth.signInWithEmail(email, password);
    if (!u.role.isStaff) {
      await repositories.auth.signOut();
      throw const AuthException(
        'not_staff',
        'This account is not an outlet staff account.',
      );
    }
    await repositories.bootstrapSession(app: 'staff');
    _user = repositories.auth.currentUser ?? u;
    _touch();
    unawaited(_registerPush());
  });

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
