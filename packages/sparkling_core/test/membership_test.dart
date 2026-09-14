import 'package:flutter_test/flutter_test.dart';
import 'package:sparkling_core/sparkling_core.dart';

/// Membership plans (docs/MEMBERSHIPS.md) on the demo store: plans and
/// allowances, the pricing rules per plan / scope, usage on booking create and
/// release on cancel, subscribe → sandbox payment → active, counter
/// enrolment, selection changes (409), plan changes, cancellation, renewals
/// and the JSON shapes of `/memberships/me` & friends.
void main() {
  final today = DateTime.now();
  late DateTime clock;
  late DemoStore store;

  const thabo = AuthUser(
    uid: 'seed_thabo',
    email: 'thabo@example.com',
    displayName: 'Thabo Nkosi',
    claims: {'role': 'customer'},
  );
  const sipho = AuthUser(uid: 'seed_sipho', claims: {'role': 'customer'});
  const zanele = AuthUser(uid: 'seed_zanele', claims: {'role': 'customer'});

  DateTime bookingSlot() {
    var slot = DateTime(today.year, today.month, today.day + 8, 10);
    if (slot.weekday == DateTime.sunday) slot = slot.add(const Duration(days: 1));
    return slot;
  }

  Vehicle vehicle(String id) => store.vehicleById(id)!;

  setUp(() {
    clock = DateTime(today.year, today.month, today.day, 10, 13);
    store = DemoStore(currentUser: thabo, clock: () => clock);
  });

  tearDown(() => store.dispose());

  group('plans & allowances', () {
    test('the three plans are seeded with stable ids, groups and services', () {
      final list = store.membershipPlanList();
      expect(list.plans.map((p) => p.code), ['gold', 'platinum', 'black']);
      expect(list.currentPlanCode, 'gold');

      final gold = list.byCode('gold')!;
      expect(gold.id, DemoStore.planGold);
      expect(gold.tier, LoyaltyTier.gold);
      expect(gold.monthlyFeeCents, 29500);
      expect(gold.feeLabel, 'R 295 / month');
      expect(gold.discountScope, DiscountScope.otherServices);
      expect(gold.groups.single.code, 'washes');
      expect(gold.groups.single.isChooseOne, isTrue);
      expect(gold.entitlements.map((e) => e.code), ['G1', 'G2']);
      expect(gold.entitlement('G1')!.id, 'c3000000-0000-4000-8000-000000000001');
      expect(gold.entitlement('G1')!.services.single.code, 'SPARKLING_WASH');
      expect(
        gold.entitlement('G2')!.services.map((s) => s.code),
        ['EXT_WASH', 'EXT_WASH_TYRE', 'WASH_GO'],
      );
      expect(gold.entitlement('G2')!.primaryService!.code, 'EXT_WASH');
      expect(gold.defaultSelections(), {'washes': 'G1'});
      expect(gold.selectionsValid({'washes': 'G2'}), isTrue);
      expect(gold.selectionsValid({'washes': 'P1'}), isFalse);

      final black = list.byCode('black')!;
      expect(black.tier, LoyaltyTier.black);
      expect(black.groups.map((g) => g.code), ['washes', 'detail', 'coating']);
      expect(black.group('coating')!.selection, GroupSelection.all);
      expect(black.entitlement('B5')!.period, EntitlementPeriod.year);
      expect(black.chooseOneGroups.length, 2);
      expect(
        black.selectedEntitlements({'washes': 'B2', 'detail': 'B4'}).map(
          (e) => e.code,
        ),
        ['B2', 'B4', 'B5'],
      );
      expect(
        black.benefitsSummary({'washes': 'B1', 'detail': 'B3'}),
        '10 × Sparkling Wash per month · 1 × Auto Detail Complete per month · 1 × Ceramic coating per annum · 10% discount on the above selected services',
      );
    });

    test('entitlement wording: item name, plurals, allowance labels', () {
      final gold = store.planByCode('gold')!;
      expect(gold.entitlement('G1')!.itemName, 'Sparkling Wash');
      expect(gold.entitlement('G1')!.itemNamePlural, 'Sparkling Washes');
      expect(gold.entitlement('G1')!.countLabel(1), '1 Sparkling Wash');
      final black = store.planByCode('black')!;
      expect(black.entitlement('B3')!.itemName, 'Auto Detail Complete');
      expect(black.entitlement('B5')!.itemName, 'Ceramic coating');

      final thaboSummary = store.membershipSummary('seed_thabo');
      final a = thaboSummary.allowances.single;
      expect(a.summaryLabel, '3 of 4 Sparkling Washes left');
      expect(a.resetLabel, startsWith('resets '));
      expect(a.fullLabel, contains(' · resets '));
      expect(a.progress, closeTo(0.75, 0.001));
    });

    test('demo memberships match the seed (used / remaining per period)', () {
      MembershipSummary of(String uid) => store.membershipSummary(uid);

      final t = of('seed_thabo');
      expect(t.membership!.id, DemoStore.membershipThabo);
      expect(t.membership!.ref, 'MEM-${today.year}-0001');
      expect(t.planCode, 'gold');
      expect(t.selections, {'washes': 'G1'});
      expect(t.allowances.single.used, 1);
      expect(t.allowances.single.remaining, 3);
      expect(t.includedRemaining, 3);
      expect(t.shortLabel, 'Gold · 3 washes left');
      expect(t.openInvoice, isNull);
      expect(t.invoices.single.ref, 'MINV-${today.year}-0101');
      expect(t.invoices.single.isPaid, isTrue);
      expect(t.nextRenewalAt, t.membership!.currentPeriodEnd);
      expect(t.benefitsSummary, contains('4 × Sparkling Wash'));

      final n = of('seed_naledi');
      expect(n.planCode, 'gold');
      expect(n.selections, {'washes': 'G2'});
      expect(n.allowances.single.remaining, 6);
      expect(n.membership!.paymentMethod, MembershipPaymentMethod.cash);

      final s = of('seed_sipho');
      expect(s.planCode, 'platinum');
      expect(s.allowances.single.entitlementCode, 'P1');
      expect(s.allowances.single.remaining, 5);

      final z = of('seed_zanele');
      expect(z.planCode, 'black');
      expect(z.tier, LoyaltyTier.black);
      expect(z.selections, {'washes': 'B1', 'detail': 'B3'});
      expect(
        {for (final a in z.allowances) a.entitlementCode: a.remaining},
        {'B1': 8, 'B3': 0, 'B5': 1},
      );
      expect(z.includedRemaining, 8);
      // Renewal due in 3 days: the pending renewal invoice is open.
      expect(z.openInvoice!.id, DemoStore.invoiceZaneleRenewal);
      expect(z.openInvoice!.amountCents, 85000);
      expect(
        z.openInvoice!.periodStart!.isAtSameMomentAs(
          z.membership!.currentPeriodEnd!,
        ),
        isTrue,
      );
      expect(z.nextRenewalAt!.difference(clock).inDays, 3);
    });

    test('periods: monthly = +1 calendar month, annual = membership year', () {
      expect(
        DemoStore.addMonths(DateTime(2026, 1, 31), 1),
        DateTime(2026, 2, 28),
      );
      expect(
        DemoStore.addMonths(DateTime(2026, 12, 15, 9), 1),
        DateTime(2027, 1, 15, 9),
      );
      final z = store.membershipSummary('seed_zanele');
      final washes = z.allowanceFor('B1')!;
      expect(washes.periodStart, z.membership!.currentPeriodStart);
      expect(washes.periodEnd, z.membership!.currentPeriodEnd);
      final coating = z.allowanceFor('B5')!;
      expect(coating.period, EntitlementPeriod.year);
      expect(coating.periodStart, z.membership!.startedAt);
      expect(
        coating.periodEnd,
        DemoStore.addMonths(z.membership!.startedAt!, 12),
      );
      // Unused allowance does not roll over: a new period starts from zero.
      final m = store.memberships.indexWhere(
        (m) => m.id == DemoStore.membershipThabo,
      );
      final rolled = store.memberships[m].copyWith(
        currentPeriodStart: store.memberships[m].currentPeriodEnd,
        currentPeriodEnd: DemoStore.addMonths(
          store.memberships[m].currentPeriodEnd!,
          1,
        ),
      );
      store.memberships[m] = rolled;
      expect(store.membershipSummary('seed_thabo').allowances.single.used, 0);
      expect(store.membershipSummary('seed_thabo').allowances.single.remaining, 4);
    });

    test('tier = plan: loyalty accounts and customer summaries carry the plan', () {
      expect(store.tierOf('seed_thabo'), LoyaltyTier.gold);
      expect(store.tierOf('seed_zanele'), LoyaltyTier.black);
      expect(store.tierOf('seed_pieter'), LoyaltyTier.silver);
      for (final t in store.loyaltyConfig.tiers) {
        expect(t.discountPct, 0, reason: '${t.tier} discount comes from the plan');
      }
      expect(
        store.loyaltyConfig.tierConfig(LoyaltyTier.black)!.earnMultiplier,
        1.75,
      );

      final acc = store.loyaltyAccount();
      expect(acc.tier, LoyaltyTier.gold);
      expect(acc.membership!.planCode, 'gold');
      expect(acc.membership!.includedRemaining, 3);
      expect(acc.membership!.shortLabel, 'Gold · 3 washes left');

      store.signInAs(DemoPersonas.technician);
      final c = store.customerSummary('seed_thabo');
      expect(c.loyalty!.planCode, 'gold');
      expect(c.loyalty!.planName, 'Gold');
      expect(c.loyalty!.includedRemaining, 3);
      expect(c.loyalty!.planLabel, 'Gold · 3 washes left');
      expect(c.loyalty!.discountPct, 0);
      expect(store.customerSummary('seed_zanele').tier, LoyaltyTier.black);
    });
  });

  group('pricing rules', () {
    test('Gold (G1): Sparkling Wash included, base waived for a large vehicle', () {
      final q = store.priceBooking(
        outletId: DemoStore.outletMenlyn,
        serviceId: DemoStore.svcSparklingWash,
        vehicle: vehicle(DemoStore.vehCorolla), // large
        customerId: 'seed_thabo',
      );
      expect(q.base, 15000);
      expect(q.discount, 15000);
      expect(q.total, 0);
      expect(q.discountLabel, 'Included in Gold · 2 of 4 left');
      expect(q.membership!.benefit, MembershipBenefit.included);
      expect(q.membership!.entitlementCode, 'G1');
      expect(q.membership!.remainingAfter, 2);
      expect(q.entitlementId, 'c3000000-0000-4000-8000-000000000001');
      expect(q.membershipId, DemoStore.membershipThabo);

      final quote = store.quoteBooking(
        outletId: DemoStore.outletMenlyn,
        serviceId: DemoStore.svcSparklingWash,
        vehicle: vehicle(DemoStore.vehCorolla),
      );
      expect(quote.isIncluded, isTrue);
      expect(quote.totalCents, 0);
      expect(quote.pointsPending, 0);
    });

    test('Gold other_services: no discount on plan services, 10% on the rest', () {
      // Exterior Wash belongs to G2 (not selected) → no benefit.
      final ext = store.priceBooking(
        outletId: DemoStore.outletMenlyn,
        serviceId: DemoStore.svcExtWash,
        vehicle: vehicle(DemoStore.vehCorolla),
        customerId: 'seed_thabo',
      );
      expect(ext.discount, 0);
      expect(ext.discountLabel, isNull);
      expect(ext.membership!.planCode, 'gold');
      expect(ext.membership!.benefit, isNull);

      // Interior detailing + odour add-on → 10 % on base + add-ons.
      final detail = store.priceBooking(
        outletId: DemoStore.outletMenlyn,
        serviceId: DemoStore.svcAutoDetailInterior,
        vehicle: vehicle(DemoStore.vehCorolla),
        addonServiceIds: const [DemoStore.svcAddonOdour],
        customerId: 'seed_thabo',
      );
      expect(detail.base, 70000);
      expect(detail.addonsCents, 18000);
      expect(detail.discount, 8800);
      expect(detail.total, 79200);
      expect(detail.discountLabel, 'Gold −10%');
      expect(detail.membership!.benefit, MembershipBenefit.discount);
    });

    test('Gold (G2): any exterior-wash variant redeems the allowance', () {
      final ext = store.priceBooking(
        outletId: DemoStore.outletMenlyn,
        serviceId: DemoStore.svcExtWash,
        vehicle: vehicle(DemoStore.vehSwift),
        customerId: 'seed_naledi',
      );
      expect(ext.discount, ext.base);
      expect(ext.discountLabel, 'Included in Gold · 5 of 8 left');
      final washGo = store.priceBooking(
        outletId: DemoStore.outletGlenVillage,
        serviceId: DemoCatalogueIds.washGo,
        vehicle: vehicle(DemoStore.vehSwift),
        customerId: 'seed_naledi',
      );
      expect(washGo.total, 0);
      expect(washGo.membership!.entitlementCode, 'G2');
      final sparkling = store.priceBooking(
        outletId: DemoStore.outletMenlyn,
        serviceId: DemoStore.svcSparklingWash,
        vehicle: vehicle(DemoStore.vehSwift),
        customerId: 'seed_naledi',
      );
      expect(sparkling.discount, 0, reason: 'G1 service, not selected');
    });

    test('Platinum plan_services: included while allowance lasts, then −10%', () {
      final hilux = vehicle(DemoStore.vehHilux);
      final included = store.priceBooking(
        outletId: DemoStore.outletMenlyn,
        serviceId: DemoStore.svcSparklingWash,
        vehicle: hilux,
        customerId: 'seed_sipho',
      );
      expect(included.discountLabel, 'Included in Platinum · 4 of 8 left');
      expect(included.total, 0);
      // Not a selected plan service → no discount under plan_services.
      final ext = store.priceBooking(
        outletId: DemoStore.outletMenlyn,
        serviceId: DemoStore.svcExtWash,
        vehicle: hilux,
        customerId: 'seed_sipho',
      );
      expect(ext.discount, 0);
      final other = store.priceBooking(
        outletId: DemoStore.outletMenlyn,
        serviceId: DemoStore.svcAutoDetailInterior,
        vehicle: hilux,
        customerId: 'seed_sipho',
      );
      expect(other.discount, 0);

      // Use up the remaining 5 washes → the plan discount applies instead.
      final m = store.memberships.firstWhere(
        (m) => m.id == DemoStore.membershipSipho,
      );
      for (var i = 0; i < 5; i++) {
        store.membershipUsage.add(
          MembershipUsage(
            id: 'u-$i',
            membershipId: m.id,
            entitlementId: 'c3000000-0000-4000-8000-000000000003',
            quantity: 1,
            periodStart: m.currentPeriodStart!,
            periodEnd: m.currentPeriodEnd!,
          ),
        );
      }
      expect(store.membershipSummary('seed_sipho').allowances.single.remaining, 0);
      final exhausted = store.priceBooking(
        outletId: DemoStore.outletMenlyn,
        serviceId: DemoStore.svcSparklingWash,
        vehicle: hilux,
        customerId: 'seed_sipho',
      );
      expect(exhausted.discount, 1500);
      expect(exhausted.total, 13500);
      expect(exhausted.discountLabel, 'Platinum −10%');
      expect(exhausted.membership!.benefit, MembershipBenefit.discount);
    });

    test('included service still charges add-ons (+ VAT on add-ons only)', () {
      store.signInAs(DemoPersonas.technician);
      final customer = store.createCustomer(
        const CustomerInput(
          fullName: 'Bongani Dlamini',
          phone: '083 555 0100',
          clientOpId: 'op-cust-black',
        ),
      );
      final car = store.createCustomerVehicle(
        customer.id,
        const VehicleInput(registrationNo: 'BB 12 CD GP'),
      );
      store.enrolMembership(
        EnrolMembershipInput(
          customerId: customer.id,
          planCode: 'black',
          selections: const {'washes': 'B1', 'detail': 'B3'},
          paymentMethod: CounterPaymentMethod.cash,
          clientOpId: 'op-enrol-black',
        ),
      );
      final q = store.priceBooking(
        outletId: DemoStore.outletGlenVillage,
        serviceId: DemoStore.svcAutoDetailComplete,
        vehicle: car,
        addonServiceIds: const [DemoStore.svcAddonOdour],
        customerId: customer.id,
      );
      expect(q.base, 85000);
      expect(q.discount, 85000);
      expect(q.addonsCents, 18000);
      expect(q.vat, 0);
      expect(q.total, 18000);
      expect(q.discountLabel, 'Included in Black · 0 of 1 left');
      // The by-quote ceramic coating (B5) is still refused for a booking.
      expect(
        () => store.priceBooking(
          outletId: DemoStore.outletGlenVillage,
          serviceId: DemoStore.svcCeramic,
          vehicle: car,
          customerId: customer.id,
        ),
        throwsA(isA<ApiException>().having((e) => e.isByQuote, 'byQuote', true)),
      );
    });

    test('past_due and pending memberships give no benefits', () {
      final i = store.memberships.indexWhere(
        (m) => m.id == DemoStore.membershipZanele,
      );
      store.memberships[i] = store.memberships[i].copyWith(
        status: MembershipStatus.pastDue,
      );
      final q = store.priceBooking(
        outletId: DemoStore.outletMenlyn,
        serviceId: DemoStore.svcSparklingWash,
        vehicle: vehicle(DemoStore.vehBmw),
        customerId: 'seed_zanele',
      );
      expect(q.discount, 0);
      expect(q.membership, isNull);
      // The tier label is kept while past due.
      expect(store.tierOf('seed_zanele'), LoyaltyTier.black);
      expect(store.membershipSummary('seed_zanele').isPastDue, isTrue);
      expect(store.membershipSummary('seed_zanele').benefitsActive, isFalse);
    });

    test('no membership → base + add-ons, tier discount is 0', () {
      final q = store.priceBooking(
        outletId: DemoStore.outletMenlyn,
        serviceId: DemoStore.svcSparklingWash,
        vehicle: vehicle(DemoStore.vehCorolla),
        customerId: 'seed_pieter',
      );
      expect(q.discount, 0);
      expect(q.total, 15000);
      expect(q.membership, isNull);
    });
  });

  group('booking lifecycle', () {
    test('create redeems +1, cancel releases −1 (both idempotent)', () {
      final b = store.createBooking(
        BookingInput(
          vehicleId: DemoStore.vehCorolla,
          outletId: DemoStore.outletMenlyn,
          serviceId: DemoStore.svcSparklingWash,
          slotStart: bookingSlot(),
          clientOpId: 'op-inc-1',
        ),
      );
      expect(b.isIncluded, isTrue);
      expect(b.membershipBenefit, MembershipBenefit.included);
      expect(b.membershipId, DemoStore.membershipThabo);
      expect(b.entitlementId, 'c3000000-0000-4000-8000-000000000001');
      expect(b.totalCents, 0);
      expect(b.discountLabel, 'Included in Gold · 2 of 4 left');
      final usage = store.membershipUsage.where((u) => u.bookingId == b.id);
      expect(usage.single.quantity, 1);
      expect(usage.single.idempotencyKey, 'booking:${b.id}:membership');
      expect(store.membershipSummary('seed_thabo').allowances.single.remaining, 2);

      // Replaying the create (same client_op_id) does not redeem twice.
      store.createBooking(
        BookingInput(
          vehicleId: DemoStore.vehCorolla,
          outletId: DemoStore.outletMenlyn,
          serviceId: DemoStore.svcSparklingWash,
          slotStart: bookingSlot(),
          clientOpId: 'op-inc-1',
        ),
      );
      expect(store.membershipUsage.where((u) => u.bookingId == b.id).length, 1);

      final cancelled = store.cancelBooking(b.id);
      expect(cancelled.status, BookingStatus.cancelled);
      final rows = store.membershipUsage.where((u) => u.bookingId == b.id).toList();
      expect(rows.length, 2);
      expect(rows.last.quantity, -1);
      expect(rows.last.idempotencyKey, 'booking:${b.id}:membership_release');
      expect(store.membershipSummary('seed_thabo').allowances.single.remaining, 3);

      // The booking JSON carries the membership block both ways.
      final back = Booking.fromJson(b.toJson());
      expect(back.membership!.toJson(), b.membership!.toJson());
      expect(back.membershipBenefit, MembershipBenefit.included);
      expect(back.membershipId, b.membershipId);
    });

    test('walk-in bookings go through the same path', () {
      store.signInAs(DemoPersonas.technician);
      final b = store.createWalkInBooking(
        const WalkInBookingInput(
          customerId: 'seed_naledi',
          vehicleId: DemoStore.vehSwift,
          outletId: DemoStore.outletMenlyn,
          serviceId: DemoStore.svcExtWash,
          clientOpId: 'op-walkin-inc',
        ),
      );
      expect(b.isIncluded, isTrue);
      expect(b.totalCents, 0);
      expect(b.discountLabel, 'Included in Gold · 5 of 8 left');
      expect(store.membershipSummary('seed_naledi').allowances.single.remaining, 5);
    });
  });

  group('subscribe / activate', () {
    test('cancel now → silver; subscribe → pending; sandbox payment → active', () {
      final ended = store.cancelMembership(atPeriodEnd: false);
      expect(ended.hasMembership, isFalse);
      expect(store.tierOf('seed_thabo'), LoyaltyTier.silver);
      expect(store.loyaltyAccount().tier, LoyaltyTier.silver);
      expect(store.loyaltyAccount().membership, isNull);
      expect(store.membershipPlanList().currentPlanCode, isNull);

      final r = store.subscribeMembership(
        planCode: 'platinum',
        selections: const {'washes': 'P2'},
        clientOpId: 'op-sub-1',
      );
      expect(r.membership.status, MembershipStatus.pending);
      expect(r.membership.ref, 'MEM-${today.year}-0005');
      expect(r.invoice!.amountCents, 47500);
      expect(r.invoice!.isPending, isTrue);
      expect(r.requiresPayment, isTrue);
      expect(r.payment!.payment.status, PaymentStatus.pending);
      expect(r.payment!.payment.membershipInvoiceId, r.invoice!.id);
      expect(r.payment!.payment.bookingId, isNull);
      expect(r.payment!.clientSecret, startsWith('sbx_secret_'));
      // Pending: no tier, no benefits yet.
      expect(store.tierOf('seed_thabo'), LoyaltyTier.silver);
      expect(store.membershipSummary('seed_thabo').isPending, isTrue);
      expect(store.membershipSummary('seed_thabo').openInvoice!.id, r.invoice!.id);

      // Replay with the same client_op_id → same membership.
      final replay = store.subscribeMembership(
        planCode: 'platinum',
        selections: const {'washes': 'P2'},
        clientOpId: 'op-sub-1',
      );
      expect(replay.membership.id, r.membership.id);
      // A second subscription while one is live → 409.
      expect(
        () => store.subscribeMembership(
          planCode: 'gold',
          selections: const {'washes': 'G1'},
          clientOpId: 'op-sub-2',
        ),
        throwsA(isA<ApiException>().having((e) => e.isConflict, 'conflict', true)),
      );

      final paid = store.sandboxConfirm(r.payment!.payment.id);
      expect(paid.status, PaymentStatus.successful);
      final s = store.membershipSummary('seed_thabo');
      expect(s.isActive, isTrue);
      expect(s.planCode, 'platinum');
      expect(s.membership!.currentPeriodStart, clock);
      expect(s.membership!.currentPeriodEnd, DemoStore.addMonths(clock, 1));
      expect(s.openInvoice, isNull);
      expect(s.invoices.single.isPaid, isTrue);
      expect(s.invoices.single.paymentId, paid.id);
      expect(s.allowances.single.entitlementCode, 'P2');
      expect(s.allowances.single.remaining, 16);
      expect(store.tierOf('seed_thabo'), LoyaltyTier.platinum);
      expect(store.loyaltyAccount().membership!.planName, 'Platinum');
      expect(
        store.myNotifications().any(
          (n) => n.templateKey == 'membership_activated',
        ),
        isTrue,
      );
    });

    test('selection validation and change-selections (409 once used)', () {
      expect(
        () => store.changeMembershipSelections(const {'washes': 'P1'}),
        throwsA(isA<ApiException>().having((e) => e.isValidation, 'validation', true)),
      );
      // Thabo used 1 wash this period → 409.
      expect(
        () => store.changeMembershipSelections(const {'washes': 'G2'}),
        throwsA(
          isA<ApiException>()
              .having((e) => e.isConflict, 'conflict', true)
              .having((e) => e.statusCode, 'status', 409),
        ),
      );
      // Naledi's period has usage too; Sipho's does — a fresh member may.
      store.cancelMembership(atPeriodEnd: false);
      final r = store.subscribeMembership(
        planCode: 'gold',
        selections: const {'washes': 'G1'},
        clientOpId: 'op-sub-fresh',
      );
      store.sandboxConfirm(r.payment!.payment.id);
      final changed = store.changeMembershipSelections(const {'washes': 'G2'});
      expect(changed.selections, {'washes': 'G2'});
      expect(changed.allowances.single.quantity, 8);
    });

    test('pay a pending renewal invoice from the app', () {
      store.signInAs(zanele);
      final intent = store.payMembershipInvoice(
        DemoStore.invoiceZaneleRenewal,
        idempotencyKey: 'op-pay-renewal',
      );
      expect(intent.payment.amountCents, 85000);
      expect(intent.payment.membershipInvoiceId, DemoStore.invoiceZaneleRenewal);
      // Idempotent while pending.
      expect(
        store
            .payMembershipInvoice(
              DemoStore.invoiceZaneleRenewal,
              idempotencyKey: 'op-pay-renewal',
            )
            .payment
            .id,
        intent.payment.id,
      );
      final before = store.membershipSummary('seed_zanele');
      store.sandboxConfirm(intent.payment.id);
      final after = store.membershipSummary('seed_zanele');
      expect(after.openInvoice, isNull);
      expect(after.isActive, isTrue);
      expect(after.membership!.currentPeriodStart, before.membership!.currentPeriodEnd);
      expect(
        after.membership!.currentPeriodEnd,
        DemoStore.addMonths(before.membership!.currentPeriodEnd!, 1),
      );
      // New period → washes reset (annual coating keeps its year).
      expect(after.allowanceFor('B1')!.used, 0);
      expect(after.allowanceFor('B5')!.remaining, 1);
      expect(
        store.myNotifications().any((n) => n.templateKey == 'membership_renewed'),
        isTrue,
      );
    });
  });

  group('change plan & cancel', () {
    test('upgrade charges now and switches on payment; downgrade waits', () {
      final up = store.changeMembershipPlan(
        planCode: 'black',
        selections: const {'washes': 'B2', 'detail': 'B4'},
        clientOpId: 'op-up-1',
      );
      expect(up.requiresPayment, isTrue);
      expect(up.invoice!.amountCents, 85000);
      expect(store.membershipSummary('seed_thabo').planCode, 'gold',
          reason: 'unchanged until paid');
      store.sandboxConfirm(up.payment!.payment.id);
      final s = store.membershipSummary('seed_thabo');
      expect(s.planCode, 'black');
      expect(s.tier, LoyaltyTier.black);
      expect(s.selections, {'washes': 'B2', 'detail': 'B4'});
      expect(s.membership!.currentPeriodStart, clock);
      expect(store.tierOf('seed_thabo'), LoyaltyTier.black);

      // Same plan → 400.
      expect(
        () => store.changeMembershipPlan(
          planCode: 'black',
          selections: const {'washes': 'B1', 'detail': 'B3'},
          clientOpId: 'op-same',
        ),
        throwsA(isA<ApiException>().having((e) => e.isValidation, 'validation', true)),
      );

      final down = store.changeMembershipPlan(
        planCode: 'gold',
        selections: const {'washes': 'G2'},
        clientOpId: 'op-down-1',
      );
      expect(down.requiresPayment, isFalse);
      expect(down.membership.nextPlanId, DemoStore.planGold);
      expect(store.membershipSummary('seed_thabo').planCode, 'black');

      // Renewal job: 3 days before the period end the next (Gold) invoice
      // is raised; once the period ends unpaid → past_due; paying at the
      // counter rolls the period onto Gold with the stored selections.
      final periodEnd = store.membershipSummary('seed_thabo').membership!.currentPeriodEnd!;
      clock = periodEnd.add(const Duration(hours: 1));
      store.runMembershipRenewals();
      final due = store.membershipSummary('seed_thabo');
      expect(due.isPastDue, isTrue);
      expect(due.openInvoice!.amountCents, 29500);
      expect(due.openInvoice!.periodStart, periodEnd);
      expect(store.tierOf('seed_thabo'), LoyaltyTier.black, reason: 'label kept');
      expect(
        store.priceBooking(
          outletId: DemoStore.outletMenlyn,
          serviceId: DemoStore.svcSparklingWash,
          vehicle: vehicle(DemoStore.vehCorolla),
          customerId: 'seed_thabo',
        ).discount,
        0,
        reason: 'benefits paused while past due',
      );

      store.signInAs(DemoPersonas.technician);
      final renewed = store.recordMembershipInvoicePayment(
        membershipId: due.membership!.id,
        invoiceId: due.openInvoice!.id,
        method: CounterPaymentMethod.cardTerminal,
        clientOpId: 'op-record-1',
      );
      expect(renewed.isActive, isTrue);
      expect(renewed.planCode, 'gold');
      expect(renewed.selections, {'washes': 'G2'});
      expect(renewed.membership!.currentPeriodStart, periodEnd);
      expect(renewed.membership!.nextPlanId, isNull);
      expect(store.tierOf('seed_thabo'), LoyaltyTier.gold);
      final pos = store.payments.firstWhere((p) => p.idempotencyKey == 'op-record-1');
      expect(pos.provider, 'pos');
      expect(pos.receipt!['method'], 'card_terminal');
      // Idempotent replay.
      expect(
        store
            .recordMembershipInvoicePayment(
              membershipId: due.membership!.id,
              invoiceId: due.openInvoice!.id,
              method: CounterPaymentMethod.cash,
              clientOpId: 'op-record-1',
            )
            .planCode,
        'gold',
      );
    });

    test('cancel at period end keeps benefits until then; then expires', () {
      final s = store.cancelMembership();
      expect(s.isActive, isTrue);
      expect(s.membership!.cancelAtPeriodEnd, isTrue);
      expect(s.membership!.isEnding, isTrue);
      expect(s.nextRenewalAt, isNull);
      expect(store.tierOf('seed_thabo'), LoyaltyTier.gold);
      expect(
        store.priceBooking(
          outletId: DemoStore.outletMenlyn,
          serviceId: DemoStore.svcSparklingWash,
          vehicle: vehicle(DemoStore.vehCorolla),
          customerId: 'seed_thabo',
        ).discount,
        15000,
      );
      clock = s.membership!.currentPeriodEnd!.add(const Duration(minutes: 1));
      store.runMembershipRenewals();
      expect(store.liveMembership('seed_thabo'), isNull);
      expect(store.tierOf('seed_thabo'), LoyaltyTier.silver);
      expect(
        store.memberships
            .firstWhere((m) => m.id == DemoStore.membershipThabo)
            .status,
        MembershipStatus.expired,
      );
      expect(
        store.myNotifications().any((n) => n.templateKey == 'membership_cancelled'),
        isTrue,
      );
    });

    test('renewal job raises the next invoice 3 days ahead, once', () {
      store.signInAs(sipho);
      final m = store.membershipSummary('seed_sipho').membership!;
      clock = m.currentPeriodEnd!.subtract(const Duration(days: 2));
      store.runMembershipRenewals();
      store.runMembershipRenewals();
      final s = store.membershipSummary('seed_sipho');
      expect(s.isActive, isTrue);
      expect(s.openInvoice!.periodStart, m.currentPeriodEnd);
      expect(s.invoices.where((i) => i.isPending).length, 1);
      expect(
        store.myNotifications().where((n) => n.templateKey == 'membership_renewal_due').length,
        1,
      );
    });
  });

  group('counter enrolment (staff)', () {
    setUp(() {
      store.signInAs(DemoPersonas.technician);
    });

    test('enrol → active immediately, invoice paid, POS payment, tier synced', () {
      final customer = store.createCustomer(
        const CustomerInput(
          fullName: 'Lerato Mokoena',
          phone: '082 555 0123',
          clientOpId: 'op-cust-1',
        ),
      );
      expect(store.customerSummary(customer.id).loyalty, isNull);
      final s = store.enrolMembership(
        EnrolMembershipInput(
          customerId: customer.id,
          planCode: 'gold',
          selections: const {'washes': 'G2'},
          paymentMethod: CounterPaymentMethod.cash,
          clientOpId: 'op-enrol-1',
        ),
      );
      expect(s.isActive, isTrue);
      expect(s.membership!.createdBy, DemoPersonas.technician.uid);
      expect(s.membership!.paymentMethod, MembershipPaymentMethod.cash);
      expect(s.membership!.currentPeriodStart, clock);
      expect(s.invoices.single.isPaid, isTrue);
      expect(s.invoices.single.amountCents, 29500);
      expect(s.allowances.single.remaining, 8);
      expect(s.includedRemaining, 8);
      final pay = store.payments.firstWhere((p) => p.idempotencyKey == 'op-enrol-1');
      expect(pay.provider, 'pos');
      expect(pay.membershipInvoiceId, s.invoices.single.id);
      expect(pay.receiptNo, startsWith('RCP-'));
      expect(pay.receipt!['method'], 'cash');
      expect(store.tierOf(customer.id), LoyaltyTier.gold);
      final c = store.customerSummary(customer.id);
      expect(c.tier, LoyaltyTier.gold);
      expect(c.loyalty!.planLabel, 'Gold · 8 washes left');
      expect(store.customerMembershipSummary(customer.id).planCode, 'gold');

      // Idempotent replay / second enrolment conflicts.
      expect(
        store
            .enrolMembership(
              EnrolMembershipInput(
                customerId: customer.id,
                planCode: 'gold',
                selections: const {'washes': 'G2'},
                paymentMethod: CounterPaymentMethod.cash,
                clientOpId: 'op-enrol-1',
              ),
            )
            .membership!
            .id,
        s.membership!.id,
      );
      expect(
        () => store.enrolMembership(
          EnrolMembershipInput(
            customerId: customer.id,
            planCode: 'platinum',
            selections: const {'washes': 'P1'},
            paymentMethod: CounterPaymentMethod.eft,
            clientOpId: 'op-enrol-2',
          ),
        ),
        throwsA(isA<ApiException>().having((e) => e.isConflict, 'conflict', true)),
      );
      // The new member's first wash is included right away.
      final car = store.createCustomerVehicle(
        customer.id,
        const VehicleInput(registrationNo: 'LM 45 KP GP'),
      );
      final b = store.createWalkInBooking(
        WalkInBookingInput(
          customerId: customer.id,
          vehicleId: car.id,
          outletId: DemoStore.outletMenlyn,
          serviceId: DemoStore.svcExtWash,
          clientOpId: 'op-walk-enrolled',
        ),
      );
      expect(b.totalCents, 0);
      expect(b.discountLabel, 'Included in Gold · 7 of 8 left');
    });

    test('membership.enrol is accepted by the sync batch', () {
      final customer = store.createCustomer(
        const CustomerInput(
          fullName: 'Sync Test',
          phone: '082 555 0199',
          clientOpId: 'op-cust-sync',
        ),
      );
      final input = EnrolMembershipInput(
        customerId: customer.id,
        planCode: 'platinum',
        selections: const {'washes': 'P1'},
        paymentMethod: CounterPaymentMethod.eft,
        clientOpId: 'op-enrol-sync',
      );
      final results = store.applySyncBatch([
        {
          'client_op_id': input.clientOpId,
          'kind': SyncKinds.membershipEnrol,
          'payload': input.toJson(),
          'device_time': clock.toIso8601String(),
        },
      ]);
      expect(results.single.applied, isTrue);
      final s = MembershipSummary.fromJson(results.single.result!);
      expect(s.planCode, 'platinum');
      expect(s.membership!.paymentMethod, MembershipPaymentMethod.eft);
      expect(store.tierOf(customer.id), LoyaltyTier.platinum);
      // Customers may not enrol at the counter.
      store.signInAs(thabo);
      expect(
        () => store.enrolMembership(input),
        throwsA(isA<ApiException>().having((e) => e.isForbidden, 'forbidden', true)),
      );
    });
  });

  group('JSON round-trips', () {
    test('plan, summary, allowance, brief, subscribe result, enrol input', () {
      final plan = store.planByCode('black')!;
      final planBack = MembershipPlan.fromJson(plan.toJson());
      expect(planBack, plan);
      expect(planBack.entitlement('B5')!.services.single.code, 'CERAMIC_COATING');
      expect(planBack.entitlement('B5')!.period, EntitlementPeriod.year);

      final list = MembershipPlanList.fromJson(store.membershipPlanList().toJson());
      expect(list.plans.length, 3);
      expect(list.currentPlanCode, 'gold');

      final s = store.membershipSummary('seed_zanele');
      final sBack = MembershipSummary.fromJson(s.toJson());
      expect(sBack.toJson(), s.toJson());
      expect(sBack.selections, {'washes': 'B1', 'detail': 'B3'});
      expect(sBack.allowances.length, 3);
      expect(sBack.openInvoice!.ref, 'MINV-${today.year}-0105');
      expect(sBack.membership!.ref, 'MEM-${today.year}-0004');
      expect(MembershipSummary.fromJson(const {}).hasMembership, isFalse);
      expect(MembershipSummary.fromJson(const {'membership': null}), MembershipSummary.none);

      final a = s.allowanceFor('B1')!;
      expect(Allowance.fromJson(a.toJson()).toJson(), a.toJson());
      expect(Allowance.fromJson(a.toJson()).summaryLabel, '8 of 10 Sparkling Washes left');

      final acc = store.loyaltyAccount();
      final accBack = LoyaltyAccountSummary.fromJson(acc.toJson());
      expect(accBack.membership!.toJson(), acc.membership!.toJson());
      expect(accBack.tier, LoyaltyTier.gold);

      final brief = MembershipBrief.fromJson({
        'plan_code': 'gold',
        'plan_name': 'Gold',
        'status': 'active',
        'period_end': '2026-10-05T08:00:00Z',
        'allowances': [
          {
            'entitlement_id': 'e',
            'entitlement_code': 'G1',
            'group_code': 'washes',
            'label': '4 × Sparkling Wash',
            'quantity': 4,
            'used': 1,
            'remaining': 3,
            'period': 'month',
          },
        ],
      });
      expect(brief.shortLabel, 'Gold · 3 washes left');
      expect(MembershipBrief.fromJson(brief.toJson()), brief);

      store.signInAs(DemoPersonas.technician);
      final c = store.customerSummary('seed_sipho');
      final cBack = CustomerSummary.fromJson(c.toJson());
      expect(cBack.loyalty!.planCode, 'platinum');
      expect(cBack.loyalty!.includedRemaining, 5);
      expect(cBack.loyalty!.planLabel, 'Platinum · 5 washes left');

      store.signInAs(thabo);
      store.cancelMembership(atPeriodEnd: false);
      final r = store.subscribeMembership(
        planCode: 'gold',
        selections: const {'washes': 'G1'},
        clientOpId: 'op-json-sub',
      );
      final rBack = SubscribeResult.fromJson(r.toJson());
      expect(rBack.toJson(), r.toJson());
      expect(rBack.membership.status, MembershipStatus.pending);
      expect(rBack.invoice!.isPending, isTrue);
      expect(rBack.payment!.payment.id, r.payment!.payment.id);
      expect(rBack.payment!.clientSecret, r.payment!.clientSecret);

      const input = EnrolMembershipInput(
        customerId: 'c1',
        planCode: 'gold',
        selections: {'washes': 'G2'},
        paymentMethod: CounterPaymentMethod.cardTerminal,
        clientOpId: 'op-x',
      );
      final inputBack = EnrolMembershipInput.fromJson(input.toJson());
      expect(inputBack.selections, {'washes': 'G2'});
      expect(inputBack.paymentMethod, CounterPaymentMethod.cardTerminal);
      expect(input.toJson()['payment_method'], 'card_terminal');
      expect(CounterPaymentMethod.cardTerminal.stored, MembershipPaymentMethod.card);
    });

    test('price quote and booking membership block', () {
      final quote = store.quoteBooking(
        outletId: DemoStore.outletMenlyn,
        serviceId: DemoStore.svcAutoDetailInterior,
        vehicle: vehicle(DemoStore.vehCorolla),
        addonServiceIds: const [DemoStore.svcAddonOdour],
      );
      final json = quote.toJson();
      expect(json['membership'], {
        'plan_code': 'gold',
        'plan_name': 'Gold',
        'benefit': 'discount',
        'entitlement_code': null,
        'remaining_after': null,
        'period_end': isNotNull,
      });
      expect(PriceQuote.fromJson(json).toJson(), json);
      expect(PriceQuote.fromJson(json).membership!.isDiscount, isTrue);
      final block = BookingMembership.fromJson({
        'plan_code': 'gold',
        'plan_name': 'Gold',
        'benefit': 'included',
        'entitlement_code': 'G1',
        'remaining_after': 2,
        'period_end': '2026-10-05T08:00:00Z',
      });
      expect(block.isIncluded, isTrue);
      expect(BookingMembership.fromJson(block.toJson()), block);
      final b = Booking.fromJson({
        'id': 'b1',
        'ref': 'SPK-2026-0001',
        'customer_id': 'seed_thabo',
        'status': 'confirmed',
        'slot_start': '2026-10-01T08:00:00Z',
        'slot_end': '2026-10-01T09:00:00Z',
        'price_cents': 15000,
        'discount_cents': 15000,
        'total_cents': 0,
        'discount_label': 'Included in Gold · 2 of 4 left',
        'membership_id': DemoStore.membershipThabo,
        'entitlement_id': 'c3000000-0000-4000-8000-000000000001',
        'membership_benefit': 'included',
        'membership': block.toJson(),
      });
      expect(b.isIncluded, isTrue);
      expect(b.membership!.remainingAfter, 2);
      expect(Booking.fromJson(b.toJson()).membershipBenefit, MembershipBenefit.included);
      expect(LoyaltyTier.fromDb('black'), LoyaltyTier.black);
      expect(LoyaltyTier.black.label, 'Black');
      expect(LoyaltyTier.platinum.next, LoyaltyTier.black);
      expect(MembershipStatus.fromDb('past_due'), MembershipStatus.pastDue);
      expect(MembershipStatus.pastDue.isLive, isTrue);
      expect(MembershipStatus.pastDue.benefitsActive, isFalse);
    });
  });
}
