import 'package:flutter/material.dart';
import 'package:sparkling_core/sparkling_core.dart';
import 'package:sparkling_ui/sparkling_ui.dart';

import '../../app/scope.dart';
import '../../widgets/async_view.dart';
import '../../widgets/avatar_tile.dart';
import '../../widgets/segmented_pills.dart';

/// Leaderboard (2e): Week/Month, podium, ranked list with delta arrows and
/// the azure-tinted "You" row, badge grid (STF-050/052).
class LeaderboardScreen extends StatefulWidget {
  const LeaderboardScreen({super.key});

  @override
  State<LeaderboardScreen> createState() => _LeaderboardScreenState();
}

class _LeaderboardScreenState extends State<LeaderboardScreen> {
  LeaderboardPeriod _period = LeaderboardPeriod.week;
  Future<LeaderboardResult>? _future;
  Future<Outlet?>? _outlet;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _future ??= _load();
    _outlet ??= context.repositories.catalogue.outlet(context.session.outletId);
  }

  Future<LeaderboardResult> _load() async {
    final r = await context.repositories.staff.leaderboard(
      outletId: context.session.outletId,
      period: _period,
    );
    if (mounted) context.syncStatus.markSynced();
    return r;
  }

  void _setPeriod(LeaderboardPeriod p) {
    if (p == _period) return;
    setState(() {
      _period = p;
      _future = _load();
    });
  }

  @override
  Widget build(BuildContext context) {
    final cs = context.colors;
    return SafeArea(
      bottom: false,
      child: FutureBuilder<LeaderboardResult>(
        future: _future,
        builder: (context, snap) {
          final header = Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Leaderboard',
                        style: SparklingTypography.headlineLarge.copyWith(
                          color: cs.onSurface,
                        ),
                      ),
                    ),
                    SizedBox(
                      width: 200,
                      child: SegmentedPills<LeaderboardPeriod>(
                        grouped: true,
                        selected: _period,
                        onChanged: _setPeriod,
                        segments: const [
                          PillSegment(
                            value: LeaderboardPeriod.week,
                            label: 'Week',
                          ),
                          PillSegment(
                            value: LeaderboardPeriod.month,
                            label: 'Month',
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                FutureBuilder<Outlet?>(
                  future: _outlet,
                  builder: (context, o) {
                    final resets = snap.data?.resetsAt;
                    final resetLabel = resets == null
                        ? (_period == LeaderboardPeriod.week
                              ? 'resets Monday 00:00'
                              : 'resets on the 1st')
                        : 'resets ${SparklingDates.weekday(resets)} ${SparklingDates.hhmm(resets)}';
                    return Text(
                      '${o.data?.name ?? 'Outlet'} bay team · $resetLabel',
                      style: SparklingTypography.bodyLarge.copyWith(
                        fontSize: 15,
                        color: cs.onSurfaceVariant,
                      ),
                    );
                  },
                ),
              ],
            ),
          );

          return AsyncView<LeaderboardResult>(
            snapshot: snap,
            onRetry: () => setState(() => _future = _load()),
            loading: Column(
              children: [header, const Expanded(child: LoadingState())],
            ),
            builder: (context, result) {
              final rows = result.rows;
              final podium = result.podium;
              final rest = result.rest;
              return ListView(
                padding: const EdgeInsets.only(bottom: 24),
                children: [
                  header,
                  if (rows.isEmpty)
                    const EmptyState(
                      icon: Symbols.social_leaderboard_rounded,
                      title: 'No points yet',
                      text: 'Complete tasks to climb the board.',
                    )
                  else ...[
                    const SizedBox(height: 16),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      child: PodiumWidget(
                        first: _entry(podium[0]),
                        second: podium.length > 1 ? _entry(podium[1]) : null,
                        third: podium.length > 2 ? _entry(podium[2]) : null,
                        pointsFormatter: Money.formatPointsLabel,
                      ),
                    ),
                    if (rest.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(20, 0, 20, 0),
                        child: Container(
                          decoration: BoxDecoration(
                            color: cs.surfaceContainer,
                            borderRadius: const BorderRadius.vertical(
                              bottom: Radius.circular(SparklingShapes.card),
                            ),
                          ),
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          child: Column(
                            children: [
                              for (final r in rest) _RankRow(row: r),
                            ],
                          ),
                        ),
                      ),
                    if (result.me != null && result.me!.rank <= 3)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
                        child: _RankRow(row: result.me!, standalone: true),
                      ),
                  ],
                  const SizedBox(height: 28),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: SectionHeader(
                      title: 'Your badges',
                      trailing: Text(
                        'All ${result.badges.length}',
                        style: SparklingTypography.titleSmall.copyWith(
                          color: cs.primary,
                        ),
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: LayoutBuilder(
                      builder: (context, c) {
                        final columns = (c.maxWidth / 100).floor().clamp(3, 8);
                        return GridView.count(
                          crossAxisCount: columns,
                          shrinkWrap: true,
                          physics: const NeverScrollableScrollPhysics(),
                          mainAxisSpacing: 10,
                          crossAxisSpacing: 10,
                          childAspectRatio: 0.92,
                          children: [
                            for (final b in result.badges)
                              BadgeTile(
                                label: b.badge.name,
                                icon: badgeIcon(b.badge.icon),
                                color: Color(b.badge.colourValue),
                                earned: b.earned,
                                size: double.infinity,
                              ),
                          ],
                        );
                      },
                    ),
                  ),
                ],
              );
            },
          );
        },
      ),
    );
  }

  static PodiumEntry _entry(LeaderboardRow r) => PodiumEntry(
    name: r.isMe ? 'You' : r.name.split(' ').first,
    points: r.points,
    initials: r.initials,
  );

  /// Material Symbols glyph for the badge `icon` name from the API.
  static IconData badgeIcon(String name) => switch (name) {
    'military_tech' => Symbols.military_tech_rounded,
    'speed' => Symbols.speed_rounded,
    'verified' => Symbols.verified_rounded,
    'workspace_premium' => Symbols.workspace_premium_rounded,
    'local_fire_department' => Symbols.local_fire_department_rounded,
    'star' => Symbols.star_rounded,
    'school' => Symbols.school_rounded,
    'trophy' => Symbols.trophy_rounded,
    'visibility' => Symbols.visibility_rounded,
    'auto_awesome' => Symbols.auto_awesome_rounded,
    'local_car_wash' => Symbols.local_car_wash_rounded,
    'groups' => Symbols.groups_rounded,
    'bolt' => Symbols.bolt_rounded,
    'diamond' => Symbols.diamond_rounded,
    _ => Symbols.military_tech_rounded,
  };
}

class _RankRow extends StatelessWidget {
  const _RankRow({required this.row, this.standalone = false});
  final LeaderboardRow row;
  final bool standalone;

  @override
  Widget build(BuildContext context) {
    final cs = context.colors;
    final x = context.sparkling;
    final me = row.isMe;
    final deltaIcon = row.delta > 0
        ? Icon(Symbols.arrow_upward_rounded, size: 18, color: x.success)
        : row.delta < 0
        ? Icon(Symbols.arrow_downward_rounded, size: 18, color: cs.error)
        : Icon(
            Symbols.remove_rounded,
            size: 18,
            color: cs.onSurfaceVariant.withValues(alpha: 0.5),
          );
    return Semantics(
      label:
          'Rank ${row.rank}, ${me ? 'you' : row.name}, ${Money.formatPointsLabel(row.points)}',
      child: Container(
        margin: EdgeInsets.symmetric(horizontal: standalone ? 0 : 8),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: me ? cs.primaryContainer.withValues(alpha: 0.75) : null,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Row(
          children: [
            SizedBox(
              width: 24,
              child: Text(
                '${row.rank}',
                style: SparklingTypography.titleLarge.copyWith(
                  fontSize: 18,
                  color: me ? cs.primary : cs.onSurfaceVariant,
                ),
              ),
            ),
            const SizedBox(width: 8),
            AvatarTile(
              initials: row.initials,
              size: 44,
              radius: 14,
              tone: me ? AvatarTone.azure : AvatarTile.toneFor(row.staffId),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Text(
                me ? 'You · ${_short(row.name)}' : _short(row.name),
                style: SparklingTypography.titleLarge.copyWith(
                  fontSize: 17,
                  color: cs.onSurface,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            deltaIcon,
            const SizedBox(width: 10),
            Text(
              Money.formatPoints(row.points),
              style: SparklingTypography.titleLarge.copyWith(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: me ? cs.primary : cs.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }

  static String _short(String name) {
    final parts = name.trim().split(RegExp(r'\s+'));
    if (parts.length < 2) return name;
    return '${parts.first} ${parts.last[0]}.';
  }
}
