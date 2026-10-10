import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sparkling_core/sparkling_core.dart';

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

Map<String, Object?> _task(int done) => {
  'id': 't1',
  'work_order_id': 'w1',
  'outlet_id': 'o1',
  'title': 'Sparkling Wash',
  'seq': 1,
  'status': 'in_progress',
  'priority': 2,
  'assignee_id': 'u1',
  'work_order': {
    'id': 'w1',
    'ref': 'WO-2026-0001',
    'status': 'in_progress',
    'progress': {'steps_done': done, 'step_count': 7},
  },
};

Map<String, Object?> _booking(String status) => {
  'id': 'b1',
  'ref': 'SPK-2026-0097',
  'status': status,
  'customer_id': 'c1',
  'slot_start': '2026-09-09T07:00:00Z',
  'slot_end': '2026-09-09T07:20:00Z',
};

void main() {
  test('cancelling a booking re-emits the customer bookings stream without realtime', () async {
    final adapter = _FakeAdapter();
    var status = 'confirmed';
    adapter.handler = (o) async {
      if (o.path.endsWith('/cancel')) {
        status = 'cancelled';
        return _json(_booking(status));
      }
      return _json({'data': [_booking(status)], 'next_cursor': null});
    };
    final api = SparklingApi(
      baseUrl: 'https://api.test/v1/',
      tokenProvider: () async => 'tok',
      clientApp: 'customer',
      clientVersion: '1.0.0+1',
      dio: Dio()..httpClientAdapter = adapter,
    );
    final repo = ApiCustomerRepository(api: api, uidProvider: () => 'c1');

    final seen = <String>[];
    final sub = repo.watchBookings().listen((l) => seen.add(l.first.status.db));
    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(seen, ['confirmed']);

    await repo.cancelBooking('b1', reason: 'Plans changed');
    // refetchOn debounces local changes by 250 ms.
    await Future<void>.delayed(const Duration(milliseconds: 400));
    expect(seen, ['confirmed', 'cancelled']);

    // Apps can bump the same bus themselves (push received / app resumed).
    announceLocalChange('bookings');
    await Future<void>.delayed(const Duration(milliseconds: 400));
    expect(seen, ['confirmed', 'cancelled', 'cancelled']);
    await sub.cancel();
  });

  test('a completed step re-emits the task list without realtime (local change bus)', () async {
    final adapter = _FakeAdapter();
    var done = 0;
    adapter.handler = (o) async {
      if (o.path.contains('/steps/')) {
        done = 1;
        return _json({
          'result': {
            'work_order_id': 'w1',
            'step_key': 'prewash',
            'status': 'done',
          },
          'progress': {'steps_done': 1, 'step_count': 7},
        });
      }
      return _json({
        'data': [_task(done)],
      });
    };
    final api = SparklingApi(
      baseUrl: 'https://api.test/v1/',
      tokenProvider: () async => 'tok',
      clientApp: 'staff',
      clientVersion: '1.0.0+1',
      dio: Dio()..httpClientAdapter = adapter,
    );
    final repo = ApiStaffRepository(api: api, uidProvider: () => 'u1');

    final seen = <int>[];
    final sub = repo
        .watchTasks(scope: TaskScope.mine)
        .listen((tasks) => seen.add(tasks.first.workOrder!.progress.stepsDone));
    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(seen, [0]);

    await repo.submitStep(
      'w1',
      'prewash',
      const StepResultInput(status: StepStatus.done, clientOpId: 'op-1'),
    );
    // refetchOn debounces local changes by 250 ms.
    await Future<void>.delayed(const Duration(milliseconds: 400));
    expect(seen, [0, 1]);
    await sub.cancel();
  });
}
