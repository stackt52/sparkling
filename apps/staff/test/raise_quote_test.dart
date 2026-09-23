import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:share_plus/share_plus.dart';
import 'package:sparkling_core/sparkling_core.dart';
import 'package:sparkling_staff/app/router.dart';
import 'package:sparkling_staff/features/quote/items_step.dart';
import 'package:sparkling_staff/features/quote/quote_actions.dart';
import 'package:sparkling_staff/features/quote/quote_widgets.dart';
import 'package:sparkling_staff/features/quote/raise_quote_controller.dart';
import 'package:sparkling_staff/features/scanner/scan_review_screen.dart';
import 'package:sparkling_ui/sparkling_ui.dart';

import 'test_harness.dart';

/// A valid 1×1 PNG so `Image.memory` decodes the fake damage photo.
final Uint8List kTinyPng = Uint8List.fromList(const [
  0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0x00, 0x00, 0x00, 0x0D, //
  0x49, 0x48, 0x44, 0x52, 0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01, //
  0x08, 0x02, 0x00, 0x00, 0x00, 0x90, 0x77, 0x53, 0xDE, 0x00, 0x00, 0x00, //
  0x0C, 0x49, 0x44, 0x41, 0x54, 0x78, 0x9C, 0x63, 0x68, 0x98, 0xB0, 0x00, //
  0x00, 0x03, 0x44, 0x01, 0xB1, 0x7A, 0xD7, 0x36, 0x14, 0x00, 0x00, 0x00, //
  0x00, 0x49, 0x45, 0x4E, 0x44, 0xAE, 0x42, 0x60, 0x82, //
]);

/// Raise-quote flow (STF-010/012, CUS-030..034) on the demo repositories.
void main() {
  Future<void> openRaiseQuote(WidgetTester tester) async {
    await openFabMenu(tester);
    await tester.tap(find.byKey(const ValueKey('fab-raise-quote')));
    await settle(tester);
    expect(find.text('Step 1 of 4 · Customer'), findsOneWidget);
    expect(find.text('Raise quote'), findsOneWidget);
  }

  group('technician', () {
    final h = DemoHarness()..install();

    setUp(() {
      ItemsStep.photoPicker = (context, source) async => QuotePhotoDraft(
        id: 'test-photo',
        bytes: kTinyPng,
        name: 'door.png',
        mimeType: 'image/png',
      );
      QuoteActions.shareOverride = null;
    });

    testWidgets(
      'register → add vehicle → item with service → photo → raise → confirmation',
      (tester) async {
        // Capture the clipboard writes of "Copy link".
        String? copied;
        tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          (call) async {
            if (call.method == 'Clipboard.setData') {
              copied = (call.arguments as Map)['text'] as String?;
            }
            return null;
          },
        );

        await pumpStaffApp(tester, h.repos);
        await openRaiseQuote(tester);

        // Step 1 — register a new customer.
        await tester.tap(find.text('Register new customer'));
        await settle(tester);
        await tester.enterText(find.byType(TextFormField).first, 'Lindiwe Zulu');
        await tester.enterText(
          find.descendant(
            of: find.byType(PhoneNumberField),
            matching: find.byType(TextField),
          ),
          '072 555 0199',
        );
        await tester.pump();
        await tester.tap(find.widgetWithText(PillButton, 'Register customer'));
        await settle(tester);
        expect(find.text('Lindiwe Zulu'), findsOneWidget);
        await tester.tap(find.text('Choose vehicle'));
        await settle(tester);

        // Step 2 — add a vehicle by hand.
        expect(find.text('Step 2 of 4 · Vehicle'), findsOneWidget);
        await tester.tap(find.text('Add manually'));
        await settle(tester);
        await tester.enterText(find.byType(TextFormField).first, 'nd 123 456');
        await tester.tap(find.text('Save vehicle'));
        await settle(tester);
        expect(find.text('ND 123 456'), findsWidgets);
        await tester.pump(const Duration(seconds: 5));
        await settle(tester);
        await tester.tap(find.text('What needs attention'));
        await settle(tester);

        // Step 3 — one item: Scratch → suggests "Scratch repair" + service.
        expect(find.text('Step 3 of 4 · What needs attention'), findsOneWidget);
        await tester.tap(find.byKey(const ValueKey('quote-add-item')));
        await settle(tester);
        await tester.tap(find.byKey(const ValueKey('quote-cat-Scratch')));
        await tester.pump();
        expect(
          tester
              .widget<TextFormField>(
                find.byKey(const ValueKey('quote-item-label')),
              )
              .controller!
              .text,
          'Scratch repair',
        );
        // The auto-body catalogue service is linked automatically.
        expect(find.textContaining('Linked · From R'), findsOneWidget);
        await tester.enterText(
          find.byKey(const ValueKey('quote-item-description')),
          'Along the rear passenger door',
        );
        await tester.enterText(
          find.byKey(const ValueKey('quote-item-amount')),
          '950',
        );
        await tester.tap(find.byKey(const ValueKey('quote-item-save')));
        await settle(tester);
        expect(find.text('Scratch repair'), findsWidgets);
        expect(find.text('R 950.00'), findsWidgets);
        expect(find.byType(CategoryChip), findsOneWidget);

        await tester.enterText(
          find.byKey(const ValueKey('quote-description')),
          'Key scratch along the passenger side, paint through to primer.',
        );
        await tester.pump();

        // Damage photo through the (fake) camera, then caption it.
        await scrollTo(tester, find.byKey(const ValueKey('quote-add-photo')));
        await tester.tap(find.byKey(const ValueKey('quote-add-photo')));
        await settle(tester);
        await tester.tap(find.text('Take photo'));
        await settle(tester);
        expect(find.text('Photo caption'), findsOneWidget);
        await tester.enterText(
          find.byKey(const ValueKey('quote-photo-caption')),
          'Rear door',
        );
        await tester.tap(find.text('Save caption'));
        await settle(tester);
        expect(find.byType(DraftPhotoTile), findsOneWidget);
        expect(find.text('1 of 10'), findsOneWidget);

        // Validity defaults to 14 days.
        await scrollTo(tester, find.text('14 days'));
        expect(
          tester.widget<ChoiceChip>(find.widgetWithText(ChoiceChip, '14 days')).selected,
          isTrue,
        );
        await tester.tap(find.text('Review & send'));
        await settle(tester);

        // Step 4 — summary + send switch on; raise.
        expect(find.text('Step 4 of 4 · Review & send'), findsOneWidget);
        expect(find.text('Lindiwe Zulu'), findsOneWidget);
        expect(find.text('ND 123 456'), findsOneWidget);
        expect(find.text('Sparkling Auto Care Centre Menlyn'), findsOneWidget);
        expect(find.text('Send to customer now'), findsOneWidget);
        final cta = find.byKey(const ValueKey('quote-raise-cta'));
        expect(find.textContaining('Raise quote · R 950'), findsOneWidget);
        await tester.tap(cta);
        await settle(tester, frames: 12);

        // Confirmation: ref, total, WhatsApp banner, public link + copy.
        expect(find.text('Quote raised'), findsOneWidget);
        expect(find.textContaining('QT-'), findsWidgets);
        expect(
          find.byKey(const ValueKey('quote-confirmation-total')),
          findsOneWidget,
        );
        expect(find.text('R 950.00'), findsOneWidget);
        expect(find.text('Sent to Lindiwe on WhatsApp'), findsOneWidget);
        expect(find.byType(ConfettiBlob), findsOneWidget);
        expect(find.byKey(const ValueKey('quote-public-url')), findsOneWidget);
        // The work-order note sits above the link card; bring the copy
        // button into the viewport before tapping.
        await scrollTo(tester, find.byKey(const ValueKey('quote-copy-link')));
        await tester.tap(find.byKey(const ValueKey('quote-copy-link')));
        await settle(tester);
        expect(find.text('Link copied'), findsOneWidget);
        expect(copied, startsWith('https://demo.sparkling.local/q/'));

        // Share goes through the (mocked) share sheet.
        ShareParams? shared;
        QuoteActions.shareOverride = (p) async => shared = p;
        await tester.tap(find.byKey(const ValueKey('quote-share-link')));
        await settle(tester);
        expect(shared?.text, contains(copied!));

        // Store: quoted, one attachment with the caption, sum = 950.
        final list = await pumpUntil(
          tester,
          h.repos.staff.quotations(outletId: DemoStore.outletMenlyn),
        );
        final created = list.firstWhere((q) => q.customerName == 'Lindiwe Zulu');
        expect(created.status, QuotationStatus.quoted);
        expect(created.amountCents, 95000);
        expect(created.items.single.serviceId, DemoStore.svcSpotRepair);
        expect(created.attachments.single.caption, 'Rear door');
        expect(created.publicUrl, copied);
        expect(h.repos.drafts.has(RaiseQuoteController.draftKey), isFalse);

        // "View quote" opens the staff detail with the timeline.
        await scrollTo(tester, find.byKey(const ValueKey('quote-view')));
        await tester.tap(find.byKey(const ValueKey('quote-view')));
        await settle(tester, frames: 10);
        expect(find.text(created.ref), findsOneWidget);
        expect(find.text('Waiting for the customer'), findsOneWidget);
        // The detail body is a lazy ListView; the Terms paragraph sits above
        // the timeline, so bring the timeline into the viewport.
        await tester.scrollUntilVisible(
          find.text('Sent to customer'),
          200,
          scrollable: find.byType(Scrollable).first,
        );
        await tester.pumpAndSettle();
        expect(find.text('Sent to customer'), findsOneWidget);
        expect(find.byType(AuthedImage), findsOneWidget);
        // Technicians cannot convert; nothing to convert yet anyway.
        expect(find.byKey(const ValueKey('quote-convert')), findsNothing);
        await flushIo(tester);
      },
    );

    testWidgets('scan review offers "Raise quote" with the plate prefilled', (
      tester,
    ) async {
      await pumpStaffApp(tester, h.repos);
      final router = GoRouter.of(tester.element(find.text('My tasks')));
      router.push(
        Routes.scanReview,
        extra: const ScanReviewArgs(
          result: DiscScanResult(registrationNo: 'ZZ99ZZGP', rawHash: 'h'),
          manual: true,
        ),
      );
      await settle(tester, frames: 8);
      await scrollTo(tester, find.byKey(const ValueKey('scan-raise-quote')));
      await tester.tap(find.byKey(const ValueKey('scan-raise-quote')));
      await settle(tester, frames: 8);
      expect(find.text('Step 1 of 4 · Customer'), findsOneWidget);
      expect(find.text('Raise quote'), findsOneWidget);
      await tester.pump(const Duration(milliseconds: 400));
      await settle(tester);
      expect(find.text('No customer matches “ZZ 99 ZZ GP”'), findsOneWidget);
      await flushIo(tester);
    });
  });

  group('supervisor', () {
    final h = DemoHarness()..install();

    testWidgets('ops quick action + Quotes section → detail with convert', (
      tester,
    ) async {
      await pumpStaffApp(tester, h.repos, persona: DemoPersonas.supervisor);
      await tester.tap(find.text('Ops'));
      await settle(tester);
      // The ops page is one lazy ListView; scroll that one explicitly.
      final page = find
          .descendant(
            of: find.byType(ListView).first,
            matching: find.byType(Scrollable),
          )
          .first;
      await scrollTo(
        tester,
        find.byKey(const ValueKey('ops-raise-quote')),
        scrollable: page,
      );
      expect(find.byKey(const ValueKey('ops-raise-quote')), findsOneWidget);
      await scrollTo(tester, find.text('Quotes'), scrollable: page);
      expect(find.text('1 awaiting'), findsOneWidget);
      // QT-0039 (Zanele) is accepted via the public link: its work order
      // WO-4819 exists already (awaiting check-in, unpaid).
      final accepted = find.byKey(
        ValueKey('ops-quote-${DemoStore.quotationAccepted}'),
      );
      await scrollTo(tester, accepted, scrollable: page);
      await tester.tap(accepted);
      await settle(tester, frames: 8);
      expect(find.text('Accepted via link by Zanele Mthembu'), findsWidgets);
      final year = DateTime.now().year;
      expect(find.text('WO-$year-4819 · awaiting check-in'), findsOneWidget);
      expect(find.text('R 2 850.00 due'), findsOneWidget);
      // The public-link SelectableText carries its own Scrollable; target
      // the detail ListView.
      final detail = find
          .descendant(
            of: find.byType(ListView).last,
            matching: find.byType(Scrollable),
          )
          .first;
      await scrollTo(
        tester,
        find.byKey(const ValueKey('quote-convert')),
        scrollable: detail,
      );
      expect(find.text('Confirm check-in · WO-$year-4819'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('quote-convert')));
      await settle(tester, frames: 8);
      expect(find.textContaining('converted'), findsWidgets);
      expect(find.text('Converted'), findsOneWidget);
      // Same work order, now checked in (auto-assigned in the demo).
      final woDetail = await pumpUntil(
        tester,
        h.repos.staff.workOrder(DemoStore.woAwaitingCheckIn),
      );
      expect(woDetail.workOrder.isCheckedIn, isTrue);
      expect(
        (h.repos.staff as DemoStaffRepository).store.workOrders
            .where((w) => w.quotationId == DemoStore.quotationAccepted),
        hasLength(1),
      );
      expect(find.byKey(const ValueKey('quote-convert')), findsNothing);
      await flushIo(tester);
    });
  });
}
