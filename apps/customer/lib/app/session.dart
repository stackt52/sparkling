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
  Object? _error;
  bool _disposed = false;

  AuthUser? get user => _user;
  Profile? get profile => _profile;
  bool get isSignedIn => _user != null;
  bool get busy => _busy;
  Object? get error => _error;

  /// First name for greetings, falling back to the auth display name.
  String get firstName {
    final p = _profile;
    if (p != null && p.fullName.trim().isNotEmpty) return p.firstName;
    final d = _user?.displayName;
    if (d != null && d.trim().isNotEmpty) return d.trim().split(' ').first;
    return 'there';
  }

  String get initials => _profile?.initials ?? _initialsOf(_user?.displayName);

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

  Future<void> _afterSignIn() async {
    _busy = true;
    _error = null;
    _notify();
    try {
      if (!repositories.demo) {
        await repositories.bootstrapSession(
          app: 'customer',
          fullName: _user?.displayName,
        );
      }
      _profile = await repositories.customer.me();
      // Best effort — never blocks the UI.
      unawaited(PushRegistration.register(repositories));
    } catch (e) {
      _error = e;
    } finally {
      _busy = false;
      _notify();
    }
  }

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

  Future<void> signUp(String email, String password, String name) =>
      repositories.auth.signUpWithEmail(email, password, displayName: name);

  Future<void> continueAsDemoCustomer() =>
      repositories.auth.signInWithEmail(DemoPersonas.customer.email!, '');

  Future<void> signOut() async {
    await repositories.auth.signOut();
    await repositories.clearLocalState();
    _profile = null;
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
