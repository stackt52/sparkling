import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sparkling_ui/sparkling_ui.dart';

Widget _wrap(Widget child, {bool dark = false}) => MaterialApp(
  theme: SparklingTheme.light(),
  darkTheme: SparklingTheme.dark(),
  themeMode: dark ? ThemeMode.dark : ThemeMode.light,
  home: Scaffold(body: Center(child: child)),
);

void main() {
  setUpAll(() {
    // No network in tests: use family names without fetching.
    SparklingTypography.useGoogleFonts = false;
  });

  group('SparklingTheme', () {
    test('light theme builds with tokens', () {
      final theme = SparklingTheme.light();
      expect(theme.useMaterial3, isTrue);
      expect(theme.colorScheme.primary, SparklingColors.lightPrimary);
      expect(theme.colorScheme.secondary, SparklingColors.navy);
      expect(
        theme.colorScheme.surfaceContainer,
        SparklingColors.lightSurfaceContainer,
      );
      final ext = theme.extension<SparklingColorsExt>();
      expect(ext, isNotNull);
      expect(ext!.success, SparklingColors.lightSuccess);
      expect(ext.azure, SparklingColors.azure);
      expect(ext.heroGradient, SparklingColors.heroGradientLight);
      expect(
        theme.filledButtonTheme.style?.minimumSize?.resolve({})?.height,
        48,
      );
    });

    test('dark theme builds with tokens', () {
      final theme = SparklingTheme.dark();
      expect(theme.brightness, Brightness.dark);
      expect(theme.colorScheme.primary, SparklingColors.darkPrimary);
      expect(theme.colorScheme.surface, SparklingColors.darkSurface);
      final ext = theme.extension<SparklingColorsExt>()!;
      expect(ext.success, SparklingColors.darkSuccess);
      expect(ext.outlineTrack, SparklingColors.darkOutline);
      expect(ext.heroGradient, SparklingColors.heroGradientDark);
    });

    test('extension lerps', () {
      final mid = SparklingColorsExt.light.lerp(SparklingColorsExt.dark, 0.5);
      expect(
        mid.success,
        Color.lerp(
          SparklingColors.lightSuccess,
          SparklingColors.darkSuccess,
          0.5,
        ),
      );
    });

    testWidgets('context.sparkling resolves the extension', (tester) async {
      late SparklingColorsExt ext;
      await tester.pumpWidget(
        _wrap(
          Builder(
            builder: (context) {
              ext = context.sparkling;
              return const SizedBox();
            },
          ),
          dark: true,
        ),
      );
      expect(ext.successContainer, SparklingColors.darkSuccessContainer);
    });
  });

  group('SparklingMotion', () {
    testWidgets('honours MediaQuery.disableAnimations and scope override', (
      tester,
    ) async {
      late bool viaMediaQuery;
      late bool viaScope;
      late bool normal;
      await tester.pumpWidget(
        _wrap(
          Column(
            children: [
              MediaQuery(
                data: const MediaQueryData(disableAnimations: true),
                child: Builder(
                  builder: (c) {
                    viaMediaQuery = SparklingMotion.reducedMotion(c);
                    return const SizedBox();
                  },
                ),
              ),
              SparklingMotionScope(
                reducedMotion: true,
                child: Builder(
                  builder: (c) {
                    viaScope = SparklingMotion.reducedMotion(c);
                    return const SizedBox();
                  },
                ),
              ),
              Builder(
                builder: (c) {
                  normal = SparklingMotion.reducedMotion(c);
                  return const SizedBox();
                },
              ),
            ],
          ),
        ),
      );
      expect(viaMediaQuery, isTrue);
      expect(viaScope, isTrue);
      expect(normal, isFalse);
    });
  });

  group('StatusChip', () {
    testWidgets('renders text for each tone', (tester) async {
      await tester.pumpWidget(
        _wrap(
          Wrap(
            children: [
              for (final tone in StatusChipTone.values)
                StatusChip(label: tone.name, tone: tone),
            ],
          ),
        ),
      );
      for (final tone in StatusChipTone.values) {
        expect(find.text(tone.name), findsOneWidget);
      }
    });

    testWidgets('PriorityChip / TierPill / SyncChip render', (tester) async {
      await tester.pumpWidget(
        _wrap(
          const Column(
            children: [
              PriorityChip(priority: 1),
              TierPill(tier: LoyaltyTierKind.gold, label: 'Gold · 1 450 pts'),
              SyncChip(state: SyncState.synced, label: 'Synced 09:41'),
            ],
          ),
        ),
      );
      expect(find.text('P1'), findsOneWidget);
      expect(find.text('Gold · 1 450 pts'), findsOneWidget);
      expect(find.text('Synced 09:41'), findsOneWidget);
    });
  });

  group('ProgressRing', () {
    testWidgets('paints and shows label', (tester) async {
      await tester.pumpWidget(
        _wrap(const ProgressRing(value: 0.58, label: '58%')),
      );
      await tester.pumpAndSettle();
      expect(find.byType(CustomPaint), findsWidgets);
      expect(find.text('58%'), findsOneWidget);
      final semantics = tester.getSemantics(find.byType(ProgressRing));
      expect(semantics.value, '58%');
    });

    testWidgets('is static under reduced motion', (tester) async {
      await tester.pumpWidget(
        _wrap(
          const SparklingMotionScope(
            reducedMotion: true,
            child: ProgressRing(value: 0.4, label: '4/7'),
          ),
        ),
      );
      // No pending animation frames.
      await tester.pump();
      expect(find.text('4/7'), findsOneWidget);
    });
  });

  group('RadioCard', () {
    testWidgets('toggles on tap', (tester) async {
      var selected = false;
      await tester.pumpWidget(
        _wrap(
          StatefulBuilder(
            builder: (context, setState) {
              return RadioCard(
                selected: selected,
                onChanged: (v) => setState(() => selected = v),
                title: const Text('Full Valet'),
                subtitle: const Text('60 min'),
                trailing: const Text('R 240.00'),
              );
            },
          ),
        ),
      );
      expect(selected, isFalse);
      await tester.tap(find.text('Full Valet'));
      await tester.pumpAndSettle();
      expect(selected, isTrue);
      expect(find.byIcon(Symbols.check_rounded), findsOneWidget);
    });

    testWidgets('disabled card ignores taps', (tester) async {
      var tapped = false;
      await tester.pumpWidget(
        _wrap(
          RadioCard(
            selected: false,
            enabled: false,
            onChanged: (_) => tapped = true,
            title: const Text('At capacity'),
          ),
        ),
      );
      await tester.tap(find.text('At capacity'));
      expect(tapped, isFalse);
    });
  });

  group('Misc widgets build', () {
    testWidgets('slot/date chips, timeline, banners, tiles', (tester) async {
      await tester.pumpWidget(
        _wrap(
          SingleChildScrollView(
            child: Column(
              children: [
                const SlotChip(label: '10:30', state: SlotState.booked),
                const DateChip(weekday: 'Mon', day: '14', selected: true),
                const StepProgressStrip(current: 1, total: 3),
                const TimelineTile(
                  title: 'Checked in',
                  subtitle: '09:12',
                  state: TimelineState.done,
                  isFirst: true,
                ),
                const TimelineTile(
                  title: 'Foam & hand wash',
                  state: TimelineState.current,
                ),
                const TimelineTile(
                  title: 'Ready',
                  state: TimelineState.pending,
                  isLast: true,
                ),
                const OfflineBanner(lastSyncLabel: '20:47'),
                const InfoBanner(
                  text: 'Nothing is booked until you approve',
                  tone: InfoTone.info,
                ),
                const KeyValueTile(
                  label: 'VIN',
                  value: '•••• 4567',
                  mono: true,
                  locked: true,
                ),
                const StatTile(
                  value: '3',
                  label: 'In progress',
                  tone: StatTone.azure,
                ),
                const LinearLevelBar(value: 0.2, state: LevelState.low),
                const BadgeTile(
                  label: '50 washes',
                  icon: Symbols.military_tech_rounded,
                  earned: true,
                ),
                const BadgeTile(
                  label: 'Mentor',
                  icon: Symbols.groups_rounded,
                  earned: false,
                ),
                PodiumWidget(
                  first: const PodiumEntry(name: 'Sipho', points: 1420),
                  second: const PodiumEntry(name: 'Lerato', points: 1180),
                  third: const PodiumEntry(name: 'Pieter', points: 960),
                ),
                const PillButton(
                  label: 'Track service',
                  variant: PillButtonVariant.whiteOnNavy,
                ),
                const VehicleCard(
                  title: 'Corolla Cross',
                  plate: 'KL 45 MN GP',
                  verified: true,
                ),
                const QuickActionCard(
                  icon: Symbols.local_car_wash_rounded,
                  title: 'Book a wash',
                  subtitle: 'From R120',
                ),
                const NotificationBell(hasUnread: true),
                const AuditNote(text: 'Actor, time and reason are recorded'),
                const PhotoPlaceholder(caption: 'exterior\nphoto'),
                const PhotoPlaceholder.add(),
                const DragHandle(),
                const SparklingMotionScope(
                  reducedMotion: true,
                  child: ConfettiBlob(size: 100),
                ),
              ],
            ),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 600));
      expect(
        find.text('Showing status from 20:47', skipOffstage: false),
        findsOneWidget,
      );
      expect(find.text('Locked', skipOffstage: false), findsOneWidget);
      expect(find.text('1 420 pts', skipOffstage: false), findsOneWidget);
      expect(find.text('KL 45 MN GP', skipOffstage: false), findsOneWidget);
    });

    testWidgets('ScanFrameOverlay builds and stops under reduced motion', (
      tester,
    ) async {
      await tester.pumpWidget(
        _wrap(
          const SparklingMotionScope(
            reducedMotion: true,
            child: SizedBox(
              width: 400,
              height: 700,
              child: ScanFrameOverlay(hint: Text('Hold steady')),
            ),
          ),
        ),
      );
      await tester.pump();
      expect(find.text('Hold steady'), findsOneWidget);
    });

    testWidgets('HeroCard variants and logo', (tester) async {
      await tester.pumpWidget(
        _wrap(
          const Column(
            children: [
              HeroCard(child: Text('Next booking')),
              HeroCard.navy(child: Text('Stage')),
              HeroCard.gold(child: Text('GOLD MEMBER')),
              SparklingLogo(height: 24),
            ],
          ),
        ),
      );
      expect(find.text('GOLD MEMBER'), findsOneWidget);
      expect(find.byType(Image), findsOneWidget);
    });
  });
}
