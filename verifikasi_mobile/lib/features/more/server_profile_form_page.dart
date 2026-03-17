import 'package:flutter/material.dart';

import '../../core/config/server_profile.dart';
import '../../core/config/server_profile_manager.dart';
import '../../core/theme/app_colors.dart';

/// Form page for create/edit server profile.
class ServerProfileFormPage extends StatefulWidget {
  final ServerProfile? profile;

  const ServerProfileFormPage({super.key, this.profile});

  @override
  State<ServerProfileFormPage> createState() => _ServerProfileFormPageState();
}

class _ServerProfileFormPageState extends State<ServerProfileFormPage> {
  final _formKey = GlobalKey<FormState>();
  late TextEditingController _nameController;
  late TextEditingController _urlController;
  late List<String> _enabledModules;
  bool _isSaving = false;

  bool get isEdit => widget.profile != null;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.profile?.name ?? '');
    _urlController = TextEditingController(
      text: widget.profile?.baseUrl ?? 'https://',
    );
    _enabledModules = List.from(
      widget.profile?.enabledModules ?? ['verification', 'toilet', 'history'],
    );
  }

  @override
  void dispose() {
    _nameController.dispose();
    _urlController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isSaving = true);

    try {
      final profile = ServerProfile(
        id: widget.profile?.id ?? ServerProfileManager.generateId(),
        name: _nameController.text.trim(),
        baseUrl: _urlController.text.trim().replaceAll(RegExp(r'/+$'), ''),
        enabledModules: _enabledModules,
        isDefault: widget.profile?.isDefault ?? false,
      );

      if (isEdit) {
        await ServerProfileManager.updateProfile(profile);
      } else {
        await ServerProfileManager.addProfile(profile);
      }

      if (mounted) {
        Navigator.pop(context, true);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              isEdit ? 'Profile diperbarui' : 'Profile ditambahkan',
            ),
            backgroundColor: AppColors.success,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isSaving = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: $e'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(isEdit ? 'Edit Profile' : 'Tambah Profile')),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            // Name field
            const Text(
              'Nama Profile',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: AppColors.textSecondary,
              ),
            ),
            const SizedBox(height: 8),
            TextFormField(
              controller: _nameController,
              decoration: const InputDecoration(
                hintText: 'contoh: Development',
                prefixIcon: Icon(Icons.label_outline),
              ),
              validator: (v) => (v == null || v.trim().isEmpty)
                  ? 'Nama tidak boleh kosong'
                  : null,
            ),

            const SizedBox(height: 20),

            // URL field
            const Text(
              'Server URL',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: AppColors.textSecondary,
              ),
            ),
            const SizedBox(height: 8),
            TextFormField(
              controller: _urlController,
              decoration: const InputDecoration(
                hintText: 'https://example.com',
                prefixIcon: Icon(Icons.link),
              ),
              keyboardType: TextInputType.url,
              validator: (v) {
                if (v == null || v.trim().isEmpty) {
                  return 'URL tidak boleh kosong';
                }
                if (!v.startsWith('http://') && !v.startsWith('https://')) {
                  return 'URL harus dimulai dengan http:// atau https://';
                }
                return null;
              },
            ),

            const SizedBox(height: 24),

            // Enabled modules
            const Text(
              'Modul Aktif',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: AppColors.textSecondary,
              ),
            ),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: AppColors.cardBorder),
              ),
              child: Column(
                children: ServerProfile.allModules.map((module) {
                  final label = ServerProfile.moduleLabels[module] ?? module;
                  final isEnabled = _enabledModules.contains(module);
                  return CheckboxListTile(
                    dense: true,
                    title: Text(label, style: const TextStyle(fontSize: 14)),
                    value: isEnabled,
                    onChanged: (val) {
                      setState(() {
                        if (val == true) {
                          _enabledModules.add(module);
                        } else {
                          _enabledModules.remove(module);
                        }
                      });
                    },
                    activeColor: AppColors.primary,
                    controlAffinity: ListTileControlAffinity.leading,
                    contentPadding: EdgeInsets.zero,
                  );
                }).toList(),
              ),
            ),

            const SizedBox(height: 32),

            // Save button
            ElevatedButton(
              onPressed: _isSaving ? null : _save,
              child: _isSaving
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : Text(isEdit ? 'Simpan Perubahan' : 'Tambah Profile'),
            ),
          ],
        ),
      ),
    );
  }
}
