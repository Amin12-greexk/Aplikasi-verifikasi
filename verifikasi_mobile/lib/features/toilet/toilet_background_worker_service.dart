import 'dart:ui';

import 'package:flutter/widgets.dart';
import 'package:workmanager/workmanager.dart';

import '../../core/config/config.dart';
import '../../core/services/auth_service.dart';
import '../../core/services/local_notification_service.dart';
import 'toilet_expiry_monitor_service.dart';

const String _toiletWorkerUniqueName = 'toilet-expiry-background-worker';
const String _toiletWorkerTaskName = 'toilet-expiry-background-check';

@pragma('vm:entry-point')
void toiletBackgroundCallbackDispatcher() {
  Workmanager().executeTask((task, inputData) async {
    try {
      WidgetsFlutterBinding.ensureInitialized();
      DartPluginRegistrant.ensureInitialized();

      await AuthService.init();
      if (!AuthService.isLoggedIn ||
          !(AuthService.isPengawas() || AuthService.isSecurity())) {
        return true;
      }

      await ServerConfig.init();
      await LocalNotificationService.init();
      await ToiletExpiryMonitorService.refreshNow();
      return true;
    } catch (e) {
      debugPrint('[ToiletWorker] Background check failed: $e');
      return false;
    }
  });
}

class ToiletBackgroundWorkerService {
  static bool _initialized = false;

  static Future<void> initialize() async {
    if (_initialized) return;
    await Workmanager().initialize(toiletBackgroundCallbackDispatcher);
    _initialized = true;
  }

  static Future<void> syncWithCurrentUser() async {
    await initialize();
    await AuthService.init();

    if (!AuthService.isLoggedIn ||
        !(AuthService.isPengawas() || AuthService.isSecurity())) {
      await cancel();
      return;
    }

    await Workmanager().registerPeriodicTask(
      _toiletWorkerUniqueName,
      _toiletWorkerTaskName,
      frequency: const Duration(minutes: 15),
      initialDelay: const Duration(minutes: 15),
      constraints: Constraints(networkType: NetworkType.connected),
      existingWorkPolicy: ExistingPeriodicWorkPolicy.update,
      backoffPolicy: BackoffPolicy.linear,
      backoffPolicyDelay: const Duration(minutes: 1),
      tag: _toiletWorkerTaskName,
    );
  }

  static Future<void> cancel() async {
    await initialize();
    await Workmanager().cancelByUniqueName(_toiletWorkerUniqueName);
  }
}
