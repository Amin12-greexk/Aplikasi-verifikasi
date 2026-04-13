import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import '../../core/theme/app_colors.dart';
import 'attendance_service.dart';

/// Attendance tab — lookup attendance by PIN.
class AttendancePage extends StatefulWidget {
  const AttendancePage({super.key});

  @override
  State<AttendancePage> createState() => _AttendancePageState();
}

class _AttendancePageState extends State<AttendancePage> {
  final TextEditingController _pinController = TextEditingController();

  bool _isConnected = false;
  bool _isCheckingConnection = true;
  bool _isLoading = false;
  String? _error;

  List<Map<String, dynamic>> _records = [];
  String? _checkInTime;
  String? _checkOutTime;
  String? _latestMode;
  String? _latestScanTime;
  String? _scannedNama; // To store name from QR

  @override
  void initState() {
    super.initState();
    _refreshConnection();
  }

  @override
  void dispose() {
    _pinController.dispose();
    super.dispose();
  }

  Future<void> _refreshConnection() async {
    setState(() => _isCheckingConnection = true);
    final available = await AttendanceService.isAvailable();
    if (!mounted) return;

    setState(() {
      _isConnected = available;
      _isCheckingConnection = false;
    });
  }

  Future<void> _searchByPin([String? pinFromQr]) async {
    final pin = pinFromQr ?? _pinController.text.trim();
    if (pin.isEmpty) {
      setState(() => _error = 'PIN wajib diisi');
      return;
    }

    if (pinFromQr != null) {
      _pinController.text = pinFromQr;
    }

    setState(() {
      _isLoading = true;
      _error = null;
      _records = [];
      _checkInTime = null;
      _checkOutTime = null;
      _latestMode = null;
      _latestScanTime = null;
    });

    try {
      final summary = await AttendanceService.getTodayStatusByPin(pin);
      final records = await AttendanceService.fetchByPin(pin);

      if (!mounted) return;
      setState(() {
        _records = records;
        _checkInTime = _formatTime(summary?['check_in']?.toString());
        _checkOutTime = _formatTime(summary?['check_out']?.toString());
        _latestMode = summary?['latest_mode']?.toString();
        _latestScanTime = _formatDateTime(
          summary?['latest_scan_date']?.toString(),
        );
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString().replaceFirst('Exception: ', '');
        _isLoading = false;
      });
    }
  }

  void _openScanner() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.black,
      builder: (context) => SizedBox(
        height: MediaQuery.of(context).size.height * 0.7,
        child: Stack(
          children: [
            MobileScanner(
              onDetect: (capture) {
                final barcode = capture.barcodes.firstOrNull;
                if (barcode != null && barcode.rawValue != null) {
                  final raw = barcode.rawValue!;
                  // Extract PIN from QR: "PIN: 123 | Nama: ..."
                  String pin = '';
                  String nama = '';
                  final parts = raw.split('|');
                  for (var p in parts) {
                    if (p.contains('PIN:')) pin = p.split(':').last.trim();
                    if (p.contains('Nama:')) nama = p.split(':').last.trim();
                  }
                  
                  if (pin.isNotEmpty) {
                    setState(() => _scannedNama = nama);
                    Navigator.pop(context);
                    _searchByPin(pin);
                  }
                }
              },
            ),
            Positioned(
              top: 40,
              right: 20,
              child: IconButton(
                icon: const Icon(Icons.close, color: Colors.white, size: 30),
                onPressed: () => Navigator.pop(context),
              ),
            ),
            Center(
              child: Container(
                width: 250,
                height: 250,
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.white, width: 2),
                  borderRadius: const BorderRadius.all(Radius.circular(12)),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _formatDateTime(String? raw) {
    if (raw == null || raw.trim().isEmpty) return '-';
    final dt = _tryParse(raw);
    if (dt == null) return raw;

    final y = dt.year.toString().padLeft(4, '0');
    final m = dt.month.toString().padLeft(2, '0');
    final d = dt.day.toString().padLeft(2, '0');
    final hh = dt.hour.toString().padLeft(2, '0');
    final mm = dt.minute.toString().padLeft(2, '0');
    final ss = dt.second.toString().padLeft(2, '0');
    return '$y-$m-$d $hh:$mm:$ss';
  }

  String _formatTime(String? raw) {
    if (raw == null || raw.trim().isEmpty) return '-';
    final dt = _tryParse(raw);
    if (dt == null) return raw;

    final hh = dt.hour.toString().padLeft(2, '0');
    final mm = dt.minute.toString().padLeft(2, '0');
    final ss = dt.second.toString().padLeft(2, '0');
    return '$hh:$mm:$ss';
  }

  DateTime? _tryParse(String raw) {
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

  Color _modeColor(String mode) {
    final lower = mode.toLowerCase();
    if (lower.contains('masuk')) return AppColors.success;
    if (lower.contains('pulang')) return AppColors.info;
    return AppColors.warning;
  }

  @override
  Widget build(BuildContext context) {
    final latestMode = _latestMode ?? '-';
    final latestModeColor = _modeColor(latestMode);

    return ListView(
      padding: const EdgeInsets.all(0),
      children: [
        // Connection status
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: _isConnected
                ? AppColors.success.withAlpha(10)
                : AppColors.warning.withAlpha(15),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: _isConnected
                  ? AppColors.success.withAlpha(40)
                  : AppColors.warning.withAlpha(40),
            ),
          ),
          child: Row(
            children: [
              Icon(
                _isConnected ? Icons.cloud_done : Icons.cloud_off,
                color: _isConnected ? AppColors.success : AppColors.warning,
                size: 22,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _isCheckingConnection
                          ? 'Mengecek koneksi...'
                          : (_isConnected ? 'Terhubung' : 'Belum Terhubung'),
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: _isConnected
                            ? AppColors.success
                            : AppColors.warning,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      _isConnected
                          ? 'Server absensi aktif. Silakan cari data berdasarkan PIN.'
                          : 'Server absensi belum dapat diakses. Cek koneksi internet / endpoint.',
                      style: TextStyle(
                        fontSize: 12,
                        color: _isConnected
                            ? AppColors.success.withAlpha(180)
                            : AppColors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                onPressed: _refreshConnection,
                icon: const Icon(Icons.refresh),
                color: AppColors.textSecondary,
                tooltip: 'Refresh koneksi',
              ),
            ],
          ),
        ),

        const SizedBox(height: 14),

        // Search PIN
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: AppColors.cardBorder),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Cari Absensi Karyawan',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textPrimary,
                ),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _pinController,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        hintText: 'PIN (e.g. 193969)',
                        prefixIcon: Icon(Icons.badge_outlined),
                      ),
                      onSubmitted: (_) => _searchByPin(),
                    ),
                  ),
                  const SizedBox(width: 8),
                  SizedBox(
                    height: 48,
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        backgroundColor: AppColors.surface,
                        foregroundColor: AppColors.primary,
                        side: BorderSide(color: AppColors.primary.withAlpha(100)),
                      ),
                      onPressed: _openScanner,
                      child: const Icon(Icons.qr_code_scanner),
                    ),
                  ),
                  const SizedBox(width: 8),
                  SizedBox(
                    height: 48,
                    child: ElevatedButton(
                      onPressed: (_isLoading || !_isConnected)
                          ? null
                          : () => _searchByPin(),
                      child: _isLoading
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : const Text('Cari'),
                    ),
                  ),
                ],
              ),
              if (_error != null) ...[
                const SizedBox(height: 8),
                Text(
                  _error!,
                  style: const TextStyle(fontSize: 12, color: AppColors.error),
                ),
              ],
            ],
          ),
        ),

        const SizedBox(height: 20),

        // Status hari ini
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text(
              'Status Hari Ini',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: AppColors.textPrimary,
              ),
            ),
            if (_scannedNama != null)
              Text(
                _scannedNama!,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  color: AppColors.primary,
                ),
              ),
          ],
        ),
        const SizedBox(height: 10),
        Container(
          padding: const EdgeInsets.all(16),
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
                  _statusTile(
                    icon: Icons.login,
                    label: 'Check-in',
                    value: _checkInTime ?? '-',
                    color: _checkInTime != null
                        ? AppColors.success
                        : AppColors.textHint,
                  ),
                  const SizedBox(width: 16),
                  _statusTile(
                    icon: Icons.logout,
                    label: 'Check-out',
                    value: _checkOutTime ?? '-',
                    color: _checkOutTime != null
                        ? AppColors.info
                        : AppColors.textHint,
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: latestModeColor.withAlpha(15),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    Icon(Icons.info_outline, size: 14, color: latestModeColor),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        _latestMode == null
                            ? 'Belum ada data absensi untuk PIN ini'
                            : 'Status terakhir: $latestMode (${_latestScanTime ?? "-"})',
                        style: TextStyle(fontSize: 11, color: latestModeColor),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),

        const SizedBox(height: 24),

        // Recent records
        const Text(
          'Riwayat Scan',
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: AppColors.textPrimary,
          ),
        ),
        const SizedBox(height: 10),
        if (_records.isEmpty)
          Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: AppColors.cardBorder),
            ),
            child: Column(
              children: [
                Icon(Icons.inbox, size: 40, color: AppColors.textHint),
                const SizedBox(height: 8),
                const Text(
                  'Belum ada data absensi',
                  style: TextStyle(
                    fontSize: 13,
                    color: AppColors.textSecondary,
                  ),
                ),
                const SizedBox(height: 4),
                const Text(
                  'Masukkan PIN atau Scan QR lalu klik Cari.',
                  style: TextStyle(fontSize: 11, color: AppColors.textHint),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          )
        else
          Container(
            width: double.infinity,
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppColors.cardBorder),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: LayoutBuilder(
                builder: (context, constraints) {
                  return DataTable(
                    headingRowColor: MaterialStateProperty.all(AppColors.background),
                    columnSpacing: 10,
                    horizontalMargin: 12,
                    columns: [
                      DataColumn(
                        label: SizedBox(
                          width: constraints.maxWidth * 0.35,
                          child: const Text('PIN/NAMA', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11)),
                        ),
                      ),
                      DataColumn(
                        label: SizedBox(
                          width: constraints.maxWidth * 0.35,
                          child: const Text('WAKTU', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11)),
                        ),
                      ),
                      DataColumn(
                        label: SizedBox(
                          width: constraints.maxWidth * 0.18,
                          child: const Text('STATUS', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11)),
                        ),
                      ),
                    ],
                    rows: _records.take(20).map((record) {
                      final mode = record['mode']?.toString() ?? '-';
                      final modeColor = _modeColor(mode);
                      final pin = record['pin']?.toString() ?? '-';
                      final name = _scannedNama ?? '';
                      
                      return DataRow(cells: [
                        DataCell(
                          SizedBox(
                            width: constraints.maxWidth * 0.35,
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Text(
                                  pin,
                                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 11),
                                  overflow: TextOverflow.ellipsis,
                                ),
                                if (name.isNotEmpty)
                                  Text(
                                    name,
                                    style: const TextStyle(fontSize: 9, color: AppColors.textSecondary),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                              ],
                            ),
                          ),
                        ),
                        DataCell(
                          SizedBox(
                            width: constraints.maxWidth * 0.35,
                            child: Text(
                              _formatDateTime(record['scan_date']?.toString()),
                              style: const TextStyle(fontSize: 10),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ),
                        DataCell(
                          SizedBox(
                            width: constraints.maxWidth * 0.18,
                            child: UnconstrainedBox(
                              alignment: Alignment.centerLeft,
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                                decoration: BoxDecoration(
                                  color: modeColor.withAlpha(15),
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: Text(
                                  mode,
                                  style: TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: modeColor),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ]);
                    }).toList(),
                  );
                },
              ),
            ),
          ),
      ],
    );
  }

  Widget _statusTile({
    required IconData icon,
    required String label,
    required String value,
    required Color color,
  }) {
    return Expanded(
      child: Row(
        children: [
          Icon(icon, size: 20, color: color),
          const SizedBox(width: 8),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: TextStyle(fontSize: 11, color: AppColors.textSecondary),
              ),
              Text(
                value,
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: color,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
