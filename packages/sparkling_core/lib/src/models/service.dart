import 'package:equatable/equatable.dart';

import 'enums.dart';
import 'json.dart';
import 'money.dart';

/// `vehicles.size_class` — drives the small / large price on a catalogue
/// offer (migration 0008). `null` in the database means [small].
enum VehicleSize implements SparklingEnum {
  small('small'),
  large('large'),
  bike('bike');

  const VehicleSize(this.db);
  @override
  final String db;

  static VehicleSize fromDb(String? v) =>
      values.where((s) => s.db == v).firstOrNull ?? small;

  String get label => switch (this) {
    small => 'Small',
    large => 'Large',
    bike => 'Bike',
  };

  /// Examples shown under the size selector.
  String get hint => switch (this) {
    small => 'Hatch, sedan, coupé',
    large => 'SUV, bakkie, station wagon, bus',
    bike => 'Motorcycle',
  };

  /// Maps the licence-disc vehicle description (e.g. `Sedan (closed top)`,
  /// `Station wagon`, `LDV / Bakkie`) to a size. Unknown → [small].
  static VehicleSize fromDiscDescription(String? description) {
    if (description == null) return small;
    final d = description.toLowerCase();
    if (d.contains('motor cycle') ||
        d.contains('motorcycle') ||
        d.contains('scooter') ||
        d.contains('quad')) {
      return bike;
    }
    const large_ = [
      'station wagon',
      'stationwagon',
      'suv',
      'sports utility',
      'pick-up',
      'pick up',
      'pickup',
      'bakkie',
      'ldv',
      'light delivery',
      'bus',
      'mpv',
      'multi purpose',
      'multi-purpose',
      'van',
      'panel van',
      'minibus',
      'double cab',
      'truck',
    ];
    for (final k in large_) {
      if (d.contains(k)) return large;
    }
    return small;
  }
}

/// `services.pricing_mode` / `outlet_services.pricing_mode`.
enum PricingMode implements SparklingEnum {
  from('from'),
  fixed('fixed'),
  byQuote('by_quote');

  const PricingMode(this.db);
  @override
  final String db;

  static PricingMode fromDb(String? v) =>
      values.where((m) => m.db == v).firstOrNull ?? from;
}

/// `services.vat_mode`: `incl` prices are final, `excl` prices get 15 % VAT
/// added on the booking / quotation total.
enum VatMode implements SparklingEnum {
  incl('incl'),
  excl('excl');

  const VatMode(this.db);
  @override
  final String db;

  static VatMode fromDb(String? v) =>
      values.where((m) => m.db == v).firstOrNull ?? incl;

  /// VAT rate applied on `excl` totals (South Africa, 15 %).
  static const int vatPct = 15;

  /// VAT in cents on [cents] for this mode (0 for [incl]).
  int vatOn(int cents) =>
      this == excl ? (cents * vatPct / 100).round() : 0;
}

/// `{ service_id, code, name }` — a composite's component.
class ServiceRef extends Equatable {
  const ServiceRef({required this.serviceId, required this.code, required this.name});
  final String serviceId;
  final String code;
  final String name;

  factory ServiceRef.fromJson(Json json) => ServiceRef(
    serviceId: str(json['service_id'] ?? json['id']),
    code: str(json['code']),
    name: str(json['name']),
  );
  Json toJson() => {'service_id': serviceId, 'code': code, 'name': name};

  @override
  List<Object?> get props => [serviceId, code, name];
}

/// Canonical `services` row.
class Service extends Equatable {
  const Service({
    required this.id,
    required this.code,
    required this.name,
    required this.category,
    this.description,
    this.groupName = ServiceGroups.carWashOptions,
    this.durationMinutes = 30,
    this.basePriceCents = 0,
    this.isQuoteBased = false,
    this.pricingMode = PricingMode.from,
    this.vatMode = VatMode.incl,
    this.priceSmallCents,
    this.priceLargeCents,
    this.priceGeneralCents,
    this.isAddon = false,
    this.addonGroupName,
    this.notes,
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

  /// `Car Wash Options` | `Combinations` | `Auto Body Repair`.
  final String groupName;
  final int durationMinutes;

  /// Legacy single price (kept in step with the small / general price).
  final int basePriceCents;
  final bool isQuoteBased;
  final PricingMode pricingMode;
  final VatMode vatMode;
  final int? priceSmallCents;
  final int? priceLargeCents;
  final int? priceGeneralCents;

  /// "Add to any Combo" items attach to a booking of a service in
  /// [addonGroupName].
  final bool isAddon;
  final String? addonGroupName;
  final String? notes;
  final double pointsPerRand;

  /// Material Symbols glyph name.
  final String icon;
  final String? checklistTemplateId;
  final bool isActive;
  final int sortOrder;

  bool get isByQuote => pricingMode == PricingMode.byQuote || isQuoteBased;

  factory Service.fromJson(Json json) {
    final mode = PricingMode.fromDb(
      strOrNull(json['pricing_mode']) ??
          (boolOf(json['is_quote_based']) ? 'by_quote' : null),
    );
    return Service(
      id: str(json['id']),
      code: str(json['code']),
      name: str(json['name']),
      category: ServiceCategory.fromDb(strOrNull(json['category'])),
      description: strOrNull(json['description']),
      groupName: str(json['group_name'], ServiceGroups.carWashOptions),
      durationMinutes: intOf(json['duration_minutes'], 30),
      basePriceCents: intOf(
        json['base_price_cents'],
        intOf(json['price_small_cents'], intOf(json['price_general_cents'])),
      ),
      isQuoteBased: boolOf(json['is_quote_based'], mode == PricingMode.byQuote),
      pricingMode: mode,
      vatMode: VatMode.fromDb(strOrNull(json['vat_mode'])),
      priceSmallCents: intOrNull(json['price_small_cents']),
      priceLargeCents: intOrNull(json['price_large_cents']),
      priceGeneralCents: intOrNull(json['price_general_cents']),
      isAddon: boolOf(json['is_addon']),
      addonGroupName: strOrNull(json['addon_group_name']),
      notes: strOrNull(json['notes']),
      pointsPerRand: dbl(json['points_per_rand'], 0.10),
      icon: str(json['icon'], 'local_car_wash'),
      checklistTemplateId: strOrNull(json['checklist_template_id']),
      isActive: boolOf(json['is_active'], true),
      sortOrder: intOf(json['sort_order'], 100),
    );
  }

  Json toJson() => compact({
    'id': id,
    'code': code,
    'name': name,
    'category': category.db,
    'description': description,
    'group_name': groupName,
    'duration_minutes': durationMinutes,
    'base_price_cents': basePriceCents,
    'is_quote_based': isQuoteBased,
    'pricing_mode': pricingMode.db,
    'vat_mode': vatMode.db,
    'price_small_cents': priceSmallCents,
    'price_large_cents': priceLargeCents,
    'price_general_cents': priceGeneralCents,
    'is_addon': isAddon,
    'addon_group_name': addonGroupName,
    'notes': notes,
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
    groupName: groupName,
    durationMinutes: durationMinutes ?? this.durationMinutes,
    basePriceCents: basePriceCents ?? this.basePriceCents,
    isQuoteBased: isQuoteBased,
    pricingMode: pricingMode,
    vatMode: vatMode,
    priceSmallCents: priceSmallCents,
    priceLargeCents: priceLargeCents,
    priceGeneralCents: priceGeneralCents,
    isAddon: isAddon,
    addonGroupName: addonGroupName,
    notes: notes,
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
    groupName,
    pricingMode,
    vatMode,
    basePriceCents,
    priceSmallCents,
    priceLargeCents,
    priceGeneralCents,
    durationMinutes,
    isAddon,
    isActive,
  ];
}

/// The three catalogue groups (`services.group_name`).
abstract final class ServiceGroups {
  static const String carWashOptions = 'Car Wash Options';
  static const String combinations = 'Combinations';
  static const String autoBodyRepair = 'Auto Body Repair';
  static const List<String> all = [carWashOptions, combinations, autoBodyRepair];

  static int order(String group) {
    final i = all.indexOf(group);
    return i < 0 ? all.length : i;
  }
}

/// One offer from `GET /outlets/:id/services` — the outlet's wording and
/// prices for a canonical service, with composition and add-on metadata
/// (docs/API.md "Catalogue pricing model").
class OutletService extends Equatable {
  const OutletService({
    required this.outletId,
    required this.serviceId,
    required this.code,
    required this.name,
    required this.category,
    this.description,
    this.groupName = ServiceGroups.carWashOptions,
    this.durationMinutes = 30,
    this.icon = 'local_car_wash',
    this.pricingMode = PricingMode.from,
    this.vatMode = VatMode.incl,
    this.priceSmallCents,
    this.priceLargeCents,
    this.priceGeneralCents,
    this.priceCents,
    this.pricedFor,
    this.isAddon = false,
    this.addonGroupName,
    this.includes = const [],
    this.includedIn = const [],
    this.isAvailable = true,
    this.sortOrder = 100,
    this.notes,
    this.pointsEstimate = 0,
    this.pointsPerRand = 0.10,
    this.checklistTemplateId,
  });

  final String outletId;
  final String serviceId;
  final String code;

  /// `display_name ?? services.name`.
  final String name;
  final ServiceCategory category;
  final String? description;
  final String groupName;
  final int durationMinutes;
  final String icon;
  final PricingMode pricingMode;
  final VatMode vatMode;
  final int? priceSmallCents;
  final int? priceLargeCents;

  /// Size-independent price (auto body).
  final int? priceGeneralCents;

  /// Price resolved for [pricedFor] when the catalogue was requested with
  /// `?vehicle_size` (null for by-quote offers).
  final int? priceCents;
  final VehicleSize? pricedFor;
  final bool isAddon;
  final String? addonGroupName;

  /// Direct components of a composite offer (resolved per outlet).
  final List<ServiceRef> includes;

  /// Ids of composites at this outlet that include this service.
  final List<String> includedIn;
  final bool isAvailable;
  final int sortOrder;
  final String? notes;

  /// Points the customer would earn on the from-price (CUS-062).
  final int pointsEstimate;
  final double pointsPerRand;
  final String? checklistTemplateId;

  String get id => serviceId;
  bool get isByQuote => pricingMode == PricingMode.byQuote;
  bool get isComposite => includes.isNotEmpty;
  bool get isExclVat => vatMode == VatMode.excl;

  /// Lowest non-null price — what "From R x" shows before a size is known.
  int? get priceFromCents {
    final prices = [
      priceSmallCents,
      priceLargeCents,
      priceGeneralCents,
    ].whereType<int>().toList();
    if (isByQuote || prices.isEmpty) return null;
    return prices.reduce((a, b) => a < b ? a : b);
  }

  /// Price for a vehicle size: general (size-independent) → small / large
  /// with bike using the small price → the other size as a last resort.
  /// `null` for by-quote offers.
  int? priceFor(VehicleSize size) {
    if (isByQuote) return null;
    if (priceGeneralCents != null) return priceGeneralCents;
    return switch (size) {
      VehicleSize.small => priceSmallCents ?? priceLargeCents,
      VehicleSize.large => priceLargeCents ?? priceSmallCents,
      VehicleSize.bike => priceSmallCents ?? priceLargeCents,
    };
  }

  /// `From R 150` / `By quote` / `R 400 excl. VAT`.
  String priceLabel(VehicleSize size) {
    final p = priceFor(size);
    if (p == null) return 'By quote';
    final amount = Money.formatZarCompact(p).replaceFirst('R', 'R ');
    final prefix = pricingMode == PricingMode.from ? 'From ' : '';
    final suffix = vatMode == VatMode.excl ? ' excl. VAT' : '';
    return '$prefix$amount$suffix';
  }

  /// VAT in cents that the total gains for this offer at [size].
  int vatFor(VehicleSize size) => vatMode.vatOn(priceFor(size) ?? 0);

  /// Points for a booking of this offer at [size].
  int pointsFor(VehicleSize size) {
    final p = priceFor(size);
    if (p == null) return 0;
    return (p / 100 * pointsPerRand).round();
  }

  /// "a · b · c" caption for composites.
  String? get includesLabel =>
      includes.isEmpty ? null : includes.map((r) => r.name).join(' · ');

  /// Legacy view of the canonical service (icon, description, code…).
  Service get service => Service(
    id: serviceId,
    code: code,
    name: name,
    category: category,
    description: description,
    groupName: groupName,
    durationMinutes: durationMinutes,
    basePriceCents: priceFromCents ?? 0,
    isQuoteBased: isByQuote,
    pricingMode: pricingMode,
    vatMode: vatMode,
    priceSmallCents: priceSmallCents,
    priceLargeCents: priceLargeCents,
    priceGeneralCents: priceGeneralCents,
    isAddon: isAddon,
    addonGroupName: addonGroupName,
    notes: notes,
    pointsPerRand: pointsPerRand,
    icon: icon,
    checklistTemplateId: checklistTemplateId,
    sortOrder: sortOrder,
  );

  factory OutletService.fromJson(Json json) {
    // Older payloads nested `service`; the catalogue endpoint flattens it.
    final nested = asJsonOrNull(json['service']);
    final s = {...?nested, ...json};
    final pricedFor = strOrNull(json['priced_for']) == null
        ? null
        : VehicleSize.fromDb(strOrNull(json['priced_for']));
    final mode = PricingMode.fromDb(
      strOrNull(s['pricing_mode']) ??
          (boolOf(s['is_quote_based']) ? 'by_quote' : null),
    );
    final small = intOrNull(s['price_small_cents']);
    final large = intOrNull(s['price_large_cents']);
    final general = intOrNull(s['price_general_cents']);
    final legacy = intOrNull(json['price_cents']) ?? intOrNull(s['base_price_cents']);
    final pointsPerRand = dbl(s['points_per_rand'], 0.10);
    final offer = OutletService(
      outletId: str(json['outlet_id']),
      serviceId: str(json['service_id'] ?? s['id']),
      code: str(s['code']),
      name: str(json['display_name'] ?? json['name'] ?? s['name']),
      category: ServiceCategory.fromDb(strOrNull(s['category'])),
      description: strOrNull(s['description']),
      groupName: str(s['group_name'], ServiceGroups.carWashOptions),
      durationMinutes: intOf(s['duration_minutes'], 30),
      icon: str(s['icon'], 'local_car_wash'),
      pricingMode: mode,
      vatMode: VatMode.fromDb(strOrNull(s['vat_mode'])),
      priceSmallCents: small,
      priceLargeCents: large,
      priceGeneralCents:
          general ??
          (small == null && large == null && mode != PricingMode.byQuote
              ? legacy
              : null),
      priceCents: mode == PricingMode.byQuote ? null : legacy,
      pricedFor: pricedFor,
      isAddon: boolOf(s['is_addon']),
      addonGroupName: strOrNull(s['addon_group_name']),
      includes: asJsonList(json['includes']).map(ServiceRef.fromJson).toList(),
      includedIn: asStringList(json['included_in']),
      isAvailable: boolOf(json['is_available'], true),
      sortOrder: intOf(json['sort_order'], intOf(s['sort_order'], 100)),
      notes: strOrNull(json['notes'] ?? s['notes']),
      pointsPerRand: pointsPerRand,
      checklistTemplateId: strOrNull(s['checklist_template_id']),
    );
    final points = intOrNull(json['points_estimate']);
    return points == null
        ? offer.copyWith(pointsEstimate: offer.pointsFor(pricedFor ?? VehicleSize.small))
        : offer.copyWith(pointsEstimate: points);
  }

  Json toJson() => compact({
    'outlet_id': outletId,
    'service_id': serviceId,
    'code': code,
    'name': name,
    'category': category.db,
    'description': description,
    'group_name': groupName,
    'duration_minutes': durationMinutes,
    'icon': icon,
    'pricing_mode': pricingMode.db,
    'vat_mode': vatMode.db,
    'price_small_cents': priceSmallCents,
    'price_large_cents': priceLargeCents,
    'price_general_cents': priceGeneralCents,
    'price_from_cents': priceFromCents,
    'price_cents': priceCents,
    'priced_for': pricedFor?.db,
    'price_for': {
      for (final s in VehicleSize.values) s.db: priceFor(s),
    },
    'is_addon': isAddon,
    'addon_group_name': addonGroupName,
    'includes': includes.map((r) => r.toJson()).toList(),
    'included_in': includedIn,
    'is_available': isAvailable,
    'sort_order': sortOrder,
    'notes': notes,
    'points_estimate': pointsEstimate,
    'points_per_rand': pointsPerRand,
    'checklist_template_id': checklistTemplateId,
  });

  OutletService copyWith({
    String? name,
    int? priceCents,
    VehicleSize? pricedFor,
    int? pointsEstimate,
    bool? isAvailable,
    List<ServiceRef>? includes,
    List<String>? includedIn,
    bool clearPrice = false,
  }) => OutletService(
    outletId: outletId,
    serviceId: serviceId,
    code: code,
    name: name ?? this.name,
    category: category,
    description: description,
    groupName: groupName,
    durationMinutes: durationMinutes,
    icon: icon,
    pricingMode: pricingMode,
    vatMode: vatMode,
    priceSmallCents: priceSmallCents,
    priceLargeCents: priceLargeCents,
    priceGeneralCents: priceGeneralCents,
    priceCents: clearPrice ? null : (priceCents ?? this.priceCents),
    pricedFor: pricedFor ?? this.pricedFor,
    isAddon: isAddon,
    addonGroupName: addonGroupName,
    includes: includes ?? this.includes,
    includedIn: includedIn ?? this.includedIn,
    isAvailable: isAvailable ?? this.isAvailable,
    sortOrder: sortOrder,
    notes: notes,
    pointsEstimate: pointsEstimate ?? this.pointsEstimate,
    pointsPerRand: pointsPerRand,
    checklistTemplateId: checklistTemplateId,
  );

  @override
  List<Object?> get props => [
    outletId,
    serviceId,
    name,
    pricingMode,
    vatMode,
    priceSmallCents,
    priceLargeCents,
    priceGeneralCents,
    priceCents,
    isAddon,
    includes,
    isAvailable,
    sortOrder,
    pointsEstimate,
  ];
}

/// `GET /outlets/:id/services` → `{ data: [offer], groups: [...] }`.
class OutletCatalogue extends Equatable {
  const OutletCatalogue({
    required this.outletId,
    required this.offers,
    this.groups = const [],
    this.vehicleSize,
  });

  final String outletId;
  final List<OutletService> offers;

  /// Group names in display order.
  final List<String> groups;

  /// Size the prices were resolved for (`?vehicle_size`), when requested.
  final VehicleSize? vehicleSize;

  static const OutletCatalogue empty = OutletCatalogue(outletId: '', offers: []);

  OutletService? byId(String serviceId) =>
      offers.where((o) => o.serviceId == serviceId).firstOrNull;

  OutletService? byCode(String code) =>
      offers.where((o) => o.code == code).firstOrNull;

  /// Groups that have at least one bookable (non add-on) offer, in order.
  List<String> get bookableGroups {
    final seen = <String>[];
    final ordered = groups.isEmpty
        ? (offers.map((o) => o.groupName).toSet().toList()
            ..sort((a, b) => ServiceGroups.order(a).compareTo(ServiceGroups.order(b))))
        : groups;
    for (final g in ordered) {
      if (offersIn(g).isNotEmpty && !seen.contains(g)) seen.add(g);
    }
    return seen;
  }

  /// Bookable (non add-on, available) offers of [group] in sort order.
  List<OutletService> offersIn(String group) =>
      offers.where((o) => o.groupName == group && !o.isAddon).toList()
        ..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));

  /// Add-ons that may be attached to a booking of a service in [group].
  List<OutletService> addonsFor(String group) =>
      offers
          .where((o) => o.isAddon && (o.addonGroupName ?? o.groupName) == group)
          .toList()
        ..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));

  /// All components of [serviceId], recursively, without duplicates and
  /// safe against cycles in the composition graph.
  List<ServiceRef> flattenIncludes(String serviceId) {
    final out = <ServiceRef>[];
    final seen = <String>{serviceId};
    void walk(String id) {
      final offer = byId(id);
      if (offer == null) return;
      for (final ref in offer.includes) {
        if (!seen.add(ref.serviceId)) continue;
        out.add(ref);
        walk(ref.serviceId);
      }
    }

    walk(serviceId);
    return out;
  }

  factory OutletCatalogue.fromJson(Json json, {String? outletId}) {
    final list = asJsonList(json['data'] ?? json['offers']);
    final id = outletId ?? str(json['outlet_id']);
    final size = strOrNull(json['vehicle_size']);
    return OutletCatalogue(
      outletId: id,
      offers: list
          .map(
            (m) => OutletService.fromJson({
              ...m,
              'outlet_id': m['outlet_id'] ?? id,
              if (size != null && m['priced_for'] == null) 'priced_for': size,
            }),
          )
          .toList(),
      groups: asStringList(json['groups']),
      vehicleSize: size == null ? null : VehicleSize.fromDb(size),
    );
  }

  Json toJson() => compact({
    'outlet_id': outletId,
    'data': offers.map((o) => o.toJson()).toList(),
    'groups': groups,
    'vehicle_size': vehicleSize?.db,
  });

  @override
  List<Object?> get props => [outletId, offers, groups, vehicleSize];
}
