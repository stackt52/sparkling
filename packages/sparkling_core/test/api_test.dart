import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sparkling_core/sparkling_core.dart';

/// Records requests and replies with scripted responses.
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

ResponseBody _json(
  Object body, {
  int status = 200,
  Map<String, List<String>>? headers,
}) => ResponseBody.fromString(
  jsonEncode(body),
  status,
  headers: {
    'content-type': ['application/json'],
    ...?headers,
  },
);

void main() {
  late _FakeAdapter adapter;
  late SparklingApi api;

  setUp(() {
    adapter = _FakeAdapter();
    final dio = Dio()..httpClientAdapter = adapter;
    api = SparklingApi(
      baseUrl: 'https://api.test/v1/',
      tokenProvider: () async => 'tok-123',
      clientApp: 'customer',
      clientVersion: '1.0.0+1',
      dio: dio,
    );
  });

  test('adds auth, correlation, client headers and idempotency key', () async {
    adapter.handler = (o) async => _json({
      'id': 'b1',
      'ref': 'SPK-2026-0097',
      'status': 'pending',
      'customer_id': 'c',
      'slot_start': '2026-09-09T07:00:00Z',
      'slot_end': '2026-09-09T07:20:00Z',
    }, status: 201);
    final booking = await api.createBooking(
      BookingInput(
        vehicleId: 'v',
        outletId: 'o',
        serviceId: 's',
        slotStart: DateTime.utc(2026, 9, 9, 7),
        clientOpId: 'op-9',
      ),
    );
    expect(booking.ref, 'SPK-2026-0097');
    final req = adapter.requests.single;
    expect(req.uri.toString(), 'https://api.test/v1/bookings');
    expect(req.method, 'POST');
    expect(req.headers['Authorization'], 'Bearer tok-123');
    expect(req.headers['X-Client-App'], 'customer');
    expect(req.headers['X-Client-Version'], '1.0.0+1');
    expect(req.headers['X-Correlation-Id'], isNotEmpty);
    expect(req.headers['Idempotency-Key'], 'op-9');
    expect(req.data, containsPair('client_op_id', 'op-9'));
  });

  test('omits null query params and stringifies booleans', () async {
    adapter.handler = (o) async => _json({'data': [], 'next_cursor': null});
    final page = await api.bookings(status: null, limit: 25);
    expect(page.items, isEmpty);
    expect(page.hasMore, isFalse);
    expect(adapter.requests.single.uri.query, 'limit=25');

    adapter.handler = (o) async => _json([]);
    await api.adminInventory(outletId: 'o1');
    expect(adapter.requests.last.uri.queryParameters, {
      'outlet_id': 'o1',
      'alerts_first': 'true',
    });
  });

  test('parses the error envelope into ApiException', () async {
    adapter.handler = (o) async => _json({
      'error': {
        'code': 'conflict',
        'message': 'Slot is no longer available',
        'details': [
          {'field': 'slot_start'},
        ],
        'correlation_id': 'corr-1',
        'existing_vehicle_id': 'veh-2',
      },
    }, status: 409);
    try {
      await api.createVehicle(
        const VehicleInput(registrationNo: 'KL 45 MN GP'),
      );
      fail('expected ApiException');
    } on ApiException catch (e) {
      expect(e.code, 'conflict');
      expect(e.statusCode, 409);
      expect(e.isConflict, isTrue);
      expect(e.message, 'Slot is no longer available');
      expect(e.details, hasLength(1));
      expect(e.correlationId, 'corr-1');
      expect(e.existingVehicleId, 'veh-2');
    }
  });

  test('maps 401 to unauthenticated and invokes the callback', () async {
    var called = false;
    final dio = Dio()..httpClientAdapter = adapter;
    api = SparklingApi(
      baseUrl: 'https://api.test/v1',
      tokenProvider: () async => null,
      clientApp: 'staff',
      clientVersion: '1',
      dio: dio,
      onUnauthenticated: () => called = true,
    );
    adapter.handler = (o) async => _json({
      'error': {'code': 'unauthenticated', 'message': 'Please sign in'},
    }, status: 401);
    await expectLater(
      api.me(),
      throwsA(
        isA<ApiException>().having(
          (e) => e.isUnauthenticated,
          'unauthenticated',
          isTrue,
        ),
      ),
    );
    expect(called, isTrue);
    expect(
      adapter.requests.single.headers.containsKey('Authorization'),
      isFalse,
    );
  });

  test('maps connection errors to a retryable network exception', () async {
    adapter.handler = (o) async => throw DioException.connectionError(
      requestOptions: o,
      reason: 'refused',
    );
    await expectLater(
      api.outlets(),
      throwsA(
        isA<ApiException>()
            .having((e) => e.code, 'code', 'network')
            .having((e) => e.isRetryable, 'retryable', isTrue),
      ),
    );
  });

  test('sync batch parses per-op results', () async {
    adapter.handler = (o) async => _json({
      'results': [
        {
          'client_op_id': 'a',
          'status': 'applied',
          'result': {'id': 'x'},
        },
        {'client_op_id': 'b', 'status': 'conflict', 'error': 'State changed'},
      ],
    });
    final results = await api.syncBatch([
      {'client_op_id': 'a', 'kind': 'k', 'payload': {}},
      {'client_op_id': 'b', 'kind': 'k', 'payload': {}},
    ]);
    expect(results[0].applied, isTrue);
    expect(results[1].status, SyncStatus.conflict);
    expect(results[1].error, 'State changed');
  });

  test('typed responses: tasks, leaderboard, ops summary, loyalty', () async {
    adapter.handler = (o) async {
      switch (o.path) {
        case '/tasks':
          return _json([
            {
              'id': 't1',
              'work_order_id': 'w1',
              'outlet_id': 'o1',
              'title': 'Full Valet',
              'status': 'in_progress',
              'priority': 1,
              'work_order': {
                'id': 'w1',
                'ref': 'WO-2026-4821',
                'status': 'in_progress',
                'vehicle': {
                  'id': 'v',
                  'registration_no': 'KL 45 MN GP',
                  'make': 'Toyota',
                  'model': 'Corolla Cross',
                },
                'service': {'name': 'Full Valet'},
                'bay': 'Bay 2',
                'progress': {'steps_done': 4, 'step_count': 7},
              },
            },
          ]);
        case '/staff/leaderboard':
          return _json({
            'rows': [
              {
                'staff_id': 's',
                'name': 'Sipho',
                'points': 1420,
                'rank': 1,
                'delta': 1,
              },
            ],
            'me': {
              'staff_id': 'me',
              'name': 'Thabo M.',
              'points': 820,
              'rank': 5,
              'delta': 1,
            },
            'badges': [
              {
                'badge': {'id': 'b', 'code': 'X', 'name': 'Half century'},
                'earned_at': '2026-09-01T00:00:00Z',
              },
            ],
          });
        case '/staff/ops-summary':
          return _json({
            'counts': {'in_progress': 3, 'queued': 5, 'blocked': 1, 'done': 6},
            'needs_attention': [
              {
                'kind': 'blocked',
                'title': 'WO blocked',
                'link': {'type': 'task', 'id': 't1'},
              },
            ],
            'team_load': [
              {
                'staff_id': 's',
                'name': 'Pieter',
                'active_tasks': 0,
                'capacity': 3,
              },
            ],
          });
        case '/loyalty/account':
          return _json({
            'account': {
              'customer_id': 'c',
              'tier': 'gold',
              'balance_points': 1450,
            },
            'tier_config': [],
            'next_tier': {'name': 'Platinum', 'points_needed': 550},
            'published_version': 14,
          });
      }
      return _json({});
    };
    final tasks = await api.tasks(scope: TaskScope.mine, outletId: 'o1');
    expect(tasks.single.workOrder?.progress.label, '4/7 steps');
    expect(tasks.single.workOrder?.title, 'Full Valet — Toyota Corolla Cross');
    expect(adapter.requests.last.uri.queryParameters['scope'], 'mine');

    final lb = await api.leaderboard(
      outletId: 'o1',
      period: LeaderboardPeriod.month,
    );
    expect(lb.rows.single.points, 1420);
    expect(lb.me?.rank, 5);
    expect(lb.badges.single.earned, isTrue);
    expect(adapter.requests.last.uri.queryParameters['period'], 'month');

    final ops = await api.opsSummary(outletId: 'o1');
    expect(ops.counts.queued, 5);
    expect(ops.needsAttention.single.kind, AttentionKind.blocked);
    expect(ops.teamLoad.single.label, 'Available');

    final acc = await api.loyaltyAccount();
    expect(acc.nextTierLabel, '550 pts to Platinum');
  });
}
