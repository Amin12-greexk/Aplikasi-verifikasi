import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';

import '../network/base_api_client.dart';
import 'auth_service.dart';
import 'local_notification_service.dart';

/// Background handler. Notification messages are displayed automatically by the
/// Android system when the app is in background/terminated, so this only needs
/// to exist and be registered — no manual display required.
@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  // Intentionally empty: system shows the notification payload automatically.
}

/// Firebase Cloud Messaging integration: registers the device token with the
/// server so the backend can push "waktu toilet habis" alerts even when the
/// app is closed.
class FcmService {
  static bool _initialized = false;
  static String? _lastToken;

  static Future<void> init() async {
    if (_initialized) return;
    try {
      await Firebase.initializeApp();
      FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);

      final messaging = FirebaseMessaging.instance;
      await messaging.requestPermission(alert: true, badge: true, sound: true);

      // App in foreground → system does NOT auto-display; show it ourselves.
      FirebaseMessaging.onMessage.listen(_handleForegroundMessage);

      // Token can rotate; keep the server in sync.
      messaging.onTokenRefresh.listen((token) {
        _lastToken = token;
        _registerToken(token);
      });

      _initialized = true;
    } catch (e) {
      debugPrint('[FCM] init failed: $e');
    }
  }

  /// Registers the current device token for the logged-in user. Call after
  /// login and on app start when already logged in.
  static Future<void> syncToken() async {
    try {
      if (!_initialized) await init();
      if (!AuthService.isLoggedIn) return;
      final token = await FirebaseMessaging.instance.getToken();
      if (token == null || token.isEmpty) return;
      _lastToken = token;
      await _registerToken(token);
    } catch (e) {
      debugPrint('[FCM] syncToken failed: $e');
    }
  }

  /// Removes this device's token from the server (call on logout).
  static Future<void> unregister() async {
    try {
      final token =
          _lastToken ?? await FirebaseMessaging.instance.getToken();
      if (token == null || token.isEmpty) return;
      await BaseApiClient.post('/devices/unregister', body: {'token': token});
    } catch (e) {
      debugPrint('[FCM] unregister failed: $e');
    }
  }

  static Future<void> _registerToken(String token) async {
    try {
      if (!AuthService.isLoggedIn) return;
      final role = AuthService.role?.toString().split('.').last;
      await BaseApiClient.post(
        '/devices/register',
        body: {
          'token': token,
          'username': AuthService.username,
          'role': role,
          'platform': 'android',
        },
      );
    } catch (e) {
      debugPrint('[FCM] register token failed: $e');
    }
  }

  static Future<void> _handleForegroundMessage(RemoteMessage message) async {
    final notification = message.notification;
    final title =
        notification?.title ?? message.data['title']?.toString() ?? 'Notifikasi';
    final body =
        notification?.body ?? message.data['body']?.toString() ?? '';
    final idSource =
        message.messageId ?? DateTime.now().millisecondsSinceEpoch.toString();
    await LocalNotificationService.showToiletExpired(
      id: idSource.hashCode & 0x7fffffff,
      title: title,
      body: body,
    );
  }
}
