import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:sparkling_core/sparkling_core.dart';

import 'push_registration.dart';

/// Auth + profile state for the signed-in customer.
///
/// Listens to [AuthGateway.authStateChanges]; on sign-in it bootstraps the
/// API session (live mode), loads the profile and registers the push token.
class SessionController extends ChangeNotifier {
  SessionController(this.repositories) {
    _user = repositories.auth.currentUser;
    _sub = repositories.auth.authStateChanges.listen(_onAuth);
    if (_user != null) _afterSignIn();
  }

  final Repositories repositories;
  StreamSubscription<AuthUser?>? _sub;

  AuthUser? _user;
  Profile? _profile;
  bool _busy = false;
  bool _bootstrapping = false;
  Object? _error;
  bool _disposed = false;

  /// Name entered on the sign-up form. Firebase emits the new user *before*
  /// `updateDisplayName` completes, so keep it for the greeting and for
  /// `POST /auth/session` (`full_name`).
  String? _pendingName;

  AuthUser? get user => _user;
  Profile? get profile => _profile;
  bool get isSignedIn => _user != null;
  bool get busy => _busy;
  Object? get error => _error;

  /// `POST /auth/session` (or `GET /me`) failed because the Sparkling API
  /// could not be reached. The Firebase session is still valid — the home
  /// screen shows a banner with Retry instead of an error state.
  bool get serverUnreachable {
    final e = _error;
    return e is ApiException && e.isNetwork;
  }

  /// First name for greetings, falling back to the auth display name.
  String get firstName {
    final p = _profile;
    if (p != null && p.fullName.trim().isNotEmpty) return p.firstName;
    final d = _user?.displayName ?? _pendingName;
    if (d != null && d.trim().isNotEmpty) return d.trim().split(' ').first;
    return 'there';
  }

  String get initials =>
      _profile?.initials ?? _initialsOf(_user?.displayName ?? _pendingName);

  static String _initialsOf(String? name) {
    if (name == null || name.trim().isEmpty) return '?';
    final parts = name.trim().split(RegExp(r'\s+'));
    if (parts.length == 1) return parts.first.substring(0, 1).toUpperCase();
    return (parts.first[0] + parts.last[0]).toUpperCase();
  }

  void _onAuth(AuthUser? u) {
    final wasSignedIn = _user != null;
    _user = u;
    if (u == null) {
      _profile = null;
      _notify();
      return;
    }
    if (!wasSignedIn || _profile == null) _afterSignIn();
    _notify();
  }

  /// Bootstraps the API session (live mode) and loads the profile. A network
  /// failure is kept in [error] (see [serverUnreachable]) without signing the
  /// user out; call [retryBootstrap] to try again.
  Future<void> _afterSignIn() async {
    if (_bootstrapping) return;
    _bootstrapping = true;
    _busy = true;
    _error = null;
    _notify();
    try {
      if (!repositories.demo) {
        final p = await repositories.bootstrapSession(
          app: 'customer',
          fullName: _user?.displayName ?? _pendingName,
        );
        if (p != null) _profile = p;
        // Claims may have been minted/refreshed by the session call.
        _user = repositories.auth.currentUser ?? _user;
      }
      _profile = await repositories.customer.me();
      // Best effort — never blocks the UI.
      unawaited(PushRegistration.register(repositories));
    } catch (e) {
      _error = e;
    } finally {
      _bootstrapping = false;
      _busy = false;
      _notify();
    }
  }

  /// Re-runs the session bootstrap after "Couldn't reach Sparkling servers".
  Future<void> retryBootstrap() => _afterSignIn();

  Future<void> refreshProfile() async {
    try {
      _profile = await repositories.customer.me();
      _error = null;
    } catch (e) {
      _error = e;
    }
    _notify();
  }

  /// PATCH /me — optimistic update, reverts on failure and rethrows.
  Future<Profile> updateProfile(ProfileUpdate update) async {
    final previous = _profile;
    if (previous != null) {
      _profile = previous.copyWith(
        fullName: update.fullName,
        phone: update.phone,
        marketingOptIn: update.marketingOptIn,
        whatsappOptIn: update.whatsappOptIn,
        pushOptIn: update.pushOptIn,
        reducedMotion: update.reducedMotion,
        haptics: update.haptics,
      );
      _notify();
    }
    try {
      _profile = await repositories.customer.updateMe(update);
      _notify();
      return _profile!;
    } catch (_) {
      _profile = previous;
      _notify();
      rethrow;
    }
  }

  Future<void> signIn(String email, String password) =>
      repositories.auth.signInWithEmail(email, password);

  Future<void> signUp(String email, String password, String name) async {
    _pendingName = name.trim().isEmpty ? null : name.trim();
    await repositories.auth.signUpWithEmail(email, password, displayName: name);
    _user = repositories.auth.currentUser ?? _user;
    _notify();
  }

  /// Native Google provider flow; throws [AuthException] (`cancelled` /
  /// `provider-unavailable`) when it cannot complete.
  Future<void> signInWithGoogle() => repositories.auth.signInWithGoogle();

  Future<void> continueAsDemoCustomer() =>
      repositories.auth.signInWithEmail(DemoPersonas.customer.email!, '');

  Future<void> signOut() async {
    await repositories.auth.signOut();
    await repositories.clearLocalState();
    _profile = null;
    _pendingName = null;
    _error = null;
    _notify();
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _sub?.cancel();
    super.dispose();
  }
}
