import '../../core/network/base_api_client.dart';
import '../../core/services/auth_service.dart';
import '../../core/utils/wib_time.dart';

/// API client for toilet permit approval, timer, and proof scan flows.
class ToiletPermitService {
  static const String stateActive = 'active';
  static const String stateExpired = 'expired';
  static const String stateWaitingSecurity = 'waiting_security';
  static const String proofPending = 'pending';
  static const String proofScanned = 'scanned';

  static String _resolveErrorMessage(
    Map<String, dynamic> data,
    String fallback, {
    int? statusCode,
  }) {
    final raw = data['error']?.toString().trim() ?? '';
    final normalized = raw.toLowerCase();
    if (statusCode == 404 || normalized == 'not found') {
      return 'Belum ada izin toilet dari pengawas';
    }
    if (raw.startsWith('Error: ')) {
      return raw.substring('Error: '.length).trim();
    }
    return raw.isEmpty ? fallback : raw;
  }

  static DateTime? parseDateTime(String? raw) {
    return WibTime.parse(raw);
  }

  static String _normalizeState(Object? raw) {
    final value = raw?.toString().trim().toUpperCase() ?? '';
    if (value == 'EXPIRED') return stateExpired;
    if (value == 'WAITING_SECURITY') return stateWaitingSecurity;
    return stateActive;
  }

  static String _normalizeProofStatus(Object? raw) {
    final value = raw?.toString().trim().toUpperCase() ?? '';
    return value == 'SCANNED' ? proofScanned : proofPending;
  }

  static int _durationMinutesFromRaw(Map<String, dynamic> raw) {
    return int.tryParse(raw['duration_minutes']?.toString() ?? '') ?? 10;
  }

  static bool _countdownStartedFromRaw(Map<String, dynamic> raw) {
    final proofStatus = _normalizeProofStatus(raw['proof_status']);
    final expiresAt = parseDateTime(raw['expires_at']?.toString());
    return proofStatus == proofScanned && expiresAt != null;
  }

  static int _remainingSecondsFromRaw(
    Map<String, dynamic> raw, {
    DateTime? now,
  }) {
    if (!_countdownStartedFromRaw(raw)) {
      return _durationMinutesFromRaw(raw) * 60;
    }

    final remainingRaw = raw['remaining_seconds'];
    final remaining = int.tryParse(remainingRaw?.toString() ?? '');
    if (remaining != null) {
      return remaining > 0 ? remaining : 0;
    }

    final expiresAt = parseDateTime(raw['expires_at']?.toString());
    if (expiresAt == null) return 0;

    final reference = now?.toUtc() ?? DateTime.now().toUtc();
    final seconds = expiresAt.difference(reference).inSeconds;
    return seconds > 0 ? seconds : 0;
  }

  static Map<String, dynamic> _normalizePermit(
    Map<String, dynamic> raw, {
    bool preserveHistoryState = false,
  }) {
    final durationMinutes = _durationMinutesFromRaw(raw);
    final countdownStarted = _countdownStartedFromRaw(raw);
    final remainingSeconds = _remainingSecondsFromRaw(raw);
    final normalizedState = _normalizeState(raw['permit_state']);
    final permitState = preserveHistoryState
        ? normalizedState
        : (!countdownStarted
              ? stateWaitingSecurity
              : (remainingSeconds == 0 ? stateExpired : normalizedState));

    return {
      ...raw,
      'duration_minutes': durationMinutes,
      'proof_status': _normalizeProofStatus(raw['proof_status']),
      'permit_state': permitState,
      'remaining_seconds': remainingSeconds,
      'countdown_started': countdownStarted,
      'is_active': preserveHistoryState
          ? permitState != stateExpired
          : permitState != stateExpired,
    };
  }

  static List<Map<String, dynamic>> _normalizePermitList(
    List<dynamic> permits, {
    bool preserveHistoryState = false,
  }) {
    final normalized = permits
        .whereType<Map>()
        .map(
          (e) => _normalizePermit(
            Map<String, dynamic>.from(e),
            preserveHistoryState: preserveHistoryState,
          ),
        )
        .toList();

    normalized.sort((a, b) {
      final aApprovedAt = parseDateTime(a['approved_at']?.toString());
      final bApprovedAt = parseDateTime(b['approved_at']?.toString());
      if (aApprovedAt == null && bApprovedAt == null) return 0;
      if (aApprovedAt == null) return 1;
      if (bApprovedAt == null) return -1;

      if (preserveHistoryState) {
        return bApprovedAt.compareTo(aApprovedAt);
      }

      final aExpired = isExpiredPermit(a);
      final bExpired = isExpiredPermit(b);
      if (aExpired != bExpired) return aExpired ? 1 : -1;

      final aProof = isProofScanned(a);
      final bProof = isProofScanned(b);
      if (aProof != bProof) return aProof ? 1 : -1;

      return bApprovedAt.compareTo(aApprovedAt);
    });

    return normalized;
  }

  static int remainingSecondsForPermit(
    Map<String, dynamic> permit, {
    DateTime? now,
  }) {
    return _remainingSecondsFromRaw(permit, now: now);
  }

  static bool isExpiredPermit(Map<String, dynamic> permit, {DateTime? now}) {
    return _normalizeState(permit['permit_state']) == stateExpired;
  }

  static bool isWaitingSecurity(Map<String, dynamic> permit) {
    return _normalizeState(permit['permit_state']) == stateWaitingSecurity;
  }

  static bool hasCountdownStarted(Map<String, dynamic> permit) {
    return _countdownStartedFromRaw(permit);
  }

  static bool isProofScanned(Map<String, dynamic> permit) {
    return _normalizeProofStatus(permit['proof_status']) == proofScanned;
  }

  static String formatRemainingLabel(int seconds) {
    if (seconds <= 0) return 'Habis';

    final hours = seconds ~/ 3600;
    final minutes = (seconds % 3600) ~/ 60;
    final secs = seconds % 60;

    if (hours > 0) {
      return '${hours}j ${minutes.toString().padLeft(2, '0')}m';
    }
    return '${minutes.toString().padLeft(2, '0')}:${secs.toString().padLeft(2, '0')}';
  }

  static String formatRemainingDetailedLabel(int seconds) {
    if (seconds <= 0) return '0 detik';

    final hours = seconds ~/ 3600;
    final minutes = (seconds % 3600) ~/ 60;
    final secs = seconds % 60;
    final parts = <String>[];

    if (hours > 0) parts.add('$hours jam');
    if (minutes > 0 || hours > 0) parts.add('$minutes menit');
    parts.add('$secs detik');

    return parts.join(' ');
  }

  static Future<Map<String, dynamic>> approvePermit(
    String idKaryawan, {
    required int durationMinutes,
  }) async {
    final response = await BaseApiClient.post(
      '/toilet-permit/approve',
      body: {
        'id_karyawan': idKaryawan,
        'username': AuthService.username,
        'duration_minutes': durationMinutes,
      },
    );
    final data = BaseApiClient.tryJson(response.body);
    if (response.statusCode >= 400) {
      throw Exception(
        _resolveErrorMessage(
          data,
          'Gagal menyetujui izin toilet',
          statusCode: response.statusCode,
        ),
      );
    }
    return _normalizePermit(data);
  }

  static Future<Map<String, dynamic>> proofScan(String idKaryawan) async {
    final response = await BaseApiClient.post(
      '/toilet-permit/proof-scan',
      body: {'id_karyawan': idKaryawan, 'username': AuthService.username},
    );
    final data = BaseApiClient.tryJson(response.body);
    if (response.statusCode >= 400) {
      throw Exception(
        _resolveErrorMessage(
          data,
          'Gagal memvalidasi izin toilet',
          statusCode: response.statusCode,
        ),
      );
    }
    return _normalizePermit(data);
  }

  static Future<Map<String, dynamic>> fetchPermitStatus(
    String idKaryawan,
  ) async {
    final response = await BaseApiClient.get(
      '/toilet-permit/status/${Uri.encodeComponent(idKaryawan)}',
    );
    final data = BaseApiClient.tryJson(response.body);
    if (response.statusCode >= 400) {
      throw Exception(
        _resolveErrorMessage(
          data,
          'Gagal mengambil status izin toilet',
          statusCode: response.statusCode,
        ),
      );
    }
    return _normalizePermit(data);
  }

  static Future<List<Map<String, dynamic>>> fetchActivePermits() async {
    final response = await BaseApiClient.get('/toilet-permits');
    if (response.statusCode >= 400) {
      final body = BaseApiClient.tryJson(response.body);
      throw Exception(
        _resolveErrorMessage(
          body,
          'Gagal mengambil izin toilet',
          statusCode: response.statusCode,
        ),
      );
    }
    final body = BaseApiClient.tryJson(response.body);
    final List<dynamic> permits = body['permits'] ?? [];
    return _normalizePermitList(permits);
  }

  static Future<List<Map<String, dynamic>>> fetchExpiredAlerts() async {
    final response = await BaseApiClient.get('/toilet-permits-alerts');
    if (response.statusCode >= 400) {
      final body = BaseApiClient.tryJson(response.body);
      throw Exception(
        _resolveErrorMessage(
          body,
          'Gagal mengambil alert izin toilet',
          statusCode: response.statusCode,
        ),
      );
    }
    final body = BaseApiClient.tryJson(response.body);
    final List<dynamic> alerts = body['alerts'] ?? [];
    return _normalizePermitList(alerts);
  }

  static Future<void> markReturned(String idKaryawan) async {
    final response = await BaseApiClient.post(
      '/toilet-permit/return',
      body: {'id_karyawan': idKaryawan, 'username': AuthService.username},
    );
    if (response.statusCode >= 400) {
      final data = BaseApiClient.tryJson(response.body);
      throw Exception(
        _resolveErrorMessage(
          data,
          'Gagal menandai mitra sudah kembali',
          statusCode: response.statusCode,
        ),
      );
    }
  }

  static Future<List<Map<String, dynamic>>> fetchPermitHistory(
    String date,
  ) async {
    final response = await BaseApiClient.get('/toilet-permits-history/$date');
    if (response.statusCode >= 400) {
      final body = BaseApiClient.tryJson(response.body);
      throw Exception(
        _resolveErrorMessage(
          body,
          'Gagal mengambil riwayat izin toilet',
          statusCode: response.statusCode,
        ),
      );
    }
    final body = BaseApiClient.tryJson(response.body);
    final List<dynamic> permits = body['permits'] ?? [];
    return _normalizePermitList(permits, preserveHistoryState: true);
  }
}
