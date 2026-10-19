import 'dart:async';

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:sparkling_core/sparkling_core.dart';

import 'router.dart';

/// Handles FCM messages once the staff app is running (INT-003):
///
/// * a push received in the foreground (e.g. `task_verify_requested` when a
///   checklist reaches its supervisor step, `task_assigned`) bumps the live
///   task streams (`announceLocalChange`) so the Mine tab refreshes at once,
///   and shows a snack with an **Open** action;
/// * tapping a notification (app in background or terminated) opens the
///   linked checklist using the `{type, <type>_id}` payload `notify()` sends.
class StaffPushMessages {
  StaffPushMessages({required this.router, required this.messenger});

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
    announceLocalChange(tableForStaffPush(m.data) ?? 'notifications');
    final route = routeForStaffPush(m.data);
    final title = m.notification?.title;
    final body = m.notification?.body;
    if (title == null && body == null) return;
    messenger.currentState
      ?..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text([title, body].whereType<String>().join(' — ')),
          duration: const Duration(seconds: 8),
          action: route == null
              ? null
              : SnackBarAction(
                  label: 'Open',
                  onPressed: () => router.push(route),
                ),
        ),
      );
  }

  void _open(RemoteMessage m) {
    router.push(routeForStaffPush(m.data) ?? Routes.tasks);
  }
}

/// Table a push payload refers to (any value bumps every `refetchOn` stream;
/// the name is for logging/intent).
@visibleForTesting
String? tableForStaffPush(Map<String, dynamic> data) =>
    switch (data['type']?.toString()) {
      'task' || 'work_order' => 'tasks',
      'inventory' => 'inventory_items',
      _ => null,
    };

/// Deep link for a push payload (`type` + `<type>_id`, as the API sends):
/// tasks and work orders open their checklist.
@visibleForTesting
String? routeForStaffPush(Map<String, dynamic> data) {
  String? id(String key) {
    final v = data[key]?.toString();
    return (v == null || v.isEmpty) ? null : v;
  }

  switch (data['type']?.toString()) {
    case 'task' || 'work_order':
      final wo = id('work_order_id');
      return wo == null ? Routes.tasks : Routes.checklist(wo);
    case 'inventory':
      return Routes.inventory;
    default:
      return null;
  }
}
