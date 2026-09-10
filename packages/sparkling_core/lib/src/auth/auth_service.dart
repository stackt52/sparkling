import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart' as fb;
import 'package:flutter/foundation.dart' show kIsWeb;

import '../api/sparkling_api.dart';
import '../models/enums.dart';
import '../models/profile.dart';

/// Minimal, provider-independent view of the signed-in user.
class AuthUser {
  const AuthUser({
    required this.uid,
    this.email,
    this.displayName,
    this.photoUrl,
    this.emailVerified = false,
    this.claims = const {},
    this.providerIds = const ['password'],
  });

  final String uid;
  final String? email;
  final String? displayName;
  final String? photoUrl;
  final bool emailVerified;

  /// Custom claims (`role`, `outlet_ids`) when known.
  final Map<String, dynamic> claims;

  /// Linked sign-in providers, e.g. `['password']`, `['google.com']`.
  final List<String> providerIds;

  /// `true` when the account can re-authenticate with an e-mail password.
  bool get hasPasswordProvider => providerIds.contains('password');

  /// `true` for accounts signed in through Google.
  bool get hasGoogleProvider => providerIds.contains('google.com');

  /// Re-authentication must go through the provider flow (no password set).
  bool get requiresProviderReauth =>
      !hasPasswordProvider && providerIds.isNotEmpty;

  UserRole get role => UserRole.fromDb(claims['role']?.toString());
  List<String> get outletIds =>
      (claims['outlet_ids'] as List?)?.map((e) => e.toString()).toList() ??
      const [];

  AuthUser copyWith({
    Map<String, dynamic>? claims,
    List<String>? providerIds,
  }) => AuthUser(
    uid: uid,
    email: email,
    displayName: displayName,
    photoUrl: photoUrl,
    emailVerified: emailVerified,
    claims: claims ?? this.claims,
    providerIds: providerIds ?? this.providerIds,
  );

  /// Builds from a Firebase [user]. [claims] should come from the cached ID
  /// token result (see [AuthService.currentUser]) so `role` / `outletIds`
  /// are populated; pass `const {}` when unknown.
  factory AuthUser.fromFirebase(
    fb.User user, {
    Map<String, dynamic> claims = const {},
  }) => AuthUser(
    uid: user.uid,
    email: user.email,
    displayName: user.displayName,
    photoUrl: user.photoURL,
    emailVerified: user.emailVerified,
    claims: claims,
    providerIds: user.providerData
        .map((p) => p.providerId)
        .where((id) => id.isNotEmpty)
        .toList(growable: false),
  );
}

/// Thrown by [AuthGateway] operations with a user-friendly [message].
class AuthException implements Exception {
  const AuthException(this.code, this.message);
  final String code;
  final String message;

  @override
  String toString() => 'AuthException($code): $message';

  factory AuthException.fromFirebase(fb.FirebaseAuthException e) =>
      AuthException(e.code, _friendly(e.code) ?? e.message ?? 'Sign-in failed');

  /// The native provider flow (Google) is not available here — typically on
  /// the iOS simulator / Android emulator without Google Play services, or
  /// when the provider is not enabled in the Firebase console.
  factory AuthException.providerUnavailable([String? detail]) => AuthException(
    'provider-unavailable',
    'Google sign-in is not available on this device'
        '${detail == null ? '' : ' ($detail)'}. '
        'Please sign in with your e-mail and password instead.',
  );

  /// The user dismissed the provider sign-in sheet.
  factory AuthException.cancelled() =>
      const AuthException('cancelled', 'Sign-in was cancelled.');

  bool get isCancelled => code == 'cancelled';

  static String? _friendly(String code) => switch (code) {
    'invalid-email' => 'That e-mail address is not valid.',
    'user-disabled' =>
      'This account has been deactivated. Contact your outlet manager.',
    'user-not-found' ||
    'wrong-password' ||
    'invalid-credential' => 'E-mail or password is incorrect.',
    'email-already-in-use' => 'An account with this e-mail already exists.',
    'weak-password' => 'Choose a stronger password (at least 8 characters).',
    'too-many-requests' =>
      'Too many attempts. Please wait a moment and try again.',
    'network-request-failed' =>
      'No connection. Check your network and try again.',
    'operation-not-allowed' =>
      'This sign-in method is not enabled for Sparkling yet.',
    'account-exists-with-different-credential' => 'An account with this e-mail already exists. Sign in with your password, then link Google from your profile.',
    'requires-recent-login' => 'Please sign in again to continue.',
    _ => null,
  };

  /// Firebase codes that mean the user closed / abandoned a provider sheet.
  static const Set<String> _cancelledCodes = {
    'web-context-cancelled',
    'web-context-canceled',
    'popup-closed-by-user',
    'cancelled-popup-request',
    'user-cancelled',
    'canceled',
  };

  /// Firebase codes that mean the provider flow cannot run in this
  /// environment at all.
  static const Set<String> _unavailableCodes = {
    'operation-not-supported-in-this-environment',
    'unsupported-first-factor',
    'app-not-authorized',
    'invalid-oauth-client-id',
    'web-storage-unsupported',
    'missing-or-invalid-nonce',
    'unauthorized-domain',
  };

  /// Maps errors thrown by a native provider sign-in ([fb.FirebaseAuthException]
  /// or platform / plugin errors) into a clear [AuthException].
  factory AuthException.fromProviderError(Object error) {
    if (error is AuthException) return error;
    if (error is fb.FirebaseAuthException) {
      if (_cancelledCodes.contains(error.code)) {
        return AuthException.cancelled();
      }
      if (_unavailableCodes.contains(error.code) ||
          error.code == 'internal-error') {
        return AuthException.providerUnavailable(error.code);
      }
      return AuthException.fromFirebase(error);
    }
    // MissingPluginException / PlatformException / UnimplementedError etc.
    final text = error.toString();
    final detail = text.length > 80 ? error.runtimeType.toString() : text;
    return AuthException.providerUnavailable(detail);
  }
}

/// Contract shared by [AuthService] (Firebase) and the demo implementation.
abstract interface class AuthGateway {
  AuthUser? get currentUser;
  bool get isSignedIn;
  Stream<AuthUser?> get authStateChanges;

  Future<AuthUser> signInWithEmail(String email, String password);
  Future<AuthUser> signUpWithEmail(
    String email,
    String password, {
    String? displayName,
  });
  Future<AuthUser> signInWithGoogle();
  Future<void> sendPasswordReset(String email);
  Future<void> signOut();

  /// Firebase ID token for `Authorization: Bearer` (null when signed out).
  Future<String?> idToken({bool forceRefresh = false});

  /// Refreshes the token so newly minted custom claims are visible.
  Future<Map<String, dynamic>> forceRefreshClaims();
}

/// Firebase Auth wrapper (CUS-001, STF-001, ADM-001).
///
/// Custom claims are read from the *cached* ID token result (cheap, no
/// network) whenever a user is observed, and force-refreshed through
/// [forceRefreshClaims] after `POST /auth/session` mints new ones.
class AuthService implements AuthGateway {
  AuthService({fb.FirebaseAuth? auth})
    : _auth = auth ?? fb.FirebaseAuth.instance;

  /// Creates the service and, when [emulatorHost] (`host:port`) is non-empty,
  /// points Firebase Auth at the local Auth emulator first. Must run after
  /// `Firebase.initializeApp()` and before any other auth call.
  static Future<AuthService> create({
    String? emulatorHost,
    fb.FirebaseAuth? auth,
  }) async {
    final instance = auth ?? fb.FirebaseAuth.instance;
    if (emulatorHost != null && emulatorHost.trim().isNotEmpty) {
      await configureEmulator(emulatorHost, auth: instance);
    }
    return AuthService(auth: instance);
  }

  /// Parses `host:port` (default port 9099) and calls `useAuthEmulator`.
  /// Idempotent per process: repeated calls with the same target are no-ops.
  static Future<void> configureEmulator(
    String hostPort, {
    fb.FirebaseAuth? auth,
  }) async {
    final trimmed = hostPort.trim();
    if (trimmed.isEmpty) return;
    if (_configuredEmulator == trimmed) return;
    final uri = Uri.tryParse(
      trimmed.contains('://') ? trimmed : 'http://$trimmed',
    );
    if (uri == null || uri.host.isEmpty) {
      throw ArgumentError.value(
        hostPort,
        'hostPort',
        'Expected AUTH_EMULATOR_HOST as host:port, e.g. 127.0.0.1:9099',
      );
    }
    final port = uri.hasPort ? uri.port : 9099;
    await (auth ?? fb.FirebaseAuth.instance).useAuthEmulator(uri.host, port);
    _configuredEmulator = trimmed;
  }

  static String? _configuredEmulator;

  /// `host:port` of the Auth emulator this process is wired to, if any.
  static String? get emulatorHost => _configuredEmulator;

  /// Resets the emulator bookkeeping (tests only).
  static void resetEmulatorForTests() => _configuredEmulator = null;

  final fb.FirebaseAuth _auth;
  Map<String, dynamic> _claims = const {};
  String? _claimsUid;

  Map<String, dynamic> _claimsFor(fb.User u) =>
      _claimsUid == u.uid ? _claims : const {};

  @override
  AuthUser? get currentUser {
    final u = _auth.currentUser;
    return u == null ? null : AuthUser.fromFirebase(u, claims: _claimsFor(u));
  }

  @override
  bool get isSignedIn => _auth.currentUser != null;

  /// Emits on sign-in / sign-out and whenever the user record changes
  /// (`userChanges`: display-name updates after sign-up, linked providers,
  /// token refreshes). Claims are loaded from the cached ID token before each
  /// user is emitted so `role` / `outletIds` are populated.
  @override
  Stream<AuthUser?> get authStateChanges =>
      _auth.userChanges().asyncMap(_withCachedClaims);

  /// Emits whenever the ID token (and therefore claims) changes.
  Stream<AuthUser?> get idTokenChanges =>
      _auth.idTokenChanges().asyncMap(_withCachedClaims);

  Future<AuthUser?> _withCachedClaims(fb.User? u) async {
    if (u == null) {
      _claims = const {};
      _claimsUid = null;
      return null;
    }
    try {
      final result = await u.getIdTokenResult();
      _claims = Map<String, dynamic>.from(result.claims ?? const {});
      _claimsUid = u.uid;
    } catch (_) {
      // Offline with an expired token — keep whatever we had for this uid.
      if (_claimsUid != u.uid) {
        _claims = const {};
        _claimsUid = null;
      }
    }
    return AuthUser.fromFirebase(u, claims: _claimsFor(u));
  }

  @override
  Future<AuthUser> signInWithEmail(String email, String password) =>
      _guard(() async {
        final cred = await _auth.signInWithEmailAndPassword(
          email: email.trim(),
          password: password,
        );
        return (await _withCachedClaims(cred.user!))!;
      });

  @override
  Future<AuthUser> signUpWithEmail(
    String email,
    String password, {
    String? displayName,
  }) => _guard(() async {
    final cred = await _auth.createUserWithEmailAndPassword(
      email: email.trim(),
      password: password,
    );
    var user = cred.user!;
    if (displayName != null && displayName.isNotEmpty) {
      await user.updateDisplayName(displayName);
      user = _auth.currentUser ?? user;
    }
    return (await _withCachedClaims(user))!;
  });

  /// Google sign-in through Firebase's native provider flow (no extra
  /// plugin). Works on Android + iOS devices; on simulators / emulators
  /// without the provider stack it throws
  /// `AuthException(code: 'provider-unavailable')`.
  @override
  Future<AuthUser> signInWithGoogle() async {
    final provider = fb.GoogleAuthProvider()
      ..addScope('email')
      ..setCustomParameters({'prompt': 'select_account'});
    try {
      final cred = kIsWeb
          ? await _auth.signInWithPopup(provider)
          : await _auth.signInWithProvider(provider);
      final user = cred.user ?? _auth.currentUser;
      if (user == null) throw AuthException.providerUnavailable('no user');
      return (await _withCachedClaims(user))!;
    } catch (e) {
      throw AuthException.fromProviderError(e);
    }
  }

  @override
  Future<void> sendPasswordReset(String email) =>
      _guard(() => _auth.sendPasswordResetEmail(email: email.trim()));

  @override
  Future<void> signOut() async {
    _claims = const {};
    _claimsUid = null;
    await _auth.signOut();
  }

  @override
  Future<String?> idToken({bool forceRefresh = false}) async {
    final u = _auth.currentUser;
    if (u == null) return null;
    try {
      return await u.getIdToken(forceRefresh);
    } on fb.FirebaseAuthException catch (e) {
      throw AuthException.fromFirebase(e);
    }
  }

  @override
  Future<Map<String, dynamic>> forceRefreshClaims() async {
    final u = _auth.currentUser;
    if (u == null) return const {};
    try {
      final result = await u.getIdTokenResult(true);
      _claims = Map<String, dynamic>.from(result.claims ?? const {});
      _claimsUid = u.uid;
      return _claims;
    } on fb.FirebaseAuthException catch (e) {
      throw AuthException.fromFirebase(e);
    }
  }

  /// Loads claims from the cached token without forcing a refresh (cheap).
  Future<Map<String, dynamic>> loadClaims() async {
    final u = _auth.currentUser;
    if (u == null) return const {};
    await _withCachedClaims(u);
    return _claimsFor(u);
  }

  Future<T> _guard<T>(Future<T> Function() body) async {
    try {
      return await body();
    } on fb.FirebaseAuthException catch (e) {
      throw AuthException.fromFirebase(e);
    }
  }
}

/// In-memory auth for `DEMO_MODE=true`: any credentials sign in as the demo
/// user; tokens are `demo-token`.
class DemoAuthService implements AuthGateway {
  DemoAuthService({AuthUser? initialUser, this.autoSignIn = true})
    : _user = initialUser ?? (autoSignIn ? demoCustomer : null);

  /// When `true` the demo starts signed in (skip the login screen).
  final bool autoSignIn;

  static const AuthUser demoCustomer = AuthUser(
    uid: 'seed_thabo',
    email: 'thabo@example.com',
    displayName: 'Thabo Nkosi',
    emailVerified: true,
    claims: {'role': 'customer', 'outlet_ids': <String>[]},
  );

  static const AuthUser demoTechnician = AuthUser(
    uid: 'seed_pieter',
    email: 'pieter@sparkling.co.za',
    displayName: 'Pieter van der Merwe',
    emailVerified: true,
    claims: {
      'role': 'technician',
      'outlet_ids': ['a0000000-0000-4000-8000-000000000001'],
    },
  );

  static const AuthUser demoSupervisor = AuthUser(
    uid: 'seed_johan',
    email: 'johan@sparkling.co.za',
    displayName: 'Johan Botha',
    emailVerified: true,
    claims: {
      'role': 'supervisor',
      'outlet_ids': ['a0000000-0000-4000-8000-000000000001'],
    },
  );

  static const AuthUser demoManager = AuthUser(
    uid: 'seed_ayesha',
    email: 'ayesha@sparkling.co.za',
    displayName: 'Ayesha Patel',
    emailVerified: true,
    claims: {
      'role': 'manager',
      'outlet_ids': [
        'a0000000-0000-4000-8000-000000000001',
        'a0000000-0000-4000-8000-000000000002',
      ],
    },
  );

  /// Maps seeded e-mails to demo users so the login form still "works".
  static const Map<String, AuthUser> demoUsers = {
    'thabo@example.com': demoCustomer,
    'pieter@sparkling.co.za': demoTechnician,
    'johan@sparkling.co.za': demoSupervisor,
    'ayesha@sparkling.co.za': demoManager,
  };

  AuthUser? _user;
  final StreamController<AuthUser?> _controller = StreamController.broadcast();

  @override
  AuthUser? get currentUser => _user;

  @override
  bool get isSignedIn => _user != null;

  @override
  Stream<AuthUser?> get authStateChanges async* {
    yield _user;
    yield* _controller.stream;
  }

  void _set(AuthUser? u) {
    _user = u;
    _controller.add(u);
  }

  @override
  Future<AuthUser> signInWithEmail(String email, String password) async {
    final u = demoUsers[email.trim().toLowerCase()] ?? demoCustomer;
    _set(u);
    return u;
  }

  @override
  Future<AuthUser> signUpWithEmail(
    String email,
    String password, {
    String? displayName,
  }) async {
    final u = AuthUser(
      uid: 'demo_${email.hashCode.abs()}',
      email: email,
      displayName: displayName ?? 'Demo User',
      claims: const {'role': 'customer'},
    );
    _set(u);
    return u;
  }

  @override
  Future<AuthUser> signInWithGoogle() async {
    final u = demoCustomer.copyWith(providerIds: const ['google.com']);
    _set(u);
    return u;
  }

  @override
  Future<void> sendPasswordReset(String email) async {}

  @override
  Future<void> signOut() async => _set(null);

  @override
  Future<String?> idToken({bool forceRefresh = false}) async =>
      _user == null ? null : 'demo-token';

  @override
  Future<Map<String, dynamic>> forceRefreshClaims() async =>
      _user?.claims ?? const {};

  void dispose() => _controller.close();
}

/// Runs `POST /v1/auth/session` after sign-in and refreshes the ID token when
/// the API minted new custom claims (ARCHITECTURE.md "Auth flow").
class SessionBootstrap {
  const SessionBootstrap({required this.api, required this.auth});

  final SparklingApi api;
  final AuthGateway auth;

  /// Returns the server-side [Profile]. [app] is `customer|staff|admin`.
  /// Network failures surface as [ApiException] with `isNetwork == true`;
  /// the Firebase session is left intact so the caller can retry.
  Future<Profile> run({
    required String app,
    String? fullName,
    String? phone,
  }) async {
    final session = await api.createSession(
      app: app,
      fullName: fullName,
      phone: phone,
    );
    if (session.claimsUpdated) {
      await auth.forceRefreshClaims();
    } else if (auth is AuthService) {
      await (auth as AuthService).loadClaims();
    }
    return session.profile;
  }
}
