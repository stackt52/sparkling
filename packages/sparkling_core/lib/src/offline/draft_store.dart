import 'dart:convert';

import 'package:hive_ce/hive.dart';

import '../models/json.dart';
import 'hive_store.dart';

/// Persists in-progress form state by key so users never lose a booking,
/// quote request or checklist input when the app is backgrounded or offline
/// (UX-009).
///
/// ```dart
/// await drafts.save('booking', {'outlet_id': ..., 'service_id': ..., 'step': 2});
/// final d = drafts.load('booking');
/// ```
class DraftStore {
  DraftStore._(this._box);

  final Box<String> _box;

  static const String defaultBoxName = 'sparkling_drafts';

  static Future<DraftStore> open({String boxName = defaultBoxName}) async =>
      DraftStore._(await HiveStore.openBox(boxName));

  Future<void> save(String key, Json draft) => _box.put(
    key,
    jsonEncode({'at': DateTime.now().toUtc().toIso8601String(), 'data': draft}),
  );

  Json? load(String key) {
    final raw = _box.get(key);
    if (raw == null) return null;
    try {
      final m = jsonDecode(raw) as Map<String, dynamic>;
      return Map<String, dynamic>.from(m['data'] as Map);
    } catch (_) {
      return null;
    }
  }

  DateTime? savedAt(String key) {
    final raw = _box.get(key);
    if (raw == null) return null;
    try {
      return DateTime.parse((jsonDecode(raw) as Map)['at'] as String).toLocal();
    } catch (_) {
      return null;
    }
  }

  bool has(String key) => _box.containsKey(key);
  Iterable<String> get keys => _box.keys.map((k) => k.toString());

  /// Merges [patch] into the existing draft (or creates it).
  Future<Json> update(String key, Json patch) async {
    final merged = {...?load(key), ...patch};
    await save(key, merged);
    return merged;
  }

  Future<void> delete(String key) => _box.delete(key);
  Future<void> clear() => _box.clear();
}
