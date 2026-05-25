import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';
import 'verification_service.dart';

class CRUDLogPage extends StatefulWidget {
  const CRUDLogPage({super.key});

  @override
  State<CRUDLogPage> createState() => _CRUDLogPageState();
}

class _CRUDLogPageState extends State<CRUDLogPage> {
  List<Map<String, dynamic>> _logs = [];
  bool _isLoading = true;
  final _idController = TextEditingController();
  final _pengawasController = TextEditingController();
  final _securityController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadLogs();
  }

  @override
  void dispose() {
    _idController.dispose();
    _pengawasController.dispose();
    _securityController.dispose();
    super.dispose();
  }

  Future<void> _loadLogs() async {
    setState(() => _isLoading = true);
    try {
      final logs = await VerificationService.fetchLogs();
      if (mounted) {
        setState(() {
          _logs = logs;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  void _resetForm() {
    _idController.clear();
    _pengawasController.text = 'pending';
    _securityController.text = 'pending';
  }

  String _extractEmployeeInfo(String fullBarcode) {
    try {
      final nama = _extractValue(fullBarcode, 'Nama');
      final pin = _extractValue(fullBarcode, 'PIN');
      final bagian = _extractValue(fullBarcode, 'Bagian');
      if (nama.isNotEmpty && pin.isNotEmpty) {
        String result = '$nama (PIN: $pin)';
        if (bagian.isNotEmpty) result += ' - $bagian';
        return result;
      }
      return fullBarcode;
    } catch (_) {
      return fullBarcode;
    }
  }

  String _extractValue(String barcode, String key) {
    try {
      final parts = barcode.split('|').map((p) => p.trim()).toList();
      for (final part in parts) {
        if (part.startsWith('$key:')) {
          return part.substring(key.length + 1).trim();
        }
      }
    } catch (_) {}
    return '';
  }

  void _showFormDialog({Map<String, dynamic>? log}) {
    final isEdit = log != null;
    if (isEdit) {
      _idController.text = log['id_karyawan'] ?? '';
      _pengawasController.text = log['status_pengawas'] ?? 'pending';
      _securityController.text = log['status_security'] ?? 'pending';
    } else {
      _resetForm();
    }

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(isEdit ? 'Edit Log' : 'Tambah Log'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: _idController,
                decoration: const InputDecoration(labelText: 'ID Karyawan'),
                enabled: !isEdit,
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                initialValue: _pengawasController.text,
                decoration: const InputDecoration(labelText: 'Status Pengawas'),
                items: ['pending', 'approved']
                    .map((s) => DropdownMenuItem(value: s, child: Text(s)))
                    .toList(),
                onChanged: (v) => _pengawasController.text = v ?? 'pending',
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                initialValue: _securityController.text,
                decoration: const InputDecoration(labelText: 'Status Security'),
                items: ['pending', 'approved']
                    .map((s) => DropdownMenuItem(value: s, child: Text(s)))
                    .toList(),
                onChanged: (v) => _securityController.text = v ?? 'pending',
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Batal'),
          ),
          ElevatedButton(
            onPressed: () async {
              final dialogNavigator = Navigator.of(ctx);
              final messenger = ScaffoldMessenger.of(context);
              try {
                if (isEdit) {
                  await VerificationService.updateLogStatus(
                    _idController.text,
                    _pengawasController.text,
                    _securityController.text,
                  );
                } else {
                  await VerificationService.createLog(
                    _idController.text,
                    _pengawasController.text,
                    _securityController.text,
                  );
                }
                if (!mounted) return;
                dialogNavigator.pop();
                await _loadLogs();
                if (!mounted) return;
                messenger.showSnackBar(
                  SnackBar(
                    content: Text(
                      isEdit ? 'Log diperbarui' : 'Log ditambahkan',
                    ),
                    backgroundColor: AppColors.success,
                  ),
                );
              } catch (e) {
                if (!mounted) return;
                messenger.showSnackBar(
                  SnackBar(
                    content: Text('Error: $e'),
                    backgroundColor: AppColors.error,
                  ),
                );
              }
            },
            child: Text(isEdit ? 'Update' : 'Simpan'),
          ),
        ],
      ),
    );
  }

  Future<void> _deleteLog(String idKaryawan) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Hapus Log'),
        content: const Text('Yakin ingin menghapus log ini?'),
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
      try {
        await VerificationService.deleteLog(idKaryawan);
        _loadLogs();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Log dihapus'),
              backgroundColor: AppColors.success,
            ),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Error: $e'),
              backgroundColor: AppColors.error,
            ),
          );
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Kelola Data Log'),
        actions: [
          IconButton(onPressed: _loadLogs, icon: const Icon(Icons.refresh)),
          IconButton(
            onPressed: () => _showFormDialog(),
            icon: const Icon(Icons.add),
          ),
        ],
      ),
      body: _isLoading
          ? const Center(
              child: CircularProgressIndicator(color: AppColors.primary),
            )
          : _logs.isEmpty
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.inbox, size: 48, color: AppColors.textHint),
                  const SizedBox(height: 8),
                  const Text(
                    'Tidak ada data',
                    style: TextStyle(color: AppColors.textSecondary),
                  ),
                ],
              ),
            )
          : ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: _logs.length,
              itemBuilder: (context, index) {
                final log = _logs[index];
                final id = log['id_karyawan'] ?? '';
                final info = _extractEmployeeInfo(id);
                final statusP = log['status_pengawas'] ?? 'pending';
                final statusS = log['status_security'] ?? 'pending';

                return Container(
                  margin: const EdgeInsets.only(bottom: 8),
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: AppColors.surface,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: AppColors.cardBorder),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        info,
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: AppColors.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          _buildStatusBadge('Pengawas', statusP),
                          const SizedBox(width: 8),
                          _buildStatusBadge('Security', statusS),
                          const Spacer(),
                          IconButton(
                            icon: const Icon(Icons.edit, size: 18),
                            onPressed: () => _showFormDialog(log: log),
                            color: AppColors.info,
                          ),
                          IconButton(
                            icon: const Icon(Icons.delete, size: 18),
                            onPressed: () => _deleteLog(id),
                            color: AppColors.error,
                          ),
                        ],
                      ),
                    ],
                  ),
                );
              },
            ),
    );
  }

  Widget _buildStatusBadge(String label, String status) {
    final isApproved = status == 'approved';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: (isApproved ? AppColors.success : AppColors.warning).withAlpha(
          20,
        ),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            isApproved ? Icons.check_circle : Icons.pending,
            size: 12,
            color: isApproved ? AppColors.success : AppColors.warning,
          ),
          const SizedBox(width: 4),
          Text(
            '$label: $status',
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w600,
              color: isApproved ? AppColors.success : AppColors.warning,
            ),
          ),
        ],
      ),
    );
  }
}
