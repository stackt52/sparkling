import 'package:flutter/material.dart';
import 'package:sparkling_ui/sparkling_ui.dart';

/// Shared chrome for sign-in / sign-up / reset: logo, headline, form body.
class AuthScaffold extends StatelessWidget {
  const AuthScaffold({
    super.key,
    required this.title,
    required this.child,
    this.subtitle,
    this.showBack = false,
    this.showEmulatorNote = false,
  });

  final String title;
  final String? subtitle;
  final Widget child;
  final bool showBack;

  /// Shows a small "Firebase Auth emulator" chip (dev builds with
  /// `AUTH_EMULATOR_HOST` set) so nobody mistakes a throwaway account for a
  /// real one.
  final bool showEmulatorNote;

  @override
  Widget build(BuildContext context) {
    final cs = context.colors;
    return Scaffold(
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) => SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
            child: ConstrainedBox(
              constraints: BoxConstraints(
                minHeight: constraints.maxHeight - 36,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (showBack)
                    Align(alignment: Alignment.centerLeft, child: BackButton()),
                  const SizedBox(height: 24),
                  const Center(child: SparklingLogo(height: 52)),
                  const SizedBox(height: 36),
                  Text(
                    title,
                    style: SparklingTypography.headlineLarge.copyWith(
                      color: cs.onSurface,
                    ),
                  ),
                  if (subtitle != null) ...[
                    const SizedBox(height: 6),
                    Text(
                      subtitle!,
                      style: SparklingTypography.bodyLarge.copyWith(
                        color: cs.onSurfaceVariant,
                      ),
                    ),
                  ],
                  if (showEmulatorNote) ...[
                    const SizedBox(height: 12),
                    const Align(
                      alignment: Alignment.centerLeft,
                      child: StatusChip(
                        label: 'Firebase Auth emulator',
                        tone: StatusChipTone.warning,
                        icon: Symbols.science_rounded,
                      ),
                    ),
                  ],
                  const SizedBox(height: 28),
                  AutofillGroup(child: child),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
