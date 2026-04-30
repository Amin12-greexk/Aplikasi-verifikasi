import 'dart:async';

import 'package:flutter/material.dart';

import 'export_service.dart';
import 'remote_api_service.dart';
import 'remote_room_management.dart';
import 'remote_user_management.dart';

class RemoteServerHomePage extends StatefulWidget {
  const RemoteServerHomePage({
    required this.api,
    required this.onLogout,
    super.key,
  });

  final RemoteApiService api;
  final VoidCallback onLogout;

  @override
  State<RemoteServerHomePage> createState() => _RemoteServerHomePageState();
}

class _RemoteServerHomePageState extends State<RemoteServerHomePage> {
  final Duration _refreshInterval = const Duration(seconds: 3);
  Timer? _refreshTimer;

  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _logs = <Map<String, dynamic>>[];
  int _selectedTab = 0; // 0: live, 1: history
  String? _viewingDate;

  @override
  void initState() {
    super.initState();
    _refreshData();
    _refreshTimer = Timer.periodic(
      _refreshInterval,
      (_) => _refreshData(silent: true),
    );
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    super.dispose();
  }

  Future<void> _refreshData({bool silent = false}) async {
    if (!silent) {
      setState(() {
        _loading = true;
      });
    }
    try {
      final logs = (_selectedTab == 1 && _viewingDate != null)
          ? await widget.api.fetchLogsByDate(_viewingDate!)
          : await widget.api.fetchLogs();
      if (!mounted) return;
      setState(() {
        _logs = logs;
        _error = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
      });
    } finally {
      if (mounted) {
        setState(() {
          _loading = false;
        });
      }
    }
  }

  void _showSnack(String msg, {bool isError = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: isError ? Colors.red.shade600 : Colors.green.shade600,
      ),
    );
  }

  Future<void> _pickHistoryDate() async {
    List<String> dates;
    try {
      dates = await widget.api.fetchHistoryDates();
    } catch (e) {
      _showSnack('Gagal load tanggal history: $e', isError: true);
      return;
    }

    if (!mounted) return;
    final selected = await showDialog<String>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Pilih Tanggal History'),
          content: SizedBox(
            width: 380,
            height: 420,
            child: dates.isEmpty
                ? const Center(child: Text('Belum ada history'))
                : ListView.builder(
                    itemCount: dates.length,
                    itemBuilder: (context, index) {
                      final date = dates[index];
                      return ListTile(
                        title: Text(date),
                        trailing: _viewingDate == date
                            ? const Icon(Icons.check)
                            : null,
                        onTap: () => Navigator.pop(context, date),
                      );
                    },
                  ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Batal'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, ''),
              child: const Text('Reset ke Live'),
            ),
          ],
        );
      },
    );

    if (selected == null) return;
    setState(() {
      if (selected.isEmpty) {
        _selectedTab = 0;
        _viewingDate = null;
      } else {
        _selectedTab = 1;
        _viewingDate = selected;
      }
    });
    await _refreshData();
  }

  Future<void> _clearLogsOnly() async {
    try {
      await widget.api.clearLogsOnly();
      _showSnack('Log hari ini berhasil dihapus. History tetap tersimpan.');
      await _refreshData();
    } catch (e) {
      _showSnack('Gagal clear logs: $e', isError: true);
    }
  }

  Future<void> _clearAllData() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Konfirmasi Clear All'),
          content: const Text(
            'Semua log dan history akan dihapus permanen.\nLanjutkan?',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Batal'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(context, true),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red.shade600,
              ),
              child: const Text('Hapus Semua'),
            ),
          ],
        );
      },
    );

    if (confirmed != true) return;
    try {
      await widget.api.clearAllData();
      _showSnack('Semua log dan history berhasil dihapus.');
      await _refreshData();
    } catch (e) {
      _showSnack('Gagal clear all: $e', isError: true);
    }
  }

  Future<void> _exportPdf() async {
    try {
      final logs = _logs.map((e) => Map<String, Object?>.from(e)).toList();
      final path = await ExportService.exportToPdf(logs, 'Laporan Ijin Pulang');
      if (path != null) _showSnack('PDF berhasil disimpan');
    } catch (e) {
      _showSnack('Gagal export PDF: $e', isError: true);
    }
  }

  Future<void> _exportExcel() async {
    try {
      final logs = _logs.map((e) => Map<String, Object?>.from(e)).toList();
      final path = await ExportService.exportToExcel(
        logs,
        'Laporan Ijin Pulang',
      );
      if (path != null) _showSnack('Excel berhasil disimpan');
    } catch (e) {
      _showSnack('Gagal export Excel: $e', isError: true);
    }
  }

  Widget _statCard(String label, int value, Color color) {
    return Expanded(
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: TextStyle(color: Colors.grey.shade600, fontSize: 12),
              ),
              const SizedBox(height: 6),
              Text(
                '$value',
                style: TextStyle(
                  color: color,
                  fontWeight: FontWeight.bold,
                  fontSize: 24,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final total = _logs.length;
    final accPengawas = _logs
        .where((e) => e['status_pengawas'] == 'ACC')
        .length;
    final accSecurity = _logs
        .where((e) => e['status_security'] == 'ACC')
        .length;

    return Scaffold(
      appBar: AppBar(
        title: Text('Server Interface (Remote) - ${widget.api.baseUrl}'),
        actions: [
          IconButton(
            tooltip: 'Refresh',
            onPressed: _loading ? null : _refreshData,
            icon: const Icon(Icons.refresh),
          ),
          PopupMenuButton<String>(
            onSelected: (value) async {
              switch (value) {
                case 'history':
                  await _pickHistoryDate();
                case 'users':
                  await Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => RemoteUserManagementPage(api: widget.api),
                    ),
                  );
                  await _refreshData();
                case 'rooms':
                  await Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => RemoteRoomManagementPage(api: widget.api),
                    ),
                  );
                  await _refreshData();
                case 'clear_logs':
                  await _clearLogsOnly();
                case 'clear_all':
                  await _clearAllData();
                case 'export_pdf':
                  await _exportPdf();
                case 'export_excel':
                  await _exportExcel();
                case 'logout':
                  widget.api.logout();
                  widget.onLogout();
              }
            },
            itemBuilder: (context) {
              return const [
                PopupMenuItem(value: 'history', child: Text('Pilih History')),
                PopupMenuItem(value: 'users', child: Text('User Management')),
                PopupMenuItem(value: 'rooms', child: Text('Room Management')),
                PopupMenuItem(value: 'export_pdf', child: Text('Export PDF')),
                PopupMenuItem(
                  value: 'export_excel',
                  child: Text('Export Excel'),
                ),
                PopupMenuItem(value: 'clear_logs', child: Text('Clear Logs')),
                PopupMenuItem(
                  value: 'clear_all',
                  child: Text('Clear All Data'),
                ),
                PopupMenuItem(value: 'logout', child: Text('Logout')),
              ];
            },
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
          ? Center(child: Text('Error: $_error'))
          : Column(
              children: [
                if (_selectedTab == 1 && _viewingDate != null)
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    color: Colors.blue.shade50,
                    child: Text(
                      'Mode History: $_viewingDate',
                      style: TextStyle(
                        color: Colors.blue.shade700,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    children: [
                      _statCard('Total Log', total, Colors.blue.shade700),
                      _statCard(
                        'ACC Pengawas',
                        accPengawas,
                        Colors.orange.shade700,
                      ),
                      _statCard(
                        'ACC Security',
                        accSecurity,
                        Colors.green.shade700,
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: _logs.isEmpty
                      ? const Center(child: Text('Tidak ada data log'))
                      : ListView.builder(
                          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                          itemCount: _logs.length,
                          itemBuilder: (context, index) {
                            final item = _logs[index];
                            return Card(
                              margin: const EdgeInsets.only(bottom: 10),
                              child: ListTile(
                                title: Text(
                                  item['id_karyawan']?.toString() ?? '-',
                                ),
                                subtitle: Text(
                                  'Pengawas: ${item['status_pengawas']} | Security: ${item['status_security']}',
                                ),
                              ),
                            );
                          },
                        ),
                ),
              ],
            ),
    );
  }
}
