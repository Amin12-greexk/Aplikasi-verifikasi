import 'package:flutter/material.dart';

import '../../core/config/server_profile.dart';
import '../../core/config/server_profile_manager.dart';
import '../../core/network/base_api_client.dart';
import '../../core/theme/app_colors.dart';
import 'server_profile_form_page.dart';

/// Server Profiles management page.
class ServerProfilesPage extends StatefulWidget {
  const ServerProfilesPage({super.key});

  @override
  State<ServerProfilesPage> createState() => _ServerProfilesPageState();
}

class _ServerProfilesPageState extends State<ServerProfilesPage> {
  final Map<String, bool?> _connectionStatus = {};
  final Map<String, bool> _testingStatus = {};

  List<ServerProfile> get _profiles => ServerProfileManager.profiles;
  ServerProfile get _activeProfile => ServerProfileManager.activeProfile;

  Future<void> _testConnection(ServerProfile profile) async {
    setState(() => _testingStatus[profile.id] = true);
    final isOk = await BaseApiClient.checkConnectivity(url: profile.baseUrl);
    if (mounted) {
      setState(() {
        _connectionStatus[profile.id] = isOk;
        _testingStatus[profile.id] = false;
      });
    }
  }

  Future<void> _setActive(ServerProfile profile) async {
    await ServerProfileManager.setActive(profile.id);
    setState(() {});
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Server aktif: ${profile.name}'),
          backgroundColor: AppColors.success,
        ),
      );
    }
  }

  Future<void> _deleteProfile(ServerProfile profile) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Hapus Profile'),
        content: Text('Hapus profile "${profile.name}"?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Batal'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.error),
            child: const Text('Hapus'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      final success = await ServerProfileManager.deleteProfile(profile.id);
      if (mounted) {
        if (success) {
          setState(() {});
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Profile dihapus'),
              backgroundColor: AppColors.success,
            ),
          );
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Tidak bisa menghapus profile default / aktif'),
              backgroundColor: AppColors.error,
            ),
          );
        }
      }
    }
  }

  Future<void> _openForm({ServerProfile? profile}) async {
    final result = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => ServerProfileFormPage(profile: profile),
      ),
    );
    if (result == true && mounted) {
      setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Server Profiles'),
        actions: [
          IconButton(onPressed: () => _openForm(), icon: const Icon(Icons.add)),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Active profile banner
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: AppColors.primaryGradient,
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Row(
              children: [
                const Icon(Icons.dns, color: Colors.white, size: 22),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Server Aktif',
                        style: TextStyle(fontSize: 11, color: Colors.white70),
                      ),
                      Text(
                        _activeProfile.name,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          color: Colors.white,
                        ),
                      ),
                      Text(
                        _activeProfile.baseUrl,
                        style: const TextStyle(
                          fontSize: 11,
                          color: Colors.white70,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 20),

          const Text(
            'Semua Profiles',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: AppColors.textSecondary,
            ),
          ),
          const SizedBox(height: 10),

          ..._profiles.map((profile) => _buildProfileCard(profile)),
        ],
      ),
    );
  }

  Widget _buildProfileCard(ServerProfile profile) {
    final isActive = profile.id == _activeProfile.id;
    final isTesting = _testingStatus[profile.id] == true;
    final connectionOk = _connectionStatus[profile.id];

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isActive ? AppColors.primary : AppColors.cardBorder,
          width: isActive ? 2 : 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.dns,
                size: 18,
                color: isActive ? AppColors.primary : AppColors.textSecondary,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  profile.name,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: isActive ? AppColors.primary : AppColors.textPrimary,
                  ),
                ),
              ),
              if (isActive)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.primary.withAlpha(20),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: const Text(
                    'Aktif',
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                      color: AppColors.primary,
                    ),
                  ),
                ),
              if (profile.isDefault)
                Padding(
                  padding: const EdgeInsets.only(left: 6),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 3,
                    ),
                    decoration: BoxDecoration(
                      color: AppColors.textHint.withAlpha(20),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: const Text(
                      'Default',
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w500,
                        color: AppColors.textHint,
                      ),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            profile.baseUrl,
            style: const TextStyle(
              fontSize: 12,
              color: AppColors.textSecondary,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Modul: ${profile.enabledModules.map((m) => ServerProfile.moduleLabels[m] ?? m).join(", ")}',
            style: const TextStyle(fontSize: 11, color: AppColors.textHint),
          ),

          // Connection status
          if (connectionOk != null) ...[
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: connectionOk
                    ? AppColors.success.withAlpha(15)
                    : AppColors.error.withAlpha(15),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    connectionOk ? Icons.check_circle : Icons.error,
                    size: 12,
                    color: connectionOk ? AppColors.success : AppColors.error,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    connectionOk ? 'Koneksi berhasil' : 'Koneksi gagal',
                    style: TextStyle(
                      fontSize: 11,
                      color: connectionOk ? AppColors.success : AppColors.error,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
          ],

          const SizedBox(height: 10),

          // Actions
          Row(
            children: [
              _actionButton(
                icon: isTesting ? null : Icons.wifi_find,
                label: isTesting ? 'Testing...' : 'Test',
                onTap: isTesting ? null : () => _testConnection(profile),
                isLoading: isTesting,
              ),
              const SizedBox(width: 8),
              if (!isActive)
                _actionButton(
                  icon: Icons.check_circle_outline,
                  label: 'Aktifkan',
                  onTap: () => _setActive(profile),
                  color: AppColors.primary,
                ),
              if (!isActive) const SizedBox(width: 8),
              _actionButton(
                icon: Icons.edit,
                label: 'Edit',
                onTap: () => _openForm(profile: profile),
              ),
              if (!profile.isDefault && !isActive) ...[
                const SizedBox(width: 8),
                _actionButton(
                  icon: Icons.delete,
                  label: 'Hapus',
                  onTap: () => _deleteProfile(profile),
                  color: AppColors.error,
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }

  Widget _actionButton({
    IconData? icon,
    required String label,
    VoidCallback? onTap,
    Color color = AppColors.textSecondary,
    bool isLoading = false,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: color.withAlpha(10),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: color.withAlpha(30)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (isLoading)
              SizedBox(
                width: 12,
                height: 12,
                child: CircularProgressIndicator(strokeWidth: 2, color: color),
              )
            else if (icon != null)
              Icon(icon, size: 14, color: color),
            const SizedBox(width: 4),
            Text(
              label,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w500,
                color: color,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
