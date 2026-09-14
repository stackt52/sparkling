import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce_flutter/hive_flutter.dart';
import 'package:sparkling_core/sparkling_core.dart';

/// Demo-mode contract for staff-raised quotations, damage photos, the public
/// link and the one-time customer decision (docs/API.md "Staff-raised
/// quotations, damage photos & public quote page").
void main() {
  late Directory dir;
  late Repositories repos;
  late DemoStore store;
  final today = DateTime.now();
  var clock = DateTime(today.year, today.month, today.day, 10, 13);

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('sparkling_quote_');
    HiveStore.reset();
    clock = DateTime(today.year, today.month, today.day, 10, 13);
    store = DemoStore(
      currentUser: DemoPersonas.technician,
      clock: () => clock,
    );
    repos = await SparklingCore.bootstrap(
      demo: true,
      hivePath: dir.path,
      demoStore: store,
      clientApp: 'staff',
      demoUser: DemoPersonas.technician,
    );
  });

  tearDown(() async {
    await repos.dispose();
    store.dispose();
    await Hive.deleteFromDisk();
    await Hive.close();
    HiveStore.reset();
    if (dir.existsSync()) dir.deleteSync(recursive: true);
  });

  StaffQuotationInput input({String? opId, bool send = true}) =>
      StaffQuotationInput(
        customerId: 'seed_thabo',
        vehicleId: DemoStore.vehCorolla,
        outletId: DemoStore.outletMenlyn,
        category: 'Dent, Scratch',
        description: 'Door ding and a key scratch on the driver side.',
        items: const [
          QuoteItemInput(
            label: 'Driver door dent',
            category: 'Dent',
            serviceId: DemoStore.svcPdr,
            amountCents: 180000,
          ),
          QuoteItemInput(
            label: 'Key scratch blend',
            category: 'Scratch',
            description: '40 cm along the rear door',
            amountCents: 95000,
          ),
        ],
        validUntil: clock.add(const Duration(days: 14)),
        itemsNote: 'Parts on hand',
        clientOpId: opId ?? SparklingApi.newOpId(),
        sendToCustomer: send,
      );

  Uint8List png() => Uint8List.fromList([
    0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 1, 2, 3, 4, 5, 6, 7, 8,
  ]);

  group('models', () {
    test('StaffQuotationInput serialises the staff contract', () {
      final json = input(opId: 'op-1').toJson();
      expect(json['customer_id'], 'seed_thabo');
      expect(json['send_to_customer'], isTrue);
      expect(json['valid_until'], matches(RegExp(r'^\d{4}-\d{2}-\d{2}$')));
      expect((json['items'] as List).length, 2);
      expect((json['items'] as List).first['service_id'], DemoStore.svcPdr);
      final back = StaffQuotationInput.fromJson(json);
      expect(back.totalCents, 275000);
      expect(back.items[1].description, '40 cm along the rear door');
    });

    test('Quotation parses items, attachments and decision fields', () {
      final q = Quotation.fromJson({
        'id': 'q1',
        'ref': 'QT-2026-0050',
        'customer_id': 'c',
        'vehicle_id': 'v',
        'outlet_id': 'o',
        'category': 'Dent',
        'description': 'x',
        'status': 'accepted',
        'amount_cents': 1000,
        'items': [
          {'label': 'A', 'amount_cents': 1000, 'category': 'Dent'},
        ],
        'attachments': [
          {
            'id': 'a1',
            'kind': 'damage_photo',
            'mime_type': 'image/jpeg',
            'size_bytes': 10,
            'width': 800,
            'height': 600,
            'caption': 'Rear',
            'url': '/v1/quotations/q1/photos/a1',
          },
        ],
        'decision_source': 'public_link',
        'decision_by_name': 'Thabo',
        'decided_at': '2026-09-10T10:00:00Z',
        'public_url': 'https://x/q/t',
        'pdf_url': '/v1/quotations/q1/pdf',
        'items_note': 'note',
      });
      expect(q.items.single.category, 'Dent');
      expect(q.attachments.single.url, '/v1/quotations/q1/photos/a1');
      expect(q.attachments.single.width, 800);
      expect(q.decisionSource, QuoteDecisionSource.publicLink);
      expect(q.decisionLabel, 'Accepted via link by Thabo');
      expect(q.isDecided, isTrue);
      expect(q.canDecide, isFalse);
      expect(q.publicUrl, 'https://x/q/t');
      expect(q.itemsNote, 'note');
      // Round-trips through toJson.
      final again = Quotation.fromJson(q.toJson());
      expect(again, q);
      expect(again.attachments.single.caption, 'Rear');
    });

    test('placeholder PDF starts with %PDF and has an xref table', () {
      final bytes = DemoStore.buildPlaceholderPdf(['Hello (world)']);
      final text = String.fromCharCodes(bytes);
      expect(text, startsWith('%PDF-1.4'));
      expect(text, contains('xref'));
      expect(text, contains(r'Hello \(world\)'));
      expect(text.trim(), endsWith('%%EOF'));
    });
  });

  group('technician raises a quote', () {
    test('→ quoted with items sum, ref, public token and notifications', () async {
      final before = store.notifications.length;
      final q = await repos.staff.raiseQuotation(input());
      expect(q.status, QuotationStatus.quoted);
      expect(q.amountCents, 275000);
      expect(q.ref, matches(RegExp(r'^QT-\d{4}-00\d{2}$')));
      expect(q.publicUrl, startsWith('https://demo.sparkling.local/q/'));
      expect(q.pdfUrl, '/v1/quotations/${q.id}/pdf');
      expect(q.assessorId, 'seed_pieter');
      expect(q.assessorName, 'Pieter van der Merwe');
      expect(q.customerName, 'Thabo Nkosi');
      expect(q.items.length, 2);
      expect(q.items.first.serviceId, DemoStore.svcPdr);
      expect(q.itemsNote, 'Parts on hand');
      expect(q.canDecide, isTrue);
      // quote_ready push + WhatsApp (Thabo is opted in).
      final sent = store.notifications.skip(before).toList();
      expect(sent.where((n) => n.templateKey == 'quote_ready').length, 2);
      expect(
        sent.any(
          (n) =>
              n.channel == NotifyChannel.whatsapp &&
              n.body.contains(q.publicUrl!),
        ),
        isTrue,
      );
      // Idempotent on client_op_id.
      final again = await repos.staff.raiseQuotation(
        input(opId: q.clientOpId),
      );
      expect(again.id, q.id);
      // Listed for the outlet and for the customer.
      final list = await repos.staff.quotations(
        outletId: DemoStore.outletMenlyn,
      );
      expect(list.first.id, q.id);
    });

    test('send_to_customer=false raises silently', () async {
      final before = store.notifications.length;
      final q = await repos.staff.raiseQuotation(input(send: false));
      expect(q.status, QuotationStatus.quoted);
      expect(store.notifications.length, before);
    });

    test('validation: empty items, bad outlet, past valid_until', () async {
      await expectLater(
        repos.staff.raiseQuotation(
          StaffQuotationInput(
            customerId: 'seed_thabo',
            vehicleId: DemoStore.vehCorolla,
            outletId: DemoStore.outletMenlyn,
            category: 'Dent',
            description: 'x',
            items: const [],
            validUntil: clock,
            clientOpId: 'op-empty',
          ),
        ),
        throwsA(isA<ApiException>().having((e) => e.isValidation, 'v', true)),
      );
      await expectLater(
        repos.staff.raiseQuotation(
          StaffQuotationInput(
            customerId: 'seed_thabo',
            vehicleId: DemoStore.vehCorolla,
            outletId: DemoStore.outletGlenVillage, // not Pieter's outlet
            category: 'Dent',
            description: 'x',
            items: const [QuoteItemInput(label: 'a', amountCents: 100)],
            validUntil: clock,
            clientOpId: 'op-outlet',
          ),
        ),
        throwsA(isA<ApiException>().having((e) => e.isForbidden, 'f', true)),
      );
      await expectLater(
        repos.staff.raiseQuotation(
          StaffQuotationInput(
            customerId: 'seed_thabo',
            vehicleId: DemoStore.vehCorolla,
            outletId: DemoStore.outletMenlyn,
            category: 'Dent',
            description: 'x',
            items: const [QuoteItemInput(label: 'a', amountCents: 100)],
            validUntil: clock.subtract(const Duration(days: 2)),
            clientOpId: 'op-past',
          ),
        ),
        throwsA(isA<ApiException>().having((e) => e.isValidation, 'v', true)),
      );
    });

    test('photos: add with caption, load bytes, remove, max 10', () async {
      final q = await repos.staff.raiseQuotation(input());
      final a = await repos.staff.uploadQuotationPhoto(
        q.id,
        png(),
        caption: 'Driver door',
        filename: 'door.png',
      );
      expect(a.kind, 'damage_photo');
      expect(a.mimeType, 'image/png');
      expect(a.caption, 'Driver door');
      expect(a.url, 'demo://photo/${a.id}');
      expect(a.sizeBytes, 16);

      final detail = await repos.staff.quotation(q.id);
      expect(detail.attachments.single.id, a.id);
      expect(detail.photos.length, 1);

      // Both apps can fetch the bytes through the repository.
      final bytes = await repos.staff.photoBytes(a.url!);
      expect(bytes, png());
      store.signInAs(DemoPersonas.customer);
      final asCustomer = await repos.customer.photoBytes(a.url!);
      expect(asCustomer.length, 16);
      store.signInAs(DemoPersonas.technician);

      await repos.staff.deleteQuotationPhoto(q.id, a.id);
      final after = await repos.staff.quotation(q.id);
      expect(after.attachments, isEmpty);
      await expectLater(
        repos.staff.photoBytes(a.url!),
        throwsA(isA<ApiException>().having((e) => e.isNotFound, 'nf', true)),
      );

      for (var i = 0; i < DemoStore.maxQuotationPhotos; i++) {
        await repos.staff.uploadQuotationPhoto(q.id, png());
      }
      await expectLater(
        repos.staff.uploadQuotationPhoto(q.id, png()),
        throwsA(isA<ApiException>().having((e) => e.isValidation, 'v', true)),
      );
    });

    test('share rotates the token and is rate-limited for 60 s', () async {
      final q = await repos.staff.raiseQuotation(input());
      final link = await repos.staff.shareQuotation(q.id);
      expect(link.publicUrl, startsWith('https://demo.sparkling.local/q/'));
      expect(link.publicUrl, isNot(q.publicUrl));
      expect(link.expiresAt, isNotNull);
      final fresh = await repos.staff.quotation(q.id);
      expect(fresh.publicUrl, link.publicUrl);

      await expectLater(
        repos.staff.shareQuotation(q.id),
        throwsA(
          isA<ApiException>().having((e) => e.isRateLimited, 'rl', true),
        ),
      );
      clock = clock.add(const Duration(seconds: 61));
      final again = await repos.staff.shareQuotation(q.id);
      expect(again.publicUrl, isNot(link.publicUrl));
    });

    test('pdf bytes start with %PDF for staff and customer', () async {
      final q = await repos.staff.raiseQuotation(input());
      final pdf = await repos.staff.quotationPdf(q.id);
      expect(String.fromCharCodes(pdf.take(5)), '%PDF-');
      expect(String.fromCharCodes(pdf), contains(q.ref));
      store.signInAs(DemoPersonas.customer);
      final mine = await repos.customer.quotationPdf(q.id);
      expect(String.fromCharCodes(mine.take(5)), '%PDF-');
    });

    test('public_url is hidden from the customer', () async {
      final q = await repos.staff.raiseQuotation(input());
      store.signInAs(DemoPersonas.customer);
      final mine = await repos.customer.quotation(q.id);
      expect(mine.publicUrl, isNull);
      expect(mine.pdfUrl, isNotNull);
      expect(mine.items.length, 2);
      final list = await repos.customer.quotations();
      expect(list.any((x) => x.id == q.id && x.publicUrl == null), isTrue);
    });
  });

  group('customer decision', () {
    test('is one-time: second call → 409 conflict with decided_at', () async {
      final q = await repos.staff.raiseQuotation(input());
      store.signInAs(DemoPersonas.customer);
      final accepted = await repos.customer.decideQuotation(
        q.id,
        accept: true,
      );
      expect(accepted.status, QuotationStatus.accepted);
      expect(accepted.decisionSource, QuoteDecisionSource.app);
      expect(accepted.decisionLabel, 'Accepted in app');
      expect(accepted.isDecided, isTrue);
      expect(accepted.canDecide, isFalse);

      await expectLater(
        repos.customer.decideQuotation(q.id, accept: false),
        throwsA(
          isA<ApiException>()
              .having((e) => e.isConflict, 'conflict', true)
              .having((e) => e.statusCode, 'status', 409)
              .having((e) => e.data?['status'], 'status', 'accepted')
              .having((e) => e.data?['decided_at'], 'decided_at', isNotNull),
        ),
      );
      // Photos are locked after the decision.
      store.signInAs(DemoPersonas.technician);
      await expectLater(
        repos.staff.deleteQuotationPhoto(q.id, 'nope'),
        throwsA(isA<ApiException>().having((e) => e.isConflict, 'c', true)),
      );
    });

    test('expired quote → 410 gone', () async {
      final q = await repos.staff.raiseQuotation(input());
      store.signInAs(DemoPersonas.customer);
      clock = clock.add(const Duration(days: 20));
      await expectLater(
        repos.customer.decideQuotation(q.id, accept: true),
        throwsA(
          isA<ApiException>()
              .having((e) => e.code, 'code', 'gone')
              .having((e) => e.statusCode, 'status', 410),
        ),
      );
    });

    test('decline with a note keeps the note and notifies the assessor', () async {
      final q = await repos.staff.raiseQuotation(input());
      final before = store.notifications.length;
      store.signInAs(DemoPersonas.customer);
      final declined = await repos.customer.decideQuotation(
        q.id,
        accept: false,
        note: 'Too pricey',
      );
      expect(declined.status, QuotationStatus.declined);
      expect(declined.decisionNote, 'Too pricey');
      expect(declined.decisionLabel, 'Declined in app');
      final sent = store.notifications.skip(before).toList();
      expect(sent.any((n) => n.templateKey == 'quote_decided'), isTrue);
    });
  });

  group('offline queue', () {
    test('quotation.raise replays through /sync/batch', () async {
      final op = input(opId: 'op-offline');
      await repos.offlineQueue.enqueue(
        SyncKinds.quotationRaise,
        op.toJson(),
        clientOpId: op.clientOpId,
        label: 'Quote',
      );
      final report = await repos.offlineQueue.sync(force: true);
      expect(report.succeeded, 1);
      final applied = repos.offlineQueue.byId('op-offline')!;
      expect(applied.status, QueuedOpStatus.succeeded);
      expect(applied.result?['status'], 'quoted');
      expect(applied.result?['amount_cents'], 275000);
      expect(applied.result?['id'], isNotNull);
      final list = await repos.staff.quotations(
        outletId: DemoStore.outletMenlyn,
      );
      expect(list.any((q) => q.clientOpId == 'op-offline'), isTrue);
    });
  });
}
