import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sparkling_core/sparkling_core.dart';
import 'package:sparkling_staff/app/session.dart';

import 'test_harness.dart';

/// Records the order of auth calls; claims only appear after
/// [forceRefreshClaims] (mirrors Firebase: no custom claims until the API
/// minted them and the ID token was refreshed).
class _FakeAuth implements AuthGateway {
  _FakeAuth({this.signInClaims = const {}});

  /// Claims the API "mints" (visible only after [forceRefreshClaims]).
  static const Map<String, dynamic> mintedClaims = {'role': 'technician'};

  /// Claims already present in the cached ID token at sign-in (returning
  /// staff); empty for a brand-new account.
  final Map<String, dynamic> signInClaims;
  final List<String> calls = [];
  AuthUser? _user;
  final _controller = StreamController<AuthUser?>.broadcast();

  static const _fresh = AuthUser(
    uid: 'u-new',
    email: 'new.tech@sparkling.co.za',
    displayName: 'New Tech',
  );

  @override
  AuthUser? get currentUser => _user;
  @override
  bool get isSignedIn => _user != null;
  @override
  Stream<AuthUser?> get authStateChanges => _controller.stream;

  void _set(AuthUser? u) {
    _user = u;
    _controller.add(u);
  }

  @override
  Future<AuthUser> signInWithEmail(String email, String password) async {
    calls.add('signInWithEmail');
    final u = _fresh.copyWith(claims: signInClaims);
    _set(u);
    return u;
  }

  @override
  Future<AuthUser> signInWithGoogle() async {
    calls.add('signInWithGoogle');
    final u = _fresh.copyWith(providerIds: const ['google.com']);
    _set(u);
    return u;
  }

  @override
  Future<AuthUser> signUpWithEmail(
    String email,
    String password, {
    String? displayName,
  }) async => throw UnimplementedError();

  @override
  Future<void> sendPasswordReset(String email) async {}

  @override
  Future<void> signOut() async {
    calls.add('signOut');
    _set(null);
  }

  @override
  Future<String?> idToken({bool forceRefresh = false}) async =>
      _user == null ? null : 'tok';

  @override
  Future<Map<String, dynamic>> forceRefreshClaims() async {
    calls.add('forceRefreshClaims');
    _user = _user?.copyWith(claims: mintedClaims);
    return mintedClaims;
  }

  void dispose() => _controller.close();
}

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

Map<String, Object> _profile(String role) => {
  'id': 'p-new',
  'role': role,
  'full_name': 'New Tech',
  'email': 'new.tech@sparkling.co.za',
  'outlet_ids': ['a0000000-0000-4000-8000-000000000002'],
};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final h = DemoHarness()..install();

  late _FakeAuth auth;
  late _FakeAdapter adapter;

  /// Live-mode [Repositories] with a scripted API and the fake auth, reusing
  /// the harness' Hive-backed cache/queue/drafts.
  Repositories live() {
    final base = h.repos;
    final api = SparklingApi(
      baseUrl: 'https://api.test/v1',
      tokenProvider: () => auth.idToken(),
      clientApp: 'staff',
      clientVersion: '0.1.0+1',
      dio: Dio()..httpClientAdapter = adapter,
    );
    return Repositories(
      demo: false,
      auth: auth,
      api: api,
      customer: base.customer,
      catalogue: base.catalogue,
      loyalty: base.loyalty,
      staff: base.staff,
      inventory: base.inventory,
      notifications: base.notifications,
      offlineQueue: base.offlineQueue,
      cache: base.cache,
      drafts: base.drafts,
      connectivity: base.connectivity,
    );
  }

  setUp(() {
    auth = _FakeAuth();
    adapter = _FakeAdapter();
  });
  tearDown(() => auth.dispose());

  test('first sign-in: session is bootstrapped before the staff check, claims '
      'are refreshed and the profile role is used', () async {
    adapter.handler = (o) async =>
        _json({'profile': _profile('supervisor'), 'claims_updated': true});
    final session = SessionController(live());
    addTearDown(session.dispose);

    final ok = await session.signIn('new.tech@sparkling.co.za', 'pw');

    expect(ok, isTrue, reason: session.error);
    expect(session.error, isNull);
    expect(session.isSignedIn, isTrue);
    expect(session.role, UserRole.supervisor);
    expect(session.canSupervise, isTrue);
    expect(session.outletId, 'a0000000-0000-4000-8000-000000000002');
    // sign in → POST /auth/session → refresh claims; never signOut.
    expect(auth.calls, ['signInWithEmail', 'forceRefreshClaims']);
    final req = adapter.requests.single;
    expect(req.uri.path, '/v1/auth/session');
    expect(req.headers['Authorization'], 'Bearer tok');
    expect(jsonDecode(jsonEncode(req.data))['app'], 'staff');
  });

  test('a customer profile is signed out with the not-staff message', () async {
    adapter.handler = (o) async =>
        _json({'profile': _profile('customer'), 'claims_updated': true});
    final session = SessionController(live());
    addTearDown(session.dispose);

    final ok = await session.signIn('someone@example.com', 'pw');

    expect(ok, isFalse);
    expect(session.error, SessionController.notStaffMessage);
    expect(session.isSignedIn, isFalse);
    expect(auth.isSignedIn, isFalse);
    expect(auth.calls.last, 'signOut');
    // The API was still consulted first (claims minted after sign-in).
    expect(adapter.requests, hasLength(1));
  });

  test(
    'API unreachable + no cached claims → rejected as not staff (offline hint)',
    () async {
      adapter.handler = (o) => throw DioException.connectionError(
        requestOptions: o,
        reason: 'Connection refused',
      );
      final session = SessionController(live());
      addTearDown(session.dispose);

      final ok = await session.signIn('new.tech@sparkling.co.za', 'pw');

      expect(ok, isFalse);
      expect(session.error, SessionController.notStaffOfflineMessage);
      expect(session.error, contains('not an outlet staff account'));
      expect(session.isSignedIn, isFalse);
      expect(auth.calls, ['signInWithEmail', 'signOut']);
    },
  );

  test('API unreachable but cached staff claims → signed in', () async {
    adapter.handler = (o) => throw DioException.connectionError(
      requestOptions: o,
      reason: 'Connection refused',
    );
    auth = _FakeAuth(
      signInClaims: const {
        'role': 'technician',
        'outlet_ids': ['a0000000-0000-4000-8000-000000000001'],
      },
    );
    final session = SessionController(live());
    addTearDown(session.dispose);

    final ok = await session.signIn('new.tech@sparkling.co.za', 'pw');

    expect(ok, isTrue, reason: session.error);
    expect(session.isSignedIn, isTrue);
    expect(session.role, UserRole.technician);
    expect(auth.calls, ['signInWithEmail']);
  });

  test('server errors other than network are shown and sign out', () async {
    adapter.handler = (o) async => _json({
      'error': {'code': 'forbidden', 'message': 'Account deactivated'},
    }, status: 403);
    final session = SessionController(live());
    addTearDown(session.dispose);

    final ok = await session.signIn('new.tech@sparkling.co.za', 'pw');

    expect(ok, isFalse);
    expect(session.error, 'Account deactivated');
    expect(session.isSignedIn, isFalse);
    expect(auth.calls.last, 'signOut');
  });

  test('Google sign-in follows the same verification flow', () async {
    adapter.handler = (o) async =>
        _json({'profile': _profile('technician'), 'claims_updated': true});
    final session = SessionController(live());
    addTearDown(session.dispose);

    final ok = await session.signInWithGoogle();

    expect(ok, isTrue, reason: session.error);
    expect(session.usesGoogle, isTrue);
    expect(session.usesProviderReauth, isTrue);
    expect(auth.calls, ['signInWithGoogle', 'forceRefreshClaims']);
  });

  test(
    'lock/unlock re-runs the Google flow for Google-only accounts',
    () async {
      adapter.handler = (o) async =>
          _json({'profile': _profile('technician'), 'claims_updated': true});
      final session = SessionController(live());
      addTearDown(session.dispose);
      await session.signInWithGoogle();
      auth.calls.clear();

      session.lock();
      expect(session.locked, isTrue);

      final ok = await session.unlock('ignored-password');
      expect(ok, isTrue, reason: session.error);
      expect(session.locked, isFalse);
      expect(auth.calls, ['signInWithGoogle']);
    },
  );

  test('lock/unlock uses the password for e-mail accounts', () async {
    adapter.handler = (o) async =>
        _json({'profile': _profile('technician'), 'claims_updated': false});
    final session = SessionController(live());
    addTearDown(session.dispose);
    await session.signIn('new.tech@sparkling.co.za', 'pw');
    auth.calls.clear();

    session.lock();
    final ok = await session.unlock('pw');
    expect(ok, isTrue, reason: session.error);
    expect(session.locked, isFalse);
    expect(auth.calls, ['signInWithEmail']);
  });
}
