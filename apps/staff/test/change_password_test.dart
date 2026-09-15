import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sparkling_core/sparkling_core.dart';
import 'package:sparkling_staff/app/app.dart';
import 'package:sparkling_staff/app/session.dart';
import 'package:sparkling_staff/features/auth/change_password_screen.dart';

import 'test_harness.dart';

/// Pumps the app signed out so the demo persona picker is shown.
Future<void> pumpSignedOut(
  WidgetTester tester,
  Repositories repos, {
  Duration? idleTimeout,
}) async {
  await repos.auth.signOut();
  tester.view.physicalSize = const Size(412, 915);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    StaffApp(repositories: repos, idleTimeout: idleTimeout),
  );
  await tester.pump();
  await settle(tester);
}

Future<void> signInAsNomsa(WidgetTester tester) async {
  expect(find.text('Outlet staff sign in'), findsOneWidget);
  await tester.tap(find.text('Nomsa Dube'));
  await settle(tester);
}

final _newField = find.byKey(const Key('change-password-new'));
final _confirmField = find.byKey(const Key('change-password-confirm'));
final _currentField = find.byKey(const Key('change-password-current'));

void main() {
  final h = DemoHarness()..install();

  testWidgets('new technician: change-password gate → weak password rejected → '
      'valid password → task list', (tester) async {
    final repos = h.repos;
    await pumpSignedOut(tester, repos);
    await signInAsNomsa(tester);

    // Gated: the change screen, not the task list.
    expect(find.byType(ChangePasswordScreen), findsOneWidget);
    expect(find.text('Choose your password'), findsOneWidget);
    expect(
      find.text(
        'Your account was created with a temporary password — '
        'choose your own to continue.',
      ),
      findsOneWidget,
    );
    expect(find.text('My tasks'), findsNothing);
    // The temporary password typed at sign-in is prefilled.
    expect(
      tester.widget<TextFormField>(_currentField).controller!.text,
      'demo',
    );
    expect(repos.demoStore!.me().mustChangePassword, isTrue);

    // Too short / no digit → inline error, still gated.
    await tester.enterText(_newField, 'abc');
    await tester.enterText(_confirmField, 'abc');
    await tester.tap(find.text('Set password'));
    await settle(tester);
    expect(find.text('Use at least 10 characters'), findsOneWidget);
    expect(find.byType(ChangePasswordScreen), findsOneWidget);

    await tester.enterText(_newField, 'abcdefghij');
    await tester.tap(find.text('Set password'));
    await settle(tester);
    expect(find.text('Include at least one digit'), findsOneWidget);

    // Mismatched confirmation.
    await tester.enterText(_newField, 'Sparkle-2026');
    await tester.enterText(_confirmField, 'Sparkle-2025');
    await tester.tap(find.text('Set password'));
    await settle(tester);
    expect(find.text('Passwords do not match'), findsOneWidget);
    expect(repos.demoStore!.me().mustChangePassword, isTrue);

    // Valid → gate cleared → task list.
    await tester.enterText(_confirmField, 'Sparkle-2026');
    await tester.tap(find.text('Set password'));
    await settle(tester, frames: 10);
    expect(find.byType(ChangePasswordScreen), findsNothing);
    expect(find.text('My tasks'), findsOneWidget);
    expect(repos.demoStore!.me().mustChangePassword, isFalse);
    expect(repos.demoStore!.me().passwordChangedAt, isNotNull);
    expect(
      (repos.auth as DemoAuthService).passwords['seed_nomsa'],
      'Sparkle-2026',
    );
    await flushIo(tester);
  });

  testWidgets('the visibility toggles reveal the new password', (tester) async {
    final repos = h.repos;
    await pumpSignedOut(tester, repos);
    await signInAsNomsa(tester);

    bool obscured(Finder f) => tester
        .widget<EditableText>(
          find.descendant(of: f, matching: find.byType(EditableText)),
        )
        .obscureText;

    expect(obscured(_newField), isTrue);
    await tester.tap(
      find.descendant(of: _newField, matching: find.byTooltip('Show password')),
    );
    await settle(tester, frames: 2);
    expect(obscured(_newField), isFalse);
    expect(obscured(_confirmField), isTrue);
    await flushIo(tester);
  });

  testWidgets('a restart while still on the temporary password is gated '
      '(flag persisted in Hive)', (tester) async {
    final repos = h.repos;
    await pumpSignedOut(tester, repos);
    await signInAsNomsa(tester);
    expect(find.byType(ChangePasswordScreen), findsOneWidget);
    await flushIo(tester);
    expect(repos.drafts.load(SessionController.gateStorageKey), {
      'uid': 'seed_nomsa',
      'must_change_password': true,
    });

    // "Restart": a fresh app over the same (still signed-in) repositories —
    // nothing calls the API, the persisted flag alone must gate.
    await tester.pumpWidget(StaffApp(repositories: repos));
    await tester.pump();
    await settle(tester);
    expect(find.byType(ChangePasswordScreen), findsOneWidget);
    expect(find.text('My tasks'), findsNothing);
    await flushIo(tester);
  });

  testWidgets('the idle lock does not bypass the gate', (tester) async {
    final repos = h.repos;
    await pumpSignedOut(tester, repos, idleTimeout: const Duration(minutes: 1));
    await signInAsNomsa(tester);
    expect(find.byType(ChangePasswordScreen), findsOneWidget);

    await tester.pump(const Duration(minutes: 2));
    await settle(tester);
    expect(find.text('Session timed out'), findsOneWidget);

    await tester.enterText(find.byType(TextField).first, 'demo');
    await tester.tap(find.text('Unlock'));
    await settle(tester);
    expect(find.text('Session timed out'), findsNothing);
    expect(find.byType(ChangePasswordScreen), findsOneWidget);
    expect(find.text('My tasks'), findsNothing);
    await flushIo(tester);
  });

  testWidgets('Sign out on the change screen returns to sign-in and clears '
      'the gate', (tester) async {
    final repos = h.repos;
    await pumpSignedOut(tester, repos);
    await signInAsNomsa(tester);
    await tester.tap(find.text('Sign out'));
    await settle(tester);
    expect(find.text('Outlet staff sign in'), findsOneWidget);
    await flushIo(tester);
    expect(repos.drafts.load(SessionController.gateStorageKey), isNull);

    // Established staff are never gated.
    await tester.tap(find.text('Pieter van der Merwe'));
    await settle(tester);
    expect(find.text('My tasks'), findsOneWidget);
    await flushIo(tester);
  });

  test('ChangePasswordScreen.validateNew rules', () {
    expect(ChangePasswordScreen.validateNew(''), 'Choose a new password');
    expect(
      ChangePasswordScreen.validateNew('abc1'),
      'Use at least 10 characters',
    );
    expect(
      ChangePasswordScreen.validateNew('1234567890'),
      'Include at least one letter',
    );
    expect(
      ChangePasswordScreen.validateNew('abcdefghij'),
      'Include at least one digit',
    );
    expect(
      ChangePasswordScreen.validateNew('Temp-12345', current: 'Temp-12345'),
      'Choose a password different from the temporary one',
    );
    expect(ChangePasswordScreen.validateNew('Sparkle-2026'), isNull);
  });
}
