import '../../core/network/base_api_client.dart';
import '../../core/services/auth_service.dart';

/// Abstraction layer for all verification-related API calls.
class VerificationService {
  /// App-level status abstraction used by UI.
  static const String statusApproved = 'approved';
  static const String statusPending = 'pending';

  /// Server/API status constants.
  static const String _apiStatusAcc = 'ACC';
  static const String _apiStatusPending = 'PENDING';

  /// Returns true for both app (`approved`) and API (`ACC`) values.
  static bool isApprovedStatus(Object? status) {
    final value = status?.toString().trim().toUpperCase() ?? '';
    return value == _apiStatusAcc || value == 'APPROVED';
  }

  static String _normalizeStatusForApp(Object? status) {
    return isApprovedStatus(status) ? statusApproved : statusPending;
  }

  static String _normalizeStatusForApi(String status) {
    return isApprovedStatus(status) ? _apiStatusAcc : _apiStatusPending;
  }

  static Map<String, dynamic> _normalizeLog(Map<String, dynamic> raw) {
    final pengawasBy =
        raw['pengawas_scanned_by']?.toString() ??
        raw['scanned_by_pengawas']?.toString();
    final securityBy =
        raw['security_scanned_by']?.toString() ??
        raw['scanned_by_security']?.toString();
    final pengawasAt =
        raw['pengawas_scanned_at']?.toString() ??
        raw['scan_time_pengawas']?.toString();
    final securityAt =
        raw['security_scanned_at']?.toString() ??
        raw['scan_time_security']?.toString();

    return {
      ...raw,
      'status_pengawas': _normalizeStatusForApp(raw['status_pengawas']),
      'status_security': _normalizeStatusForApp(raw['status_security']),
      // Canonical keys used by server API.
      'pengawas_scanned_by': pengawasBy,
      'security_scanned_by': securityBy,
      'pengawas_scanned_at': pengawasAt,
      'security_scanned_at': securityAt,
      // Compatibility aliases used in current UI.
      'scanned_by_pengawas': pengawasBy,
      'scanned_by_security': securityBy,
      'scan_time_pengawas': pengawasAt,
      'scan_time_security': securityAt,
    };
  }

  static List<Map<String, dynamic>> _normalizeLogs(List<dynamic> logs) {
    return logs
        .whereType<Map>()
        .map((e) => _normalizeLog(Map<String, dynamic>.from(e)))
        .toList();
  }

  /// Approve pengawas scan
  static Future<Map<String, dynamic>> accPengawas(String id) async {
    final response = await BaseApiClient.post(
      '/scan-pengawas',
      body: {'id_karyawan': id, 'username': AuthService.username},
    );
    final data = BaseApiClient.tryJson(response.body);
    if (response.statusCode >= 400) {
      throw Exception(data['error'] ?? 'Gagal ACC pengawas');
    }
    return data.containsKey('status_pengawas') ? _normalizeLog(data) : data;
  }

  /// Approve security scan
  static Future<Map<String, dynamic>> accSecurity(String id) async {
    final response = await BaseApiClient.post(
      '/scan-security',
      body: {'id_karyawan': id, 'username': AuthService.username},
    );
    final data = BaseApiClient.tryJson(response.body);
    if (response.statusCode >= 400) {
      throw Exception(data['error'] ?? 'Gagal ACC security');
    }
    return data.containsKey('status_pengawas') ? _normalizeLog(data) : data;
  }

  /// Fetch all logs for today
  static Future<List<Map<String, dynamic>>> fetchLogs() async {
    final response = await BaseApiClient.get('/logs');
    if (response.statusCode >= 400) {
      final body = BaseApiClient.tryJson(response.body);
      throw Exception(body['error'] ?? 'Gagal mengambil data');
    }
    final body = BaseApiClient.tryJson(response.body);
    final List<dynamic> logs = body['logs'] ?? [];
    return _normalizeLogs(logs);
  }

  /// Fetch logs by specific date
  static Future<List<Map<String, dynamic>>> fetchLogsByDate(String date) async {
    final response = await BaseApiClient.get('/logs-history/$date');
    if (response.statusCode >= 400) {
      final body = BaseApiClient.tryJson(response.body);
      throw Exception(body['error'] ?? 'Gagal mengambil data');
    }
    final body = BaseApiClient.tryJson(response.body);
    final List<dynamic> logs = body['logs'] ?? [];
    return _normalizeLogs(logs);
  }

  /// Daily reset
  static Future<Map<String, dynamic>> dailyReset() async {
    final response = await BaseApiClient.post('/daily-reset');
    final data = BaseApiClient.tryJson(response.body);
    if (response.statusCode >= 400) {
      throw Exception(data['error'] ?? 'Gagal melakukan daily reset');
    }
    return data;
  }

  /// Delete a log
  static Future<void> deleteLog(String idKaryawan) async {
    final response = await BaseApiClient.delete('/logs/$idKaryawan');
    if (response.statusCode >= 400) {
      final data = BaseApiClient.tryJson(response.body);
      throw Exception(data['error'] ?? 'Gagal menghapus log');
    }
  }

  /// Update log status
  static Future<Map<String, dynamic>> updateLogStatus(
    String idKaryawan,
    String statusPengawas,
    String statusSecurity,
  ) async {
    final response = await BaseApiClient.put(
      '/logs/$idKaryawan',
      body: {
        'status_pengawas': _normalizeStatusForApi(statusPengawas),
        'status_security': _normalizeStatusForApi(statusSecurity),
      },
    );
    final data = BaseApiClient.tryJson(response.body);
    if (response.statusCode >= 400) {
      throw Exception(data['error'] ?? 'Gagal mengupdate log');
    }
    return data.containsKey('status_pengawas') ? _normalizeLog(data) : data;
  }

  /// Create a new log
  static Future<Map<String, dynamic>> createLog(
    String idKaryawan,
    String statusPengawas,
    String statusSecurity,
  ) async {
    final response = await BaseApiClient.post(
      '/logs',
      body: {
        'id_karyawan': idKaryawan,
        'status_pengawas': _normalizeStatusForApi(statusPengawas),
        'status_security': _normalizeStatusForApi(statusSecurity),
      },
    );
    final data = BaseApiClient.tryJson(response.body);
    if (response.statusCode >= 400) {
      throw Exception(data['error'] ?? 'Gagal membuat log');
    }
    return data.containsKey('status_pengawas') ? _normalizeLog(data) : data;
  }

  /// Fetch single log status by ID
  static Future<Map<String, dynamic>> fetchStatus(String id) async {
    final response = await BaseApiClient.get('/status/${Uri.encodeComponent(id)}');
    final data = BaseApiClient.tryJson(response.body);
    if (response.statusCode >= 400) {
      throw Exception(data['error'] ?? 'Gagal mengambil status');
    }
    return _normalizeLog(data);
  }

  /// Check server connectivity
  static Future<bool> checkConnectivity() async {
    return BaseApiClient.checkConnectivity();
  }
}
