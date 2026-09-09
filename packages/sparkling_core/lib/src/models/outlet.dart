import 'package:equatable/equatable.dart';

import 'json.dart';

/// `outlets` row. `distanceKm` is present when `GET /outlets?lat&lng`.
class Outlet extends Equatable {
  const Outlet({
    required this.id,
    required this.code,
    required this.name,
    this.addressLine,
    this.city,
    this.province,
    this.country = 'ZA',
    this.latitude,
    this.longitude,
    this.phone,
    this.email,
    this.timezone = 'Africa/Johannesburg',
    this.openingHours = const {},
    this.slotMinutes = 30,
    this.bayCount = 3,
    this.rating = 4.8,
    this.isActive = true,
    this.distanceKm,
  });

  final String id;
  final String code;
  final String name;
  final String? addressLine;
  final String? city;
  final String? province;
  final String country;
  final double? latitude;
  final double? longitude;
  final String? phone;
  final String? email;
  final String timezone;

  /// `{ "mon": ["07:30","17:30"], ..., "sun": null }`
  final Map<String, List<String>?> openingHours;
  final int slotMinutes;
  final int bayCount;
  final double rating;
  final bool isActive;
  final double? distanceKm;

  /// "14 Rivonia Rd, Sandton · Johannesburg"
  String get addressLabel =>
      [addressLine, city].where((s) => s != null && s.isNotEmpty).join(' · ');

  String? get distanceLabel =>
      distanceKm == null ? null : '${distanceKm!.toStringAsFixed(1)} km';

  /// Opening hours for a weekday (1 = Monday … 7 = Sunday) or null when closed.
  List<String>? hoursFor(int weekday) {
    const keys = ['mon', 'tue', 'wed', 'thu', 'fri', 'sat', 'sun'];
    return openingHours[keys[(weekday - 1).clamp(0, 6)]];
  }

  factory Outlet.fromJson(Json json) {
    final oh = asJsonOrNull(json['opening_hours']) ?? const {};
    return Outlet(
      id: str(json['id']),
      code: str(json['code']),
      name: str(json['name']),
      addressLine: strOrNull(json['address_line']),
      city: strOrNull(json['city']),
      province: strOrNull(json['province']),
      country: str(json['country'], 'ZA'),
      latitude: dblOrNull(json['latitude']),
      longitude: dblOrNull(json['longitude']),
      phone: strOrNull(json['phone']),
      email: strOrNull(json['email']),
      timezone: str(json['timezone'], 'Africa/Johannesburg'),
      openingHours: oh.map(
        (k, v) => MapEntry(k, v == null ? null : asStringList(v)),
      ),
      slotMinutes: intOf(json['slot_minutes'], 30),
      bayCount: intOf(json['bay_count'], 3),
      rating: dbl(json['rating'], 4.8),
      isActive: boolOf(json['is_active'], true),
      distanceKm: dblOrNull(json['distance_km']),
    );
  }

  Json toJson() => compact({
    'id': id,
    'code': code,
    'name': name,
    'address_line': addressLine,
    'city': city,
    'province': province,
    'country': country,
    'latitude': latitude,
    'longitude': longitude,
    'phone': phone,
    'email': email,
    'timezone': timezone,
    'opening_hours': openingHours,
    'slot_minutes': slotMinutes,
    'bay_count': bayCount,
    'rating': rating,
    'is_active': isActive,
    'distance_km': distanceKm,
  });

  Outlet copyWith({
    String? name,
    double? rating,
    int? bayCount,
    bool? isActive,
    double? distanceKm,
  }) => Outlet(
    id: id,
    code: code,
    name: name ?? this.name,
    addressLine: addressLine,
    city: city,
    province: province,
    country: country,
    latitude: latitude,
    longitude: longitude,
    phone: phone,
    email: email,
    timezone: timezone,
    openingHours: openingHours,
    slotMinutes: slotMinutes,
    bayCount: bayCount ?? this.bayCount,
    rating: rating ?? this.rating,
    isActive: isActive ?? this.isActive,
    distanceKm: distanceKm ?? this.distanceKm,
  );

  @override
  List<Object?> get props => [
    id,
    code,
    name,
    rating,
    bayCount,
    isActive,
    distanceKm,
  ];
}
