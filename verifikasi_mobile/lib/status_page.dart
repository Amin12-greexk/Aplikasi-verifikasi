import 'package:flutter/material.dart';

import 'api_client.dart';

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
    _future = fetchLogs();
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
    final data = fetchLogs();
    setState(() => _future = data);
    await data;
  }

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      onRefresh: _refresh,
      child: FutureBuilder<List<Map<String, dynamic>>>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return ListView(
              children: [
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text('Error: ${snapshot.error}'),
                )
              ],
            );
          }
          final logs = snapshot.data ?? [];
          final accBoth = logs.where((e) => e['status_pengawas'] == 'ACC' && e['status_security'] == 'ACC').length;
          final accPengawas =
              logs.where((e) => e['status_pengawas'] == 'ACC' && e['status_security'] != 'ACC').length;
          final pending = logs.length - accBoth - accPengawas;
          return ListView(
            padding: const EdgeInsets.only(bottom: 12),
            children: [
              const SizedBox(height: 8),
              _StatRow(total: logs.length, accBoth: accBoth, accPengawas: accPengawas, pending: pending),
              const SizedBox(height: 12),
              if (logs.isEmpty)
                const Padding(
                  padding: EdgeInsets.all(16),
                  child: Text('Belum ada data'),
                )
              else
                ...logs.map((item) {
                  final id = item['id_karyawan']?.toString() ?? '-';
                  final statusPengawas = item['status_pengawas']?.toString() ?? 'PENDING';
                  final statusSecurity = item['status_security']?.toString() ?? 'PENDING';
                  final color = _statusColor(statusPengawas, statusSecurity);
                  final label = _statusLabel(statusPengawas, statusSecurity);
                  final isDone = statusPengawas == 'ACC' && statusSecurity == 'ACC';
                  return Container(
                    margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                    decoration: BoxDecoration(
                      color: color,
                      borderRadius: BorderRadius.circular(12),
                      boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 4, offset: Offset(0, 2))],
                    ),
                    child: ListTile(
                      leading: CircleAvatar(
                        backgroundColor: isDone ? Colors.green : Colors.orange,
                        child: Icon(isDone ? Icons.verified : Icons.pending, color: Colors.white),
                      ),
                      title: Text(id, style: const TextStyle(fontWeight: FontWeight.bold)),
                      subtitle: Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Wrap(
                          spacing: 8,
                          runSpacing: -4,
                          children: [
                            _chip('Pengawas: $statusPengawas', statusPengawas == 'ACC' ? Colors.green : Colors.amber),
                            _chip('Security: $statusSecurity',
                                statusSecurity == 'ACC' ? Colors.green : Colors.amber),
                            Text(label, style: TextStyle(color: Colors.grey.shade800)),
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
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: const TextStyle(fontSize: 12, color: Colors.black54)),
          const SizedBox(height: 6),
          Text(value, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
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
