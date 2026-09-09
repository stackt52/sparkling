import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:sparkling_core/sparkling_core.dart';
import 'package:sparkling_ui/sparkling_ui.dart';

/// Derives the header sync chip (STF-062) and the sync centre (NFR-005) from
/// the offline queue + connectivity.
class SyncStatusController extends ChangeNotifier {
  SyncStatusController(this.repositories) {
    _online = repositories.connectivity.lastKnown;
    _ops = repositories.offlineQueue.all;
    _lastSync = _latestSyncFromOps() ?? repositories.cache.latestSync();
    _queueSub = repositories.offlineQueue.changes.listen((ops) {
      _ops = ops;
      _lastSync = _latestSyncFromOps() ?? _lastSync;
      notifyListeners();
    });
    _connSub = repositories.connectivity.online.listen((online) {
      if (online == _online) return;
      _online = online;
      notifyListeners();
    });
  }

  final Repositories repositories;

  bool _online = true;
  List<QueuedOperation> _ops = const [];
  DateTime? _lastSync;
  bool _syncing = false;
  StreamSubscription<List<QueuedOperation>>? _queueSub;
  StreamSubscription<bool>? _connSub;

  bool get online => _online;
  bool get syncing => _syncing;
  List<QueuedOperation> get operations => _ops;
  List<QueuedOperation> get pending => _ops.where((o) => o.isPending).toList();
  List<QueuedOperation> get needsAttention => _ops
      .where(
        (o) =>
            o.status == QueuedOpStatus.failed ||
            o.status == QueuedOpStatus.conflicted,
      )
      .toList();
  int get pendingCount => pending.length;
  DateTime? get lastSync => _lastSync;

  SyncState get state {
    if (!_online) return SyncState.offline;
    if (pending.isNotEmpty || needsAttention.isNotEmpty) {
      return SyncState.queued;
    }
    return SyncState.synced;
  }

  /// "Synced 09:41" / "3 queued" / "Offline · 2 queued".
  String get label => switch (state) {
    SyncState.synced =>
      _lastSync == null
          ? 'Synced'
          : 'Synced ${SparklingDates.hhmm(_lastSync!)}',
    SyncState.queued =>
      needsAttention.isNotEmpty && pending.isEmpty
          ? '${needsAttention.length} need attention'
          : '${pending.length + needsAttention.length} queued',
    SyncState.offline =>
      pending.isEmpty ? 'Offline' : 'Offline · ${pending.length} queued',
  };

  /// Records a successful server round-trip (called by screens after a fetch).
  void markSynced([DateTime? at]) {
    final t = at ?? DateTime.now();
    if (_lastSync != null && !t.isAfter(_lastSync!)) return;
    _lastSync = t;
    notifyListeners();
  }

  Future<SyncReport> syncNow() async {
    _syncing = true;
    notifyListeners();
    try {
      final report = await repositories.offlineQueue.sync(force: true);
      if (report.succeeded > 0 || report.attempted == 0) markSynced();
      return report;
    } finally {
      _syncing = false;
      notifyListeners();
    }
  }

  Future<void> retry(String clientOpId) async {
    await repositories.offlineQueue.retry(clientOpId);
    await syncNow();
  }

  Future<void> remove(String clientOpId) =>
      repositories.offlineQueue.remove(clientOpId);

  Future<void> clearCompleted() => repositories.offlineQueue.clearCompleted();

  DateTime? _latestSyncFromOps() {
    DateTime? latest;
    for (final o in _ops) {
      final at = o.syncedAt;
      if (at != null && (latest == null || at.isAfter(latest))) latest = at;
    }
    return latest;
  }

  @override
  void dispose() {
    _queueSub?.cancel();
    _connSub?.cancel();
    super.dispose();
  }
}
