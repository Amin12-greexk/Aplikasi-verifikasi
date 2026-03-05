import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';
import 'verification_service.dart';

class StatusTab extends StatefulWidget {
  const StatusTab({super.key});

  @override
  State<StatusTab> createState() => _StatusTabState();
}

class _StatusTabState extends State<StatusTab> {
  List<Map<String, dynamic>> _logs = [];
  bool _isLoading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _initializeData();
  }

  /// Parse barcode string to extract Nama, PIN, and Bagian
  String _extractEmployeeInfo(String fullBarcode) {
    try {
      final nama = _extractValue(fullBarcode, 'Nama');
      final pin = _extractValue(fullBarcode, 'PIN');
      final bagian = _extractValue(fullBarcode, 'Bagian');

      if (nama.isNotEmpty && pin.isNotEmpty) {
        String result = '$nama (PIN: $pin)';
        if (bagian.isNotEmpty) result += ' - $bagian';
        return result;
      }
      return fullBarcode;
    } catch (e) {
      return fullBarcode;
    }
  }

  String _extractValue(String barcode, String key) {
    try {
      final parts = barcode.split('|').map((p) => p.trim()).toList();
      for (final part in parts) {
        if (part.startsWith('$key:')) {
          return part.substring(key.length + 1).trim();
        }
      }
    } catch (_) {}
    return '';
  }

  String _formatTimeLabel(String? raw) {
    if (raw == null || raw.isEmpty || raw == '-') return '-';
    try {
      if (raw.contains('T')) {
        final dt = DateTime.parse(raw).toLocal();
        return '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
      }
      if (raw.contains(':')) {
        final parts = raw.split(':');
        if (parts.length >= 2) {
          return '${parts[0].padLeft(2, '0')}:${parts[1].padLeft(2, '0')}';
        }
      }
    } catch (_) {}
    return raw;
  }

  Future<void> _initializeData() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final logs = await VerificationService.fetchLogs();
      if (mounted) {
        setState(() {
          _logs = logs;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _isLoading = false;
        });
      }
    }
  }

  Color _statusColor(String pengawas, String security) {
    if (pengawas == 'approved' && security == 'approved')
      return AppColors.success;
    if (pengawas == 'approved') return AppColors.info;
    return AppColors.warning;
  }

  String _statusLabel(String pengawas, String security) {
    if (pengawas == 'approved' && security == 'approved') return 'Selesai';
    if (pengawas == 'approved') return 'Menunggu Security';
    return 'Menunggu';
  }

  Future<void> _refresh() async {
    await _initializeData();
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
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.error_outline, size: 48, color: AppColors.error),
            const SizedBox(height: 12),
            Text(
              'Gagal memuat data',
              style: TextStyle(
                fontWeight: FontWeight.w600,
                color: AppColors.textPrimary,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              _error!,
              style: const TextStyle(
                fontSize: 12,
                color: AppColors.textSecondary,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              onPressed: _refresh,
              icon: const Icon(Icons.refresh),
              label: const Text('Coba Lagi'),
            ),
          ],
        ),
      );
    }

    final approved = _logs
        .where(
          (l) =>
              l['status_pengawas'] == 'approved' &&
              l['status_security'] == 'approved',
        )
        .length;
    final waitingSecurity = _logs
        .where(
          (l) =>
              l['status_pengawas'] == 'approved' &&
              l['status_security'] != 'approved',
        )
        .length;
    final pending = _logs.length - approved - waitingSecurity;

    return RefreshIndicator(
      onRefresh: _refresh,
      color: AppColors.primary,
      child: ListView(
        children: [
          // Stats row
          _StatRow(
            total: _logs.length,
            approved: approved,
            waitingSecurity: waitingSecurity,
            pending: pending,
          ),
          const SizedBox(height: 16),
          // Logs list
          if (_logs.isEmpty)
            Container(
              padding: const EdgeInsets.all(32),
              alignment: Alignment.center,
              child: Column(
                children: [
                  Icon(Icons.inbox, size: 48, color: AppColors.textHint),
                  const SizedBox(height: 8),
                  const Text(
                    'Belum ada data verifikasi hari ini',
                    style: TextStyle(color: AppColors.textSecondary),
                  ),
                ],
              ),
            )
          else
            ..._logs.map((log) {
              final idKaryawan = log['id_karyawan'] ?? '';
              final statusP = log['status_pengawas'] ?? 'pending';
              final statusS = log['status_security'] ?? 'pending';
              final info = _extractEmployeeInfo(idKaryawan);
              final scanP = log['scanned_by_pengawas'] ?? '-';
              final scanS = log['scanned_by_security'] ?? '-';
              final timeP = _formatTimeLabel(
                log['scan_time_pengawas']?.toString(),
              );
              final timeS = _formatTimeLabel(
                log['scan_time_security']?.toString(),
              );

              return Container(
                margin: const EdgeInsets.only(bottom: 8),
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
                        _chip(
                          _statusLabel(statusP, statusS),
                          _statusColor(statusP, statusS),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    _scanInfoRow(
                      label: 'Pengawas',
                      by: scanP,
                      time: timeP,
                      color: statusP == 'approved'
                          ? AppColors.success
                          : AppColors.textHint,
                      icon: statusP == 'approved'
                          ? Icons.check_circle
                          : Icons.pending,
                    ),
                    const SizedBox(height: 4),
                    _scanInfoRow(
                      label: 'Security',
                      by: scanS,
                      time: timeS,
                      color: statusS == 'approved'
                          ? AppColors.success
                          : AppColors.textHint,
                      icon: statusS == 'approved'
                          ? Icons.check_circle
                          : Icons.pending,
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

Widget _scanInfoRow({
  required String label,
  required String by,
  required String time,
  required Color color,
  required IconData icon,
  bool hideIfEmpty = false,
}) {
  if (hideIfEmpty && by == '-' && time == '-') return const SizedBox.shrink();

  return Row(
    children: [
      Icon(icon, size: 14, color: color),
      const SizedBox(width: 6),
      Text(
        '$label: ',
        style: TextStyle(
          fontSize: 11,
          color: AppColors.textSecondary,
          fontWeight: FontWeight.w500,
        ),
      ),
      Expanded(
        child: Text(
          by == '-' ? 'Belum scan' : '$by ($time)',
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

class _StatRow extends StatelessWidget {
  final int total, approved, waitingSecurity, pending;

  const _StatRow({
    required this.total,
    required this.approved,
    required this.waitingSecurity,
    required this.pending,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(child: _statCard('Total', '$total', AppColors.info)),
        const SizedBox(width: 8),
        Expanded(child: _statCard('Selesai', '$approved', AppColors.success)),
        const SizedBox(width: 8),
        Expanded(
          child: _statCard('Menunggu', '$waitingSecurity', AppColors.warning),
        ),
        const SizedBox(width: 8),
        Expanded(child: _statCard('Pending', '$pending', AppColors.textHint)),
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
