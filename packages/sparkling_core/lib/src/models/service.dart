import 'package:equatable/equatable.dart';

import 'enums.dart';
import 'json.dart';

/// `services` row.
class Service extends Equatable {
  const Service({
    required this.id,
    required this.code,
    required this.name,
    required this.category,
    this.description,
    this.durationMinutes = 30,
    this.basePriceCents = 0,
    this.isQuoteBased = false,
    this.pointsPerRand = 0.10,
    this.icon = 'local_car_wash',
    this.checklistTemplateId,
    this.isActive = true,
    this.sortOrder = 100,
  });

  final String id;
  final String code;
  final String name;
  final ServiceCategory category;
  final String? description;
  final int durationMinutes;
  final int basePriceCents;
  final bool isQuoteBased;
  final double pointsPerRand;

  /// Material Symbols glyph name.
  final String icon;
  final String? checklistTemplateId;
  final bool isActive;
  final int sortOrder;

  factory Service.fromJson(Json json) => Service(
    id: str(json['id']),
    code: str(json['code']),
    name: str(json['name']),
    category: ServiceCategory.fromDb(strOrNull(json['category'])),
    description: strOrNull(json['description']),
    durationMinutes: intOf(json['duration_minutes'], 30),
    basePriceCents: intOf(json['base_price_cents']),
    isQuoteBased: boolOf(json['is_quote_based']),
    pointsPerRand: dbl(json['points_per_rand'], 0.10),
    icon: str(json['icon'], 'local_car_wash'),
    checklistTemplateId: strOrNull(json['checklist_template_id']),
    isActive: boolOf(json['is_active'], true),
    sortOrder: intOf(json['sort_order'], 100),
  );

  Json toJson() => compact({
    'id': id,
    'code': code,
    'name': name,
    'category': category.db,
    'description': description,
    'duration_minutes': durationMinutes,
    'base_price_cents': basePriceCents,
    'is_quote_based': isQuoteBased,
    'points_per_rand': pointsPerRand,
    'icon': icon,
    'checklist_template_id': checklistTemplateId,
    'is_active': isActive,
    'sort_order': sortOrder,
  });

  Service copyWith({
    String? name,
    String? description,
    int? durationMinutes,
    int? basePriceCents,
    bool? isActive,
  }) => Service(
    id: id,
    code: code,
    name: name ?? this.name,
    category: category,
    description: description ?? this.description,
    durationMinutes: durationMinutes ?? this.durationMinutes,
    basePriceCents: basePriceCents ?? this.basePriceCents,
    isQuoteBased: isQuoteBased,
    pointsPerRand: pointsPerRand,
    icon: icon,
    checklistTemplateId: checklistTemplateId,
    isActive: isActive ?? this.isActive,
    sortOrder: sortOrder,
  );

  @override
  List<Object?> get props => [
    id,
    code,
    name,
    category,
    basePriceCents,
    durationMinutes,
    isActive,
  ];
}

/// `GET /outlets/:id/services` item: service + effective `price_cents` and
/// `points_estimate` for this outlet.
class OutletService extends Equatable {
  const OutletService({
    required this.outletId,
    required this.service,
    required this.priceCents,
    this.pointsEstimate = 0,
    this.isAvailable = true,
  });

  final String outletId;
  final Service service;

  /// Effective price for the outlet (override or base).
  final int priceCents;

  /// Points the customer would earn (CUS-062).
  final int pointsEstimate;
  final bool isAvailable;

  String get id => service.id;
  String get name => service.name;
  int get durationMinutes => service.durationMinutes;
  ServiceCategory get category => service.category;

  factory OutletService.fromJson(Json json) {
    // API may either nest `service` or flatten the service columns.
    final nested = asJsonOrNull(json['service']);
    final service = Service.fromJson(nested ?? json);
    return OutletService(
      outletId: str(json['outlet_id']),
      service: service,
      priceCents: intOf(json['price_cents'], service.basePriceCents),
      pointsEstimate: intOf(
        json['points_estimate'],
        (intOf(json['price_cents'], service.basePriceCents) /
                100 *
                service.pointsPerRand)
            .round(),
      ),
      isAvailable: boolOf(json['is_available'], true),
    );
  }

  Json toJson() => {
    'outlet_id': outletId,
    'service': service.toJson(),
    'service_id': service.id,
    'price_cents': priceCents,
    'points_estimate': pointsEstimate,
    'is_available': isAvailable,
  };

  OutletService copyWith({
    int? priceCents,
    int? pointsEstimate,
    bool? isAvailable,
  }) => OutletService(
    outletId: outletId,
    service: service,
    priceCents: priceCents ?? this.priceCents,
    pointsEstimate: pointsEstimate ?? this.pointsEstimate,
    isAvailable: isAvailable ?? this.isAvailable,
  );

  @override
  List<Object?> get props => [
    outletId,
    service,
    priceCents,
    pointsEstimate,
    isAvailable,
  ];
}
