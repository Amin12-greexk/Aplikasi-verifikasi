import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';
import '../../core/utils/wib_time.dart';
import 'toilet_permit_service.dart';

class ToiletStatusPage extends StatefulWidget {
  const ToiletStatusPage({super.key});

  @override
  State<ToiletStatusPage> createState() => _ToiletStatusPageState();
}

class _ToiletStatusPageState extends State<ToiletStatusPage> {
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
      final nik = _extractValue(fullBarcode, 'NIK');
      final bagian = _extractValue(fullBarcode, 'Bagian');

      if (nama.isNotEmpty && pin.isNotEmpty) {
        var result = '$nama (PIN: $pin)';
        if (bagian.isNotEmpty) result += ' - $bagian';
        return result;
      }
      if (nama.isNotEmpty && nik.isNotEmpty) {
        var result = '$nama (NIK: $nik)';
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
    return ToiletPermitService.isWaitingSecurity(permit)
        ? AppColors.error
        : AppColors.success;
  }

  String _statusLabel(Map<String, dynamic> permit) {
    if (ToiletPermitService.isWaitingSecurity(permit)) {
      return 'Menunggu Scan Security';
    }
    if (ToiletPermitService.isExpiredPermit(permit, now: _now)) {
      return 'Sudah Scan Security | Waktu Habis';
    }
    return 'Sudah Scan Security';
  }

  int _remainingSeconds(Map<String, dynamic> permit) {
    return ToiletPermitService.remainingSecondsForPermit(permit, now: _now);
  }

  String _statusDescription(Map<String, dynamic> permit) {
    final remaining = _remainingSeconds(permit);
    if (ToiletPermitService.isWaitingSecurity(permit)) {
      return 'Pengawas sudah memberi izin. Hitungan waktu belum berjalan sampai QR discan oleh security.';
    }
    if (ToiletPermitService.isExpiredPermit(permit, now: _now)) {
      return 'Waktu toilet sudah habis. Security sudah memulai timer, tetapi batas waktunya telah terlewati.';
    }
    final proofBy = permit['proof_scanned_by']?.toString().trim();
    return proofBy == null || proofBy.isEmpty
        ? 'Timer toilet sedang berjalan. Sisa waktu ${ToiletPermitService.formatRemainingDetailedLabel(remaining)}.'
        : 'Timer toilet sedang berjalan sejak discan oleh $proofBy. Sisa waktu ${ToiletPermitService.formatRemainingDetailedLabel(remaining)}.';
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
    final waitingSecurityCount = _permits.length - scannedCount;
    final expiredCount = _permits.length - activeCount;

    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Status Toilet',
          style: TextStyle(fontWeight: FontWeight.w600, fontSize: 16),
        ),
        backgroundColor: AppColors.surface,
        foregroundColor: AppColors.textPrimary,
        elevation: 0,
        centerTitle: true,
      ),
      backgroundColor: AppColors.background,
      body: RefreshIndicator(
        onRefresh: _loadPermits,
        color: AppColors.primary,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            _PermitSummaryCard(
              total: _permits.length,
              active: activeCount,
              scanned: scannedCount,
              waitingSecurity: waitingSecurityCount,
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
                final waitingSecurity = ToiletPermitService.isWaitingSecurity(
                  permit,
                );
                final expired = ToiletPermitService.isExpiredPermit(
                  permit,
                  now: _now,
                );
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
                final duration = permit['duration_minutes']?.toString() ?? '-';

                return Container(
                  margin: const EdgeInsets.only(bottom: 10),
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: color.withAlpha(12),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: color.withAlpha(70), width: 1.3),
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
                      Text(
                        waitingSecurity
                            ? 'Belum mulai dihitung'
                            : expired
                            ? 'Waktu toilet habis'
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
                          height: 1.35,
                        ),
                      ),
                      const SizedBox(height: 12),
                      Container(
                        width: double.infinity,
                        height: 1,
                        color: color.withAlpha(45),
                      ),
                      const SizedBox(height: 12),
                      _infoLine(
                        label: 'Pengawas',
                        value: approvedBy == null || approvedBy.isEmpty
                            ? 'Nama pengawas belum tercatat'
                            : approvedBy,
                      ),
                      const SizedBox(height: 6),
                      _infoLine(
                        label: 'Jam disetujui',
                        value: approvedAt == '-'
                            ? 'Belum ada jam persetujuan'
                            : approvedAt,
                      ),
                      const SizedBox(height: 6),
                      _infoLine(
                        label: 'Batas kembali',
                        value: waitingSecurity
                            ? 'Belum ada. Timer mulai saat security scan.'
                            : (expiresAt == '-'
                                  ? 'Batas waktu belum tersedia'
                                  : expiresAt),
                      ),
                      const SizedBox(height: 6),
                      _infoLine(label: 'Durasi izin', value: '$duration menit'),
                      const SizedBox(height: 6),
                      _infoLine(
                        label: 'Timer mulai',
                        value: proofScanned
                            ? (proofAt == '-'
                                  ? 'Sudah dimulai oleh security'
                                  : proofAt)
                            : 'Akan mulai saat security scan',
                      ),
                      const SizedBox(height: 6),
                      _infoLine(
                        label: 'Security',
                        value: proofScanned
                            ? '${proofBy == null || proofBy.isEmpty ? 'Security' : proofBy} pada $proofAt'
                            : 'Belum ada scan security',
                      ),
                    ],
                  ),
                );
              }),
          ],
        ),
      ),
    );
  }
}

Widget _infoLine({required String label, required String value}) {
  return Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      SizedBox(
        width: 96,
        child: Text(
          label,
          style: const TextStyle(
            fontSize: 11,
            color: AppColors.textSecondary,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
      const Text(
        ': ',
        style: TextStyle(
          fontSize: 11,
          color: AppColors.textSecondary,
          fontWeight: FontWeight.w600,
        ),
      ),
      Expanded(
        child: Text(
          value,
          style: const TextStyle(
            fontSize: 12,
            color: AppColors.textPrimary,
            fontWeight: FontWeight.w600,
            height: 1.3,
          ),
        ),
      ),
    ],
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

class _PermitSummaryCard extends StatelessWidget {
  final int total;
  final int active;
  final int scanned;
  final int waitingSecurity;
  final int expired;

  const _PermitSummaryCard({
    required this.total,
    required this.active,
    required this.scanned,
    required this.waitingSecurity,
    required this.expired,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.cardBorder),
      ),
      child: Wrap(
        spacing: 14,
        runSpacing: 8,
        children: [
          _summaryItem('Total', '$total', AppColors.info),
          _summaryItem('Aktif', '$active', AppColors.primary),
          _summaryItem('Sudah Scan', '$scanned', AppColors.success),
          _summaryItem('Belum Scan', '$waitingSecurity', AppColors.error),
          _summaryItem('Habis', '$expired', AppColors.warning),
        ],
      ),
    );
  }

  Widget _summaryItem(String title, String value, Color color) {
    return RichText(
      text: TextSpan(
        style: const TextStyle(fontSize: 12),
        children: [
          TextSpan(
            text: '$title: ',
            style: const TextStyle(
              color: AppColors.textSecondary,
              fontWeight: FontWeight.w600,
            ),
          ),
          TextSpan(
            text: value,
            style: TextStyle(color: color, fontWeight: FontWeight.w800),
          ),
        ],
      ),
    );
  }
}
