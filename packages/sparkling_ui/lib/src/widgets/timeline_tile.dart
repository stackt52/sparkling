import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../theme/colors_ext.dart';
import '../tokens/motion.dart';
import '../tokens/typography.dart';

/// State of a tracking-timeline stage (1h).
enum TimelineState { done, current, pending }

/// Vertical timeline row: done (filled primary circle + check), current
/// (primaryContainer ring + dot, primary title), pending (muted). Connectors
/// are 3px and coloured by the state above/below.
class TimelineTile extends StatelessWidget {
  const TimelineTile({
    super.key,
    required this.title,
    required this.state,
    this.subtitle,
    this.isFirst = false,
    this.isLast = false,
    this.icon,
    this.indicatorSize = 40,
    this.onTap,
  });

  final String title;
  final String? subtitle;
  final TimelineState state;
  final bool isFirst;
  final bool isLast;

  /// Overrides the indicator glyph (e.g. `Symbols.flag_rounded` for the last row).
  final IconData? icon;
  final double indicatorSize;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final cs = context.colors;
    final connectorActive = cs.primary;
    final connectorMuted = cs.surfaceContainerHigh;

    final topConnector = state == TimelineState.pending
        ? connectorMuted
        : connectorActive;
    final bottomConnector = state == TimelineState.done
        ? connectorActive
        : connectorMuted;

    final titleColor = switch (state) {
      TimelineState.done => cs.onSurface,
      TimelineState.current => cs.primary,
      TimelineState.pending => cs.onSurfaceVariant.withValues(alpha: 0.7),
    };
    final subtitleColor = state == TimelineState.pending
        ? cs.onSurfaceVariant.withValues(alpha: 0.6)
        : cs.onSurfaceVariant;

    return Semantics(
      label: '$title, ${state.name}',
      child: InkWell(
        onTap: onTap,
        child: IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(
                width: indicatorSize,
                child: Column(
                  children: [
                    SizedBox(
                      height: 8,
                      child: isFirst ? null : _Connector(color: topConnector),
                    ),
                    _Indicator(state: state, size: indicatorSize, icon: icon),
                    Expanded(
                      child: isLast
                          ? const SizedBox.shrink()
                          : _Connector(color: bottomConnector),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(0, 10, 0, 20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: SparklingTypography.titleLarge.copyWith(
                          fontSize: 16.5,
                          color: titleColor,
                        ),
                      ),
                      if (subtitle != null) ...[
                        const SizedBox(height: 2),
                        Text(
                          subtitle!,
                          style: SparklingTypography.bodyMedium.copyWith(
                            color: subtitleColor,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Connector extends StatelessWidget {
  const _Connector({required this.color});
  final Color color;

  @override
  Widget build(BuildContext context) => Center(
    child: AnimatedContainer(
      duration: SparklingMotion.durationFor(context, SparklingMotion.medium),
      width: 3,
      color: color,
    ),
  );
}

class _Indicator extends StatelessWidget {
  const _Indicator({required this.state, required this.size, this.icon});
  final TimelineState state;
  final double size;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final cs = context.colors;
    final duration = SparklingMotion.durationFor(
      context,
      SparklingMotion.medium,
    );
    switch (state) {
      case TimelineState.done:
        return AnimatedContainer(
          duration: duration,
          width: size,
          height: size,
          decoration: BoxDecoration(shape: BoxShape.circle, color: cs.primary),
          child: Icon(
            icon ?? Symbols.check_rounded,
            color: cs.onPrimary,
            size: size * 0.5,
            weight: 700,
          ),
        );
      case TimelineState.current:
        return AnimatedContainer(
          duration: duration,
          width: size,
          height: size,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: cs.primaryContainer,
            border: Border.all(color: cs.primary, width: 3),
          ),
          child: Center(
            child: Container(
              width: size * 0.3,
              height: size * 0.3,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: cs.primary,
              ),
            ),
          ),
        );
      case TimelineState.pending:
        return AnimatedContainer(
          duration: duration,
          width: size,
          height: size,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: cs.surfaceContainerHigh,
          ),
          child: icon == null
              ? null
              : Icon(
                  icon,
                  color: cs.onSurfaceVariant.withValues(alpha: 0.5),
                  size: size * 0.45,
                ),
        );
    }
  }
}
