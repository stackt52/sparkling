import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce_flutter/hive_flutter.dart';
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

ResponseBody _json(Object body, {int status = 200}) => ResponseBody.fromString(
  jsonEncode(body),
  status,
  headers: {
    'content-type': ['application/json'],
  },
);

const _notCheckedInMessage =
    'The vehicle has not been checked in yet — confirm the check-in before '
    'assigning this work order';

/// Work-order check-in gate: `checked_in_at / by` on every work-order shape,
/// `POST /work-orders/:id/checkin`, the `not_checked_in` 409 on assign and
/// the demo mirror (booking check-ins stamp it, converted quotations wait).
void main() {
  group('models', () {
    test('WorkOrder parses checked_in_at / checked_in_by', () {
      final wo = WorkOrder.fromJson({
        'id': 'wo1',
        'ref': 'WO-2026-4819',
        'outlet_id': 'o1',
        'vehicle_id': 'v1',
        'customer_id': 'c1',
        'service_id': 's1',
        'status': 'queued',
        'checked_in_at': '2026-09-22T08:15:00Z',
        'checked_in_by': 'staff_johan',
      });
      expect(wo.isCheckedIn, isTrue);
      expect(wo.checkedInAt, DateTime.utc(2026, 9, 22, 8, 15));
      expect(wo.checkedInBy, 'staff_johan');
      expect(wo.toJson()['checked_in_at'], '2026-09-22T08:15:00.000Z');
      expect(wo.toJson()['checked_in_by'], 'staff_johan');

      final unchecked = WorkOrder.fromJson({
        ...wo.toJson(),
        'checked_in_at': null,
        'checked_in_by': null,
      });
      expect(unchecked.isCheckedIn, isFalse);
      expect(unchecked.toJson().containsKey('checked_in_at'), isFalse);
      expect(unchecked.copyWith(checkedInAt: DateTime(2026)).isCheckedIn, true);
      // Equality tracks the check-in.
      expect(unchecked == wo, isFalse);
    });

    test('task card work_order carries the check-in state', () {
      final task = Task.fromJson({
        'id': 't1',
        'outlet_id': 'o1',
        'title': 'Spot repair',
        'status': 'queued',
        'work_order': {
          'id': 'wo1',
          'ref': 'WO-2026-4819',
          'status': 'queued',
          'checked_in_at': null,
          'checked_in_by': null,
        },
      });
      expect(task.workOrder!.isCheckedIn, isFalse);
      final checked = task.workOrder!.copyWith(
        checkedInAt: DateTime.utc(2026, 9, 22, 9),
        checkedInBy: 'u1',
      );
      expect(checked.isCheckedIn, isTrue);
      expect(checked.toJson()['checked_in_at'], '2026-09-22T09:00:00.000Z');
      expect(
        WorkOrderCard.fromJson(checked.toJson()).checkedInBy,
        'u1',
      );
    });

    test('WorkOrderCheckInResult parses { work_order, task, already }', () {
      final r = WorkOrderCheckInResult.fromJson({
        'work_order': {
          'id': 'wo1',
          'ref': 'WO-2026-4819',
          'outlet_id': 'o1',
          'vehicle_id': 'v1',
          'customer_id': 'c1',
          'service_id': 's1',
          'status': 'assigned',
          'checked_in_at': '2026-09-22T08:15:00Z',
          'checked_in_by': 'u1',
        },
        'task': {
          'id': 't1',
          'work_order_id': 'wo1',
          'outlet_id': 'o1',
          'title': 'Spot repair',
          'status': 'assigned',
          'assignee_id': 'u2',
        },
        'already': true,
      });
      expect(r.already, isTrue);
      expect(r.workOrder.isCheckedIn, isTrue);
      expect(r.task?.assigneeId, 'u2');
      expect(WorkOrderCheckInResult.fromJson(r.toJson()), r);
    });

    test('ApiException.isNotCheckedIn reads the 409 reason', () {
      final nested = ApiException.fromEnvelope({
        'error': {
          'code': 'validation_error',
          'message': _notCheckedInMessage,
          'details': {'reason': 'not_checked_in', 'work_order_id': 'wo1'},
        },
      }, statusCode: 409);
      expect(nested.isNotCheckedIn, isTrue);
      expect(nested.isValidation, isTrue);
      expect(nested.isConflict, isTrue);
      expect(nested.notCheckedInWorkOrderId, 'wo1');

      final flat = ApiException.fromEnvelope({
        'error': {
          'code': 'validation_error',
          'message': _notCheckedInMessage,
          'reason': 'not_checked_in',
          'work_order_id': 'wo1',
        },
      }, statusCode: 409);
      expect(flat.isNotCheckedIn, isTrue);
      expect(flat.notCheckedInWorkOrderId, 'wo1');

      final other = ApiException.fromEnvelope({
        'error': {'code': 'validation_error', 'message': 'x'},
      }, statusCode: 400);
      expect(other.isNotCheckedIn, isFalse);
      expect(other.notCheckedInWorkOrderId, isNull);
    });
  });

  group('API', () {
    late _FakeAdapter adapter;
    late SparklingApi api;

    setUp(() {
      adapter = _FakeAdapter();
      api = SparklingApi(
        baseUrl: 'https://api.test/v1/',
        tokenProvider: () async => 'tok',
        clientApp: 'staff',
        clientVersion: '1.0.0+1',
        dio: Dio()..httpClientAdapter = adapter,
      );
    });

    test('checkInWorkOrder posts /work-orders/:id/checkin { bay }', () async {
      adapter.handler = (o) async => _json({
        'work_order': {
          'id': 'wo1',
          'ref': 'WO-2026-4819',
          'outlet_id': 'o1',
          'vehicle_id': 'v1',
          'customer_id': 'c1',
          'service_id': 's1',
          'status': 'queued',
          'bay': 'Body 2',
          'checked_in_at': '2026-09-22T08:15:00Z',
          'checked_in_by': 'u1',
        },
        'task': {
          'id': 't1',
          'work_order_id': 'wo1',
          'outlet_id': 'o1',
          'title': 'Spot repair',
          'status': 'queued',
        },
        'already': false,
      }, status: 201);
      final r = await api.checkInWorkOrder(
        'wo1',
        bay: 'Body 2',
        idempotencyKey: 'op-1',
      );
      expect(r.already, isFalse);
      expect(r.workOrder.isCheckedIn, isTrue);
      expect(r.workOrder.bay, 'Body 2');
      expect(r.task?.id, 't1');
      final req = adapter.requests.single;
      expect(req.method, 'POST');
      expect(req.uri.path, '/v1/work-orders/wo1/checkin');
      expect(req.data, {'bay': 'Body 2'});
      expect(req.headers['Idempotency-Key'], 'op-1');

      // Without a bay the body is empty.
      adapter.requests.clear();
      await api.checkInWorkOrder('wo1');
      expect(adapter.requests.single.data, isEmpty);
    });

    test('assignTask surfaces the not_checked_in 409', () async {
      adapter.handler = (o) async => _json({
        'error': {
          'code': 'validation_error',
          'message': _notCheckedInMessage,
          'details': {'reason': 'not_checked_in', 'work_order_id': 'wo1'},
          'correlation_id': 'corr-1',
        },
      }, status: 409);
      try {
        await api.assignTask('t1', assigneeId: 'u2');
        fail('expected ApiException');
      } on ApiException catch (e) {
        expect(e.statusCode, 409);
        expect(e.isNotCheckedIn, isTrue);
        expect(e.notCheckedInWorkOrderId, 'wo1');
        expect(e.message, _notCheckedInMessage);
        expect(e.correlationId, 'corr-1');
      }
    });
  });

  group('demo store', () {
    late Directory dir;
    late Repositories repos;
    late DemoStore store;
    final today = DateTime.now();

    Future<void> boot({
      AuthUser persona = DemoPersonas.supervisor,
      bool autoAssignment = true,
    }) async {
      store = DemoStore(
        currentUser: persona,
        clock: () => DateTime(today.year, today.month, today.day, 10, 13),
      );
      store.featureFlags['auto_assignment'] = autoAssignment;
      repos = await SparklingCore.bootstrap(
        demo: true,
        hivePath: dir.path,
        demoStore: store,
        clientApp: 'staff',
        demoUser: persona,
      );
    }

    setUp(() async {
      dir = await Directory.systemTemp.createTemp('sparkling_checkin_');
      HiveStore.reset();
    });

    tearDown(() async {
      await repos.dispose();
      store.dispose();
      await Hive.deleteFromDisk();
      await Hive.close();
      HiveStore.reset();
      if (dir.existsSync()) dir.deleteSync(recursive: true);
    });

    Future<Task> queuedTask() async {
      final queue = await repos.staff.tasks(
        scope: TaskScope.queue,
        outletId: DemoStore.outletMenlyn,
      );
      return queue.firstWhere((t) => t.id == DemoStore.taskAwaitingCheckIn);
    }

    test('seed: converted-quotation work order awaits check-in', () async {
      await boot();
      final task = await queuedTask();
      expect(task.assigneeId, isNull);
      expect(task.status, WorkStatus.queued);
      expect(task.workOrder!.isCheckedIn, isFalse);
      expect(task.workOrder!.ref, 'WO-${today.year}-4819');
      final detail = await repos.staff.workOrder(DemoStore.woAwaitingCheckIn);
      expect(detail.workOrder.isCheckedIn, isFalse);
      expect(detail.workOrder.quotationId, DemoStore.quotationConverted);
      expect(detail.steps, isNotEmpty);
      // Booking-backed work orders were checked in at the counter.
      final inService = await repos.staff.workOrder(DemoStore.woInService);
      expect(inService.workOrder.isCheckedIn, isTrue);
      expect(inService.workOrder.checkedInBy, isNotNull);
      final all = await repos.staff.tasks(
        scope: TaskScope.queue,
        outletId: DemoStore.outletMenlyn,
      );
      expect(
        all.where((t) => !(t.workOrder?.isCheckedIn ?? true)).map((t) => t.id),
        [DemoStore.taskAwaitingCheckIn],
      );
    });

    test('assign refuses with 409 not_checked_in until checked in', () async {
      await boot(autoAssignment: false);
      final task = await queuedTask();
      try {
        await repos.staff.assignTask(task, assigneeId: 'seed_pieter');
        fail('expected ApiException');
      } on ApiException catch (e) {
        expect(e.statusCode, 409);
        expect(e.code, 'validation_error');
        expect(e.isNotCheckedIn, isTrue);
        expect(e.notCheckedInWorkOrderId, DemoStore.woAwaitingCheckIn);
        expect(e.message, _notCheckedInMessage);
      }
      expect((await queuedTask()).assigneeId, isNull);

      final result = await repos.staff.checkInWorkOrder(
        DemoStore.woAwaitingCheckIn,
        bay: 'Body 2',
      );
      expect(result.already, isFalse);
      expect(result.workOrder.isCheckedIn, isTrue);
      expect(result.workOrder.checkedInBy, DemoPersonas.supervisor.uid);
      expect(result.workOrder.bay, 'Body 2');
      // Flag off: nobody was auto-assigned.
      expect(result.task?.assigneeId, isNull);
      expect(result.task?.workOrder?.isCheckedIn, isTrue);

      final assigned = await repos.staff.assignTask(
        await queuedTask(),
        assigneeId: 'seed_pieter',
      );
      expect(assigned.assigneeId, 'seed_pieter');
      expect(assigned.status, WorkStatus.assigned);
      final detail = await repos.staff.workOrder(DemoStore.woAwaitingCheckIn);
      expect(detail.workOrder.assigneeId, 'seed_pieter');
      expect(detail.events.map((e) => e.event), contains('checked_in'));

      // Idempotent: a second check-in reports `already`.
      final again = await repos.staff.checkInWorkOrder(
        DemoStore.woAwaitingCheckIn,
      );
      expect(again.already, isTrue);
      expect(again.workOrder.checkedInAt, result.workOrder.checkedInAt);
    });

    test('check-in auto-assigns when the flag is on', () async {
      await boot();
      final result = await repos.staff.checkInWorkOrder(
        DemoStore.woAwaitingCheckIn,
      );
      expect(result.already, isFalse);
      expect(result.workOrder.isCheckedIn, isTrue);
      expect(result.workOrder.bay, isNull);
      final task = result.task!;
      expect(task.assigneeId, isNotNull);
      expect(task.status, WorkStatus.assigned);
      // Least loaded available team member with an auto-body skill.
      final team = await repos.staff.team(outletId: DemoStore.outletMenlyn);
      final pick = team.firstWhere((m) => m.id == task.assigneeId);
      expect(pick.availability, AvailabilityStatus.available);
      expect(pick.skills, anyOf(contains('paint'), contains('panel')));
      final detail = await repos.staff.workOrder(DemoStore.woAwaitingCheckIn);
      expect(detail.workOrder.assigneeId, task.assigneeId);
      expect(
        detail.events.where((e) => e.event == 'assigned').single.actorName,
        'Auto-assignment',
      );
    });

    test('a technician can check in at their own outlet only', () async {
      await boot(persona: DemoPersonas.technician, autoAssignment: false);
      final result = await repos.staff.checkInWorkOrder(
        DemoStore.woAwaitingCheckIn,
      );
      expect(result.workOrder.checkedInBy, DemoPersonas.technician.uid);
      // Assignment itself stays a supervisor action.
      expect(
        () => repos.staff.assignTask(result.task!, assigneeId: 'seed_pieter'),
        throwsA(isA<ApiException>().having((e) => e.isForbidden, 'forbidden', true)),
      );
    });

    test('booking check-in stamps the work order at once', () async {
      await boot();
      final upcoming = (await repos.staff.outletBookings(
        outletId: DemoStore.outletGlenVillage,
        status: BookingStatus.pending,
      )).firstWhere((b) => b.workOrder == null);
      final booking = await repos.staff.checkinBooking(upcoming.id, bay: 'Bay 4');
      final wo = await repos.staff.workOrder(booking.workOrder!.id);
      expect(wo.workOrder.isCheckedIn, isTrue);
      expect(wo.workOrder.checkedInBy, DemoPersonas.supervisor.uid);
      final again = await repos.staff.checkInWorkOrder(booking.workOrder!.id);
      expect(again.already, isTrue);
    });
  });
}
