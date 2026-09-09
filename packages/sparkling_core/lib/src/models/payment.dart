import 'package:equatable/equatable.dart';

import 'enums.dart';
import 'json.dart';

/// `payment_methods` row — tokenised only (SEC-009).
class PaymentMethod extends Equatable {
  const PaymentMethod({
    required this.id,
    required this.customerId,
    this.provider = 'sandbox',
    this.brand,
    this.last4,
    this.label,
    this.isDefault = false,
    this.createdAt,
  });

  final String id;
  final String customerId;
  final String provider;

  /// 'visa' | 'mastercard' | 'eft'
  final String? brand;
  final String? last4;
  final String? label;
  final bool isDefault;
  final DateTime? createdAt;

  bool get isCard => brand != 'eft';

  /// "Visa •••• 4242" / "Instant EFT"
  String get displayLabel =>
      label ??
      (isCard ? '${_brandName(brand)} •••• ${last4 ?? ''}' : 'Instant EFT');

  static String _brandName(String? b) => switch (b) {
    'visa' => 'Visa',
    'mastercard' => 'Mastercard',
    'amex' => 'Amex',
    _ => b ?? 'Card',
  };

  factory PaymentMethod.fromJson(Json json) => PaymentMethod(
    id: str(json['id']),
    customerId: str(json['customer_id']),
    provider: str(json['provider'], 'sandbox'),
    brand: strOrNull(json['brand']),
    last4: strOrNull(json['last4']),
    label: strOrNull(json['label']),
    isDefault: boolOf(json['is_default']),
    createdAt: dtOrNull(json['created_at']),
  );

  Json toJson() => compact({
    'id': id,
    'customer_id': customerId,
    'provider': provider,
    'brand': brand,
    'last4': last4,
    'label': label,
    'is_default': isDefault,
    'created_at': iso(createdAt),
  });

  PaymentMethod copyWith({bool? isDefault, String? label}) => PaymentMethod(
    id: id,
    customerId: customerId,
    provider: provider,
    brand: brand,
    last4: last4,
    label: label ?? this.label,
    isDefault: isDefault ?? this.isDefault,
    createdAt: createdAt,
  );

  @override
  List<Object?> get props => [
    id,
    customerId,
    provider,
    brand,
    last4,
    label,
    isDefault,
  ];
}

/// Body for `POST /payments/methods` (token from the provider SDK — never a PAN).
class PaymentMethodInput {
  const PaymentMethodInput({
    required this.providerToken,
    required this.brand,
    this.last4,
    this.label,
  });
  final String providerToken;
  final String brand;
  final String? last4;
  final String? label;
  Json toJson() => compact({
    'provider_token': providerToken,
    'brand': brand,
    'last4': last4,
    'label': label,
  });
}

/// `payments` row (+ `receipt` on `GET /payments/:id`).
class Payment extends Equatable {
  const Payment({
    required this.id,
    required this.customerId,
    required this.amountCents,
    required this.status,
    this.bookingId,
    this.quotationId,
    this.provider = 'sandbox',
    this.providerRef,
    this.methodId,
    this.currency = 'ZAR',
    this.receiptNo,
    this.idempotencyKey,
    this.failureReason,
    this.verifiedAt,
    this.createdAt,
    this.updatedAt,
    this.receipt,
  });

  final String id;
  final String? bookingId;
  final String? quotationId;
  final String customerId;
  final String provider;
  final String? providerRef;
  final String? methodId;
  final int amountCents;
  final String currency;
  final PaymentStatus status;
  final String? receiptNo;
  final String? idempotencyKey;
  final String? failureReason;

  /// Set only by the webhook / sandbox confirm (CUS-041).
  final DateTime? verifiedAt;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  /// Receipt payload when included (`GET /payments/:id`).
  final Json? receipt;

  bool get isVerified => status.isVerified && verifiedAt != null;

  factory Payment.fromJson(Json json) => Payment(
    id: str(json['id']),
    bookingId: strOrNull(json['booking_id']),
    quotationId: strOrNull(json['quotation_id']),
    customerId: str(json['customer_id']),
    provider: str(json['provider'], 'sandbox'),
    providerRef: strOrNull(json['provider_ref']),
    methodId: strOrNull(json['method_id']),
    amountCents: intOf(json['amount_cents']),
    currency: str(json['currency'], 'ZAR'),
    status: PaymentStatus.fromDb(strOrNull(json['status'])),
    receiptNo: strOrNull(json['receipt_no']),
    idempotencyKey: strOrNull(json['idempotency_key']),
    failureReason: strOrNull(json['failure_reason']),
    verifiedAt: dtOrNull(json['verified_at']),
    createdAt: dtOrNull(json['created_at']),
    updatedAt: dtOrNull(json['updated_at']),
    receipt: asJsonOrNull(json['receipt']),
  );

  Json toJson() => compact({
    'id': id,
    'booking_id': bookingId,
    'quotation_id': quotationId,
    'customer_id': customerId,
    'provider': provider,
    'provider_ref': providerRef,
    'method_id': methodId,
    'amount_cents': amountCents,
    'currency': currency,
    'status': status.db,
    'receipt_no': receiptNo,
    'idempotency_key': idempotencyKey,
    'failure_reason': failureReason,
    'verified_at': iso(verifiedAt),
    'created_at': iso(createdAt),
    'updated_at': iso(updatedAt),
    'receipt': receipt,
  });

  Payment copyWith({
    PaymentStatus? status,
    String? receiptNo,
    String? failureReason,
    DateTime? verifiedAt,
    DateTime? updatedAt,
    Json? receipt,
  }) => Payment(
    id: id,
    bookingId: bookingId,
    quotationId: quotationId,
    customerId: customerId,
    provider: provider,
    providerRef: providerRef,
    methodId: methodId,
    amountCents: amountCents,
    currency: currency,
    status: status ?? this.status,
    receiptNo: receiptNo ?? this.receiptNo,
    idempotencyKey: idempotencyKey,
    failureReason: failureReason ?? this.failureReason,
    verifiedAt: verifiedAt ?? this.verifiedAt,
    createdAt: createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
    receipt: receipt ?? this.receipt,
  );

  @override
  List<Object?> get props => [
    id,
    bookingId,
    customerId,
    amountCents,
    status,
    receiptNo,
    verifiedAt,
    updatedAt,
  ];
}

/// `POST /payments/intents` → `{ payment, client_secret?, redirect_url? }`.
class PaymentIntentResult extends Equatable {
  const PaymentIntentResult({
    required this.payment,
    this.clientSecret,
    this.redirectUrl,
  });
  final Payment payment;
  final String? clientSecret;
  final String? redirectUrl;

  factory PaymentIntentResult.fromJson(Json json) => PaymentIntentResult(
    payment: Payment.fromJson(asJson(json['payment'] ?? json)),
    clientSecret: strOrNull(json['client_secret']),
    redirectUrl: strOrNull(json['redirect_url']),
  );
  Json toJson() => compact({
    'payment': payment.toJson(),
    'client_secret': clientSecret,
    'redirect_url': redirectUrl,
  });
  @override
  List<Object?> get props => [payment, clientSecret, redirectUrl];
}
