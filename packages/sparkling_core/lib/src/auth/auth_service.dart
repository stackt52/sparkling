import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart' as fb;

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
  });

  final String uid;
  final String? email;
  final String? displayName;
  final String? photoUrl;
  final bool emailVerified;

  /// Custom claims (`role`, `outlet_ids`) when known.
  final Map<String, dynamic> claims;

  UserRole get role => UserRole.fromDb(claims['role']?.toString());
  List<String> get outletIds =>
      (claims['outlet_ids'] as List?)?.map((e) => e.toString()).toList() ??
      const [];

  AuthUser copyWith({Map<String, dynamic>? claims}) => AuthUser(
    uid: uid,
    email: email,
    displayName: displayName,
    photoUrl: photoUrl,
    emailVerified: emailVerified,
    claims: claims ?? this.claims,
  );

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
    _ => null,
  };
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
class AuthService implements AuthGateway {
  AuthService({fb.FirebaseAuth? auth})
    : _auth = auth ?? fb.FirebaseAuth.instance;

  final fb.FirebaseAuth _auth;
  Map<String, dynamic> _claims = const {};

  @override
  AuthUser? get currentUser {
    final u = _auth.currentUser;
    return u == null ? null : AuthUser.fromFirebase(u, claims: _claims);
  }

  @override
  bool get isSignedIn => _auth.currentUser != null;

  @override
  Stream<AuthUser?> get authStateChanges => _auth.authStateChanges().map(
    (u) => u == null ? null : AuthUser.fromFirebase(u, claims: _claims),
  );

  /// Emits whenever the ID token (and therefore claims) changes.
  Stream<AuthUser?> get idTokenChanges => _auth.idTokenChanges().map(
    (u) => u == null ? null : AuthUser.fromFirebase(u, claims: _claims),
  );

  @override
  Future<AuthUser> signInWithEmail(String email, String password) =>
      _guard(() async {
        final cred = await _auth.signInWithEmailAndPassword(
          email: email.trim(),
          password: password,
        );
        return AuthUser.fromFirebase(cred.user!);
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
    if (displayName != null && displayName.isNotEmpty) {
      await cred.user!.updateDisplayName(displayName);
    }
    return AuthUser.fromFirebase(cred.user!);
  });

  /// Google sign-in through Firebase's native provider flow (no extra plugin).
  @override
  Future<AuthUser> signInWithGoogle() => _guard(() async {
    final cred = await _auth.signInWithProvider(fb.GoogleAuthProvider());
    return AuthUser.fromFirebase(cred.user!);
  });

  @override
  Future<void> sendPasswordReset(String email) =>
      _guard(() => _auth.sendPasswordResetEmail(email: email.trim()));

  @override
  Future<void> signOut() async {
    _claims = const {};
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
      return _claims;
    } on fb.FirebaseAuthException catch (e) {
      throw AuthException.fromFirebase(e);
    }
  }

  /// Loads claims without forcing a refresh (cheap).
  Future<Map<String, dynamic>> loadClaims() async {
    final u = _auth.currentUser;
    if (u == null) return const {};
    final result = await u.getIdTokenResult();
    _claims = Map<String, dynamic>.from(result.claims ?? const {});
    return _claims;
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
    _set(demoCustomer);
    return demoCustomer;
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
