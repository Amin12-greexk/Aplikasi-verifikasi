import 'package:flutter/material.dart';

import '../../core/config/dev_visibility.dart';
import '../../core/config/server_profile_manager.dart';
import '../../core/services/auth_service.dart';
import '../../core/services/offline_queue.dart';
import '../../core/theme/app_colors.dart';
import '../attendance/attendance_service.dart';
import '../verification/verification_service.dart';

/// Dashboard beranda with summary cards.
class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  static const Duration _dashboardCacheTtl = Duration(seconds: 30);
  static const int _maxPinsToCheck = 5;
  static _DashboardCache? _dashboardCache;

  int _totalLogs = 0;
  int _approved = 0;
  int _pending = 0;
  int _offlineCount = 0;
  bool _attendanceConnected = false;
  int _attendancePinsChecked = 0;
  int _attendanceTodayCount = 0;
  DateTime? _attendanceCheckedAt;
  bool _isLoading = true;
  bool _isAttendanceLoading = true;
  int _activeLoadId = 0;

  @override
  void initState() {
    super.initState();
    final restored = _restoreFromCache();
    _loadDashboard(showLoader: !restored);
  }

  bool _restoreFromCache() {
    final cache = _dashboardCache;
    if (cache == null) return false;
    if (DateTime.now().difference(cache.fetchedAt) > _dashboardCacheTtl) {
      return false;
    }

    _totalLogs = cache.totalLogs;
    _approved = cache.approved;
    _pending = cache.pending;
    _offlineCount = cache.offlineCount;
    _attendanceConnected = cache.attendanceConnected;
    _attendancePinsChecked = cache.attendancePinsChecked;
    _attendanceTodayCount = cache.attendanceTodayCount;
    _attendanceCheckedAt = cache.attendanceCheckedAt;
    _isLoading = false;
    _isAttendanceLoading = false;
    return true;
  }

  void _saveCache() {
    _dashboardCache = _DashboardCache(
      totalLogs: _totalLogs,
      approved: _approved,
      pending: _pending,
      offlineCount: _offlineCount,
      attendanceConnected: _attendanceConnected,
      attendancePinsChecked: _attendancePinsChecked,
      attendanceTodayCount: _attendanceTodayCount,
      attendanceCheckedAt: _attendanceCheckedAt,
      fetchedAt: DateTime.now(),
    );
  }

  Future<List<Map<String, dynamic>>> _safeFetchLogs() async {
    try {
      return await VerificationService.fetchLogs().timeout(
        const Duration(seconds: 8),
      );
    } catch (_) {
      return <Map<String, dynamic>>[];
    }
  }

  Future<List<Map<String, dynamic>>> _safeGetPendingQueue() async {
    try {
      return await OfflineQueueManager.getPending().timeout(
        const Duration(seconds: 2),
      );
    } catch (_) {
      return <Map<String, dynamic>>[];
    }
  }

  Future<bool> _safeCheckAttendanceApi() async {
    try {
      return await AttendanceService.isAvailable().timeout(
        const Duration(seconds: 3),
      );
    } catch (_) {
      return false;
    }
  }

  Future<void> _loadDashboard({bool showLoader = true}) async {
    final loadId = ++_activeLoadId;

    if (showLoader && mounted) {
      setState(() {
        _isLoading = true;
        _isAttendanceLoading = true;
      });
    }

    final results = await Future.wait<dynamic>([
      _safeFetchLogs(),
      _safeGetPendingQueue(),
      _safeCheckAttendanceApi(),
    ]);

    if (!mounted || loadId != _activeLoadId) return;

    final logs = List<Map<String, dynamic>>.from(results[0] as List);
    final offline = List<Map<String, dynamic>>.from(results[1] as List);
    final attendanceConnected = results[2] as bool;

    final pins = logs
        .map((l) => _extractPinFromId(l['id_karyawan']?.toString() ?? ''))
        .where((pin) => pin.isNotEmpty)
        .toSet()
        .toList();
    final pinsToCheck = attendanceConnected
        ? pins.take(_maxPinsToCheck).toList()
        : <String>[];
    final shouldLoadAttendance = attendanceConnected && pinsToCheck.isNotEmpty;

    if (mounted) {
      setState(() {
        _totalLogs = logs.length;
        _approved = logs
            .where(
              (l) =>
                  l['status_pengawas'] == 'approved' &&
                  l['status_security'] == 'approved',
            )
            .length;
        _pending = _totalLogs - _approved;
        _offlineCount = offline.length;
        _attendanceConnected = attendanceConnected;
        _attendancePinsChecked = pinsToCheck.length;
        if (!shouldLoadAttendance) {
          _attendanceTodayCount = 0;
          _attendanceCheckedAt = DateTime.now();
        }
        _isLoading = false;
        _isAttendanceLoading = shouldLoadAttendance;
      });
      _saveCache();
    }

    if (shouldLoadAttendance) {
      _loadAttendanceSummary(loadId: loadId, pinsToCheck: pinsToCheck);
    }
  }

  Future<void> _loadAttendanceSummary({
    required int loadId,
    required List<String> pinsToCheck,
  }) async {
    final now = DateTime.now();
    final hasTodayAttendance = await Future.wait(
      pinsToCheck.map((pin) async {
        try {
          final summary = await AttendanceService.getTodayStatusByPin(
            pin,
          ).timeout(const Duration(seconds: 4));
          final latestRaw = summary?['latest_scan_date']?.toString();
          final latest = _parseDateTime(latestRaw);
          return latest != null && _isSameDay(latest, now);
        } catch (_) {
          return false;
        }
      }),
    );

    if (!mounted || loadId != _activeLoadId) return;

    setState(() {
      _attendanceTodayCount = hasTodayAttendance.where((v) => v).length;
      _attendanceCheckedAt = DateTime.now();
      _isAttendanceLoading = false;
    });
    _saveCache();
  }

  String _extractPinFromId(String rawId) {
    final raw = rawId.trim();
    if (raw.isEmpty) return '';
    if (RegExp(r'^[0-9]{4,}$').hasMatch(raw)) return raw;

    final parts = raw.split('|').map((p) => p.trim());
    for (final part in parts) {
      final separator = part.indexOf(':');
      if (separator <= 0) continue;
      final key = part.substring(0, separator).trim().toLowerCase();
      if (key != 'pin') continue;
      final value = part.substring(separator + 1).trim();
      if (value.isNotEmpty) return value;
    }
    return '';
  }

  DateTime? _parseDateTime(String? raw) {
    if (raw == null || raw.trim().isEmpty) return null;
    try {
      return DateTime.parse(raw);
    } catch (_) {
      try {
        return DateTime.parse(raw.replaceFirst(' ', 'T'));
      } catch (_) {
        return null;
      }
    }
  }

  bool _isSameDay(DateTime a, DateTime b) {
    return a.year == b.year && a.month == b.month && a.day == b.day;
  }

  String _formatClock(DateTime value) {
    final h = value.hour.toString().padLeft(2, '0');
    final m = value.minute.toString().padLeft(2, '0');
    return '$h:$m';
  }

  @override
  Widget build(BuildContext context) {
    final isPengawas = AuthService.isPengawas();
    final userName = AuthService.username ?? 'User';
    final attendanceStatusLabel = _isAttendanceLoading
        ? 'Memuat'
        : (_attendanceConnected ? 'Online' : 'Offline');
    final attendanceStatusColor = _isAttendanceLoading
        ? AppColors.info
        : (_attendanceConnected ? AppColors.success : AppColors.warning);
    final attendanceSubtitle = _isAttendanceLoading
        ? 'Mengecek absensi hari ini...'
        : !_attendanceConnected
        ? 'Server absensi belum dapat diakses.'
        : _attendancePinsChecked == 0
        ? 'Belum ada PIN hasil scan untuk dicek ke API absensi.'
        : '$_attendanceTodayCount dari $_attendancePinsChecked PIN hasil scan terdeteksi absen hari ini.';

    return RefreshIndicator(
      onRefresh: _loadDashboard,
      color: AppColors.primary,
      child: ListView(
        padding: const EdgeInsets.all(0),
        children: [
          // User greeting
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AppColors.cardBorder),
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: isPengawas
                        ? AppColors.pengawasSurface
                        : AppColors.securitySurface,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(
                    isPengawas ? Icons.badge : Icons.security,
                    color: isPengawas ? AppColors.pengawas : AppColors.security,
                    size: 28,
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Selamat datang,',
                        style: TextStyle(
                          fontSize: 12,
                          color: AppColors.textSecondary,
                        ),
                      ),
                      Text(
                        userName,
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                          color: AppColors.textPrimary,
                        ),
                      ),
                      Text(
                        isPengawas ? 'Pengawas' : 'Security',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                          color: isPengawas
                              ? AppColors.pengawas
                              : AppColors.security,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 16),

          if (DevVisibility.canControlServerSection)
            ValueListenableBuilder<bool>(
              valueListenable: DevVisibility.showServerSection,
              builder: (context, showServerSection, _) {
                if (!showServerSection) {
                  return const SizedBox.shrink();
                }

                final profile = ServerProfileManager.activeProfile;
                return Column(
                  children: [
                    // Active server (dev only)
                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: AppColors.surface,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: AppColors.cardBorder),
                      ),
                      child: Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: AppColors.primarySurface,
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: const Icon(
                              Icons.dns,
                              size: 20,
                              color: AppColors.primary,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  'Server Aktif',
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: AppColors.textSecondary,
                                  ),
                                ),
                                Text(
                                  profile.name,
                                  style: const TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w600,
                                    color: AppColors.textPrimary,
                                  ),
                                ),
                                Text(
                                  profile.baseUrl,
                                  style: const TextStyle(
                                    fontSize: 11,
                                    color: AppColors.textSecondary,
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ],
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: AppColors.success.withAlpha(20),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: const Text(
                              'Aktif',
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.w600,
                                color: AppColors.success,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                  ],
                );
              },
            ),

          // Verification summary
          const Text(
            'Ringkasan Hari Ini',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: 10),
          _isLoading
              ? const Center(
                  child: Padding(
                    padding: EdgeInsets.all(24),
                    child: CircularProgressIndicator(
                      color: AppColors.primary,
                      strokeWidth: 2.5,
                    ),
                  ),
                )
              : Row(
                  children: [
                    Expanded(
                      child: _summaryCard(
                        'Total Scan',
                        '$_totalLogs',
                        Icons.qr_code_scanner,
                        AppColors.info,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _summaryCard(
                        'Selesai',
                        '$_approved',
                        Icons.check_circle,
                        AppColors.success,
                      ),
                    ),
                  ],
                ),
          const SizedBox(height: 10),
          if (!_isLoading)
            Row(
              children: [
                Expanded(
                  child: _summaryCard(
                    'Proses',
                    '$_pending',
                    Icons.pending,
                    AppColors.warning,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _summaryCard(
                    'Offline Queue',
                    '$_offlineCount',
                    Icons.cloud_off,
                    AppColors.textSecondary,
                  ),
                ),
              ],
            ),

          const SizedBox(height: 16),

          // Attendance summary
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: AppColors.cardBorder),
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: attendanceStatusColor.withAlpha(20),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(
                    Icons.fingerprint,
                    size: 20,
                    color: attendanceStatusColor,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Absensi Hari Ini',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: AppColors.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        attendanceSubtitle,
                        style: TextStyle(
                          fontSize: 12,
                          color: _attendanceConnected
                              ? AppColors.textSecondary
                              : AppColors.warning,
                        ),
                      ),
                      if (_attendanceCheckedAt != null)
                        Text(
                          'Update: ${_formatClock(_attendanceCheckedAt!)}',
                          style: const TextStyle(
                            fontSize: 11,
                            color: AppColors.textHint,
                          ),
                        ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: attendanceStatusColor.withAlpha(20),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    attendanceStatusLabel,
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                      color: attendanceStatusColor,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _summaryCard(String title, String value, IconData icon, Color color) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: color.withAlpha(10),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withAlpha(30)),
      ),
      child: Row(
        children: [
          Icon(icon, size: 28, color: color),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  value,
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                    color: color,
                  ),
                ),
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w500,
                    color: color.withAlpha(180),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _DashboardCache {
  final int totalLogs;
  final int approved;
  final int pending;
  final int offlineCount;
  final bool attendanceConnected;
  final int attendancePinsChecked;
  final int attendanceTodayCount;
  final DateTime? attendanceCheckedAt;
  final DateTime fetchedAt;

  const _DashboardCache({
    required this.totalLogs,
    required this.approved,
    required this.pending,
    required this.offlineCount,
    required this.attendanceConnected,
    required this.attendancePinsChecked,
    required this.attendanceTodayCount,
    required this.attendanceCheckedAt,
    required this.fetchedAt,
  });
}
