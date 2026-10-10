import 'dart:async';
import 'dart:io' show Platform;

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:sparkling_core/sparkling_core.dart';

/// Registers the FCM device token with `POST /devices` (INT-003).
///
/// Skipped in demo mode and when no token is available (e.g. iOS simulator,
/// where APNs is unavailable). Never throws.
///
/// On iOS the APNs token arrives asynchronously after the permission prompt,
/// so [register] polls for it briefly instead of giving up on the first null;
/// without it `getToken()` throws and the device would never be registered,
/// leaving every push (quote ready, keys collected…) stored `queued` and
/// visible only in the in-app inbox. Token rotations are re-registered via
/// `onTokenRefresh`.
abstract final class PushRegistration {
  static const int _apnsAttempts = 10;
  static const Duration _apnsRetry = Duration(seconds: 1);

  static StreamSubscription<String>? _refresh;

  static Future<void> register(Repositories repositories) async {
    final api = repositories.api;
    if (repositories.demo || api == null) return;
    try {
      final messaging = FirebaseMessaging.instance;
      await messaging.requestPermission();
      if (Platform.isIOS) {
        String? apns;
        for (var i = 0; i < _apnsAttempts && apns == null; i++) {
          apns = await messaging.getAPNSToken();
          if (apns == null) await Future<void>.delayed(_apnsRetry);
        }
        if (apns == null) {
          // Simulator, or the build lacks the aps-environment entitlement.
          debugPrint(
            'Push: no APNs token after ${_apnsAttempts * _apnsRetry.inSeconds} s — skipping registration',
          );
          return;
        }
      }
      final token = await messaging.getToken();
      if (token == null || token.isEmpty) return;
      await _send(api, token);
      _refresh ??= messaging.onTokenRefresh.listen(
        (t) => unawaited(
          _send(api, t).catchError(
            (Object e) => debugPrint('Push: re-registration failed: $e'),
          ),
        ),
      );
    } catch (e) {
      debugPrint('Push registration skipped: $e');
    }
  }

  static Future<void> _send(SparklingApi api, String token) =>
      api.registerDevice(
        DeviceTokenInput(
          token: token,
          platform: Platform.isIOS ? 'ios' : 'android',
          app: 'customer',
        ),
      );
}
