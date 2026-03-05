import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';
import 'history_service.dart';

/// Riwayat tab with date filter, module filter, and status filter.
class HistoryPage extends StatefulWidget {
  const HistoryPage({super.key});

  @override
  State<HistoryPage> createState() => _HistoryPageState();
}

class _HistoryPageState extends State<HistoryPage> {
  DateTime _selectedDate = DateTime.now();
  String _selectedModule = 'verification';
  List<Map<String, dynamic>> _records = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadHistory();
  }

  String _formatDate(DateTime date) {
    return '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
  }

  String _formatDisplayDate(DateTime date) {
    const months = [
      '', 'Jan', 'Feb', 'Mar', 'Apr', 'Mei', 'Jun',
      'Jul', 'Agu', 'Sep', 'Okt', 'Nov', 'Des',
    ];
    return '${date.day} ${months[date.month]} ${date.year}';
  }

  Future<void> _loadHistory() async {
    setState(() => _isLoading = true);
    try {
      final dateStr = _formatDate(_selectedDate);
      List<Map<String, dynamic>> data;
      if (_selectedModule == 'verification') {
        data = await HistoryService.fetchVerificationHistory(dateStr);
      } else {
        data = await HistoryService.fetchAttendanceHistory(dateStr);
      }
      if (mounted) {
        setState(() {
          _records = data;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime(2024),
      lastDate: DateTime.now(),
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: const ColorScheme.light(primary: AppColors.primary),
          ),
          child: child!,
        );
      },
    );
    if (picked != null && picked != _selectedDate) {
      setState(() => _selectedDate = picked);
      _loadHistory();
    }
  }

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
    } catch (_) {
      return fullBarcode;
    }
  }

  String _extractValue(String barcode, String key) {
    try {
      final parts = barcode.split('|').map((p) => p.trim()).toList();
      for (final part in parts) {
        if (part.startsWith('$key:')) return part.substring(key.length + 1).trim();
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
    } catch (_) {}
    return raw;
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // Filters row
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: AppColors.cardBorder),
          ),
          child: Column(
            children: [
              // Date picker
              InkWell(
                onTap: _pickDate,
                borderRadius: BorderRadius.circular(10),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  decoration: BoxDecoration(
                    color: AppColors.background,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.calendar_today, size: 18, color: AppColors.primary),
                      const SizedBox(width: 10),
                      Text(
                        _formatDisplayDate(_selectedDate),
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: AppColors.textPrimary,
                        ),
                      ),
                      const Spacer(),
                      const Icon(Icons.arrow_drop_down, color: AppColors.textSecondary),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 10),
              // Module filter
              Row(
                children: [
                  _filterChip('Verifikasi', 'verification'),
                  const SizedBox(width: 8),
                  _filterChip('Absensi', 'attendance'),
                ],
              ),
            ],
          ),
        ),

        const SizedBox(height: 12),

        // Content
        Expanded(
          child: _isLoading
              ? const Center(
                  child: CircularProgressIndicator(color: AppColors.primary, strokeWidth: 2.5),
                )
              : _selectedModule == 'attendance'
                  ? _buildAttendancePlaceholder()
                  : _records.isEmpty
                      ? _buildEmptyState()
                      : RefreshIndicator(
                          onRefresh: _loadHistory,
                          color: AppColors.primary,
                          child: ListView.builder(
                            itemCount: _records.length,
                            itemBuilder: (context, index) {
                              final log = _records[index];
                              return _buildVerificationItem(log);
                            },
                          ),
                        ),
        ),
      ],
    );
  }

  Widget _filterChip(String label, String value) {
    final isSelected = _selectedModule == value;
    return GestureDetector(
      onTap: () {
        setState(() => _selectedModule = value);
        _loadHistory();
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected ? AppColors.primary : AppColors.background,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: isSelected ? AppColors.primary : AppColors.cardBorder,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: isSelected ? Colors.white : AppColors.textSecondary,
          ),
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.inbox, size: 48, color: AppColors.textHint),
          const SizedBox(height: 8),
          const Text(
            'Tidak ada data di tanggal ini',
            style: TextStyle(color: AppColors.textSecondary),
          ),
        ],
      ),
    );
  }

  Widget _buildAttendancePlaceholder() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.cloud_off, size: 48, color: AppColors.textHint),
          const SizedBox(height: 8),
          const Text(
            'Data absensi belum tersedia',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w500,
              color: AppColors.textSecondary,
            ),
          ),
          const SizedBox(height: 4),
          const Text(
            'Fitur ini akan aktif setelah endpoint absensi terhubung.',
            style: TextStyle(fontSize: 12, color: AppColors.textHint),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _buildVerificationItem(Map<String, dynamic> log) {
    final id = log['id_karyawan'] ?? '';
    final info = _extractEmployeeInfo(id);
    final statusP = log['status_pengawas'] ?? 'pending';
    final statusS = log['status_security'] ?? 'pending';
    final timeP = _formatTimeLabel(log['scan_time_pengawas']?.toString());
    final timeS = _formatTimeLabel(log['scan_time_security']?.toString());

    Color statusColor;
    String statusLabel;
    if (statusP == 'approved' && statusS == 'approved') {
      statusColor = AppColors.success;
      statusLabel = 'Selesai';
    } else if (statusP == 'approved') {
      statusColor = AppColors.info;
      statusLabel = 'Menunggu Security';
    } else {
      statusColor = AppColors.warning;
      statusLabel = 'Menunggu';
    }

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
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: statusColor.withAlpha(20),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  statusLabel,
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                    color: statusColor,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Icon(
                statusP == 'approved' ? Icons.check_circle : Icons.pending,
                size: 14,
                color: statusP == 'approved' ? AppColors.success : AppColors.textHint,
              ),
              const SizedBox(width: 4),
              Text(
                'Pengawas: $timeP',
                style: TextStyle(
                  fontSize: 11,
                  color: statusP == 'approved' ? AppColors.success : AppColors.textHint,
                ),
              ),
              const SizedBox(width: 16),
              Icon(
                statusS == 'approved' ? Icons.check_circle : Icons.pending,
                size: 14,
                color: statusS == 'approved' ? AppColors.success : AppColors.textHint,
              ),
              const SizedBox(width: 4),
              Text(
                'Security: $timeS',
                style: TextStyle(
                  fontSize: 11,
                  color: statusS == 'approved' ? AppColors.success : AppColors.textHint,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
