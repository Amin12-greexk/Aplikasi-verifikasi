import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import '../../core/config/config.dart';
import '../../core/theme/app_colors.dart';

class UserManagementPage extends StatefulWidget {
  const UserManagementPage({super.key});

  @override
  State<UserManagementPage> createState() => _UserManagementPageState();
}

class _UserManagementPageState extends State<UserManagementPage> {
  bool _isLoading = true;
  List<dynamic> _users = [];
  String? _error;

  @override
  void initState() {
    super.initState();
    _fetchUsers();
  }

  Future<void> _fetchUsers() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final response = await http.get(
        Uri.parse('${ServerConfig.baseUrl}/admin/users'),
        headers: {'Content-Type': 'application/json'},
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        setState(() {
          _users = data['users'] ?? [];
          _isLoading = false;
        });
      } else {
        throw Exception('Gagal mengambil daftar user');
      }
    } catch (e) {
      setState(() {
        _error = e.toString();
        _isLoading = false;
      });
    }
  }

  Future<void> _showUserDialog([Map<String, dynamic>? user]) async {
    final isEditing = user != null;
    final usernameController = TextEditingController(
      text: user?['username'] ?? '',
    );
    final passwordController = TextEditingController();
    String selectedRole = user?['role'] ?? 'pengawas';

    final result = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text(isEditing ? 'Edit User' : 'Tambah User Baru'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (!isEditing)
                  TextField(
                    controller: usernameController,
                    decoration: const InputDecoration(labelText: 'Username'),
                  ),
                TextField(
                  controller: passwordController,
                  decoration: InputDecoration(
                    labelText: isEditing ? 'Password Baru (wajib)' : 'Password',
                  ),
                  obscureText: true,
                ),
                const SizedBox(height: 16),
                const Text(
                  'Pilih Role:',
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                ),
                DropdownButton<String>(
                  value: selectedRole,
                  isExpanded: true,
                  items: const [
                    DropdownMenuItem(
                      value: 'pengawas',
                      child: Text('Pengawas'),
                    ),
                    DropdownMenuItem(
                      value: 'security',
                      child: Text('Security'),
                    ),
                    DropdownMenuItem(value: 'manager', child: Text('Manager')),
                  ],
                  onChanged: (val) {
                    if (val != null) setDialogState(() => selectedRole = val);
                  },
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Batal'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: Text(isEditing ? 'Simpan' : 'Tambah'),
            ),
          ],
        ),
      ),
    );

    if (!mounted) {
      usernameController.dispose();
      passwordController.dispose();
      return;
    }

    if (result == true) {
      final username = usernameController.text.trim();
      final password = passwordController.text.trim();
      usernameController.dispose();
      passwordController.dispose();

      if (password.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Password tidak boleh kosong')),
        );
        return;
      }

      try {
        final url = isEditing
            ? '${ServerConfig.baseUrl}/admin/users/${user['id']}'
            : '${ServerConfig.baseUrl}/admin/users';

        final response = await (isEditing
            ? http.put(
                Uri.parse(url),
                headers: {'Content-Type': 'application/json'},
                body: jsonEncode({'password': password, 'role': selectedRole}),
              )
            : http.post(
                Uri.parse(url),
                headers: {'Content-Type': 'application/json'},
                body: jsonEncode({
                  'username': username,
                  'password': password,
                  'role': selectedRole,
                }),
              ));

        if (response.statusCode == 200) {
          if (!mounted) return;
          await _fetchUsers();
          if (!mounted) return;
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                  isEditing
                      ? 'User berhasil diupdate'
                      : 'User berhasil ditambah',
                ),
              ),
            );
          }
        } else {
          final err = jsonDecode(response.body);
          throw Exception(err['error'] ?? 'Gagal memproses user');
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text('Error: $e')));
        }
      }
    } else {
      usernameController.dispose();
      passwordController.dispose();
    }
  }

  Future<void> _deleteUser(int id, String username) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Hapus User'),
        content: Text('Apakah Anda yakin ingin menghapus user "$username"?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Batal'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Hapus', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );

    if (confirm == true) {
      try {
        final response = await http.delete(
          Uri.parse('${ServerConfig.baseUrl}/admin/users/$id'),
          headers: {'Content-Type': 'application/json'},
        );

        if (response.statusCode == 200) {
          if (!mounted) return;
          await _fetchUsers();
        } else {
          throw Exception('Gagal menghapus user');
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text('Error: $e')));
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Manajemen Akun')),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
          ? Center(child: Text('Error: $_error'))
          : ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: _users.length,
              itemBuilder: (context, index) {
                final user = _users[index];
                final role = user['role']?.toString() ?? '';
                final roleColor = role == 'manager'
                    ? AppColors.manager
                    : (role == 'pengawas'
                          ? AppColors.pengawas
                          : AppColors.security);

                return Card(
                  margin: const EdgeInsets.only(bottom: 12),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: ListTile(
                    leading: CircleAvatar(
                      backgroundColor: roleColor.withAlpha(30),
                      child: Icon(
                        role == 'manager'
                            ? Icons.stars
                            : (role == 'pengawas'
                                  ? Icons.badge
                                  : Icons.security),
                        color: roleColor,
                      ),
                    ),
                    title: Text(
                      user['username'] ?? '',
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    subtitle: Text('Role: ${role.toUpperCase()}'),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          icon: const Icon(Icons.edit, color: Colors.blue),
                          onPressed: () => _showUserDialog(user),
                        ),
                        IconButton(
                          icon: const Icon(Icons.delete, color: Colors.red),
                          onPressed: () =>
                              _deleteUser(user['id'], user['username']),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _showUserDialog(),
        icon: const Icon(Icons.person_add),
        label: const Text('Tambah Akun'),
        backgroundColor: AppColors.manager,
      ),
    );
  }
}
