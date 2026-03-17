import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/services/local_notification_service.dart';
import 'toilet_permit_service.dart';

class ToiletExpiryMonitorService {
  static const Duration _pollInterval = Duration(seconds: 10);
  static const String _prefsKey = 'toilet_expiry_notified_keys';

  static Timer? _timer;
  static bool _running = false;
  static bool _checking = false;
  static bool _loaded = false;
  static final Set<String> _notifiedKeys = <String>{};

  static Future<void> start() async {
    if (_running) return;

    await _loadState();
    await LocalNotificationService.init();

    _running = true;
    await refreshNow();
    _timer = Timer.periodic(_pollInterval, (_) {
      refreshNow();
    });
  }

  static void stop() {
    _timer?.cancel();
    _timer = null;
    _running = false;
  }

  static Future<void> refreshNow() async {
    if (_checking) return;
    if (!_loaded) {
      await _loadState();
    }

    _checking = true;
    try {
      final permits = await ToiletPermitService.fetchExpiredAlerts();
      final currentKeys = <String>{};

      for (final permit in permits) {
        final key = _buildKey(permit);
        currentKeys.add(key);

        if (_notifiedKeys.contains(key)) {
          continue;
        }

        final employeeLabel = _extractEmployeeLabel(
          permit['id_karyawan']?.toString() ?? '',
        );

        await LocalNotificationService.showToiletExpired(
          id: _buildNotificationId(key),
          title: 'Waktu toilet sudah habis',
          body: '$employeeLabel belum scan security.',
        );
        _notifiedKeys.add(key);
      }

      _notifiedKeys.removeWhere((key) => !currentKeys.contains(key));
      await _saveState();
    } catch (e) {
      debugPrint('[ToiletExpiryMonitor] Failed to check permits: $e');
    } finally {
      _checking = false;
    }
  }

  static String _buildKey(Map<String, dynamic> permit) {
    final id = permit['id_karyawan']?.toString().trim() ?? '';
    final expiresAt = permit['expires_at']?.toString().trim() ?? '';
    return '$id::$expiresAt';
  }

  static int _buildNotificationId(String key) => key.hashCode & 0x7fffffff;

  static String _extractEmployeeLabel(String barcode) {
    final pin = _extractValue(barcode, 'PIN');
    final nama = _extractValue(barcode, 'Nama');
    final bagian = _extractValue(barcode, 'Bagian');

    if (nama.isNotEmpty && pin.isNotEmpty && bagian.isNotEmpty) {
      return '$nama (PIN: $pin) - $bagian';
    }
    if (nama.isNotEmpty && pin.isNotEmpty) {
      return '$nama (PIN: $pin)';
    }
    if (pin.isNotEmpty) return 'PIN: $pin';
    return barcode.isEmpty ? 'Mitra' : barcode;
  }

  static String _extractValue(String barcode, String key) {
    final parts = barcode.split('|').map((part) => part.trim()).toList();
    for (final part in parts) {
      if (part.startsWith('$key:')) {
        return part.substring(key.length + 1).trim();
      }
    }
    return '';
  }

  static Future<void> _loadState() async {
    final prefs = await SharedPreferences.getInstance();
    _notifiedKeys
      ..clear()
      ..addAll(prefs.getStringList(_prefsKey) ?? const <String>[]);
    _loaded = true;
  }

  static Future<void> _saveState() async {
    final prefs = await SharedPreferences.getInstance();
    final sortedKeys = _notifiedKeys.toList()..sort();
    await prefs.setStringList(_prefsKey, sortedKeys);
  }
}
