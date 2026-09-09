import 'package:hive_ce_flutter/hive_flutter.dart';

/// One-time Hive initialisation shared by [OfflineQueue], [LocalCache] and
/// [DraftStore].
///
/// Apps call `SparklingCore.bootstrap()` which does this; tests pass a
/// temporary [path].
abstract final class HiveStore {
  static bool _initialised = false;

  static Future<void> ensureInitialized({String? path}) async {
    if (_initialised) return;
    if (path != null) {
      Hive.init(path);
    } else {
      await Hive.initFlutter('sparkling');
    }
    _initialised = true;
  }

  /// Opens (or returns the already open) string box.
  static Future<Box<String>> openBox(String name) async {
    if (Hive.isBoxOpen(name)) return Hive.box<String>(name);
    return Hive.openBox<String>(name);
  }

  /// For tests: forget the initialised flag (after `Hive.close()`).
  static void reset() => _initialised = false;
}
