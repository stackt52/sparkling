import 'package:flutter_test/flutter_test.dart';
import 'package:sparkling_core/sparkling_core.dart';

void main() {
  group('Pdf417DiscParser', () {
    test('parses the sample payload', () {
      final raw = Pdf417DiscParser.sampleDiscPayload();
      expect(Pdf417DiscParser.looksLikeDisc(raw), isTrue);
      final r = Pdf417DiscParser.parse(raw);
      expect(r.registrationNo, 'KL45MNGP');
      expect(r.registrationNoFormatted, 'KL 45 MN GP');
      expect(r.vin, 'AHTFB3CB301234567');
      expect(r.engineNo, '2ZR1234567');
      expect(r.make, 'Toyota');
      expect(r.model, 'Corolla Cross');
      expect(r.colour, 'Celestite Grey');
      expect(r.description, 'Sedan (closed top)');
      expect(r.licenceNo, 'ABC123456');
      expect(r.discExpiry, DateTime(2027, 3, 31));
      expect(r.rawHash, Pdf417DiscParser.hash(raw));
      expect(r.rawHash.length, 64);
      expect(r.isExpired, isFalse);
    });

    test('toVehicleInput produces a scan-sourced POST /vehicles body', () {
      final r = Pdf417DiscParser.parse(Pdf417DiscParser.sampleDiscPayload());
      final json = r.toVehicleInput().toJson();
      expect(json['registration_no'], 'KL 45 MN GP');
      expect(json['source'], 'scan');
      expect(json['disc_hash'], r.rawHash);
      expect(json['disc_expiry'], '2027-03-31');
      expect(json.containsKey('force'), isFalse);
      expect(r.toVehicleInput(force: true).toJson()['force'], isTrue);
    });

    test(
      'accepts a payload without the leading percent and lower-case reg',
      () {
        final raw = Pdf417DiscParser.sampleDiscPayload(registration: 'cj12pzgp')
            .substring(1);
        final r = Pdf417DiscParser.parse(raw);
        expect(r.registrationNo, 'CJ12PZGP');
        expect(r.registrationNoFormatted, 'CJ 12 PZ GP');
      },
    );

    test('keeps short brand names upper-case', () {
      final r = Pdf417DiscParser.parse(
        Pdf417DiscParser.sampleDiscPayload(make: 'BMW', model: '330I'),
      );
      expect(r.make, 'BMW');
      expect(r.model, '330i');
    });

    test('rejects empty and malformed payloads with friendly messages', () {
      expect(
        () => Pdf417DiscParser.parse(''),
        throwsA(
          isA<DiscParseException>().having((e) => e.reason, 'reason', 'empty'),
        ),
      );
      expect(
        () => Pdf417DiscParser.parse('https://example.com/qr'),
        throwsA(
          isA<DiscParseException>().having(
            (e) => e.reason,
            'reason',
            'malformed',
          ),
        ),
      );
      expect(
        () => Pdf417DiscParser.parse('%A%B%C%D'),
        throwsA(
          isA<DiscParseException>().having(
            (e) => e.message,
            'message',
            contains("isn't a vehicle licence disc"),
          ),
        ),
      );
      expect(Pdf417DiscParser.looksLikeDisc('%A%B%C%D'), isFalse);
      expect(Pdf417DiscParser.tryParse('garbage'), isNull);
    });

    test('rejects a partial payload (too few segments)', () {
      final segments = Pdf417DiscParser.sampleDiscPayload().split('%');
      final partial = segments.take(10).join('%');
      expect(
        () => Pdf417DiscParser.parse(partial),
        throwsA(
          isA<DiscParseException>().having(
            (e) => e.reason,
            'reason',
            'malformed',
          ),
        ),
      );
    });

    test('rejects an invalid registration', () {
      final raw = Pdf417DiscParser.sampleDiscPayload(registration: '?');
      expect(Pdf417DiscParser.looksLikeDisc(raw), isFalse);
      expect(
        () => Pdf417DiscParser.parse(raw),
        throwsA(
          isA<DiscParseException>().having(
            (e) => e.reason,
            'reason',
            'registration',
          ),
        ),
      );
    });

    test('rejects an invalid VIN but allows a missing one', () {
      expect(
        () => Pdf417DiscParser.parse(
          Pdf417DiscParser.sampleDiscPayload(vin: 'AHTFB3CB30123456O'),
        ),
        throwsA(
          isA<DiscParseException>().having((e) => e.reason, 'reason', 'vin'),
        ),
      );
      expect(
        () => Pdf417DiscParser.parse(
          Pdf417DiscParser.sampleDiscPayload(vin: 'SHORT'),
        ),
        throwsA(isA<DiscParseException>()),
      );
      final r = Pdf417DiscParser.parse(
        Pdf417DiscParser.sampleDiscPayload(vin: ''),
      );
      expect(r.vin, isNull);
    });

    test('rejects an unparseable expiry, accepts yyyyMMdd', () {
      expect(
        () => Pdf417DiscParser.parse(
          Pdf417DiscParser.sampleDiscPayload(expiry: '31/13/2027x'),
        ),
        throwsA(
          isA<DiscParseException>().having((e) => e.reason, 'reason', 'expiry'),
        ),
      );
      expect(
        Pdf417DiscParser.parse(
          Pdf417DiscParser.sampleDiscPayload(expiry: '20261130'),
        ).discExpiry,
        DateTime(2026, 11, 30),
      );
      expect(
        Pdf417DiscParser.parse(
          Pdf417DiscParser.sampleDiscPayload(expiry: '30/11/2026'),
        ).discExpiry,
        DateTime(2026, 11, 30),
      );
    });

    test('formatRegistration handles non-GP plates', () {
      expect(Pdf417DiscParser.formatRegistration('ABC123WP'), 'ABC123WP');
      expect(
        Pdf417DiscParser.formatRegistration('  cf 123 456 '),
        'CF 123 456',
      );
    });
  });

  group('ScanDebouncer', () {
    test('accepts only one result per session until reset', () {
      final d = ScanDebouncer();
      final raw = Pdf417DiscParser.sampleDiscPayload();
      expect(d.hasResult, isFalse);
      expect(d.accept(raw), isTrue);
      expect(d.accept(raw), isFalse);
      expect(
        d.accept(Pdf417DiscParser.sampleDiscPayload(registration: 'CJ12PZGP')),
        isFalse,
      );
      expect(d.isDuplicate(raw), isTrue);
      expect(d.hasResult, isTrue);
      d.reset();
      expect(d.hasResult, isFalse);
      expect(d.accept(raw), isTrue);
    });

    test('cooldown window uses the injected clock', () {
      var t = DateTime(2026, 9, 8, 9, 41);
      final d = ScanDebouncer(
        window: const Duration(seconds: 2),
        clock: () => t,
      );
      d.accept('x');
      expect(d.inCooldown, isTrue);
      t = t.add(const Duration(seconds: 3));
      expect(d.inCooldown, isFalse);
    });
  });
}
