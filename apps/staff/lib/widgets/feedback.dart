import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:sparkling_core/sparkling_core.dart';
import 'package:sparkling_ui/sparkling_ui.dart';

import '../app/scope.dart';
import 'async_view.dart';

/// Haptics that respect the profile "haptics" preference (non-essential,
/// UX-004 / scan success feedback).
abstract final class StaffHaptics {
  static void success(BuildContext context) {
    if (!context.settings.haptics) return;
    HapticFeedback.mediumImpact();
  }

  static void tap(BuildContext context) {
    if (!context.settings.haptics) return;
    HapticFeedback.selectionClick();
  }

  static void error(BuildContext context) {
    if (!context.settings.haptics) return;
    HapticFeedback.heavyImpact();
  }
}

/// Floating snack helpers.
abstract final class StaffSnack {
  static void show(BuildContext context, String message) {
    ScaffoldMessenger.maybeOf(context)
      ?..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  static void error(BuildContext context, Object error) =>
      show(context, ErrorState.messageFor(error));

  /// Shows the queued-offline notice when a mutation returned optimistically.
  static void queued(BuildContext context, String what) =>
      show(context, '$what queued — will sync when you reconnect');
}

/// Explains a 409 from the server in the user's terms (STF-035): what the
/// server state is now and that the local change was not applied.
Future<void> showConflictDialog(
  BuildContext context,
  ApiException error, {
  String? title,
  VoidCallback? onRefresh,
}) {
  final cs = context.colors;
  return showDialog<void>(
    context: context,
    builder: (ctx) => AlertDialog(
      icon: Icon(Symbols.sync_problem_rounded, color: cs.error, size: 32),
      title: Text(title ?? 'Already changed on the server'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(error.message),
          const SizedBox(height: 10),
          Text(
            'Your change was not applied. The screen has been refreshed with '
            'the current server state — review it and try again if needed.',
            style: SparklingTypography.bodySmall.copyWith(
              color: cs.onSurfaceVariant,
            ),
          ),
          if (error.correlationId != null) ...[
            const SizedBox(height: 8),
            Text(
              'Ref ${error.correlationId}',
              style: SparklingTypography.mono(
                fontSize: 11,
                color: cs.onSurfaceVariant,
              ),
            ),
          ],
        ],
      ),
      actions: [
        TextButton(
          onPressed: () {
            Navigator.of(ctx).pop();
            onRefresh?.call();
          },
          child: const Text('OK'),
        ),
      ],
    ),
  );
}

/// Runs a repository mutation with unified error handling: conflicts open the
/// conflict dialog, network queueing shows the "queued" snack, everything
/// else a snack with the message. Returns the result or null on failure.
Future<T?> runMutation<T>(
  BuildContext context,
  Future<T> Function() body, {
  String? queuedLabel,
  VoidCallback? onConflict,
}) async {
  try {
    final result = await body();
    if (!context.mounted) return result;
    if (queuedLabel != null && context.syncStatus.state != SyncState.synced) {
      StaffSnack.queued(context, queuedLabel);
    }
    return result;
  } on ApiException catch (e) {
    if (!context.mounted) return null;
    if (e.isConflict) {
      StaffHaptics.error(context);
      await showConflictDialog(context, e, onRefresh: onConflict);
    } else {
      StaffSnack.error(context, e);
    }
    return null;
  } catch (e) {
    if (context.mounted) StaffSnack.error(context, e);
    return null;
  }
}
