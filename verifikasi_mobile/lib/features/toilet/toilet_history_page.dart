import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';
import '../../core/utils/wib_time.dart';
import '../history/history_service.dart';

class ToiletHistoryPage extends StatefulWidget {
  const ToiletHistoryPage({super.key});

  @override
  State<ToiletHistoryPage> createState() => _ToiletHistoryPageState();
}

class _ToiletHistoryPageState extends State<ToiletHistoryPage> {
  DateTime _selectedDate = DateTime.now();
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
      '',
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'Mei',
      'Jun',
      'Jul',
      'Agu',
      'Sep',
      'Okt',
      'Nov',
      'Des',
    ];
    return '${date.day} ${months[date.month]} ${date.year}';
  }

  Future<void> _loadHistory() async {
    setState(() => _isLoading = true);
    try {
      final dateStr = _formatDate(_selectedDate);
      final data = await HistoryService.fetchToiletHistory(dateStr);
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
        if (part.startsWith('$key:')) {
          return part.substring(key.length + 1).trim();
        }
      }
    } catch (_) {}
    return '';
  }

  String _formatTimeLabel(String? raw) {
    final formatted = WibTime.formatTime(raw);
    return formatted == '-' ? (raw ?? '-') : formatted;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Riwayat Toilet',
          style: TextStyle(fontWeight: FontWeight.w600, fontSize: 16),
        ),
        backgroundColor: AppColors.surface,
        foregroundColor: AppColors.textPrimary,
        elevation: 0,
        centerTitle: true,
      ),
      backgroundColor: AppColors.background,
      body: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            margin: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: AppColors.cardBorder),
            ),
            child: InkWell(
              onTap: _pickDate,
              borderRadius: BorderRadius.circular(10),
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 10,
                ),
                decoration: BoxDecoration(
                  color: AppColors.background,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Row(
                  children: [
                    const Icon(
                      Icons.calendar_today,
                      size: 18,
                      color: AppColors.primary,
                    ),
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
                    const Icon(
                      Icons.arrow_drop_down,
                      color: AppColors.textSecondary,
                    ),
                  ],
                ),
              ),
            ),
          ),
          Expanded(
            child: _isLoading
                ? const Center(
                    child: CircularProgressIndicator(
                      color: AppColors.primary,
                      strokeWidth: 2.5,
                    ),
                  )
                : _records.isEmpty
                ? _buildEmptyState()
                : RefreshIndicator(
                    onRefresh: _loadHistory,
                    color: AppColors.primary,
                    child: ListView.builder(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      itemCount: _records.length,
                      itemBuilder: (context, index) {
                        return _buildToiletItem(_records[index]);
                      },
                    ),
                  ),
          ),
        ],
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
            'Tidak ada data toilet di tanggal ini',
            style: TextStyle(color: AppColors.textSecondary),
          ),
        ],
      ),
    );
  }

  Widget _buildToiletItem(Map<String, dynamic> permit) {
    final id = permit['id_karyawan'] ?? '';
    final info = _extractEmployeeInfo(id);
    final proofStatus =
        permit['proof_status']?.toString().toLowerCase() ?? 'pending';
    final permitState =
        permit['permit_state']?.toString().toLowerCase() ?? 'active';
    final duration = permit['duration_minutes']?.toString() ?? '-';
    final approvedAt = _formatTimeLabel(permit['approved_at']?.toString());
    final expiresAt = _formatTimeLabel(permit['expires_at']?.toString());
    final proofAt = _formatTimeLabel(permit['proof_scanned_at']?.toString());

    Color statusColor;
    String statusLabel;
    if (permitState == 'expired') {
      statusColor = AppColors.error;
      statusLabel = 'Waktu Habis';
    } else if (permitState == 'waiting_security') {
      statusColor = AppColors.warning;
      statusLabel = 'Menunggu Security';
    } else if (proofStatus == 'scanned') {
      statusColor = AppColors.success;
      statusLabel = 'Tervalidasi';
    } else {
      statusColor = AppColors.info;
      statusLabel = 'Menunggu Proof';
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
              Icon(Icons.timer, size: 14, color: statusColor),
              const SizedBox(width: 4),
              Text(
                '$duration menit',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: statusColor,
                ),
              ),
              const SizedBox(width: 14),
              const Icon(Icons.schedule, size: 14, color: AppColors.textHint),
              const SizedBox(width: 4),
              Text(
                'Batas: $expiresAt',
                style: const TextStyle(
                  fontSize: 11,
                  color: AppColors.textSecondary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'Pengawas: ${permit['approved_by'] ?? '-'} ($approvedAt)',
            style: const TextStyle(
              fontSize: 11,
              color: AppColors.textSecondary,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            proofStatus == 'scanned'
                ? 'Security: ${permit['proof_scanned_by'] ?? '-'} ($proofAt)'
                : 'Security: Belum proof scan',
            style: TextStyle(
              fontSize: 11,
              color: proofStatus == 'scanned'
                  ? AppColors.success
                  : AppColors.textHint,
            ),
          ),
        ],
      ),
    );
  }
}
