import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce_flutter/hive_flutter.dart';
import 'package:sparkling_core/sparkling_core.dart';

void main() {
  late Directory dir;
  late Repositories repos;
  late DemoStore store;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('sparkling_demo_');
    HiveStore.reset();
    store = DemoStore(currentUser: DemoPersonas.customer);
    repos = await SparklingCore.bootstrap(
      demo: true,
      hivePath: dir.path,
      demoStore: store,
      clientApp: 'customer',
    );
  });

  tearDown(() async {
    await repos.dispose();
    store.dispose();
    await Hive.deleteFromDisk();
    await Hive.close();
    HiveStore.reset();
    if (dir.existsSync()) dir.deleteSync(recursive: true);
  });

  group('Customer (Thabo Nkosi)', () {
    test('profile, vehicles, bookings and loyalty mirror the seed', () async {
      expect(repos.demo, isTrue);
      expect(repos.auth.currentUser?.uid, 'seed_thabo');
      final me = await repos.customer.me();
      expect(me.fullName, 'Thabo Nkosi');
      expect(me.initials, 'TN');

      final vehicles = await repos.customer.vehicles();
      expect(vehicles.map((v) => v.registrationNo), [
        'KL 45 MN GP',
        'CJ 12 PZ GP',
      ]);
      expect(vehicles.first.discVerified, isTrue);
      expect(vehicles.last.source, VehicleSource.manual);

      final bookings = await repos.customer.bookings();
      expect(
        bookings.map((b) => b.ref),
        containsAll([
          'SPK-${DateTime.now().year}-0091',
          'SPK-${DateTime.now().year}-0094',
        ]),
      );
      final inService = bookings.firstWhere(
        (b) => b.status == BookingStatus.inService,
      );
      expect(inService.outlet?.name, 'Sparkling Sandton');
      expect(inService.service?.name, 'Full Valet');
      expect(inService.totalCents, 19800);
      expect(inService.discountLabel, 'Gold −10%');
      expect(inService.workOrder?.ref, 'WO-${DateTime.now().year}-4821');
      expect(inService.workOrder?.stageCount, 7);
      expect(inService.workOrder?.stage, 5);
      expect(inService.workOrder?.progressPct, 57);
      expect(inService.workOrder?.assigneeFirstName, 'Pieter');
      expect(inService.workOrder?.bay, 'Bay 2');

      final detail = await repos.customer.booking(inService.id);
      expect(detail.timeline.first.title, 'Checked in');
      expect(
        detail.timeline.where((t) => t.state == TimelineEntryState.done),
        hasLength(5),
      );
      expect(
        detail.timeline
            .firstWhere((t) => t.state == TimelineEntryState.current)
            .title,
        'Windows inside & out',
      );
      expect(detail.payment?.receiptNo, 'RCP-70001');
      expect(detail.isPaid, isTrue);

      final loyalty = await repos.loyalty.account();
      expect(loyalty.tier, LoyaltyTier.gold);
      expect(loyalty.balance, 1450);
      expect(loyalty.nextTierLabel, '200 pts to Platinum');
      final ledger = await repos.loyalty.ledger();
      expect(ledger.items.first.reference, 'SPK-${DateTime.now().year}-0078');
      expect(
        ledger.items.where((e) => e.type == LedgerType.redeem).single.delta,
        -350,
      );
      final rewards = await repos.loyalty.rewards();
      expect(rewards.map((r) => r.name), isNot(contains('Priority bay')));
      expect(rewards.map((r) => r.name), contains('Full Valet upgrade'));

      final quotes = await repos.customer.quotations();
      final quoted = quotes.firstWhere(
        (q) => q.status == QuotationStatus.quoted,
      );
      expect(quoted.ref, 'QT-${DateTime.now().year}-0041');
      expect(quoted.amountCents, 385000);
      expect(Money.formatZar(quoted.amountCents!), 'R 3 850.00');

      final notes = await repos.notifications.list();
      expect(
        notes.items.map((n) => n.templateKey),
        containsAll(['service_started', 'quote_ready']),
      );
      expect(await repos.notifications.unreadCount(), 2);
    });

    test(
      'catalogue: outlets, services with outlet pricing, availability',
      () async {
        final outlets = await repos.catalogue.outlets();
        expect(outlets.map((o) => o.name), [
          'Sparkling Sandton',
          'Sparkling Rosebank',
          'Sparkling Centurion',
        ]);
        final services = await repos.catalogue.outletServices(
          DemoStore.outletSandton,
        );
        final valet = services.firstWhere((s) => s.name == 'Full Valet');
        expect(valet.priceCents, 24000);
        expect(valet.pointsEstimate, 24);
        final centurion = await repos.catalogue.outletServices(
          DemoStore.outletCenturion,
        );
        expect(
          centurion.firstWhere((s) => s.name == 'Panel respray').isAvailable,
          isFalse,
        );

        final tomorrow = DateTime.now().add(const Duration(days: 1));
        final monday = tomorrow.weekday == DateTime.sunday
            ? tomorrow.add(const Duration(days: 1))
            : tomorrow;
        final slots = await repos.catalogue.availability(
          outletId: DemoStore.outletSandton,
          serviceId: DemoStore.svcExpress,
          date: monday,
        );
        expect(slots, isNotEmpty);
        expect(slots.first.capacity, 4);
        expect(slots.every((s) => s.available), isTrue);
      },
    );

    test(
      'booking flow: create → pay (sandbox) → confirmed, streams emit',
      () async {
        final emissions = <int>[];
        final sub = repos.customer.watchBookings().listen(
          (b) => emissions.add(b.length),
        );
        await Future<void>.delayed(const Duration(milliseconds: 10));

        final slotDay = DateTime.now().add(const Duration(days: 2));
        final day = slotDay.weekday == DateTime.sunday
            ? slotDay.add(const Duration(days: 1))
            : slotDay;
        final slots = await repos.catalogue.availability(
          outletId: DemoStore.outletSandton,
          serviceId: DemoStore.svcValet,
          date: day,
        );
        final booking = await repos.customer.createBooking(
          BookingInput(
            vehicleId: DemoStore.vehCorolla,
            outletId: DemoStore.outletSandton,
            serviceId: DemoStore.svcValet,
            slotStart: slots.first.slotStart,
            clientOpId: 'op-new-1',
          ),
        );
        expect(booking.ref, 'SPK-${DateTime.now().year}-0097');
        expect(booking.status, BookingStatus.pending);
        expect(booking.priceCents, 24000);
        expect(booking.discountCents, 2400);
        expect(booking.totalCents, 21600);
        expect(booking.discountLabel, 'Gold −10%');
        expect(booking.pointsPending, 22);

        // Idempotent replay returns the same booking.
        final replay = await repos.customer.createBooking(
          BookingInput(
            vehicleId: DemoStore.vehCorolla,
            outletId: DemoStore.outletSandton,
            serviceId: DemoStore.svcValet,
            slotStart: slots.first.slotStart,
            clientOpId: 'op-new-1',
          ),
        );
        expect(replay.id, booking.id);

        final methods = await repos.customer.paymentMethods();
        expect(methods.first.displayLabel, 'Visa •••• 4242');
        final intent = await repos.customer.createPaymentIntent(
          bookingId: booking.id,
          methodId: methods.first.id,
        );
        expect(intent.payment.status, PaymentStatus.pending);
        expect(intent.payment.amountCents, 21600);
        final paid = await repos.customer.confirmSandboxPayment(
          intent.payment.id,
        );
        expect(paid.status, PaymentStatus.successful);
        expect(paid.receiptNo, 'RCP-70006');
        final confirmed = await repos.customer.booking(booking.id);
        expect(confirmed.status, BookingStatus.confirmed);
        expect(confirmed.isPaid, isTrue);

        await Future<void>.delayed(const Duration(milliseconds: 10));
        expect(emissions.first, 4);
        expect(emissions.last, 5);
        await sub.cancel();

        // Cancel is allowed before in_service; in-service booking is not.
        final cancelled = await repos.customer.cancelBooking(
          booking.id,
          reason: 'Changed plans',
        );
        expect(cancelled.status, BookingStatus.cancelled);
        await expectLater(
          repos.customer.cancelBooking(DemoStore.bookingInService),
          throwsA(
            isA<ApiException>().having(
              (e) => e.code,
              'code',
              'invalid_transition',
            ),
          ),
        );
      },
    );

    test('duplicate vehicle is a 409 conflict with existing_vehicle_id unless forced', () async {
      await expectLater(
        repos.customer.addVehicle(
          const VehicleInput(registrationNo: 'kl45mngp'),
        ),
        throwsA(
          isA<ApiException>().having(
            (e) => e.existingVehicleId,
            'existing',
            DemoStore.vehCorolla,
          ),
        ),
      );
      final scan = Pdf417DiscParser.parse(
        Pdf417DiscParser.sampleDiscPayload(
          registration: 'HX42KLGP',
          vin: 'JTDKN3DU0A0123456',
        ),
      );
      final v = await repos.customer.addVehicle(scan.toVehicleInput());
      expect(v.registrationNo, 'HX 42 KL GP');
      expect(v.discVerified, isTrue);
      expect(v.discHash, scan.rawHash);
      expect((await repos.customer.vehicles()).length, 3);
    });

    test('quote request and decision', () async {
      final q = await repos.customer.createQuotation(
        const QuotationInput(
          vehicleId: DemoStore.vehPolo,
          outletId: DemoStore.outletSandton,
          category: 'Scratch',
          description: 'Scratch along the rear door from a trolley.',
          clientOpId: 'op-q1',
        ),
      );
      expect(q.ref, 'QT-${DateTime.now().year}-0043');
      expect(q.status, QuotationStatus.requested);
      await expectLater(
        repos.customer.decideQuotation(q.id, accept: true),
        throwsA(
          isA<ApiException>().having(
            (e) => e.code,
            'code',
            'invalid_transition',
          ),
        ),
      );
      final accepted = await repos.customer.decideQuotation(
        DemoStore.quotationQuoted,
        accept: true,
      );
      expect(accepted.status, QuotationStatus.accepted);
    });

    test(
      'redeem reward posts a ledger entry and updates the account stream',
      () async {
        final accounts = <int>[];
        final sub = repos.loyalty.watchAccount().listen(
          (a) => accounts.add(a.balance),
        );
        await Future<void>.delayed(const Duration(milliseconds: 10));
        final reward = (await repos.loyalty.rewards()).firstWhere(
          (r) => r.name == 'Full Valet upgrade',
        );
        final redemption = await repos.loyalty.redeem(reward.id);
        expect(redemption.code, 'RW-1183');
        expect(redemption.balanceAfter, 550);
        await Future<void>.delayed(const Duration(milliseconds: 10));
        expect(accounts, [1450, 550]);
        await expectLater(
          repos.loyalty.redeem(reward.id),
          throwsA(
            isA<ApiException>().having(
              (e) => e.isValidation,
              'validation',
              isTrue,
            ),
          ),
        );
        await sub.cancel();
      },
    );
  });

  group('Staff (Pieter → Johan)', () {
    test('tasks, checklist step, transitions and verification side effects', () async {
      await repos.auth.signInWithEmail('pieter@sparkling.co.za', 'x');
      await Future<void>.delayed(const Duration(milliseconds: 5));
      expect(store.uid, 'seed_pieter');

      final mine = await repos.staff.tasks(scope: TaskScope.mine);
      final task = mine.single;
      expect(task.workOrder?.ref, 'WO-${DateTime.now().year}-4821');
      expect(task.workOrder?.progress.label, '4/7 steps');
      expect(task.workOrder?.title, 'Full Valet — Toyota Corolla Cross');
      expect(task.priority, 1);
      final queue = await repos.staff.tasks(scope: TaskScope.queue);
      expect(
        queue.map((t) => t.workOrder?.ref),
        containsAll([
          'WO-${DateTime.now().year}-4823',
          'WO-${DateTime.now().year}-4824',
        ]),
      );
      expect(
        queue.firstWhere((t) => t.isBlocked).blockedReason,
        contains('interior shampoo'),
      );
      expect(
        (await repos.staff.tasks(scope: TaskScope.done)).single.workOrder?.ref,
        'WO-${DateTime.now().year}-4822',
      );

      final detail = await repos.staff.workOrder(task.workOrderId);
      expect(detail.stepsDone, 4);
      expect(detail.currentStep?.key, 'windows');
      expect(detail.isStepLocked(detail.steps.last), isTrue);
      expect(detail.events, hasLength(2));

      // Supervisor step locked for technician and while required steps pending.
      await expectLater(
        repos.staff.submitStep(
          task.workOrderId,
          'supervisor',
          const StepResultInput(status: StepStatus.done, clientOpId: 'op-s0'),
        ),
        throwsA(isA<ApiException>()),
      );
      // Numeric validation.
      await expectLater(
        repos.staff.submitStep(
          task.workOrderId,
          'tyre_pressure',
          const StepResultInput(
            status: StepStatus.done,
            clientOpId: 'op-s1',
            value: 9,
          ),
        ),
        throwsA(
          isA<ApiException>().having(
            (e) => e.message,
            'message',
            contains('at most'),
          ),
        ),
      );
      final windows = await repos.staff.submitStep(
        task.workOrderId,
        'windows',
        const StepResultInput(status: StepStatus.done, clientOpId: 'op-s2'),
      );
      expect(windows.isDone, isTrue);
      expect(windows.actorName, 'Pieter van der Merwe');
      final tyre = await repos.staff.submitStep(
        task.workOrderId,
        'tyre_pressure',
        const StepResultInput(
          status: StepStatus.done,
          clientOpId: 'op-s3',
          value: 2.4,
        ),
      );
      expect(tyre.value, 2.4);
      final after = await repos.staff.workOrder(task.workOrderId);
      expect(after.progress.label, '6/7 steps');
      expect(after.requiredStepsPassed, isTrue);

      // Invalid transition (in_progress → verified), completion, then RBAC.
      await expectLater(
        repos.staff.transitionTask(
          task,
          const TaskTransitionInput(
            to: WorkStatus.verified,
            clientOpId: 'op-t0',
          ),
        ),
        throwsA(
          isA<ApiException>().having(
            (e) => e.code,
            'code',
            'invalid_transition',
          ),
        ),
      );
      final completed = await repos.staff.transitionTask(
        task,
        const TaskTransitionInput(
          to: WorkStatus.completed,
          clientOpId: 'op-t1',
        ),
      );
      expect(completed.status, WorkStatus.completed);
      // A technician may not verify (STF-033).
      await expectLater(
        repos.staff.transitionTask(
          completed,
          const TaskTransitionInput(
            to: WorkStatus.verified,
            clientOpId: 'op-t1b',
          ),
        ),
        throwsA(isA<ApiException>().having((e) => e.code, 'code', 'forbidden')),
      );
      await expectLater(
        repos.staff.transitionTask(
          completed,
          const TaskTransitionInput(
            to: WorkStatus.blocked,
            clientOpId: 'op-t2',
            reason: 'x',
          ),
        ),
        throwsA(
          isA<ApiException>().having(
            (e) => e.code,
            'code',
            'invalid_transition',
          ),
        ),
      );

      // Supervisor verifies → booking completed, points posted (idempotent), notification.
      await repos.auth.signInWithEmail('johan@sparkling.co.za', 'x');
      await Future<void>.delayed(const Duration(milliseconds: 5));
      await repos.staff.submitStep(
        task.workOrderId,
        'supervisor',
        const StepResultInput(status: StepStatus.done, clientOpId: 'op-s4'),
      );
      final verified = await repos.staff.transitionTask(
        completed,
        const TaskTransitionInput(to: WorkStatus.verified, clientOpId: 'op-t3'),
      );
      expect(verified.status, WorkStatus.verified);
      final booking = store.bookings.firstWhere(
        (b) => b.id == DemoStore.bookingInService,
      );
      expect(booking.status, BookingStatus.completed);
      expect(store.balanceOf('seed_thabo'), 1470);
      expect(
        store.staffPoints.where((p) => p.key == 'task:${task.id}:completed'),
        hasLength(1),
      );
      expect(
        store.notifications.where(
          (n) =>
              n.recipientId == 'seed_thabo' && n.templateKey == 'service_ready',
        ),
        hasLength(1),
      );

      // Ops summary + assignment for the supervisor.
      final ops = await repos.staff.opsSummary(
        outletId: DemoStore.outletSandton,
      );
      expect(ops.counts.blocked, 1);
      expect(ops.counts.done, 2);
      expect(
        ops.needsAttention.map((a) => a.kind),
        containsAll([
          AttentionKind.blocked,
          AttentionKind.overdueSla,
          AttentionKind.outOfStock,
          AttentionKind.lowStock,
        ]),
      );
      final team = await repos.staff.team(outletId: DemoStore.outletSandton);
      expect(
        team.map((m) => m.firstName),
        containsAll(['Pieter', 'Lerato', 'Sipho', 'Johan']),
      );
      final queued = (await repos.staff.tasks(
        scope: TaskScope.queue,
        outletId: DemoStore.outletSandton,
      )).firstWhere((t) => t.status == WorkStatus.queued);
      final assigned = await repos.staff.assignTask(
        queued,
        assigneeId: 'seed_pieter',
        reason: 'Skill match',
      );
      expect(assigned.status, WorkStatus.assigned);
      expect(assigned.assigneeName, 'Pieter van der Merwe');

      final lb = await repos.staff.leaderboard(
        outletId: DemoStore.outletSandton,
      );
      expect(lb.rows.first.rank, 1);
      expect(lb.rows.map((r) => r.name), contains('Pieter van der Merwe'));
      expect(lb.badges, hasLength(6));
    });

    test('check-in creates a work order and task; quotation convert', () async {
      // Customer accepts the quoted QT-0041 first.
      await repos.customer.decideQuotation(
        DemoStore.quotationQuoted,
        accept: true,
      );
      await repos.auth.signInWithEmail('johan@sparkling.co.za', 'x');
      await Future<void>.delayed(const Duration(milliseconds: 5));
      final upcoming = (await repos.staff.outletBookings(
        outletId: DemoStore.outletRosebank,
        status: BookingStatus.pending,
      )).firstWhere((b) => b.workOrder == null);
      final checked = await repos.staff.checkinBooking(
        upcoming.id,
        bay: 'Bay 4',
        priority: 2,
      );
      expect(checked.status, BookingStatus.inService);
      expect(checked.workOrder?.ref, 'WO-${DateTime.now().year}-4825');
      expect(checked.workOrder?.bay, 'Bay 4');
      expect(checked.timeline.first.state, TimelineEntryState.pending);

      final accepted = store.quotations.firstWhere(
        (q) =>
            q.status == QuotationStatus.accepted &&
            !store.workOrders.any((w) => w.quotationId == q.id),
      );
      expect(accepted.ref, 'QT-${DateTime.now().year}-0041');
      final converted = await repos.staff.convertQuotation(accepted.id);
      expect(converted.status, QuotationStatus.converted);
      expect(store.workOrders.last.quotationId, accepted.id);
    });
  });

  group('Inventory', () {
    test('RBAC, no negative stock, alerts resolve, streams update', () async {
      await repos.auth.signInWithEmail('pieter@sparkling.co.za', 'x');
      await Future<void>.delayed(const Duration(milliseconds: 5));
      final items = await repos.inventory.items(
        outletId: DemoStore.outletSandton,
      );
      expect(items.first.name, 'Interior shampoo 5L');
      expect(items.first.level, StockLevel.out);
      expect(items.first.alert?.level, AlertLevel.out);
      expect(items.where((i) => i.needsAttention), hasLength(3));

      final wax = items.firstWhere((i) => i.sku == 'WAX-CRN');
      await expectLater(
        repos.inventory.logMovement(
          wax,
          const InventoryMovementInput(
            delta: 5,
            reason: InventoryReason.receive,
            clientOpId: 'op-i0',
          ),
        ),
        throwsA(
          isA<ApiException>().having((e) => e.isForbidden, 'forbidden', isTrue),
        ),
      );
      await expectLater(
        repos.inventory.logMovement(
          wax,
          const InventoryMovementInput(
            delta: -10,
            reason: InventoryReason.usage,
            clientOpId: 'op-i1',
          ),
        ),
        throwsA(
          isA<ApiException>().having(
            (e) => e.message,
            'message',
            contains('negative'),
          ),
        ),
      );
      final used = await repos.inventory.logMovement(
        wax,
        const InventoryMovementInput(
          delta: -1,
          reason: InventoryReason.usage,
          clientOpId: 'op-i2',
        ),
      );
      expect(used.onHand, 2);
      final requested = await repos.inventory.logMovement(
        wax,
        const InventoryMovementInput(
          delta: 0,
          reason: InventoryReason.reorderRequest,
          clientOpId: 'op-i3',
          note: 'Please order',
        ),
      );
      expect(requested.onHand, 2);
      expect(
        store.notifications
            .where((n) => n.templateKey == 'reorder_requested')
            .map((n) => n.recipientId),
        contains('seed_ayesha'),
      );

      await repos.auth.signInWithEmail('ayesha@sparkling.co.za', 'x');
      await Future<void>.delayed(const Duration(milliseconds: 5));
      final restocked = await repos.inventory.logMovement(
        used,
        const InventoryMovementInput(
          delta: 10,
          reason: InventoryReason.receive,
          clientOpId: 'op-i4',
        ),
      );
      expect(restocked.onHand, 12);
      expect(restocked.alert, isNull);
      final updated = await repos.inventory.updateItem(
        wax.id,
        reorderThreshold: 20,
      );
      expect(updated.alert?.level, AlertLevel.low);
    });
  });

  group('Offline queue in demo mode', () {
    test('queued operations are applied through the store on sync', () async {
      await repos.auth.signInWithEmail('pieter@sparkling.co.za', 'x');
      await Future<void>.delayed(const Duration(milliseconds: 5));
      await repos.offlineQueue.enqueue(SyncKinds.stepResult, {
        'work_order_id': DemoStore.woInService,
        'step_key': 'windows',
        'status': 'done',
      }, clientOpId: 'op-off-1');
      await repos.offlineQueue.enqueue(SyncKinds.stepResult, {
        'work_order_id': DemoStore.woInService,
        'step_key': 'supervisor',
        'status': 'done',
      }, clientOpId: 'op-off-2');
      await repos.offlineQueue.enqueue(SyncKinds.taskTransition, {
        'task_id': DemoStore.taskInService,
        'to': 'verified',
      }, clientOpId: 'op-off-3');
      final report = await repos.offlineQueue.sync();
      expect(report.succeeded, 1);
      expect(
        report.failed,
        1,
      ); // technician cannot complete the supervisor step → rejected
      expect(
        report.conflicted,
        1,
      ); // in_progress → verified is an invalid transition → conflict
      expect(
        store.stepResults
            .firstWhere(
              (r) =>
                  r.workOrderId == DemoStore.woInService &&
                  r.stepKey == 'windows',
            )
            .isDone,
        isTrue,
      );
      expect(
        repos.offlineQueue.failed.single.lastError,
        contains('supervisor'),
      );
      expect(
        repos.offlineQueue.conflicted.single.lastError,
        contains('Cannot move'),
      );
    });
  });

  testWidgets('RepositoriesScope provides the bundle', (tester) async {
    Repositories? found;
    await tester.pumpWidget(
      RepositoriesScope(
        repositories: repos,
        child: Builder(
          builder: (context) {
            found = context.repositories;
            return const SizedBox();
          },
        ),
      ),
    );
    expect(found, same(repos));
  });
}
