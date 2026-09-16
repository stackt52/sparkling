import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sparkling_core/sparkling_core.dart';
import 'package:sparkling_customer/features/profile/profile_screen.dart';
import 'package:sparkling_ui/sparkling_ui.dart';

import 'helpers.dart';

/// Profile "Your details" sheet — mobile numbers from any country are entered
/// with their code and saved as E.164 (`PATCH /me`).
void main() {
  late Repositories repos;

  setUpAll(() async {
    repos = await bootstrapDemo();
  });

  final phoneInput = find.descendant(
    of: find.byType(PhoneNumberField),
    matching: find.byType(TextField),
  );

  /// Awaits a repository future inside the FakeAsync zone by pumping frames
  /// until the demo delay elapses.
  Future<T> pumpUntil<T>(WidgetTester tester, Future<T> future) async {
    T? value;
    Object? error;
    var done = false;
    future.then((v) {
      value = v;
      done = true;
    }, onError: (Object e) {
      error = e;
      done = true;
    });
    for (var i = 0; i < 50 && !done; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    if (!done) throw StateError('Future did not complete');
    if (error != null) throw error!;
    return value as T;
  }

  Future<void> openDetails(WidgetTester tester) async {
    await pumpScreen(tester, repos, const ProfileScreen());
    await settle(tester);
    expect(find.text('Thabo Nkosi'), findsOneWidget);
    await tester.tap(find.text('Thabo Nkosi'));
    await settle(tester, total: const Duration(milliseconds: 600));
    expect(find.text('Your details'), findsOneWidget);
  }

  testWidgets('saves an international mobile number as E.164', (tester) async {
    await openDetails(tester);
    // Prefilled from the profile (+27 83 111 2222).
    expect(find.text('+27'), findsOneWidget);
    expect(tester.widget<TextField>(phoneInput).controller!.text, '83 111 2222');

    // Pasting a full UK number switches the country chip.
    await tester.enterText(phoneInput, '+44 7400 123456');
    await tester.pump();
    expect(find.text('+44'), findsOneWidget);
    expect(tester.widget<TextField>(phoneInput).controller!.text, '7400 123456');

    await tester.tap(find.widgetWithText(PillButton, 'Save'));
    await settle(tester);

    expect(find.text('Your details'), findsNothing);
    expect(find.textContaining('+44 7400 123456'), findsOneWidget);
    final me = await pumpUntil(tester, repos.customer.me());
    expect(me.phone, '+447400123456');
  });

  testWidgets('rejects a number that is not a mobile number', (tester) async {
    await openDetails(tester);
    await tester.enterText(phoneInput, '12345');
    await tester.pump();
    await tester.tap(find.widgetWithText(PillButton, 'Save'));
    await settle(tester, total: const Duration(milliseconds: 600));

    // Sheet stays open with the inline error; nothing was saved.
    expect(find.text('Your details'), findsOneWidget);
    // Country reflects the saved number (UK after the test above).
    expect(
      find.textContaining(RegExp(r'^Enter a valid .+ mobile number$')),
      findsOneWidget,
    );
    final me = await pumpUntil(tester, repos.customer.me());
    expect(me.phone, isNot('+2712345'));
  });

  test('demo store mirrors the API validation on PATCH /me', () async {
    await expectLater(
      repos.customer.updateMe(const ProfileUpdate(phone: '12345')),
      throwsA(
        isA<ApiException>()
            .having((e) => e.isValidation, 'isValidation', isTrue)
            .having((e) => e.message, 'message', Phone.invalidMessage),
      ),
    );
    final saved = await repos.customer.updateMe(
      const ProfileUpdate(phone: '+263 71 234 5678'),
    );
    expect(saved.phone, '+263712345678');
    expect(Phone.format(saved.phone), '+263 71 234 5678');
  });
}
