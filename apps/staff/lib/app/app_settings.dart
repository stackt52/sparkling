import 'package:flutter/material.dart';
import 'package:sparkling_core/sparkling_core.dart';

/// Device-local preferences (theme, reduced motion, haptics, availability).
///
/// Persisted through the shared [DraftStore] so no extra storage dependency
/// is needed; `reduced_motion` / `haptics` are also mirrored to the profile
/// via `PATCH /me` by the profile screen when online.
class AppSettings extends ChangeNotifier {
  AppSettings(this._drafts) {
    _load();
  }

  static const String storageKey = 'staff_settings';

  final DraftStore _drafts;

  ThemeMode _themeMode = ThemeMode.dark;
  bool _reducedMotion = false;
  bool _haptics = true;
  AvailabilityStatus _availability = AvailabilityStatus.available;

  ThemeMode get themeMode => _themeMode;
  bool get reducedMotion => _reducedMotion;
  bool get haptics => _haptics;
  AvailabilityStatus get availability => _availability;

  void _load() {
    final json = _drafts.load(storageKey);
    if (json == null) return;
    _themeMode = switch (json['theme']) {
      'light' => ThemeMode.light,
      'system' => ThemeMode.system,
      _ => ThemeMode.dark,
    };
    _reducedMotion = json['reduced_motion'] == true;
    _haptics = json['haptics'] != false;
    _availability = AvailabilityStatus.fromDb(json['availability']?.toString());
  }

  Future<void> _save() => _drafts.save(storageKey, {
    'theme': switch (_themeMode) {
      ThemeMode.light => 'light',
      ThemeMode.system => 'system',
      ThemeMode.dark => 'dark',
    },
    'reduced_motion': _reducedMotion,
    'haptics': _haptics,
    'availability': _availability.db,
  });

  void setThemeMode(ThemeMode mode) {
    if (mode == _themeMode) return;
    _themeMode = mode;
    notifyListeners();
    _save();
  }

  void setReducedMotion(bool value) {
    if (value == _reducedMotion) return;
    _reducedMotion = value;
    notifyListeners();
    _save();
  }

  void setHaptics(bool value) {
    if (value == _haptics) return;
    _haptics = value;
    notifyListeners();
    _save();
  }

  void setAvailability(AvailabilityStatus value) {
    if (value == _availability) return;
    _availability = value;
    notifyListeners();
    _save();
  }
}
