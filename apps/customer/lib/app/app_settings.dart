import 'package:flutter/material.dart';
import 'package:sparkling_core/sparkling_core.dart';

/// Device-local preferences that are not part of the server profile:
/// theme override (system / light / dark). Persisted in [LocalCache].
class AppSettings extends ChangeNotifier {
  AppSettings(this._cache) {
    final cached = _cache.get(_themeKey)?.data;
    _themeMode = switch (cached) {
      'light' => ThemeMode.light,
      'dark' => ThemeMode.dark,
      _ => ThemeMode.system,
    };
  }

  static const String _themeKey = 'settings:theme_mode';

  final LocalCache _cache;
  ThemeMode _themeMode = ThemeMode.system;

  ThemeMode get themeMode => _themeMode;

  Future<void> setThemeMode(ThemeMode mode) async {
    if (mode == _themeMode) return;
    _themeMode = mode;
    notifyListeners();
    await _cache.put(_themeKey, mode.name);
  }
}
