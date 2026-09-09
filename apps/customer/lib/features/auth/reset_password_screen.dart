import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:sparkling_ui/sparkling_ui.dart';

import '../../app/app_scope.dart';
import '../../widgets/common.dart';
import 'auth_scaffold.dart';

class ResetPasswordScreen extends StatefulWidget {
  const ResetPasswordScreen({super.key});

  @override
  State<ResetPasswordScreen> createState() => _ResetPasswordScreenState();
}

class _ResetPasswordScreenState extends State<ResetPasswordScreen> {
  final _email = TextEditingController();
  bool _busy = false;
  bool _sent = false;

  @override
  void dispose() {
    _email.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    if (!_email.text.contains('@')) {
      showSnack(context, 'Enter the e-mail you signed up with.');
      return;
    }
    setState(() => _busy = true);
    try {
      await context.repos.auth.sendPasswordReset(_email.text);
      setState(() => _sent = true);
    } catch (e) {
      if (mounted) showSnack(context, describeError(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AuthScaffold(
      title: 'Reset password',
      subtitle: "We'll e-mail you a link to choose a new password.",
      showBack: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (_sent) ...[
            InfoBanner(
              tone: InfoTone.success,
              title: 'Check your inbox',
              text:
                  'If ${_email.text.trim()} has an account, a reset link is on its way.',
            ),
            const SizedBox(height: 16),
            PillButton(
              label: 'Back to sign in',
              variant: PillButtonVariant.tonal,
              expand: true,
              onPressed: () => context.pop(),
            ),
          ] else ...[
            TextField(
              controller: _email,
              keyboardType: TextInputType.emailAddress,
              autocorrect: false,
              decoration: const InputDecoration(
                labelText: 'E-mail',
                prefixIcon: Icon(Symbols.mail_rounded),
              ),
            ),
            const SizedBox(height: 16),
            PillButton(
              label: 'Send reset link',
              loading: _busy,
              expand: true,
              onPressed: _send,
            ),
          ],
        ],
      ),
    );
  }
}
