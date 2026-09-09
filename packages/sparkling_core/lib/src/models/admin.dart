import 'package:equatable/equatable.dart';

import 'enums.dart';
import 'json.dart';
import 'loyalty.dart';

/// `bookings_by_hour[]` entry.
class HourBucket extends Equatable {
  const HourBucket({
    required this.hour,
    this.carWash = 0,
    this.autoBody = 0,
    this.isFuture = false,
  });
  final int hour;
  final int carWash;
  final int autoBody;
  final bool isFuture;
  int get total => carWash + autoBody;

  factory HourBucket.fromJson(Json json) => HourBucket(
    hour: intOf(json['hour']),
    carWash: intOf(json['car_wash']),
    autoBody: intOf(json['auto_body']),
    isFuture: boolOf(json['is_future']),
  );
  Json toJson() => {
    'hour': hour,
    'car_wash': carWash,
    'auto_body': autoBody,
    'is_future': isFuture,
  };
  @override
  List<Object?> get props => [hour, carWash, autoBody, isFuture];
}

/// `revenue_by_outlet[]` entry.
class OutletRevenue extends Equatable {
  const OutletRevenue({
    required this.outletId,
    required this.name,
    required this.revenueCents,
    this.bookings = 0,
  });
  final String outletId;
  final String name;
  final int revenueCents;
  final int bookings;

  factory OutletRevenue.fromJson(Json json) => OutletRevenue(
    outletId: str(json['outlet_id']),
    name: str(json['name'] ?? json['outlet_name']),
    revenueCents: intOf(json['revenue_cents']),
    bookings: intOf(json['bookings']),
  );
  Json toJson() => {
    'outlet_id': outletId,
    'name': name,
    'revenue_cents': revenueCents,
    'bookings': bookings,
  };
  @override
  List<Object?> get props => [outletId, name, revenueCents, bookings];
}

/// `top_staff[]` entry.
class TopStaff extends Equatable {
  const TopStaff({
    required this.staffId,
    required this.name,
    required this.points,
    this.tasksCompleted = 0,
  });
  final String staffId;
  final String name;
  final int points;
  final int tasksCompleted;

  factory TopStaff.fromJson(Json json) => TopStaff(
    staffId: str(json['staff_id']),
    name: str(json['name']),
    points: intOf(json['points']),
    tasksCompleted: intOf(json['tasks_completed']),
  );
  Json toJson() => {
    'staff_id': staffId,
    'name': name,
    'points': points,
    'tasks_completed': tasksCompleted,
  };
  @override
  List<Object?> get props => [staffId, name, points, tasksCompleted];
}

/// `GET /admin/kpis`.
class AdminKpis extends Equatable {
  const AdminKpis({
    this.revenueCents = 0,
    this.revenueTrendPct = 0,
    this.bookingsToday = 0,
    this.activeWorkOrders = 0,
    this.completedToday = 0,
    this.exceptionsCount = 0,
    this.bookingsByHour = const [],
    this.revenueByOutlet = const [],
    this.topStaff = const [],
    this.generatedAt,
  });

  final int revenueCents;
  final double revenueTrendPct;
  final int bookingsToday;
  final int activeWorkOrders;
  final int completedToday;
  final int exceptionsCount;
  final List<HourBucket> bookingsByHour;
  final List<OutletRevenue> revenueByOutlet;
  final List<TopStaff> topStaff;
  final DateTime? generatedAt;

  factory AdminKpis.fromJson(Json json) => AdminKpis(
    revenueCents: intOf(json['revenue_cents']),
    revenueTrendPct: dbl(json['revenue_trend_pct']),
    bookingsToday: intOf(json['bookings_today']),
    activeWorkOrders: intOf(json['active_work_orders']),
    completedToday: intOf(json['completed_today']),
    exceptionsCount: intOf(json['exceptions_count']),
    bookingsByHour: asJsonList(json['bookings_by_hour'])
        .map(HourBucket.fromJson)
        .toList(),
    revenueByOutlet: asJsonList(json['revenue_by_outlet'])
        .map(OutletRevenue.fromJson)
        .toList(),
    topStaff: asJsonList(json['top_staff']).map(TopStaff.fromJson).toList(),
    generatedAt: dtOrNull(json['generated_at']),
  );

  Json toJson() => compact({
    'revenue_cents': revenueCents,
    'revenue_trend_pct': revenueTrendPct,
    'bookings_today': bookingsToday,
    'active_work_orders': activeWorkOrders,
    'completed_today': completedToday,
    'exceptions_count': exceptionsCount,
    'bookings_by_hour': bookingsByHour.map((b) => b.toJson()).toList(),
    'revenue_by_outlet': revenueByOutlet.map((r) => r.toJson()).toList(),
    'top_staff': topStaff.map((t) => t.toJson()).toList(),
    'generated_at': iso(generatedAt),
  });

  @override
  List<Object?> get props => [
    revenueCents,
    revenueTrendPct,
    bookingsToday,
    activeWorkOrders,
    completedToday,
    exceptionsCount,
    bookingsByHour,
    revenueByOutlet,
    topStaff,
  ];
}

/// `GET /admin/activity` feed item.
class ActivityItem extends Equatable {
  const ActivityItem({
    required this.id,
    required this.kind,
    required this.title,
    this.detail,
    this.at,
    this.outletId,
    this.actorName,
    this.linkType,
    this.linkId,
  });

  final String id;

  /// 'task_completed' | 'payment_verified' | 'quote_converted' | 'low_stock' | 'loyalty_posted' | …
  final String kind;
  final String title;
  final String? detail;
  final DateTime? at;
  final String? outletId;
  final String? actorName;
  final String? linkType;
  final String? linkId;

  factory ActivityItem.fromJson(Json json) {
    final link = asJsonOrNull(json['link']);
    return ActivityItem(
      id: str(json['id']),
      kind: str(json['kind'] ?? json['type']),
      title: str(json['title']),
      detail: strOrNull(json['detail']),
      at: dtOrNull(json['at'] ?? json['created_at']),
      outletId: strOrNull(json['outlet_id']),
      actorName: strOrNull(json['actor_name']),
      linkType: strOrNull(link?['type']),
      linkId: strOrNull(link?['id']),
    );
  }

  Json toJson() => compact({
    'id': id,
    'kind': kind,
    'title': title,
    'detail': detail,
    'at': iso(at),
    'outlet_id': outletId,
    'actor_name': actorName,
    'link': linkType == null ? null : {'type': linkType, 'id': linkId},
  });

  @override
  List<Object?> get props => [id, kind, title, detail, at];
}

/// `feature_flags` row.
class FeatureFlag extends Equatable {
  const FeatureFlag({
    required this.key,
    required this.enabled,
    this.description,
    this.updatedAt,
  });
  final String key;
  final bool enabled;
  final String? description;
  final DateTime? updatedAt;

  factory FeatureFlag.fromJson(Json json) => FeatureFlag(
    key: str(json['key']),
    enabled: boolOf(json['enabled']),
    description: strOrNull(json['description']),
    updatedAt: dtOrNull(json['updated_at']),
  );
  Json toJson() => compact({
    'key': key,
    'enabled': enabled,
    'description': description,
    'updated_at': iso(updatedAt),
  });
  @override
  List<Object?> get props => [key, enabled, description];
}

/// `audit_events` row.
class AuditEvent extends Equatable {
  const AuditEvent({
    required this.id,
    required this.action,
    required this.entityType,
    this.entityId,
    this.actorId,
    this.actorRole,
    this.outletId,
    this.before,
    this.after,
    this.correlationId,
    this.outcome = 'ok',
    this.createdAt,
  });

  final String id;
  final String action;
  final String entityType;
  final String? entityId;
  final String? actorId;
  final String? actorRole;
  final String? outletId;
  final Json? before;
  final Json? after;
  final String? correlationId;
  final String outcome;
  final DateTime? createdAt;

  factory AuditEvent.fromJson(Json json) => AuditEvent(
    id: str(json['id']),
    action: str(json['action']),
    entityType: str(json['entity_type']),
    entityId: strOrNull(json['entity_id']),
    actorId: strOrNull(json['actor_id']),
    actorRole: strOrNull(json['actor_role']),
    outletId: strOrNull(json['outlet_id']),
    before: asJsonOrNull(json['before']),
    after: asJsonOrNull(json['after']),
    correlationId: strOrNull(json['correlation_id']),
    outcome: str(json['outcome'], 'ok'),
    createdAt: dtOrNull(json['created_at']),
  );

  Json toJson() => compact({
    'id': id,
    'action': action,
    'entity_type': entityType,
    'entity_id': entityId,
    'actor_id': actorId,
    'actor_role': actorRole,
    'outlet_id': outletId,
    'before': before,
    'after': after,
    'correlation_id': correlationId,
    'outcome': outcome,
    'created_at': iso(createdAt),
  });

  @override
  List<Object?> get props => [
    id,
    action,
    entityType,
    entityId,
    actorId,
    createdAt,
  ];
}

/// `GET /admin/staff/performance` row.
class StaffPerformanceRow extends Equatable {
  const StaffPerformanceRow({
    required this.staffId,
    required this.name,
    this.tasksCompleted = 0,
    this.avgCycleMinutes = 0,
    this.checklistCompliancePct = 0,
    this.points = 0,
    this.outletId,
  });

  final String staffId;
  final String name;
  final int tasksCompleted;
  final double avgCycleMinutes;
  final double checklistCompliancePct;
  final int points;
  final String? outletId;

  factory StaffPerformanceRow.fromJson(Json json) => StaffPerformanceRow(
    staffId: str(json['staff_id']),
    name: str(json['name']),
    tasksCompleted: intOf(json['tasks_completed']),
    avgCycleMinutes: dbl(
      json['avg_cycle_minutes'] ?? json['cycle_time_minutes'],
    ),
    checklistCompliancePct: dbl(json['checklist_compliance_pct']),
    points: intOf(json['points']),
    outletId: strOrNull(json['outlet_id']),
  );

  Json toJson() => compact({
    'staff_id': staffId,
    'name': name,
    'tasks_completed': tasksCompleted,
    'avg_cycle_minutes': avgCycleMinutes,
    'checklist_compliance_pct': checklistCompliancePct,
    'points': points,
    'outlet_id': outletId,
  });

  @override
  List<Object?> get props => [
    staffId,
    name,
    tasksCompleted,
    avgCycleMinutes,
    checklistCompliancePct,
    points,
  ];
}

/// `GET /admin/loyalty/config` → `{ published, draft }`.
class LoyaltyConfigBundle extends Equatable {
  const LoyaltyConfigBundle({this.published, this.draft});
  final LoyaltyConfig? published;
  final LoyaltyConfig? draft;

  factory LoyaltyConfigBundle.fromJson(Json json) => LoyaltyConfigBundle(
    published: json['published'] is Map
        ? LoyaltyConfig.fromJson(asJson(json['published']))
        : null,
    draft: json['draft'] is Map
        ? LoyaltyConfig.fromJson(asJson(json['draft']))
        : null,
  );
  Json toJson() =>
      compact({'published': published?.toJson(), 'draft': draft?.toJson()});
  @override
  List<Object?> get props => [published, draft];
}

/// Body for `POST /admin/users` (invite) and `PATCH /admin/users/:id`.
class AdminUserInput {
  const AdminUserInput({
    this.email,
    this.fullName,
    this.role,
    this.outletIds,
    this.isActive,
    this.phone,
  });
  final String? email;
  final String? fullName;
  final UserRole? role;
  final List<String>? outletIds;
  final bool? isActive;
  final String? phone;

  Json toJson() => compact({
    'email': email,
    'full_name': fullName,
    'role': role?.db,
    'outlet_ids': outletIds,
    'is_active': isActive,
    'phone': phone,
  });
}
