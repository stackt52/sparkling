import 'dart:async';

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:sparkling_core/sparkling_core.dart';

import 'router.dart';

/// Handles FCM messages once the app is running (INT-003, CUS-032):
///
/// * a push received while the app is in the foreground bumps the live
///   streams (`announceLocalChange`) so the quotes list, bookings and home
///   hero refetch at once, and shows a snack with a **View** action;
/// * tapping a notification (app in background or terminated) opens the
///   linked screen — the quote for `quote_ready`, the booking for booking
///   updates — using the `{type, <type>_id}` payload `notify()` sends.
class PushMessages {
  PushMessages({required this.router, required this.messenger});

  final GoRouter router;
  final GlobalKey<ScaffoldMessengerState> messenger;
  final List<StreamSubscription<RemoteMessage>> _subs = [];

  /// Never throws (Firebase may be unavailable, e.g. in tests).
  Future<void> start() async {
    try {
      _subs.add(FirebaseMessaging.onMessage.listen(_onForeground));
      _subs.add(FirebaseMessaging.onMessageOpenedApp.listen(_open));
      final initial = await FirebaseMessaging.instance.getInitialMessage();
      if (initial != null) _open(initial);
    } catch (e) {
      debugPrint('Push messages unavailable: $e');
    }
  }

  void dispose() {
    for (final s in _subs) {
      s.cancel();
    }
    _subs.clear();
  }

  void _onForeground(RemoteMessage m) {
    announceLocalChange(tableForPush(m.data) ?? 'notifications');
    final route = routeForPush(m.data);
    final title = m.notification?.title;
    final body = m.notification?.body;
    if (title == null && body == null) return;
    messenger.currentState
      ?..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text([title, body].whereType<String>().join(' — ')),
          duration: const Duration(seconds: 6),
          action: route == null
              ? null
              : SnackBarAction(
                  label: 'View',
                  onPressed: () => router.push(route),
                ),
        ),
      );
  }

  void _open(RemoteMessage m) {
    router.push(routeForPush(m.data) ?? Routes.notifications);
  }
}

/// Table a push payload refers to (drives which live streams refetch; any
/// value bumps every `refetchOn` stream, the name is for logging/intent).
@visibleForTesting
String? tableForPush(Map<String, dynamic> data) =>
    switch (data['type']?.toString()) {
      'quotation' => 'quotations',
      'booking' || 'payment' || 'loyalty' || 'work_order' => 'bookings',
      'membership' => 'memberships',
      _ => null,
    };

/// Deep link for a push payload (`type` + `<type>_id`, as the API sends).
@visibleForTesting
String? routeForPush(Map<String, dynamic> data) {
  String? id(String key) {
    final v = data[key]?.toString();
    return (v == null || v.isEmpty) ? null : v;
  }

  switch (data['type']?.toString()) {
    case 'quotation':
      final q = id('quotation_id') ?? id('id');
      return q == null ? Routes.quotes : Routes.quote(q);
    case 'booking' || 'payment' || 'loyalty':
      final b = id('booking_id') ?? id('id');
      return b == null ? Routes.bookings : Routes.bookingDetail(b);
    case 'work_order':
      final b = id('booking_id');
      return b == null ? Routes.bookings : Routes.track(b);
    case 'membership':
      return Routes.membership;
    default:
      return null;
  }
}
