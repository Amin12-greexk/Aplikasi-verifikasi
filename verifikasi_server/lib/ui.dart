import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'export_service.dart';

class GreenTheme {
  static ThemeData getTheme() {
    return ThemeData(
      useMaterial3: true,
      colorScheme: ColorScheme.fromSeed(
        seedColor: Colors.green.shade600,
        brightness: Brightness.light,
      ),
      scaffoldBackgroundColor: Colors.grey.shade50,
      appBarTheme: AppBarTheme(
        backgroundColor: Colors.green.shade600,
        elevation: 4,
        shadowColor: Colors.green.shade900.withAlpha(50),
        centerTitle: false,
        titleTextStyle: const TextStyle(
          color: Colors.white,
          fontSize: 20,
          fontWeight: FontWeight.bold,
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.green.shade600,
          foregroundColor: Colors.white,
          elevation: 2,
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          textStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
        ),
      ),
      cardTheme: CardThemeData(
        elevation: 2,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        color: Colors.white,
      ),
    );
  }
}

class ServerDashboard extends StatefulWidget {
  final List<Map<String, Object?>> logs;
  final VoidCallback onRefresh;

  const ServerDashboard({
    required this.logs,
    required this.onRefresh,
    super.key,
  });

  @override
  State<ServerDashboard> createState() => _ServerDashboardState();
}

class _ServerDashboardState extends State<ServerDashboard> {
  late PageController _pageController;
  DateTime? _selectedStartDate;
  DateTime? _selectedEndDate;

  @override
  void initState() {
    super.initState();
    _pageController = PageController();
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            SizedBox(
              width: 40,
              height: 40,
              child: SvgPicture.asset('assets/logo.svg'),
            ),
            const SizedBox(width: 12),
            const Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('Verifikasi Pulang'),
                SizedBox(height: 2),
                Text(
                  'Server Dashboard',
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.normal),
                ),
              ],
            ),
          ],
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.all(8),
            child: PopupMenuButton<String>(
              onSelected: (value) async {
                if (value == 'pdf') {
                  await _showDatePickerAndExport(widget.logs, 'pdf');
                } else if (value == 'excel') {
                  await _showDatePickerAndExport(widget.logs, 'excel');
                }
              },
              itemBuilder: (BuildContext context) => [
                const PopupMenuItem<String>(
                  value: 'pdf',
                  child: Row(
                    children: [
                      Icon(Icons.picture_as_pdf, color: Colors.red),
                      SizedBox(width: 8),
                      Text('Export to PDF'),
                    ],
                  ),
                ),
                const PopupMenuItem<String>(
                  value: 'excel',
                  child: Row(
                    children: [
                      Icon(Icons.table_chart, color: Colors.green),
                      SizedBox(width: 8),
                      Text('Export to Excel'),
                    ],
                  ),
                ),
              ],
              child: Tooltip(
                message: 'Export Data',
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.download, color: Colors.green.shade600),
                      const SizedBox(width: 4),
                      Text(
                        'Export',
                        style: TextStyle(color: Colors.green.shade600),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: ElevatedButton.icon(
              onPressed: widget.onRefresh,
              icon: const Icon(Icons.refresh),
              label: const Text('Refresh'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.white,
                foregroundColor: Colors.green.shade600,
              ),
            ),
          ),
        ],
      ),
      body: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildStatsCards(),
              const SizedBox(height: 24),
              _buildLogsSection(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStatsCards() {
    final totalLogs = widget.logs.length;
    final approvedByPengawas = widget.logs
        .where((log) => log['status_pengawas'] == 'ACC')
        .length;
    final approvedBySecurity = widget.logs
        .where((log) => log['status_security'] == 'ACC')
        .length;
    final pendingSecurity = widget.logs
        .where((log) => log['status_pengawas'] == 'ACC' && log['status_security'] != 'ACC')
        .length;

    return GridView.count(
      crossAxisCount: MediaQuery.of(context).size.width > 800 ? 4 : 2,
      crossAxisSpacing: 16,
      mainAxisSpacing: 16,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      children: [
        _buildStatCard(
          title: 'Total Requests',
          value: totalLogs.toString(),
          icon: Icons.assignment,
          color: Colors.blue.shade600,
        ),
        _buildStatCard(
          title: 'Pengawas ACC',
          value: approvedByPengawas.toString(),
          icon: Icons.verified_user,
          color: Colors.green.shade600,
        ),
        _buildStatCard(
          title: 'Security ACC',
          value: approvedBySecurity.toString(),
          icon: Icons.security,
          color: Colors.teal.shade600,
        ),
        _buildStatCard(
          title: 'Pending Security',
          value: pendingSecurity.toString(),
          icon: Icons.pending_actions,
          color: Colors.orange.shade600,
        ),
      ],
    );
  }

  Widget _buildStatCard({
    required String title,
    required String value,
    required IconData icon,
    required Color color,
  }) {
    return Card(
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          gradient: LinearGradient(
            colors: [color.withAlpha(200), color.withAlpha(150)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 32, color: Colors.white),
            const SizedBox(height: 12),
            Text(
              value,
              style: const TextStyle(
                fontSize: 28,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              title,
              style: const TextStyle(
                fontSize: 12,
                color: Colors.white70,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLogsSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Verification Logs',
          style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                color: Colors.green.shade700,
                fontWeight: FontWeight.bold,
              ),
        ),
        const SizedBox(height: 12),
        if (widget.logs.isEmpty)
          Center(
            child: Padding(
              padding: const EdgeInsets.all(32),
              child: Column(
                children: [
                  Icon(Icons.inbox, size: 48, color: Colors.grey.shade300),
                  const SizedBox(height: 12),
                  Text(
                    'No verification logs yet',
                    style: TextStyle(color: Colors.grey.shade600),
                  ),
                ],
              ),
            ),
          )
        else
          Card(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: DataTable(
                headingRowColor: WidgetStateProperty.all(Colors.green.shade50),
                headingRowHeight: 56,
                dataRowMinHeight: 56,
                dataRowMaxHeight: 56,
                columns: [
                  DataColumn(
                    label: Text(
                      'ID Karyawan',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: Colors.green.shade700,
                      ),
                    ),
                  ),
                  DataColumn(
                    label: Text(
                      'Pengawas Status',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: Colors.green.shade700,
                      ),
                    ),
                  ),
                  DataColumn(
                    label: Text(
                      'Security Status',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: Colors.green.shade700,
                      ),
                    ),
                  ),
                ],
                rows: widget.logs
                    .map((log) => DataRow(
                          color: WidgetStateProperty.all(
                            (widget.logs.indexOf(log) % 2 == 0)
                                ? Colors.white
                                : Colors.green.shade50,
                          ),
                          cells: [
                            DataCell(
                              Text(log['id_karyawan']?.toString() ?? ''),
                            ),
                            DataCell(
                              _buildStatusBadge(
                                log['status_pengawas']?.toString() ?? 'PENDING',
                              ),
                            ),
                            DataCell(
                              _buildStatusBadge(
                                log['status_security']?.toString() ?? 'PENDING',
                              ),
                            ),
                          ],
                        ))
                    .toList(),
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildStatusBadge(String status) {
    final isApproved = status == 'ACC';
    final color = isApproved ? Colors.green : Colors.orange;
    final textColor = isApproved ? Colors.green.shade900 : Colors.orange.shade900;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: color.withAlpha(100),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color),
      ),
      child: Text(
        status,
        style: TextStyle(
          color: textColor,
          fontWeight: FontWeight.w600,
          fontSize: 12,
        ),
      ),
    );
  }

  Future<void> _showDatePickerAndExport(
    List<Map<String, Object?>> logs,
    String exportType,
  ) async {
    showDialog(
      context: context,
      builder: (context) => ExportDateRangeDialog(
        onExport: (startDate, endDate) async {
          Navigator.pop(context);
          if (exportType == 'pdf') {
            await _exportPdf(logs, startDate, endDate);
          } else {
            await _exportExcel(logs, startDate, endDate);
          }
        },
      ),
    );
  }

  Future<void> _exportPdf(
    List<Map<String, Object?>> logs,
    DateTime? startDate,
    DateTime? endDate,
  ) async {
    try {
      final filePath = await ExportService.exportToPdf(
        logs,
        'Laporan Ijin Pulang',
        startDate: startDate,
        endDate: endDate,
      );
      if (!mounted) return;

      if (filePath == null) {
        // User cancelled
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('PDF saved: $filePath'),
          duration: const Duration(seconds: 3),
          backgroundColor: Colors.green.shade600,
          action: SnackBarAction(
            label: 'Open',
            onPressed: () {
              Process.run('explorer', ['/select,', filePath]);
            },
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error: $e'),
          backgroundColor: Colors.red.shade600,
        ),
      );
    }
  }

  Future<void> _exportExcel(
    List<Map<String, Object?>> logs,
    DateTime? startDate,
    DateTime? endDate,
  ) async {
    try {
      final filePath = await ExportService.exportToExcel(
        logs,
        'Laporan Ijin Pulang',
        startDate: startDate,
        endDate: endDate,
      );
      if (!mounted) return;

      if (filePath == null) {
        // User cancelled
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Excel saved: $filePath'),
          duration: const Duration(seconds: 3),
          backgroundColor: Colors.green.shade600,
          action: SnackBarAction(
            label: 'Open',
            onPressed: () {
              Process.run('explorer', ['/select,', filePath]);
            },
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error: $e'),
          backgroundColor: Colors.red.shade600,
        ),
      );
    }
  }
}

class ExportDateRangeDialog extends StatefulWidget {
  final Function(DateTime?, DateTime?) onExport;

  const ExportDateRangeDialog({
    required this.onExport,
    super.key,
  });

  @override
  State<ExportDateRangeDialog> createState() => _ExportDateRangeDialogState();
}

class _ExportDateRangeDialogState extends State<ExportDateRangeDialog> {
  DateTime? _startDate;
  DateTime? _endDate;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Filter Tanggal Export'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Pilih rentang tanggal (opsional):',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 16),
            // Start Date Picker
            Text(
              'Tanggal Mulai:',
              style: Theme.of(context).textTheme.labelMedium,
            ),
            const SizedBox(height: 8),
            Container(
              decoration: BoxDecoration(
                border: Border.all(color: Colors.green.shade300),
                borderRadius: BorderRadius.circular(8),
              ),
              child: ListTile(
                title: Text(
                  _startDate == null
                      ? 'Belum dipilih'
                      : 'dd/MM/yyyy'.replaceAll('dd', '${_startDate!.day.toString().padLeft(2, '0')}')
                          .replaceAll('MM', '${_startDate!.month.toString().padLeft(2, '0')}')
                          .replaceAll('yyyy', '${_startDate!.year}'),
                ),
                trailing: Icon(Icons.calendar_today, color: Colors.green.shade600),
                onTap: () async {
                  final picked = await showDatePicker(
                    context: context,
                    initialDate: _startDate ?? DateTime.now(),
                    firstDate: DateTime(2020),
                    lastDate: DateTime.now(),
                  );
                  if (picked != null) {
                    setState(() => _startDate = picked);
                  }
                },
              ),
            ),
            const SizedBox(height: 16),
            // End Date Picker
            Text(
              'Tanggal Akhir:',
              style: Theme.of(context).textTheme.labelMedium,
            ),
            const SizedBox(height: 8),
            Container(
              decoration: BoxDecoration(
                border: Border.all(color: Colors.green.shade300),
                borderRadius: BorderRadius.circular(8),
              ),
              child: ListTile(
                title: Text(
                  _endDate == null
                      ? 'Belum dipilih'
                      : 'dd/MM/yyyy'.replaceAll('dd', '${_endDate!.day.toString().padLeft(2, '0')}')
                          .replaceAll('MM', '${_endDate!.month.toString().padLeft(2, '0')}')
                          .replaceAll('yyyy', '${_endDate!.year}'),
                ),
                trailing: Icon(Icons.calendar_today, color: Colors.green.shade600),
                onTap: () async {
                  final picked = await showDatePicker(
                    context: context,
                    initialDate: _endDate ?? DateTime.now(),
                    firstDate: DateTime(2020),
                    lastDate: DateTime.now(),
                  );
                  if (picked != null) {
                    setState(() => _endDate = picked);
                  }
                },
              ),
            ),
            const SizedBox(height: 8),
            if (_startDate != null && _endDate != null && _startDate!.isAfter(_endDate!))
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.orange.shade50,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  'Tanggal mulai tidak boleh lebih besar dari tanggal akhir',
                  style: TextStyle(
                    color: Colors.orange.shade900,
                    fontSize: 12,
                  ),
                ),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Batal'),
        ),
        ElevatedButton(
          onPressed: () {
            if (_startDate != null && _endDate != null && _startDate!.isAfter(_endDate!)) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Tanggal mulai tidak boleh lebih besar dari tanggal akhir'),
                  backgroundColor: Colors.red,
                ),
              );
              return;
            }
            widget.onExport(_startDate, _endDate);
          },
          child: const Text('Export'),
        ),
      ],
    );
  }
}
