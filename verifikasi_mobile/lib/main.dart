import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import 'auth_service.dart';
import 'config.dart';
import 'crud_log_page.dart';
import 'daily_refresh_manager.dart';
import 'login_page.dart';
import 'scanner_page.dart';
import 'settings_page.dart';
import 'status_page.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await ServerConfig.init();
  await AuthService.init();
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Verifikasi Pulang',
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.green.shade600,
          brightness: Brightness.light,
        ),
        scaffoldBackgroundColor: const Color(0xFFF8FAFB),
        appBarTheme: AppBarTheme(
          backgroundColor: Colors.white,
          elevation: 0,
          surfaceTintColor: Colors.transparent,
        ),
        navigationBarTheme: NavigationBarThemeData(
          indicatorColor: Colors.green.shade100,
          backgroundColor: Colors.white,
          elevation: 8,
          labelTextStyle: WidgetStateProperty.all(
            TextStyle(color: Colors.green.shade800, fontWeight: FontWeight.w600, fontSize: 12),
          ),
          iconTheme: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.selected)) {
              return IconThemeData(color: Colors.green.shade700, size: 26);
            }
            return IconThemeData(color: Colors.grey.shade500, size: 24);
          }),
        ),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.green.shade600,
            foregroundColor: Colors.white,
            elevation: 4,
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
        ),
      ),
      home: AuthService.isLoggedIn ? const HomeShell() : const LoginPage(),
      routes: {
        '/home': (context) => const HomeShell(),
        '/login': (context) => const LoginPage(),
      },
    );
  }
}

class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> with TickerProviderStateMixin {
  int _index = 0;
  late AnimationController _headerAnimationController;

  @override
  void initState() {
    super.initState();
    _headerAnimationController = AnimationController(
      duration: const Duration(milliseconds: 800),
      vsync: this,
    )..forward();

    _checkDailyRefresh();
  }

  @override
  void dispose() {
    _headerAnimationController.dispose();
    super.dispose();
  }

  Future<void> _checkDailyRefresh() async {
    final shouldRefresh = await DailyRefreshManager.shouldRefreshDaily();
    if (shouldRefresh && mounted) {
      // Show notification that a new day has started
      // The actual reset will happen when StatusTab initializes
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Row(
            children: [
              Icon(Icons.wb_sunny, color: Colors.white),
              SizedBox(width: 12),
              Expanded(
                child: Text(
                  'Hari baru dimulai! Data akan direset otomatis.',
                  maxLines: 2,
                ),
              ),
            ],
          ),
          backgroundColor: Colors.green.shade600,
          duration: const Duration(seconds: 3),
        ),
      );
    }
  }

  Widget _buildHeader() {
    final isPengawas = AuthService.isPengawas();
    final userName = AuthService.username ?? 'User';

    return FadeTransition(
      opacity: _headerAnimationController,
      child: Container(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: isPengawas
                ? [Colors.blue.shade600, Colors.blue.shade500]
                : [Colors.green.shade600, Colors.green.shade500],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: const BorderRadius.vertical(bottom: Radius.circular(24)),
          boxShadow: [
            BoxShadow(
              color: (isPengawas ? Colors.blue.shade900 : Colors.green.shade900)
                  .withAlpha(40),
              blurRadius: 16,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.white.withAlpha(200),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(
                    isPengawas ? Icons.badge : Icons.security,
                    color: isPengawas ? Colors.blue.shade600 : Colors.green.shade600,
                    size: 32,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Verifikasi Pulang',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Text(
                        isPengawas ? 'Pengawas' : 'Security',
                        style: TextStyle(
                          color: Colors.white.withAlpha(200),
                          fontSize: 12,
                          fontWeight: FontWeight.w400,
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.settings, color: Colors.white),
                  onPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => const SettingsPage(),
                      ),
                    );
                  },
                ),
              ],
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: Colors.white.withAlpha(180),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    isPengawas ? Icons.verified_user : Icons.security,
                    size: 16,
                    color: isPengawas ? Colors.blue.shade600 : Colors.green.shade600,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    isPengawas
                        ? 'Login sebagai: $userName (Pengawas)'
                        : 'Login sebagai: $userName (Security)',
                    style: TextStyle(
                      color: isPengawas ? Colors.blue.shade700 : Colors.green.shade700,
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _body() {
    if (AuthService.isPengawas()) {
      // Menu untuk Pengawas
      switch (_index) {
        case 0:
          return const StatusTab();
        case 1:
          return const ScannerTab(isPengawas: true);
        case 2:
          return const CRUDLogPage();
        default:
          return const StatusTab();
      }
    } else {
      // Menu untuk Security (hanya Status & Scan)
      switch (_index) {
        case 0:
          return const StatusTab();
        case 1:
          return const ScannerTab(isPengawas: false);
        default:
          return const StatusTab();
      }
    }
  }

  List<NavigationDestination> _buildNavigationDestinations() {
    final isPengawas = AuthService.isPengawas();

    if (isPengawas) {
      // Navigation untuk Pengawas (3 menu: Status, Scan, Data)
      return [
        NavigationDestination(
          icon: Icon(
            Icons.list_alt,
            color: _index == 0 ? Colors.green.shade600 : Colors.grey.shade500,
          ),
          label: 'Status',
        ),
        NavigationDestination(
          icon: Icon(
            Icons.badge,
            color: _index == 1 ? Colors.green.shade600 : Colors.grey.shade500,
          ),
          label: 'Scan',
        ),
        NavigationDestination(
          icon: Icon(
            Icons.edit_note,
            color: _index == 2 ? Colors.green.shade600 : Colors.grey.shade500,
          ),
          label: 'Data',
        ),
      ];
    } else {
      // Navigation untuk Security (2 menu: Status, Scan)
      return [
        NavigationDestination(
          icon: Icon(
            Icons.list_alt,
            color: _index == 0 ? Colors.green.shade600 : Colors.grey.shade500,
          ),
          label: 'Status',
        ),
        NavigationDestination(
          icon: Icon(
            Icons.security,
            color: _index == 1 ? Colors.green.shade600 : Colors.grey.shade500,
          ),
          label: 'Scan',
        ),
      ];
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            _buildHeader(),
            const SizedBox(height: 20),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: _body(),
              ),
            ),
          ],
        ),
      ),
      bottomNavigationBar: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withAlpha(30),
              blurRadius: 12,
              offset: const Offset(0, -4),
            ),
          ],
        ),
        child: NavigationBar(
          selectedIndex: _index,
          onDestinationSelected: (i) => setState(() => _index = i),
          backgroundColor: Colors.white,
          surfaceTintColor: Colors.transparent,
          destinations: _buildNavigationDestinations(),
        ),
      ),
    );
  }
}
