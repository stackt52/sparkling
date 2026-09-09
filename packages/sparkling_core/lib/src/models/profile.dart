import 'package:equatable/equatable.dart';

import 'enums.dart';
import 'json.dart';

/// `profiles` row (id = Firebase UID).
class Profile extends Equatable {
  const Profile({
    required this.id,
    required this.role,
    required this.fullName,
    this.email,
    this.phone,
    this.avatarUrl,
    this.isActive = true,
    this.marketingOptIn = false,
    this.whatsappOptIn = true,
    this.pushOptIn = true,
    this.locale = 'en-ZA',
    this.reducedMotion = false,
    this.haptics = true,
    this.outletIds = const [],
    this.lastSeenAt,
    this.createdAt,
    this.updatedAt,
  });

  final String id;
  final UserRole role;
  final String fullName;
  final String? email;
  final String? phone;
  final String? avatarUrl;
  final bool isActive;
  final bool marketingOptIn;
  final bool whatsappOptIn;
  final bool pushOptIn;
  final String locale;
  final bool reducedMotion;
  final bool haptics;

  /// Outlets the (staff) profile may access — from claims / `staff_outlets`.
  final List<String> outletIds;
  final DateTime? lastSeenAt;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  String get firstName => fullName.trim().split(RegExp(r'\s+')).first;

  /// "TN" for "Thabo Nkosi".
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

  factory Profile.fromJson(Json json) => Profile(
    id: str(json['id']),
    role: UserRole.fromDb(strOrNull(json['role'])),
    fullName: str(json['full_name']),
    email: strOrNull(json['email']),
    phone: strOrNull(json['phone']),
    avatarUrl: strOrNull(json['avatar_url']),
    isActive: boolOf(json['is_active'], true),
    marketingOptIn: boolOf(json['marketing_opt_in']),
    whatsappOptIn: boolOf(json['whatsapp_opt_in'], true),
    pushOptIn: boolOf(json['push_opt_in'], true),
    locale: str(json['locale'], 'en-ZA'),
    reducedMotion: boolOf(json['reduced_motion']),
    haptics: boolOf(json['haptics'], true),
    outletIds: asStringList(json['outlet_ids']),
    lastSeenAt: dtOrNull(json['last_seen_at']),
    createdAt: dtOrNull(json['created_at']),
    updatedAt: dtOrNull(json['updated_at']),
  );

  Json toJson() => compact({
    'id': id,
    'role': role.db,
    'full_name': fullName,
    'email': email,
    'phone': phone,
    'avatar_url': avatarUrl,
    'is_active': isActive,
    'marketing_opt_in': marketingOptIn,
    'whatsapp_opt_in': whatsappOptIn,
    'push_opt_in': pushOptIn,
    'locale': locale,
    'reduced_motion': reducedMotion,
    'haptics': haptics,
    'outlet_ids': outletIds,
    'last_seen_at': iso(lastSeenAt),
    'created_at': iso(createdAt),
    'updated_at': iso(updatedAt),
  });

  Profile copyWith({
    String? id,
    UserRole? role,
    String? fullName,
    String? email,
    String? phone,
    String? avatarUrl,
    bool? isActive,
    bool? marketingOptIn,
    bool? whatsappOptIn,
    bool? pushOptIn,
    String? locale,
    bool? reducedMotion,
    bool? haptics,
    List<String>? outletIds,
    DateTime? lastSeenAt,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) => Profile(
    id: id ?? this.id,
    role: role ?? this.role,
    fullName: fullName ?? this.fullName,
    email: email ?? this.email,
    phone: phone ?? this.phone,
    avatarUrl: avatarUrl ?? this.avatarUrl,
    isActive: isActive ?? this.isActive,
    marketingOptIn: marketingOptIn ?? this.marketingOptIn,
    whatsappOptIn: whatsappOptIn ?? this.whatsappOptIn,
    pushOptIn: pushOptIn ?? this.pushOptIn,
    locale: locale ?? this.locale,
    reducedMotion: reducedMotion ?? this.reducedMotion,
    haptics: haptics ?? this.haptics,
    outletIds: outletIds ?? this.outletIds,
    lastSeenAt: lastSeenAt ?? this.lastSeenAt,
    createdAt: createdAt ?? this.createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
  );

  @override
  List<Object?> get props => [
    id,
    role,
    fullName,
    email,
    phone,
    avatarUrl,
    isActive,
    marketingOptIn,
    whatsappOptIn,
    pushOptIn,
    locale,
    reducedMotion,
    haptics,
    outletIds,
    updatedAt,
  ];
}

/// Editable subset for `PATCH /me`.
class ProfileUpdate {
  const ProfileUpdate({
    this.fullName,
    this.phone,
    this.avatarUrl,
    this.marketingOptIn,
    this.whatsappOptIn,
    this.pushOptIn,
    this.locale,
    this.reducedMotion,
    this.haptics,
  });

  final String? fullName;
  final String? phone;
  final String? avatarUrl;
  final bool? marketingOptIn;
  final bool? whatsappOptIn;
  final bool? pushOptIn;
  final String? locale;
  final bool? reducedMotion;
  final bool? haptics;

  Json toJson() => compact({
    'full_name': fullName,
    'phone': phone,
    'avatar_url': avatarUrl,
    'marketing_opt_in': marketingOptIn,
    'whatsapp_opt_in': whatsappOptIn,
    'push_opt_in': pushOptIn,
    'locale': locale,
    'reduced_motion': reducedMotion,
    'haptics': haptics,
  });
}

/// `GET /me` → `{ profile, outlets[], loyalty_account? }` (loyalty decoded by the caller).
class MeResponse {
  const MeResponse({
    required this.profile,
    this.outlets = const [],
    this.loyaltyAccount,
  });

  final Profile profile;
  final List<Json> outlets;
  final Json? loyaltyAccount;

  factory MeResponse.fromJson(Json json) => MeResponse(
    profile: Profile.fromJson(asJson(json['profile'])),
    outlets: asJsonList(json['outlets']),
    loyaltyAccount: asJsonOrNull(json['loyalty_account']),
  );
}

/// `POST /auth/session` → `{ profile, claims_updated }`.
class SessionResponse {
  const SessionResponse({required this.profile, required this.claimsUpdated});

  final Profile profile;
  final bool claimsUpdated;

  factory SessionResponse.fromJson(Json json) => SessionResponse(
    profile: Profile.fromJson(asJson(json['profile'])),
    claimsUpdated: boolOf(json['claims_updated']),
  );
}
