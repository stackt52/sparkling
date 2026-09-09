import 'package:equatable/equatable.dart';

import 'enums.dart';
import 'json.dart';

/// `loyalty_accounts` row (trigger-maintained cache; ledger is authoritative).
class LoyaltyAccount extends Equatable {
  const LoyaltyAccount({
    required this.customerId,
    required this.tier,
    required this.balancePoints,
    this.lifetimePoints = 0,
    this.tierSince,
    this.updatedAt,
  });

  final String customerId;
  final LoyaltyTier tier;
  final int balancePoints;
  final int lifetimePoints;
  final DateTime? tierSince;
  final DateTime? updatedAt;

  factory LoyaltyAccount.fromJson(Json json) => LoyaltyAccount(
    customerId: str(json['customer_id']),
    tier: LoyaltyTier.fromDb(strOrNull(json['tier'])),
    balancePoints: intOf(json['balance_points']),
    lifetimePoints: intOf(json['lifetime_points']),
    tierSince: dtOrNull(json['tier_since']),
    updatedAt: dtOrNull(json['updated_at']),
  );

  Json toJson() => compact({
    'customer_id': customerId,
    'tier': tier.db,
    'balance_points': balancePoints,
    'lifetime_points': lifetimePoints,
    'tier_since': iso(tierSince),
    'updated_at': iso(updatedAt),
  });

  LoyaltyAccount copyWith({
    LoyaltyTier? tier,
    int? balancePoints,
    int? lifetimePoints,
    DateTime? tierSince,
    DateTime? updatedAt,
  }) => LoyaltyAccount(
    customerId: customerId,
    tier: tier ?? this.tier,
    balancePoints: balancePoints ?? this.balancePoints,
    lifetimePoints: lifetimePoints ?? this.lifetimePoints,
    tierSince: tierSince ?? this.tierSince,
    updatedAt: updatedAt ?? this.updatedAt,
  );

  @override
  List<Object?> get props => [
    customerId,
    tier,
    balancePoints,
    lifetimePoints,
    tierSince,
  ];
}

/// One entry of `loyalty_configs.tiers`.
class LoyaltyTierConfig extends Equatable {
  const LoyaltyTierConfig({
    required this.tier,
    required this.name,
    required this.minPoints,
    this.maxPoints,
    this.earnMultiplier = 1.0,
    this.discountPct = 0,
  });

  final LoyaltyTier tier;
  final String name;
  final int minPoints;
  final int? maxPoints;
  final double earnMultiplier;
  final int discountPct;

  /// "0 – 499 pts" / "2 000+ pts"
  String get qualifyRange =>
      maxPoints == null ? '$minPoints+ pts' : '$minPoints – $maxPoints pts';

  factory LoyaltyTierConfig.fromJson(Json json) => LoyaltyTierConfig(
    tier: LoyaltyTier.fromDb(strOrNull(json['tier'])),
    name: str(json['name'], LoyaltyTier.fromDb(strOrNull(json['tier'])).label),
    minPoints: intOf(json['min_points']),
    maxPoints: intOrNull(json['max_points']),
    earnMultiplier: dbl(json['earn_multiplier'], 1),
    discountPct: intOf(json['discount_pct']),
  );

  Json toJson() => {
    'tier': tier.db,
    'name': name,
    'min_points': minPoints,
    'max_points': maxPoints,
    'earn_multiplier': earnMultiplier,
    'discount_pct': discountPct,
  };

  LoyaltyTierConfig copyWith({
    int? minPoints,
    int? maxPoints,
    double? earnMultiplier,
    int? discountPct,
  }) => LoyaltyTierConfig(
    tier: tier,
    name: name,
    minPoints: minPoints ?? this.minPoints,
    maxPoints: maxPoints ?? this.maxPoints,
    earnMultiplier: earnMultiplier ?? this.earnMultiplier,
    discountPct: discountPct ?? this.discountPct,
  );

  @override
  List<Object?> get props => [
    tier,
    name,
    minPoints,
    maxPoints,
    earnMultiplier,
    discountPct,
  ];
}

/// Optional bonus rule (`birthday_bonus`, `referral_bonus`).
class BonusRule extends Equatable {
  const BonusRule({required this.enabled, required this.points, this.reason});
  final bool enabled;
  final int points;

  /// Why it is disabled (e.g. "Pending consent review (ADM-042)").
  final String? reason;

  factory BonusRule.fromJson(Json json) => BonusRule(
    enabled: boolOf(json['enabled']),
    points: intOf(json['points']),
    reason: strOrNull(json['reason']),
  );
  Json toJson() =>
      compact({'enabled': enabled, 'points': points, 'reason': reason});
  BonusRule copyWith({bool? enabled, int? points, String? reason}) => BonusRule(
    enabled: enabled ?? this.enabled,
    points: points ?? this.points,
    reason: reason ?? this.reason,
  );
  @override
  List<Object?> get props => [enabled, points, reason];
}

/// `loyalty_configs.rules`.
class LoyaltyRules extends Equatable {
  const LoyaltyRules({
    this.pointsPerRand = 0.10,
    this.awardOn = 'completion',
    this.idempotentAward = true,
    this.expiryMonths = 24,
    this.birthdayBonus = const BonusRule(enabled: false, points: 0),
    this.referralBonus = const BonusRule(enabled: false, points: 0),
  });

  final double pointsPerRand;
  final String awardOn;
  final bool idempotentAward;
  final int expiryMonths;
  final BonusRule birthdayBonus;
  final BonusRule referralBonus;

  factory LoyaltyRules.fromJson(Json json) => LoyaltyRules(
    pointsPerRand: dbl(json['points_per_rand'], 0.10),
    awardOn: str(json['award_on'], 'completion'),
    idempotentAward: boolOf(json['idempotent_award'], true),
    expiryMonths: intOf(json['expiry_months'], 24),
    birthdayBonus: BonusRule.fromJson(asJson(json['birthday_bonus'])),
    referralBonus: BonusRule.fromJson(asJson(json['referral_bonus'])),
  );

  Json toJson() => {
    'points_per_rand': pointsPerRand,
    'award_on': awardOn,
    'idempotent_award': idempotentAward,
    'expiry_months': expiryMonths,
    'birthday_bonus': birthdayBonus.toJson(),
    'referral_bonus': referralBonus.toJson(),
  };

  LoyaltyRules copyWith({
    double? pointsPerRand,
    String? awardOn,
    bool? idempotentAward,
    int? expiryMonths,
    BonusRule? birthdayBonus,
    BonusRule? referralBonus,
  }) => LoyaltyRules(
    pointsPerRand: pointsPerRand ?? this.pointsPerRand,
    awardOn: awardOn ?? this.awardOn,
    idempotentAward: idempotentAward ?? this.idempotentAward,
    expiryMonths: expiryMonths ?? this.expiryMonths,
    birthdayBonus: birthdayBonus ?? this.birthdayBonus,
    referralBonus: referralBonus ?? this.referralBonus,
  );

  @override
  List<Object?> get props => [
    pointsPerRand,
    awardOn,
    idempotentAward,
    expiryMonths,
    birthdayBonus,
    referralBonus,
  ];
}

/// `loyalty_configs` row (versioned; one published at a time — ADM-025).
class LoyaltyConfig extends Equatable {
  const LoyaltyConfig({
    required this.version,
    required this.status,
    required this.tiers,
    required this.rules,
    this.id,
    this.changeNote,
    this.createdBy,
    this.publishedBy,
    this.publishedAt,
    this.createdAt,
  });

  final String? id;
  final int version;
  final ConfigStatus status;
  final List<LoyaltyTierConfig> tiers;
  final LoyaltyRules rules;
  final String? changeNote;
  final String? createdBy;
  final String? publishedBy;
  final DateTime? publishedAt;
  final DateTime? createdAt;

  LoyaltyTierConfig? tierConfig(LoyaltyTier tier) {
    for (final t in tiers) {
      if (t.tier == tier) return t;
    }
    return null;
  }

  /// Tier for a lifetime-points value.
  LoyaltyTier tierFor(int points) {
    LoyaltyTier result = LoyaltyTier.silver;
    for (final t in tiers) {
      if (points >= t.minPoints) result = t.tier;
    }
    return result;
  }

  /// Points still needed for the next tier, or null at the top tier.
  int? pointsToNextTier(LoyaltyTier current, int points) {
    final next = current.next;
    if (next == null) return null;
    final cfg = tierConfig(next);
    if (cfg == null) return null;
    return (cfg.minPoints - points).clamp(0, cfg.minPoints);
  }

  factory LoyaltyConfig.fromJson(Json json) => LoyaltyConfig(
    id: strOrNull(json['id']),
    version: intOf(json['version']),
    status: ConfigStatus.fromDb(strOrNull(json['status'])),
    tiers: asJsonList(json['tiers']).map(LoyaltyTierConfig.fromJson).toList(),
    rules: LoyaltyRules.fromJson(asJson(json['rules'])),
    changeNote: strOrNull(json['change_note']),
    createdBy: strOrNull(json['created_by']),
    publishedBy: strOrNull(json['published_by']),
    publishedAt: dtOrNull(json['published_at']),
    createdAt: dtOrNull(json['created_at']),
  );

  Json toJson() => compact({
    'id': id,
    'version': version,
    'status': status.db,
    'tiers': tiers.map((t) => t.toJson()).toList(),
    'rules': rules.toJson(),
    'change_note': changeNote,
    'created_by': createdBy,
    'published_by': publishedBy,
    'published_at': iso(publishedAt),
    'created_at': iso(createdAt),
  });

  /// Body for `PUT /admin/loyalty/config/draft`.
  Json toDraftJson({String? changeNote}) => {
    'tiers': tiers.map((t) => t.toJson()).toList(),
    'rules': rules.toJson(),
    'change_note': changeNote ?? this.changeNote,
  };

  LoyaltyConfig copyWith({
    int? version,
    ConfigStatus? status,
    List<LoyaltyTierConfig>? tiers,
    LoyaltyRules? rules,
    String? changeNote,
    DateTime? publishedAt,
    String? publishedBy,
  }) => LoyaltyConfig(
    id: id,
    version: version ?? this.version,
    status: status ?? this.status,
    tiers: tiers ?? this.tiers,
    rules: rules ?? this.rules,
    changeNote: changeNote ?? this.changeNote,
    createdBy: createdBy,
    publishedBy: publishedBy ?? this.publishedBy,
    publishedAt: publishedAt ?? this.publishedAt,
    createdAt: createdAt,
  );

  @override
  List<Object?> get props => [
    id,
    version,
    status,
    tiers,
    rules,
    changeNote,
    publishedAt,
  ];
}

/// `next_tier{name, points_needed}`.
class NextTier extends Equatable {
  const NextTier({
    required this.tier,
    required this.name,
    required this.pointsNeeded,
  });
  final LoyaltyTier tier;
  final String name;
  final int pointsNeeded;

  factory NextTier.fromJson(Json json) {
    final tier = LoyaltyTier.fromDb(
      strOrNull(json['tier']) ?? str(json['name']).toLowerCase(),
    );
    return NextTier(
      tier: tier,
      name: str(json['name'], tier.label),
      pointsNeeded: intOf(json['points_needed']),
    );
  }
  Json toJson() => {
    'tier': tier.db,
    'name': name,
    'points_needed': pointsNeeded,
  };
  @override
  List<Object?> get props => [tier, name, pointsNeeded];
}

/// `GET /loyalty/account` → `{ account, tier_config, next_tier, published_version }`.
class LoyaltyAccountSummary extends Equatable {
  const LoyaltyAccountSummary({
    required this.account,
    this.tierConfig = const [],
    this.nextTier,
    this.publishedVersion,
  });

  final LoyaltyAccount account;
  final List<LoyaltyTierConfig> tierConfig;
  final NextTier? nextTier;
  final int? publishedVersion;

  LoyaltyTier get tier => account.tier;
  int get balance => account.balancePoints;

  LoyaltyTierConfig? get currentTierConfig {
    for (final t in tierConfig) {
      if (t.tier == account.tier) return t;
    }
    return null;
  }

  /// 0…1 progress from the current tier floor to the next tier floor.
  double get progressToNextTier {
    final cur = currentTierConfig;
    final next = nextTier;
    if (cur == null || next == null) return 1;
    final nextCfg = tierConfig.where((t) => t.tier == next.tier).firstOrNull;
    if (nextCfg == null) return 1;
    final span = nextCfg.minPoints - cur.minPoints;
    if (span <= 0) return 1;
    return ((account.lifetimePoints - cur.minPoints) / span).clamp(0, 1);
  }

  /// "550 pts to Platinum"
  String? get nextTierLabel => nextTier == null
      ? null
      : '${nextTier!.pointsNeeded} pts to ${nextTier!.name}';

  factory LoyaltyAccountSummary.fromJson(Json json) => LoyaltyAccountSummary(
    account: LoyaltyAccount.fromJson(asJson(json['account'] ?? json)),
    tierConfig: asJsonList(json['tier_config'] ?? json['tiers'])
        .map(LoyaltyTierConfig.fromJson)
        .toList(),
    nextTier: json['next_tier'] is Map
        ? NextTier.fromJson(asJson(json['next_tier']))
        : null,
    publishedVersion: intOrNull(json['published_version']),
  );

  Json toJson() => compact({
    'account': account.toJson(),
    'tier_config': tierConfig.map((t) => t.toJson()).toList(),
    'next_tier': nextTier?.toJson(),
    'published_version': publishedVersion,
  });

  LoyaltyAccountSummary copyWith({
    LoyaltyAccount? account,
    NextTier? nextTier,
    bool clearNextTier = false,
  }) => LoyaltyAccountSummary(
    account: account ?? this.account,
    tierConfig: tierConfig,
    nextTier: clearNextTier ? null : (nextTier ?? this.nextTier),
    publishedVersion: publishedVersion,
  );

  @override
  List<Object?> get props => [account, tierConfig, nextTier, publishedVersion];
}

/// `loyalty_ledger` row (append-only — CUS-063).
class LedgerEntry extends Equatable {
  const LedgerEntry({
    required this.id,
    required this.customerId,
    required this.delta,
    required this.type,
    this.sourceType,
    this.sourceId,
    this.reference,
    this.description,
    this.idempotencyKey,
    this.expiresAt,
    this.createdBy,
    this.createdAt,
  });

  final String id;
  final String customerId;
  final int delta;
  final LedgerType type;
  final String? sourceType;
  final String? sourceId;

  /// e.g. "SPK-2026-0067" / "RW-1182"
  final String? reference;
  final String? description;
  final String? idempotencyKey;
  final DateTime? expiresAt;
  final String? createdBy;
  final DateTime? createdAt;

  bool get isCredit => delta >= 0;

  /// "Premium Detail · SPK-2026-0067"
  String get title => [
    description,
    reference,
  ].where((s) => s != null && s.isNotEmpty).join(' · ');

  factory LedgerEntry.fromJson(Json json) => LedgerEntry(
    id: str(json['id']),
    customerId: str(json['customer_id']),
    delta: intOf(json['delta']),
    type: LedgerType.fromDb(strOrNull(json['type'])),
    sourceType: strOrNull(json['source_type']),
    sourceId: strOrNull(json['source_id']),
    reference: strOrNull(json['reference']),
    description: strOrNull(json['description']),
    idempotencyKey: strOrNull(json['idempotency_key']),
    expiresAt: dtOrNull(json['expires_at']),
    createdBy: strOrNull(json['created_by']),
    createdAt: dtOrNull(json['created_at']),
  );

  Json toJson() => compact({
    'id': id,
    'customer_id': customerId,
    'delta': delta,
    'type': type.db,
    'source_type': sourceType,
    'source_id': sourceId,
    'reference': reference,
    'description': description,
    'idempotency_key': idempotencyKey,
    'expires_at': iso(expiresAt),
    'created_by': createdBy,
    'created_at': iso(createdAt),
  });

  @override
  List<Object?> get props => [
    id,
    customerId,
    delta,
    type,
    reference,
    description,
    createdAt,
  ];
}

/// `rewards` row.
class Reward extends Equatable {
  const Reward({
    required this.id,
    required this.name,
    required this.pointsCost,
    this.description,
    this.icon = 'auto_awesome',
    this.minTier = LoyaltyTier.silver,
    this.isActive = true,
    this.sortOrder = 100,
  });

  final String id;
  final String name;
  final String? description;
  final String icon;
  final int pointsCost;
  final LoyaltyTier minTier;
  final bool isActive;
  final int sortOrder;

  bool eligibleFor(LoyaltyTier tier) => tier.index >= minTier.index;
  bool affordableWith(int balance) => balance >= pointsCost;

  factory Reward.fromJson(Json json) => Reward(
    id: str(json['id']),
    name: str(json['name']),
    description: strOrNull(json['description']),
    icon: str(json['icon'], 'auto_awesome'),
    pointsCost: intOf(json['points_cost']),
    minTier: LoyaltyTier.fromDb(strOrNull(json['min_tier'])),
    isActive: boolOf(json['is_active'], true),
    sortOrder: intOf(json['sort_order'], 100),
  );

  Json toJson() => compact({
    'id': id,
    'name': name,
    'description': description,
    'icon': icon,
    'points_cost': pointsCost,
    'min_tier': minTier.db,
    'is_active': isActive,
    'sort_order': sortOrder,
  });

  @override
  List<Object?> get props => [id, name, pointsCost, minTier, isActive];
}

/// `POST /loyalty/rewards/:id/redeem` result: ledger entry + redemption code.
class RewardRedemption extends Equatable {
  const RewardRedemption({
    required this.id,
    required this.rewardId,
    required this.code,
    required this.status,
    this.ledger,
    this.balanceAfter,
    this.createdAt,
  });

  final String id;
  final String rewardId;
  final String code;

  /// 'issued' | 'used' | 'expired' | 'cancelled'
  final String status;
  final LedgerEntry? ledger;
  final int? balanceAfter;
  final DateTime? createdAt;

  factory RewardRedemption.fromJson(Json json) {
    final r = asJsonOrNull(json['redemption']) ?? json;
    return RewardRedemption(
      id: str(r['id']),
      rewardId: str(r['reward_id']),
      code: str(r['code']),
      status: str(r['status'], 'issued'),
      ledger: json['ledger'] is Map
          ? LedgerEntry.fromJson(asJson(json['ledger']))
          : null,
      balanceAfter:
          intOrNull(json['balance_after']) ??
          intOrNull(asJsonOrNull(json['account'])?['balance_points']),
      createdAt: dtOrNull(r['created_at']),
    );
  }

  Json toJson() => compact({
    'redemption': {
      'id': id,
      'reward_id': rewardId,
      'code': code,
      'status': status,
      'created_at': iso(createdAt),
    },
    'ledger': ledger?.toJson(),
    'balance_after': balanceAfter,
  });

  @override
  List<Object?> get props => [id, rewardId, code, status, balanceAfter];
}
