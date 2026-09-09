import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:hive_ce/hive.dart';
import 'package:uuid/uuid.dart';

import '../api/api_exception.dart';
import '../models/enums.dart';
import '../models/json.dart';
import '../models/sync.dart';
import 'connectivity_service.dart';
import 'hive_store.dart';

/// Lifecycle of a queued operation.
enum QueuedOpStatus {
  pending,
  syncing,
  succeeded,

  /// Terminal: rejected by the server or too many attempts; needs user action
  /// ([OfflineQueue.retry] or [OfflineQueue.remove]).
  failed,

  /// Terminal: server reported a conflict (e.g. state changed meanwhile).
  conflicted;

  static QueuedOpStatus fromName(String? v) =>
      values.firstWhere((e) => e.name == v, orElse: () => pending);
  bool get isTerminal =>
      this == succeeded || this == failed || this == conflicted;
}

/// One durable operation (DAT-005). `clientOpId` is the idempotency key the
/// server dedupes on.
class QueuedOperation {
  const QueuedOperation({
    required this.clientOpId,
    required this.kind,
    required this.payload,
    required this.deviceTime,
    this.status = QueuedOpStatus.pending,
    this.attempts = 0,
    this.lastError,
    this.nextAttemptAt,
    this.result,
    this.syncedAt,
    this.label,
  });

  final String clientOpId;

  /// One of [SyncKinds].
  final String kind;
  final Json payload;
  final DateTime deviceTime;
  final QueuedOpStatus status;
  final int attempts;
  final String? lastError;
  final DateTime? nextAttemptAt;

  /// Server result once applied.
  final Json? result;
  final DateTime? syncedAt;

  /// Human label for pending-indicator UIs ("Complete step: Hand wash").
  final String? label;

  bool get isPending =>
      status == QueuedOpStatus.pending || status == QueuedOpStatus.syncing;

  /// Body sent in `POST /sync/batch`.
  Json toSyncJson() => {
    'client_op_id': clientOpId,
    'kind': kind,
    'payload': payload,
    'device_time': deviceTime.toUtc().toIso8601String(),
  };

  Json toJson() => compact({
    'client_op_id': clientOpId,
    'kind': kind,
    'payload': payload,
    'device_time': deviceTime.toUtc().toIso8601String(),
    'status': status.name,
    'attempts': attempts,
    'last_error': lastError,
    'next_attempt_at': nextAttemptAt?.toUtc().toIso8601String(),
    'result': result,
    'synced_at': syncedAt?.toUtc().toIso8601String(),
    'label': label,
  });

  factory QueuedOperation.fromJson(Json json) => QueuedOperation(
    clientOpId: str(json['client_op_id']),
    kind: str(json['kind']),
    payload: asJson(json['payload']),
    deviceTime: dt(json['device_time']).toLocal(),
    status: QueuedOpStatus.fromName(strOrNull(json['status'])),
    attempts: intOf(json['attempts']),
    lastError: strOrNull(json['last_error']),
    nextAttemptAt: dtOrNull(json['next_attempt_at'])?.toLocal(),
    result: asJsonOrNull(json['result']),
    syncedAt: dtOrNull(json['synced_at'])?.toLocal(),
    label: strOrNull(json['label']),
  );

  QueuedOperation copyWith({
    QueuedOpStatus? status,
    int? attempts,
    String? lastError,
    DateTime? nextAttemptAt,
    Json? result,
    DateTime? syncedAt,
    bool clearError = false,
    bool clearNextAttempt = false,
  }) => QueuedOperation(
    clientOpId: clientOpId,
    kind: kind,
    payload: payload,
    deviceTime: deviceTime,
    status: status ?? this.status,
    attempts: attempts ?? this.attempts,
    lastError: clearError ? null : (lastError ?? this.lastError),
    nextAttemptAt: clearNextAttempt
        ? null
        : (nextAttemptAt ?? this.nextAttemptAt),
    result: result ?? this.result,
    syncedAt: syncedAt ?? this.syncedAt,
    label: label,
  );
}

/// Posts a batch to the server (normally `SparklingApi.syncBatch`).
typedef SyncBatchPoster = Future<List<SyncOperationResult>> Function(
  List<QueuedOperation> operations,
);

/// Outcome of one [OfflineQueue.sync] call.
class SyncReport {
  const SyncReport({
    this.attempted = 0,
    this.succeeded = 0,
    this.failed = 0,
    this.conflicted = 0,
    this.deferred = 0,
    this.error,
  });

  final int attempted;
  final int succeeded;
  final int failed;
  final int conflicted;

  /// Put back to pending with backoff (network error).
  final int deferred;
  final Object? error;

  bool get isClean => error == null && failed == 0 && conflicted == 0;

  @override
  String toString() =>
      'SyncReport(attempted: $attempted, ok: $succeeded, failed: $failed, conflicted: $conflicted, deferred: $deferred${error == null ? '' : ', error: $error'})';
}

/// Durable, ordered, resumable offline queue backed by Hive (ARC-004, DAT-005).
///
/// * [enqueue] persists immediately and emits on [changes].
/// * [sync] posts pending ops **in device-time order** through `/sync/batch`,
///   applies the per-op results and backs off exponentially on network
///   failure. Ops still `syncing` when the app was killed are resumed as
///   `pending` on [open].
/// * Terminal `failed` / `conflicted` ops stay visible until [retry] or
///   [remove] so the UI can surface them.
class OfflineQueue {
  OfflineQueue._(
    this._box,
    this._poster, {
    required this.baseBackoff,
    required this.maxBackoff,
    required this.maxAttempts,
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now {
    // Resume: anything left mid-flight goes back to pending.
    for (final op in all) {
      if (op.status == QueuedOpStatus.syncing) {
        _write(op.copyWith(status: QueuedOpStatus.pending));
      }
    }
  }

  static const String defaultBoxName = 'sparkling_offline_queue';
  static const Uuid _uuid = Uuid();

  final Box<String> _box;
  final SyncBatchPoster _poster;
  final Duration baseBackoff;
  final Duration maxBackoff;
  final int maxAttempts;
  final DateTime Function() _clock;
  final StreamController<List<QueuedOperation>> _changes =
      StreamController.broadcast();
  bool _syncing = false;
  StreamSubscription<bool>? _autoSync;

  static Future<OfflineQueue> open({
    required SyncBatchPoster poster,
    String boxName = defaultBoxName,
    Duration baseBackoff = const Duration(seconds: 2),
    Duration maxBackoff = const Duration(minutes: 5),
    int maxAttempts = 10,
    DateTime Function()? clock,
  }) async {
    final box = await HiveStore.openBox(boxName);
    return OfflineQueue._(
      box,
      poster,
      baseBackoff: baseBackoff,
      maxBackoff: maxBackoff,
      maxAttempts: maxAttempts,
      clock: clock,
    );
  }

  // ---- Reads -----------------------------------------------------------------

  /// All operations ordered by device time.
  List<QueuedOperation> get all {
    final ops = _box.values
        .map(
          (s) =>
              QueuedOperation.fromJson(jsonDecode(s) as Map<String, dynamic>),
        )
        .toList();
    ops.sort((a, b) => a.deviceTime.compareTo(b.deviceTime));
    return ops;
  }

  List<QueuedOperation> get pending => all.where((o) => o.isPending).toList();
  List<QueuedOperation> get failed =>
      all.where((o) => o.status == QueuedOpStatus.failed).toList();
  List<QueuedOperation> get conflicted =>
      all.where((o) => o.status == QueuedOpStatus.conflicted).toList();
  int get pendingCount => pending.length;
  bool get hasPending => pending.isNotEmpty;
  bool get isSyncing => _syncing;

  QueuedOperation? byId(String clientOpId) {
    final raw = _box.get(clientOpId);
    return raw == null
        ? null
        : QueuedOperation.fromJson(jsonDecode(raw) as Map<String, dynamic>);
  }

  /// Pending ops of a kind touching an entity, e.g. to render "queued" badges.
  List<QueuedOperation> pendingFor({
    String? kind,
    String? payloadKey,
    Object? payloadValue,
  }) => pending.where((o) {
    if (kind != null && o.kind != kind) return false;
    if (payloadKey != null && o.payload[payloadKey] != payloadValue) {
      return false;
    }
    return true;
  }).toList();

  /// Emits the full list after every change.
  Stream<List<QueuedOperation>> get changes => _changes.stream;

  // ---- Writes ----------------------------------------------------------------

  Future<QueuedOperation> enqueue(
    String kind,
    Json payload, {
    String? clientOpId,
    DateTime? deviceTime,
    String? label,
  }) async {
    final id = clientOpId ?? payload['client_op_id']?.toString() ?? _uuid.v4();
    final op = QueuedOperation(
      clientOpId: id,
      kind: kind,
      payload: {...payload, 'client_op_id': id},
      deviceTime: deviceTime ?? _clock(),
      label: label,
    );
    await _write(op);
    _emit();
    return op;
  }

  Future<void> retry(String clientOpId) async {
    final op = byId(clientOpId);
    if (op == null) return;
    await _write(
      op.copyWith(
        status: QueuedOpStatus.pending,
        attempts: 0,
        clearError: true,
        clearNextAttempt: true,
      ),
    );
    _emit();
  }

  Future<void> remove(String clientOpId) async {
    await _box.delete(clientOpId);
    _emit();
  }

  /// Drops succeeded ops older than [olderThan] (default: all succeeded).
  Future<void> clearCompleted({Duration? olderThan}) async {
    final now = _clock();
    for (final op in all) {
      if (op.status != QueuedOpStatus.succeeded) continue;
      if (olderThan != null &&
          op.syncedAt != null &&
          now.difference(op.syncedAt!) < olderThan) {
        continue;
      }
      await _box.delete(op.clientOpId);
    }
    _emit();
  }

  Future<void> clearAll() async {
    await _box.clear();
    _emit();
  }

  // ---- Sync ------------------------------------------------------------------

  Duration backoffFor(int attempts) {
    final ms =
        baseBackoff.inMilliseconds * math.pow(2, math.max(0, attempts - 1));
    return Duration(
      milliseconds: math.min(ms.toInt(), maxBackoff.inMilliseconds),
    );
  }

  /// Posts due pending operations in order. Pass [force] to ignore backoff.
  Future<SyncReport> sync({bool force = false}) async {
    if (_syncing) return const SyncReport();
    final now = _clock();
    final batch = all
        .where(
          (o) =>
              o.status == QueuedOpStatus.pending &&
              (force ||
                  o.nextAttemptAt == null ||
                  !o.nextAttemptAt!.isAfter(now)),
        )
        .toList();
    if (batch.isEmpty) return const SyncReport();

    _syncing = true;
    for (final op in batch) {
      await _write(op.copyWith(status: QueuedOpStatus.syncing));
    }
    _emit();

    var ok = 0, failed = 0, conflicted = 0, deferred = 0;
    try {
      final results = await _poster(batch);
      final byId = {for (final r in results) r.clientOpId: r};
      for (final op in batch) {
        final r = byId[op.clientOpId];
        if (r == null) {
          deferred++;
          await _defer(op, 'No result returned for operation');
          continue;
        }
        switch (r.status) {
          case SyncStatus.applied:
            ok++;
            await _write(
              op.copyWith(
                status: QueuedOpStatus.succeeded,
                result: r.result,
                syncedAt: _clock(),
                clearError: true,
                clearNextAttempt: true,
              ),
            );
          case SyncStatus.conflict:
            conflicted++;
            await _write(
              op.copyWith(
                status: QueuedOpStatus.conflicted,
                result: r.result,
                lastError: r.error ?? 'Conflict',
                clearNextAttempt: true,
              ),
            );
          case SyncStatus.rejected:
            failed++;
            await _write(
              op.copyWith(
                status: QueuedOpStatus.failed,
                result: r.result,
                lastError: r.error ?? 'Rejected',
                clearNextAttempt: true,
              ),
            );
          case SyncStatus.pending:
            deferred++;
            await _defer(op, 'Server still processing');
        }
      }
      _syncing = false;
      _emit();
      return SyncReport(
        attempted: batch.length,
        succeeded: ok,
        failed: failed,
        conflicted: conflicted,
        deferred: deferred,
      );
    } catch (e) {
      final retryable =
          e is! ApiException || e.isRetryable || e.isUnauthenticated;
      for (final op in batch) {
        if (retryable) {
          deferred++;
          await _defer(op, e.toString());
        } else {
          failed++;
          await _write(
            op.copyWith(
              status: QueuedOpStatus.failed,
              lastError: e.toString(),
              clearNextAttempt: true,
            ),
          );
        }
      }
      _syncing = false;
      _emit();
      return SyncReport(
        attempted: batch.length,
        failed: failed,
        deferred: deferred,
        error: e,
      );
    }
  }

  Future<void> _defer(QueuedOperation op, String error) async {
    final attempts = op.attempts + 1;
    if (attempts >= maxAttempts) {
      await _write(
        op.copyWith(
          status: QueuedOpStatus.failed,
          attempts: attempts,
          lastError: 'Gave up after $attempts attempts: $error',
          clearNextAttempt: true,
        ),
      );
      return;
    }
    await _write(
      op.copyWith(
        status: QueuedOpStatus.pending,
        attempts: attempts,
        lastError: error,
        nextAttemptAt: _clock().add(backoffFor(attempts)),
      ),
    );
  }

  /// Syncs whenever connectivity returns. Returns the subscription; cancel on dispose.
  StreamSubscription<bool> autoSyncWhenOnline(
    ConnectivityService connectivity,
  ) {
    _autoSync?.cancel();
    return _autoSync = connectivity.online.listen((online) {
      if (online && hasPending) unawaited(sync());
    });
  }

  Future<void> _write(QueuedOperation op) =>
      _box.put(op.clientOpId, jsonEncode(op.toJson()));

  void _emit() {
    if (!_changes.isClosed) _changes.add(all);
  }

  Future<void> close() async {
    await _autoSync?.cancel();
    await _changes.close();
  }
}
