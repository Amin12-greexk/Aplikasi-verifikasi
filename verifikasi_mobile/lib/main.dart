import 'package:flutter/material.dart';

import 'core/config/config.dart';
import 'core/config/dev_visibility.dart';
import 'core/services/auth_service.dart';
import 'core/services/daily_refresh_manager.dart';
import 'core/theme/app_colors.dart';
import 'core/theme/app_theme.dart';
import 'features/attendance/attendance_page.dart';
import 'features/auth/login_page.dart';
import 'features/history/history_page.dart';
import 'features/home/home_page.dart';
import 'features/more/more_page.dart';
import 'features/verification/crud_log_page.dart';
import 'features/verification/verification_tab.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await ServerConfig.init();
  await DevVisibility.init();
  await AuthService.init();
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Verifikasi Mobile',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.lightTheme,
      home: AuthService.isLoggedIn ? const HomeShell() : const LoginPage(),
      routes: {
        '/home': (context) => const HomeShell(),
        '/login': (context) => const LoginPage(),
      },
    );
  }
}

/// Main shell with 5-tab bottom navigation.
/// Role-based visibility:
///   Pengawas: Beranda, Verifikasi, Absensi, Riwayat, Lainnya
///   Security: Beranda, Verifikasi, Riwayat, Lainnya (no Absensi)
class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> with TickerProviderStateMixin {
  late int _index;
  late AnimationController _headerAnimationController;

  bool get _isPengawas => AuthService.isPengawas();

  // Default tab: Verifikasi (index 1 for both roles)
  @override
  void initState() {
    super.initState();
    _index = 1;
    _headerAnimationController = AnimationController(
      duration: const Duration(milliseconds: 600),
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
          backgroundColor: AppColors.primary,
          duration: const Duration(seconds: 3),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
        ),
      );
    }
  }

  /// Build the appropriate body based on current tab index and role.
  Widget _body() {
    if (_isPengawas) {
      // Pengawas: 5 tabs [Beranda, Verifikasi, Absensi, Riwayat, Lainnya]
      switch (_index) {
        case 0:
          return const HomePage();
        case 1:
          return const VerificationTab();
        case 2:
          return const AttendancePage();
        case 3:
          return const HistoryPage();
        case 4:
          return const MorePage();
        default:
          return const VerificationTab();
      }
    } else {
      // Security: 4 tabs [Beranda, Verifikasi, Riwayat, Lainnya]
      switch (_index) {
        case 0:
          return const HomePage();
        case 1:
          return const VerificationTab();
        case 2:
          return const HistoryPage();
        case 3:
          return const MorePage();
        default:
          return const VerificationTab();
      }
    }
  }

  List<NavigationDestination> _buildDestinations() {
    if (_isPengawas) {
      return [
        NavigationDestination(
          icon: const Icon(Icons.home_outlined),
          selectedIcon: const Icon(Icons.home),
          label: 'Beranda',
        ),
        NavigationDestination(
          icon: const Icon(Icons.qr_code_scanner_outlined),
          selectedIcon: const Icon(Icons.qr_code_scanner),
          label: 'Verifikasi',
        ),
        NavigationDestination(
          icon: const Icon(Icons.fingerprint_outlined),
          selectedIcon: const Icon(Icons.fingerprint),
          label: 'Absensi',
        ),
        NavigationDestination(
          icon: const Icon(Icons.history_outlined),
          selectedIcon: const Icon(Icons.history),
          label: 'Riwayat',
        ),
        NavigationDestination(
          icon: const Icon(Icons.more_horiz_outlined),
          selectedIcon: const Icon(Icons.more_horiz),
          label: 'Lainnya',
        ),
      ];
    } else {
      return [
        NavigationDestination(
          icon: const Icon(Icons.home_outlined),
          selectedIcon: const Icon(Icons.home),
          label: 'Beranda',
        ),
        NavigationDestination(
          icon: const Icon(Icons.qr_code_scanner_outlined),
          selectedIcon: const Icon(Icons.qr_code_scanner),
          label: 'Verifikasi',
        ),
        NavigationDestination(
          icon: const Icon(Icons.history_outlined),
          selectedIcon: const Icon(Icons.history),
          label: 'Riwayat',
        ),
        NavigationDestination(
          icon: const Icon(Icons.more_horiz_outlined),
          selectedIcon: const Icon(Icons.more_horiz),
          label: 'Lainnya',
        ),
      ];
    }
  }

  /// Build the header section with user info and role indicator.
  Widget _buildHeader() {
    final userName = AuthService.username ?? 'User';
    final roleName = _isPengawas ? 'Pengawas' : 'Security';
    final gradientColors = _isPengawas
        ? AppColors.pengawasGradient
        : AppColors.primaryGradient;

    return FadeTransition(
      opacity: _headerAnimationController,
      child: Container(
        padding: const EdgeInsets.fromLTRB(20, 14, 20, 18),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: gradientColors,
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: const BorderRadius.vertical(
            bottom: Radius.circular(22),
          ),
          boxShadow: [
            BoxShadow(
              color: gradientColors.first.withAlpha(40),
              blurRadius: 16,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.white.withAlpha(40),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(
                _isPengawas ? Icons.badge : Icons.security,
                color: Colors.white,
                size: 26,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Verifikasi Mobile',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  Text(
                    '$userName · $roleName',
                    style: TextStyle(
                      color: Colors.white.withAlpha(200),
                      fontSize: 12,
                      fontWeight: FontWeight.w400,
                    ),
                  ),
                ],
              ),
            ),
            // Data management (Pengawas only)
            if (_isPengawas)
              IconButton(
                icon: const Icon(Icons.edit_note, color: Colors.white),
                tooltip: 'Kelola Data',
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const CRUDLogPage()),
                  );
                },
              ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            _buildHeader(),
            const SizedBox(height: 16),
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
          color: AppColors.surface,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withAlpha(15),
              blurRadius: 10,
              offset: const Offset(0, -3),
            ),
          ],
        ),
        child: NavigationBar(
          selectedIndex: _index,
          onDestinationSelected: (i) => setState(() => _index = i),
          backgroundColor: AppColors.surface,
          surfaceTintColor: Colors.transparent,
          destinations: _buildDestinations(),
        ),
      ),
    );
  }
}
