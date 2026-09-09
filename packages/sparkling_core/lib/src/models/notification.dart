import 'package:equatable/equatable.dart';

import 'enums.dart';
import 'json.dart';

/// `notifications` row (NOT-003). Named `AppNotification` to avoid clashing
/// with Flutter's `Notification`.
class AppNotification extends Equatable {
  const AppNotification({
    required this.id,
    required this.recipientId,
    required this.channel,
    required this.templateKey,
    required this.body,
    this.title,
    this.payload = const {},
    this.status = NotifyStatus.queued,
    this.providerRef,
    this.error,
    this.attempts = 0,
    this.dedupeKey,
    this.readAt,
    this.sentAt,
    this.createdAt,
  });

  final String id;
  final String recipientId;
  final NotifyChannel channel;

  /// e.g. 'booking_confirmed', 'service_ready', 'quote_ready'
  final String templateKey;
  final String? title;
  final String body;
  final Json payload;
  final NotifyStatus status;
  final String? providerRef;
  final String? error;
  final int attempts;
  final String? dedupeKey;
  final DateTime? readAt;
  final DateTime? sentAt;
  final DateTime? createdAt;

  bool get isRead => readAt != null;

  /// Deep-link target from the payload, when present (`{type, id}`).
  String? get linkType => strOrNull(payload['type'] ?? payload['link_type']);
  String? get linkId => strOrNull(payload['id'] ?? payload['link_id']);

  factory AppNotification.fromJson(Json json) => AppNotification(
    id: str(json['id']),
    recipientId: str(json['recipient_id']),
    channel: NotifyChannel.fromDb(strOrNull(json['channel'])),
    templateKey: str(json['template_key']),
    title: strOrNull(json['title']),
    body: str(json['body']),
    payload: asJson(json['payload']),
    status: NotifyStatus.fromDb(strOrNull(json['status'])),
    providerRef: strOrNull(json['provider_ref']),
    error: strOrNull(json['error']),
    attempts: intOf(json['attempts']),
    dedupeKey: strOrNull(json['dedupe_key']),
    readAt: dtOrNull(json['read_at']),
    sentAt: dtOrNull(json['sent_at']),
    createdAt: dtOrNull(json['created_at']),
  );

  Json toJson() => compact({
    'id': id,
    'recipient_id': recipientId,
    'channel': channel.db,
    'template_key': templateKey,
    'title': title,
    'body': body,
    'payload': payload.isEmpty ? null : payload,
    'status': status.db,
    'provider_ref': providerRef,
    'error': error,
    'attempts': attempts,
    'dedupe_key': dedupeKey,
    'read_at': iso(readAt),
    'sent_at': iso(sentAt),
    'created_at': iso(createdAt),
  });

  AppNotification copyWith({
    NotifyStatus? status,
    DateTime? readAt,
    DateTime? sentAt,
  }) => AppNotification(
    id: id,
    recipientId: recipientId,
    channel: channel,
    templateKey: templateKey,
    title: title,
    body: body,
    payload: payload,
    status: status ?? this.status,
    providerRef: providerRef,
    error: error,
    attempts: attempts,
    dedupeKey: dedupeKey,
    readAt: readAt ?? this.readAt,
    sentAt: sentAt ?? this.sentAt,
    createdAt: createdAt,
  );

  @override
  List<Object?> get props => [
    id,
    recipientId,
    channel,
    templateKey,
    title,
    body,
    status,
    readAt,
    createdAt,
  ];
}

/// Body for `POST /devices`.
class DeviceTokenInput {
  const DeviceTokenInput({
    required this.token,
    required this.platform,
    required this.app,
  });
  final String token;

  /// 'android' | 'ios' | 'web'
  final String platform;

  /// 'customer' | 'staff' | 'admin'
  final String app;
  Json toJson() => {'token': token, 'platform': platform, 'app': app};
}
