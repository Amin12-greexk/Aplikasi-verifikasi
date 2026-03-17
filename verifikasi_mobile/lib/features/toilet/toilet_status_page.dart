import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';
import '../../core/utils/wib_time.dart';
import 'toilet_permit_service.dart';

class ToiletStatusTab extends StatefulWidget {
  const ToiletStatusTab({super.key});

  @override
  State<ToiletStatusTab> createState() => _ToiletStatusTabState();
}

class _ToiletStatusTabState extends State<ToiletStatusTab> {
  List<Map<String, dynamic>> _permits = [];
  bool _isLoading = true;
  bool _isRefreshing = false;
  String? _error;
  Timer? _ticker;
  Timer? _refreshTimer;
  DateTime _now = DateTime.now().toUtc();

  @override
  void initState() {
    super.initState();
    _loadPermits();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      setState(() => _now = DateTime.now().toUtc());
    });
    _refreshTimer = Timer.periodic(const Duration(seconds: 10), (_) {
      if (!mounted) return;
      _loadPermits(showLoading: false);
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    _refreshTimer?.cancel();
    super.dispose();
  }

  Future<void> _loadPermits({bool showLoading = true}) async {
    if (_isRefreshing) return;
    _isRefreshing = true;

    if (showLoading) {
      setState(() {
        _isLoading = true;
        _error = null;
      });
    }

    try {
      final permits = await ToiletPermitService.fetchActivePermits();
      if (!mounted) return;
      setState(() {
        _permits = permits;
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      if (showLoading || _permits.isEmpty) {
        setState(() {
          _error = e.toString();
          _isLoading = false;
        });
      }
    } finally {
      _isRefreshing = false;
    }
  }

  String _extractEmployeeInfo(String fullBarcode) {
    try {
      final nama = _extractValue(fullBarcode, 'Nama');
      final pin = _extractValue(fullBarcode, 'PIN');
      final bagian = _extractValue(fullBarcode, 'Bagian');

      if (nama.isNotEmpty && pin.isNotEmpty) {
        var result = '$nama (PIN: $pin)';
        if (bagian.isNotEmpty) result += ' - $bagian';
        return result;
      }
    } catch (_) {}

    return fullBarcode;
  }

  String _extractValue(String barcode, String key) {
    final parts = barcode.split('|').map((p) => p.trim()).toList();
    for (final part in parts) {
      if (part.startsWith('$key:')) {
        return part.substring(key.length + 1).trim();
      }
    }
    return '';
  }

  String _formatTimeLabel(String? raw, {bool withSeconds = false}) {
    return WibTime.formatTime(raw, withSeconds: withSeconds);
  }

  Color _statusColor(Map<String, dynamic> permit) {
    if (ToiletPermitService.isExpiredPermit(permit, now: _now)) {
      return AppColors.error;
    }
    if (ToiletPermitService.isProofScanned(permit)) {
      return AppColors.success;
    }
    return AppColors.info;
  }

  String _statusLabel(Map<String, dynamic> permit) {
    if (ToiletPermitService.isExpiredPermit(permit, now: _now)) {
      return 'Sudah Habis';
    }
    if (ToiletPermitService.isProofScanned(permit)) {
      return 'Sudah Diverifikasi Security';
    }
    return 'Masih Aktif';
  }

  int _remainingSeconds(Map<String, dynamic> permit) {
    return ToiletPermitService.remainingSecondsForPermit(permit, now: _now);
  }

  String _statusDescription(Map<String, dynamic> permit) {
    final remaining = _remainingSeconds(permit);
    if (ToiletPermitService.isExpiredPermit(permit, now: _now)) {
      return 'Izin toilet sudah melewati batas waktu kembali.';
    }
    if (ToiletPermitService.isProofScanned(permit)) {
      final proofBy = permit['proof_scanned_by']?.toString().trim();
      return proofBy == null || proofBy.isEmpty
          ? 'Izin ini sudah dicatat oleh security.'
          : 'Izin ini sudah dicatat oleh security: $proofBy.';
    }
    return 'Masih menunggu proof scan security. Sisa waktu ${ToiletPermitService.formatRemainingDetailedLabel(remaining)}.';
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Center(
        child: CircularProgressIndicator(color: AppColors.primary),
      );
    }

    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.error_outline, size: 48, color: AppColors.error),
              const SizedBox(height: 12),
              const Text(
                'Gagal memuat izin toilet',
                style: TextStyle(
                  fontWeight: FontWeight.w600,
                  color: AppColors.textPrimary,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                _error!,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 12,
                  color: AppColors.textSecondary,
                ),
              ),
              const SizedBox(height: 16),
              ElevatedButton.icon(
                onPressed: _loadPermits,
                icon: const Icon(Icons.refresh),
                label: const Text('Coba Lagi'),
              ),
            ],
          ),
        ),
      );
    }

    final activeCount = _permits
        .where(
          (permit) => !ToiletPermitService.isExpiredPermit(permit, now: _now),
        )
        .length;
    final scannedCount = _permits
        .where((permit) => ToiletPermitService.isProofScanned(permit))
        .length;
    final expiredCount = _permits.length - activeCount;

    return RefreshIndicator(
      onRefresh: _loadPermits,
      color: AppColors.primary,
      child: ListView(
        children: [
          _PermitStatRow(
            total: _permits.length,
            active: activeCount,
            scanned: scannedCount,
            expired: expiredCount,
          ),
          const SizedBox(height: 16),
          if (_permits.isEmpty)
            Container(
              padding: const EdgeInsets.all(32),
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: AppColors.cardBorder),
              ),
              child: Column(
                children: [
                  Icon(Icons.timer_off, size: 48, color: AppColors.textHint),
                  const SizedBox(height: 8),
                  const Text(
                    'Belum ada izin toilet aktif',
                    style: TextStyle(color: AppColors.textSecondary),
                  ),
                ],
              ),
            )
          else
            ..._permits.map((permit) {
              final info = _extractEmployeeInfo(
                permit['id_karyawan']?.toString() ?? '',
              );
              final color = _statusColor(permit);
              final label = _statusLabel(permit);
              final remaining = _remainingSeconds(permit);
              final approvedAt = _formatTimeLabel(
                permit['approved_at']?.toString(),
                withSeconds: true,
              );
              final expiresAt = _formatTimeLabel(
                permit['expires_at']?.toString(),
                withSeconds: true,
              );
              final proofAt = _formatTimeLabel(
                permit['proof_scanned_at']?.toString(),
                withSeconds: true,
              );
              final proofScanned = ToiletPermitService.isProofScanned(permit);
              final approvedBy = permit['approved_by']?.toString().trim();
              final proofBy = permit['proof_scanned_by']?.toString().trim();

              return Container(
                margin: const EdgeInsets.only(bottom: 10),
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: AppColors.cardBorder),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            info,
                            style: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: AppColors.textPrimary,
                            ),
                          ),
                        ),
                        _chip(label, color),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: color.withAlpha(16),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: color.withAlpha(40)),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            proofScanned
                                ? 'Status Saat Ini'
                                : 'Sisa Waktu Real-Time',
                            style: const TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: AppColors.textSecondary,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            proofScanned
                                ? 'Sudah diverifikasi security'
                                : ToiletPermitService.formatRemainingDetailedLabel(
                                    remaining,
                                  ),
                            style: TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.w800,
                              color: color,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            _statusDescription(permit),
                            style: const TextStyle(
                              fontSize: 12,
                              color: AppColors.textSecondary,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 10),
                    _detailItem(
                      icon: Icons.person_pin_circle,
                      label: 'Disetujui Pengawas',
                      value: approvedBy == null || approvedBy.isEmpty
                          ? 'Nama pengawas belum tercatat'
                          : approvedBy,
                      color: AppColors.pengawas,
                    ),
                    const SizedBox(height: 8),
                    _detailItem(
                      icon: Icons.schedule_send,
                      label: 'Jam Disetujui',
                      value: approvedAt == '-'
                          ? 'Belum ada jam persetujuan'
                          : approvedAt,
                      color: AppColors.info,
                    ),
                    const SizedBox(height: 8),
                    _detailItem(
                      icon: Icons.schedule,
                      label: 'Batas Kembali',
                      value: expiresAt == '-'
                          ? 'Batas waktu belum tersedia'
                          : expiresAt,
                      color: AppColors.warning,
                    ),
                    const SizedBox(height: 8),
                    _detailItem(
                      icon: Icons.security,
                      label: 'Status Security',
                      value: proofScanned
                          ? '${proofBy == null || proofBy.isEmpty ? 'Security' : proofBy} pada $proofAt'
                          : 'Belum ada proof scan dari security',
                      color: proofScanned
                          ? AppColors.success
                          : AppColors.textHint,
                    ),
                  ],
                ),
              );
            }),
        ],
      ),
    );
  }
}

Widget _detailItem({
  required IconData icon,
  required String label,
  required String value,
  required Color color,
}) {
  return Container(
    width: double.infinity,
    padding: const EdgeInsets.all(10),
    decoration: BoxDecoration(
      color: color.withAlpha(12),
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: color.withAlpha(30)),
    ),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 16, color: color),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: const TextStyle(
                  fontSize: 11,
                  color: AppColors.textSecondary,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                value,
                style: TextStyle(
                  fontSize: 12,
                  color: color,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ],
    ),
  );
}

Widget _chip(String text, Color color) {
  return Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
    decoration: BoxDecoration(
      color: color.withAlpha(20),
      borderRadius: BorderRadius.circular(6),
    ),
    child: Text(
      text,
      style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: color),
    ),
  );
}

class _PermitStatRow extends StatelessWidget {
  final int total;
  final int active;
  final int scanned;
  final int expired;

  const _PermitStatRow({
    required this.total,
    required this.active,
    required this.scanned,
    required this.expired,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(child: _statCard('Total', '$total', AppColors.info)),
        const SizedBox(width: 8),
        Expanded(child: _statCard('Aktif', '$active', AppColors.primary)),
        const SizedBox(width: 8),
        Expanded(child: _statCard('Proof', '$scanned', AppColors.success)),
        const SizedBox(width: 8),
        Expanded(child: _statCard('Habis', '$expired', AppColors.error)),
      ],
    );
  }

  Widget _statCard(String title, String value, Color bg) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
      decoration: BoxDecoration(
        color: bg.withAlpha(20),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: bg.withAlpha(40)),
      ),
      child: Column(
        children: [
          Text(
            value,
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: bg,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            title,
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w500,
              color: bg,
            ),
          ),
        ],
      ),
    );
  }
}
