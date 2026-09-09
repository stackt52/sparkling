import 'package:flutter/material.dart';
import 'package:sparkling_ui/sparkling_ui.dart';

import '../../app/scope.dart';
import '../../widgets/avatar_tile.dart';

/// Session-timeout re-authentication (STF-004): the app locked after a period
/// of inactivity; the signed-in user re-enters their password.
class LockScreen extends StatefulWidget {
  const LockScreen({super.key});

  @override
  State<LockScreen> createState() => _LockScreenState();
}

class _LockScreenState extends State<LockScreen> {
  final _password = TextEditingController();

  @override
  void dispose() {
    _password.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = context.colors;
    final session = context.session;
    return Scaffold(
      body: SafeArea(
        child: ListenableBuilder(
          listenable: session,
          builder: (context, _) => Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Center(
                      child: AvatarTile(
                        initials: _initials(session.displayName),
                        size: 72,
                        tone: AvatarTile.toneFor(session.user?.uid ?? ''),
                      ),
                    ),
                    const SizedBox(height: 18),
                    Text(
                      'Session timed out',
                      textAlign: TextAlign.center,
                      style: SparklingTypography.headlineMedium.copyWith(
                        color: cs.onSurface,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      '${session.displayName} · enter your password to continue',
                      textAlign: TextAlign.center,
                      style: SparklingTypography.bodyLarge.copyWith(
                        color: cs.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 24),
                    TextField(
                      controller: _password,
                      obscureText: true,
                      autofocus: true,
                      decoration: const InputDecoration(
                        hintText: 'Password',
                        prefixIcon: Icon(Symbols.lock_rounded),
                      ),
                      onSubmitted: (_) => session.unlock(_password.text),
                    ),
                    if (session.error != null) ...[
                      const SizedBox(height: 12),
                      InfoBanner(text: session.error!, tone: InfoTone.error),
                    ],
                    const SizedBox(height: 16),
                    PillButton(
                      label: 'Unlock',
                      expand: true,
                      loading: session.busy,
                      onPressed: () => session.unlock(_password.text),
                    ),
                    const SizedBox(height: 8),
                    TextButton(
                      onPressed: session.busy ? null : session.signOut,
                      child: const Text('Sign in as someone else'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  static String _initials(String name) {
    final parts = name.trim().split(RegExp(r'\s+'));
    if (parts.isEmpty || parts.first.isEmpty) return '?';
    if (parts.length == 1) return parts.first.substring(0, 1).toUpperCase();
    return (parts.first[0] + parts.last[0]).toUpperCase();
  }
}
