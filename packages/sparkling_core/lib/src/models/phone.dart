import 'package:phone_numbers_parser/metadata.dart' as meta;
import 'package:phone_numbers_parser/phone_numbers_parser.dart';

import 'countries.dart';

/// Mobile-number helpers on top of `phone_numbers_parser`. Numbers travel as
/// E.164 (`+27821234567`); the API validates them per country and rejects
/// anything that is not a mobile number with
/// [invalidMessage] (400 `validation_error`).
abstract final class Phone {
  /// The API's validation message for a bad mobile number — mirrored by the
  /// demo store so both paths surface the same text.
  static const String invalidMessage =
      'Enter the mobile number with its country code, e.g. +27 82 123 4567';

  /// Parses [raw] to E.164 (`+27821234567`) or `null` when it is not a valid
  /// mobile number anywhere.
  ///
  /// Accepts `+27 82 123 4567`, `0027 82…`, `27821234567` (digits with the
  /// country code), a bare local number for [defaultIso] (`082 123 4567`)
  /// and — as a last resort — digits that carry another country's code
  /// without a `+` (`447400123456`).
  static String? normalise(String? raw, {String defaultIso = defaultCountryIso}) {
    return parse(raw, defaultIso: defaultIso)?.international;
  }

  /// `true` when [raw] normalises to a valid mobile number.
  static bool isValid(String? raw, {String defaultIso = defaultCountryIso}) =>
      normalise(raw, defaultIso: defaultIso) != null;

  /// Digits only (`27821234567`) — the key used for duplicate detection.
  /// Falls back to the raw digits when the number does not parse so legacy
  /// rows still compare.
  static String key(String? raw, {String defaultIso = defaultCountryIso}) {
    if (raw == null) return '';
    final e164 = normalise(raw, defaultIso: defaultIso);
    return (e164 ?? raw).replaceAll(RegExp(r'[^0-9]'), '');
  }

  /// `'+27 82 123 4567'` for display. Unparseable input is returned trimmed.
  static String format(String? e164) {
    if (e164 == null) return '';
    final p = _parseAny(e164);
    if (p == null || p.nsn.isEmpty) return e164.trim();
    return '+${p.countryCode} ${_nsn(p)}';
  }

  /// National part grouped the way [format] groups it (`82 123 4567`), also
  /// for partial input (`82 12`) — used for live grouping while typing.
  static String formatNational(String iso, String nationalDigits) {
    final digits = nationalDigits.replaceAll(RegExp(r'[^0-9]'), '');
    if (digits.isEmpty) return '';
    final code = _iso(iso);
    if (code == null) return digits;
    try {
      return PhoneNumber(isoCode: code, nsn: digits)
          .formatNsn(format: NsnFormat.international);
    } catch (_) {
      return digits;
    }
  }

  /// The [Country] an E.164 number belongs to (`+44…` → United Kingdom /
  /// Guernsey / … as the number's range dictates), or `null`.
  static Country? countryOf(String? e164) {
    final p = _parseAny(e164);
    if (p == null) return null;
    return countryByIso(p.isoCode.name) ?? _mainCountryFor(p.countryCode);
  }

  /// Splits an E.164 number into its country and national digits
  /// (`+27821234567` → `(ZA, '821234567')`). `null` when unparseable.
  static (Country, String)? split(String? e164) {
    final p = _parseAny(e164);
    if (p == null || p.nsn.isEmpty) return null;
    final c = countryByIso(p.isoCode.name) ?? _mainCountryFor(p.countryCode);
    return c == null ? null : (c, p.nsn);
  }

  /// Placeholder national number for [iso] (`71 123 4567` for ZA) from the
  /// parser's example metadata, else a generic digits hint.
  static String exampleFor(String iso) {
    final code = _iso(iso);
    final example = code == null ? null : meta.metadataExamplesByIsoCode[code];
    final nsn = example?.mobile.isNotEmpty ?? false
        ? example!.mobile
        : (example?.fixedLine.isNotEmpty ?? false ? example!.fixedLine : null);
    if (nsn == null || code == null) return '12 345 6789';
    return formatNational(code.name, nsn);
  }

  /// National trunk prefix the user may type in front of a local number
  /// (`0` for ZA/GB/…, `1` for NANP, `null` when the plan has none).
  static String? nationalPrefixOf(String iso) {
    final code = _iso(iso);
    return code == null ? null : meta.metadataByIsoCode[code]?.nationalPrefix;
  }

  /// Longest valid national-number length for [iso] (used to cap input).
  static int maxNationalLength(String iso) {
    final code = _iso(iso);
    final lengths = code == null ? null : meta.metadataLenghtsByIsoCode[code];
    if (lengths == null) return 15;
    final all = [...lengths.mobile, ...lengths.general];
    return all.isEmpty ? 15 : all.reduce((a, b) => a > b ? a : b);
  }

  /// [countries] entry for an ISO 3166-1 alpha-2 code, or `null`.
  static Country? countryByIso(String? iso) {
    if (iso == null) return null;
    final u = iso.toUpperCase();
    for (final c in countries) {
      if (c.iso == u) return c;
    }
    return null;
  }

  /// Full parse (valid mobile numbers only) — see [normalise].
  static PhoneNumber? parse(String? raw, {String defaultIso = defaultCountryIso}) {
    if (raw == null) return null;
    final text = raw.trim();
    if (text.isEmpty) return null;
    final compact = text.replaceAll(RegExp(r'[^0-9+]'), '');
    if (compact.replaceAll('+', '').isEmpty) return null;
    final caller = _iso(defaultIso) ?? IsoCode.ZA;
    final international = compact.startsWith('+') || compact.startsWith('00');

    PhoneNumber? candidate;
    if (international) {
      candidate = _try(() => PhoneNumber.parse(text, callerCountry: caller));
    } else {
      candidate = _try(() => PhoneNumber.parse(text, destinationCountry: caller));
      if (!_mobile(candidate)) {
        // Digits carrying a foreign country code without `+`.
        final withPlus = _try(() => PhoneNumber.parse('+$compact'));
        if (_mobile(withPlus)) candidate = withPlus;
      }
    }
    if (_mobile(candidate)) return candidate;
    // Some plans (e.g. shared dial codes) validate under a sibling territory.
    if (candidate != null) {
      final sibling = _try(() => PhoneNumber.parse(candidate!.international));
      if (_mobile(sibling)) return sibling;
    }
    return null;
  }

  // ---------------------------------------------------------------------------

  static bool _mobile(PhoneNumber? p) =>
      p != null && p.nsn.isNotEmpty && p.isValid(type: PhoneNumberType.mobile);

  /// Lenient parse for display: any parseable number, mobile or not.
  static PhoneNumber? _parseAny(String? raw) {
    if (raw == null || raw.trim().isEmpty) return null;
    final compact = raw.replaceAll(RegExp(r'[^0-9+]'), '');
    if (compact.replaceAll('+', '').isEmpty) return null;
    final text = compact.startsWith('+') ? compact : '+$compact';
    return _try(() => PhoneNumber.parse(text));
  }

  static String _nsn(PhoneNumber p) {
    try {
      return p.formatNsn(format: NsnFormat.international);
    } catch (_) {
      return p.nsn;
    }
  }

  static Country? _mainCountryFor(String dial) {
    Country? first;
    for (final c in countries) {
      if (c.dial != dial) continue;
      first ??= c;
      final code = _iso(c.iso);
      if (code != null &&
          (meta.metadataByIsoCode[code]?.isMainCountryForDialCode ?? false)) {
        return c;
      }
    }
    return first;
  }

  static IsoCode? _iso(String iso) {
    final u = iso.trim().toUpperCase();
    for (final c in IsoCode.values) {
      if (c.name == u) return c;
    }
    return null;
  }

  static T? _try<T>(T Function() fn) {
    try {
      return fn();
    } catch (_) {
      return null;
    }
  }
}
