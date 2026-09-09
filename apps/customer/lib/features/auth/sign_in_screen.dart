import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:sparkling_ui/sparkling_ui.dart';

import '../../app/app_scope.dart';
import '../../app/router.dart';
import '../../widgets/common.dart';
import 'auth_scaffold.dart';

class SignInScreen extends StatefulWidget {
  const SignInScreen({super.key});

  @override
  State<SignInScreen> createState() => _SignInScreenState();
}

class _SignInScreenState extends State<SignInScreen> {
  final _form = GlobalKey<FormState>();
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _busy = false;
  bool _obscure = true;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _run(Future<void> Function() action) async {
    setState(() => _busy = true);
    try {
      await action();
    } catch (e) {
      if (mounted) showSnack(context, describeError(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final repos = context.repos;
    final cs = context.colors;
    return AuthScaffold(
      title: 'Welcome back',
      subtitle: 'Sign in to book, track and earn rewards.',
      child: Form(
        key: _form,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextFormField(
              controller: _email,
              keyboardType: TextInputType.emailAddress,
              autocorrect: false,
              autofillHints: const [AutofillHints.email],
              decoration: const InputDecoration(
                labelText: 'E-mail',
                prefixIcon: Icon(Symbols.mail_rounded),
              ),
              validator: (v) =>
                  (v == null || !v.contains('@')) ? 'Enter your e-mail' : null,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _password,
              obscureText: _obscure,
              autofillHints: const [AutofillHints.password],
              decoration: InputDecoration(
                labelText: 'Password',
                prefixIcon: const Icon(Symbols.lock_rounded),
                suffixIcon: IconButton(
                  tooltip: _obscure ? 'Show password' : 'Hide password',
                  icon: Icon(
                    _obscure
                        ? Symbols.visibility_rounded
                        : Symbols.visibility_off_rounded,
                  ),
                  onPressed: () => setState(() => _obscure = !_obscure),
                ),
              ),
              validator: (v) =>
                  (v == null || v.isEmpty) ? 'Enter your password' : null,
            ),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: _busy ? null : () => context.push(Routes.reset),
                child: const Text('Forgot password?'),
              ),
            ),
            const SizedBox(height: 4),
            PillButton(
              label: 'Sign in',
              loading: _busy,
              expand: true,
              onPressed: () {
                if (!_form.currentState!.validate()) return;
                _run(() => context.session.signIn(_email.text, _password.text));
              },
            ),
            const SizedBox(height: 10),
            PillButton(
              label: 'Continue with Google',
              icon: Symbols.account_circle_rounded,
              variant: PillButtonVariant.outlined,
              expand: true,
              onPressed: _busy
                  ? null
                  : () => _run(() => repos.auth.signInWithGoogle()),
            ),
            if (repos.demo) ...[
              const SizedBox(height: 18),
              InfoBanner(
                tone: InfoTone.azure,
                icon: Symbols.science_rounded,
                text: 'Demo mode — data lives on this device and resets on restart.',
              ),
              const SizedBox(height: 10),
              PillButton(
                label: 'Continue as Thabo',
                icon: Symbols.person_rounded,
                variant: PillButtonVariant.navy,
                expand: true,
                onPressed: _busy
                    ? null
                    : () =>
                          _run(() => context.session.continueAsDemoCustomer()),
              ),
            ],
            const SizedBox(height: 22),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  'New to Sparkling?',
                  style: SparklingTypography.bodyMedium.copyWith(
                    color: cs.onSurfaceVariant,
                  ),
                ),
                TextButton(
                  onPressed: _busy ? null : () => context.push(Routes.signUp),
                  child: const Text('Create account'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
