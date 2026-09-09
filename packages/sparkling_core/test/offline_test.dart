import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce_flutter/hive_flutter.dart';
import 'package:sparkling_core/sparkling_core.dart';

void main() {
  late Directory dir;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('sparkling_offline_');
    HiveStore.reset();
    await HiveStore.ensureInitialized(path: dir.path);
  });

  tearDown(() async {
    await Hive.deleteFromDisk();
    await Hive.close();
    HiveStore.reset();
    if (dir.existsSync()) dir.deleteSync(recursive: true);
  });

  group('OfflineQueue', () {
    test('enqueue persists, sync applies results in order', () async {
      final posted = <List<String>>[];
      final queue = await OfflineQueue.open(
        boxName: 'q1',
        poster: (ops) async {
          posted.add(ops.map((o) => o.clientOpId).toList());
          return [
            for (final o in ops)
              SyncOperationResult(
                clientOpId: o.clientOpId,
                status: o.kind == 'bad'
                    ? SyncStatus.rejected
                    : (o.kind == 'clash'
                          ? SyncStatus.conflict
                          : SyncStatus.applied),
                result: {'ok': true},
                error: o.kind == 'bad' ? 'Rejected by server' : null,
              ),
          ];
        },
      );
      final emitted = <int>[];
      final sub = queue.changes.listen((ops) => emitted.add(ops.length));

      final a = await queue.enqueue(SyncKinds.stepResult, {
        'work_order_id': 'w',
        'step_key': 'a',
      }, deviceTime: DateTime(2026, 9, 8, 9, 0));
      await queue.enqueue(
        'bad',
        {'x': 1},
        clientOpId: 'op-bad',
        deviceTime: DateTime(2026, 9, 8, 9, 1),
      );
      await queue.enqueue(
        'clash',
        {'x': 2},
        clientOpId: 'op-clash',
        deviceTime: DateTime(2026, 9, 8, 9, 2),
      );
      expect(a.payload['client_op_id'], a.clientOpId);
      expect(queue.pendingCount, 3);
      expect(
        queue.pendingFor(
          kind: SyncKinds.stepResult,
          payloadKey: 'work_order_id',
          payloadValue: 'w',
        ),
        hasLength(1),
      );

      final report = await queue.sync();
      expect(posted.single, [a.clientOpId, 'op-bad', 'op-clash']);
      expect(report.succeeded, 1);
      expect(report.failed, 1);
      expect(report.conflicted, 1);
      expect(queue.pendingCount, 0);
      expect(queue.byId(a.clientOpId)?.status, QueuedOpStatus.succeeded);
      expect(queue.byId(a.clientOpId)?.result, {'ok': true});
      expect(queue.failed.single.lastError, 'Rejected by server');
      expect(queue.conflicted.single.clientOpId, 'op-clash');

      await queue.retry('op-bad');
      expect(queue.pendingCount, 1);
      await queue.clearCompleted();
      expect(
        queue.all.map((o) => o.clientOpId),
        containsAll(['op-bad', 'op-clash']),
      );
      expect(queue.all, hasLength(2));
      expect(emitted, isNotEmpty);
      await sub.cancel();
      await queue.close();
    });

    test(
      'network failure backs off exponentially and resumes after restart',
      () async {
        var t = DateTime(2026, 9, 8, 9, 0);
        var fail = true;
        Future<OfflineQueue> open() => OfflineQueue.open(
          boxName: 'q2',
          baseBackoff: const Duration(seconds: 2),
          clock: () => t,
          poster: (ops) async {
            if (fail) throw ApiException.network();
            return [
              for (final o in ops)
                SyncOperationResult(
                  clientOpId: o.clientOpId,
                  status: SyncStatus.applied,
                ),
            ];
          },
        );

        var queue = await open();
        await queue.enqueue(SyncKinds.taskTransition, {
          'task_id': 't',
          'to': 'in_progress',
        }, clientOpId: 'op-1');
        final r1 = await queue.sync();
        expect(r1.deferred, 1);
        expect(r1.error, isA<ApiException>());
        final op = queue.byId('op-1')!;
        expect(op.status, QueuedOpStatus.pending);
        expect(op.attempts, 1);
        expect(op.nextAttemptAt, t.add(const Duration(seconds: 2)));

        // Not due yet → nothing attempted.
        expect((await queue.sync()).attempted, 0);
        t = t.add(const Duration(seconds: 3));
        expect((await queue.sync()).deferred, 1);
        expect(queue.byId('op-1')!.attempts, 2);
        expect(
          queue.byId('op-1')!.nextAttemptAt,
          t.add(const Duration(seconds: 4)),
        );
        expect(queue.backoffFor(10), const Duration(minutes: 5));

        // Simulate a crash mid-sync: mark syncing, reopen → back to pending.
        fail = false;
        t = t.add(const Duration(minutes: 1));
        await Hive.box<String>('q2').put(
          'op-1',
          '{"client_op_id":"op-1","kind":"task.transition","payload":{"client_op_id":"op-1"},"device_time":"2026-09-08T09:00:00.000Z","status":"syncing","attempts":2}',
        );
        queue = await open();
        expect(queue.byId('op-1')!.status, QueuedOpStatus.pending);
        final r3 = await queue.sync(force: true);
        expect(r3.succeeded, 1);
        expect(queue.byId('op-1')!.status, QueuedOpStatus.succeeded);
        await queue.close();
      },
    );

    test('non-retryable API errors mark the batch failed', () async {
      final queue = await OfflineQueue.open(
        boxName: 'q3',
        poster: (_) async => throw const ApiException(
          code: 'forbidden',
          message: 'nope',
          statusCode: 403,
        ),
      );
      await queue.enqueue('k', {}, clientOpId: 'x');
      final r = await queue.sync();
      expect(r.failed, 1);
      expect(queue.byId('x')!.status, QueuedOpStatus.failed);
      await queue.close();
    });

    test('auto-syncs when connectivity returns', () async {
      var posts = 0;
      final queue = await OfflineQueue.open(
        boxName: 'q4',
        poster: (ops) async {
          posts++;
          return [
            for (final o in ops)
              SyncOperationResult(
                clientOpId: o.clientOpId,
                status: SyncStatus.applied,
              ),
          ];
        },
      );
      final conn = ConnectivityService.fromStream(
        Stream.fromIterable([false, true]).asBroadcastStream(),
        initial: false,
      );
      await queue.enqueue('k', {}, clientOpId: 'y');
      final sub = queue.autoSyncWhenOnline(conn);
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(posts, 1);
      expect(queue.pendingCount, 0);
      await sub.cancel();
      await queue.close();
      await conn.dispose();
    });
  });

  group('LocalCache', () {
    test(
      'stores JSON with lastSyncedAt and serves stale data on failure',
      () async {
        final cache = await LocalCache.open(boxName: 'c1');
        final at = DateTime(2026, 9, 8, 20, 47);
        await cache.put('bookings', [
          {
            'id': 'b1',
            'ref': 'SPK-1',
            'customer_id': 'c',
            'status': 'confirmed',
            'slot_start': '2026-09-08T08:00:00Z',
            'slot_end': '2026-09-08T09:00:00Z',
          },
        ], at: at);
        expect(cache.lastSyncedAt('bookings'), at);
        expect(SparklingDates.hhmm(cache.lastSyncedAt('bookings')!), '20:47');
        final list = cache.getList('bookings', Booking.fromJson)!;
        expect(list.data.single.ref, 'SPK-1');
        expect(cache.latestSync(), at);

        var calls = 0;
        final value = await cache.remember<int>(
          'n',
          fetch: () async {
            calls++;
            return 42;
          },
          encode: (v) => v,
          decode: (d) => d as int,
        );
        expect(value, 42);
        final stale = await cache.remember<int>(
          'n',
          fetch: () async => throw ApiException.network(),
          encode: (v) => v,
          decode: (d) => d as int,
        );
        expect(stale, 42);
        expect(calls, 1);
        await expectLater(
          cache.remember<int>(
            'missing',
            fetch: () async => throw ApiException.network(),
            encode: (v) => v,
            decode: (d) => d as int,
          ),
          throwsA(isA<ApiException>()),
        );
        await cache.remove('n');
        expect(cache.contains('n'), isFalse);
      },
    );
  });

  group('DraftStore', () {
    test('saves, merges and deletes drafts', () async {
      final drafts = await DraftStore.open(boxName: 'd1');
      await drafts.save('booking', {'outlet_id': 'o1', 'step': 1});
      expect(drafts.load('booking'), {'outlet_id': 'o1', 'step': 1});
      expect(drafts.savedAt('booking'), isNotNull);
      await drafts.update('booking', {'step': 2, 'service_id': 's1'});
      expect(drafts.load('booking'), {
        'outlet_id': 'o1',
        'step': 2,
        'service_id': 's1',
      });
      expect(drafts.keys, ['booking']);
      await drafts.delete('booking');
      expect(drafts.has('booking'), isFalse);
    });
  });

  group('ConnectivityService', () {
    test('emits current value then distinct transitions', () async {
      final source = StreamController<bool>.broadcast();
      final conn = ConnectivityService.fromStream(source.stream, initial: true);
      final seen = <bool>[];
      final sub = conn.online.listen(seen.add);
      await Future<void>.delayed(const Duration(milliseconds: 5));
      source.add(true);
      source.add(false);
      source.add(false);
      source.add(true);
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(seen, [true, false, true]);
      expect(conn.lastKnown, isTrue);
      conn.report(false);
      expect(conn.isOffline, isTrue);
      await sub.cancel();
      await conn.dispose();
      await source.close();
    });
  });
}
