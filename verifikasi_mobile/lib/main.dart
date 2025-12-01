import 'package:flutter/material.dart';

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
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.green.shade600),
        scaffoldBackgroundColor: Colors.grey.shade50,
        navigationBarTheme: NavigationBarThemeData(
          indicatorColor: Colors.green.shade100,
          backgroundColor: Colors.white,
          labelTextStyle: WidgetStateProperty.all(
            TextStyle(color: Colors.green.shade800, fontWeight: FontWeight.w600),
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

class _HomeShellState extends State<HomeShell> {
  int _index = 0;

  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            Colors.green.shade700,
            Colors.green.shade500,
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: const BorderRadius.vertical(bottom: Radius.circular(24)),
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 24,
            backgroundColor: Colors.white,
            child: Icon(Icons.verified, color: Colors.green.shade700),
          ),
          const SizedBox(width: 12),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: const [
              Text('Verifikasi Pulang',
                  style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
              Text('Monitor ACC Pengawas & Security', style: TextStyle(color: Colors.white70)),
            ],
          )
        ],
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
            const SizedBox(height: 12),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: _body(),
              ),
            ),
          ],
        ),
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (i) => setState(() => _index = i),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.list_alt), label: 'Status'),
          NavigationDestination(icon: Icon(Icons.badge), label: 'Scan Pengawas'),
          NavigationDestination(icon: Icon(Icons.security), label: 'Scan Security'),
        ],
      ),
    );
  }
}
