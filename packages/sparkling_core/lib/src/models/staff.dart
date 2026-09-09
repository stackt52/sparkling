import 'package:equatable/equatable.dart';

import 'enums.dart';
import 'json.dart';

/// `GET /staff/team` item: profile + availability + skills + active task count.
class StaffMember extends Equatable {
  const StaffMember({
    required this.id,
    required this.fullName,
    required this.role,
    this.availability = AvailabilityStatus.available,
    this.capacity = 3,
    this.skills = const [],
    this.activeTasks = 0,
    this.outletIds = const [],
    this.avatarUrl,
    this.email,
    this.phone,
  });

  final String id;
  final String fullName;
  final UserRole role;
  final AvailabilityStatus availability;
  final int capacity;
  final List<String> skills;
  final int activeTasks;
  final List<String> outletIds;
  final String? avatarUrl;
  final String? email;
  final String? phone;

  String get firstName => fullName.trim().split(RegExp(r'\s+')).first;

  /// "Sipho N." style short name.
  String get shortName {
    final parts = fullName.trim().split(RegExp(r'\s+'));
    if (parts.length < 2) return fullName;
    return '${parts.first} ${parts.last[0]}.';
  }

  String get initials {
    final parts = fullName
        .trim()
        .split(RegExp(r'\s+'))
        .where((p) => p.isNotEmpty)
        .toList();
    if (parts.isEmpty) return '?';
    if (parts.length == 1) {
      return parts.first
          .substring(0, parts.first.length.clamp(0, 2))
          .toUpperCase();
    }
    return (parts.first[0] + parts.last[0]).toUpperCase();
  }

  bool get atCapacity =>
      activeTasks >= capacity || availability == AvailabilityStatus.off;
  double get load => capacity == 0 ? 1 : (activeTasks / capacity).clamp(0, 1);
  bool get isAvailable =>
      availability == AvailabilityStatus.available && activeTasks < capacity;

  factory StaffMember.fromJson(Json json) {
    final availability = asJsonOrNull(json['availability']);
    return StaffMember(
      id: str(json['id'] ?? json['staff_id'] ?? json['profile_id']),
      fullName: str(json['full_name'] ?? json['name']),
      role: UserRole.fromDb(strOrNull(json['role']) ?? 'technician'),
      availability: AvailabilityStatus.fromDb(
        strOrNull(availability?['status']) ??
            strOrNull(json['availability_status']) ??
            strOrNull(json['status']),
      ),
      capacity: intOf(availability?['capacity'] ?? json['capacity'], 3),
      skills: asStringList(json['skills']),
      activeTasks: intOf(json['active_tasks'] ?? json['active_task_count']),
      outletIds: asStringList(json['outlet_ids']),
      avatarUrl: strOrNull(json['avatar_url']),
      email: strOrNull(json['email']),
      phone: strOrNull(json['phone']),
    );
  }

  Json toJson() => compact({
    'id': id,
    'full_name': fullName,
    'role': role.db,
    'availability': {'status': availability.db, 'capacity': capacity},
    'skills': skills,
    'active_tasks': activeTasks,
    'outlet_ids': outletIds,
    'avatar_url': avatarUrl,
    'email': email,
    'phone': phone,
  });

  StaffMember copyWith({
    AvailabilityStatus? availability,
    int? capacity,
    int? activeTasks,
    List<String>? skills,
  }) => StaffMember(
    id: id,
    fullName: fullName,
    role: role,
    availability: availability ?? this.availability,
    capacity: capacity ?? this.capacity,
    skills: skills ?? this.skills,
    activeTasks: activeTasks ?? this.activeTasks,
    outletIds: outletIds,
    avatarUrl: avatarUrl,
    email: email,
    phone: phone,
  );

  @override
  List<Object?> get props => [
    id,
    fullName,
    role,
    availability,
    capacity,
    skills,
    activeTasks,
  ];
}

/// `badges` row.
class Badge extends Equatable {
  const Badge({
    required this.id,
    required this.code,
    required this.name,
    this.description,
    this.icon = 'military_tech',
    this.colour = '#00A0E0',
    this.criteria = const {},
  });

  final String id;
  final String code;
  final String name;
  final String? description;

  /// Material Symbols glyph name.
  final String icon;

  /// Hex colour (`#RRGGBB`).
  final String colour;
  final Json criteria;

  /// ARGB int for `Color(badge.colourValue)`.
  int get colourValue {
    final hex = colour.replaceFirst('#', '');
    final v = int.tryParse(hex, radix: 16) ?? 0x00A0E0;
    return hex.length <= 6 ? (0xFF000000 | v) : v;
  }

  factory Badge.fromJson(Json json) => Badge(
    id: str(json['id']),
    code: str(json['code']),
    name: str(json['name']),
    description: strOrNull(json['description']),
    icon: str(json['icon'], 'military_tech'),
    colour: str(json['colour'] ?? json['color'], '#00A0E0'),
    criteria: asJson(json['criteria']),
  );

  Json toJson() => compact({
    'id': id,
    'code': code,
    'name': name,
    'description': description,
    'icon': icon,
    'colour': colour,
    'criteria': criteria.isEmpty ? null : criteria,
  });

  @override
  List<Object?> get props => [id, code, name, icon, colour];
}

/// `badges[]` entry of the leaderboard: `{ badge, earned_at? }`.
class EarnedBadge extends Equatable {
  const EarnedBadge({required this.badge, this.earnedAt});
  final Badge badge;
  final DateTime? earnedAt;
  bool get earned => earnedAt != null;

  factory EarnedBadge.fromJson(Json json) => EarnedBadge(
    badge: Badge.fromJson(asJson(json['badge'] ?? json)),
    earnedAt: dtOrNull(json['earned_at'] ?? json['awarded_at']),
  );
  Json toJson() =>
      compact({'badge': badge.toJson(), 'earned_at': iso(earnedAt)});
  @override
  List<Object?> get props => [badge, earnedAt];
}

/// `rows[]` of `GET /staff/leaderboard`.
class LeaderboardRow extends Equatable {
  const LeaderboardRow({
    required this.staffId,
    required this.name,
    required this.points,
    required this.rank,
    this.delta = 0,
    this.isMe = false,
    this.avatarUrl,
  });

  final String staffId;
  final String name;
  final int points;
  final int rank;

  /// Rank change vs the previous period (+ = moved up).
  final int delta;
  final bool isMe;
  final String? avatarUrl;

  String get initials {
    final parts = name
        .trim()
        .split(RegExp(r'\s+'))
        .where((p) => p.isNotEmpty)
        .toList();
    if (parts.isEmpty) return '?';
    if (parts.length == 1) {
      return parts.first
          .substring(0, parts.first.length.clamp(0, 2))
          .toUpperCase();
    }
    return (parts.first[0] + parts.last[0]).toUpperCase();
  }

  factory LeaderboardRow.fromJson(Json json) => LeaderboardRow(
    staffId: str(json['staff_id']),
    name: str(json['name']),
    points: intOf(json['points']),
    rank: intOf(json['rank']),
    delta: intOf(json['delta']),
    isMe: boolOf(json['is_me']),
    avatarUrl: strOrNull(json['avatar_url']),
  );

  Json toJson() => compact({
    'staff_id': staffId,
    'name': name,
    'points': points,
    'rank': rank,
    'delta': delta,
    'is_me': isMe ? true : null,
    'avatar_url': avatarUrl,
  });

  LeaderboardRow copyWith({int? points, int? rank, int? delta, bool? isMe}) =>
      LeaderboardRow(
        staffId: staffId,
        name: name,
        points: points ?? this.points,
        rank: rank ?? this.rank,
        delta: delta ?? this.delta,
        isMe: isMe ?? this.isMe,
        avatarUrl: avatarUrl,
      );

  @override
  List<Object?> get props => [staffId, name, points, rank, delta, isMe];
}

/// `GET /staff/leaderboard` → `{ rows, me, badges }`.
class LeaderboardResult extends Equatable {
  const LeaderboardResult({
    required this.rows,
    this.me,
    this.badges = const [],
    this.period = LeaderboardPeriod.week,
    this.resetsAt,
  });

  final List<LeaderboardRow> rows;
  final LeaderboardRow? me;
  final List<EarnedBadge> badges;
  final LeaderboardPeriod period;
  final DateTime? resetsAt;

  List<LeaderboardRow> get podium => rows.take(3).toList();
  List<LeaderboardRow> get rest => rows.skip(3).toList();
  List<EarnedBadge> get earnedBadges => badges.where((b) => b.earned).toList();

  factory LeaderboardResult.fromJson(Json json) => LeaderboardResult(
    rows: asJsonList(json['rows']).map(LeaderboardRow.fromJson).toList(),
    me: json['me'] is Map ? LeaderboardRow.fromJson(asJson(json['me'])) : null,
    badges: asJsonList(json['badges']).map(EarnedBadge.fromJson).toList(),
    period: str(json['period']) == 'month'
        ? LeaderboardPeriod.month
        : LeaderboardPeriod.week,
    resetsAt: dtOrNull(json['resets_at']),
  );

  Json toJson() => compact({
    'rows': rows.map((r) => r.toJson()).toList(),
    'me': me?.toJson(),
    'badges': badges.map((b) => b.toJson()).toList(),
    'period': period.name,
    'resets_at': iso(resetsAt),
  });

  @override
  List<Object?> get props => [rows, me, badges, period];
}

/// `counts{in_progress, queued, blocked, done}` of the ops summary.
class OpsCounts extends Equatable {
  const OpsCounts({
    this.inProgress = 0,
    this.queued = 0,
    this.blocked = 0,
    this.done = 0,
  });
  final int inProgress;
  final int queued;
  final int blocked;
  final int done;

  factory OpsCounts.fromJson(Json json) => OpsCounts(
    inProgress: intOf(json['in_progress']),
    queued: intOf(json['queued']),
    blocked: intOf(json['blocked']),
    done: intOf(json['done']),
  );
  Json toJson() => {
    'in_progress': inProgress,
    'queued': queued,
    'blocked': blocked,
    'done': done,
  };
  @override
  List<Object?> get props => [inProgress, queued, blocked, done];
}

/// Kind of item in `needs_attention[]` / admin exceptions.
enum AttentionKind {
  blocked,
  overdueSla,
  lowStock,
  outOfStock,
  failedPayment,
  other;

  static AttentionKind fromDb(String? v) => switch (v) {
    'blocked' => blocked,
    'overdue_sla' || 'overdue' => overdueSla,
    'low_stock' => lowStock,
    'out_of_stock' => outOfStock,
    'failed_payment' => failedPayment,
    _ => other,
  };

  String get db => switch (this) {
    blocked => 'blocked',
    overdueSla => 'overdue_sla',
    lowStock => 'low_stock',
    outOfStock => 'out_of_stock',
    failedPayment => 'failed_payment',
    other => 'other',
  };
}

/// Link to the underlying record (`link{type,id}`).
class RecordLink extends Equatable {
  const RecordLink({required this.type, required this.id});

  /// 'work_order' | 'task' | 'inventory_item' | 'payment' | 'booking'
  final String type;
  final String id;

  factory RecordLink.fromJson(Json json) =>
      RecordLink(type: str(json['type']), id: str(json['id']));
  Json toJson() => {'type': type, 'id': id};
  @override
  List<Object?> get props => [type, id];
}

/// `needs_attention[]` item (STF-060) and `GET /admin/exceptions` item (ADM-011).
class AttentionItem extends Equatable {
  const AttentionItem({
    required this.kind,
    required this.title,
    this.detail,
    this.link,
    this.ref,
    this.since,
    this.outletId,
    this.severity = 'warning',
    this.actions = const [],
  });

  final AttentionKind kind;
  final String title;
  final String? detail;
  final RecordLink? link;

  /// e.g. "WO-2026-4823"
  final String? ref;
  final DateTime? since;
  final String? outletId;

  /// 'error' | 'warning' | 'info'
  final String severity;

  /// Suggested actions ('reassign', 'substitute_stock', 'reorder', 'retry_payment').
  final List<String> actions;

  factory AttentionItem.fromJson(Json json) => AttentionItem(
    kind: AttentionKind.fromDb(strOrNull(json['kind'] ?? json['type'])),
    title: str(json['title']),
    detail: strOrNull(json['detail'] ?? json['description']),
    link: json['link'] is Map
        ? RecordLink.fromJson(asJson(json['link']))
        : null,
    ref: strOrNull(json['ref']),
    since: dtOrNull(json['since'] ?? json['created_at']),
    outletId: strOrNull(json['outlet_id']),
    severity: str(json['severity'], 'warning'),
    actions: asStringList(json['actions']),
  );

  Json toJson() => compact({
    'kind': kind.db,
    'title': title,
    'detail': detail,
    'link': link?.toJson(),
    'ref': ref,
    'since': iso(since),
    'outlet_id': outletId,
    'severity': severity,
    'actions': actions.isEmpty ? null : actions,
  });

  @override
  List<Object?> get props => [kind, title, detail, link, ref, since, severity];
}

/// `team_load[]` row (STF-061).
class TeamLoadRow extends Equatable {
  const TeamLoadRow({
    required this.staffId,
    required this.name,
    required this.activeTasks,
    required this.capacity,
    this.availability = AvailabilityStatus.available,
    this.avatarUrl,
  });

  final String staffId;
  final String name;
  final int activeTasks;
  final int capacity;
  final AvailabilityStatus availability;
  final String? avatarUrl;

  double get load => capacity == 0 ? 1 : (activeTasks / capacity).clamp(0, 1);
  bool get isAvailable =>
      activeTasks == 0 && availability == AvailabilityStatus.available;

  /// "2 tasks" / "Available"
  String get label => isAvailable
      ? 'Available'
      : '$activeTasks task${activeTasks == 1 ? '' : 's'}';

  String get initials {
    final parts = name
        .trim()
        .split(RegExp(r'\s+'))
        .where((p) => p.isNotEmpty)
        .toList();
    if (parts.isEmpty) return '?';
    if (parts.length == 1) {
      return parts.first
          .substring(0, parts.first.length.clamp(0, 2))
          .toUpperCase();
    }
    return (parts.first[0] + parts.last[0]).toUpperCase();
  }

  factory TeamLoadRow.fromJson(Json json) => TeamLoadRow(
    staffId: str(json['staff_id'] ?? json['id']),
    name: str(json['name'] ?? json['full_name']),
    activeTasks: intOf(json['active_tasks']),
    capacity: intOf(json['capacity'], 3),
    availability: AvailabilityStatus.fromDb(
      strOrNull(json['availability'] ?? json['status']),
    ),
    avatarUrl: strOrNull(json['avatar_url']),
  );

  Json toJson() => compact({
    'staff_id': staffId,
    'name': name,
    'active_tasks': activeTasks,
    'capacity': capacity,
    'availability': availability.db,
    'avatar_url': avatarUrl,
  });

  @override
  List<Object?> get props => [
    staffId,
    name,
    activeTasks,
    capacity,
    availability,
  ];
}

/// `GET /staff/ops-summary` → `{ counts, needs_attention[], team_load[] }`.
class OpsSummary extends Equatable {
  const OpsSummary({
    required this.counts,
    this.needsAttention = const [],
    this.teamLoad = const [],
    this.generatedAt,
  });

  final OpsCounts counts;
  final List<AttentionItem> needsAttention;
  final List<TeamLoadRow> teamLoad;
  final DateTime? generatedAt;

  factory OpsSummary.fromJson(Json json) => OpsSummary(
    counts: OpsCounts.fromJson(asJson(json['counts'])),
    needsAttention: asJsonList(json['needs_attention'])
        .map(AttentionItem.fromJson)
        .toList(),
    teamLoad: asJsonList(json['team_load']).map(TeamLoadRow.fromJson).toList(),
    generatedAt: dtOrNull(json['generated_at']),
  );

  Json toJson() => compact({
    'counts': counts.toJson(),
    'needs_attention': needsAttention.map((a) => a.toJson()).toList(),
    'team_load': teamLoad.map((t) => t.toJson()).toList(),
    'generated_at': iso(generatedAt),
  });

  @override
  List<Object?> get props => [counts, needsAttention, teamLoad];
}
