import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:sparkling_core/sparkling_core.dart';
import 'package:sparkling_ui/sparkling_ui.dart';

import '../../app/app_scope.dart';
import '../../app/router.dart';
import '../../widgets/common.dart';

/// Customer home (1a light / 1k dark): greeting, tier pill, booking hero,
/// quick actions, vehicles.
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  late Stream<List<Booking>> _bookings;
  late Stream<List<Vehicle>> _vehicles;
  late Stream<LoyaltyAccountSummary> _loyalty;
  late Future<int> _unread;
  late Future<int?> _fromPrice;
  bool _ready = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_ready) {
      _ready = true;
      _init();
    }
  }

  void _init() {
    final repos = context.repos;
    _bookings = repos.customer.watchBookings();
    _vehicles = repos.customer.watchVehicles();
    _loyalty = repos.loyalty.watchAccount();
    _unread = repos.notifications.unreadCount().catchError((_) => 0);
    _fromPrice = _cheapestWash(repos);
  }

  static Future<int?> _cheapestWash(Repositories repos) async {
    try {
      final outlets = await repos.catalogue.outlets();
      if (outlets.isEmpty) return null;
      final services = await repos.catalogue.outletServices(outlets.first.id);
      final prices = services
          .where((s) => s.category == ServiceCategory.carWash && s.isAvailable)
          .map((s) => s.priceCents);
      return prices.isEmpty ? null : prices.reduce((a, b) => a < b ? a : b);
    } catch (_) {
      return null;
    }
  }

  Future<void> _refresh() async {
    setState(_init);
    await context.session.refreshProfile();
  }

  @override
  Widget build(BuildContext context) {
    final cs = context.colors;
    final session = context.session;

    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: RefreshIndicator(
          onRefresh: _refresh,
          child: ListenableBuilder(
            listenable: session,
            builder: (context, _) => ListView(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
              children: [
                _AppBarRow(unread: _unread),
                const SizedBox(height: 22),
                _Greeting(loyalty: _loyalty),
                const SizedBox(height: 18),
                StreamBuilder<List<Booking>>(
                  stream: _bookings,
                  builder: (context, snap) {
                    if (snap.hasError) {
                      return ErrorView(
                        error: snap.error,
                        compact: true,
                        onRetry: _refresh,
                      );
                    }
                    final list = snap.data;
                    if (list == null) return const _HeroSkeleton();
                    return _BookingHero(bookings: list);
                  },
                ),
                const SizedBox(height: 14),
                Row(
                  children: [
                    Expanded(
                      child: FutureBuilder<int?>(
                        future: _fromPrice,
                        builder: (context, snap) => QuickActionCard(
                          height: 160,
                          icon: Symbols.local_car_wash_rounded,
                          title: 'Book a wash',
                          subtitle: snap.data == null
                              ? 'Wash & valet'
                              : 'From ${Money.formatZarCompact(snap.data!)}',
                          onTap: () => context.push(Routes.bookService),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: QuickActionCard(
                        height: 160,
                        icon: Symbols.car_crash_rounded,
                        title: 'Repair quote',
                        subtitle: 'Body & paint',
                        primary: false,
                        onTap: () => context.push(Routes.quoteNew),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 24),
                SectionHeader(
                  title: 'Your vehicles',
                  actionLabel: 'Manage',
                  onAction: () => context.push(Routes.vehicles),
                ),
                StreamBuilder<List<Vehicle>>(
                  stream: _vehicles,
                  builder: (context, snap) {
                    final vehicles = snap.data ?? const <Vehicle>[];
                    return _VehicleRow(vehicles: vehicles);
                  },
                ),
                const SizedBox(height: 8),
                if (context.bookingFlow.hasDraft)
                  ListenableBuilder(
                    listenable: context.bookingFlow,
                    builder: (context, _) {
                      final flow = context.bookingFlow;
                      if (!flow.hasDraft) return const SizedBox.shrink();
                      return Padding(
                        padding: const EdgeInsets.only(top: 12),
                        child: InfoBanner(
                          tone: InfoTone.info,
                          icon: Symbols.edit_calendar_rounded,
                          title: 'Unfinished booking',
                          text:
                              '${flow.service!.name} at ${shortOutletName(flow.outlet!.name)} — pick up where you left off.',
                          actionLabel: 'Resume',
                          onAction: () => context.push(Routes.bookService),
                        ),
                      );
                    },
                  ),
                if (cs.brightness == Brightness.dark) const SizedBox(height: 4),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _AppBarRow extends StatelessWidget {
  const _AppBarRow({required this.unread});
  final Future<int> unread;

  @override
  Widget build(BuildContext context) {
    final session = context.session;
    return Row(
      children: [
        const SparklingLogo(height: 38),
        const Spacer(),
        FutureBuilder<int>(
          future: unread,
          builder: (context, snap) => NotificationBell(
            hasUnread: (snap.data ?? 0) > 0,
            onPressed: () => context.push(Routes.notifications),
          ),
        ),
        const SizedBox(width: 10),
        AvatarTile(
          initials: session.initials,
          onTap: () => context.go(Routes.profile),
        ),
      ],
    );
  }
}

class _Greeting extends StatelessWidget {
  const _Greeting({required this.loyalty});
  final Stream<LoyaltyAccountSummary> loyalty;

  @override
  Widget build(BuildContext context) {
    final cs = context.colors;
    final session = context.session;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                greetingFor(DateTime.now()),
                style: SparklingTypography.bodyLarge.copyWith(
                  fontSize: 18,
                  color: cs.onSurfaceVariant,
                ),
              ),
              Text(
                session.firstName,
                style: SparklingTypography.headlineLarge.copyWith(
                  fontSize: 30,
                  color: cs.onSurface,
                ),
              ),
            ],
          ),
        ),
        StreamBuilder<LoyaltyAccountSummary>(
          stream: loyalty,
          builder: (context, snap) {
            final acc = snap.data;
            if (acc == null) return const SizedBox.shrink();
            return Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: TierPill(
                tier: tierKind(acc.tier),
                label:
                    '${acc.tier.label} · ${Money.formatPointsLabel(acc.balance)}',
                onTap: () => context.go(Routes.loyalty),
              ),
            );
          },
        ),
      ],
    );
  }
}

class _HeroSkeleton extends StatelessWidget {
  const _HeroSkeleton();

  @override
  Widget build(BuildContext context) {
    return const HeroCard(
      child: SizedBox(
        height: 120,
        child: Center(
          child: SizedBox(
            width: 24,
            height: 24,
            child: CircularProgressIndicator(
              strokeWidth: 2.5,
              color: Colors.white,
            ),
          ),
        ),
      ),
    );
  }
}

/// Chooses the most relevant booking: in-service first, then next upcoming.
class _BookingHero extends StatelessWidget {
  const _BookingHero({required this.bookings});
  final List<Booking> bookings;

  @override
  Widget build(BuildContext context) {
    final inService = bookings.where((b) => b.isInService).toList();
    if (inService.isNotEmpty) return _InServiceHero(booking: inService.first);

    final upcoming = bookings.where((b) => b.isUpcoming).toList()
      ..sort((a, b) => a.slotStart.compareTo(b.slotStart));
    if (upcoming.isNotEmpty) return _NextBookingHero(booking: upcoming.first);

    return HeroCard(
      onTap: () => context.push(Routes.bookService),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _Overline('No upcoming booking'),
          const SizedBox(height: 10),
          Text(
            'Ready for a sparkle?',
            style: SparklingTypography.headlineMedium.copyWith(
              fontSize: 24,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Book a wash in under a minute.',
            style: SparklingTypography.bodyLarge.copyWith(
              fontSize: 15,
              color: Colors.white.withValues(alpha: 0.85),
            ),
          ),
          const SizedBox(height: 18),
          PillButton(
            label: 'Book a wash',
            variant: context.isDark
                ? PillButtonVariant.filled
                : PillButtonVariant.whiteOnNavy,
            expand: true,
            onPressed: () => context.push(Routes.bookService),
          ),
        ],
      ),
    );
  }
}

class _Overline extends StatelessWidget {
  const _Overline(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text.toUpperCase(),
      style: SparklingTypography.overline.copyWith(
        fontSize: 12,
        letterSpacing: 1.6,
        color: context.isDark
            ? context.colors.primary
            : const Color(0xFF8BD2FF),
      ),
    );
  }
}

class _NextBookingHero extends StatelessWidget {
  const _NextBookingHero({required this.booking});
  final Booking booking;

  @override
  Widget build(BuildContext context) {
    final b = booking;
    final when = SparklingDates.relativeSlot(b.slotStart);
    return HeroCard(
      onTap: () => context.push(Routes.bookingDetail(b.id), extra: b),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Expanded(child: _Overline('Next booking')),
              StatusChip(
                label: b.status.label,
                tone: StatusChipTone.onDark,
                dot: true,
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            b.title,
            style: SparklingTypography.headlineMedium.copyWith(
              fontSize: 25,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            '${b.outlet?.name ?? ''} · $when',
            style: SparklingTypography.bodyLarge.copyWith(
              fontSize: 15,
              color: Colors.white.withValues(alpha: 0.85),
            ),
          ),
          const SizedBox(height: 18),
          Row(
            children: [
              Expanded(
                child: PillButton(
                  label: 'Track service',
                  variant: context.isDark
                      ? PillButtonVariant.filled
                      : PillButtonVariant.whiteOnNavy,
                  expand: true,
                  onPressed: () => context.push(Routes.track(b.id)),
                ),
              ),
              const SizedBox(width: 10),
              IconTileButton(
                icon: Symbols.more_horiz_rounded,
                tone: IconTileTone.onDark,
                size: 48,
                radius: 24,
                tooltip: 'Booking options',
                onPressed: () =>
                    context.push(Routes.bookingDetail(b.id), extra: b),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _InServiceHero extends StatelessWidget {
  const _InServiceHero({required this.booking});
  final Booking booking;

  @override
  Widget build(BuildContext context) {
    final b = booking;
    final wo = b.workOrder;
    final stageLabel = wo == null || wo.stageCount == 0
        ? 'In service'
        : 'Stage ${wo.stage} of ${wo.stageCount}';
    final eta = wo?.etaAt == null ? null : SparklingDates.eta(wo!.etaAt!);
    final subtitle = [
      b.vehicle?.shortName,
      if (eta != null) 'ready by $eta',
    ].whereType<String>().join(' · ');

    return HeroCard(
      onTap: () => context.push(Routes.track(b.id)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Expanded(child: _Overline('In service now')),
              StatusChip(
                label: stageLabel,
                tone: StatusChipTone.onDark,
                dot: true,
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            wo?.stageTitle ?? b.service?.name ?? 'In service',
            style: SparklingTypography.headlineMedium.copyWith(
              fontSize: 25,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            subtitle,
            style: SparklingTypography.bodyLarge.copyWith(
              fontSize: 15,
              color: Colors.white.withValues(alpha: 0.85),
            ),
          ),
          const SizedBox(height: 16),
          LinearLevelBar.progress(
            value: (wo?.progress ?? 0).clamp(0, 1),
            height: 8,
            trackColor: Colors.white.withValues(alpha: 0.2),
          ),
          const SizedBox(height: 16),
          PillButton(
            label: 'Open timeline',
            variant: context.isDark
                ? PillButtonVariant.filled
                : PillButtonVariant.whiteOnNavy,
            expand: true,
            onPressed: () => context.push(Routes.track(b.id)),
          ),
        ],
      ),
    );
  }
}

class _VehicleRow extends StatelessWidget {
  const _VehicleRow({required this.vehicles});
  final List<Vehicle> vehicles;

  @override
  Widget build(BuildContext context) {
    final cs = context.colors;
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      clipBehavior: Clip.none,
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (final v in vehicles) ...[
              VehicleCard(
                title: v.shortName,
                plate: v.registrationNo,
                verified: v.discVerified,
                onTap: () => context.push(Routes.vehicleEdit(v.id), extra: v),
              ),
              const SizedBox(width: 12),
            ],
            Semantics(
              button: true,
              label: 'Add vehicle',
              child: Material(
                color: cs.surfaceContainer,
                borderRadius: BorderRadius.circular(SparklingShapes.card),
                child: InkWell(
                  borderRadius: BorderRadius.circular(SparklingShapes.card),
                  onTap: () => context.push(Routes.vehicleAdd),
                  child: SizedBox(
                    width: vehicles.isEmpty ? 200 : 120,
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(
                            Symbols.add_circle_rounded,
                            color: cs.primary,
                            fill: 1,
                          ),
                          const SizedBox(height: 10),
                          Text(
                            vehicles.isEmpty
                                ? 'Add your first vehicle'
                                : 'Add vehicle',
                            style: SparklingTypography.titleMedium.copyWith(
                              color: cs.onSurface,
                            ),
                          ),
                          Text(
                            'Scan disc or type',
                            style: SparklingTypography.bodySmall.copyWith(
                              color: cs.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
