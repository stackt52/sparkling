import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:firebase_auth/firebase_auth.dart' as fb;
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce_flutter/hive_flutter.dart';
import 'package:sparkling_core/sparkling_core.dart';

/// Scripted HTTP adapter (no sockets).
class _FakeAdapter implements HttpClientAdapter {
  final List<RequestOptions> requests = [];
  Future<ResponseBody> Function(RequestOptions o)? handler;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) {
    requests.add(options);
    return handler!(options);
  }

  @override
  void close({bool force = false}) {}
}

ResponseBody _json(Object body, {int status = 200}) => ResponseBody.fromString(
  jsonEncode(body),
  status,
  headers: {
    'content-type': ['application/json'],
  },
);

/// Minimal [AuthGateway] that records claim refreshes.
class _FakeAuth implements AuthGateway {
  _FakeAuth({this.user});

  AuthUser? user;
  int refreshes = 0;
  int signOuts = 0;
  final _controller = StreamController<AuthUser?>.broadcast();

  @override
  AuthUser? get currentUser => user;
  @override
  bool get isSignedIn => user != null;
  @override
  Stream<AuthUser?> get authStateChanges => _controller.stream;

  @override
  Future<AuthUser> signInWithEmail(String email, String password) async {
    calls.add('signIn:$password');
    return user!;
  }

  @override
  Future<AuthUser> signUpWithEmail(
    String email,
    String password, {
    String? displayName,
  }) async => user!;
  @override
  Future<AuthUser> signInWithGoogle() async => user!;
  @override
  Future<void> sendPasswordReset(String email) async {}

  /// Scripted `updatePassword` failures (first call throws when set).
  AuthException? updatePasswordError;
  final List<String> calls = [];

  @override
  Future<void> updatePassword(String newPassword) async {
    calls.add('updatePassword:$newPassword');
    final err = updatePasswordError;
    if (err != null) {
      updatePasswordError = null;
      throw err;
    }
  }

  @override
  Future<void> reauthenticateWithPassword(String password) async {
    calls.add('reauthenticate:$password');
  }

  @override
  Future<void> signOut() async {
    signOuts++;
    user = null;
  }

  @override
  Future<String?> idToken({bool forceRefresh = false}) async =>
      user == null ? null : 'tok';
  @override
  Future<Map<String, dynamic>> forceRefreshClaims() async {
    refreshes++;
    user = user?.copyWith(claims: const {'role': 'technician'});
    return user?.claims ?? const {};
  }
}

const _profileJson = {
  'id': 'p1',
  'role': 'technician',
  'full_name': 'Pieter van der Merwe',
  'email': 'pieter@sparkling.co.za',
  'outlet_ids': ['a0000000-0000-4000-8000-000000000001'],
};

void main() {
  late Directory dir;
  late _FakeAdapter adapter;
  late _FakeAuth auth;

  Future<Repositories> live({required String baseUrl}) async {
    final dio = Dio()..httpClientAdapter = adapter;
    return SparklingCore.bootstrap(
      demo: false,
      clientApp: 'staff',
      apiBaseUrl: baseUrl,
      supabaseUrl: '',
      supabaseAnonKey: '',
      auth: auth,
      dio: dio,
      hivePath: dir.path,
      connectivity: ConnectivityService.alwaysOnline(),
    );
  }

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('sparkling_core_auth_');
    HiveStore.reset();
    adapter = _FakeAdapter();
    auth = _FakeAuth(
      user: const AuthUser(uid: 'u1', email: 'pieter@sparkling.co.za'),
    );
  });

  tearDown(() async {
    await Hive.deleteFromDisk();
    await Hive.close();
    HiveStore.reset();
    if (dir.existsSync()) dir.deleteSync(recursive: true);
  });

  group('Repositories.bootstrapSession', () {
    test(
      'returns the server profile and refreshes claims when minted',
      () async {
        adapter.handler = (o) async =>
            _json({'profile': _profileJson, 'claims_updated': true});
        final repos = await live(baseUrl: 'https://api.test/v1');
        addTearDown(repos.dispose);

        final profile = await repos.bootstrapSession(app: 'staff');
        expect(profile, isNotNull);
        expect(profile!.role, UserRole.technician);
        expect(profile.outletIds, hasLength(1));
        expect(auth.refreshes, 1);
        expect(auth.currentUser!.role, UserRole.technician);
        final req = adapter.requests.single;
        expect(req.uri.path, '/v1/auth/session');
        expect(req.headers['X-Client-App'], 'staff');
        expect(jsonDecode(jsonEncode(req.data))['app'], 'staff');
      },
    );

    test('does not refresh claims when the API did not change them', () async {
      adapter.handler = (o) async =>
          _json({'profile': _profileJson, 'claims_updated': false});
      final repos = await live(baseUrl: 'https://api.test/v1');
      addTearDown(repos.dispose);
      await repos.bootstrapSession(app: 'staff');
      expect(auth.refreshes, 0);
    });

    test('throws ApiException(network) when API_BASE_URL is empty', () async {
      adapter.handler = (o) async => fail('must not hit the network');
      final repos = await live(baseUrl: '');
      addTearDown(repos.dispose);

      await expectLater(
        repos.bootstrapSession(app: 'customer'),
        throwsA(
          isA<ApiException>()
              .having((e) => e.code, 'code', 'network')
              .having((e) => e.isNetwork, 'isNetwork', isTrue)
              .having(
                (e) => e.message,
                'message',
                contains("Couldn't reach Sparkling servers"),
              ),
        ),
      );
      expect(adapter.requests, isEmpty);
      // The Firebase session is untouched.
      expect(auth.signOuts, 0);
      expect(auth.isSignedIn, isTrue);
    });

    test('maps connection failures to ApiException(network)', () async {
      adapter.handler = (o) => throw DioException.connectionError(
        requestOptions: o,
        reason: 'Connection refused',
      );
      final repos = await live(baseUrl: 'http://127.0.0.1:1/v1');
      addTearDown(repos.dispose);

      await expectLater(
        repos.bootstrapSession(app: 'customer'),
        throwsA(
          isA<ApiException>()
              .having((e) => e.code, 'code', 'network')
              .having(
                (e) => e.message,
                'message',
                contains("Couldn't reach Sparkling servers"),
              ),
        ),
      );
      expect(auth.signOuts, 0);
    });

    test('maps timeouts to ApiException(network)', () async {
      adapter.handler = (o) => throw DioException.connectionTimeout(
        requestOptions: o,
        timeout: const Duration(seconds: 1),
      );
      final repos = await live(baseUrl: 'http://127.0.0.1:1/v1');
      addTearDown(repos.dispose);
      await expectLater(
        repos.bootstrapSession(app: 'customer'),
        throwsA(isA<ApiException>().having((e) => e.code, 'code', 'network')),
      );
    });

    test('rethrows server errors untouched (e.g. forbidden)', () async {
      adapter.handler = (o) async => _json({
        'error': {'code': 'forbidden', 'message': 'Deactivated'},
      }, status: 403);
      final repos = await live(baseUrl: 'https://api.test/v1');
      addTearDown(repos.dispose);
      await expectLater(
        repos.bootstrapSession(app: 'staff'),
        throwsA(
          isA<ApiException>()
              .having((e) => e.code, 'code', 'forbidden')
              .having((e) => e.message, 'message', 'Deactivated'),
        ),
      );
    });

    test('demo mode returns the persona profile (no API call)', () async {
      final repos = await SparklingCore.bootstrap(
        demo: true,
        clientApp: 'staff',
        hivePath: dir.path,
      );
      addTearDown(repos.dispose);
      final profile = await repos.bootstrapSession(app: 'staff');
      expect(profile, isNotNull);
      expect(profile!.id, 'seed_pieter');
      expect(profile.role, UserRole.technician);
      expect(profile.mustChangePassword, isFalse);
      expect(adapter.requests, isEmpty);
    });

    test('demo "new technician" persona must change the password', () async {
      final repos = await SparklingCore.bootstrap(
        demo: true,
        clientApp: 'staff',
        hivePath: dir.path,
      );
      addTearDown(repos.dispose);
      await repos.auth.signInWithEmail('nomsa@sparkling.co.za', 'Temp-1234');
      final profile = await repos.bootstrapSession(app: 'staff');
      expect(profile!.id, 'seed_nomsa');
      expect(profile.fullName, 'Nomsa Dube');
      expect(profile.role, UserRole.technician);
      expect(profile.outletIds, [DemoStore.outletMenlyn]);
      expect(profile.mustChangePassword, isTrue);
      expect(profile.passwordChangedAt, isNull);
    });
  });

  group('Repositories.completePasswordChange', () {
    const args = (
      email: 'pieter@sparkling.co.za',
      current: 'Temp-1234',
      next: 'Sparkle-2026',
    );
    Map<String, Object?> changedProfile() => {
      ..._profileJson,
      'must_change_password': false,
      'password_changed_at': '2026-09-15T08:30:00Z',
    };

    test('updates, re-signs in with the new password, then posts '
        'password-changed', () async {
      adapter.handler = (o) async => _json({'profile': changedProfile()});
      final repos = await live(baseUrl: 'https://api.test/v1');
      addTearDown(repos.dispose);

      final profile = await repos.completePasswordChange(
        email: args.email,
        currentPassword: args.current,
        newPassword: args.next,
      );

      expect(profile.mustChangePassword, isFalse);
      expect(profile.passwordChangedAt, DateTime.utc(2026, 9, 15, 8, 30));
      expect(auth.calls, [
        'updatePassword:Sparkle-2026',
        'signIn:Sparkle-2026',
      ]);
      final req = adapter.requests.single;
      expect(req.method, 'POST');
      expect(req.uri.path, '/v1/auth/password-changed');
      expect(req.headers['Authorization'], 'Bearer tok');
    });

    test(
      're-authenticates with the temporary password when Firebase asks',
      () async {
        adapter.handler = (o) async => _json({'profile': changedProfile()});
        auth.updatePasswordError = const AuthException(
          'requires-recent-login',
          'Please sign in again to continue.',
        );
        final repos = await live(baseUrl: 'https://api.test/v1');
        addTearDown(repos.dispose);

        final profile = await repos.completePasswordChange(
          email: args.email,
          currentPassword: args.current,
          newPassword: args.next,
        );

        expect(profile.mustChangePassword, isFalse);
        expect(auth.calls, [
          'updatePassword:Sparkle-2026',
          'reauthenticate:Temp-1234',
          'updatePassword:Sparkle-2026',
          'signIn:Sparkle-2026',
        ]);
        expect(adapter.requests, hasLength(1));
      },
    );

    test('weak-password surfaces before anything else happens', () async {
      adapter.handler = (o) async => fail('must not hit the network');
      auth.updatePasswordError = const AuthException('weak-password', 'weak');
      final repos = await live(baseUrl: 'https://api.test/v1');
      addTearDown(repos.dispose);

      await expectLater(
        repos.completePasswordChange(
          email: args.email,
          currentPassword: args.current,
          newPassword: 'short',
        ),
        throwsA(
          isA<AuthException>().having((e) => e.isWeakPassword, 'weak', isTrue),
        ),
      );
      expect(auth.calls, ['updatePassword:short']);
      expect(adapter.requests, isEmpty);
    });

    test(
      '409 stale_session is exposed as ApiException.isStaleSession',
      () async {
        adapter.handler = (o) async => _json({
          'error': {
            'code': 'validation_error',
            'message': 'Sign in again with your new password',
            'details': {'reason': 'stale_session'},
          },
        }, status: 409);
        final repos = await live(baseUrl: 'https://api.test/v1');
        addTearDown(repos.dispose);

        await expectLater(
          repos.completePasswordChange(
            email: args.email,
            currentPassword: args.current,
            newPassword: args.next,
          ),
          throwsA(
            isA<ApiException>()
                .having((e) => e.isValidation, 'validation', isTrue)
                .having((e) => e.isStaleSession, 'stale', isTrue),
          ),
        );
      },
    );

    test('network failures map to ApiException(network)', () async {
      adapter.handler = (o) => throw DioException.connectionError(
        requestOptions: o,
        reason: 'Connection refused',
      );
      final repos = await live(baseUrl: 'http://127.0.0.1:1/v1');
      addTearDown(repos.dispose);
      await expectLater(
        repos.completePasswordChange(
          email: args.email,
          currentPassword: args.current,
          newPassword: args.next,
        ),
        throwsA(isA<ApiException>().having((e) => e.code, 'code', 'network')),
      );
    });

    test(
      'demo gateway: clears mustChangePassword for the new technician',
      () async {
        final repos = await SparklingCore.bootstrap(
          demo: true,
          clientApp: 'staff',
          hivePath: dir.path,
          demoUser: DemoPersonas.newTechnician,
        );
        addTearDown(repos.dispose);
        final before = await repos.bootstrapSession(app: 'staff');
        expect(before!.mustChangePassword, isTrue);

        final after = await repos.completePasswordChange(
          email: 'nomsa@sparkling.co.za',
          currentPassword: 'Temp-1234',
          newPassword: 'Sparkle-2026',
        );

        expect(after.id, 'seed_nomsa');
        expect(after.mustChangePassword, isFalse);
        expect(after.passwordChangedAt, isNotNull);
        expect(after.outletIds, [DemoStore.outletMenlyn]);
        // Still signed in as Nomsa; the store agrees and stays cleared.
        expect(repos.auth.currentUser?.uid, 'seed_nomsa');
        expect(
          (repos.auth as DemoAuthService).passwords['seed_nomsa'],
          'Sparkle-2026',
        );
        expect(repos.demoStore!.me().mustChangePassword, isFalse);
        final again = await repos.bootstrapSession(app: 'staff');
        expect(again!.mustChangePassword, isFalse);
        // Other personas are untouched.
        expect(
          repos.demoStore!.profiles['seed_pieter']!.mustChangePassword,
          isFalse,
        );
      },
    );

    test('demo gateway rejects a too-short password', () async {
      final repos = await SparklingCore.bootstrap(
        demo: true,
        clientApp: 'staff',
        hivePath: dir.path,
        demoUser: DemoPersonas.newTechnician,
      );
      addTearDown(repos.dispose);
      await expectLater(
        repos.completePasswordChange(
          email: 'nomsa@sparkling.co.za',
          currentPassword: 'Temp-1234',
          newPassword: 'abc',
        ),
        throwsA(
          isA<AuthException>().having((e) => e.code, 'c', 'weak-password'),
        ),
      );
      expect(repos.demoStore!.me().mustChangePassword, isTrue);
    });

    test(
      'DemoStore.passwordChanged clears the flag and stamps the time',
      () async {
        final store = DemoStore(
          currentUser: DemoPersonas.newTechnician,
          clock: () => DateTime.utc(2026, 9, 15, 9),
        );
        addTearDown(store.dispose);
        expect(store.me().mustChangePassword, isTrue);
        final p = store.passwordChanged();
        expect(p.mustChangePassword, isFalse);
        expect(p.passwordChangedAt, DateTime.utc(2026, 9, 15, 9));
        expect(store.me().mustChangePassword, isFalse);
      },
    );
  });

  group('AuthUser', () {
    test('provider helpers', () {
      const pw = AuthUser(uid: 'a');
      expect(pw.hasPasswordProvider, isTrue);
      expect(pw.requiresProviderReauth, isFalse);
      const g = AuthUser(uid: 'b', providerIds: ['google.com']);
      expect(g.hasGoogleProvider, isTrue);
      expect(g.requiresProviderReauth, isTrue);
      expect(
        g.copyWith(claims: const {'role': 'manager'}).role,
        UserRole.manager,
      );
      expect(g.copyWith(claims: const {'role': 'manager'}).providerIds, [
        'google.com',
      ]);
    });
  });

  group('AuthException.fromProviderError', () {
    test('maps cancelled provider sheets', () {
      final e = AuthException.fromProviderError(
        fb.FirebaseAuthException(code: 'web-context-cancelled'),
      );
      expect(e.isCancelled, isTrue);
    });

    test('maps unsupported environments to provider-unavailable', () {
      final e = AuthException.fromProviderError(
        fb.FirebaseAuthException(
          code: 'operation-not-supported-in-this-environment',
        ),
      );
      expect(e.code, 'provider-unavailable');
      expect(e.message, contains('Google sign-in is not available'));
      expect(e.message, contains('e-mail and password'));
    });

    test('maps plugin / platform errors to provider-unavailable', () {
      final e = AuthException.fromProviderError(
        UnimplementedError('signInWithProvider'),
      );
      expect(e.code, 'provider-unavailable');
    });

    test('keeps friendly Firebase messages for other codes', () {
      final e = AuthException.fromProviderError(
        fb.FirebaseAuthException(code: 'operation-not-allowed'),
      );
      expect(e.code, 'operation-not-allowed');
      expect(e.message, contains('not enabled'));
    });
  });

  group('AuthService.configureEmulator', () {
    test('rejects malformed hosts before touching Firebase', () async {
      AuthService.resetEmulatorForTests();
      await expectLater(
        AuthService.configureEmulator('::not a host::'),
        throwsA(isA<ArgumentError>()),
      );
      expect(AuthService.emulatorHost, isNull);
    });

    test('empty host is a no-op', () async {
      AuthService.resetEmulatorForTests();
      await AuthService.configureEmulator('   ');
      expect(AuthService.emulatorHost, isNull);
    });
  });
}
