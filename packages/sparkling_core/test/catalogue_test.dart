import 'package:flutter_test/flutter_test.dart';
import 'package:sparkling_core/sparkling_core.dart';

/// Catalogue pricing model (docs/API.md "Catalogue pricing model") as mirrored
/// by the demo store: size resolution, by-quote, add-ons, VAT and composites.
void main() {
  late DemoStore store;

  setUp(() {
    final today = DateTime.now();
    store = DemoStore(
      currentUser: DemoPersonas.customer,
      clock: () => DateTime(today.year, today.month, today.day, 9),
    );
  });

  tearDown(() => store.dispose());

  group('VehicleSize', () {
    test('maps disc descriptions', () {
      expect(VehicleSize.fromDiscDescription('Sedan (closed top)'), VehicleSize.small);
      expect(VehicleSize.fromDiscDescription('Hatch back'), VehicleSize.small);
      expect(VehicleSize.fromDiscDescription('Coupe'), VehicleSize.small);
      expect(VehicleSize.fromDiscDescription('Station wagon'), VehicleSize.large);
      expect(VehicleSize.fromDiscDescription('SUV'), VehicleSize.large);
      expect(VehicleSize.fromDiscDescription('LDV / Bakkie'), VehicleSize.large);
      expect(VehicleSize.fromDiscDescription('Pick-up'), VehicleSize.large);
      expect(VehicleSize.fromDiscDescription('Bus'), VehicleSize.large);
      expect(VehicleSize.fromDiscDescription('MPV'), VehicleSize.large);
      expect(VehicleSize.fromDiscDescription('Panel van'), VehicleSize.large);
      expect(VehicleSize.fromDiscDescription('Motorcycle'), VehicleSize.bike);
      expect(VehicleSize.fromDiscDescription('Motor cycle'), VehicleSize.bike);
      expect(VehicleSize.fromDiscDescription(null), VehicleSize.small);
      expect(VehicleSize.fromDiscDescription('Unknown thing'), VehicleSize.small);
      expect(VehicleSize.fromDb('large'), VehicleSize.large);
      expect(VehicleSize.fromDb(null), VehicleSize.small);
    });
  });

  group('offer resolution', () {
    test('Menlyn Sparkling Wash: small 14000 / large 15000, bike falls back', () {
      final c = store.outletCatalogue(DemoStore.outletMenlyn);
      final wash = c.byCode('SPARKLING_WASH')!;
      expect(wash.name, '"Sparkling wash" - include All of the above');
      expect(wash.groupName, ServiceGroups.carWashOptions);
      expect(wash.priceFor(VehicleSize.small), 14000);
      expect(wash.priceFor(VehicleSize.large), 15000);
      expect(wash.priceFor(VehicleSize.bike), 14000);
      expect(wash.priceFromCents, 14000);
      expect(wash.priceLabel(VehicleSize.small), 'From R 140');
      expect(wash.priceLabel(VehicleSize.large), 'From R 150');
      expect(wash.vatMode, VatMode.incl);

      // Wash bike only has a small price → every size resolves to it.
      final bike = c.byCode('WASH_BIKE')!;
      expect(bike.priceFor(VehicleSize.bike), 8000);
      expect(bike.priceFor(VehicleSize.large), 8000);

      // General (size-independent) price wins for auto body.
      final headlight = c.byCode('HEADLIGHT_RENEWAL')!;
      expect(headlight.priceFor(VehicleSize.large), 40000);
      expect(headlight.priceLabel(VehicleSize.small), 'From R 400 excl. VAT');
      expect(headlight.isExclVat, isTrue);
    });

    test('catalogue with ?vehicle_size resolves price_cents and points', () {
      final c = store.outletCatalogue(
        DemoStore.outletMenlyn,
        vehicleSize: VehicleSize.large,
      );
      expect(c.vehicleSize, VehicleSize.large);
      final wash = c.byCode('SPARKLING_WASH')!;
      expect(wash.priceCents, 15000);
      expect(wash.pricedFor, VehicleSize.large);
      expect(wash.pointsEstimate, 15);
      // By-quote offers carry no price.
      final tar = c.byCode('TAR_REMOVAL')!;
      expect(tar.isByQuote, isTrue);
      expect(tar.priceCents, isNull);
      expect(tar.priceLabel(VehicleSize.large), 'By quote');
      expect(tar.pointsEstimate, 0);
    });

    test('groups, add-ons and JSON round trip', () {
      final c = store.outletCatalogue(DemoStore.outletGlenVillage);
      expect(c.groups, ServiceGroups.all);
      expect(c.bookableGroups, ServiceGroups.all);
      final addons = c.addonsFor(ServiceGroups.combinations);
      expect(addons.map((a) => a.code), ['ADDON_ODOUR']);
      expect(addons.single.priceFor(VehicleSize.large), 18000);
      expect(c.addonsFor(ServiceGroups.carWashOptions), isEmpty);
      // Add-ons are not listed as bookable offers of their group.
      expect(
        c.offersIn(ServiceGroups.combinations).any((o) => o.isAddon),
        isFalse,
      );
      final back = OutletCatalogue.fromJson(c.toJson());
      expect(back.offers.length, c.offers.length);
      expect(back.byCode('FULL_MONTY')!.includes.length, 3);
      expect(back.byCode('AUTO_DETAIL_INTERIOR')!.priceFor(VehicleSize.large), 70000);
    });

    test('composition is resolved per outlet, flattened without cycles', () {
      final glv = store.outletCatalogue(DemoStore.outletGlenVillage);
      final monty = glv.byCode('FULL_MONTY')!;
      expect(monty.includes.map((r) => r.code), [
        'AUTO_DETAIL_COMPLETE',
        'ENGINE_CHASSIS_COMBO',
        'PAINT_POLISH_3STAGE',
      ]);
      expect(
        monty.includesLabel,
        'Auto Detailing Complete & Polish - Including "Sparkling Wash" · '
        'Engine & Chassis steam clean Combo · 3 Stage Paint polishing & Auto Glaze',
      );
      final flat = glv.flattenIncludes(monty.serviceId).map((r) => r.code).toList();
      expect(flat.toSet().length, flat.length, reason: 'no duplicates');
      expect(flat, containsAll(['SPARKLING_WASH', 'WASH_GO', 'ENGINE_STEAM', 'CHASSIS_STEAM']));
      expect(flat, isNot(contains('FULL_MONTY')));
      expect(glv.byCode('AUTO_DETAIL_COMPLETE')!.includedIn, contains(monty.serviceId));
      expect(glv.byCode('SPARKLING_WASH')!.includedIn, contains(DemoStore.svcAutoDetailComplete));

      // Menlyn's Sparkling Wash includes Menlyn's own prior options.
      final men = store.outletCatalogue(DemoStore.outletMenlyn);
      expect(men.byCode('SPARKLING_WASH')!.includes.map((r) => r.code), [
        'EXT_WASH',
        'EXT_WASH_TYRE_BUMPER',
        'WINDOWS_INSIDE',
        'INT_CLEAN',
      ]);
      expect(men.byCode('ENGINE_CHASSIS_COMBO')!.includes.map((r) => r.code), [
        'ENGINE_STEAM',
        'CHASSIS_STEAM',
      ]);

      // A cycle in the data must still terminate.
      store.serviceComponents.add(
        const DemoComponentRow(
          parentServiceId: DemoStore.svcSparklingWash,
          childServiceId: DemoStore.svcFullMonty,
          outletId: DemoStore.outletGlenVillage,
          sortOrder: 999,
        ),
      );
      final cyclic = store.outletCatalogue(DemoStore.outletGlenVillage);
      final flat2 = cyclic.flattenIncludes(monty.serviceId);
      expect(flat2.map((r) => r.code).toSet().length, flat2.length);
      expect(flat2.any((r) => r.code == 'FULL_MONTY'), isFalse);
    });
  });

  group('booking price engine', () {
    Vehicle vehicle(VehicleSize size) => Vehicle(
      id: 'v',
      customerId: 'seed_thabo',
      registrationNo: 'AA 11 BB GP',
      sizeClass: size,
    );

    test('size resolution: request → vehicle → small', () {
      final byVehicle = store.priceBooking(
        outletId: DemoStore.outletMenlyn,
        serviceId: DemoStore.svcSparklingWash,
        vehicle: vehicle(VehicleSize.large),
        discountPct: 0,
      );
      expect(byVehicle.size, VehicleSize.large);
      expect(byVehicle.base, 15000);
      final requested = store.priceBooking(
        outletId: DemoStore.outletMenlyn,
        serviceId: DemoStore.svcSparklingWash,
        vehicle: vehicle(VehicleSize.large),
        vehicleSize: VehicleSize.small,
        discountPct: 0,
      );
      expect(requested.size, VehicleSize.small);
      expect(requested.base, 14000);
      expect(requested.total, 14000);
      expect(requested.vat, 0);
    });

    test('Glen Village interior detailing (large) + odour add-on = 88000', () {
      final q = store.priceBooking(
        outletId: DemoStore.outletGlenVillage,
        serviceId: DemoStore.svcAutoDetailInterior,
        vehicle: vehicle(VehicleSize.large),
        addonServiceIds: const [DemoStore.svcAddonOdour],
        discountPct: 0,
      );
      expect(q.base, 70000);
      expect(q.addons.single.name, 'Add to any Combo: Odour Removal');
      expect(q.addons.single.priceCents, 18000);
      expect(q.addonsCents, 18000);
      expect(q.total, 88000);

      // Tier discount applies to base + add-ons.
      final gold = store.priceBooking(
        outletId: DemoStore.outletGlenVillage,
        serviceId: DemoStore.svcAutoDetailInterior,
        vehicle: vehicle(VehicleSize.large),
        addonServiceIds: const [DemoStore.svcAddonOdour],
        discountPct: 10,
      );
      expect(gold.discount, 8800);
      expect(gold.total, 79200);
    });

    test('add-ons must belong to the service group', () {
      expect(
        () => store.priceBooking(
          outletId: DemoStore.outletGlenVillage,
          serviceId: DemoStore.svcSparklingWash, // Car Wash Options
          vehicle: vehicle(VehicleSize.small),
          addonServiceIds: const [DemoStore.svcAddonOdour], // Combinations
          discountPct: 0,
        ),
        throwsA(
          isA<ApiException>()
              .having((e) => e.code, 'code', 'validation_error')
              .having((e) => e.isByQuote, 'isByQuote', isFalse),
        ),
      );
      // Booking an add-on on its own is refused too.
      expect(
        () => store.priceBooking(
          outletId: DemoStore.outletGlenVillage,
          serviceId: DemoStore.svcAddonOdour,
          vehicle: vehicle(VehicleSize.small),
          discountPct: 0,
        ),
        throwsA(isA<ApiException>()),
      );
    });

    test('VAT: headlight renewal 40000 excl → 46000 total', () {
      final q = store.priceBooking(
        outletId: DemoStore.outletMenlyn,
        serviceId: DemoStore.svcHeadlight,
        vehicle: vehicle(VehicleSize.small),
        discountPct: 0,
      );
      expect(q.offer.vatMode, VatMode.excl);
      expect(q.base, 40000);
      expect(q.vat, 6000);
      expect(q.total, 46000);
      expect(q.offer.vatFor(VehicleSize.small), 6000);
    });

    test('by-quote services refuse a booking with isByQuote', () async {
      expect(
        () => store.priceBooking(
          outletId: DemoStore.outletGlenVillage,
          serviceId: DemoStore.svcCeramic,
          vehicle: vehicle(VehicleSize.small),
          discountPct: 0,
        ),
        throwsA(
          isA<ApiException>()
              .having((e) => e.isByQuote, 'isByQuote', isTrue)
              .having((e) => e.statusCode, 'status', 409),
        ),
      );
      // …and through the repository path as the customer.
      final today = DateTime.now();
      final slot = DateTime(today.year, today.month, today.day + 8, 10);
      expect(
        () => store.createBooking(
          BookingInput(
            vehicleId: DemoStore.vehCorolla,
            outletId: DemoStore.outletMenlyn,
            serviceId: DemoStore.svcTarRemoval,
            slotStart: slot,
            clientOpId: 'op-bq-1',
          ),
        ),
        throwsA(isA<ApiException>().having((e) => e.isByQuote, 'isByQuote', isTrue)),
      );
      // The 409 envelope parses back the same way.
      final parsed = ApiException.fromEnvelope({
        'error': {
          'code': 'validation_error',
          'message': 'Quote-only service',
          'details': {'reason': 'by_quote'},
        },
      }, statusCode: 409);
      expect(parsed.isByQuote, isTrue);
    });

    test('createBooking records size, add-ons and VAT on the booking', () {
      final today = DateTime.now();
      var slot = DateTime(today.year, today.month, today.day + 8, 10);
      if (slot.weekday == DateTime.sunday) slot = slot.add(const Duration(days: 1));
      final b = store.createBooking(
        BookingInput(
          vehicleId: DemoStore.vehCorolla, // large
          outletId: DemoStore.outletGlenVillage,
          serviceId: DemoStore.svcAutoDetailInterior,
          slotStart: slot,
          clientOpId: 'op-addon-1',
          addonServiceIds: const [DemoStore.svcAddonOdour],
        ),
      );
      expect(b.vehicleSize, VehicleSize.large);
      expect(b.priceCents, 70000);
      expect(b.addons.single.serviceId, DemoStore.svcAddonOdour);
      expect(b.addonsCents, 18000);
      expect(b.subtotalCents, 88000);
      expect(b.discountCents, 8800); // Thabo is Gold −10 %
      expect(b.vatCents, 0);
      expect(b.totalCents, 79200);
      expect(b.pricingMode, PricingMode.from);
      expect(b.vatMode, VatMode.incl);
      expect(b.service?.name, 'Auto Detailing Interior');
      final json = b.toJson();
      expect(json['addon_service_ids'], [DemoStore.svcAddonOdour]);
      final back = Booking.fromJson(json);
      expect(back.addons, b.addons);
      expect(back.vehicleSize, VehicleSize.large);
    });

    test('vehicle input carries size_class and the store keeps it', () {
      final v = store.addVehicle(
        const VehicleInput(
          registrationNo: 'ZZ 99 YY GP',
          make: 'Ford',
          model: 'Ranger',
          sizeClass: VehicleSize.large,
        ),
      );
      expect(v.sizeClass, VehicleSize.large);
      expect(v.toJson()['size_class'], 'large');
      const input = VehicleInput(registrationNo: 'AB 12 CD GP');
      expect(input.toJson().containsKey('size_class'), isFalse);
      expect(input.copyWith(sizeClass: VehicleSize.bike).sizeClass, VehicleSize.bike);
    });
  });
}
