import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';
import 'toilet_permit_service.dart';

class ToiletStatusTab extends StatefulWidget {
  const ToiletStatusTab({super.key});

  @override
  State<ToiletStatusTab> createState() => _ToiletStatusTabState();
}

class _ToiletStatusTabState extends State<ToiletStatusTab> {
  List<Map<String, dynamic>> _permits = [];
  bool _isLoading = true;
  String? _error;
  Timer? _ticker;
  DateTime _now = DateTime.now();

  @override
  void initState() {
    super.initState();
    _loadPermits();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      setState(() => _now = DateTime.now());
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  Future<void> _loadPermits() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final permits = await ToiletPermitService.fetchActivePermits();
      if (!mounted) return;
      setState(() {
        _permits = permits;
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _isLoading = false;
      });
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

  String _formatTimeLabel(String? raw) {
    final parsed = ToiletPermitService.parseDateTime(raw);
    if (parsed == null) return '-';

    final local = parsed.toLocal();
    final h = local.hour.toString().padLeft(2, '0');
    final m = local.minute.toString().padLeft(2, '0');
    return '$h:$m';
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
      return 'Waktu Habis';
    }
    if (ToiletPermitService.isProofScanned(permit)) {
      return 'Tervalidasi Security';
    }
    return 'Menunggu Proof Scan';
  }

  int _remainingSeconds(Map<String, dynamic> permit) {
    return ToiletPermitService.remainingSecondsForPermit(permit, now: _now);
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
              );
              final expiresAt = _formatTimeLabel(
                permit['expires_at']?.toString(),
              );
              final proofAt = _formatTimeLabel(
                permit['proof_scanned_at']?.toString(),
              );

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
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Icon(Icons.timer, size: 16, color: color),
                        const SizedBox(width: 6),
                        Text(
                          ToiletPermitService.formatRemainingLabel(remaining),
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                            color: color,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Text(
                          '${permit['duration_minutes']} menit',
                          style: const TextStyle(
                            fontSize: 11,
                            color: AppColors.textSecondary,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    _infoRow(
                      icon: Icons.badge,
                      label: 'Pengawas',
                      value:
                          '${permit['approved_by'] ?? '-'} (${approvedAt == '-' ? expiresAt : approvedAt})',
                      color: AppColors.pengawas,
                    ),
                    const SizedBox(height: 4),
                    _infoRow(
                      icon: Icons.schedule,
                      label: 'Batas',
                      value: expiresAt == '-' ? 'Tidak diketahui' : expiresAt,
                      color: AppColors.warning,
                    ),
                    const SizedBox(height: 4),
                    _infoRow(
                      icon: Icons.security,
                      label: 'Security',
                      value: ToiletPermitService.isProofScanned(permit)
                          ? '${permit['proof_scanned_by'] ?? '-'} ($proofAt)'
                          : 'Belum proof scan',
                      color: ToiletPermitService.isProofScanned(permit)
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

Widget _infoRow({
  required IconData icon,
  required String label,
  required String value,
  required Color color,
}) {
  return Row(
    children: [
      Icon(icon, size: 14, color: color),
      const SizedBox(width: 6),
      Text(
        '$label: ',
        style: const TextStyle(
          fontSize: 11,
          color: AppColors.textSecondary,
          fontWeight: FontWeight.w500,
        ),
      ),
      Expanded(
        child: Text(
          value,
          style: TextStyle(
            fontSize: 11,
            color: color,
            fontWeight: FontWeight.w500,
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
