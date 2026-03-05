import 'dart:convert';

import 'package:http/http.dart' as http;

/// Attendance service (read-only) using SPL API by employee PIN.
class AttendanceService {
  static const String _baseUrlRaw = String.fromEnvironment(
    'ATTENDANCE_API_BASE_URL',
    defaultValue: 'https://spl.estaindonesia.com/apiv2',
  );

  static const String _apiToken = String.fromEnvironment(
    'ATTENDANCE_API_TOKEN',
    defaultValue: 'dff4f683-ed10-11f0-af43-f89e94d63c41',
  );

  static String get _baseUrl {
    // Prevent auth header loss caused by HTTP -> HTTPS redirect.
    var value = _baseUrlRaw.trim();
    if (value.startsWith('http://')) {
      value = value.replaceFirst('http://', 'https://');
    }
    return value.replaceAll(RegExp(r'/+$'), '');
  }

  static Uri _buildAbsenUri(String pin) {
    return Uri.parse('$_baseUrl/absen').replace(
      queryParameters: {
        'pin': pin,
        // Keep query token for compatibility with APIs that require query auth.
        'token': _apiToken,
      },
    );
  }

  static Map<String, String> get _headers => {
    'Accept': 'application/json',
    // Keep headers for compatibility with APIs that require header auth.
    'Authorization': 'Bearer $_apiToken',
    'X-API-Token': _apiToken,
  };

  static DateTime? _parseScanDate(String? raw) {
    if (raw == null || raw.trim().isEmpty) return null;

    final trimmed = raw.trim();
    try {
      return DateTime.parse(trimmed);
    } catch (_) {
      // SPL format usually "yyyy-MM-dd HH:mm:ss"
      try {
        return DateTime.parse(trimmed.replaceFirst(' ', 'T'));
      } catch (_) {
        return null;
      }
    }
  }

  static List<dynamic> _extractRawList(dynamic decoded) {
    if (decoded is List) return decoded;

    if (decoded is Map<String, dynamic>) {
      const candidates = [
        'data',
        'result',
        'results',
        'absen',
        'records',
        'attendance',
      ];
      for (final key in candidates) {
        final value = decoded[key];
        if (value is List) return value;
      }

      if (decoded.containsKey('pin') && decoded.containsKey('scan_date')) {
        return [decoded];
      }
    }

    return const [];
  }

  static Map<String, dynamic> _normalizeRecord(Map<String, dynamic> raw) {
    return {
      'pin': raw['pin']?.toString() ?? '',
      'scan_date': raw['scan_date']?.toString() ?? '',
      'sn': raw['sn']?.toString() ?? '',
      'mode': raw['mode']?.toString() ?? '',
    };
  }

  /// Fetch all attendance records by PIN (newest first).
  static Future<List<Map<String, dynamic>>> fetchByPin(String pin) async {
    final normalizedPin = pin.trim();
    if (normalizedPin.isEmpty) {
      throw Exception('PIN wajib diisi');
    }

    final response = await http.get(
      _buildAbsenUri(normalizedPin),
      headers: _headers,
    );

    if (response.statusCode >= 400) {
      throw Exception(
        'Gagal mengambil absensi PIN $normalizedPin (HTTP ${response.statusCode})',
      );
    }

    final decoded = jsonDecode(response.body);
    final rawList = _extractRawList(decoded);

    final records = rawList
        .whereType<Map>()
        .map((item) => _normalizeRecord(Map<String, dynamic>.from(item)))
        .toList();

    records.sort((a, b) {
      final da = _parseScanDate(a['scan_date']?.toString());
      final db = _parseScanDate(b['scan_date']?.toString());
      if (da == null && db == null) return 0;
      if (da == null) return 1;
      if (db == null) return -1;
      return db.compareTo(da);
    });

    return records;
  }

  /// Return today's summary by PIN: check-in, check-out, latest mode.
  static Future<Map<String, dynamic>?> getTodayStatusByPin(String pin) async {
    final records = await fetchByPin(pin);
    if (records.isEmpty) return null;

    final today = DateTime.now();
    final todayRecords = records.where((record) {
      final dt = _parseScanDate(record['scan_date']?.toString());
      if (dt == null) return false;
      return dt.year == today.year &&
          dt.month == today.month &&
          dt.day == today.day;
    }).toList();

    final source = todayRecords.isNotEmpty ? todayRecords : records;

    Map<String, dynamic>? firstMasuk;
    Map<String, dynamic>? lastPulang;

    for (final record in source.reversed) {
      final mode = record['mode']?.toString().toLowerCase() ?? '';
      if (mode.contains('masuk') && firstMasuk == null) {
        firstMasuk = record;
      }
      if (mode.contains('pulang')) {
        lastPulang = record;
      }
    }

    final latest = source.first;

    return {
      'pin': pin,
      'check_in': firstMasuk?['scan_date'],
      'check_out': lastPulang?['scan_date'],
      'latest_mode': latest['mode'],
      'latest_scan_date': latest['scan_date'],
      'records': source,
    };
  }

  /// Check if attendance endpoint is reachable.
  static Future<bool> isAvailable() async {
    try {
      final response = await http.get(_buildAbsenUri('0'), headers: _headers);
      // Any non-5xx response means endpoint is reachable.
      return response.statusCode < 500;
    } catch (_) {
      return false;
    }
  }

  /// Fetch attendance history (optionally by date) by PIN.
  static Future<List<Map<String, dynamic>>> getHistory({
    required String pin,
    String? date,
  }) async {
    final records = await fetchByPin(pin);
    if (date == null || date.trim().isEmpty) return records;

    final normalizedDate = date.trim();
    return records.where((record) {
      final scanDate = record['scan_date']?.toString() ?? '';
      return scanDate.startsWith(normalizedDate);
    }).toList();
  }
}
