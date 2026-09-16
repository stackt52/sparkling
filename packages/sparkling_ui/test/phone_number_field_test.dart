import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sparkling_ui/sparkling_ui.dart';

/// [PhoneNumberField] — country chip + grouped national digits → E.164.
void main() {
  setUpAll(() {
    SparklingTypography.useGoogleFonts = false;
  });

  final input = find.descendant(
    of: find.byType(PhoneNumberField),
    matching: find.byType(TextField),
  );
  final chip = find.byKey(const ValueKey('phone-country-chip'));

  Future<void> pump(
    WidgetTester tester, {
    required List<String> emitted,
    String? initialValue,
    bool required = false,
    GlobalKey<FormState>? formKey,
    PhoneNumberController? controller,
  }) async {
    tester.view.physicalSize = const Size(412 * 2, 915 * 2);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: SparklingTheme.light(),
        home: Scaffold(
          body: Form(
            key: formKey,
            child: Column(
              children: [
                PhoneNumberField(
                  controller: controller,
                  initialValue: initialValue,
                  required: required,
                  onChanged: emitted.add,
                ),
                const TextField(key: ValueKey('other')),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.pump();
  }

  testWidgets('typing national digits groups them and emits E.164', (
    tester,
  ) async {
    final emitted = <String>[];
    await pump(tester, emitted: emitted);
    expect(find.text('+27'), findsOneWidget); // default ZA chip
    expect(find.text('71 123 4567'), findsOneWidget); // ZA example hint

    await tester.enterText(input, '0821234567');
    await tester.pump();
    expect(tester.widget<TextField>(input).controller!.text, '82 123 4567');
    expect(emitted.last, '+27821234567');

    await tester.enterText(input, '');
    await tester.pump();
    expect(emitted.last, '');
  });

  testWidgets('switching country via the sheet re-targets the number', (
    tester,
  ) async {
    final emitted = <String>[];
    await pump(tester, emitted: emitted);
    await tester.tap(chip);
    await tester.pumpAndSettle();
    expect(find.text('Choose country'), findsOneWidget);
    expect(find.text('South Africa'), findsWidgets); // pinned default

    await tester.enterText(
      find.byKey(const ValueKey('phone-country-search')),
      'united k',
    );
    await tester.pumpAndSettle();
    expect(find.text('United Kingdom'), findsOneWidget);
    expect(find.text('United States'), findsNothing);
    await tester.tap(find.text('United Kingdom'));
    await tester.pumpAndSettle();

    expect(find.text('+44'), findsOneWidget);
    expect(find.text('7400 123456'), findsOneWidget); // GB example hint
    expect(PhoneNumberField.recentCountries.first.iso, 'GB');

    await tester.enterText(input, '07400123456');
    await tester.pump();
    expect(tester.widget<TextField>(input).controller!.text, '7400 123456');
    expect(emitted.last, '+447400123456');

    // Dial-code search.
    await tester.tap(chip);
    await tester.pumpAndSettle();
    expect(find.text('Recent'.toUpperCase()), findsOneWidget);
    await tester.enterText(
      find.byKey(const ValueKey('phone-country-search')),
      '+263',
    );
    await tester.pumpAndSettle();
    expect(find.text('Zimbabwe'), findsOneWidget);
    await tester.tap(find.text('Zimbabwe'));
    await tester.pumpAndSettle();
    expect(find.text('+263'), findsOneWidget);
    // The digits stay; 7400123456 is not a Zimbabwean mobile → ''.
    expect(emitted.last, '');
  });

  testWidgets('pasting a full +44 number switches the country', (
    tester,
  ) async {
    final emitted = <String>[];
    await pump(tester, emitted: emitted);
    await tester.enterText(input, '+44 7400 123456');
    await tester.pump();
    expect(find.text('+44'), findsOneWidget);
    expect(tester.widget<TextField>(input).controller!.text, '7400 123456');
    expect(emitted.last, '+447400123456');

    await tester.enterText(input, '0027 82 123 4567');
    await tester.pump();
    expect(find.text('+27'), findsOneWidget);
    expect(emitted.last, '+27821234567');
  });

  testWidgets('invalid number shows an inline error after blur', (
    tester,
  ) async {
    final emitted = <String>[];
    await pump(tester, emitted: emitted);
    await tester.enterText(input, '12345');
    await tester.pump();
    expect(emitted.last, '');
    expect(find.text('Enter a valid South Africa mobile number'), findsNothing);

    await tester.tap(find.byKey(const ValueKey('other')));
    await tester.pump();
    expect(
      find.text('Enter a valid South Africa mobile number'),
      findsOneWidget,
    );

    // Fixing the number clears the error immediately.
    await tester.enterText(input, '0821234567');
    await tester.pump();
    expect(find.text('Enter a valid South Africa mobile number'), findsNothing);
    expect(emitted.last, '+27821234567');
  });

  testWidgets('required field fails Form.validate() when empty', (
    tester,
  ) async {
    final key = GlobalKey<FormState>();
    await pump(tester, emitted: [], required: true, formKey: key);
    expect(key.currentState!.validate(), isFalse);
    await tester.pump();
    expect(find.text('Enter a mobile number'), findsOneWidget);
    await tester.enterText(input, '082 123 4567');
    await tester.pump();
    expect(find.text('Enter a mobile number'), findsNothing);
    expect(key.currentState!.validate(), isTrue);
  });

  testWidgets('initialValue prefills country and digits; controller syncs', (
    tester,
  ) async {
    final emitted = <String>[];
    await pump(tester, emitted: emitted, initialValue: '+447911123456');
    expect(find.text('+44'), findsOneWidget);
    expect(tester.widget<TextField>(input).controller!.text, '7911 123456');

    final controller = PhoneNumberController(initialValue: '+27831112222');
    expect(controller.country.iso, 'ZA');
    expect(controller.nationalDigits, '831112222');
    expect(controller.value, '+27831112222');
    expect(controller.isValid, isTrue);
    await pump(tester, emitted: emitted, controller: controller);
    expect(tester.widget<TextField>(input).controller!.text, '83 111 2222');
    controller.value = '+263712345678';
    await tester.pump();
    expect(find.text('+263'), findsOneWidget);
    expect(tester.widget<TextField>(input).controller!.text, '71 234 5678');
    controller.value = '';
    await tester.pump();
    expect(tester.widget<TextField>(input).controller!.text, '');
    expect(controller.isEmpty, isTrue);
    controller.dispose();
  });
}
