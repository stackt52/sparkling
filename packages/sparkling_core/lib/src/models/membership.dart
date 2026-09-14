/// Membership plans (monthly subscriptions) — `docs/MEMBERSHIPS.md`,
/// migration `0010_membership_plans`. The loyalty tier is the plan.
library;

import 'package:equatable/equatable.dart';

import 'enums.dart';
import 'json.dart';
import 'money.dart';
import 'payment.dart';

/// `memberships.status`
enum MembershipStatus implements SparklingEnum {
  pending('pending'),
  active('active'),
  pastDue('past_due'),
  cancelled('cancelled'),
  expired('expired');

  const MembershipStatus(this.db);
  @override
  final String db;
  static MembershipStatus fromDb(String? v) =>
      values.where((s) => s.db == v).firstOrNull ?? pending;

  String get label => switch (this) {
    pending => 'Awaiting payment',
    active => 'Active',
    pastDue => 'Payment due',
    cancelled => 'Cancelled',
    expired => 'Expired',
  };

  /// One live membership per customer: pending, active or past due.
  bool get isLive => this == pending || this == active || this == pastDue;

  /// Plan benefits (included washes, discounts) apply only while active.
  bool get benefitsActive => this == active;
}

/// `bookings.membership_benefit`
enum MembershipBenefit implements SparklingEnum {
  included('included'),
  discount('discount');

  const MembershipBenefit(this.db);
  @override
  final String db;
  static MembershipBenefit? fromDb(String? v) =>
      values.where((b) => b.db == v).firstOrNull;
}

/// `membership_plans.discount_scope`
enum DiscountScope implements SparklingEnum {
  planServices('plan_services'),
  otherServices('other_services'),
  allServices('all_services'),
  none('none');

  const DiscountScope(this.db);
  @override
  final String db;
  static DiscountScope fromDb(String? v) =>
      values.where((s) => s.db == v).firstOrNull ?? planServices;
}

/// `membership_plan_groups.selection`
enum GroupSelection implements SparklingEnum {
  chooseOne('choose_one'),
  all('all');

  const GroupSelection(this.db);
  @override
  final String db;
  static GroupSelection fromDb(String? v) =>
      values.where((s) => s.db == v).firstOrNull ?? chooseOne;
}

/// `membership_plan_entitlements.period`
enum EntitlementPeriod implements SparklingEnum {
  month('month'),
  year('year');

  const EntitlementPeriod(this.db);
  @override
  final String db;
  static EntitlementPeriod fromDb(String? v) =>
      values.where((p) => p.db == v).firstOrNull ?? month;

  String get label => this == month ? 'per month' : 'per year';
}

/// `memberships.payment_method`
enum MembershipPaymentMethod implements SparklingEnum {
  card('card'),
  cash('cash'),
  eft('eft'),
  sandbox('sandbox');

  const MembershipPaymentMethod(this.db);
  @override
  final String db;
  static MembershipPaymentMethod fromDb(String? v) =>
      values.where((m) => m.db == v).firstOrNull ?? card;

  String get label => switch (this) {
    card => 'Card',
    cash => 'Cash',
    eft => 'EFT',
    sandbox => 'Card (sandbox)',
  };
}

/// Counter payment for `POST /staff/customers/:id/membership` and
/// `…/record-payment` (`cash` | `card_terminal` | `eft`).
enum CounterPaymentMethod implements SparklingEnum {
  cash('cash'),
  cardTerminal('card_terminal'),
  eft('eft');

  const CounterPaymentMethod(this.db);
  @override
  final String db;
  static CounterPaymentMethod fromDb(String? v) =>
      values.where((m) => m.db == v).firstOrNull ?? cash;

  String get label => switch (this) {
    cash => 'Cash',
    cardTerminal => 'Card terminal',
    eft => 'EFT',
  };

  /// The `memberships.payment_method` value stored for this counter method.
  MembershipPaymentMethod get stored => switch (this) {
    cash => MembershipPaymentMethod.cash,
    cardTerminal => MembershipPaymentMethod.card,
    eft => MembershipPaymentMethod.eft,
  };
}

/// `membership_invoices.status`
enum MembershipInvoiceStatus implements SparklingEnum {
  pending('pending'),
  paid('paid'),
  failed('failed'),
  voided('void');

  const MembershipInvoiceStatus(this.db);
  @override
  final String db;
  static MembershipInvoiceStatus fromDb(String? v) =>
      values.where((s) => s.db == v).firstOrNull ?? pending;

  String get label => switch (this) {
    pending => 'Pending',
    paid => 'Paid',
    failed => 'Failed',
    voided => 'Void',
  };
}

/// `{ id, code, name, is_primary }` — a service that redeems an entitlement.
class EntitlementService extends Equatable {
  const EntitlementService({
    required this.id,
    required this.code,
    required this.name,
    this.isPrimary = false,
  });

  final String id;
  final String code;
  final String name;
  final bool isPrimary;

  factory EntitlementService.fromJson(Json json) => EntitlementService(
    id: str(json['id'] ?? json['service_id']),
    code: str(json['code']),
    name: str(json['name']),
    isPrimary: boolOf(json['is_primary']),
  );

  Json toJson() => {
    'id': id,
    'code': code,
    'name': name,
    'is_primary': isPrimary,
  };

  @override
  List<Object?> get props => [id, code, name, isPrimary];
}

/// One option of a plan group (`membership_plan_entitlements`), e.g.
/// `G1 = 4 × Sparkling Wash / month`.
class MembershipEntitlement extends Equatable {
  const MembershipEntitlement({
    required this.id,
    required this.code,
    required this.label,
    required this.quantity,
    this.period = EntitlementPeriod.month,
    this.sortOrder = 100,
    this.services = const [],
  });

  final String id;
  final String code;

  /// "4 × Sparkling Wash"
  final String label;
  final int quantity;
  final EntitlementPeriod period;
  final int sortOrder;

  /// Any of these redeems the entitlement (the primary one is listed first).
  final List<EntitlementService> services;

  EntitlementService? get primaryService =>
      services.where((s) => s.isPrimary).firstOrNull ?? services.firstOrNull;

  /// "Sparkling Wash" — the label without the `N ×` prefix and period suffix.
  String get itemName {
    var s = label.trim();
    s = s.replaceFirst(RegExp(r'^\d+\s*[×x]\s*'), '');
    s = s.replaceFirst(
      RegExp(r'\s*(per|/)\s*(month|annum|year)\s*$', caseSensitive: false),
      '',
    );
    return s.isEmpty ? (primaryService?.name ?? label) : s;
  }

  /// "Sparkling Washes" / "Auto Detail Completes" — naive English plural.
  String get itemNamePlural {
    final n = itemName;
    if (n.endsWith('sh') || n.endsWith('ch') || n.endsWith('s')) return '${n}es';
    return '${n}s';
  }

  /// Wording for [count] items: "1 Sparkling Wash" / "3 Sparkling Washes".
  String countLabel(int count) =>
      '$count ${count == 1 ? itemName : itemNamePlural}';

  bool coversServiceId(String serviceId) =>
      services.any((s) => s.id == serviceId);
  bool coversServiceCode(String code) => services.any((s) => s.code == code);

  factory MembershipEntitlement.fromJson(Json json) => MembershipEntitlement(
    id: str(json['id']),
    code: str(json['code']),
    label: str(json['label']),
    quantity: intOf(json['quantity']),
    period: EntitlementPeriod.fromDb(strOrNull(json['period'])),
    sortOrder: intOf(json['sort_order'], 100),
    services: asJsonList(json['services'])
        .map(EntitlementService.fromJson)
        .toList(),
  );

  Json toJson() => {
    'id': id,
    'code': code,
    'label': label,
    'quantity': quantity,
    'period': period.db,
    'sort_order': sortOrder,
    'services': services.map((s) => s.toJson()).toList(),
  };

  @override
  List<Object?> get props => [id, code, label, quantity, period, services];
}

/// A plan group (`membership_plan_groups`): `choose_one` (OR) or `all` (AND).
class MembershipPlanGroup extends Equatable {
  const MembershipPlanGroup({
    required this.id,
    required this.code,
    required this.name,
    this.selection = GroupSelection.chooseOne,
    this.sortOrder = 100,
    this.entitlements = const [],
  });

  final String id;
  final String code;
  final String name;
  final GroupSelection selection;
  final int sortOrder;
  final List<MembershipEntitlement> entitlements;

  bool get isChooseOne => selection == GroupSelection.chooseOne;

  MembershipEntitlement? entitlement(String code) =>
      entitlements.where((e) => e.code == code).firstOrNull;

  factory MembershipPlanGroup.fromJson(Json json) => MembershipPlanGroup(
    id: str(json['id']),
    code: str(json['code']),
    name: str(json['name']),
    selection: GroupSelection.fromDb(strOrNull(json['selection'])),
    sortOrder: intOf(json['sort_order'], 100),
    entitlements: asJsonList(json['entitlements'])
        .map(MembershipEntitlement.fromJson)
        .toList(),
  );

  Json toJson() => {
    'id': id,
    'code': code,
    'name': name,
    'selection': selection.db,
    'sort_order': sortOrder,
    'entitlements': entitlements.map((e) => e.toJson()).toList(),
  };

  @override
  List<Object?> get props => [id, code, name, selection, entitlements];
}

/// `membership_plans` row with its groups (`GET /memberships/plans`).
class MembershipPlan extends Equatable {
  const MembershipPlan({
    required this.id,
    required this.code,
    required this.tier,
    required this.name,
    required this.monthlyFeeCents,
    this.tagline,
    this.discountPct = 0,
    this.discountScope = DiscountScope.planServices,
    this.discountNote,
    this.color,
    this.sortOrder = 100,
    this.isActive = true,
    this.groups = const [],
    this.memberCount,
    this.mrrCents,
  });

  final String id;
  final String code;
  final LoyaltyTier tier;
  final String name;
  final String? tagline;
  final int monthlyFeeCents;
  final int discountPct;
  final DiscountScope discountScope;
  final String? discountNote;

  /// `gold` | `platinum` | `black` (UI palette key).
  final String? color;
  final int sortOrder;
  final bool isActive;
  final List<MembershipPlanGroup> groups;

  /// Admin only (`GET /admin/memberships/plans`).
  final int? memberCount;
  final int? mrrCents;

  /// "R 295 / month"
  String get feeLabel =>
      '${Money.formatZarCompact(monthlyFeeCents).replaceFirst('R', 'R ')} / month';

  /// Every entitlement across all groups (group order, then sort order).
  List<MembershipEntitlement> get entitlements => [
    for (final g in groups) ...g.entitlements,
  ];

  MembershipEntitlement? entitlement(String code) =>
      entitlements.where((e) => e.code == code).firstOrNull;

  MembershipEntitlement? entitlementById(String id) =>
      entitlements.where((e) => e.id == id).firstOrNull;

  MembershipPlanGroup? group(String code) =>
      groups.where((g) => g.code == code).firstOrNull;

  MembershipPlanGroup? groupOf(MembershipEntitlement e) =>
      groups.where((g) => g.entitlements.any((x) => x.id == e.id)).firstOrNull;

  /// Groups the member must pick an option for.
  List<MembershipPlanGroup> get chooseOneGroups =>
      groups.where((g) => g.isChooseOne).toList();

  /// `true` when any entitlement of the plan (selected or not) covers the
  /// service — the `other_services` discount scope excludes these.
  bool coversServiceCode(String code) =>
      entitlements.any((e) => e.coversServiceCode(code));
  bool coversServiceId(String id) =>
      entitlements.any((e) => e.coversServiceId(id));

  /// First option of every `choose_one` group.
  Map<String, String> defaultSelections() => {
    for (final g in chooseOneGroups)
      if (g.entitlements.isNotEmpty) g.code: g.entitlements.first.code,
  };

  /// Every `choose_one` group has a valid option in [selections].
  bool selectionsValid(Map<String, String> selections) => chooseOneGroups.every(
    (g) => g.entitlement(selections[g.code] ?? '') != null,
  );

  /// Entitlements in force for [selections] (chosen options + every option
  /// of `all` groups).
  List<MembershipEntitlement> selectedEntitlements(
    Map<String, String> selections,
  ) => [
    for (final g in groups)
      if (g.isChooseOne) ...[
        ?g.entitlement(selections[g.code] ?? ''),
      ] else
        ...g.entitlements,
  ];

  /// "4 × Sparkling Wash · 10% off other services"
  String benefitsSummary(Map<String, String> selections) => [
    ...selectedEntitlements(selections).map((e) => e.label),
    ?discountNote,
  ].join(' · ');

  factory MembershipPlan.fromJson(Json json) => MembershipPlan(
    id: str(json['id']),
    code: str(json['code']),
    tier: LoyaltyTier.fromDb(strOrNull(json['tier']) ?? strOrNull(json['code'])),
    name: str(json['name'], str(json['code'])),
    tagline: strOrNull(json['tagline']),
    monthlyFeeCents: intOf(json['monthly_fee_cents']),
    discountPct: intOf(json['discount_pct']),
    discountScope: DiscountScope.fromDb(strOrNull(json['discount_scope'])),
    discountNote: strOrNull(json['discount_note']),
    color: strOrNull(json['color']),
    sortOrder: intOf(json['sort_order'], 100),
    isActive: boolOf(json['is_active'], true),
    groups: asJsonList(json['groups']).map(MembershipPlanGroup.fromJson).toList(),
    memberCount: intOrNull(json['member_count']),
    mrrCents: intOrNull(json['mrr_cents']),
  );

  Json toJson() => compact({
    'id': id,
    'code': code,
    'tier': tier.db,
    'name': name,
    'tagline': tagline,
    'monthly_fee_cents': monthlyFeeCents,
    'discount_pct': discountPct,
    'discount_scope': discountScope.db,
    'discount_note': discountNote,
    'color': color,
    'sort_order': sortOrder,
    'is_active': isActive,
    'groups': groups.map((g) => g.toJson()).toList(),
    'member_count': memberCount,
    'mrr_cents': mrrCents,
  });

  @override
  List<Object?> get props => [
    id,
    code,
    tier,
    name,
    monthlyFeeCents,
    discountPct,
    discountScope,
    isActive,
    groups,
  ];
}

/// `GET /memberships/plans` → `{ data: Plan[], current_plan_code }`.
class MembershipPlanList extends Equatable {
  const MembershipPlanList({required this.plans, this.currentPlanCode});
  final List<MembershipPlan> plans;
  final String? currentPlanCode;

  MembershipPlan? byCode(String code) =>
      plans.where((p) => p.code == code).firstOrNull;

  factory MembershipPlanList.fromJson(Json json) => MembershipPlanList(
    plans: asJsonList(json['data'] ?? json['plans'])
        .map(MembershipPlan.fromJson)
        .toList(),
    currentPlanCode: strOrNull(json['current_plan_code']),
  );

  Json toJson() => compact({
    'data': plans.map((p) => p.toJson()).toList(),
    'current_plan_code': currentPlanCode,
  });

  @override
  List<Object?> get props => [plans, currentPlanCode];
}

/// `memberships` row.
class Membership extends Equatable {
  const Membership({
    required this.id,
    required this.ref,
    required this.customerId,
    required this.planId,
    required this.status,
    this.planCode,
    this.startedAt,
    this.currentPeriodStart,
    this.currentPeriodEnd,
    this.cancelAtPeriodEnd = false,
    this.cancelledAt,
    this.endedAt,
    this.nextPlanId,
    this.paymentMethod = MembershipPaymentMethod.card,
    this.clientOpId,
    this.createdBy,
    this.createdAt,
    this.updatedAt,
    this.pendingSync = false,
  });

  final String id;

  /// `MEM-2026-0001`
  final String ref;
  final String customerId;
  final String planId;

  /// Convenience when the API expands it.
  final String? planCode;
  final MembershipStatus status;
  final DateTime? startedAt;
  final DateTime? currentPeriodStart;
  final DateTime? currentPeriodEnd;
  final bool cancelAtPeriodEnd;
  final DateTime? cancelledAt;
  final DateTime? endedAt;

  /// Downgrade target applied at renewal.
  final String? nextPlanId;
  final MembershipPaymentMethod paymentMethod;
  final String? clientOpId;
  final String? createdBy;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  /// Optimistic copy while a counter enrolment (`membership.enrol`) is queued
  /// offline.
  final bool pendingSync;

  bool get isLive => status.isLive;
  bool get isActive => status == MembershipStatus.active;
  bool get isPastDue => status == MembershipStatus.pastDue;
  bool get isPending => status == MembershipStatus.pending;
  bool get benefitsActive => status.benefitsActive;

  /// Ends at the period end instead of renewing.
  bool get isEnding => cancelAtPeriodEnd && isLive;

  factory Membership.fromJson(Json json) => Membership(
    id: str(json['id']),
    ref: str(json['ref']),
    customerId: str(json['customer_id']),
    planId: str(json['plan_id']),
    planCode: strOrNull(json['plan_code']),
    status: MembershipStatus.fromDb(strOrNull(json['status'])),
    startedAt: dtOrNull(json['started_at']),
    currentPeriodStart: dtOrNull(json['current_period_start']),
    currentPeriodEnd: dtOrNull(json['current_period_end']),
    cancelAtPeriodEnd: boolOf(json['cancel_at_period_end']),
    cancelledAt: dtOrNull(json['cancelled_at']),
    endedAt: dtOrNull(json['ended_at']),
    nextPlanId: strOrNull(json['next_plan_id']),
    paymentMethod: MembershipPaymentMethod.fromDb(
      strOrNull(json['payment_method']),
    ),
    clientOpId: strOrNull(json['client_op_id']),
    createdBy: strOrNull(json['created_by']),
    createdAt: dtOrNull(json['created_at']),
    updatedAt: dtOrNull(json['updated_at']),
    pendingSync: boolOf(json['pending_sync']),
  );

  Json toJson() => compact({
    'id': id,
    'ref': ref,
    'customer_id': customerId,
    'plan_id': planId,
    'plan_code': planCode,
    'status': status.db,
    'started_at': iso(startedAt),
    'current_period_start': iso(currentPeriodStart),
    'current_period_end': iso(currentPeriodEnd),
    'cancel_at_period_end': cancelAtPeriodEnd,
    'cancelled_at': iso(cancelledAt),
    'ended_at': iso(endedAt),
    'next_plan_id': nextPlanId,
    'payment_method': paymentMethod.db,
    'client_op_id': clientOpId,
    'created_by': createdBy,
    'created_at': iso(createdAt),
    'updated_at': iso(updatedAt),
    'pending_sync': pendingSync ? true : null,
  });

  Membership copyWith({
    String? planId,
    String? planCode,
    MembershipStatus? status,
    DateTime? startedAt,
    DateTime? currentPeriodStart,
    DateTime? currentPeriodEnd,
    bool? cancelAtPeriodEnd,
    DateTime? cancelledAt,
    DateTime? endedAt,
    String? nextPlanId,
    bool clearNextPlan = false,
    MembershipPaymentMethod? paymentMethod,
    DateTime? updatedAt,
    bool? pendingSync,
  }) => Membership(
    id: id,
    ref: ref,
    customerId: customerId,
    planId: planId ?? this.planId,
    planCode: planCode ?? this.planCode,
    status: status ?? this.status,
    startedAt: startedAt ?? this.startedAt,
    currentPeriodStart: currentPeriodStart ?? this.currentPeriodStart,
    currentPeriodEnd: currentPeriodEnd ?? this.currentPeriodEnd,
    cancelAtPeriodEnd: cancelAtPeriodEnd ?? this.cancelAtPeriodEnd,
    cancelledAt: cancelledAt ?? this.cancelledAt,
    endedAt: endedAt ?? this.endedAt,
    nextPlanId: clearNextPlan ? null : (nextPlanId ?? this.nextPlanId),
    paymentMethod: paymentMethod ?? this.paymentMethod,
    clientOpId: clientOpId,
    createdBy: createdBy,
    createdAt: createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
    pendingSync: pendingSync ?? this.pendingSync,
  );

  @override
  List<Object?> get props => [
    id,
    ref,
    customerId,
    planId,
    status,
    currentPeriodStart,
    currentPeriodEnd,
    cancelAtPeriodEnd,
    nextPlanId,
    paymentMethod,
    updatedAt,
    pendingSync,
  ];
}

/// `membership_invoices` row.
class MembershipInvoice extends Equatable {
  const MembershipInvoice({
    required this.id,
    required this.ref,
    required this.membershipId,
    required this.customerId,
    required this.amountCents,
    required this.status,
    this.periodStart,
    this.periodEnd,
    this.dueAt,
    this.paidAt,
    this.paymentId,
    this.idempotencyKey,
    this.createdAt,
  });

  final String id;

  /// `MINV-2026-0101`
  final String ref;
  final String membershipId;
  final String customerId;
  final DateTime? periodStart;
  final DateTime? periodEnd;
  final int amountCents;
  final MembershipInvoiceStatus status;
  final DateTime? dueAt;
  final DateTime? paidAt;
  final String? paymentId;
  final String? idempotencyKey;
  final DateTime? createdAt;

  bool get isPending => status == MembershipInvoiceStatus.pending;
  bool get isPaid => status == MembershipInvoiceStatus.paid;

  factory MembershipInvoice.fromJson(Json json) => MembershipInvoice(
    id: str(json['id']),
    ref: str(json['ref']),
    membershipId: str(json['membership_id']),
    customerId: str(json['customer_id']),
    periodStart: dtOrNull(json['period_start']),
    periodEnd: dtOrNull(json['period_end']),
    amountCents: intOf(json['amount_cents']),
    status: MembershipInvoiceStatus.fromDb(strOrNull(json['status'])),
    dueAt: dtOrNull(json['due_at']),
    paidAt: dtOrNull(json['paid_at']),
    paymentId: strOrNull(json['payment_id']),
    idempotencyKey: strOrNull(json['idempotency_key']),
    createdAt: dtOrNull(json['created_at']),
  );

  Json toJson() => compact({
    'id': id,
    'ref': ref,
    'membership_id': membershipId,
    'customer_id': customerId,
    'period_start': iso(periodStart),
    'period_end': iso(periodEnd),
    'amount_cents': amountCents,
    'status': status.db,
    'due_at': iso(dueAt),
    'paid_at': iso(paidAt),
    'payment_id': paymentId,
    'idempotency_key': idempotencyKey,
    'created_at': iso(createdAt),
  });

  MembershipInvoice copyWith({
    MembershipInvoiceStatus? status,
    DateTime? paidAt,
    String? paymentId,
  }) => MembershipInvoice(
    id: id,
    ref: ref,
    membershipId: membershipId,
    customerId: customerId,
    periodStart: periodStart,
    periodEnd: periodEnd,
    amountCents: amountCents,
    status: status ?? this.status,
    dueAt: dueAt,
    paidAt: paidAt ?? this.paidAt,
    paymentId: paymentId ?? this.paymentId,
    idempotencyKey: idempotencyKey,
    createdAt: createdAt,
  );

  @override
  List<Object?> get props => [
    id,
    ref,
    membershipId,
    customerId,
    periodStart,
    periodEnd,
    amountCents,
    status,
    paidAt,
    paymentId,
  ];
}

/// `membership_usage` row (append-only: `+1` redeem, `−1` release).
class MembershipUsage extends Equatable {
  const MembershipUsage({
    required this.id,
    required this.membershipId,
    required this.entitlementId,
    required this.quantity,
    required this.periodStart,
    required this.periodEnd,
    this.bookingId,
    this.idempotencyKey,
    this.createdBy,
    this.createdAt,
  });

  final String id;
  final String membershipId;
  final String entitlementId;
  final String? bookingId;
  final int quantity;
  final DateTime periodStart;
  final DateTime periodEnd;
  final String? idempotencyKey;
  final String? createdBy;
  final DateTime? createdAt;

  factory MembershipUsage.fromJson(Json json) => MembershipUsage(
    id: str(json['id']),
    membershipId: str(json['membership_id']),
    entitlementId: str(json['entitlement_id']),
    bookingId: strOrNull(json['booking_id']),
    quantity: intOf(json['quantity']),
    periodStart: dt(json['period_start']),
    periodEnd: dt(json['period_end']),
    idempotencyKey: strOrNull(json['idempotency_key']),
    createdBy: strOrNull(json['created_by']),
    createdAt: dtOrNull(json['created_at']),
  );

  Json toJson() => compact({
    'id': id,
    'membership_id': membershipId,
    'entitlement_id': entitlementId,
    'booking_id': bookingId,
    'quantity': quantity,
    'period_start': iso(periodStart),
    'period_end': iso(periodEnd),
    'idempotency_key': idempotencyKey,
    'created_by': createdBy,
    'created_at': iso(createdAt),
  });

  @override
  List<Object?> get props => [
    id,
    membershipId,
    entitlementId,
    bookingId,
    quantity,
    periodStart,
  ];
}

/// One `allowances[]` entry of `GET /memberships/me`: remaining quantity of
/// an entitlement in its current period.
class Allowance extends Equatable {
  const Allowance({
    required this.entitlementId,
    required this.entitlementCode,
    required this.groupCode,
    required this.label,
    required this.quantity,
    required this.used,
    required this.remaining,
    this.period = EntitlementPeriod.month,
    this.periodStart,
    this.periodEnd,
    this.itemName,
  });

  final String entitlementId;
  final String entitlementCode;
  final String groupCode;

  /// The entitlement label ("4 × Sparkling Wash").
  final String label;
  final int quantity;
  final int used;
  final int remaining;
  final EntitlementPeriod period;
  final DateTime? periodStart;
  final DateTime? periodEnd;

  /// Optional noun from the API ("Sparkling Wash"); derived from [label]
  /// when absent.
  final String? itemName;

  /// 0…1 share of the allowance still available.
  double get progress => quantity <= 0 ? 0 : (remaining / quantity).clamp(0, 1);
  bool get isExhausted => remaining <= 0;
  bool get isMonthly => period == EntitlementPeriod.month;

  MembershipEntitlement get _ent => MembershipEntitlement(
    id: entitlementId,
    code: entitlementCode,
    label: itemName ?? label,
    quantity: quantity,
    period: period,
  );

  /// "Sparkling Wash"
  String get noun => itemName ?? _ent.itemName;

  /// "Sparkling Washes"
  String get nounPlural => _ent.itemNamePlural;

  /// "Sparkling Washes" for a quantity above one, else the singular.
  String get nounFor => quantity == 1 ? noun : nounPlural;

  /// "3 of 4 Sparkling Washes left"
  String get summaryLabel =>
      '$remaining of $quantity ${quantity == 1 ? _ent.itemName : _ent.itemNamePlural} left';

  /// "resets 5 Oct"
  String? get resetLabel =>
      periodEnd == null ? null : 'resets ${SparklingDates.dayMonth(periodEnd!)}';

  /// "3 of 4 Sparkling Washes left · resets 5 Oct"
  String get fullLabel =>
      [summaryLabel, ?resetLabel].join(' · ');

  factory Allowance.fromJson(Json json) => Allowance(
    entitlementId: str(json['entitlement_id']),
    entitlementCode: str(json['entitlement_code']),
    groupCode: str(json['group_code']),
    label: str(json['label']),
    quantity: intOf(json['quantity']),
    used: intOf(json['used']),
    remaining: intOf(json['remaining']),
    period: EntitlementPeriod.fromDb(strOrNull(json['period'])),
    periodStart: dtOrNull(json['period_start']),
    periodEnd: dtOrNull(json['period_end']),
    itemName: strOrNull(json['item_name']),
  );

  Json toJson() => compact({
    'entitlement_id': entitlementId,
    'entitlement_code': entitlementCode,
    'group_code': groupCode,
    'label': label,
    'quantity': quantity,
    'used': used,
    'remaining': remaining,
    'period': period.db,
    'period_start': iso(periodStart),
    'period_end': iso(periodEnd),
    'item_name': itemName,
  });

  @override
  List<Object?> get props => [
    entitlementId,
    entitlementCode,
    groupCode,
    quantity,
    used,
    remaining,
    period,
    periodStart,
    periodEnd,
  ];
}

/// `GET /memberships/me` (and `GET /staff/customers/:id/membership`).
class MembershipSummary extends Equatable {
  const MembershipSummary({
    this.membership,
    this.plan,
    this.selections = const {},
    this.allowances = const [],
    this.openInvoice,
    this.invoices = const [],
    this.nextRenewalAt,
    this.benefitsSummary,
  });

  static const MembershipSummary none = MembershipSummary();

  final Membership? membership;
  final MembershipPlan? plan;

  /// `{ group_code: entitlement_code }`
  final Map<String, String> selections;
  final List<Allowance> allowances;
  final MembershipInvoice? openInvoice;

  /// Last 12.
  final List<MembershipInvoice> invoices;
  final DateTime? nextRenewalAt;
  final String? benefitsSummary;

  bool get hasMembership => membership != null && membership!.isLive;
  bool get isActive => membership?.isActive ?? false;
  bool get isPastDue => membership?.isPastDue ?? false;
  bool get isPending => membership?.isPending ?? false;
  bool get benefitsActive => membership?.benefitsActive ?? false;
  bool get pendingSync => membership?.pendingSync ?? false;

  MembershipStatus? get status => membership?.status;
  String? get planCode => plan?.code ?? membership?.planCode;
  String? get planName => plan?.name;
  LoyaltyTier get tier =>
      hasMembership ? (plan?.tier ?? LoyaltyTier.silver) : LoyaltyTier.silver;

  /// Entitlements in force (selected options + `all` groups).
  List<MembershipEntitlement> get selectedEntitlements =>
      plan?.selectedEntitlements(selections) ?? const [];

  /// Remaining monthly washes (the `washes` group, else every monthly
  /// allowance) — "Gold · 3 washes left".
  int get includedRemaining {
    final washes = allowances.where((a) => a.groupCode == 'washes').toList();
    final pool = washes.isNotEmpty
        ? washes
        : allowances.where((a) => a.isMonthly).toList();
    return pool.fold(0, (s, a) => s + a.remaining);
  }

  /// Anything redeemed in the current period (blocks selection changes).
  bool get usedThisPeriod => allowances.any((a) => a.used > 0);

  Allowance? allowanceFor(String entitlementCode) =>
      allowances.where((a) => a.entitlementCode == entitlementCode).firstOrNull;

  /// The allowance covering a catalogue service code, when it still has
  /// quantity left.
  Allowance? coveringAllowance(String serviceCode) {
    for (final e in selectedEntitlements) {
      if (!e.coversServiceCode(serviceCode)) continue;
      final a = allowanceFor(e.code);
      if (a != null && a.remaining > 0) return a;
    }
    return null;
  }

  /// Plan discount rule applied to a service (see docs/MEMBERSHIPS.md §3);
  /// 0 when no discount applies.
  int discountPctFor(String serviceCode) {
    final p = plan;
    if (p == null || !benefitsActive || p.discountPct <= 0) return 0;
    return switch (p.discountScope) {
      DiscountScope.planServices =>
        selectedEntitlements.any((e) => e.coversServiceCode(serviceCode))
            ? p.discountPct
            : 0,
      DiscountScope.otherServices =>
        p.coversServiceCode(serviceCode) ? 0 : p.discountPct,
      DiscountScope.allServices => p.discountPct,
      DiscountScope.none => 0,
    };
  }

  /// "Gold · 3 washes left"
  String? get shortLabel {
    if (!hasMembership) return null;
    final n = includedRemaining;
    return '${planName ?? planCode} · $n wash${n == 1 ? '' : 'es'} left';
  }

  factory MembershipSummary.fromJson(Json json) {
    final sel = <String, String>{};
    (asJsonOrNull(json['selections']) ?? const {}).forEach((k, v) {
      if (v != null) sel[k] = v.toString();
    });
    return MembershipSummary(
      membership: json['membership'] is Map
          ? Membership.fromJson(asJson(json['membership']))
          : null,
      plan: json['plan'] is Map ? MembershipPlan.fromJson(asJson(json['plan'])) : null,
      selections: sel,
      allowances: asJsonList(json['allowances']).map(Allowance.fromJson).toList(),
      openInvoice: json['open_invoice'] is Map
          ? MembershipInvoice.fromJson(asJson(json['open_invoice']))
          : null,
      invoices: asJsonList(json['invoices'])
          .map(MembershipInvoice.fromJson)
          .toList(),
      nextRenewalAt: dtOrNull(json['next_renewal_at']),
      benefitsSummary: strOrNull(json['benefits_summary']),
    );
  }

  Json toJson() => compact({
    'membership': membership?.toJson(),
    'plan': plan?.toJson(),
    'selections': selections,
    'allowances': allowances.map((a) => a.toJson()).toList(),
    'open_invoice': openInvoice?.toJson(),
    'invoices': invoices.map((i) => i.toJson()).toList(),
    'next_renewal_at': iso(nextRenewalAt),
    'benefits_summary': benefitsSummary,
  });

  MembershipSummary copyWith({Membership? membership}) => MembershipSummary(
    membership: membership ?? this.membership,
    plan: plan,
    selections: selections,
    allowances: allowances,
    openInvoice: openInvoice,
    invoices: invoices,
    nextRenewalAt: nextRenewalAt,
    benefitsSummary: benefitsSummary,
  );

  @override
  List<Object?> get props => [
    membership,
    plan,
    selections,
    allowances,
    openInvoice,
    invoices,
    nextRenewalAt,
    benefitsSummary,
  ];
}

/// The `membership` block on `GET /loyalty/account` and `GET /me`:
/// `{ plan_code, plan_name, status, period_end, allowances }`.
class MembershipBrief extends Equatable {
  const MembershipBrief({
    required this.planCode,
    required this.planName,
    required this.status,
    this.periodEnd,
    this.allowances = const [],
  });

  final String planCode;
  final String planName;
  final MembershipStatus status;
  final DateTime? periodEnd;
  final List<Allowance> allowances;

  bool get benefitsActive => status.benefitsActive;

  int get includedRemaining {
    final washes = allowances.where((a) => a.groupCode == 'washes').toList();
    final pool = washes.isNotEmpty
        ? washes
        : allowances.where((a) => a.isMonthly).toList();
    return pool.fold(0, (s, a) => s + a.remaining);
  }

  /// "Gold · 3 washes left"
  String get shortLabel {
    final n = includedRemaining;
    return '$planName · $n wash${n == 1 ? '' : 'es'} left';
  }

  factory MembershipBrief.fromJson(Json json) => MembershipBrief(
    planCode: str(json['plan_code']),
    planName: str(json['plan_name'], str(json['plan_code'])),
    status: MembershipStatus.fromDb(strOrNull(json['status'])),
    periodEnd: dtOrNull(json['period_end']),
    allowances: asJsonList(json['allowances']).map(Allowance.fromJson).toList(),
  );

  Json toJson() => compact({
    'plan_code': planCode,
    'plan_name': planName,
    'status': status.db,
    'period_end': iso(periodEnd),
    'allowances': allowances.map((a) => a.toJson()).toList(),
  });

  @override
  List<Object?> get props => [planCode, planName, status, periodEnd, allowances];
}

/// The `membership` block on a price quote / booking:
/// `{ plan_code, plan_name, benefit, entitlement_code, remaining_after, period_end }`.
class BookingMembership extends Equatable {
  const BookingMembership({
    required this.planCode,
    required this.planName,
    this.benefit,
    this.entitlementCode,
    this.remainingAfter,
    this.periodEnd,
  });

  final String planCode;
  final String planName;

  /// `null` when the plan gave no benefit on this booking.
  final MembershipBenefit? benefit;
  final String? entitlementCode;

  /// Allowance left **after** this booking (included bookings only).
  final int? remainingAfter;
  final DateTime? periodEnd;

  bool get isIncluded => benefit == MembershipBenefit.included;
  bool get isDiscount => benefit == MembershipBenefit.discount;

  factory BookingMembership.fromJson(Json json) => BookingMembership(
    planCode: str(json['plan_code']),
    planName: str(json['plan_name'], str(json['plan_code'])),
    benefit: MembershipBenefit.fromDb(strOrNull(json['benefit'])),
    entitlementCode: strOrNull(json['entitlement_code']),
    remainingAfter: intOrNull(json['remaining_after']),
    periodEnd: dtOrNull(json['period_end']),
  );

  Json toJson() => {
    'plan_code': planCode,
    'plan_name': planName,
    'benefit': benefit?.db,
    'entitlement_code': entitlementCode,
    'remaining_after': remainingAfter,
    'period_end': iso(periodEnd),
  };

  @override
  List<Object?> get props => [
    planCode,
    planName,
    benefit,
    entitlementCode,
    remainingAfter,
    periodEnd,
  ];
}

/// `POST /memberships` / `POST /memberships/me/change-plan` result:
/// the membership plus, when money is due now, the invoice and the sandbox
/// payment intent to confirm.
class SubscribeResult extends Equatable {
  const SubscribeResult({required this.membership, this.invoice, this.payment});

  final Membership membership;
  final MembershipInvoice? invoice;
  final PaymentIntentResult? payment;

  /// A payment must be confirmed before the change takes effect.
  bool get requiresPayment => payment != null;

  factory SubscribeResult.fromJson(Json json) => SubscribeResult(
    membership: Membership.fromJson(asJson(json['membership'] ?? json)),
    invoice: json['invoice'] is Map
        ? MembershipInvoice.fromJson(asJson(json['invoice']))
        : null,
    payment: json['payment'] is Map
        ? PaymentIntentResult.fromJson(asJson(json['payment']))
        : null,
  );

  Json toJson() => compact({
    'membership': membership.toJson(),
    'invoice': invoice?.toJson(),
    'payment': payment?.toJson(),
  });

  @override
  List<Object?> get props => [membership, invoice, payment];
}

/// Body for `POST /staff/customers/:id/membership` (also the payload of the
/// `membership.enrol` sync operation, which adds `customer_id`).
class EnrolMembershipInput {
  const EnrolMembershipInput({
    required this.customerId,
    required this.planCode,
    required this.selections,
    required this.paymentMethod,
    required this.clientOpId,
  });

  final String customerId;
  final String planCode;
  final Map<String, String> selections;
  final CounterPaymentMethod paymentMethod;
  final String clientOpId;

  Json toJson() => {
    'customer_id': customerId,
    'plan_code': planCode,
    'selections': selections,
    'payment_method': paymentMethod.db,
    'client_op_id': clientOpId,
  };

  factory EnrolMembershipInput.fromJson(Json json) {
    final sel = <String, String>{};
    (asJsonOrNull(json['selections']) ?? const {}).forEach((k, v) {
      if (v != null) sel[k] = v.toString();
    });
    return EnrolMembershipInput(
      customerId: str(json['customer_id']),
      planCode: str(json['plan_code']),
      selections: sel,
      paymentMethod: CounterPaymentMethod.fromDb(
        strOrNull(json['payment_method']),
      ),
      clientOpId: str(json['client_op_id']),
    );
  }
}
