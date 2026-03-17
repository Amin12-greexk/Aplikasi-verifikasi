import 'package:flutter/material.dart';

import '../../core/services/auth_service.dart';
import '../../core/theme/app_colors.dart';
import '../toilet/toilet_scanner_page.dart';
import '../toilet/toilet_status_page.dart';
import 'scanner_page.dart';
import 'status_page.dart';

/// Container widget for verification and toilet-permit flows.
class VerificationTab extends StatefulWidget {
  final bool isShellActive;

  const VerificationTab({super.key, required this.isShellActive});

  @override
  State<VerificationTab> createState() => _VerificationTabState();
}

class _VerificationTabState extends State<VerificationTab>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  int _activeTabIndex = 0;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
    _tabController.addListener(_handleTabChange);
  }

  void _handleTabChange() {
    if (!mounted) return;
    final nextIndex = _tabController.index;
    if (_activeTabIndex != nextIndex) {
      setState(() => _activeTabIndex = nextIndex);
    }
  }

  @override
  void dispose() {
    _tabController.removeListener(_handleTabChange);
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
            isScrollable: true,
            labelColor: AppColors.primary,
            unselectedLabelColor: AppColors.textSecondary,
            indicatorColor: AppColors.primary,
            indicatorSize: TabBarIndicatorSize.tab,
            dividerHeight: 0,
            labelStyle: const TextStyle(
              fontWeight: FontWeight.w600,
              fontSize: 13,
            ),
            unselectedLabelStyle: const TextStyle(
              fontWeight: FontWeight.w500,
              fontSize: 13,
            ),
            tabs: const [
              Tab(
                icon: Icon(Icons.qr_code_scanner, size: 20),
                text: 'Pulang Scan',
              ),
              Tab(icon: Icon(Icons.list_alt, size: 20), text: 'Pulang Status'),
              Tab(icon: Icon(Icons.wc, size: 20), text: 'Toilet Scan'),
              Tab(icon: Icon(Icons.timer, size: 20), text: 'Toilet Status'),
            ],
          ),
        ),
        Expanded(
          child: TabBarView(
            controller: _tabController,
            children: [
              ScannerTab(
                isPengawas: isPengawas,
                isActive: widget.isShellActive && _activeTabIndex == 0,
              ),
              const StatusTab(),
              ToiletScannerTab(
                isPengawas: isPengawas,
                isActive: widget.isShellActive && _activeTabIndex == 2,
              ),
              const ToiletStatusTab(),
            ],
          ),
        ),
      ],
    );
  }
}
