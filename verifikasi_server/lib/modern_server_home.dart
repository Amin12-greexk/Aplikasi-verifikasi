import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:sqlite3/sqlite3.dart' hide Row;
import 'user_management.dart';
import 'room_management.dart';
import 'export_service.dart';

class ModernServerHome extends StatefulWidget {
  final Database db;

  const ModernServerHome({required this.db, super.key});

  @override
  State<ModernServerHome> createState() => _ModernServerHomeState();
}

class _ModernServerHomeState extends State<ModernServerHome> {
  String? _viewingDate;
  int _selectedTabIndex = 0; // 0: Live, 1: History
  bool _showToiletLogs = false;
  late final Timer _refreshTimer;

  // Warna Tema
  static const Color primaryColor = Color(0xFF059669); // Emerald 600
  static const Color bgColor = Color(0xFFF3F4F6); // Cool Gray 100
  static const Color surfaceColor = Colors.white;

  @override
  void initState() {
    super.initState();
    // Auto-refresh setiap 2 detik untuk data realtime
    _refreshTimer = Timer.periodic(const Duration(seconds: 2), (_) {
      if (mounted) {
        setState(() {});
      }
    });
  }

  @override
  void dispose() {
    _refreshTimer.cancel();
    super.dispose();
  }

  // --- Logic Data ---

  List<Map<String, Object?>> _getLogs() {
    // Logic: Jika Tab History (1) & ada tanggal dipilih, ambil dari history
    // Jika Tab Live (0), ambil dari log_pulang (realtime)
    if (_selectedTabIndex == 1 && _viewingDate != null) {
      if (_showToiletLogs) {
        return widget.db
            .select(
              'SELECT * FROM toilet_permit_history WHERE tanggal = ? ORDER BY rowid DESC',
              [_viewingDate!],
            )
            .map((r) => Map<String, Object?>.from(r))
            .toList();
      }
      return widget.db
          .select(
            'SELECT * FROM log_pulang_history WHERE tanggal = ? ORDER BY rowid DESC',
            [_viewingDate!],
          )
          .map((r) => Map<String, Object?>.from(r))
          .toList();
    }

    if (_showToiletLogs) {
      return widget.db
          .select('SELECT * FROM toilet_permit ORDER BY rowid DESC')
          .map((r) => Map<String, Object?>.from(r))
          .toList();
    }

    return widget.db
        .select('SELECT * FROM log_pulang ORDER BY rowid DESC')
        .map((r) => Map<String, Object?>.from(r))
        .toList();
  }

  int _getStatusCount(String status, String statusField) {
    final logs = _getLogs();
    return logs.where((log) => log[statusField] == status).length;
  }

  void _handleTabChange(int index) {
    setState(() {
      _selectedTabIndex = index;
    });

    if (index == 0) {
      // Reset ke Live
      _viewingDate = null;
    } else if (index == 1 && _viewingDate == null) {
      // Jika pindah ke history tapi belum pilih tanggal, buka picker
      _showHistoryPicker();
    }
  }

  void _showHistoryPicker() {
    showDialog(
      context: context,
      builder: (context) => _DateHistoryPickerDialog(
        db: widget.db,
        showToiletLogs: _showToiletLogs,
        onDateSelected: (date) {
          setState(() {
            _viewingDate = date;
            _selectedTabIndex = 1; // Paksa pindah ke tab history
          });
          Navigator.pop(context);
        },
        onReset: () {
          setState(() {
            _viewingDate = null;
            _selectedTabIndex = 0; // Kembali ke Live
          });
          Navigator.pop(context);
        },
      ),
    );
  }

  void _showClearLogsDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Clear Logs'),
        content: const Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Pilih tindakan:',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            SizedBox(height: 8),
            Text(
              '• Clear Logs Only: Hapus log hari ini, history tetap tersimpan untuk export',
              style: TextStyle(fontSize: 13),
            ),
            SizedBox(height: 8),
            Text(
              '• Clear All: Hapus semua log dan history (tidak bisa dipulihkan)',
              style: TextStyle(fontSize: 13, color: Colors.red),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () async {
              Navigator.pop(context);
              await _clearLogs();
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.amber.shade600,
            ),
            child: const Text('Clear Logs Only'),
          ),
          ElevatedButton(
            onPressed: () async {
              Navigator.pop(context);
              await _clearAllData();
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red.shade600,
            ),
            child: const Text('Clear All'),
          ),
        ],
      ),
    );
  }

  Future<void> _clearLogs() async {
    try {
      final response = await http.post(
        Uri.parse('http://localhost:8080/admin/clear-logs'),
      );

      if (response.statusCode == 200) {
        setState(() {
          // Refresh data
        });
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: const Text(
                'Log berhasil dihapus - History tetap tersimpan',
              ),
              backgroundColor: Colors.green.shade600,
              duration: const Duration(seconds: 3),
            ),
          );
        }
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Error: ${response.body}'),
              backgroundColor: Colors.red.shade600,
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Connection error: ${e.toString()}'),
            backgroundColor: Colors.red.shade600,
          ),
        );
      }
    }
  }

  Future<void> _clearAllData() async {
    // Show confirmation dialog
    if (!mounted) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Konfirmasi Hapus Semua Data'),
        content: const Text(
          'Anda yakin ingin menghapus SEMUA log dan history?\n\nTindakan ini tidak bisa dipulihkan!',
          style: TextStyle(color: Colors.red),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red.shade600,
            ),
            child: const Text('Ya, Hapus Semua'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    try {
      final response = await http.post(
        Uri.parse('http://localhost:8080/admin/clear-all-data'),
      );

      if (response.statusCode == 200) {
        setState(() {
          // Refresh data
        });
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: const Text('Semua log dan history berhasil dihapus'),
              backgroundColor: Colors.orange.shade600,
              duration: const Duration(seconds: 3),
            ),
          );
        }
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Error: ${response.body}'),
              backgroundColor: Colors.red.shade600,
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Connection error: ${e.toString()}'),
            backgroundColor: Colors.red.shade600,
          ),
        );
      }
    }
  }

  // --- UI Build ---

  @override
  Widget build(BuildContext context) {
    final logs = _getLogs();
    final totalLogs = logs.length;
    final pengawasACC = _showToiletLogs
        ? logs.where((e) => e['proof_status'] == 'SCANNED').length
        : _getStatusCount('ACC', 'status_pengawas');
    final securityACC = _showToiletLogs
        ? logs.where((e) => e['permit_state'] == 'EXPIRED').length
        : _getStatusCount('ACC', 'status_security');

    return Scaffold(
      backgroundColor: bgColor,
      body: SafeArea(
        child: Column(
          children: [
            _buildHeader(context),
            Expanded(
              child: CustomScrollView(
                physics: const BouncingScrollPhysics(),
                slivers: [
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.all(20),
                      child: Column(
                        children: [
                          _buildStatsSection(
                            totalLogs,
                            pengawasACC,
                            securityACC,
                          ),
                          const SizedBox(height: 24),
                          _buildTabNavigation(),
                          if (_selectedTabIndex == 1 &&
                              _viewingDate != null) ...[
                            const SizedBox(height: 12),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 6,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.blue.shade50,
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(color: Colors.blue.shade200),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    Icons.calendar_today,
                                    size: 14,
                                    color: Colors.blue.shade700,
                                  ),
                                  const SizedBox(width: 8),
                                  Text(
                                    'Arsip ${_showToiletLogs ? "Toilet" : "Pulang"}: $_viewingDate',
                                    style: TextStyle(
                                      color: Colors.blue.shade700,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                  _buildContentSliver(logs),
                  const SliverPadding(padding: EdgeInsets.only(bottom: 20)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      decoration: BoxDecoration(
        color: surfaceColor,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: primaryColor.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(
                  Icons.dns_rounded,
                  color: primaryColor,
                  size: 24,
                ),
              ),
              const SizedBox(width: 12),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Server Home',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: Colors.black87,
                    ),
                  ),
                  Text(
                    'Verifikasi Pulang',
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.grey.shade500,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ],
          ),
          Row(
            children: [
              // Refresh button
              IconButton(
                onPressed: () {
                  setState(() {});
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: const Text('Data refreshed'),
                      backgroundColor: Colors.green.shade600,
                      duration: const Duration(seconds: 2),
                    ),
                  );
                },
                icon: Icon(Icons.refresh_rounded, color: Colors.grey.shade600),
                tooltip: 'Refresh data',
              ),
              const SizedBox(width: 8),
              PopupMenuButton(
                offset: const Offset(0, 50),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                icon: CircleAvatar(
                  backgroundColor: Colors.grey.shade100,
                  child: Icon(Icons.more_vert, color: Colors.grey.shade600),
                ),
                itemBuilder: (context) => [
                  PopupMenuItem(
                    onTap: () async {
                      await Future.delayed(Duration.zero);
                      if (!mounted) return;
                      final logs = _getLogs();
                      try {
                        final result = await ExportService.exportToPdf(
                          logs,
                          'Laporan Ijin Pulang',
                        );
                        if (result != null && mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: const Text('PDF exported successfully'),
                              backgroundColor: Colors.green.shade600,
                            ),
                          );
                        }
                      } catch (e) {
                        if (mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text('Error: ${e.toString()}'),
                              backgroundColor: Colors.red.shade600,
                            ),
                          );
                        }
                      }
                    },
                    child: Row(
                      children: [
                        Icon(
                          Icons.picture_as_pdf_rounded,
                          color: Colors.red.shade600,
                          size: 20,
                        ),
                        const SizedBox(width: 12),
                        const Text('Export PDF'),
                      ],
                    ),
                  ),
                  PopupMenuItem(
                    onTap: () async {
                      await Future.delayed(Duration.zero);
                      if (!mounted) return;
                      final logs = _getLogs();
                      try {
                        final result = await ExportService.exportToExcel(
                          logs,
                          'Laporan Ijin Pulang',
                        );
                        if (result != null && mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: const Text(
                                'Excel exported successfully',
                              ),
                              backgroundColor: Colors.green.shade600,
                            ),
                          );
                        }
                      } catch (e) {
                        if (mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text('Error: ${e.toString()}'),
                              backgroundColor: Colors.red.shade600,
                            ),
                          );
                        }
                      }
                    },
                    child: Row(
                      children: [
                        Icon(
                          Icons.table_chart_rounded,
                          color: Colors.green.shade600,
                          size: 20,
                        ),
                        const SizedBox(width: 12),
                        const Text('Export Excel'),
                      ],
                    ),
                  ),
                  PopupMenuItem(
                    onTap: () async {
                      await Future.delayed(Duration.zero);
                      if (!mounted) return;
                      setState(() {
                        _showToiletLogs = !_showToiletLogs;
                        _selectedTabIndex = 0;
                        _viewingDate = null;
                      });
                    },
                    child: Row(
                      children: [
                        Icon(
                          Icons.swap_horiz,
                          color: Colors.purple.shade600,
                          size: 20,
                        ),
                        const SizedBox(width: 12),
                        Text(
                          _showToiletLogs
                              ? 'Lihat Log Pulang'
                              : 'Lihat Log Toilet',
                        ),
                      ],
                    ),
                  ),
                  PopupMenuItem(
                    onTap: () async {
                      await Future.delayed(Duration.zero);
                      if (!mounted) return;
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) =>
                              RoomManagementPage(db: widget.db),
                        ),
                      );
                    },
                    child: Row(
                      children: [
                        Icon(
                          Icons.meeting_room_outlined,
                          color: Colors.blue.shade700,
                          size: 20,
                        ),
                        const SizedBox(width: 12),
                        const Text('Room Management'),
                      ],
                    ),
                  ),
                  PopupMenuItem(
                    onTap: () async {
                      await Future.delayed(Duration.zero);
                      if (!mounted) return;
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) =>
                              UserManagementPage(db: widget.db),
                        ),
                      );
                    },
                    child: Row(
                      children: [
                        Icon(
                          Icons.people_outline,
                          color: Colors.grey.shade700,
                          size: 20,
                        ),
                        const SizedBox(width: 12),
                        const Text('User Management'),
                      ],
                    ),
                  ),
                  PopupMenuItem(
                    onTap: () async {
                      await Future.delayed(Duration.zero);
                      if (!mounted) return;
                      _showClearLogsDialog();
                    },
                    child: Row(
                      children: [
                        Icon(
                          Icons.delete_sweep_rounded,
                          color: Colors.amber.shade600,
                          size: 20,
                        ),
                        const SizedBox(width: 12),
                        Text(
                          'Clear Logs',
                          style: TextStyle(color: Colors.amber.shade600),
                        ),
                      ],
                    ),
                  ),
                  PopupMenuItem(
                    onTap: () => Navigator.pop(context), // Logout logic
                    child: Row(
                      children: [
                        Icon(
                          Icons.logout_rounded,
                          color: Colors.red.shade400,
                          size: 20,
                        ),
                        const SizedBox(width: 12),
                        Text(
                          'Logout',
                          style: TextStyle(color: Colors.red.shade400),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildStatsSection(int total, int pengawasACC, int securityACC) {
    return Row(
      children: [
        _buildStatCard(
          'Total Log',
          total.toString(),
          Icons.folder_open_rounded,
          Colors.blue,
        ),
        const SizedBox(width: 12),
        _buildStatCard(
          _showToiletLogs ? 'Sudah Scan' : 'Pengawas',
          pengawasACC.toString(),
          Icons.admin_panel_settings_outlined,
          Colors.orange,
        ),
        const SizedBox(width: 12),
        _buildStatCard(
          _showToiletLogs ? 'Expired' : 'Security',
          securityACC.toString(),
          Icons.security_rounded,
          primaryColor,
        ),
      ],
    );
  }

  Widget _buildStatCard(
    String title,
    String value,
    IconData icon,
    Color color,
  ) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 12),
        decoration: BoxDecoration(
          color: surfaceColor,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: color.withOpacity(0.08),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          children: [
            Icon(icon, color: color, size: 22),
            const SizedBox(height: 8),
            Text(
              value,
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: Colors.grey.shade800,
              ),
            ),
            Text(
              title,
              style: TextStyle(fontSize: 11, color: Colors.grey.shade500),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTabNavigation() {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: Colors.grey.shade200,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          _buildTabItem('Live Hari Ini', 0),
          _buildTabItem('Riwayat Data', 1),
        ],
      ),
    );
  }

  Widget _buildTabItem(String label, int index) {
    final isSelected = _selectedTabIndex == index;
    return Expanded(
      child: GestureDetector(
        onTap: () => _handleTabChange(index),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: isSelected ? surfaceColor : Colors.transparent,
            borderRadius: BorderRadius.circular(10),
            boxShadow: isSelected
                ? [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.05),
                      blurRadius: 4,
                      offset: const Offset(0, 2),
                    ),
                  ]
                : [],
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (index == 1 && isSelected) ...[
                GestureDetector(
                  onTap: _showHistoryPicker, // Klik ikon untuk ganti tanggal
                  child: Icon(
                    Icons.calendar_month,
                    size: 16,
                    color: primaryColor,
                  ),
                ),
                const SizedBox(width: 6),
              ],
              Text(
                label,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                  color: isSelected ? primaryColor : Colors.grey.shade600,
                  fontSize: 13,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildContentSliver(List<Map<String, Object?>> logs) {
    if (logs.isEmpty) {
      return SliverToBoxAdapter(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 40),
          child: Column(
            children: [
              Icon(Icons.inbox_rounded, size: 48, color: Colors.grey.shade300),
              const SizedBox(height: 12),
              Text(
                'Tidak ada data log',
                style: TextStyle(
                  color: Colors.grey.shade400,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
        ),
      );
    }

    return SliverList(
      delegate: SliverChildBuilderDelegate((context, index) {
        final log = logs[index];
        return _buildLogCard(log, index);
      }, childCount: logs.length),
    );
  }

  Future<void> _deleteLog(String id) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Hapus Log Pulang'),
        content: Text('Anda yakin ingin menghapus log untuk $id?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Hapus'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    try {
      final encodedId = Uri.encodeComponent(id);
      final response = await http.delete(
        Uri.parse('http://localhost:8080/logs/$encodedId'),
      );

      if (response.statusCode == 200) {
        setState(() {});
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Log berhasil dihapus'), backgroundColor: Colors.green),
          );
        }
      } else {
        throw Exception(response.body);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Gagal menghapus: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  Widget _buildLogCard(Map<String, Object?> log, int index) {
    final id = log['id_karyawan'].toString();
    if (_showToiletLogs) {
      return _buildToiletLogCard(log, index, id);
    }
    final pengawas = log['status_pengawas']?.toString() ?? '-';
    final security = log['status_security']?.toString() ?? '-';

    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: Duration(milliseconds: 300 + (index * 50).clamp(0, 500)),
      curve: Curves.easeOutQuart,
      builder: (context, value, child) {
        return Transform.translate(
          offset: Offset(0, 20 * (1 - value)),
          child: Opacity(opacity: value, child: child),
        );
      },
      child: Container(
        margin: const EdgeInsets.fromLTRB(20, 0, 20, 12),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: surfaceColor,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: Colors.grey.shade100,
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Row(
          children: [
            // Avatar ID
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: Colors.green.shade50,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.green.shade100),
              ),
              child: Center(
                child: Text(
                  id.isNotEmpty ? id.substring(0, 1).toUpperCase() : '?',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                    color: Colors.green.shade700,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 16),
            // Info Content
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'ID Card: $id',
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 15,
                      color: Colors.black87,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      _buildStatusPill('Pengawas', pengawas),
                      const SizedBox(width: 8),
                      _buildStatusPill('Security', security),
                    ],
                  ),
                ],
              ),
            ),
            IconButton(
              icon: const Icon(Icons.delete_outline, color: Colors.redAccent, size: 20),
              onPressed: () => _deleteLog(id),
              tooltip: 'Hapus Log',
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _deleteToiletLog(String id) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Hapus Izin Toilet'),
        content: Text('Anda yakin ingin menghapus izin untuk $id?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Hapus'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    try {
      final encodedId = Uri.encodeComponent(id);
      final response = await http.delete(
        Uri.parse('http://localhost:8080/toilet-permits/$encodedId'),
      );

      if (response.statusCode == 200) {
        setState(() {}); // Refresh UI
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Izin toilet berhasil dihapus'),
              backgroundColor: Colors.green,
            ),
          );
        }
      } else {
        throw Exception(response.body);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Gagal menghapus: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _editToiletLog(Map<String, Object?> log) async {
    final id = log['id_karyawan'].toString();
    final currentDuration = int.tryParse(log['duration_minutes']?.toString() ?? '10') ?? 10;
    final currentStatus = log['proof_status']?.toString() ?? 'PENDING';

    final durationController = TextEditingController(text: currentDuration.toString());
    String selectedStatus = currentStatus;

    final result = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Edit Izin Toilet'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('ID: $id', style: const TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 16),
              TextField(
                controller: durationController,
                decoration: const InputDecoration(
                  labelText: 'Durasi (menit)',
                  border: OutlineInputBorder(),
                ),
                keyboardType: TextInputType.number,
              ),
              const SizedBox(height: 16),
              DropdownButtonFormField<String>(
                value: selectedStatus,
                decoration: const InputDecoration(
                  labelText: 'Status Bukti',
                  border: OutlineInputBorder(),
                ),
                items: const [
                  DropdownMenuItem(value: 'PENDING', child: Text('PENDING')),
                  DropdownMenuItem(value: 'SCANNED', child: Text('SCANNED')),
                ],
                onChanged: (val) {
                  if (val != null) setDialogState(() => selectedStatus = val);
                },
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Simpan'),
            ),
          ],
        ),
      ),
    );

    if (result != true) return;

    try {
      final encodedId = Uri.encodeComponent(id);
      final response = await http.put(
        Uri.parse('http://localhost:8080/toilet-permits/$encodedId'),
        body: jsonEncode({
          'duration_minutes': int.tryParse(durationController.text) ?? 10,
          'proof_status': selectedStatus,
        }),
        headers: {'Content-Type': 'application/json'},
      );

      if (response.statusCode == 200) {
        setState(() {});
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Izin berhasil diupdate'), backgroundColor: Colors.green),
          );
        }
      } else {
        throw Exception(response.body);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Gagal update: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  Widget _buildToiletLogCard(Map<String, Object?> log, int index, String id) {
    final state = log['permit_state']?.toString() ?? '-';
    final proof = log['proof_status']?.toString() ?? '-';
    final duration = log['duration_minutes']?.toString() ?? '-';
    final expiresAt = log['expires_at']?.toString() ?? '-';
    final approvedBy = log['approved_by']?.toString() ?? '-';

    return Container(
      margin: const EdgeInsets.fromLTRB(20, 0, 20, 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: surfaceColor,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.grey.shade100,
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          Icon(Icons.wc_rounded, color: Colors.blue.shade700, size: 32),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  id,
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 15,
                    color: Colors.black87,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 6),
                Text(
                  'Status: $state | Bukti: $proof | Durasi: $duration menit',
                  style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
                ),
                Text(
                  'Pengawas: $approvedBy | Habis: $expiresAt',
                  style: TextStyle(fontSize: 12, color: Colors.grey.shade500),
                ),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.edit_outlined, color: Colors.blueAccent, size: 20),
            onPressed: () => _editToiletLog(log),
            tooltip: 'Edit Izin',
          ),
          IconButton(
            icon: const Icon(Icons.delete_outline, color: Colors.redAccent, size: 20),
            onPressed: () => _deleteToiletLog(id),
            tooltip: 'Hapus Izin',
          ),
        ],
      ),
    );
  }

  Widget _buildStatusPill(String label, String status) {
    final isAcc = status == 'ACC';
    final color = isAcc ? const Color(0xFF10B981) : const Color(0xFFF59E0B);
    final bgColor = isAcc ? const Color(0xFFECFDF5) : const Color(0xFFFFFBEB);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withOpacity(0.2)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            '$label: ',
            style: TextStyle(fontSize: 10, color: Colors.grey.shade600),
          ),
          Text(
            isAcc ? 'OK' : 'Wait', // Teks lebih pendek agar muat
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}

// Dialog Date Picker Modern
class _DateHistoryPickerDialog extends StatefulWidget {
  final Database db;
  final bool showToiletLogs;
  final Function(String) onDateSelected;
  final VoidCallback onReset;

  const _DateHistoryPickerDialog({
    required this.db,
    required this.showToiletLogs,
    required this.onDateSelected,
    required this.onReset,
  });

  @override
  State<_DateHistoryPickerDialog> createState() =>
      _DateHistoryPickerDialogState();
}

class _DateHistoryPickerDialogState extends State<_DateHistoryPickerDialog> {
  late Future<List<String>> _datesFuture;
  String? _selectedDate;

  @override
  void initState() {
    super.initState();
    _datesFuture = _fetchAvailableDates();
  }

  Future<List<String>> _fetchAvailableDates() async {
    final table = widget.showToiletLogs
        ? 'toilet_permit_history'
        : 'log_pulang_history';
    final rows = widget.db.select(
      'SELECT DISTINCT tanggal FROM $table ORDER BY tanggal DESC',
    );
    return rows.map((row) => row['tanggal'].toString()).toList();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: const Text(
        'Pilih Tanggal',
        style: TextStyle(fontWeight: FontWeight.bold),
      ),
      content: SizedBox(
        width: double.maxFinite,
        height: 300,
        child: FutureBuilder<List<String>>(
          future: _datesFuture,
          builder: (context, snapshot) {
            if (!snapshot.hasData) {
              return const Center(child: CircularProgressIndicator());
            }
            final dates = snapshot.data!;
            return ListView.builder(
              itemCount: dates.length,
              itemBuilder: (context, index) {
                final date = dates[index];
                final isSelected = _selectedDate == date;
                return Container(
                  margin: const EdgeInsets.only(bottom: 8),
                  decoration: BoxDecoration(
                    color: isSelected ? Colors.green.shade50 : Colors.white,
                    border: Border.all(
                      color: isSelected
                          ? Colors.green.shade500
                          : Colors.grey.shade200,
                    ),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: ListTile(
                    dense: true,
                    title: Text(
                      date,
                      style: TextStyle(
                        fontWeight: isSelected
                            ? FontWeight.bold
                            : FontWeight.normal,
                        color: isSelected
                            ? Colors.green.shade700
                            : Colors.black87,
                      ),
                    ),
                    trailing: isSelected
                        ? Icon(Icons.check_circle, color: Colors.green.shade600)
                        : null,
                    onTap: () => setState(() => _selectedDate = date),
                  ),
                );
              },
            );
          },
        ),
      ),
      actions: [
        TextButton(
          onPressed: widget.onReset,
          child: const Text(
            'Reset ke Live',
            style: TextStyle(color: Colors.orange),
          ),
        ),
        ElevatedButton(
          onPressed: _selectedDate == null
              ? null
              : () => widget.onDateSelected(_selectedDate!),
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFF059669),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
            ),
          ),
          child: const Text('Tampilkan'),
        ),
      ],
    );
  }
}
