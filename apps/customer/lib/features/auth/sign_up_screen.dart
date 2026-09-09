import 'package:flutter/material.dart';
import 'package:sparkling_ui/sparkling_ui.dart';

import '../../app/app_scope.dart';
import '../../widgets/common.dart';
import 'auth_scaffold.dart';

class SignUpScreen extends StatefulWidget {
  const SignUpScreen({super.key});

  @override
  State<SignUpScreen> createState() => _SignUpScreenState();
}

class _SignUpScreenState extends State<SignUpScreen> {
  final _form = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _busy = false;
  bool _marketing = false;

  @override
  void dispose() {
    _name.dispose();
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_form.currentState!.validate()) return;
    setState(() => _busy = true);
    try {
      await context.session.signUp(
        _email.text,
        _password.text,
        _name.text.trim(),
      );
      // Router redirects to home once the auth stream emits.
    } catch (e) {
      if (mounted) showSnack(context, describeError(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AuthScaffold(
      title: 'Create account',
      subtitle: 'Earn points on every wash from day one.',
      showBack: true,
      child: Form(
        key: _form,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextFormField(
              controller: _name,
              textCapitalization: TextCapitalization.words,
              autofillHints: const [AutofillHints.name],
              decoration: const InputDecoration(
                labelText: 'Full name',
                prefixIcon: Icon(Symbols.person_rounded),
              ),
              validator: (v) =>
                  (v == null || v.trim().length < 2) ? 'Enter your name' : null,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _email,
              keyboardType: TextInputType.emailAddress,
              autocorrect: false,
              autofillHints: const [AutofillHints.email],
              decoration: const InputDecoration(
                labelText: 'E-mail',
                prefixIcon: Icon(Symbols.mail_rounded),
              ),
              validator: (v) => (v == null || !v.contains('@'))
                  ? 'Enter a valid e-mail'
                  : null,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _password,
              obscureText: true,
              autofillHints: const [AutofillHints.newPassword],
              decoration: const InputDecoration(
                labelText: 'Password (8+ characters)',
                prefixIcon: Icon(Symbols.lock_rounded),
              ),
              validator: (v) => (v == null || v.length < 8)
                  ? 'Use at least 8 characters'
                  : null,
            ),
            const SizedBox(height: 8),
            SwitchListTile(
              value: _marketing,
              onChanged: (v) => setState(() => _marketing = v),
              contentPadding: const EdgeInsets.symmetric(horizontal: 4),
              title: const Text('Send me offers and news'),
              subtitle: const Text('Optional. You can change this any time.'),
            ),
            const SizedBox(height: 12),
            PillButton(
              label: 'Create account',
              loading: _busy,
              expand: true,
              onPressed: _submit,
            ),
          ],
        ),
      ),
    );
  }
}
