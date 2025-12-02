import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'export_service.dart';
import 'ui.dart';

class ModernServerDashboard extends StatefulWidget {
  final List<Map<String, Object?>> logs;
  final VoidCallback onRefresh;

  const ModernServerDashboard({
    required this.logs,
    required this.onRefresh,
    super.key,
  });

  @override
  State<ModernServerDashboard> createState() => _ModernServerDashboardState();
}

class _ModernServerDashboardState extends State<ModernServerDashboard>
    with TickerProviderStateMixin {
  late AnimationController _animationController;
  late AnimationController _fadeController;
  String _selectedDate = '';
  List<String> _availableDates = [];
  bool _showHistory = false;
  List<Map<String, Object?>> _historyLogs = [];

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      duration: const Duration(milliseconds: 1200),
      vsync: this,
    )..forward();

    _fadeController = AnimationController(
      duration: const Duration(milliseconds: 800),
      vsync: this,
    )..forward();

    _loadAvailableDates();
  }

  @override
  void dispose() {
    _animationController.dispose();
    _fadeController.dispose();
    super.dispose();
  }

  Future<void> _loadAvailableDates() async {
    try {
      // This would call the API endpoint when implemented
      // For now, we'll leave it for future implementation
    } catch (e) {
      print('Error loading dates: $e');
    }
  }

  Future<void> _loadHistoryByDate(String tanggal) async {
    try {
      // This would call the API endpoint to fetch history for specific date
      // For now, we'll filter the current logs
      setState(() {
        _selectedDate = tanggal;
        _showHistory = true;
      });
    } catch (e) {
      print('Error loading history: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFB),
      appBar: _buildModernAppBar(),
      body: RefreshIndicator(
        onRefresh: () async => widget.onRefresh(),
        color: Colors.green.shade600,
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildWelcomeSection(),
                const SizedBox(height: 32),
                _buildStatsSection(),
                const SizedBox(height: 32),
                _buildLogsSection(),
                const SizedBox(height: 20),
              ],
            ),
          ),
        ),
      ),
    );
  }

  PreferredSizeWidget _buildModernAppBar() {
    return AppBar(
      elevation: 0,
      backgroundColor: Colors.white,
      title: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [Colors.green.shade600, Colors.green.shade400],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(12),
            ),
            child: SizedBox(
              width: 40,
              height: 40,
              child: SvgPicture.asset('assets/logo.svg'),
            ),
          ),
          const SizedBox(width: 16),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'Verifikasi Pulang',
                style: TextStyle(
                  color: Colors.black87,
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
              Text(
                'Dashboard Management',
                style: TextStyle(
                  fontSize: 11,
                  color: Colors.grey.shade600,
                  fontWeight: FontWeight.w400,
                ),
              ),
            ],
          ),
        ],
      ),
      actions: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: PopupMenuButton<String>(
            onSelected: (value) async {
              if (value == 'pdf') {
                showDialog(
                  context: context,
                  builder: (context) => ExportDateRangeDialog(
                    onExport: (startDate, endDate) async {
                      Navigator.pop(context);
                      await _exportPdf(widget.logs, startDate, endDate);
                    },
                  ),
                );
              } else if (value == 'excel') {
                showDialog(
                  context: context,
                  builder: (context) => ExportDateRangeDialog(
                    onExport: (startDate, endDate) async {
                      Navigator.pop(context);
                      await _exportExcel(widget.logs, startDate, endDate);
                    },
                  ),
                );
              }
            },
            itemBuilder: (BuildContext context) => [
              const PopupMenuItem<String>(
                value: 'pdf',
                child: Row(
                  children: [
                    Icon(Icons.picture_as_pdf, color: Colors.red, size: 20),
                    SizedBox(width: 12),
                    Text('Export to PDF'),
                  ],
                ),
              ),
              const PopupMenuItem<String>(
                value: 'excel',
                child: Row(
                  children: [
                    Icon(Icons.table_chart, color: Colors.green, size: 20),
                    SizedBox(width: 12),
                    Text('Export to Excel'),
                  ],
                ),
              ),
            ],
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            child: Container(
              margin: const EdgeInsets.all(8),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              decoration: BoxDecoration(
                color: Colors.green.shade50,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.green.shade200),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.download, color: Colors.green.shade600, size: 18),
                  const SizedBox(width: 6),
                  Text(
                    'Export',
                    style: TextStyle(
                      color: Colors.green.shade600,
                      fontWeight: FontWeight.w600,
                      fontSize: 13,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Center(
            child: IconButton(
              icon: Icon(Icons.refresh, color: Colors.green.shade600),
              onPressed: widget.onRefresh,
              tooltip: 'Refresh Data',
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildWelcomeSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        FadeTransition(
          opacity: _fadeController,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Selamat datang kembali! 👋',
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: Colors.black87,
                    ),
              ),
              const SizedBox(height: 8),
              Text(
                'Pantau status verifikasi pulang karyawan secara real-time',
                style: TextStyle(
                  color: Colors.grey.shade600,
                  fontSize: 14,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildStatsSection() {
    final totalLogs = widget.logs.length;
    final approvedByPengawas =
        widget.logs.where((log) => log['status_pengawas'] == 'ACC').length;
    final approvedBySecurity =
        widget.logs.where((log) => log['status_security'] == 'ACC').length;
    final pendingSecurity = widget.logs
        .where((log) =>
            log['status_pengawas'] == 'ACC' &&
            log['status_security'] != 'ACC')
        .length;

    final stats = [
      {
        'title': 'Total Requests',
        'value': totalLogs,
        'icon': Icons.assignment_outlined,
        'color': Colors.blue,
        'bgColor': Colors.blue.shade50,
      },
      {
        'title': 'Pengawas ACC',
        'value': approvedByPengawas,
        'icon': Icons.verified_user_outlined,
        'color': Colors.green,
        'bgColor': Colors.green.shade50,
      },
      {
        'title': 'Security ACC',
        'value': approvedBySecurity,
        'icon': Icons.security_outlined,
        'color': Colors.teal,
        'bgColor': Colors.teal.shade50,
      },
      {
        'title': 'Pending Security',
        'value': pendingSecurity,
        'icon': Icons.pending_actions_outlined,
        'color': Colors.orange,
        'bgColor': Colors.orange.shade50,
      },
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Statistik Overview',
          style: Theme.of(context).textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.bold,
                color: Colors.black87,
              ),
        ),
        const SizedBox(height: 16),
        GridView.count(
          crossAxisCount: MediaQuery.of(context).size.width > 1200 ? 4 : 2,
          crossAxisSpacing: 16,
          mainAxisSpacing: 16,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          children: List.generate(stats.length, (index) {
            final stat = stats[index];
            return ScaleTransition(
              scale: Tween<double>(begin: 0.8, end: 1.0).animate(
                CurvedAnimation(
                  parent: _animationController,
                  curve: Interval(
                    index * 0.1,
                    0.4 + (index * 0.1),
                    curve: Curves.easeOutBack,
                  ),
                ),
              ),
              child: _buildModernStatCard(
                title: stat['title'] as String,
                value: stat['value'] as int,
                icon: stat['icon'] as IconData,
                color: stat['color'] as Color,
                bgColor: stat['bgColor'] as Color,
              ),
            );
          }),
        ),
      ],
    );
  }

  Widget _buildModernStatCard({
    required String title,
    required int value,
    required IconData icon,
    required Color color,
    required Color bgColor,
  }) {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: color.withAlpha(20),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Material(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          onTap: () {},
          borderRadius: BorderRadius.circular(16),
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: bgColor,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(icon, color: color, size: 24),
                ),
                const SizedBox(height: 16),
                Text(
                  value.toString(),
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: Colors.black87,
                      ),
                ),
                const SizedBox(height: 4),
                Text(
                  title,
                  style: TextStyle(
                    color: Colors.grey.shade600,
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildLogsSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'Verification Logs',
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: Colors.black87,
                  ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.green.shade50,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.green.shade200),
              ),
              child: Text(
                '${widget.logs.length} entries',
                style: TextStyle(
                  color: Colors.green.shade600,
                  fontWeight: FontWeight.w600,
                  fontSize: 12,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        if (widget.logs.isEmpty)
          Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 48),
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
                    'No verification logs yet',
                    style: TextStyle(
                      color: Colors.grey.shade600,
                      fontSize: 16,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Logs will appear here when verifications are processed',
                    style: TextStyle(
                      color: Colors.grey.shade500,
                      fontSize: 13,
                    ),
                  ),
                ],
              ),
            ),
          )
        else
          Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              boxShadow: [
                BoxShadow(
                  color: Colors.grey.withAlpha(50),
                  blurRadius: 12,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: DataTable(
                  headingRowColor: WidgetStateProperty.all(
                    Colors.green.shade50,
                  ),
                  headingRowHeight: 60,
                  dataRowMinHeight: 56,
                  dataRowMaxHeight: 56,
                  horizontalMargin: 20,
                  columnSpacing: 32,
                  columns: [
                    DataColumn(
                      label: Text(
                        'ID Karyawan',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: Colors.green.shade700,
                          fontSize: 13,
                        ),
                      ),
                    ),
                    DataColumn(
                      label: Text(
                        'Pengawas',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: Colors.green.shade700,
                          fontSize: 13,
                        ),
                      ),
                    ),
                    DataColumn(
                      label: Text(
                        'Security',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: Colors.green.shade700,
                          fontSize: 13,
                        ),
                      ),
                    ),
                  ],
                  rows: widget.logs.map((log) {
                    final index = widget.logs.indexOf(log);
                    return DataRow(
                      color: WidgetStateProperty.all(
                        index % 2 == 0
                            ? Colors.white
                            : Colors.grey.shade50,
                      ),
                      cells: [
                        DataCell(
                          Text(
                            log['id_karyawan']?.toString() ?? '',
                            style: const TextStyle(
                              fontWeight: FontWeight.w500,
                              color: Colors.black87,
                            ),
                          ),
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
                    );
                  }).toList(),
                ),
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildStatusBadge(String status) {
    final isApproved = status == 'ACC';
    final backgroundColor = isApproved
        ? Colors.green.shade100
        : Colors.orange.shade100;
    final textColor = isApproved
        ? Colors.green.shade700
        : Colors.orange.shade700;
    final borderColor = isApproved
        ? Colors.green.shade300
        : Colors.orange.shade300;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: borderColor),
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

      if (filePath == null) return;

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

      if (filePath == null) return;

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

class DateHistoryDialog extends StatefulWidget {
  final Function(String) onDateSelected;

  const DateHistoryDialog({
    required this.onDateSelected,
    super.key,
  });

  @override
  State<DateHistoryDialog> createState() => _DateHistoryDialogState();
}

class _DateHistoryDialogState extends State<DateHistoryDialog> {
  late Future<List<String>> _datesFuture;
  String? _selectedDate;

  @override
  void initState() {
    super.initState();
    _datesFuture = _fetchAvailableDates();
  }

  Future<List<String>> _fetchAvailableDates() async {
    // Generate list of dates (last 30 days as example)
    List<String> dates = [];
    final today = DateTime.now();
    for (int i = 0; i < 30; i++) {
      final date = today.subtract(Duration(days: i));
      final formatted = '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
      dates.add(formatted);
    }
    return dates;
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Pilih Tanggal'),
      content: FutureBuilder<List<String>>(
        future: _datesFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const SizedBox(
              height: 200,
              child: Center(child: CircularProgressIndicator()),
            );
          }

          if (snapshot.hasError) {
            return Text('Error: ${snapshot.error}');
          }

          final dates = snapshot.data ?? [];

          return SingleChildScrollView(
            child: SizedBox(
              width: 300,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.green.shade50,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      'Tersedia ${dates.length} tanggal log',
                      style: TextStyle(
                        color: Colors.green.shade700,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    height: 300,
                    child: ListView.builder(
                      itemCount: dates.length,
                      itemBuilder: (context, index) {
                        final date = dates[index];
                        final isSelected = _selectedDate == date;
                        return Container(
                          margin: const EdgeInsets.symmetric(vertical: 4),
                          decoration: BoxDecoration(
                            color: isSelected ? Colors.green.shade100 : Colors.white,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                              color: isSelected ? Colors.green.shade600 : Colors.grey.shade300,
                            ),
                          ),
                          child: ListTile(
                            title: Text(date),
                            trailing: isSelected
                                ? Icon(Icons.check, color: Colors.green.shade600)
                                : null,
                            onTap: () {
                              setState(() => _selectedDate = date);
                            },
                          ),
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Batal'),
        ),
        ElevatedButton(
          onPressed: _selectedDate == null
              ? null
              : () {
                  widget.onDateSelected(_selectedDate!);
                },
          child: const Text('Lihat Log'),
        ),
      ],
    );
  }
}
