import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/services/local_notification_service.dart';
import 'toilet_permit_service.dart';

class ToiletExpiryMonitorService {
  static const Duration _pollInterval = Duration(seconds: 10);
  static const String _prefsKey = 'toilet_expiry_notified_keys';
  static const String _lastCheckedAtPrefsKey = 'toilet_expiry_last_checked_at';
  static const int _summaryNotificationId = 44001;

  static Timer? _timer;
  static bool _running = false;
  static bool _checking = false;
  static bool _loaded = false;
  static DateTime? _lastCheckedAtUtc;
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
      final checkedAtUtc = DateTime.now().toUtc();
      final previousCheckedAtUtc = _lastCheckedAtUtc;
      final permits = await ToiletPermitService.fetchExpiredAlerts();
      final currentKeys = <String>{};
      final newAlerts = <Map<String, dynamic>>[];
      final newAlertKeys = <String>[];

      for (final permit in permits) {
        final key = _buildKey(permit);
        currentKeys.add(key);

        if (_notifiedKeys.contains(key)) {
          continue;
        }

        final expiresAtUtc = _parseDateTimeUtc(
          permit['expires_at']?.toString(),
        );
        final isNewSinceLastCheck =
            previousCheckedAtUtc != null &&
            expiresAtUtc != null &&
            expiresAtUtc.isAfter(previousCheckedAtUtc);

        if (!isNewSinceLastCheck) {
          _notifiedKeys.add(key);
          continue;
        }

        newAlerts.add(permit);
        newAlertKeys.add(key);
      }

      if (newAlerts.isNotEmpty) {
        final shown = await _showExpiryNotification(newAlerts);
        if (shown) _notifiedKeys.addAll(newAlertKeys);
      }

      _notifiedKeys.removeWhere((key) => !currentKeys.contains(key));
      _lastCheckedAtUtc = checkedAtUtc;
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

  static Future<bool> _showExpiryNotification(
    List<Map<String, dynamic>> alerts,
  ) {
    if (alerts.length == 1) {
      final permit = alerts.first;
      final key = _buildKey(permit);
      final employeeLabel = _extractEmployeeLabel(
        permit['id_karyawan']?.toString() ?? '',
      );
      return LocalNotificationService.showToiletExpired(
        id: _buildNotificationId(key),
        title: 'Waktu toilet sudah habis',
        body: '$employeeLabel sudah melewati batas waktu toilet.',
      );
    }

    final labels = alerts
        .take(3)
        .map((permit) {
          return _extractEmployeeLabel(permit['id_karyawan']?.toString() ?? '');
        })
        .where((label) => label.trim().isNotEmpty)
        .join(', ');
    final remaining = alerts.length - 3;
    final suffix = remaining > 0 ? ', dan $remaining lainnya' : '';

    return LocalNotificationService.showToiletExpired(
      id: _summaryNotificationId,
      title: '${alerts.length} izin toilet melewati batas',
      body: '$labels$suffix perlu dicek. Buka aplikasi untuk melihat daftar.',
    );
  }

  static DateTime? _parseDateTimeUtc(String? raw) {
    if (raw == null || raw.trim().isEmpty) return null;
    return DateTime.tryParse(raw.trim())?.toUtc();
  }

  static String _extractEmployeeLabel(String barcode) {
    final pin = _extractValue(barcode, 'PIN');
    final nik = _extractValue(barcode, 'NIK');
    final nama = _extractValue(barcode, 'Nama');
    final bagian = _extractValue(barcode, 'Bagian');

    if (nama.isNotEmpty && pin.isNotEmpty && bagian.isNotEmpty) {
      return '$nama (PIN: $pin) - $bagian';
    }
    if (nama.isNotEmpty && nik.isNotEmpty && bagian.isNotEmpty) {
      return '$nama (NIK: $nik) - $bagian';
    }
    if (nama.isNotEmpty && pin.isNotEmpty) {
      return '$nama (PIN: $pin)';
    }
    if (nama.isNotEmpty && nik.isNotEmpty) {
      return '$nama (NIK: $nik)';
    }
    if (pin.isNotEmpty) return 'PIN: $pin';
    if (nik.isNotEmpty) return 'NIK: $nik';
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
    _lastCheckedAtUtc = _parseDateTimeUtc(
      prefs.getString(_lastCheckedAtPrefsKey),
    );
    _loaded = true;
  }

  static Future<void> _saveState() async {
    final prefs = await SharedPreferences.getInstance();
    final sortedKeys = _notifiedKeys.toList()..sort();
    await prefs.setStringList(_prefsKey, sortedKeys);
    final lastCheckedAt = _lastCheckedAtUtc;
    if (lastCheckedAt != null) {
      await prefs.setString(
        _lastCheckedAtPrefsKey,
        lastCheckedAt.toIso8601String(),
      );
    }
  }
}
