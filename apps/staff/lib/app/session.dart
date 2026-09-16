import 'dart:async';
import 'dart:io' show Platform;

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:sparkling_core/sparkling_core.dart';

/// Signed-in staff session: auth state, role/outlet helpers, idle timeout
/// with re-authentication (STF-001, STF-004), the forced password change
/// for accounts created with a temporary password (ADM-010) and FCM
/// registration.
class SessionController extends ChangeNotifier {
  SessionController(
    this.repositories, {
    this.idleTimeout = const Duration(minutes: 30),
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now {
    _user = repositories.auth.currentUser;
    _mustChangePassword = _loadGate(_user?.uid);
    _sub = repositories.auth.authStateChanges.listen(_onAuth);
    _touch();
  }

  /// [DraftStore] key remembering that the signed-in account still has to
  /// replace its temporary password, so an offline restart is gated too.
  static const String gateStorageKey = 'staff_password_gate';

  final Repositories repositories;

  /// Inactivity window before the app locks and asks for the password again.
  final Duration idleTimeout;
  final DateTime Function() _clock;

  AuthUser? _user;
  bool _mustChangePassword = false;
  String? _temporaryPassword;
  bool _locked = false;
  bool _busy = false;
  bool _authenticating = false;
  String? _error;
  DateTime? _lastActivity;
  Timer? _idleTimer;
  StreamSubscription<AuthUser?>? _sub;

  static const String notStaffMessage =
      'This account is not an outlet staff account. Ask your manager to add '
      'you as staff in the admin dashboard, then sign in again.';
  static const String notStaffOfflineMessage =
      'This account is not an outlet staff account. Sparkling servers '
      "couldn't be reached to verify staff access — try again when you're "
      'online.';

  AuthUser? get user => _user;

  /// `false` while a sign-in is still being verified against the API so the
  /// router does not flash the task list before the staff check completes.
  bool get isSignedIn => _user != null && !_authenticating;
  bool get locked => _locked;

  /// The account was created from the admin dashboard with a temporary
  /// password: every route redirects to the change-password screen until
  /// [completePasswordChange] succeeds (ADM-010).
  bool get mustChangePassword => _user != null && _mustChangePassword;

  /// The temporary password typed on the sign-in form (in memory only,
  /// while [mustChangePassword]) so the change screen can prefill it.
  String? get temporaryPassword =>
      mustChangePassword ? _temporaryPassword : null;
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
    if (u == null) {
      _locked = false;
      _mustChangePassword = false;
      _temporaryPassword = null;
    }
    if (changed) notifyListeners();
  }

  // ---- Temporary-password gate (ADM-010) --------------------------------------

  bool _loadGate(String? uid) {
    if (uid == null) return false;
    final d = repositories.drafts.load(gateStorageKey);
    return d != null && d['uid'] == uid && d['must_change_password'] == true;
  }

  /// Persists the gate. Hive applies the change in memory synchronously;
  /// the disk write is best-effort and never blocks the auth flow.
  void _saveGate() {
    final uid = _user?.uid;
    final write = (_mustChangePassword && uid != null)
        ? repositories.drafts.save(gateStorageKey, {
            'uid': uid,
            'must_change_password': true,
          })
        : repositories.drafts.delete(gateStorageKey);
    unawaited(write.catchError((Object _) {}));
  }

  /// Replaces the temporary password: re-authenticates if needed, updates
  /// the Firebase password, signs in again with the new one and tells the
  /// API (`POST /auth/password-changed`). On success the gate is cleared
  /// (memory + disk) and the router lets the user through.
  Future<bool> completePasswordChange(
    String currentPassword,
    String newPassword,
  ) async {
    final email = _user?.email;
    if (email == null) {
      await signOut();
      return false;
    }
    return _run(
      () async {
        final profile = await repositories.completePasswordChange(
          email: email,
          currentPassword: currentPassword,
          newPassword: newPassword,
        );
        _user = repositories.auth.currentUser ?? _user;
        _mustChangePassword = profile.mustChangePassword;
        _temporaryPassword = null;
        _saveGate();
        _touch();
      },
      fallback: "Couldn't set your password. Please try again.",
      onApiError: (e) => e.isStaleSession
          ? 'Your sign-in is too old to change the password. Sign out, sign '
                'in again with the password you just chose and retry.'
          : null,
    );
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

  Future<bool> signIn(String email, String password) => _authenticate(
    () => repositories.auth.signInWithEmail(email, password),
    password: password,
  );

  /// Google sign-in (same staff verification as e-mail).
  Future<bool> signInWithGoogle() =>
      _authenticate(repositories.auth.signInWithGoogle);

  /// sign in → `POST /auth/session` → check the server profile's role.
  ///
  /// Order matters (STF-001): the API mints the `role` / `outlet_ids` custom
  /// claims *during* the session call, so a first-time staff sign-in has no
  /// claims yet. Anything that fails after Firebase sign-in signs out again so
  /// a non-staff (or unverifiable) account never reaches the task list.
  Future<bool> _authenticate(
    Future<AuthUser> Function() method, {
    String? password,
  }) => _run(() async {
    _authenticating = true;
    try {
      final signedIn = await method();
      try {
        final (user, gate) = await _verifyStaff(signedIn);
        _user = user;
        _mustChangePassword = gate;
      } catch (_) {
        await repositories.auth.signOut();
        _user = null;
        _mustChangePassword = false;
        rethrow;
      }
      _temporaryPassword = _mustChangePassword ? password : null;
      _saveGate();
      _touch();
      unawaited(_registerPush());
    } finally {
      _authenticating = false;
    }
  });

  /// Returns the verified staff user and whether the temporary-password gate
  /// applies (from the server profile; the persisted flag when offline).
  Future<(AuthUser, bool)> _verifyStaff(AuthUser signedIn) async {
    Profile? profile;
    var unreachable = false;
    try {
      profile = await repositories.bootstrapSession(app: 'staff');
    } on ApiException catch (e) {
      // The API refuses unknown / customer accounts on the staff app (403
      // `not_staff`) without creating a profile — surface that plainly.
      if (e.isForbidden) {
        throw AuthException('not_staff', e.message);
      }
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
    if (profile == null) return (current, _loadGate(current.uid));
    // The server profile is authoritative even if the token refresh lagged.
    final user = current.copyWith(
      claims: {
        ...current.claims,
        'role': profile.role.db,
        'outlet_ids': profile.outletIds.isNotEmpty
            ? profile.outletIds
            : current.outletIds,
      },
    );
    return (user, profile.mustChangePassword);
  }

  /// Demo mode only: sign in as one of the seeded personas.
  Future<bool> signInAs(AuthUser persona) =>
      signIn(persona.email ?? '', 'demo');

  Future<void> signOut() async {
    _idleTimer?.cancel();
    // Drop the temporary-password gate first so nothing lingers for the
    // next account even if clearing local state is interrupted.
    _mustChangePassword = false;
    _temporaryPassword = null;
    _saveGate();
    await repositories.auth.signOut();
    await repositories.clearLocalState();
    _locked = false;
    _user = null;
    notifyListeners();
  }

  Future<bool> _run(
    Future<void> Function() body, {
    String fallback = 'Sign-in failed. Please try again.',
    String? Function(ApiException e)? onApiError,
  }) async {
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
      _error = onApiError?.call(e) ?? e.message;
      return false;
    } catch (e) {
      _error = fallback;
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
