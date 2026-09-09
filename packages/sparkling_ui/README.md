# sparkling_ui

Sparkling design system for the Flutter apps (SRS UX-001..004): Material 3
Expressive tokens, theme and shared widgets derived from
`design_handoff_sparkling_apps/README.md`.

```dart
import 'package:sparkling_ui/sparkling_ui.dart';

MaterialApp(
  theme: SparklingTheme.light(),
  darkTheme: SparklingTheme.dark(),
  home: SparklingMotionScope(reducedMotion: profile.reducedMotion, child: const Home()),
);
```

- Tokens: `SparklingColors`, `SparklingTypography` (Outfit / JetBrains Mono via google_fonts),
  `SparklingShapes`, `SparklingSpacing`, `SparklingMotion`, `SparklingElevation`.
- Theme: `SparklingTheme.light()/dark()`, `SparklingColorsExt` (`context.sparkling`).
- Icons: `Symbols.<name>_rounded` (re-exported from material_symbols_icons), `fill: 1` when active.
- Widgets: `HeroCard`, `StatusChip`, `PriorityChip`, `TierPill`, `SyncChip`, `OfflineBanner`,
  `ProgressRing`, `LinearLevelBar`, `StepProgressStrip`, `RadioCard`, `SlotChip`, `DateChip`,
  `TimelineTile`, `SectionHeader`, `StatTile`, `QuickActionCard`, `VehicleCard`, `ListTileCard`,
  `PillButton`, `IconTileButton`, `NotificationBell`, `ConfettiBlob`, `ScanFrameOverlay`,
  `PhotoPlaceholder`, `DragHandle`, `KeyValueTile`, `PodiumWidget`, `BadgeTile`, `AuditNote`,
  `InfoBanner`, `SparklingLogo`.

Tests run without network: set `SparklingTypography.useGoogleFonts = false` in `setUpAll`.
