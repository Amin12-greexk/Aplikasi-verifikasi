import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:sqlite3/sqlite3.dart' hide Row;
import 'package:window_manager/window_manager.dart';

import 'admin_login.dart';
import 'db.dart';
import 'headless_server.dart';
import 'modern_dashboard.dart';
import 'modern_server_home.dart';
import 'system_tray_manager.dart';
import 'ui.dart';
import 'user_management.dart';

void main(List<String> args) async {
  WidgetsFlutterBinding.ensureInitialized();

  // Detect if running in service mode
  final isServiceMode = args.contains('--service-mode');
  final minimizeToTray = args.contains('--minimize-to-tray');

  // Initialize database
  final db = await initDb('log.db');

  if (isServiceMode) {
    // Headless mode: Run HTTP server only, no UI
    stdout.writeln('[SERVICE MODE] Starting verifikasi_server as Windows Service...');
    await startServerHeadless(db);
    // Keep the application alive by preventing early exit
    // The service wrapper will manage the process lifecycle
    await Future.delayed(const Duration(days: 365));
  } else {
    // Desktop mode: Run both UI and HTTP server
    stdout.writeln('[DESKTOP MODE] Starting verifikasi_server with UI...');

    // Start the HTTP server in the background immediately
    unawaited(startServerBackground(db));

    runApp(ServerApp(
      db: db,
      minimizeToTray: minimizeToTray,
    ));
  }
}

// Helper to run future without awaiting
void unawaited(Future<void> future) {
  // Fire and forget
}

class ServerApp extends StatefulWidget {
  final Database db;
  final bool minimizeToTray;

  const ServerApp({
    required this.db,
    this.minimizeToTray = false,
    super.key,
  });

  @override
  State<ServerApp> createState() => _ServerAppState();
}

class _ServerAppState extends State<ServerApp> with WindowListener {
  bool _isLoggedIn = false;
  late SystemTrayManager _trayManager;

  @override
  void initState() {
    super.initState();
    _initWindowManager();
    _initSystemTray();
  }

  Future<void> _initWindowManager() async {
    try {
      // Ensure window manager is initialized
      await windowManager.ensureInitialized();
      windowManager.addListener(this);

      // Configure window
      const windowOptions = WindowOptions(
        size: Size(1280, 720),
        center: true,
        backgroundColor: Colors.white,
        skipTaskbar: false,
        alwaysOnTop: false,
      );

      await windowManager.waitUntilReadyToShow(windowOptions, () async {
        await windowManager.show();
        await windowManager.focus();
      });

      print('[Window] Window manager initialized');
    } catch (e) {
      print('[Window] Error initializing window manager: $e');
    }
  }

  void _initSystemTray() {
    _trayManager = SystemTrayManager();
    _trayManager.initialize(
      onShow: () {
        if (kDebugMode) {
          print('Show dashboard from tray');
        }
        _trayManager.showWindow();
      },
      onExit: () {
        if (kDebugMode) {
          print('Exit from tray');
        }
        windowManager.destroy();
        exit(0);
      },
    );

    // Minimize to tray on startup if flag is set
    if (widget.minimizeToTray) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _trayManager.hideWindow();
      });
    }
  }

  @override
  void dispose() {
    _trayManager.dispose();
    windowManager.removeListener(this);
    super.dispose();
  }

  // WindowListener implementation
  @override
  void onWindowEvent(String eventName) {
    print('[Window] Event: $eventName');
  }

  @override
  void onWindowClose() async {
    print('[Window] Window closing');
    // Instead of closing immediately, minimize to tray
    if (!_isLoggedIn) {
      await windowManager.destroy();
    } else {
      await _trayManager.hideWindow();
    }
  }

  @override
  void onWindowMinimize() {
    print('[Window] Minimized - hiding to tray');
    _trayManager.hideWindow();
  }

  @override
  void onWindowMaximize() {
    print('[Window] Maximized');
  }

  @override
  void onWindowRestore() {
    print('[Window] Restored');
  }

  @override
  void onWindowResized() {
    print('[Window] Resized');
  }

  @override
  void onWindowMoved() {
    print('[Window] Moved');
  }

  @override
  void onWindowFocusChanged(bool focused) {
    if (kDebugMode) {
      print('[Window] Focus changed: $focused');
    }
  }

  @override
  void onWindowEnterFullScreen() {
    print('[Window] Entered fullscreen');
  }

  @override
  void onWindowLeaveFullScreen() {
    print('[Window] Left fullscreen');
  }

  @override
  void onWindowBeforeClose() {
    print('[Window] Before close');
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Verifikasi Pulang - Server',
      theme: GreenTheme.getTheme(),
      home: _isLoggedIn
          ? ModernServerHome(db: widget.db)
          : AdminLoginPage(
              onLoginSuccess: (success) {
                if (success) {
                  setState(() => _isLoggedIn = true);
                }
              },
            ),
      debugShowCheckedModeBanner: false,
    );
  }
}

class ServerHome extends StatefulWidget {
  final Database db;

  const ServerHome({required this.db, super.key});

  @override
  State<ServerHome> createState() => _ServerHomeState();
}

class _ServerHomeState extends State<ServerHome> {
  late Timer _refreshTimer;
  String? _viewingDate;

  @override
  void initState() {
    super.initState();
    // Refresh data every 2 seconds
    _refreshTimer = Timer.periodic(const Duration(seconds: 2), (_) {
      setState(() {});
    });
  }

  @override
  void dispose() {
    _refreshTimer.cancel();
    super.dispose();
  }

  List<Map<String, Object?>> _getLogs() {
    if (_viewingDate != null) {
      // Get logs from history table for selected date
      final rows = widget.db.select(
        'SELECT * FROM log_pulang_history WHERE tanggal = ? ORDER BY id_karyawan ASC',
        [_viewingDate!],
      );
      return rows
          .map((r) => {
                'id_karyawan': r['id_karyawan'],
                'status_pengawas': r['status_pengawas'],
                'status_security': r['status_security'],
              })
          .toList();
    } else {
      // Get current logs
      final rows = widget.db.select('SELECT * FROM log_pulang ORDER BY id_karyawan ASC');
      return rows
          .map((r) => {
                'id_karyawan': r['id_karyawan'],
                'status_pengawas': r['status_pengawas'],
                'status_security': r['status_security'],
              })
          .toList();
    }
  }

  void _showHistoryPicker() {
    showDialog(
      context: context,
      builder: (context) => DateHistoryPickerDialog(
        onDateSelected: (date) {
          setState(() {
            _viewingDate = date;
          });
          Navigator.pop(context);
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Menampilkan log untuk tanggal: $date'),
              duration: const Duration(seconds: 2),
              backgroundColor: Colors.blue.shade600,
            ),
          );
        },
        onReset: () {
          setState(() {
            _viewingDate = null;
          });
          Navigator.pop(context);
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: const Text('Menampilkan log hari ini'),
              duration: const Duration(seconds: 2),
              backgroundColor: Colors.green.shade600,
            ),
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final logs = _getLogs();
    return Column(
      children: [
        // Custom AppBar with History button
        Container(
          color: Colors.white,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  _viewingDate != null ? 'Log History: $_viewingDate' : 'Log Hari Ini',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: Colors.green.shade700,
                  ),
                ),
              ),
              if (_viewingDate != null)
                ElevatedButton.icon(
                  onPressed: () {
                    setState(() {
                      _viewingDate = null;
                    });
                  },
                  icon: const Icon(Icons.close, size: 18),
                  label: const Text('Clear Filter'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.orange.shade600,
                    foregroundColor: Colors.white,
                  ),
                ),
              const SizedBox(width: 8),
              ElevatedButton.icon(
                onPressed: _showHistoryPicker,
                icon: const Icon(Icons.calendar_month, size: 18),
                label: const Text('History'),
              ),
              const SizedBox(width: 8),
              ElevatedButton.icon(
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => UserManagementPage(db: widget.db),
                    ),
                  );
                },
                icon: const Icon(Icons.people, size: 18),
                label: const Text('Users'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.blue.shade600,
                ),
              ),
            ],
          ),
        ),
        const Divider(height: 1),
        // Dashboard
        Expanded(
          child: ModernServerDashboard(
            logs: logs,
            onRefresh: () {
              setState(() {});
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: const Text('Data refreshed'),
                  duration: const Duration(seconds: 1),
                  backgroundColor: Colors.green.shade600,
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

class DateHistoryPickerDialog extends StatefulWidget {
  final Function(String) onDateSelected;
  final VoidCallback onReset;

  const DateHistoryPickerDialog({
    required this.onDateSelected,
    required this.onReset,
    super.key,
  });

  @override
  State<DateHistoryPickerDialog> createState() => _DateHistoryPickerDialogState();
}

class _DateHistoryPickerDialogState extends State<DateHistoryPickerDialog> {
  late Future<List<String>> _datesFuture;
  String? _selectedDate;

  @override
  void initState() {
    super.initState();
    _datesFuture = _fetchAvailableDates();
  }

  Future<List<String>> _fetchAvailableDates() async {
    // Generate list of dates (last 30 days)
    List<String> dates = [];
    final today = DateTime.now();
    for (int i = 0; i < 30; i++) {
      final date = today.subtract(Duration(days: i));
      final formatted =
          '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
      dates.add(formatted);
    }
    return dates;
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('📅 Pilih Tanggal History'),
      content: FutureBuilder<List<String>>(
        future: _datesFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const SizedBox(
              height: 200,
              child: Center(child: CircularProgressIndicator()),
            );
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
        TextButton(
          onPressed: () {
            widget.onReset();
          },
          child: Text(
            'Reset',
            style: TextStyle(color: Colors.orange.shade600),
          ),
        ),
        ElevatedButton(
          onPressed: _selectedDate == null ? null : () => widget.onDateSelected(_selectedDate!),
          child: const Text('Lihat Log'),
        ),
      ],
    );
  }
}
