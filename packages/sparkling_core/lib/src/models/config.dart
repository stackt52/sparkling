import 'package:equatable/equatable.dart';

import 'json.dart';

/// Public feature flags from `GET /config` (readable before sign-in).
class PublicFlags extends Equatable {
  const PublicFlags({
    this.cashOnCollection = false,
    this.paymentsSandbox = false,
    this.whatsappEnabled = false,
    this.raw = const {},
  });

  /// Customers may choose **Cash on collection** at "Review & pay"; staff
  /// record the cash at the counter before the keys are released.
  final bool cashOnCollection;

  /// Sandbox payment confirmation is available (`POST /payments/:id/sandbox-confirm`).
  final bool paymentsSandbox;

  /// WhatsApp notifications are wired up (Twilio).
  final bool whatsappEnabled;

  /// Every flag the server sent, keyed as-is (for flags added later).
  final Map<String, bool> raw;

  bool operator [](String key) => raw[key] ?? false;

  factory PublicFlags.fromJson(Json json) {
    final raw = <String, bool>{
      for (final e in json.entries) e.key: boolOf(e.value),
    };
    return PublicFlags(
      cashOnCollection: raw['cash_on_collection'] ?? false,
      paymentsSandbox: raw['payments_sandbox'] ?? false,
      whatsappEnabled: raw['whatsapp_enabled'] ?? false,
      raw: raw,
    );
  }

  Json toJson() => {
    ...raw,
    'cash_on_collection': cashOnCollection,
    'payments_sandbox': paymentsSandbox,
    'whatsapp_enabled': whatsappEnabled,
  };

  @override
  List<Object?> get props => [
    cashOnCollection,
    paymentsSandbox,
    whatsappEnabled,
    raw,
  ];
}

/// `GET /config` → `{ flags: { cash_on_collection, payments_sandbox, whatsapp_enabled } }`.
class AppConfig extends Equatable {
  const AppConfig({this.flags = const PublicFlags(), this.fetchedAt});

  /// Safe default when the API cannot be reached: every flag off.
  static const AppConfig defaults = AppConfig();

  final PublicFlags flags;

  /// When the config was fetched (null for [defaults]).
  final DateTime? fetchedAt;

  factory AppConfig.fromJson(Json json, {DateTime? fetchedAt}) => AppConfig(
    flags: PublicFlags.fromJson(asJsonOrNull(json['flags']) ?? const {}),
    fetchedAt: fetchedAt ?? dtOrNull(json['fetched_at']),
  );

  Json toJson() =>
      compact({'flags': flags.toJson(), 'fetched_at': iso(fetchedAt)});

  @override
  List<Object?> get props => [flags, fetchedAt];
}
