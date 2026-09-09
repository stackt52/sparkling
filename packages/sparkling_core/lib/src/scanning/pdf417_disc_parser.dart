import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:equatable/equatable.dart';

import '../models/enums.dart';
import '../models/vehicle.dart';

/// Thrown when a scanned payload is not a usable licence disc (CUS-012,
/// BAR-006). [message] is user-facing; [reason] is a stable code.
class DiscParseException implements Exception {
  const DiscParseException(this.reason, this.message);
  final String reason;
  final String message;

  @override
  String toString() => 'DiscParseException($reason): $message';
}

/// Parsed South African vehicle licence disc.
class DiscScanResult extends Equatable {
  const DiscScanResult({
    required this.registrationNo,
    required this.rawHash,
    this.vin,
    this.engineNo,
    this.make,
    this.model,
    this.colour,
    this.description,
    this.licenceNo,
    this.discExpiry,
    this.vehicleRegisterNo,
  });

  /// Upper-cased, whitespace-collapsed as printed on the disc (e.g. `KL45MNGP`).
  final String registrationNo;
  final String? vin;
  final String? engineNo;
  final String? make;
  final String? model;
  final String? colour;

  /// e.g. "Sedan (closed top)"
  final String? description;

  /// Licence disc number.
  final String? licenceNo;
  final DateTime? discExpiry;
  final String? vehicleRegisterNo;

  /// sha256 hex of the raw payload — stored instead of the payload (BAR-004).
  final String rawHash;

  /// GP-style spacing for display: `KL45MNGP` → `KL 45 MN GP`.
  String get registrationNoFormatted =>
      Pdf417DiscParser.formatRegistration(registrationNo);

  bool get isExpired =>
      discExpiry != null && discExpiry!.isBefore(DateTime.now());

  /// Converts to the `POST /vehicles` body with `source: scan`.
  VehicleInput toVehicleInput({bool force = false}) => VehicleInput(
    registrationNo: registrationNoFormatted,
    vin: vin,
    engineNo: engineNo,
    make: make,
    model: model,
    colour: colour,
    licenceNo: licenceNo,
    discExpiry: discExpiry,
    source: VehicleSource.scan,
    discHash: rawHash,
    force: force,
  );

  Map<String, dynamic> toJson() => {
    'registration_no': registrationNo,
    'vin': vin,
    'engine_no': engineNo,
    'make': make,
    'model': model,
    'colour': colour,
    'description': description,
    'licence_no': licenceNo,
    'disc_expiry': discExpiry?.toIso8601String().substring(0, 10),
    'vehicle_register_no': vehicleRegisterNo,
    'raw_hash': rawHash,
  };

  @override
  List<Object?> get props => [
    registrationNo,
    vin,
    engineNo,
    make,
    model,
    colour,
    description,
    licenceNo,
    discExpiry,
    vehicleRegisterNo,
    rawHash,
  ];
}

/// Parser for the PDF417 barcode printed on South African vehicle licence
/// discs (STF-013, INT-005 — decoding happens on-device).
///
/// **Documented assumption (SRS §15 — schema to be confirmed):** the payload is
/// `%`-delimited. After `split('%')` (leading `%` gives an empty index 0):
///
/// | idx | field |
/// |---|---|
/// | 1 | control / version (e.g. `MVL1CC52`) |
/// | 2 | form id |
/// | 3, 4 | internal |
/// | 5 | licence disc number |
/// | 6 | registration number |
/// | 7 | vehicle register number |
/// | 8 | description (e.g. `Sedan (closed top)`) |
/// | 9 | make |
/// | 10 | model |
/// | 11 | colour |
/// | 12 | VIN |
/// | 13 | engine number |
/// | 14 | expiry date `yyyy-MM-dd` |
///
/// Validation: ≥ 15 segments, registration matches `^[A-Z0-9 ]{2,12}$`
/// (upper-cased), VIN (when present) is 17 alphanumerics without I/O/Q, expiry
/// parseable. Anything else throws [DiscParseException].
abstract final class Pdf417DiscParser {
  static const int minSegments = 15;
  static const int idxLicence = 5;
  static const int idxRegistration = 6;
  static const int idxVehicleRegister = 7;
  static const int idxDescription = 8;
  static const int idxMake = 9;
  static const int idxModel = 10;
  static const int idxColour = 11;
  static const int idxVin = 12;
  static const int idxEngine = 13;
  static const int idxExpiry = 14;

  static final RegExp _regNo = RegExp(r'^[A-Z0-9 ]{2,12}$');
  static final RegExp _vin = RegExp(r'^[A-HJ-NPR-Z0-9]{17}$');
  static final RegExp _gpPlate = RegExp(
    r'^([A-Z]{2})(\d{2})([A-Z]{2})(GP|MP|L|NW|FS|NC|EC|WC|ZN)$',
  );

  /// Quick structural check before attempting a full parse (used to ignore
  /// other barcodes in the camera frame).
  static bool looksLikeDisc(String raw) {
    final segments = _segments(raw);
    if (segments.length < minSegments) return false;
    final reg = _normaliseReg(segments[idxRegistration]);
    return _regNo.hasMatch(reg);
  }

  /// Parses [raw] or throws [DiscParseException].
  static DiscScanResult parse(String raw) {
    final trimmed = raw.trim();
    if (trimmed.isEmpty) {
      throw const DiscParseException(
        'empty',
        'Nothing was decoded. Hold the disc steady inside the frame.',
      );
    }
    final segments = _segments(trimmed);
    if (segments.length < minSegments) {
      throw const DiscParseException(
        'malformed',
        "That barcode isn't a vehicle licence disc. Try scanning the disc on the windscreen.",
      );
    }

    final registration = _normaliseReg(segments[idxRegistration]);
    if (!_regNo.hasMatch(registration)) {
      throw const DiscParseException(
        'registration',
        "Couldn't read the registration number. Clean the disc and try again, or enter details manually.",
      );
    }

    final vinRaw = _clean(segments[idxVin])?.toUpperCase().replaceAll(' ', '');
    String? vin;
    if (vinRaw != null && vinRaw.isNotEmpty) {
      if (!_vin.hasMatch(vinRaw)) {
        throw const DiscParseException(
          'vin',
          'The VIN on this disc is invalid. Rescan or enter the vehicle manually.',
        );
      }
      vin = vinRaw;
    }

    final expiryRaw = _clean(segments[idxExpiry]);
    DateTime? expiry;
    if (expiryRaw != null && expiryRaw.isNotEmpty) {
      expiry = _parseDate(expiryRaw);
      if (expiry == null) {
        throw const DiscParseException(
          'expiry',
          "Couldn't read the disc expiry date. Rescan or enter details manually.",
        );
      }
    }

    return DiscScanResult(
      registrationNo: registration,
      vin: vin,
      engineNo: _clean(segments[idxEngine])?.toUpperCase(),
      make: _titleCase(_clean(segments[idxMake])),
      model: _titleCase(_clean(segments[idxModel])),
      colour: _titleCase(_clean(segments[idxColour])),
      description: _clean(segments[idxDescription]),
      licenceNo: _clean(segments[idxLicence])?.toUpperCase(),
      discExpiry: expiry,
      vehicleRegisterNo: _clean(segments[idxVehicleRegister])?.toUpperCase(),
      rawHash: hash(trimmed),
    );
  }

  /// Non-throwing variant.
  static DiscScanResult? tryParse(String raw) {
    try {
      return parse(raw);
    } on DiscParseException {
      return null;
    }
  }

  /// sha256 hex of the raw payload (BAR-004).
  static String hash(String raw) => sha256.convert(utf8.encode(raw)).toString();

  /// `KL45MNGP` → `KL 45 MN GP`; other formats returned unchanged.
  static String formatRegistration(String reg) {
    final compact = reg.toUpperCase().replaceAll(RegExp(r'\s+'), '');
    final m = _gpPlate.firstMatch(compact);
    if (m == null) {
      return reg.toUpperCase().replaceAll(RegExp(r'\s+'), ' ').trim();
    }
    return '${m[1]} ${m[2]} ${m[3]} ${m[4]}';
  }

  /// Representative fixture (fictional vehicle) for tests and demo mode.
  static String sampleDiscPayload({
    String registration = 'KL45MNGP',
    String vin = 'AHTFB3CB301234567',
    String make = 'TOYOTA',
    String model = 'COROLLA CROSS',
    String colour = 'Celestite Grey',
    String expiry = '2027-03-31',
    String licence = 'ABC123456',
  }) =>
      '%MVL1CC52%0002%2025%1%$licence%$registration%AAB123X%Sedan (closed top)%$make%$model%$colour%$vin%2ZR1234567%$expiry%';

  // ---- helpers ---------------------------------------------------------------

  static List<String> _segments(String raw) {
    final s = raw.startsWith('%') ? raw : '%$raw';
    return s.split('%');
  }

  static String _normaliseReg(String s) => s
      .trim()
      .toUpperCase()
      .replaceAll(RegExp(r'[^A-Z0-9 ]'), '')
      .replaceAll(RegExp(r'\s+'), ' ');

  static String? _clean(String s) {
    final t = s.trim();
    return t.isEmpty ? null : t;
  }

  static String? _titleCase(String? s) {
    if (s == null) return null;
    return s
        .split(RegExp(r'\s+'))
        .map((w) {
          if (w.isEmpty) return w;
          if (w.length <= 3 &&
              w == w.toUpperCase() &&
              RegExp(r'^[A-Z]+$').hasMatch(w)) {
            return w; // BMW, VW, GP
          }
          return w[0].toUpperCase() + w.substring(1).toLowerCase();
        })
        .join(' ');
  }

  static DateTime? _parseDate(String s) {
    final iso = DateTime.tryParse(s);
    if (iso != null) return DateTime(iso.year, iso.month, iso.day);
    final m = RegExp(r'^(\d{4})(\d{2})(\d{2})$').firstMatch(s);
    if (m != null) {
      return DateTime(int.parse(m[1]!), int.parse(m[2]!), int.parse(m[3]!));
    }
    final dmy = RegExp(r'^(\d{2})[/-](\d{2})[/-](\d{4})$').firstMatch(s);
    if (dmy != null) {
      return DateTime(
        int.parse(dmy[3]!),
        int.parse(dmy[2]!),
        int.parse(dmy[1]!),
      );
    }
    return null;
  }
}

/// Ensures only one scan result is emitted per scan session (BAR-010): the
/// camera keeps delivering frames of the same barcode, so the first accepted
/// payload wins until [reset] is called. Also suppresses rapid re-reads of a
/// different payload inside [window].
class ScanDebouncer {
  ScanDebouncer({
    this.window = const Duration(milliseconds: 1500),
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now;

  final Duration window;
  final DateTime Function() _clock;
  String? _acceptedHash;
  DateTime? _acceptedAt;

  /// `true` once a payload has been accepted in this session.
  bool get hasResult => _acceptedHash != null;
  String? get acceptedHash => _acceptedHash;

  /// Returns `true` exactly once per session — for the first payload — and
  /// `false` for everything after until [reset].
  bool accept(String raw) {
    if (_acceptedHash != null) return false;
    _acceptedHash = Pdf417DiscParser.hash(raw);
    _acceptedAt = _clock();
    return true;
  }

  /// `true` when [raw] is the same payload already accepted.
  bool isDuplicate(String raw) =>
      _acceptedHash != null && Pdf417DiscParser.hash(raw) == _acceptedHash;

  /// `true` while inside [window] since the accepted scan.
  bool get inCooldown =>
      _acceptedAt != null && _clock().difference(_acceptedAt!) < window;

  /// Start a new scan session (e.g. user tapped "Retry scan").
  void reset() {
    _acceptedHash = null;
    _acceptedAt = null;
  }
}
