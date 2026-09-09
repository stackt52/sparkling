import 'dart:io' show Platform;

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:sparkling_core/sparkling_core.dart';

/// Registers the FCM device token with `POST /devices` (INT-003).
///
/// Skipped in demo mode and when no token is available (e.g. iOS simulator,
/// where APNs is unavailable). Never throws.
abstract final class PushRegistration {
  static Future<void> register(Repositories repositories) async {
    final api = repositories.api;
    if (repositories.demo || api == null) return;
    try {
      final messaging = FirebaseMessaging.instance;
      await messaging.requestPermission();
      if (Platform.isIOS) {
        // On the simulator (and before APNs registers) this stays null and
        // getToken() would throw — bail out quietly.
        final apns = await messaging.getAPNSToken();
        if (apns == null) {
          debugPrint('Push: no APNs token (simulator?) — skipping');
          return;
        }
      }
      final token = await messaging.getToken();
      if (token == null || token.isEmpty) return;
      await api.registerDevice(
        DeviceTokenInput(
          token: token,
          platform: Platform.isIOS ? 'ios' : 'android',
          app: 'customer',
        ),
      );
    } catch (e) {
      debugPrint('Push registration skipped: $e');
    }
  }
}
