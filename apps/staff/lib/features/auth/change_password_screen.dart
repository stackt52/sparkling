import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:sparkling_ui/sparkling_ui.dart';

import '../../app/router.dart';
import '../../app/scope.dart';
import '../../widgets/avatar_tile.dart';

/// Forced password change for staff accounts created from the admin
/// dashboard with a temporary password (ADM-010). The router sends every
/// route here while `session.mustChangePassword`; on success → tasks.
class ChangePasswordScreen extends StatefulWidget {
  const ChangePasswordScreen({super.key});

  /// Password rules shared with the validator and the live checklist.
  static const int minLength = 10;

  static bool hasLetter(String v) => RegExp(r'[A-Za-z]').hasMatch(v);
  static bool hasDigit(String v) => RegExp(r'\d').hasMatch(v);
  static bool longEnough(String v) => v.length >= minLength;

  /// `null` when [value] satisfies every rule, else the inline error.
  static String? validateNew(String? value, {String? current}) {
    final v = value ?? '';
    if (v.isEmpty) return 'Choose a new password';
    if (!longEnough(v)) return 'Use at least $minLength characters';
    if (!hasLetter(v)) return 'Include at least one letter';
    if (!hasDigit(v)) return 'Include at least one digit';
    if (current != null && current.isNotEmpty && v == current) {
      return 'Choose a password different from the temporary one';
    }
    return null;
  }

  @override
  State<ChangePasswordScreen> createState() => _ChangePasswordScreenState();
}

class _ChangePasswordScreenState extends State<ChangePasswordScreen> {
  final _formKey = GlobalKey<FormState>();
  final _current = TextEditingController();
  final _next = TextEditingController();
  final _confirm = TextEditingController();
  bool _showCurrent = false;
  bool _showNext = false;
  bool _showConfirm = false;
  bool _prefilled = false;

  @override
  void initState() {
    super.initState();
    _next.addListener(_refresh);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Prefill the temporary password typed on the sign-in form (once).
    if (!_prefilled) {
      _prefilled = true;
      _current.text = context.session.temporaryPassword ?? '';
    }
  }

  void _refresh() => setState(() {});

  @override
  void dispose() {
    _next.removeListener(_refresh);
    _current.dispose();
    _next.dispose();
    _confirm.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    final session = context.session;
    final ok = await session.completePasswordChange(_current.text, _next.text);
    if (!mounted) return;
    if (ok && !session.mustChangePassword) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Password set — welcome to Sparkling.')),
      );
      context.go(Routes.tasks);
    }
  }

  Widget _eye(bool shown, VoidCallback toggle) => IconButton(
    tooltip: shown ? 'Hide password' : 'Show password',
    onPressed: toggle,
    icon: Icon(
      shown ? Symbols.visibility_off_rounded : Symbols.visibility_rounded,
    ),
  );

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
              constraints: const BoxConstraints(maxWidth: 480),
              child: ListView(
                padding: const EdgeInsets.fromLTRB(24, 32, 24, 24),
                children: [
                  const Center(child: SparklingLogo(height: 44)),
                  const SizedBox(height: 28),
                  Row(
                    children: [
                      AvatarTile(
                        initials: _initials(session.displayName),
                        size: 48,
                        tone: AvatarTile.toneFor(session.user?.uid ?? ''),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              session.displayName,
                              style: SparklingTypography.titleMedium.copyWith(
                                color: cs.onSurface,
                              ),
                            ),
                            if (session.user?.email != null)
                              Text(
                                session.user!.email!,
                                style: SparklingTypography.bodyMedium.copyWith(
                                  color: cs.onSurfaceVariant,
                                ),
                              ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),
                  Text(
                    'Choose your password',
                    style: SparklingTypography.headlineLarge.copyWith(
                      color: cs.onSurface,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Your account was created with a temporary password — '
                    'choose your own to continue.',
                    style: SparklingTypography.bodyLarge.copyWith(
                      color: cs.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 24),
                  Form(
                    key: _formKey,
                    autovalidateMode: AutovalidateMode.onUserInteraction,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        TextFormField(
                          key: const Key('change-password-current'),
                          controller: _current,
                          obscureText: !_showCurrent,
                          autocorrect: false,
                          enableSuggestions: false,
                          autofillHints: const [AutofillHints.password],
                          decoration: InputDecoration(
                            labelText: 'Temporary password',
                            prefixIcon: const Icon(Symbols.key_rounded),
                            suffixIcon: _eye(
                              _showCurrent,
                              () =>
                                  setState(() => _showCurrent = !_showCurrent),
                            ),
                          ),
                          validator: (v) => (v == null || v.isEmpty)
                              ? 'Enter the temporary password you signed in with'
                              : null,
                        ),
                        const SizedBox(height: 12),
                        TextFormField(
                          key: const Key('change-password-new'),
                          controller: _next,
                          obscureText: !_showNext,
                          autocorrect: false,
                          enableSuggestions: false,
                          autofillHints: const [AutofillHints.newPassword],
                          decoration: InputDecoration(
                            labelText: 'New password',
                            prefixIcon: const Icon(Symbols.lock_rounded),
                            suffixIcon: _eye(
                              _showNext,
                              () => setState(() => _showNext = !_showNext),
                            ),
                          ),
                          validator: (v) => ChangePasswordScreen.validateNew(
                            v,
                            current: _current.text,
                          ),
                        ),
                        const SizedBox(height: 10),
                        _Rules(value: _next.text),
                        const SizedBox(height: 12),
                        TextFormField(
                          key: const Key('change-password-confirm'),
                          controller: _confirm,
                          obscureText: !_showConfirm,
                          autocorrect: false,
                          enableSuggestions: false,
                          autofillHints: const [AutofillHints.newPassword],
                          decoration: InputDecoration(
                            labelText: 'Confirm new password',
                            prefixIcon: const Icon(Symbols.lock_reset_rounded),
                            suffixIcon: _eye(
                              _showConfirm,
                              () =>
                                  setState(() => _showConfirm = !_showConfirm),
                            ),
                          ),
                          onFieldSubmitted: (_) => _submit(),
                          validator: (v) => (v == null || v.isEmpty)
                              ? 'Repeat the new password'
                              : v != _next.text
                              ? 'Passwords do not match'
                              : null,
                        ),
                        if (session.error != null) ...[
                          const SizedBox(height: 12),
                          InfoBanner(
                            text: session.error!,
                            tone: InfoTone.error,
                          ),
                        ],
                        const SizedBox(height: 20),
                        PillButton(
                          label: 'Set password',
                          icon: Symbols.check_rounded,
                          expand: true,
                          loading: session.busy,
                          onPressed: _submit,
                        ),
                        const SizedBox(height: 8),
                        TextButton(
                          onPressed: session.busy ? null : session.signOut,
                          child: const Text('Sign out'),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 8),
                  AuditNote(
                    icon: Symbols.verified_user_rounded,
                    text:
                        'The temporary password stops working once you set '
                        'your own. Your outlet manager can issue a new one '
                        'if you forget it.',
                  ),
                ],
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

/// Live checklist of the password rules under the new-password field.
class _Rules extends StatelessWidget {
  const _Rules({required this.value});
  final String value;

  @override
  Widget build(BuildContext context) {
    final cs = context.colors;
    final rules = [
      (
        'At least ${ChangePasswordScreen.minLength} characters',
        ChangePasswordScreen.longEnough(value),
      ),
      ('At least one letter', ChangePasswordScreen.hasLetter(value)),
      ('At least one digit', ChangePasswordScreen.hasDigit(value)),
    ];
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final (label, ok) in rules)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: Row(
                children: [
                  Icon(
                    ok
                        ? Symbols.check_circle_rounded
                        : Symbols.radio_button_unchecked_rounded,
                    size: 18,
                    fill: ok ? 1 : 0,
                    color: ok ? cs.primary : cs.onSurfaceVariant,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    label,
                    style: SparklingTypography.bodyMedium.copyWith(
                      color: ok ? cs.onSurface : cs.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
