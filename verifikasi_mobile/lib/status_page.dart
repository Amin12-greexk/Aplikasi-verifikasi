import 'package:flutter/material.dart';

import 'api_client_retry.dart'; // Use retry version
import 'daily_refresh_manager.dart';
import 'offline_queue.dart';

class StatusTab extends StatefulWidget {
  const StatusTab({super.key});

  @override
  State<StatusTab> createState() => _StatusTabState();
}

class _StatusTabState extends State<StatusTab> {
  late Future<Map<String, dynamic>> _future;

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

  String _formatTimeLabel(String? raw) {
    if (raw == null || raw.isEmpty) return '-';
    // Try full DateTime parse (handles "2025-12-08T14:22:00" or "2025-12-08 14:22:00")
    final normalized = raw.contains('T') ? raw : raw.replaceFirst(' ', 'T');
    final dt = DateTime.tryParse(normalized);
    if (dt != null) {
      final local = dt.toLocal();
      final hh = local.hour.toString().padLeft(2, '0');
      final mm = local.minute.toString().padLeft(2, '0');
      return '$hh:$mm';
    }

    // Fallback: extract HH:mm pattern directly from the string if parsing failed
    final hhmm = RegExp(r'(\d{1,2}:\d{2})').firstMatch(raw)?.group(1);
    if (hhmm != null) return hhmm;

    // Last resort: return trimmed raw string (first 16 chars) so user still sees something
    return raw.length > 16 ? raw.substring(0, 16) : raw;
  }

  Future<Map<String, dynamic>> _initializeData() async {
    try {
      // Check if should refresh and clear old data
      final shouldRefresh = await DailyRefreshManager.shouldRefreshDaily();
      if (shouldRefresh) {
        // Call server to reset/clear logs from previous day
        // This will move current logs to history and clear the table
        try {
          await ApiClientRetry.dailyReset();
          // Only mark as refreshed if the API call succeeded
          await DailyRefreshManager.markAsRefreshed();
          print('Daily reset completed successfully');
        } catch (e) {
          print('Daily reset error: $e');
          // Don't mark as refreshed - will retry next time the app opens
          // Continue anyway to show current data
        }
      }
    } catch (e) {
      print('Error in _initializeData: $e');
    }
    final logs = await ApiClientRetry.fetchLogs();
    final pending = await OfflineQueueManager.getPending();
    return {'logs': logs, 'pending': pending};
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
    final data = _initializeData();
    setState(() => _future = data);
    await data;
  }

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      onRefresh: _refresh,
      color: Colors.green.shade600,
      child: FutureBuilder<Map<String, dynamic>>(
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
          final data = snapshot.data ?? {'logs': <Map<String, dynamic>>[], 'pending': <Map<String, dynamic>>[]};
          final logs = (data['logs'] as List).cast<Map<String, dynamic>>();
          final pendingQueue = (data['pending'] as List).cast<Map<String, dynamic>>();
          // Logs are already sorted newest first from server
          final accBoth = logs.where((e) => e['status_pengawas'] == 'ACC' && e['status_security'] == 'ACC').length;
          final accPengawas =
              logs.where((e) => e['status_pengawas'] == 'ACC' && e['status_security'] != 'ACC').length;
          final pendingCount = logs.length - accBoth - accPengawas;
          return ListView(
            padding: const EdgeInsets.only(bottom: 20),
            children: [
              const SizedBox(height: 8),
              _StatRow(total: logs.length, accBoth: accBoth, accPengawas: accPengawas, pending: pendingCount),
              const SizedBox(height: 20),
              if (pendingQueue.isNotEmpty)
                Card(
                  margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                  color: Colors.orange.shade50,
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(Icons.cloud_off, color: Colors.orange.shade700, size: 18),
                            const SizedBox(width: 8),
                            Text(
                              'Pending sync (${pendingQueue.length})',
                              style: TextStyle(
                                color: Colors.orange.shade800,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        ...pendingQueue.map((q) {
                          final id = q['id']?.toString() ?? '-';
                          final role = q['role']?.toString() ?? '-';
                          final created = _formatTimeLabel(q['created_at']?.toString());
                          return Padding(
                            padding: const EdgeInsets.symmetric(vertical: 4),
                            child: Row(
                              children: [
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                  decoration: BoxDecoration(
                                    color: Colors.orange.shade100,
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Text(
                                    role.toUpperCase(),
                                    style: TextStyle(
                                      color: Colors.orange.shade800,
                                      fontWeight: FontWeight.w700,
                                      fontSize: 11,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    id,
                                    style: TextStyle(
                                      color: Colors.grey.shade800,
                                      fontWeight: FontWeight.w600,
                                    ),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Text(
                                  'Jam: $created',
                                  style: TextStyle(
                                    color: Colors.orange.shade800,
                                    fontWeight: FontWeight.w700,
                                    fontSize: 11,
                                  ),
                                ),
                              ],
                            ),
                          );
                        }),
                        const SizedBox(height: 8),
                        Text(
                          'Akan otomatis dikirim saat koneksi kembali.',
                          style: TextStyle(color: Colors.orange.shade700, fontSize: 11),
                        ),
                      ],
                    ),
                  ),
                ),
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
                  final pengawasScanAt = _formatTimeLabel(
                    item['pengawas_scanned_at']?.toString() ?? item['created_at']?.toString(),
                  );
                  final securityScanAt = _formatTimeLabel(
                    item['security_scanned_at']?.toString(),
                  );
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
                            _scanInfoRow(
                              label: 'Pengawas',
                              by: pengawasScanBy,
                              time: pengawasScanAt,
                              color: Colors.blue.shade600,
                              icon: Icons.admin_panel_settings,
                              hideIfEmpty: true,
                            ),
                            const SizedBox(height: 4),
                            _scanInfoRow(
                              label: 'Security',
                              by: securityScanBy,
                              time: securityScanAt,
                              color: Colors.green.shade600,
                              icon: Icons.security,
                              hideIfEmpty: true,
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

Widget _scanInfoRow({
  required String label,
  required String by,
  required String time,
  required Color color,
  required IconData icon,
  bool hideIfEmpty = false,
}) {
  final hasData = (by != '-' && by.trim().isNotEmpty) || (time != '-' && time.trim().isNotEmpty);
  if (hideIfEmpty && !hasData) return const SizedBox.shrink();

  return Row(
    crossAxisAlignment: CrossAxisAlignment.center,
    children: [
      Icon(icon, size: 14, color: color),
      const SizedBox(width: 6),
      Text(
        '$label:',
        style: TextStyle(
          color: color,
          fontSize: 11,
          fontWeight: FontWeight.w700,
        ),
      ),
      const SizedBox(width: 6),
      Flexible(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (by != '-' && by.trim().isNotEmpty)
              Text(
                by,
                style: TextStyle(
                  color: Colors.grey.shade800,
                  fontSize: 11,
                  fontWeight: FontWeight.w500,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            if (time != '-' && time.trim().isNotEmpty)
              Text(
                'Jam: $time',
                style: TextStyle(
                  color: color,
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                ),
                overflow: TextOverflow.ellipsis,
              ),
          ],
        ),
      ),
    ],
  );
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
