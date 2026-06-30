import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

class LocalNotificationService {
  static const String _channelId = 'toilet_expiry_channel';
  static const String _channelName = 'Toilet Expiry Alerts';
  static const String _channelDescription =
      'Notifikasi ketika waktu izin toilet sudah habis.';

  static final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();

  static bool _initialized = false;
  static bool? _notificationsAllowed;

  static Future<void> init() async {
    if (_initialized) return;

    const androidSettings = AndroidInitializationSettings(
      '@mipmap/ic_launcher',
    );
    const settings = InitializationSettings(android: androidSettings);

    await _plugin.initialize(settings);

    final androidPlugin = _plugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >();

    await androidPlugin?.createNotificationChannel(
      const AndroidNotificationChannel(
        _channelId,
        _channelName,
        description: _channelDescription,
        importance: Importance.max,
      ),
    );
    _notificationsAllowed =
        await androidPlugin?.requestNotificationsPermission() ?? true;

    _initialized = true;
  }

  static Future<bool> showToiletExpired({
    required int id,
    required String title,
    required String body,
  }) async {
    try {
      await init();
      final androidPlugin = _plugin
          .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin
          >();
      final notificationsEnabled =
          await androidPlugin?.areNotificationsEnabled() ??
          _notificationsAllowed ??
          true;

      if (!notificationsEnabled) {
        debugPrint('[LocalNotification] Notification permission is disabled');
        return false;
      }

      await _plugin.show(
        id,
        title,
        body,
        const NotificationDetails(
          android: AndroidNotificationDetails(
            _channelId,
            _channelName,
            channelDescription: _channelDescription,
            importance: Importance.max,
            priority: Priority.high,
            category: AndroidNotificationCategory.reminder,
            playSound: true,
            enableVibration: true,
            visibility: NotificationVisibility.public,
          ),
        ),
      );
      return true;
    } catch (e) {
      debugPrint('[LocalNotification] Failed to show notification: $e');
      return false;
    }
  }
}
