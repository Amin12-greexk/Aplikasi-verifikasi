import '../toilet/toilet_permit_service.dart';
import '../verification/verification_service.dart';

/// History service — aggregates data from verification + attendance modules.
class HistoryService {
  /// Fetch verification logs by date
  static Future<List<Map<String, dynamic>>> fetchVerificationHistory(
    String date,
  ) async {
    try {
      return await VerificationService.fetchLogsByDate(date);
    } catch (_) {
      return [];
    }
  }

  /// Fetch attendance history by date — placeholder
  static Future<List<Map<String, dynamic>>> fetchAttendanceHistory(
    String date,
  ) async {
    // TODO: Implement when attendance endpoint is available
    return [];
  }

  /// Fetch toilet permit history by date
  static Future<List<Map<String, dynamic>>> fetchToiletHistory(
    String date,
  ) async {
    try {
      return await ToiletPermitService.fetchPermitHistory(date);
    } catch (_) {
      return [];
    }
  }
}
