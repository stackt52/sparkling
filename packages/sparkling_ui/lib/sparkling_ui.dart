/// Sparkling design system — M3 Expressive tokens, theme and shared widgets
/// (SRS UX-001/002/003/004).
///
/// ```dart
/// import 'package:sparkling_ui/sparkling_ui.dart';
///
/// MaterialApp(theme: SparklingTheme.light(), darkTheme: SparklingTheme.dark());
/// ```
///
/// Icons: use `Symbols.<name>_rounded` from `material_symbols_icons`
/// (re-exported here) with `fill: 1` for active/filled glyphs.
library;

export 'package:material_symbols_icons/symbols.dart' show Symbols;

// Tokens
export 'src/tokens/colors.dart';
export 'src/tokens/elevation.dart';
export 'src/tokens/motion.dart';
export 'src/tokens/shapes.dart';
export 'src/tokens/spacing.dart';
export 'src/tokens/typography.dart';

// Theme
export 'src/theme/colors_ext.dart';
export 'src/theme/theme.dart';

// Widgets
export 'src/widgets/audit_note.dart';
export 'src/widgets/badge_tile.dart';
export 'src/widgets/confetti_blob.dart';
export 'src/widgets/date_chip.dart';
export 'src/widgets/drag_handle.dart';
export 'src/widgets/hero_card.dart';
export 'src/widgets/icon_tile_button.dart';
export 'src/widgets/info_banner.dart';
export 'src/widgets/key_value_tile.dart';
export 'src/widgets/linear_level_bar.dart';
export 'src/widgets/list_tile_card.dart';
export 'src/widgets/notification_bell.dart';
export 'src/widgets/offline_banner.dart';
export 'src/widgets/photo_placeholder.dart';
export 'src/widgets/pill_button.dart';
export 'src/widgets/podium_widget.dart';
export 'src/widgets/priority_chip.dart';
export 'src/widgets/progress_ring.dart';
export 'src/widgets/quick_action_card.dart';
export 'src/widgets/radio_card.dart';
export 'src/widgets/scan_frame_overlay.dart';
export 'src/widgets/section_header.dart';
export 'src/widgets/slot_chip.dart';
export 'src/widgets/sparkling_logo.dart';
export 'src/widgets/stat_tile.dart';
export 'src/widgets/status_chip.dart';
export 'src/widgets/step_progress_strip.dart';
export 'src/widgets/sync_chip.dart';
export 'src/widgets/tier_pill.dart';
export 'src/widgets/timeline_tile.dart';
export 'src/widgets/vehicle_card.dart';
