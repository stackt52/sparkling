import 'package:equatable/equatable.dart';

import 'enums.dart';
import 'json.dart';

/// `vehicles` row.
class Vehicle extends Equatable {
  const Vehicle({
    required this.id,
    required this.customerId,
    required this.registrationNo,
    this.vin,
    this.engineNo,
    this.make,
    this.model,
    this.colour,
    this.year,
    this.licenceNo,
    this.discExpiry,
    this.source = VehicleSource.manual,
    this.discVerified = false,
    this.discHash,
    this.isActive = true,
    this.createdAt,
    this.updatedAt,
  });

  final String id;
  final String customerId;
  final String registrationNo;
  final String? vin;
  final String? engineNo;
  final String? make;
  final String? model;
  final String? colour;
  final int? year;
  final String? licenceNo;
  final DateTime? discExpiry;
  final VehicleSource source;
  final bool discVerified;

  /// sha256 of the raw disc payload (BAR-004: raw never stored).
  final String? discHash;
  final bool isActive;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  /// "Toyota Corolla Cross"
  String get displayName =>
      [make, model].where((s) => s != null && s.isNotEmpty).join(' ');

  /// "Corolla Cross" when a model exists, otherwise the registration.
  String get shortName =>
      (model?.isNotEmpty ?? false) ? model! : (make ?? registrationNo);

  /// VIN masked for display (`•••• 4567`) — CUS-013 non-editable field.
  String? get maskedVin => vin == null || vin!.length < 4
      ? vin
      : '•••• ${vin!.substring(vin!.length - 4)}';

  bool get discExpiringSoon =>
      discExpiry != null && discExpiry!.difference(DateTime.now()).inDays <= 60;

  bool get discExpired =>
      discExpiry != null && discExpiry!.isBefore(DateTime.now());

  /// Normalised plate for duplicate checks (matches the SQL unique index).
  String get normalisedRegistration => normaliseRegistration(registrationNo);

  static String normaliseRegistration(String reg) =>
      reg.toUpperCase().replaceAll(RegExp(r'[^A-Z0-9]'), '');

  factory Vehicle.fromJson(Json json) => Vehicle(
    id: str(json['id']),
    customerId: str(json['customer_id']),
    registrationNo: str(json['registration_no']),
    vin: strOrNull(json['vin']),
    engineNo: strOrNull(json['engine_no']),
    make: strOrNull(json['make']),
    model: strOrNull(json['model']),
    colour: strOrNull(json['colour']),
    year: intOrNull(json['year']),
    licenceNo: strOrNull(json['licence_no']),
    discExpiry: dtOrNull(json['disc_expiry']),
    source: VehicleSource.fromDb(strOrNull(json['source'])),
    discVerified: boolOf(json['disc_verified']),
    discHash: strOrNull(json['disc_hash']),
    isActive: boolOf(json['is_active'], true),
    createdAt: dtOrNull(json['created_at']),
    updatedAt: dtOrNull(json['updated_at']),
  );

  Json toJson() => compact({
    'id': id,
    'customer_id': customerId,
    'registration_no': registrationNo,
    'vin': vin,
    'engine_no': engineNo,
    'make': make,
    'model': model,
    'colour': colour,
    'year': year,
    'licence_no': licenceNo,
    'disc_expiry': isoDate(discExpiry),
    'source': source.db,
    'disc_verified': discVerified,
    'disc_hash': discHash,
    'is_active': isActive,
    'created_at': iso(createdAt),
    'updated_at': iso(updatedAt),
  });

  Vehicle copyWith({
    String? registrationNo,
    String? vin,
    String? engineNo,
    String? make,
    String? model,
    String? colour,
    int? year,
    String? licenceNo,
    DateTime? discExpiry,
    VehicleSource? source,
    bool? discVerified,
    String? discHash,
    bool? isActive,
    DateTime? updatedAt,
  }) => Vehicle(
    id: id,
    customerId: customerId,
    registrationNo: registrationNo ?? this.registrationNo,
    vin: vin ?? this.vin,
    engineNo: engineNo ?? this.engineNo,
    make: make ?? this.make,
    model: model ?? this.model,
    colour: colour ?? this.colour,
    year: year ?? this.year,
    licenceNo: licenceNo ?? this.licenceNo,
    discExpiry: discExpiry ?? this.discExpiry,
    source: source ?? this.source,
    discVerified: discVerified ?? this.discVerified,
    discHash: discHash ?? this.discHash,
    isActive: isActive ?? this.isActive,
    createdAt: createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
  );

  @override
  List<Object?> get props => [
    id,
    customerId,
    registrationNo,
    vin,
    make,
    model,
    colour,
    year,
    discExpiry,
    source,
    discVerified,
    isActive,
  ];
}

/// Body for `POST /vehicles` / `PATCH /vehicles/:id`.
class VehicleInput {
  const VehicleInput({
    required this.registrationNo,
    this.vin,
    this.engineNo,
    this.make,
    this.model,
    this.colour,
    this.year,
    this.licenceNo,
    this.discExpiry,
    this.source = VehicleSource.manual,
    this.discHash,
    this.force = false,
  });

  final String registrationNo;
  final String? vin;
  final String? engineNo;
  final String? make;
  final String? model;
  final String? colour;
  final int? year;
  final String? licenceNo;
  final DateTime? discExpiry;
  final VehicleSource source;
  final String? discHash;

  /// Override the duplicate check (CUS-015) after the user confirmed.
  final bool force;

  Json toJson() => compact({
    'registration_no': registrationNo,
    'vin': vin,
    'engine_no': engineNo,
    'make': make,
    'model': model,
    'colour': colour,
    'year': year,
    'licence_no': licenceNo,
    'disc_expiry': isoDate(discExpiry),
    'source': source.db,
    'disc_hash': discHash,
    'force': force ? true : null,
  });

  VehicleInput copyWith({
    bool? force,
    String? registrationNo,
    String? make,
    String? model,
    String? colour,
    int? year,
  }) => VehicleInput(
    registrationNo: registrationNo ?? this.registrationNo,
    vin: vin,
    engineNo: engineNo,
    make: make ?? this.make,
    model: model ?? this.model,
    colour: colour ?? this.colour,
    year: year ?? this.year,
    licenceNo: licenceNo,
    discExpiry: discExpiry,
    source: source,
    discHash: discHash,
    force: force ?? this.force,
  );
}
