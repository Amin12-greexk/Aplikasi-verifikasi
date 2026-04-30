import 'package:flutter/material.dart';

import 'remote_api_service.dart';

class RemoteUserManagementPage extends StatefulWidget {
  const RemoteUserManagementPage({required this.api, super.key});

  final RemoteApiService api;

  @override
  State<RemoteUserManagementPage> createState() =>
      _RemoteUserManagementPageState();
}

class _RemoteUserManagementPageState extends State<RemoteUserManagementPage> {
  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _users = <Map<String, dynamic>>[];
  List<Map<String, dynamic>> _rooms = <Map<String, dynamic>>[];

  @override
  void initState() {
    super.initState();
    _loadUsers();
  }

  Future<void> _loadUsers() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final users = await widget.api.fetchUsers();
      final rooms = await widget.api.fetchRooms();
      if (!mounted) return;
      setState(() {
        _users = users;
        _rooms = rooms;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
      });
    } finally {
      if (mounted) {
        setState(() {
          _loading = false;
        });
      }
    }
  }

  void _showSnack(String message, {bool isError = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError ? Colors.red.shade600 : Colors.green.shade600,
      ),
    );
  }

  Future<void> _showCreateDialog() async {
    final usernameController = TextEditingController();
    final passwordController = TextEditingController();
    var role = 'pengawas';
    int? roomId;

    await showDialog<void>(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: const Text('Tambah User'),
              content: SizedBox(
                width: 360,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(
                      controller: usernameController,
                      decoration: const InputDecoration(labelText: 'Username'),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: passwordController,
                      obscureText: true,
                      decoration: const InputDecoration(labelText: 'Password'),
                    ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<String>(
                      initialValue: role,
                      items: const [
                        DropdownMenuItem(
                          value: 'pengawas',
                          child: Text('Pengawas'),
                        ),
                        DropdownMenuItem(
                          value: 'security',
                          child: Text('Security'),
                        ),
                        DropdownMenuItem(
                          value: 'manager',
                          child: Text('Manager'),
                        ),
                        DropdownMenuItem(value: 'admin', child: Text('Admin')),
                      ],
                      onChanged: (value) {
                        if (value != null) {
                          setDialogState(() {
                            role = value;
                            if (role != 'pengawas') roomId = null;
                          });
                        }
                      },
                      decoration: const InputDecoration(labelText: 'Role'),
                    ),
                    if (role == 'pengawas') ...[
                      const SizedBox(height: 12),
                      DropdownButtonFormField<int>(
                        initialValue: roomId,
                        items: _rooms
                            .map(
                              (room) => DropdownMenuItem(
                                value: int.tryParse(room['id'].toString()),
                                child: Text(room['name']?.toString() ?? '-'),
                              ),
                            )
                            .where((item) => item.value != null)
                            .toList(),
                        onChanged: (value) {
                          setDialogState(() {
                            roomId = value;
                          });
                        },
                        decoration: const InputDecoration(labelText: 'Ruangan'),
                      ),
                    ],
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Batal'),
                ),
                ElevatedButton(
                  onPressed: () async {
                    final username = usernameController.text.trim();
                    final password = passwordController.text.trim();
                    if (username.isEmpty || password.isEmpty) {
                      _showSnack(
                        'Username dan password wajib diisi',
                        isError: true,
                      );
                      return;
                    }
                    try {
                      await widget.api.createUser(
                        username: username,
                        password: password,
                        role: role,
                        roomId: role == 'pengawas' ? roomId : null,
                      );
                      if (!mounted) return;
                      Navigator.of(this.context).pop();
                      _showSnack('User berhasil ditambahkan');
                      await _loadUsers();
                    } catch (e) {
                      if (!mounted) return;
                      _showSnack(e.toString(), isError: true);
                    }
                  },
                  child: const Text('Simpan'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<void> _showEditDialog(Map<String, dynamic> user) async {
    final passwordController = TextEditingController();
    var role = user['role']?.toString() ?? 'pengawas';
    var roomId = int.tryParse(user['room_id']?.toString() ?? '');
    final id = int.tryParse(user['id'].toString());
    if (id == null) return;

    await showDialog<void>(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: Text('Edit User: ${user['username']}'),
              content: SizedBox(
                width: 360,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(
                      enabled: false,
                      controller: TextEditingController(
                        text: user['username']?.toString() ?? '',
                      ),
                      decoration: const InputDecoration(labelText: 'Username'),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: passwordController,
                      obscureText: true,
                      decoration: const InputDecoration(
                        labelText: 'Password Baru',
                        hintText: 'Wajib diisi',
                      ),
                    ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<String>(
                      initialValue: role,
                      items: const [
                        DropdownMenuItem(
                          value: 'pengawas',
                          child: Text('Pengawas'),
                        ),
                        DropdownMenuItem(
                          value: 'security',
                          child: Text('Security'),
                        ),
                        DropdownMenuItem(
                          value: 'manager',
                          child: Text('Manager'),
                        ),
                        DropdownMenuItem(value: 'admin', child: Text('Admin')),
                      ],
                      onChanged: (value) {
                        if (value != null) {
                          setDialogState(() {
                            role = value;
                            if (role != 'pengawas') roomId = null;
                          });
                        }
                      },
                      decoration: const InputDecoration(labelText: 'Role'),
                    ),
                    if (role == 'pengawas') ...[
                      const SizedBox(height: 12),
                      DropdownButtonFormField<int>(
                        initialValue: roomId,
                        items: _rooms
                            .map(
                              (room) => DropdownMenuItem(
                                value: int.tryParse(room['id'].toString()),
                                child: Text(room['name']?.toString() ?? '-'),
                              ),
                            )
                            .where((item) => item.value != null)
                            .toList(),
                        onChanged: (value) {
                          setDialogState(() {
                            roomId = value;
                          });
                        },
                        decoration: const InputDecoration(labelText: 'Ruangan'),
                      ),
                    ],
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Batal'),
                ),
                ElevatedButton(
                  onPressed: () async {
                    final password = passwordController.text.trim();
                    if (password.isEmpty) {
                      _showSnack(
                        'Password wajib diisi untuk update user',
                        isError: true,
                      );
                      return;
                    }
                    try {
                      await widget.api.updateUser(
                        id: id,
                        password: password,
                        role: role,
                        roomId: role == 'pengawas' ? roomId : null,
                      );
                      if (!mounted) return;
                      Navigator.of(this.context).pop();
                      _showSnack('User berhasil diupdate');
                      await _loadUsers();
                    } catch (e) {
                      if (!mounted) return;
                      _showSnack(e.toString(), isError: true);
                    }
                  },
                  child: const Text('Update'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<void> _deleteUser(Map<String, dynamic> user) async {
    final id = int.tryParse(user['id'].toString());
    if (id == null) return;
    final username = user['username']?.toString() ?? '-';

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Hapus User'),
          content: Text('Yakin ingin menghapus user "$username"?'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Batal'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(context, true),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red.shade600,
              ),
              child: const Text('Hapus'),
            ),
          ],
        );
      },
    );

    if (confirmed != true) return;
    try {
      await widget.api.deleteUser(id);
      if (!mounted) return;
      _showSnack('User berhasil dihapus');
      await _loadUsers();
    } catch (e) {
      if (!mounted) return;
      _showSnack(e.toString(), isError: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('User Management (Remote)')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
          ? Center(child: Text('Error: $_error'))
          : _users.isEmpty
          ? const Center(child: Text('Belum ada user'))
          : ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: _users.length,
              itemBuilder: (context, index) {
                final user = _users[index];
                return Card(
                  margin: const EdgeInsets.only(bottom: 12),
                  child: ListTile(
                    title: Text(user['username']?.toString() ?? '-'),
                    subtitle: Text(
                      'Role: ${user['role'] ?? '-'}${user['room_name'] == null ? '' : ' | Ruangan: ${user['room_name']}'}',
                    ),
                    trailing: Wrap(
                      spacing: 8,
                      children: [
                        IconButton(
                          icon: const Icon(Icons.edit),
                          onPressed: () => _showEditDialog(user),
                        ),
                        IconButton(
                          icon: Icon(Icons.delete, color: Colors.red.shade600),
                          onPressed: () => _deleteUser(user),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _showCreateDialog,
        icon: const Icon(Icons.person_add),
        label: const Text('Tambah User'),
      ),
    );
  }
}
