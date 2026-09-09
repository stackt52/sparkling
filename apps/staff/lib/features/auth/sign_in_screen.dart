import 'package:flutter/material.dart';
import 'package:sparkling_core/sparkling_core.dart';
import 'package:sparkling_ui/sparkling_ui.dart';

import '../../app/scope.dart';
import '../../widgets/avatar_tile.dart';

/// Staff sign-in (STF-001): e-mail + password. In demo mode a persona picker
/// (Pieter technician / Johan supervisor / Ayesha manager) sits above the
/// form.
class SignInScreen extends StatefulWidget {
  const SignInScreen({super.key});

  @override
  State<SignInScreen> createState() => _SignInScreenState();
}

class _SignInScreenState extends State<SignInScreen> {
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _formKey = GlobalKey<FormState>();
  bool _obscure = true;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    await context.session.signIn(_email.text, _password.text);
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
              constraints: const BoxConstraints(maxWidth: 480),
              child: ListView(
                padding: const EdgeInsets.fromLTRB(24, 32, 24, 24),
                children: [
                  const Center(child: SparklingLogo(height: 44)),
                  const SizedBox(height: 28),
                  Text(
                    'Outlet staff sign in',
                    style: SparklingTypography.headlineLarge.copyWith(
                      color: cs.onSurface,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Use the account your outlet manager created for you.',
                    style: SparklingTypography.bodyLarge.copyWith(
                      color: cs.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 24),
                  if (session.demo) ...[
                    _PersonaPicker(busy: session.busy),
                    const SizedBox(height: 20),
                    Row(
                      children: [
                        const Expanded(child: Divider()),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                          child: Text(
                            'or sign in with e-mail',
                            style: SparklingTypography.labelMedium.copyWith(
                              color: cs.onSurfaceVariant,
                            ),
                          ),
                        ),
                        const Expanded(child: Divider()),
                      ],
                    ),
                    const SizedBox(height: 20),
                  ],
                  Form(
                    key: _formKey,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        TextFormField(
                          controller: _email,
                          keyboardType: TextInputType.emailAddress,
                          autocorrect: false,
                          autofillHints: const [AutofillHints.username],
                          decoration: const InputDecoration(
                            hintText: 'E-mail',
                            prefixIcon: Icon(Symbols.mail_rounded),
                          ),
                          validator: (v) => (v == null || !v.contains('@'))
                              ? 'Enter your work e-mail'
                              : null,
                        ),
                        const SizedBox(height: 12),
                        TextFormField(
                          controller: _password,
                          obscureText: _obscure,
                          autofillHints: const [AutofillHints.password],
                          decoration: InputDecoration(
                            hintText: 'Password',
                            prefixIcon: const Icon(Symbols.key_rounded),
                            suffixIcon: IconButton(
                              tooltip: _obscure
                                  ? 'Show password'
                                  : 'Hide password',
                              onPressed: () =>
                                  setState(() => _obscure = !_obscure),
                              icon: Icon(
                                _obscure
                                    ? Symbols.visibility_rounded
                                    : Symbols.visibility_off_rounded,
                              ),
                            ),
                          ),
                          onFieldSubmitted: (_) => _submit(),
                          validator: (v) => (v == null || v.isEmpty)
                              ? 'Enter your password'
                              : null,
                        ),
                        if (session.error != null) ...[
                          const SizedBox(height: 12),
                          InfoBanner(text: session.error!, tone: InfoTone.error),
                        ],
                        const SizedBox(height: 20),
                        PillButton(
                          label: 'Sign in',
                          expand: true,
                          loading: session.busy,
                          onPressed: _submit,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  AuditNote(
                    icon: Symbols.verified_user_rounded,
                    text:
                        'Sessions lock after 30 minutes without activity — '
                        'you will be asked for your password again (STF-004).',
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _PersonaPicker extends StatelessWidget {
  const _PersonaPicker({required this.busy});
  final bool busy;

  static const _personas = [
    (DemoPersonas.technician, 'Technician · Sandton bay team'),
    (DemoPersonas.supervisor, 'Supervisor · Sandton'),
    (DemoPersonas.manager, 'Manager · Sandton + Rosebank'),
  ];

  @override
  Widget build(BuildContext context) {
    final cs = context.colors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            StatusChip(
              label: 'Demo mode',
              tone: StatusChipTone.gold,
              icon: Symbols.offline_bolt_rounded,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                'Pick a persona — no network needed.',
                style: SparklingTypography.bodyMedium.copyWith(
                  color: cs.onSurfaceVariant,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        for (final (user, subtitle) in _personas) ...[
          ListTileCard(
            onTap: busy ? null : () => context.session.signInAs(user),
            leading: AvatarTile(
              initials: _initials(user.displayName ?? '?'),
              size: 48,
              tone: AvatarTile.toneFor(user.uid),
            ),
            title: Text(user.displayName ?? user.email ?? user.uid),
            subtitle: Text(subtitle),
            trailing: Icon(
              Symbols.arrow_forward_rounded,
              color: cs.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 10),
        ],
      ],
    );
  }

  static String _initials(String name) {
    final parts = name.trim().split(RegExp(r'\s+'));
    if (parts.length == 1) return parts.first.substring(0, 1).toUpperCase();
    return (parts.first[0] + parts.last[0]).toUpperCase();
  }
}
