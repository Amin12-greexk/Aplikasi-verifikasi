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
  int? _selectedRoomId;
  String? _editingUserId;

  static const Color primaryColor = Color(0xFF059669);
  static const Color bgColor = Color(0xFFF3F4F6);
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

  void _resetForm() {
    _usernameController.clear();
    _passwordController.clear();
    _selectedRole = 'pengawas';
    _selectedRoomId = null;
    _editingUserId = null;
  }

  void _showUserDialog({Map<String, Object?>? user}) {
    if (user != null) {
      _editingUserId = user['id'].toString();
      _usernameController.text = user['username'] as String;
      _passwordController.clear();
      _selectedRole = user['role'] as String;
      _selectedRoomId = user['room_id'] as int?;
    } else {
      _resetForm();
    }

    final rooms = widget.db.select('SELECT id, name FROM rooms ORDER BY name ASC');

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: Text(_editingUserId != null ? 'Edit User' : 'Tambah User Baru'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _buildModernTextField(controller: _usernameController, label: 'Username', icon: Icons.person_outline, enabled: _editingUserId == null),
                const SizedBox(height: 16),
                _buildModernTextField(controller: _passwordController, label: 'Password', icon: Icons.lock_outline, isObscure: true, hint: _editingUserId != null ? 'Kosongkan jika tidak ubah' : null),
                const SizedBox(height: 16),
                DropdownButtonFormField<String>(
                  value: _selectedRole,
                  decoration: const InputDecoration(labelText: 'Role', border: OutlineInputBorder()),
                  items: ['pengawas', 'security', 'manager', 'admin'].map((e) => DropdownMenuItem(value: e, child: Text(e.toUpperCase()))).toList(),
                  onChanged: (val) {
                    if (val != null) setDialogState(() => _selectedRole = val);
                  },
                ),
                if (_selectedRole == 'pengawas') ...[
                  const SizedBox(height: 16),
                  DropdownButtonFormField<int>(
                    value: _selectedRoomId,
                    decoration: const InputDecoration(labelText: 'Pilih Ruangan', border: OutlineInputBorder()),
                    items: rooms.map((r) => DropdownMenuItem(value: r['id'] as int, child: Text(r['name'] as String))).toList(),
                    onChanged: (val) => setDialogState(() => _selectedRoomId = val),
                    hint: const Text('Tugaskan ke Ruangan'),
                  ),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: const Text('Batal')),
            ElevatedButton(onPressed: () => _handleSaveUser(context), child: const Text('Simpan')),
          ],
        ),
      ),
    );
  }

  void _handleSaveUser(BuildContext dialogContext) {
    if (_usernameController.text.isEmpty) return;
    if (_selectedRole == 'pengawas' && _selectedRoomId == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Pengawas harus memiliki ruangan')));
      return;
    }

    try {
      if (_editingUserId != null) {
        if (_passwordController.text.isNotEmpty) {
          widget.db.execute('UPDATE users SET password=?, role=?, room_id=? WHERE id=?', [_passwordController.text, _selectedRole, _selectedRoomId, _editingUserId]);
        } else {
          widget.db.execute('UPDATE users SET role=?, room_id=? WHERE id=?', [_selectedRole, _selectedRoomId, _editingUserId]);
        }
      } else {
        widget.db.execute('INSERT INTO users(username, password, role, room_id) VALUES(?, ?, ?, ?)', [_usernameController.text, _passwordController.text, _selectedRole, _selectedRoomId]);
      }
      setState(() {});
      Navigator.pop(dialogContext);
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
    }
  }

  Widget _buildModernTextField({required TextEditingController controller, required String label, required IconData icon, bool isObscure = false, bool enabled = true, String? hint}) {
    return TextField(
      controller: controller,
      obscureText: isObscure,
      enabled: enabled,
      decoration: InputDecoration(labelText: label, hintText: hint, prefixIcon: Icon(icon), border: const OutlineInputBorder()),
    );
  }

  @override
  Widget build(BuildContext context) {
    final users = widget.db.select('SELECT u.*, r.name as room_name FROM users u LEFT JOIN rooms r ON u.room_id = r.id ORDER BY u.id DESC');
    return Scaffold(
      backgroundColor: bgColor,
      appBar: AppBar(title: const Text('User Management'), backgroundColor: Colors.white, foregroundColor: Colors.black),
      body: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: users.length,
        itemBuilder: (context, i) {
          final u = users[i];
          return Card(
            child: ListTile(
              leading: CircleAvatar(child: Text(u['username'].toString().substring(0, 1).toUpperCase())),
              title: Text(u['username'] as String, style: const TextStyle(fontWeight: FontWeight.bold)),
              subtitle: Text('Role: ${u['role']} ${u['room_name'] != null ? '| Ruang: ${u['room_name']}' : ''}'),
              trailing: IconButton(icon: const Icon(Icons.delete, color: Colors.red), onPressed: () {
                widget.db.execute('DELETE FROM users WHERE id=?', [u['id']]);
                setState(() {});
              }),
              onTap: () => _showUserDialog(user: u),
            ),
          );
        },
      ),
      floatingActionButton: FloatingActionButton(onPressed: () => _showUserDialog(), backgroundColor: primaryColor, child: const Icon(Icons.add)),
    );
  }
}
