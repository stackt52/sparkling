import 'package:flutter_test/flutter_test.dart';
import 'package:sparkling_core/sparkling_core.dart';

/// [Phone] — E.164 normalisation, validation and display for any country.
void main() {
  group('Phone.normalise', () {
    test('bare South African local numbers default to +27', () {
      expect(Phone.normalise('082 123 4567'), '+27821234567');
      expect(Phone.normalise('0821234567'), '+27821234567');
      expect(Phone.normalise('82 123 4567'), '+27821234567');
      expect(Phone.normalise('(082) 123-4567'), '+27821234567');
    });

    test('accepts +, 00 and digits with the country code', () {
      expect(Phone.normalise('+27 82 123 4567'), '+27821234567');
      expect(Phone.normalise('0027 82 123 4567'), '+27821234567');
      expect(Phone.normalise('27821234567'), '+27821234567');
      expect(Phone.normalise('00 44 7400 123456'), '+447400123456');
      expect(Phone.normalise('447400123456'), '+447400123456');
    });

    test('other countries: UK, US, Zimbabwe', () {
      expect(Phone.normalise('+44 7400 123456'), '+447400123456');
      expect(Phone.normalise('+44 7911 123456'), '+447911123456');
      expect(Phone.normalise('07400 123456', defaultIso: 'GB'), '+447400123456');
      expect(Phone.normalise('+1 202 555 0143'), '+12025550143');
      expect(Phone.normalise('(202) 555-0143', defaultIso: 'US'), '+12025550143');
      expect(Phone.normalise('+263 71 234 5678'), '+263712345678');
      expect(Phone.normalise('071 234 5678', defaultIso: 'ZW'), '+263712345678');
    });

    test('invalid input → null', () {
      expect(Phone.normalise(null), isNull);
      expect(Phone.normalise(''), isNull);
      expect(Phone.normalise('   '), isNull);
      expect(Phone.normalise('abc'), isNull);
      expect(Phone.normalise('12345'), isNull);
      expect(Phone.normalise('+999 123 4567'), isNull);
      // A landline is not a mobile number.
      expect(Phone.normalise('+27 12 345 6789'), isNull);
      expect(Phone.normalise('012 345 6789'), isNull);
      // Too many digits for a ZA mobile.
      expect(Phone.normalise('082 123 45678'), isNull);
    });

    test('isValid mirrors normalise', () {
      expect(Phone.isValid('082 123 4567'), isTrue);
      expect(Phone.isValid('+44 7400 123456'), isTrue);
      expect(Phone.isValid('12345'), isFalse);
      expect(Phone.isValid(null), isFalse);
    });
  });

  group('Phone.format', () {
    test('groups E.164 for display', () {
      expect(Phone.format('+27821234567'), '+27 82 123 4567');
      expect(Phone.format('+447911123456'), '+44 7911 123456');
      expect(Phone.format('+447400123456'), '+44 7400 123456');
      expect(Phone.format('+12025550143'), '+1 202-555-0143');
      expect(Phone.format('+263712345678'), '+263 71 234 5678');
      // Seed rows stored with spaces still format.
      expect(Phone.format('+27 83 111 2222'), '+27 83 111 2222');
    });

    test('passes through what it cannot parse', () {
      expect(Phone.format(null), '');
      expect(Phone.format(''), '');
      expect(Phone.format('n/a'), 'n/a');
    });

    test('formatNational groups partial input while typing', () {
      expect(Phone.formatNational('ZA', '8'), '8');
      expect(Phone.formatNational('ZA', '8212'), '82 12');
      expect(Phone.formatNational('ZA', '821234567'), '82 123 4567');
      expect(Phone.formatNational('GB', '7400123'), '7400 123');
      expect(Phone.formatNational('ZA', ''), '');
    });
  });

  group('Phone.countryOf / split', () {
    test('resolves the country of an E.164 number', () {
      expect(Phone.countryOf('+27821234567')?.iso, 'ZA');
      expect(Phone.countryOf('+447400123456')?.iso, 'GB');
      expect(Phone.countryOf('+12025550143')?.iso, 'US');
      expect(Phone.countryOf('+14165550199')?.iso, 'CA');
      expect(Phone.countryOf('+263712345678')?.iso, 'ZW');
      expect(Phone.countryOf('garbage'), isNull);
      expect(Phone.countryOf(null), isNull);
    });

    test('split returns country + national digits', () {
      final (c, nsn) = Phone.split('+27821234567')!;
      expect(c.iso, 'ZA');
      expect(c.dial, '27');
      expect(c.flag, '🇿🇦');
      expect(nsn, '821234567');
      final (uk, ukNsn) = Phone.split('+44 7400 123456')!;
      expect(uk.name, 'United Kingdom');
      expect(ukNsn, '7400123456');
      expect(Phone.split(''), isNull);
    });
  });

  group('Phone metadata helpers', () {
    test('exampleFor derives a placeholder from the parser examples', () {
      expect(Phone.exampleFor('ZA'), '71 123 4567');
      expect(Phone.exampleFor('GB'), '7400 123456');
      expect(Phone.exampleFor('ZW'), '71 234 5678');
      expect(Phone.exampleFor('??'), '12 345 6789');
    });

    test('nationalPrefixOf / maxNationalLength', () {
      expect(Phone.nationalPrefixOf('ZA'), '0');
      expect(Phone.nationalPrefixOf('GB'), '0');
      expect(Phone.nationalPrefixOf('US'), '1');
      expect(Phone.maxNationalLength('ZA'), 9);
      expect(Phone.maxNationalLength('GB'), greaterThanOrEqualTo(10));
      expect(Phone.maxNationalLength('??'), 15);
    });

    test('every picker country is known to the parser', () {
      for (final c in countries) {
        expect(
          Phone.exampleFor(c.iso),
          isNot('12 345 6789'),
          reason: '${c.iso} has no example number',
        );
      }
      expect(Phone.countryByIso('za')?.name, 'South Africa');
      expect(Phone.countryByIso('XX'), isNull);
      expect(defaultCountryIso, 'ZA');
    });

    test('key strips to digits for duplicate detection', () {
      expect(Phone.key('+27 83 111 2222'), '27831112222');
      expect(Phone.key('083 111 2222'), '27831112222');
      expect(Phone.key('+44 7911 123456'), '447911123456');
      expect(Phone.key(null), '');
      expect(Phone.key('n/a 123'), '123');
    });
  });

  group('CustomerInput delegates to Phone', () {
    test('normalisePhone / phoneKey', () {
      expect(CustomerInput.normalisePhone('072 555 0199'), '+27725550199');
      expect(CustomerInput.normalisePhone('+44 7400 123456'), '+447400123456');
      expect(CustomerInput.normalisePhone(' 12345 '), '12345');
      expect(CustomerInput.phoneKey('+27 83 111 2222'), '27831112222');
    });
  });
}
