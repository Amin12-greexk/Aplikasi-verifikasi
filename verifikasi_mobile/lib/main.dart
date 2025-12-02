import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import 'daily_refresh_manager.dart';
import 'scanner_page.dart';
import 'status_page.dart';

void main() {
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
      home: const HomeShell(),
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
      // Show notification that data has been reset
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Row(
            children: [
              Icon(Icons.refresh, color: Colors.white),
              SizedBox(width: 12),
              Expanded(
                child: Text(
                  'Data verifikasi telah direset untuk hari baru. Log tersimpan di server.',
                  maxLines: 2,
                ),
              ),
            ],
          ),
          backgroundColor: Colors.green.shade600,
          duration: const Duration(seconds: 4),
        ),
      );
    }
  }

  Widget _buildHeader() {
    return FadeTransition(
      opacity: _headerAnimationController,
      child: Container(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [
              Colors.green.shade600,
              Colors.green.shade500,
            ],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: const BorderRadius.vertical(bottom: Radius.circular(24)),
          boxShadow: [
            BoxShadow(
              color: Colors.green.shade900.withAlpha(40),
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
                  child: SizedBox(
                    width: 40,
                    height: 40,
                    child: SvgPicture.asset('assets/logo.svg'),
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
                        'Management System',
                        style: TextStyle(
                          color: Colors.white.withAlpha(200),
                          fontSize: 12,
                          fontWeight: FontWeight.w400,
                        ),
                      ),
                    ],
                  ),
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
                  Icon(Icons.info_outline, size: 16, color: Colors.green.shade600),
                  const SizedBox(width: 8),
                  Text(
                    'Monitor ACC Pengawas & Security',
                    style: TextStyle(
                      color: Colors.green.shade700,
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
    switch (_index) {
      case 0:
        return const StatusTab();
      case 1:
        return const ScannerTab(isPengawas: true);
      case 2:
        return const ScannerTab(isPengawas: false);
      default:
        return const StatusTab();
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
          destinations: [
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
              label: 'Scan Pengawas',
            ),
            NavigationDestination(
              icon: Icon(
                Icons.security,
                color: _index == 2 ? Colors.green.shade600 : Colors.grey.shade500,
              ),
              label: 'Scan Security',
            ),
          ],
        ),
      ),
    );
  }
}
