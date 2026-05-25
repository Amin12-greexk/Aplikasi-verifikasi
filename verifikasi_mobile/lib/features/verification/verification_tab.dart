import 'package:flutter/material.dart';

import '../../core/services/auth_service.dart';
import '../../core/theme/app_colors.dart';
import '../toilet/toilet_menu_page.dart';
import 'pulang_menu_page.dart';

/// Container widget for verification and toilet-permit flows.
class VerificationTab extends StatelessWidget {
  final bool isShellActive;

  const VerificationTab({super.key, required this.isShellActive});

  @override
  Widget build(BuildContext context) {
    final isSecurity = AuthService.isSecurity();

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _MainCard(
          title: isSecurity ? 'Gate Security' : 'Verifikasi Pulang',
          subtitle: isSecurity
              ? 'Mode self service untuk scan ID Card kepulangan.'
              : 'Scan tiket kepulangan & pantau status antrean pulang.',
          icon: isSecurity ? Icons.sensors : Icons.directions_walk,
          color: isSecurity ? AppColors.security : AppColors.primary,
          onTap: () {
            Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const PulangMenuPage()),
            );
          },
        ),
        const SizedBox(height: 16),
        _MainCard(
          title: isSecurity ? 'Gate Toilet' : 'Izin Toilet',
          subtitle: isSecurity
              ? 'Mode self service untuk proof scan izin toilet.'
              : 'Validasi izin ke toilet & pantau durasi izin aktif.',
          icon: isSecurity ? Icons.sensors : Icons.wc,
          color: AppColors.warning,
          onTap: () {
            Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const ToiletMenuPage()),
            );
          },
        ),
      ],
    );
  }
}

class _MainCard extends StatelessWidget {
  final String title;
  final String subtitle;
  final IconData icon;
  final Color color;
  final VoidCallback onTap;

  const _MainCard({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: AppColors.cardBorder),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.03),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.15),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(icon, size: 36, color: color),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Text(
                    title,
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textPrimary,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Text(
              subtitle,
              style: const TextStyle(
                fontSize: 14,
                color: AppColors.textSecondary,
                height: 1.4,
              ),
            ),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                Text(
                  'Buka Menu',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: color,
                  ),
                ),
                const SizedBox(width: 4),
                Icon(Icons.arrow_forward, size: 18, color: color),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
