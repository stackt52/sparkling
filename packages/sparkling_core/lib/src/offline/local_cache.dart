import 'dart:convert';

import 'package:hive_ce/hive.dart';

import '../models/json.dart';
import 'hive_store.dart';

/// A cached value with the time it was last fetched from the server.
class CachedEntry<T> {
  const CachedEntry({required this.data, required this.lastSyncedAt});
  final T data;
  final DateTime lastSyncedAt;

  Duration age({DateTime? now}) =>
      (now ?? DateTime.now()).difference(lastSyncedAt);
  bool isStale(Duration maxAge, {DateTime? now}) => age(now: now) > maxAge;
}

/// Durable JSON cache keyed by string with a `lastSyncedAt` per key so UIs
/// can show "Last sync 20:47" and serve stale data offline (CUS-054, NFR-005).
///
/// Values must be JSON-encodable (`Map`, `List`, primitives). Store model
/// JSON via `model.toJson()` and rebuild with `Model.fromJson`.
class LocalCache {
  LocalCache._(this._box);

  final Box<String> _box;

  static const String defaultBoxName = 'sparkling_cache';

  static Future<LocalCache> open({String boxName = defaultBoxName}) async =>
      LocalCache._(await HiveStore.openBox(boxName));

  Future<void> put(String key, Object? json, {DateTime? at}) => _box.put(
    key,
    jsonEncode({
      'at': (at ?? DateTime.now()).toUtc().toIso8601String(),
      'data': json,
    }),
  );

  CachedEntry<dynamic>? get(String key) {
    final raw = _box.get(key);
    if (raw == null) return null;
    try {
      final m = jsonDecode(raw) as Map<String, dynamic>;
      return CachedEntry(
        data: m['data'],
        lastSyncedAt: DateTime.parse(m['at'] as String).toLocal(),
      );
    } catch (_) {
      return null;
    }
  }

  /// Typed convenience for cached objects.
  CachedEntry<T>? getObject<T>(String key, T Function(Json) fromJson) {
    final e = get(key);
    if (e == null || e.data is! Map) return null;
    return CachedEntry(
      data: fromJson(Map<String, dynamic>.from(e.data as Map)),
      lastSyncedAt: e.lastSyncedAt,
    );
  }

  /// Typed convenience for cached lists.
  CachedEntry<List<T>>? getList<T>(String key, T Function(Json) fromJson) {
    final e = get(key);
    if (e == null || e.data is! List) return null;
    final items = (e.data as List)
        .whereType<Map>()
        .map((m) => fromJson(Map<String, dynamic>.from(m)))
        .toList();
    return CachedEntry(data: items, lastSyncedAt: e.lastSyncedAt);
  }

  DateTime? lastSyncedAt(String key) => get(key)?.lastSyncedAt;

  /// Most recent sync time across all keys with the given prefix (for a
  /// screen-level "Last sync" chip).
  DateTime? latestSync({String prefix = ''}) {
    DateTime? latest;
    for (final k in _box.keys) {
      if (!k.toString().startsWith(prefix)) continue;
      final at = lastSyncedAt(k.toString());
      if (at != null && (latest == null || at.isAfter(latest))) latest = at;
    }
    return latest;
  }

  bool contains(String key) => _box.containsKey(key);
  Iterable<String> get keys => _box.keys.map((k) => k.toString());

  Future<void> remove(String key) => _box.delete(key);
  Future<void> clear() => _box.clear();

  /// Stale-while-revalidate helper: returns cached data immediately when
  /// present (and [maxAge] not exceeded when [preferCache]), otherwise
  /// fetches, caches and returns fresh data. On fetch failure falls back to
  /// any cached value before rethrowing.
  Future<T> remember<T>(
    String key, {
    required Future<T> Function() fetch,
    required Object? Function(T value) encode,
    required T Function(dynamic json) decode,
    bool preferCache = false,
    Duration maxAge = const Duration(minutes: 5),
  }) async {
    final cached = get(key);
    if (preferCache && cached != null && !cached.isStale(maxAge)) {
      return decode(cached.data);
    }
    try {
      final fresh = await fetch();
      await put(key, encode(fresh));
      return fresh;
    } catch (_) {
      if (cached != null) return decode(cached.data);
      rethrow;
    }
  }
}
