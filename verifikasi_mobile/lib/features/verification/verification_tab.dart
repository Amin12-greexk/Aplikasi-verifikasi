import 'package:flutter/material.dart';

import '../../core/services/auth_service.dart';
import '../../core/theme/app_colors.dart';
import 'scanner_page.dart';
import 'status_page.dart';

/// Container widget for the Verifikasi tab.
/// Provides sub-tabs: Scanner and Status.
class VerificationTab extends StatefulWidget {
  const VerificationTab({super.key});

  @override
  State<VerificationTab> createState() => _VerificationTabState();
}

class _VerificationTabState extends State<VerificationTab>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isPengawas = AuthService.isPengawas();

    return Column(
      children: [
        Container(
          margin: const EdgeInsets.only(bottom: 12),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppColors.cardBorder),
          ),
          child: TabBar(
            controller: _tabController,
            labelColor: AppColors.primary,
            unselectedLabelColor: AppColors.textSecondary,
            indicatorColor: AppColors.primary,
            indicatorSize: TabBarIndicatorSize.tab,
            dividerHeight: 0,
            labelStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
            unselectedLabelStyle: const TextStyle(fontWeight: FontWeight.w500, fontSize: 13),
            tabs: const [
              Tab(
                icon: Icon(Icons.qr_code_scanner, size: 20),
                text: 'Scanner',
              ),
              Tab(
                icon: Icon(Icons.list_alt, size: 20),
                text: 'Status',
              ),
            ],
          ),
        ),
        Expanded(
          child: TabBarView(
            controller: _tabController,
            children: [
              ScannerTab(isPengawas: isPengawas),
              const StatusTab(),
            ],
          ),
        ),
      ],
    );
  }
}
