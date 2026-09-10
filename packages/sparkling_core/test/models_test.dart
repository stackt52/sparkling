import 'package:flutter_test/flutter_test.dart';
import 'package:sparkling_core/sparkling_core.dart';

const _referencePayload = {
  'id': '10000000-0000-4000-8000-000000000001',
  'ref': 'SPK-2026-0091',
  'status': 'in_service',
  'customer_id': 'seed_thabo',
  'slot_start': '2026-09-08T08:00:00Z',
  'slot_end': '2026-09-08T09:00:00Z',
  'price_cents': 22000,
  'discount_cents': 2200,
  'total_cents': 19800,
  'discount_label': 'Gold −10%',
  'points_pending': 20,
  'outlet': {'id': 'o1', 'name': 'Sparkling Sandton', 'rating': 4.8},
  'service': {
    'id': 's1',
    'name': 'Full Valet',
    'duration_minutes': 60,
    'category': 'car_wash',
  },
  'vehicle': {
    'id': 'v1',
    'registration_no': 'KL 45 MN GP',
    'make': 'Toyota',
    'model': 'Corolla Cross',
  },
  'work_order': {
    'id': 'w1',
    'ref': 'WO-2026-4821',
    'status': 'in_progress',
    'stage': 3,
    'stage_count': 6,
    'progress_pct': 58,
    'assignee_name': 'Pieter van der Merwe',
    'bay': 'Bay 2',
    'eta_at': '2026-09-08T08:55:00Z',
    'updated_at': '2026-09-08T08:30:00Z',
  },
  'timeline': [
    {
      'key': 'checked_in',
      'title': 'Checked in',
      'state': 'done',
      'at': '2026-09-08T08:05:00Z',
    },
    {
      'key': 'prewash',
      'title': 'Pre-wash inspection',
      'state': 'done',
      'at': '2026-09-08T08:12:00Z',
    },
    {'key': 'exterior', 'title': 'Exterior wash & rinse', 'state': 'current'},
    {'key': 'interior', 'title': 'Interior vacuum & dash', 'state': 'pending'},
  ],
  'payment': {
    'id': 'p1',
    'status': 'successful',
    'receipt_no': 'RCP-70001',
    'amount_cents': 19800,
  },
};

void main() {
  group('Booking', () {
    test('parses the API.md reference payload and round-trips', () {
      final b = Booking.fromJson(Map<String, dynamic>.from(_referencePayload));
      expect(b.ref, 'SPK-2026-0091');
      expect(b.status, BookingStatus.inService);
      expect(b.isInService, isTrue);
      expect(b.canCancel, isFalse);
      expect(b.totalCents, 19800);
      expect(b.discountLabel, 'Gold −10%');
      expect(b.outlet?.name, 'Sparkling Sandton');
      expect(b.outletId, 'o1');
      expect(b.service?.category, ServiceCategory.carWash);
      expect(b.vehicle?.shortName, 'Corolla Cross');
      expect(b.title, 'Full Valet — Corolla Cross');
      expect(b.workOrder?.ref, 'WO-2026-4821');
      expect(b.workOrder?.progress, closeTo(0.58, 0.001));
      expect(b.workOrder?.assigneeFirstName, 'Pieter');
      expect(b.timeline.length, 4);
      expect(b.timeline[2].state, TimelineEntryState.current);
      expect(b.payment?.status.isVerified, isTrue);
      expect(b.isPaid, isTrue);

      final again = Booking.fromJson(b.toJson());
      expect(again, b);
      expect(again.toJson()['slot_start'], '2026-09-08T08:00:00.000Z');
    });

    test('copyWith and BookingInput', () {
      final b = Booking.fromJson(Map<String, dynamic>.from(_referencePayload));
      expect(
        b.copyWith(status: BookingStatus.completed).status,
        BookingStatus.completed,
      );
      expect(b.copyWith(clearWorkOrder: true).workOrder, isNull);
      final input = BookingInput(
        vehicleId: 'v1',
        outletId: 'o1',
        serviceId: 's1',
        slotStart: DateTime.utc(2026, 9, 9, 7),
        clientOpId: 'op-1',
      );
      expect(input.toJson(), {
        'vehicle_id': 'v1',
        'outlet_id': 'o1',
        'service_id': 's1',
        'slot_start': '2026-09-09T07:00:00.000Z',
        'client_op_id': 'op-1',
      });
    });
  });

  group('Enums', () {
    test('db round-trip for every enum', () {
      for (final v in BookingStatus.values) {
        expect(BookingStatus.fromDb(v.db), v);
      }
      for (final v in WorkStatus.values) {
        expect(WorkStatus.fromDb(v.db), v);
      }
      for (final v in StepType.values) {
        expect(StepType.fromDb(v.db), v);
      }
      for (final v in PaymentStatus.values) {
        expect(PaymentStatus.fromDb(v.db), v);
      }
      for (final v in InventoryReason.values) {
        expect(InventoryReason.fromDb(v.db), v);
      }
      expect(WorkStatus.fromDb('in_progress'), WorkStatus.inProgress);
      expect(StepType.supervisorVerify.db, 'supervisor_verify');
      expect(BookingStatus.fromDb('nope'), BookingStatus.pending);
    });

    test('work status state machine', () {
      expect(WorkStatus.queued.canTransitionTo(WorkStatus.assigned), isTrue);
      expect(WorkStatus.inProgress.canTransitionTo(WorkStatus.blocked), isTrue);
      expect(WorkStatus.blocked.canTransitionTo(WorkStatus.inProgress), isTrue);
      expect(WorkStatus.completed.canTransitionTo(WorkStatus.verified), isTrue);
      expect(
        WorkStatus.verified.canTransitionTo(WorkStatus.inProgress),
        isFalse,
      );
      expect(WorkStatus.queued.canTransitionTo(WorkStatus.verified), isFalse);
    });
  });

  group('Money & dates', () {
    test('formatZar', () {
      expect(Money.formatZar(19800), 'R 198.00');
      expect(Money.formatZar(385000), 'R 3 850.00');
      expect(Money.formatZar(123456789), 'R 1 234 567.89');
      expect(Money.formatZar(-500), '−R 5.00');
      expect(Money.formatZarCompact(12000), 'R120');
      expect(Money.parseZar('R 198.00'), 19800);
      expect(Money.parseZar('3 850,50'), 385050);
    });

    test('formatPoints / delta', () {
      expect(Money.formatPoints(1450), '1 450');
      expect(Money.formatPointsLabel(2450), '2 450 pts');
      expect(Money.formatDelta(20), '+20');
      expect(Money.formatDelta(-800), '−800');
      expect(Money.formatTrendPct(12), '+12%');
    });

    test('relativeSlot', () {
      final now = DateTime(2026, 9, 8, 9, 41);
      expect(
        SparklingDates.relativeSlot(DateTime(2026, 9, 8, 10, 30), now: now),
        'Today 10:30',
      );
      expect(
        SparklingDates.relativeSlot(DateTime(2026, 9, 9, 9), now: now),
        'Tomorrow 09:00',
      );
      expect(
        SparklingDates.ago(now.subtract(const Duration(minutes: 2)), now: now),
        '2 min ago',
      );
    });
  });

  group('WorkOrderDetail', () {
    test('progress, locking and timeline derivation', () {
      final detail = WorkOrderDetail.fromJson({
        'work_order': {
          'id': 'w',
          'ref': 'WO-1',
          'outlet_id': 'o',
          'vehicle_id': 'v',
          'customer_id': 'c',
          'service_id': 's',
          'status': 'in_progress',
          'started_at': '2026-09-08T08:05:00Z',
        },
        'template': {
          'id': 't',
          'name': 'Express',
          'category': 'car_wash',
          'steps': [
            {'key': 'a', 'title': 'A', 'type': 'confirm', 'required': true},
            {
              'key': 'b',
              'title': 'B',
              'type': 'numeric',
              'required': true,
              'min': 1,
              'max': 3,
            },
            {
              'key': 'sup',
              'title': 'Supervisor',
              'type': 'supervisor_verify',
              'required': true,
            },
          ],
        },
        'results': [
          {
            'work_order_id': 'w',
            'step_key': 'a',
            'status': 'done',
            'completed_at': '2026-09-08T08:10:00Z',
          },
        ],
      });
      expect(detail.progress.label, '1/3 steps');
      expect(detail.currentStep?.key, 'b');
      expect(detail.requiredStepsPassed, isFalse);
      expect(detail.isStepLocked(detail.steps.last), isTrue);
      expect(detail.steps[1].validate(value: 5), contains('at most'));
      expect(detail.steps[1].validate(value: 2), isNull);
      final tl = detail.toTimeline();
      expect(tl.first.key, 'checked_in');
      expect(tl.first.state, TimelineEntryState.done);
      expect(tl[1].state, TimelineEntryState.done);
      expect(tl[2].state, TimelineEntryState.current);
      expect(tl.last.key, 'ready');
      expect(tl.last.state, TimelineEntryState.pending);
    });
  });

  group('Page', () {
    test('parses envelope and appends', () {
      final p = Page.fromJson({
        'data': [
          {'id': '1'},
          {'id': '2'},
        ],
        'next_cursor': 'abc',
      }, (m) => m['id'] as String);
      expect(p.items, ['1', '2']);
      expect(p.hasMore, isTrue);
      final merged = p.append(
        Page.fromJson({
          'data': [
            {'id': '3'},
          ],
          'next_cursor': null,
        }, (m) => m['id'] as String),
      );
      expect(merged.items, ['1', '2', '3']);
      expect(merged.hasMore, isFalse);
    });
  });

  group('Loyalty / inventory helpers', () {
    test('LoyaltyAccountSummary progress', () {
      final s = LoyaltyAccountSummary.fromJson({
        'account': {
          'customer_id': 'c',
          'tier': 'gold',
          'balance_points': 1450,
          'lifetime_points': 1800,
        },
        'tier_config': [
          {
            'tier': 'silver',
            'name': 'Silver',
            'min_points': 0,
            'max_points': 499,
          },
          {
            'tier': 'gold',
            'name': 'Gold',
            'min_points': 500,
            'max_points': 1999,
            'discount_pct': 10,
          },
          {'tier': 'platinum', 'name': 'Platinum', 'min_points': 2000},
        ],
        'next_tier': {'name': 'Platinum', 'points_needed': 200},
        'published_version': 14,
      });
      expect(s.tier, LoyaltyTier.gold);
      expect(s.nextTierLabel, '200 pts to Platinum');
      expect(s.progressToNextTier, closeTo((1800 - 500) / 1500, 0.001));
      expect(s.currentTierConfig?.discountPct, 10);
    });

    test('InventoryItem level', () {
      final low = InventoryItem.fromJson({
        'id': 'i',
        'outlet_id': 'o',
        'sku': 'S',
        'name': 'Wax',
        'on_hand': 3,
        'reorder_threshold': 6,
        'open_alert': {
          'id': 'a',
          'item_id': 'i',
          'outlet_id': 'o',
          'level': 'low',
          'status': 'open',
        },
      });
      expect(low.level, StockLevel.low);
      expect(low.alert?.level, AlertLevel.low);
      expect(low.levelLabel, '3 of 12 · min 6');
      expect(low.copyWith(onHand: 0).level, StockLevel.out);
      expect(low.copyWith(onHand: 9).level, StockLevel.ok);
    });

    test('Profile initials and Badge colour', () {
      expect(
        const Profile(
          id: 'x',
          role: UserRole.customer,
          fullName: 'Thabo Nkosi',
        ).initials,
        'TN',
      );
      expect(
        const Badge(
          id: 'b',
          code: 'C',
          name: 'N',
          colour: '#E2BA5F',
        ).colourValue,
        0xFFE2BA5F,
      );
    });
  });

  group('Pickup OTP & delivery fields', () {
    test('WorkOrderSummary / WorkOrder round-trip pickup fields', () {
      final summary = WorkOrderSummary.fromJson({
        'id': 'w1',
        'ref': 'WO-2026-4820',
        'status': 'verified',
        'pickup_otp': '73104',
        'pickup_otp_verified_at': null,
        'collected_at': null,
      });
      expect(summary.pickupOtp, '73104');
      expect(summary.awaitingCollection, isTrue);
      expect(summary.toJson()['pickup_otp'], '73104');
      final collected = summary.copyWith(
        collectedAt: DateTime.utc(2026, 9, 9, 8, 30),
        clearPickupOtp: true,
      );
      expect(collected.awaitingCollection, isFalse);
      expect(collected.toJson().containsKey('pickup_otp'), isFalse);
      expect(collected.toJson()['collected_at'], '2026-09-09T08:30:00.000Z');

      final booking = Booking.fromJson({
        'id': 'b1',
        'ref': 'SPK-2026-0098',
        'customer_id': 'c',
        'status': 'completed',
        'slot_start': '2026-09-09T06:00:00Z',
        'slot_end': '2026-09-09T06:20:00Z',
        'work_order': summary.toJson(),
      });
      expect(booking.isReadyForCollection, isTrue);
      expect(booking.pickupOtp, '73104');
      expect(
        booking.copyWith(status: BookingStatus.inService).pickupOtp,
        isNull,
      );

      final wo = WorkOrder.fromJson({
        'id': 'w1',
        'ref': 'WO-2026-4820',
        'outlet_id': 'o',
        'vehicle_id': 'v',
        'customer_id': 'c',
        'service_id': 's',
        'status': 'verified',
        'pickup_otp_verified_at': '2026-09-09T08:30:00Z',
        'collected_at': '2026-09-09T08:30:00Z',
      });
      expect(wo.isCollected, isTrue);
      expect(wo.awaitingCollection, isFalse);
      expect(wo.toJson()['collected_at'], '2026-09-09T08:30:00.000Z');
      expect(WorkOrder.fromJson(wo.toJson()), wo);

      final result = PickupVerifyResult.fromJson({
        'verified': true,
        'collected_at': '2026-09-09T08:30:00Z',
      });
      expect(result.verified, isTrue);
      expect(result.collectedAt, DateTime.utc(2026, 9, 9, 8, 30));
    });

    test('ApiException exposes attempts_left for invalid_otp', () {
      final e = ApiException.fromEnvelope({
        'error': {
          'code': 'invalid_otp',
          'message': 'Wrong code',
          'details': {'attempts_left': 3},
        },
      }, statusCode: 409);
      expect(e.isInvalidOtp, isTrue);
      expect(e.attemptsLeft, 3);
      expect(e.isConflict, isTrue);
      const plain = ApiException(code: 'rate_limited', message: 'x');
      expect(plain.attemptsLeft, isNull);
      expect(plain.isInvalidOtp, isFalse);
    });

    test('AppNotification carries provider_status / delivered_at', () {
      final n = AppNotification.fromJson({
        'id': 'n1',
        'recipient_id': 'c',
        'channel': 'whatsapp',
        'template_key': 'pickup_otp',
        'body': 'OTP 73104',
        'status': 'sent',
        'provider_status': 'delivered',
        'delivered_at': '2026-09-09T08:21:00Z',
        'attempts': 1,
      });
      expect(n.isDelivered, isTrue);
      expect(n.deliveredAt, DateTime.utc(2026, 9, 9, 8, 21));
      expect(n.toJson()['provider_status'], 'delivered');
      expect(AppNotification.fromJson(n.toJson()), n);
      final failed = n.copyWith(
        status: NotifyStatus.failed,
        providerStatus: 'undelivered',
        error: '63016 outside 24h session',
        attempts: 2,
      );
      expect(failed.isFailed, isTrue);
      expect(failed.attempts, 2);
      expect(failed.error, contains('63016'));
      expect(failed.copyWith(clearError: true).error, isNull);
      expect(
        AppNotification.fromJson({
          'id': 'n2',
          'recipient_id': 'c',
          'channel': 'push',
          'template_key': 'x',
          'body': 'b',
          'status': 'sent',
        }).isDelivered,
        isFalse,
      );
    });
  });
}
