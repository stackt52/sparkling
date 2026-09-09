import 'package:flutter/material.dart';
import 'package:sparkling_core/sparkling_core.dart';
import 'package:sparkling_ui/sparkling_ui.dart';

/// Loading / error / data switch for [Future]s and [Stream]s that keeps the
/// last good value on screen while a refresh is in flight.
class AsyncView<T> extends StatelessWidget {
  const AsyncView({
    super.key,
    required this.snapshot,
    required this.builder,
    this.onRetry,
    this.loading,
    this.emptyWhen,
    this.empty,
  });

  final AsyncSnapshot<T> snapshot;
  final Widget Function(BuildContext context, T data) builder;
  final VoidCallback? onRetry;
  final Widget? loading;
  final bool Function(T data)? emptyWhen;
  final Widget? empty;

  @override
  Widget build(BuildContext context) {
    if (snapshot.hasData) {
      final data = snapshot.data as T;
      if (emptyWhen != null && emptyWhen!(data) && empty != null) {
        return empty!;
      }
      return builder(context, data);
    }
    if (snapshot.hasError) {
      return ErrorState(error: snapshot.error!, onRetry: onRetry);
    }
    return loading ?? const LoadingState();
  }
}

/// Centred spinner with the theme colours.
class LoadingState extends StatelessWidget {
  const LoadingState({super.key, this.label});
  final String? label;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(
            width: 32,
            height: 32,
            child: CircularProgressIndicator(strokeWidth: 3),
          ),
          if (label != null) ...[
            const SizedBox(height: 12),
            Text(label!, style: context.text.bodyMedium),
          ],
        ],
      ),
    );
  }
}

/// Friendly error with retry.
class ErrorState extends StatelessWidget {
  const ErrorState({super.key, required this.error, this.onRetry});
  final Object error;
  final VoidCallback? onRetry;

  static String messageFor(Object error) => switch (error) {
    ApiException e => e.message,
    AuthException e => e.message,
    DiscParseException e => e.message,
    _ => 'Something went wrong. Please try again.',
  };

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(SparklingSpacing.gutter),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Symbols.error_rounded,
              size: 40,
              color: context.colors.error,
              fill: 1,
            ),
            const SizedBox(height: 12),
            Text(
              messageFor(error),
              textAlign: TextAlign.center,
              style: context.text.bodyLarge,
            ),
            if (onRetry != null) ...[
              const SizedBox(height: 16),
              PillButton(
                label: 'Retry',
                icon: Symbols.refresh_rounded,
                variant: PillButtonVariant.tonal,
                onPressed: onRetry,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Empty list placeholder.
class EmptyState extends StatelessWidget {
  const EmptyState({
    super.key,
    required this.icon,
    required this.title,
    this.text,
    this.action,
  });

  final IconData icon;
  final String title;
  final String? text;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final cs = context.colors;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(SparklingSpacing.xxxl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(
                color: cs.surfaceContainer,
                borderRadius: BorderRadius.circular(SparklingShapes.tile),
              ),
              child: Icon(icon, size: 30, color: cs.onSurfaceVariant),
            ),
            const SizedBox(height: 14),
            Text(
              title,
              textAlign: TextAlign.center,
              style: context.text.titleLarge,
            ),
            if (text != null) ...[
              const SizedBox(height: 4),
              Text(
                text!,
                textAlign: TextAlign.center,
                style: context.text.bodyMedium?.copyWith(
                  color: cs.onSurfaceVariant,
                ),
              ),
            ],
            if (action != null) ...[const SizedBox(height: 16), action!],
          ],
        ),
      ),
    );
  }
}
