import 'package:flutter/material.dart';
import 'package:sqlite3/sqlite3.dart' hide Row;

class UserManagementPage extends StatefulWidget {
  final Database db;

  const UserManagementPage({required this.db, super.key});

  @override
  State<UserManagementPage> createState() => _UserManagementPageState();
}

class _UserManagementPageState extends State<UserManagementPage> {
  late TextEditingController _usernameController;
  late TextEditingController _passwordController;
  String _selectedRole = 'pengawas';
  String? _editingUserId;

  // Warna Tema Konsisten
  static const Color primaryColor = Color(0xFF059669); // Emerald 600
  static const Color bgColor = Color(0xFFF3F4F6); // Cool Gray 100
  static const Color surfaceColor = Colors.white;

  @override
  void initState() {
    super.initState();
    _usernameController = TextEditingController();
    _passwordController = TextEditingController();
  }

  @override
  void dispose() {
    _usernameController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  // --- Logic Database & Form (Sama, dengan sedikit styling) ---

  void _resetForm() {
    _usernameController.clear();
    _passwordController.clear();
    _selectedRole = 'pengawas';
    _editingUserId = null;
  }

  void _showUserDialog({Map<String, Object?>? user}) {
    if (user != null) {
      _editingUserId = user['id'].toString();
      _usernameController.text = user['username'] as String;
      _passwordController.clear();
      _selectedRole = user['role'] as String;
    } else {
      _resetForm();
    }

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text(
          _editingUserId != null ? 'Edit User' : 'Tambah User Baru',
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _buildModernTextField(
                controller: _usernameController,
                label: 'Username',
                icon: Icons.person_outline,
                enabled: _editingUserId == null,
              ),
              const SizedBox(height: 16),
              _buildModernTextField(
                controller: _passwordController,
                label: 'Password',
                icon: Icons.lock_outline,
                isObscure: true,
                hint: _editingUserId != null
                    ? 'Kosongkan jika tidak ingin mengubah'
                    : null,
              ),
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.grey.shade50,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.grey.shade300),
                ),
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<String>(
                    value: _selectedRole,
                    isExpanded: true,
                    icon: const Icon(Icons.keyboard_arrow_down_rounded),
                    items: ['pengawas', 'security'].map((e) {
                      return DropdownMenuItem(
                        value: e,
                        child: Row(
                          children: [
                            Icon(
                              e == 'pengawas'
                                  ? Icons.admin_panel_settings_outlined
                                  : Icons.security_outlined,
                              size: 18,
                              color: e == 'pengawas'
                                  ? Colors.blue.shade600
                                  : Colors.green.shade600,
                            ),
                            const SizedBox(width: 12),
                            Text(
                              e.toUpperCase(),
                              style: const TextStyle(fontWeight: FontWeight.w600),
                            ),
                          ],
                        ),
                      );
                    }).toList(),
                    onChanged: (val) {
                      if (val != null) setState(() => _selectedRole = val);
                    },
                  ),
                ),
              ),
            ],
          ),
        ),
        actionsPadding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
        actions: [
          TextButton(
            onPressed: () {
              _resetForm();
              Navigator.pop(context);
            },
            child: Text('Batal', style: TextStyle(color: Colors.grey.shade600)),
          ),
          ElevatedButton(
            onPressed: _handleSaveUser,
            style: ElevatedButton.styleFrom(
              backgroundColor: primaryColor,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
            ),
            child: Text(
              _editingUserId != null ? 'Simpan Perubahan' : 'Tambah User',
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
    );
  }

  void _handleSaveUser() {
    if (_usernameController.text.isEmpty) {
      _showSnack('Username wajib diisi', isError: true);
      return;
    }
    if (_editingUserId == null && _passwordController.text.isEmpty) {
      _showSnack('Password wajib diisi untuk user baru', isError: true);
      return;
    }

    try {
      if (_editingUserId != null) {
        // Update logic
        if (_passwordController.text.isNotEmpty) {
          widget.db.execute(
            'UPDATE users SET password=?, role=? WHERE id=?',
            [_passwordController.text, _selectedRole, _editingUserId],
          );
        } else {
          widget.db.execute(
            'UPDATE users SET role=? WHERE id=?',
            [_selectedRole, _editingUserId],
          );
        }
        _showSnack('Data user berhasil diperbarui');
      } else {
        // Insert logic
        widget.db.execute(
          'INSERT INTO users(username, password, role) VALUES(?, ?, ?)',
          [_usernameController.text, _passwordController.text, _selectedRole],
        );
        _showSnack('User baru berhasil ditambahkan');
      }
      _resetForm();
      setState(() {});
      Navigator.pop(context);
    } catch (e) {
      _showSnack('Database Error: $e', isError: true);
    }
  }

  void _deleteUser(int id, String username) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('Hapus User?'),
        content: Text('Anda yakin ingin menghapus akses untuk "$username"?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('Batal', style: TextStyle(color: Colors.grey.shade600)),
          ),
          ElevatedButton(
            onPressed: () {
              try {
                widget.db.execute('DELETE FROM users WHERE id=?', [id]);
                _showSnack('User dihapus');
                setState(() {});
                Navigator.pop(context);
              } catch (e) {
                _showSnack('Error: $e', isError: true);
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red.shade600,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            child: const Text('Hapus Akses'),
          ),
        ],
      ),
    );
  }

  void _showSnack(String msg, {bool isError = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: isError ? Colors.red.shade600 : primaryColor,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );
  }

  // --- UI Widget Builders ---

  Widget _buildModernTextField({
    required TextEditingController controller,
    required String label,
    required IconData icon,
    bool isObscure = false,
    bool enabled = true,
    String? hint,
  }) {
    return TextField(
      controller: controller,
      obscureText: isObscure,
      enabled: enabled,
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        hintStyle: TextStyle(fontSize: 12, color: Colors.grey.shade400),
        prefixIcon: Icon(icon, color: Colors.grey.shade400),
        filled: true,
        fillColor: enabled ? Colors.grey.shade50 : Colors.grey.shade200,
        contentPadding: const EdgeInsets.symmetric(vertical: 16, horizontal: 16),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: Colors.grey.shade300),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: primaryColor),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // Query data setiap kali build (bisa dioptimasi dengan FutureBuilder jika data besar)
    final users = widget.db.select(
      'SELECT id, username, role, created_at FROM users ORDER BY id DESC',
    );

    return Scaffold(
      backgroundColor: bgColor,
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            expandedHeight: 120.0,
            floating: false,
            pinned: true,
            backgroundColor: surfaceColor,
            elevation: 0,
            leading: IconButton(
              icon: const Icon(Icons.arrow_back_ios_new_rounded,
                  color: Colors.black87),
              onPressed: () => Navigator.pop(context),
            ),
            flexibleSpace: FlexibleSpaceBar(
              centerTitle: false,
              titlePadding: const EdgeInsets.only(left: 20, bottom: 16),
              title: const Text(
                'User Management',
                style: TextStyle(
                  color: Colors.black87,
                  fontWeight: FontWeight.bold,
                  fontSize: 18,
                ),
              ),
              background: Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [Colors.white, Colors.grey.shade50],
                  ),
                ),
              ),
            ),
          ),
          if (users.isEmpty)
            SliverFillRemaining(
              child: _buildEmptyState(),
            )
          else
            SliverPadding(
              padding: const EdgeInsets.all(20),
              sliver: SliverList(
                delegate: SliverChildBuilderDelegate(
                  (context, index) {
                    final user = users[index];
                    return _buildUserCard(user, index);
                  },
                  childCount: users.length,
                ),
              ),
            ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _showUserDialog(),
        backgroundColor: primaryColor,
        icon: const Icon(Icons.add_rounded),
        label: const Text('Tambah User'),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: Colors.grey.shade200,
              shape: BoxShape.circle,
            ),
            child: Icon(Icons.people_alt_outlined,
                size: 64, color: Colors.grey.shade400),
          ),
          const SizedBox(height: 24),
          Text(
            'Belum ada user',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w600,
              color: Colors.grey.shade600,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Tambahkan user untuk memberi akses sistem',
            style: TextStyle(color: Colors.grey.shade500),
          ),
        ],
      ),
    );
  }

  Widget _buildUserCard(Map<String, Object?> user, int index) {
    final id = user['id'];
    final username = user['username'] as String;
    final role = user['role'] as String;
    final isPengawas = role == 'pengawas';

    // Warna untuk badge role
    final roleColor = isPengawas ? Colors.blue.shade700 : Colors.green.shade700;
    final roleBg = isPengawas ? Colors.blue.shade50 : Colors.green.shade50;
    final roleIcon =
        isPengawas ? Icons.admin_panel_settings : Icons.security_rounded;

    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: Duration(milliseconds: 300 + (index * 100).clamp(0, 800)),
      curve: Curves.easeOutBack,
      builder: (context, value, child) {
        return Transform.scale(
          scale: value,
          child: Opacity(opacity: value, child: child),
        );
      },
      child: Container(
        margin: const EdgeInsets.only(bottom: 16),
        decoration: BoxDecoration(
          color: surfaceColor,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.04),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Material(
          color: Colors.transparent,
          borderRadius: BorderRadius.circular(16),
          child: InkWell(
            borderRadius: BorderRadius.circular(16),
            onTap: () => _showUserDialog(user: user),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  // Avatar Inisial
                  Container(
                    width: 56,
                    height: 56,
                    decoration: BoxDecoration(
                      color: roleBg,
                      shape: BoxShape.circle,
                    ),
                    child: Center(
                      child: Text(
                        username.substring(0, 1).toUpperCase(),
                        style: TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                          color: roleColor,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 16),
                  
                  // Info User
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          username,
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: Colors.black87,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(
                            color: roleBg,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                                color: roleColor.withOpacity(0.2)),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(roleIcon, size: 12, color: roleColor),
                              const SizedBox(width: 6),
                              Text(
                                role.toUpperCase(),
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w700,
                                  color: roleColor,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),

                  // Action Button
                  IconButton(
                    icon: Icon(Icons.delete_outline_rounded,
                        color: Colors.red.shade400),
                    onPressed: () => _deleteUser(id as int, username),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}