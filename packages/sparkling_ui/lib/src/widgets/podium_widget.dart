import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../theme/colors_ext.dart';
import '../tokens/colors.dart';
import '../tokens/elevation.dart';
import '../tokens/motion.dart';
import '../tokens/typography.dart';

/// One podium entry.
class PodiumEntry {
  const PodiumEntry({
    required this.name,
    required this.points,
    this.initials,
    this.avatarColor,
  });

  final String name;
  final int points;

  /// Two-letter initials (derived from [name] when null).
  final String? initials;

  /// Avatar tint for 2nd/3rd (1st always uses the gold gradient).
  final Color? avatarColor;

  String get initialsOrDerived {
    if (initials != null) return initials!;
    final parts = name.trim().split(RegExp(r'\s+'));
    if (parts.length == 1) {
      return parts.first.characters.take(2).toString().toUpperCase();
    }
    return (parts.first.characters.first + parts.last.characters.first)
        .toUpperCase();
  }
}

/// Leaderboard podium (2e): winner with 64px gold-gradient avatar + crown +
/// tallest column, 2nd on the left, 3rd on the right. Columns grow in with
/// the emphasized curve unless motion is reduced.
class PodiumWidget extends StatelessWidget {
  const PodiumWidget({
    super.key,
    required this.first,
    this.second,
    this.third,
    this.pointsFormatter,
    this.height = 290,
  });

  final PodiumEntry first;
  final PodiumEntry? second;
  final PodiumEntry? third;

  /// Formats points ("1 420 pts"). Defaults to a thin-space thousands format.
  final String Function(int points)? pointsFormatter;
  final double height;

  String _fmt(int p) => pointsFormatter?.call(p) ?? '${_group(p)} pts';

  static String _group(int n) {
    final s = n.toString();
    final buf = StringBuffer();
    for (var i = 0; i < s.length; i++) {
      if (i > 0 && (s.length - i) % 3 == 0) buf.write(' ');
      buf.write(s[i]);
    }
    return buf.toString();
  }

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label:
          'Podium. First ${first.name} ${_fmt(first.points)}'
          '${second == null ? '' : ', second ${second!.name} ${_fmt(second!.points)}'}'
          '${third == null ? '' : ', third ${third!.name} ${_fmt(third!.points)}'}',
      child: SizedBox(
        height: height,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Expanded(
              child: second == null
                  ? const SizedBox.shrink()
                  : _Column(
                      entry: second!,
                      rank: 2,
                      avatarSize: 52,
                      columnHeight: 88,
                      fmt: _fmt,
                    ),
            ),
            const SizedBox(width: 10),
            Expanded(
              flex: 1,
              child: _Column(
                entry: first,
                rank: 1,
                avatarSize: 64,
                columnHeight: 130,
                fmt: _fmt,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: third == null
                  ? const SizedBox.shrink()
                  : _Column(
                      entry: third!,
                      rank: 3,
                      avatarSize: 52,
                      columnHeight: 66,
                      fmt: _fmt,
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Column extends StatelessWidget {
  const _Column({
    required this.entry,
    required this.rank,
    required this.avatarSize,
    required this.columnHeight,
    required this.fmt,
  });

  final PodiumEntry entry;
  final int rank;
  final double avatarSize;
  final double columnHeight;
  final String Function(int) fmt;

  @override
  Widget build(BuildContext context) {
    final cs = context.colors;
    final dark = context.isDark;
    final isFirst = rank == 1;
    final avatarBg = isFirst
        ? null
        : entry.avatarColor ??
              (rank == 2 ? const Color(0xFFB9C7E6) : const Color(0xFFE8B3A0));
    final columnColor = isFirst
        ? (dark
              ? const Color(0xFF243560)
              : SparklingColors.lightSecondaryContainer)
        : (dark ? cs.surfaceContainerHigh : cs.surfaceContainer);
    final rankColor = isFirst ? SparklingColors.goldDeep : cs.onSurfaceVariant;
    final reduced = SparklingMotion.reducedMotion(context);

    return Column(
      mainAxisSize: MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        if (isFirst) ...[
          const Icon(
            Symbols.crown_rounded,
            color: SparklingColors.goldDeep,
            size: 28,
            fill: 1,
          ),
          const SizedBox(height: 6),
        ],
        Container(
          width: avatarSize,
          height: avatarSize,
          decoration: BoxDecoration(
            color: avatarBg,
            gradient: isFirst ? SparklingColors.goldGradient : null,
            borderRadius: BorderRadius.circular(avatarSize * 0.32),
            boxShadow: isFirst ? SparklingElevation.podiumGlow : null,
          ),
          child: Center(
            child: Text(
              entry.initialsOrDerived,
              style: SparklingTypography.font(
                fontSize: avatarSize * 0.34,
                fontWeight: FontWeight.w700,
                color: isFirst ? SparklingColors.onGold : SparklingColors.navy,
              ),
            ),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          entry.name,
          style: SparklingTypography.titleMedium.copyWith(
            fontSize: isFirst ? 16 : 15,
            color: cs.onSurface,
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        Text(
          fmt(entry.points),
          style: SparklingTypography.labelLarge.copyWith(
            color: isFirst ? SparklingColors.goldDeep : cs.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 8),
        Flexible(
          child: TweenAnimationBuilder<double>(
            tween: Tween(begin: reduced ? 1 : 0, end: 1),
            duration: reduced ? Duration.zero : SparklingMotion.slow,
            curve: SparklingMotion.emphasized,
            builder: (context, t, child) => Container(
              height: columnHeight * t,
              decoration: BoxDecoration(
                color: columnColor,
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(18),
                ),
              ),
              alignment: Alignment.topCenter,
              padding: const EdgeInsets.only(top: 14),
              child: Opacity(opacity: t, child: child),
            ),
            child: Text(
              '$rank',
              style: SparklingTypography.font(
                fontSize: isFirst ? 30 : 26,
                fontWeight: FontWeight.w700,
                color: rankColor,
              ),
            ),
          ),
        ),
      ],
    );
  }
}
