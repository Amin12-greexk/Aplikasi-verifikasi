import 'package:flutter/material.dart';

import 'api_client_retry.dart'; // Use retry version
import 'daily_refresh_manager.dart';

class StatusTab extends StatefulWidget {
  const StatusTab({super.key});

  @override
  State<StatusTab> createState() => _StatusTabState();
}

class _StatusTabState extends State<StatusTab> {
  late Future<List<Map<String, dynamic>>> _future;

  @override
  void initState() {
    super.initState();
    _future = _initializeData();
  }

  /// Parse barcode string to extract Nama, PIN, and Bagian
  /// Example input: "Nama: SURATI | PIN: 12053 | NIK: 3321125211850005 | Bagian: Cuci Hancuran | Alamat: ..."
  /// Returns: "SURATI (PIN: 12053) - Cuci Hancuran"
  String _extractEmployeeInfo(String fullBarcode) {
    try {
      final nama = _extractValue(fullBarcode, 'Nama');
      final pin = _extractValue(fullBarcode, 'PIN');
      final bagian = _extractValue(fullBarcode, 'Bagian');

      if (nama.isEmpty && pin.isEmpty && bagian.isEmpty) {
        // If parsing fails, return original string truncated
        return fullBarcode.length > 30 ? '${fullBarcode.substring(0, 30)}...' : fullBarcode;
      }

      // Format: "NAMA (PIN: 12053) - Bagian"
      final List<String> parts = [];
      if (nama.isNotEmpty) parts.add(nama);
      if (pin.isNotEmpty) parts.add('PIN: $pin');
      if (bagian.isNotEmpty) parts.add(bagian);

      return parts.join(' | ');
    } catch (e) {
      return fullBarcode.length > 30 ? '${fullBarcode.substring(0, 30)}...' : fullBarcode;
    }
  }

  /// Extract value from barcode string by key
  /// Example: extractValue("Nama: SURATI | PIN: 12053", "Nama") returns "SURATI"
  String _extractValue(String barcode, String key) {
    try {
      final regex = RegExp('$key:\\s*([^|]+)');
      final match = regex.firstMatch(barcode);
      if (match != null) {
        return match.group(1)?.trim() ?? '';
      }
    } catch (e) {
      // Silent fail, return empty string
    }
    return '';
  }

  Future<List<Map<String, dynamic>>> _initializeData() async {
    try {
      // Check if should refresh and clear old data
      final shouldRefresh = await DailyRefreshManager.shouldRefreshDaily();
      if (shouldRefresh) {
        // Call server to reset/clear logs from previous day
        // This will move current logs to history and clear the table
        try {
          await ApiClientRetry.dailyReset();
        } catch (e) {
          print('Daily reset error: $e');
          // Continue anyway, just log the data
        }
      }
    } catch (e) {
      print('Error in _initializeData: $e');
    }
    return await ApiClientRetry.fetchLogs();
  }

  Color _statusColor(String pengawas, String security) {
    if (pengawas == 'ACC' && security == 'ACC') return Colors.green.shade100;
    if (pengawas == 'ACC' && security != 'ACC') return Colors.amber.shade100;
    return Colors.grey.shade200;
  }

  String _statusLabel(String pengawas, String security) {
    if (pengawas == 'ACC' && security == 'ACC') return 'ACC Pengawas & Security';
    if (pengawas == 'ACC') return 'ACC Pengawas, Security pending';
    return 'Belum ACC';
  }

  Future<void> _refresh() async {
    final data = ApiClientRetry.fetchLogs();
    setState(() => _future = data);
    await data;
  }

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      onRefresh: _refresh,
      color: Colors.green.shade600,
      child: FutureBuilder<List<Map<String, dynamic>>>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(
              child: CircularProgressIndicator(
                strokeWidth: 3,
              ),
            );
          }
          if (snapshot.hasError) {
            return ListView(
              children: [
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.red.shade50,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.red.shade300),
                    ),
                    child: Text(
                      'Error: ${snapshot.error}',
                      style: TextStyle(color: Colors.red.shade700),
                    ),
                  ),
                )
              ],
            );
          }
          final logs = snapshot.data ?? [];
          // Logs are already sorted newest first from server
          final accBoth = logs.where((e) => e['status_pengawas'] == 'ACC' && e['status_security'] == 'ACC').length;
          final accPengawas =
              logs.where((e) => e['status_pengawas'] == 'ACC' && e['status_security'] != 'ACC').length;
          final pending = logs.length - accBoth - accPengawas;
          return ListView(
            padding: const EdgeInsets.only(bottom: 20),
            children: [
              const SizedBox(height: 8),
              _StatRow(total: logs.length, accBoth: accBoth, accPengawas: accPengawas, pending: pending),
              const SizedBox(height: 20),
              if (logs.isEmpty)
                Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(24),
                        decoration: BoxDecoration(
                          color: Colors.grey.shade100,
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          Icons.inbox_outlined,
                          size: 48,
                          color: Colors.grey.shade400,
                        ),
                      ),
                      const SizedBox(height: 16),
                      Text(
                        'Belum ada data',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w500,
                          color: Colors.grey.shade600,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Data verifikasi akan muncul di sini',
                        style: TextStyle(
                          fontSize: 13,
                          color: Colors.grey.shade500,
                        ),
                      ),
                    ],
                  ),
                )
              else
                ...logs.map((item) {
                  final fullBarcode = item['id_karyawan']?.toString() ?? '-';
                  final displayName = _extractEmployeeInfo(fullBarcode);
                  final statusPengawas = item['status_pengawas']?.toString() ?? 'PENDING';
                  final statusSecurity = item['status_security']?.toString() ?? 'PENDING';
                  final pengawasScanBy = item['pengawas_scanned_by']?.toString() ?? '-';
                  final securityScanBy = item['security_scanned_by']?.toString() ?? '-';
                  final label = _statusLabel(statusPengawas, statusSecurity);
                  final isDone = statusPengawas == 'ACC' && statusSecurity == 'ACC';
                  return Container(
                    margin: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: isDone ? Colors.green.shade200 : Colors.amber.shade200,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withAlpha(20),
                          blurRadius: 8,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: ListTile(
                      contentPadding: const EdgeInsets.all(16),
                      leading: Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: isDone ? Colors.green.shade100 : Colors.amber.shade100,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Icon(
                          isDone ? Icons.verified_user : Icons.pending_actions,
                          color: isDone ? Colors.green.shade600 : Colors.amber.shade600,
                          size: 20,
                        ),
                      ),
                      title: Text(
                        displayName,
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      subtitle: Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Wrap(
                              spacing: 8,
                              runSpacing: 4,
                              children: [
                                _chip('Pengawas: $statusPengawas', statusPengawas == 'ACC' ? Colors.green : Colors.amber),
                                _chip('Security: $statusSecurity', statusSecurity == 'ACC' ? Colors.green : Colors.amber),
                              ],
                            ),
                            const SizedBox(height: 6),
                            Text(
                              label,
                              style: TextStyle(color: Colors.grey.shade700, fontSize: 12),
                            ),
                            const SizedBox(height: 8),
                            if (pengawasScanBy != '-')
                              Text(
                                'Scan pengawas: $pengawasScanBy',
                                style: TextStyle(
                                  color: Colors.blue.shade600,
                                  fontSize: 11,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            if (securityScanBy != '-')
                              Text(
                                'Scan security: $securityScanBy',
                                style: TextStyle(
                                  color: Colors.green.shade600,
                                  fontSize: 11,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                  );
                }),
            ],
          );
        },
      ),
    );
  }
}

class _StatRow extends StatelessWidget {
  final int total;
  final int accBoth;
  final int accPengawas;
  final int pending;
  const _StatRow({
    required this.total,
    required this.accBoth,
    required this.accPengawas,
    required this.pending,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Row(
        children: [
          Expanded(child: _statCard('Total', '$total', Colors.grey.shade200)),
          const SizedBox(width: 8),
          Expanded(child: _statCard('ACC 2 Layer', '$accBoth', Colors.green.shade100)),
          const SizedBox(width: 8),
          Expanded(child: _statCard('ACC Pengawas', '$accPengawas', Colors.amber.shade100)),
          const SizedBox(width: 8),
          Expanded(child: _statCard('Pending', '$pending', Colors.grey.shade300)),
        ],
      ),
    );
  }

  Widget _statCard(String title, String value, Color bg) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: bg, width: 2),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withAlpha(15),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: TextStyle(
              fontSize: 11,
              color: Colors.grey.shade600,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            value,
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.bold,
              color: bg.withAlpha(255),
            ),
          ),
        ],
      ),
    );
  }
}

Widget _chip(String text, Color color) {
  return Chip(
    label: Text(text),
    backgroundColor: color.withValues(alpha: 0.15),
    labelStyle: TextStyle(color: color.darken()),
    side: BorderSide(color: color.withValues(alpha: 0.4)),
    visualDensity: VisualDensity.compact,
  );
}

extension on Color {
  Color darken([double amount = .2]) {
    final f = 1 - amount;
    return Color.fromARGB((a * 255).round(), (r * 255 * f).round(), (g * 255 * f).round(),
        (b * 255 * f).round());
  }
}
