import 'package:flutter/material.dart';

import 'remote_api_service.dart';

class RemoteRoomManagementPage extends StatefulWidget {
  const RemoteRoomManagementPage({required this.api, super.key});

  final RemoteApiService api;

  @override
  State<RemoteRoomManagementPage> createState() =>
      _RemoteRoomManagementPageState();
}

class _RemoteRoomManagementPageState extends State<RemoteRoomManagementPage> {
  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _rooms = <Map<String, dynamic>>[];

  @override
  void initState() {
    super.initState();
    _loadRooms();
  }

  Future<void> _loadRooms() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final rooms = await widget.api.fetchRooms();
      if (!mounted) return;
      setState(() => _rooms = rooms);
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
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

  Future<void> _showForm({Map<String, dynamic>? room}) async {
    final nameController = TextEditingController(
      text: room?['name']?.toString() ?? '',
    );
    final maxController = TextEditingController(
      text: room?['max_concurrent_permits']?.toString() ?? '5',
    );
    final dailyController = TextEditingController(
      text: room?['daily_mitra_limit']?.toString() ?? '5',
    );
    var isActive = room == null
        ? true
        : room['is_active'] == 1 || room['is_active'] == true;
    final roomId = room == null ? null : int.tryParse(room['id'].toString());

    await showDialog<void>(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: Text(roomId == null ? 'Tambah Ruangan' : 'Edit Ruangan'),
              content: SizedBox(
                width: 380,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(
                      controller: nameController,
                      decoration: const InputDecoration(
                        labelText: 'Nama Ruangan',
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: maxController,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: 'Maks. Kuota Bersamaan',
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: dailyController,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: 'Limit Harian per Mitra',
                      ),
                    ),
                    const SizedBox(height: 12),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Status Aktif'),
                      value: isActive,
                      onChanged: (value) =>
                          setDialogState(() => isActive = value),
                    ),
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
                    final name = nameController.text.trim();
                    final maxConcurrent = int.tryParse(maxController.text);
                    final dailyLimit = int.tryParse(dailyController.text);
                    if (name.isEmpty) {
                      _showSnack('Nama ruangan wajib diisi', isError: true);
                      return;
                    }
                    if (maxConcurrent == null ||
                        maxConcurrent < 1 ||
                        dailyLimit == null ||
                        dailyLimit < 1) {
                      _showSnack(
                        'Kuota bersamaan dan limit harian minimal 1',
                        isError: true,
                      );
                      return;
                    }

                    try {
                      if (roomId == null) {
                        await widget.api.createRoom(
                          name: name,
                          maxConcurrentPermits: maxConcurrent,
                          dailyMitraLimit: dailyLimit,
                          isActive: isActive,
                        );
                      } else {
                        await widget.api.updateRoom(
                          id: roomId,
                          name: name,
                          maxConcurrentPermits: maxConcurrent,
                          dailyMitraLimit: dailyLimit,
                          isActive: isActive,
                        );
                      }
                      if (!mounted) return;
                      Navigator.of(this.context).pop();
                      _showSnack(
                        roomId == null
                            ? 'Ruangan berhasil ditambahkan'
                            : 'Ruangan berhasil diupdate',
                      );
                      await _loadRooms();
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

  Future<void> _deleteRoom(Map<String, dynamic> room) async {
    final id = int.tryParse(room['id'].toString());
    if (id == null) return;
    final name = room['name']?.toString() ?? '-';
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Hapus Ruangan'),
        content: Text(
          'Yakin ingin menghapus "$name"? User yang memakai ruangan ini akan dilepas dari ruangan.',
        ),
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
      ),
    );
    if (confirmed != true) return;
    try {
      await widget.api.deleteRoom(id);
      if (!mounted) return;
      _showSnack('Ruangan berhasil dihapus');
      await _loadRooms();
    } catch (e) {
      if (!mounted) return;
      _showSnack(e.toString(), isError: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Room Management (Remote)')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
          ? Center(child: Text('Error: $_error'))
          : _rooms.isEmpty
          ? const Center(child: Text('Belum ada ruangan'))
          : ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: _rooms.length,
              itemBuilder: (context, index) {
                final room = _rooms[index];
                final active =
                    room['is_active'] == 1 || room['is_active'] == true;
                return Card(
                  margin: const EdgeInsets.only(bottom: 12),
                  child: ListTile(
                    leading: CircleAvatar(
                      backgroundColor: active
                          ? Colors.green.shade50
                          : Colors.red.shade50,
                      child: Icon(
                        Icons.meeting_room,
                        color: active ? Colors.green : Colors.red,
                      ),
                    ),
                    title: Text(room['name']?.toString() ?? '-'),
                    subtitle: Text(
                      'Kuota: ${room['max_concurrent_permits'] ?? '-'} | Limit: ${room['daily_mitra_limit'] ?? '-'} | ${active ? "AKTIF" : "NONAKTIF"}',
                    ),
                    trailing: Wrap(
                      spacing: 8,
                      children: [
                        IconButton(
                          icon: const Icon(Icons.edit),
                          onPressed: () => _showForm(room: room),
                        ),
                        IconButton(
                          icon: Icon(Icons.delete, color: Colors.red.shade600),
                          onPressed: () => _deleteRoom(room),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _showForm(),
        icon: const Icon(Icons.meeting_room),
        label: const Text('Tambah Ruangan'),
      ),
    );
  }
}
