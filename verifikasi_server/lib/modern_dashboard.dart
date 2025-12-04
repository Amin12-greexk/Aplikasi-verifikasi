import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
// Pastikan import ini sesuai dengan struktur project Anda
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
  final ScrollController _scrollController = ScrollController();

  // Warna Tema (Palette)
  static const Color primaryColor = Color(0xFF059669); // Emerald 600
  static const Color secondaryColor = Color(0xFF10B981); // Emerald 500
  static const Color bgColor = Color(0xFFF3F4F6); // Cool Gray 100
  static const Color surfaceColor = Colors.white;

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      duration: const Duration(milliseconds: 1000),
      vsync: this,
    )..forward();
  }

  @override
  void dispose() {
    _animationController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: bgColor,
      appBar: _buildTransparentAppBar(),
      body: RefreshIndicator(
        onRefresh: () async => widget.onRefresh(),
        color: primaryColor,
        child: CustomScrollView(
          controller: _scrollController,
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 10, 20, 20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildHeaderSection(),
                    const SizedBox(height: 24),
                    _buildStatsGrid(),
                    const SizedBox(height: 32),
                    _buildSectionTitle('Aktivitas Terkini', widget.logs.length),
                    const SizedBox(height: 16),
                  ],
                ),
              ),
            ),
            _buildLogListSliver(),
            const SliverPadding(padding: EdgeInsets.only(bottom: 40)),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: widget.onRefresh,
        backgroundColor: primaryColor,
        icon: const Icon(Icons.refresh, color: Colors.white),
        label: const Text('Refresh', style: TextStyle(color: Colors.white)),
      ),
    );
  }

  PreferredSizeWidget _buildTransparentAppBar() {
    return AppBar(
      backgroundColor: Colors.transparent,
      elevation: 0,
      centerTitle: false,
      title: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.05),
                  blurRadius: 10,
                  offset: const Offset(0, 4),
                )
              ],
            ),
            child: SvgPicture.asset(
              'assets/logo.svg',
              height: 24,
              width: 24,
              // Fallback icon jika aset tidak ada (untuk testing)
              placeholderBuilder: (_) => const Icon(Icons.dashboard, color: primaryColor),
            ),
          ),
          const SizedBox(width: 12),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Verifikasi Pulang',
                style: TextStyle(
                  color: Colors.black87,
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                ),
              ),
              Text(
                'Admin Panel',
                style: TextStyle(
                  color: Colors.grey.shade500,
                  fontSize: 12,
                ),
              ),
            ],
          ),
        ],
      ),
      actions: [
        _buildExportButton(),
        const SizedBox(width: 16),
      ],
    );
  }

  Widget _buildExportButton() {
    return PopupMenuButton<String>(
      offset: const Offset(0, 50),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        margin: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: Colors.grey.shade200),
        ),
        child: Row(
          children: [
            Icon(Icons.download_rounded, size: 18, color: Colors.grey.shade700),
            const SizedBox(width: 8),
            Text(
              "Export",
              style: TextStyle(
                color: Colors.grey.shade700,
                fontWeight: FontWeight.w600,
                fontSize: 13,
              ),
            ),
          ],
        ),
      ),
      onSelected: (value) => _handleExport(value),
      itemBuilder: (context) => [
        _buildPopupItem('pdf', 'Export to PDF', Icons.picture_as_pdf, Colors.red),
        _buildPopupItem('excel', 'Export to Excel', Icons.table_chart, Colors.green),
      ],
    );
  }

  PopupMenuItem<String> _buildPopupItem(String value, String text, IconData icon, Color color) {
    return PopupMenuItem(
      value: value,
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: color.withOpacity(0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, color: color, size: 20),
          ),
          const SizedBox(width: 12),
          Text(text, style: const TextStyle(fontWeight: FontWeight.w500)),
        ],
      ),
    );
  }

  Widget _buildHeaderSection() {
    return FadeTransition(
      opacity: _animationController,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Overview Hari Ini',
            style: TextStyle(
              fontSize: 28,
              fontWeight: FontWeight.bold,
              color: Colors.grey.shade900,
              letterSpacing: -0.5,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Pantau status persetujuan karyawan secara real-time.',
            style: TextStyle(
              fontSize: 15,
              color: Colors.grey.shade600,
              height: 1.5,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatsGrid() {
    final total = widget.logs.length;
    final accPengawas = widget.logs.where((l) => l['status_pengawas'] == 'ACC').length;
    final accSecurity = widget.logs.where((l) => l['status_security'] == 'ACC').length;
    final pending = total - accSecurity; // Simple logic adjustment

    return LayoutBuilder(builder: (context, constraints) {
      // Responsive Grid
      final int crossAxisCount = constraints.maxWidth > 600 ? 4 : 2;
      
      return GridView.count(
        crossAxisCount: crossAxisCount,
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        crossAxisSpacing: 16,
        mainAxisSpacing: 16,
        childAspectRatio: 1.4,
        children: [
          _buildStatCard('Total Request', total, Icons.folder_open, Colors.blue),
          _buildStatCard('ACC Pengawas', accPengawas, Icons.person_outline, Colors.orange),
          _buildStatCard('ACC Security', accSecurity, Icons.shield_outlined, primaryColor),
          _buildStatCard('Pending', pending, Icons.hourglass_empty, Colors.redAccent),
        ],
      );
    });
  }

  Widget _buildStatCard(String title, int value, IconData icon, Color color) {
    return Container(
      decoration: BoxDecoration(
        color: surfaceColor,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: color.withOpacity(0.08),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: color.withOpacity(0.1),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, color: color, size: 20),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  value.toString(),
                  style: TextStyle(
                    fontSize: 26,
                    fontWeight: FontWeight.bold,
                    color: Colors.grey.shade800,
                  ),
                ),
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 13,
                    color: Colors.grey.shade500,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSectionTitle(String title, int count) {
    return Row(
      children: [
        Text(
          title,
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            color: Colors.grey.shade800,
          ),
        ),
        const SizedBox(width: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(
            color: primaryColor.withOpacity(0.1),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Text(
            '$count Data',
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.bold,
              color: primaryColor,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildLogListSliver() {
    if (widget.logs.isEmpty) {
      return SliverToBoxAdapter(child: _buildEmptyState());
    }

    return SliverList(
      delegate: SliverChildBuilderDelegate(
        (context, index) {
          final log = widget.logs[index];
          return _buildModernLogCard(log, index);
        },
        childCount: widget.logs.length,
      ),
    );
  }

  Widget _buildModernLogCard(Map<String, Object?> log, int index) {
    // Animasi muncul berurutan
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: Duration(milliseconds: 400 + (index * 50).clamp(0, 1000)),
      curve: Curves.easeOutQuart,
      builder: (context, value, child) {
        return Transform.translate(
          offset: Offset(0, 50 * (1 - value)),
          child: Opacity(opacity: value, child: child),
        );
      },
      child: Container(
        margin: const EdgeInsets.fromLTRB(20, 0, 20, 16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.grey.shade100),
          boxShadow: [
            BoxShadow(
              color: Colors.grey.shade200.withOpacity(0.5),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              // Avatar / Icon ID
              Container(
                width: 50,
                height: 50,
                decoration: BoxDecoration(
                  color: Colors.blueGrey.shade50,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Center(
                  child: Text(
                    _getInitials(log['id_karyawan']),
                    style: TextStyle(
                      color: Colors.blueGrey.shade700,
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 16),
              // Info Utama
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'ID: ${log['id_karyawan'] ?? '-'}',
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                        color: Colors.black87,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Permintaan Verifikasi', // Bisa diganti timestamp jika ada
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey.shade500,
                      ),
                    ),
                  ],
                ),
              ),
              // Status Pills
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  _buildStatusPill('Pengawas', log['status_pengawas']?.toString() ?? '-'),
                  const SizedBox(height: 8),
                  _buildStatusPill('Security', log['status_security']?.toString() ?? '-'),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStatusPill(String label, String status) {
    final isAcc = status == 'ACC';
    final color = isAcc ? const Color(0xFF10B981) : const Color(0xFFF59E0B);
    final bgColor = isAcc ? const Color(0xFFECFDF5) : const Color(0xFFFFFBEB);
    final icon = isAcc ? Icons.check_circle_rounded : Icons.pending_rounded;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          label,
          style: TextStyle(fontSize: 11, color: Colors.grey.shade400, fontWeight: FontWeight.w500),
        ),
        const SizedBox(width: 6),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: bgColor,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: color.withOpacity(0.3)),
          ),
          child: Row(
            children: [
              Icon(icon, size: 12, color: color),
              const SizedBox(width: 4),
              Text(
                isAcc ? 'Approved' : 'Pending',
                style: TextStyle(
                  color: color,
                  fontWeight: FontWeight.w700,
                  fontSize: 10,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildEmptyState() {
    return Padding(
      padding: const EdgeInsets.all(40.0),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: Colors.grey.shade100,
              shape: BoxShape.circle,
            ),
            child: Icon(Icons.inbox_rounded, size: 60, color: Colors.grey.shade300),
          ),
          const SizedBox(height: 16),
          Text(
            'Belum ada data',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: Colors.grey.shade400,
            ),
          ),
        ],
      ),
    );
  }

  String _getInitials(Object? id) {
    String s = id?.toString() ?? '?';
    if (s.length > 2) return s.substring(s.length - 2);
    return s;
  }

  // --- Logic Export (Sama seperti sebelumnya) ---
  void _handleExport(String value) {
    showDialog(
      context: context,
      builder: (context) => ExportDateRangeDialog(
        onExport: (startDate, endDate) async {
          Navigator.pop(context);
          if (value == 'pdf') {
            await _exportPdf(widget.logs, startDate, endDate);
          } else {
            await _exportExcel(widget.logs, startDate, endDate);
          }
        },
      ),
    );
  }

  Future<void> _exportPdf(List<Map<String, Object?>> logs, DateTime? startDate, DateTime? endDate) async {
    // Implementasi sama, panggil ExportService
    // ... Gunakan kode yang ada di widget sebelumnya
    try {
      final filePath = await ExportService.exportToPdf(logs, 'Laporan Ijin Pulang', startDate: startDate, endDate: endDate);
      if(!mounted || filePath == null) return;
      _showSuccessSnack('PDF disimpan: $filePath', filePath);
    } catch (e) {
      _showErrorSnack(e.toString());
    }
  }

  Future<void> _exportExcel(List<Map<String, Object?>> logs, DateTime? startDate, DateTime? endDate) async {
     try {
      final filePath = await ExportService.exportToExcel(logs, 'Laporan Ijin Pulang', startDate: startDate, endDate: endDate);
      if(!mounted || filePath == null) return;
      _showSuccessSnack('Excel disimpan: $filePath', filePath);
    } catch (e) {
      _showErrorSnack(e.toString());
    }
  }

  void _showSuccessSnack(String msg, String path) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: primaryColor,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        action: SnackBarAction(
          label: 'BUKA',
          textColor: Colors.white,
          onPressed: () => Process.run('explorer', ['/select,', path]),
        ),
      ),
    );
  }

  void _showErrorSnack(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), backgroundColor: Colors.red),
    );
  }
}

// Pastikan class DateHistoryDialog dan ExportDateRangeDialog tetap ada 
// jika belum ada di file lain (ui.dart).