import 'package:flutter/material.dart';
import 'package:sqlite3/sqlite3.dart' hide Row;

class RoomManagementPage extends StatefulWidget {
  final Database db;
  const RoomManagementPage({required this.db, super.key});

  @override
  State<RoomManagementPage> createState() => _RoomManagementPageState();
}

class _RoomManagementPageState extends State<RoomManagementPage> {
  final _nameController = TextEditingController();
  final _maxConcurrentController = TextEditingController(text: '5');
  final _dailyLimitController = TextEditingController(text: '5');
  int? _editingId;
  bool _isActive = true;

  static const Color primaryColor = Color(0xFF059669);
  static const Color bgColor = Color(0xFFF3F4F6);

  void _showSnack(String message, {bool isError = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError ? Colors.red.shade600 : Colors.green.shade600,
      ),
    );
  }

  void _showForm({Map<String, Object?>? room}) {
    if (room != null) {
      _editingId = room['id'] as int;
      _nameController.text = room['name'] as String;
      _maxConcurrentController.text = room['max_concurrent_permits'].toString();
      _dailyLimitController.text = room['daily_mitra_limit'].toString();
      _isActive = (room['is_active'] as int) == 1;
    } else {
      _editingId = null;
      _nameController.clear();
      _maxConcurrentController.text = '5';
      _dailyLimitController.text = '5';
      _isActive = true;
    }

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          title: Text(_editingId == null ? 'Tambah Ruangan' : 'Edit Ruangan'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: _nameController,
                  decoration: const InputDecoration(
                    labelText: 'Nama Ruangan',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: _maxConcurrentController,
                  decoration: const InputDecoration(
                    labelText: 'Maks. Kuota Bersamaan',
                    border: OutlineInputBorder(),
                  ),
                  keyboardType: TextInputType.number,
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: _dailyLimitController,
                  decoration: const InputDecoration(
                    labelText: 'Limit Harian per Mitra',
                    border: OutlineInputBorder(),
                  ),
                  keyboardType: TextInputType.number,
                ),
                const SizedBox(height: 16),
                SwitchListTile(
                  title: const Text('Status Aktif'),
                  value: _isActive,
                  onChanged: (val) => setDialogState(() => _isActive = val),
                  contentPadding: EdgeInsets.zero,
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
              onPressed: _save,
              style: ElevatedButton.styleFrom(backgroundColor: primaryColor),
              child: const Text('Simpan'),
            ),
          ],
        ),
      ),
    );
  }

  void _save() {
    final name = _nameController.text.trim();
    final maxC = int.tryParse(_maxConcurrentController.text);
    final daily = int.tryParse(_dailyLimitController.text);
    if (name.isEmpty) {
      _showSnack('Nama ruangan wajib diisi', isError: true);
      return;
    }
    if (maxC == null || maxC < 1 || daily == null || daily < 1) {
      _showSnack('Kuota bersamaan dan limit harian minimal 1', isError: true);
      return;
    }

    try {
      if (_editingId == null) {
        widget.db.execute(
          'INSERT INTO rooms(name, max_concurrent_permits, daily_mitra_limit, is_active) VALUES(?, ?, ?, ?)',
          [name, maxC, daily, _isActive ? 1 : 0],
        );
      } else {
        widget.db.execute(
          'UPDATE rooms SET name=?, max_concurrent_permits=?, daily_mitra_limit=?, is_active=? WHERE id=?',
          [name, maxC, daily, _isActive ? 1 : 0, _editingId],
        );
      }
      setState(() {});
      Navigator.pop(context);
      _showSnack(
        _editingId == null
            ? 'Ruangan berhasil ditambahkan'
            : 'Ruangan berhasil diupdate',
      );
    } catch (e) {
      _showSnack('Error: $e', isError: true);
    }
  }

  Future<void> _deleteRoom(Map<String, Object?> room) async {
    final id = room['id'] as int?;
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
      widget.db.execute('BEGIN IMMEDIATE TRANSACTION');
      try {
        widget.db.execute('UPDATE users SET room_id=NULL WHERE room_id=?', [
          id,
        ]);
        widget.db.execute(
          'UPDATE toilet_permit SET room_id=NULL WHERE room_id=?',
          [id],
        );
        widget.db.execute(
          'UPDATE toilet_permit_history SET room_id=NULL WHERE room_id=?',
          [id],
        );
        widget.db.execute('DELETE FROM rooms WHERE id=?', [id]);
        widget.db.execute('COMMIT');
      } catch (e) {
        widget.db.execute('ROLLBACK');
        rethrow;
      }
      setState(() {});
      _showSnack('Ruangan berhasil dihapus');
    } catch (e) {
      _showSnack('Error: $e', isError: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final rooms = widget.db.select('SELECT * FROM rooms ORDER BY name ASC');
    return Scaffold(
      backgroundColor: bgColor,
      appBar: AppBar(
        title: const Text('Manajemen Ruangan'),
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
        elevation: 0,
      ),
      body: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: rooms.length,
        itemBuilder: (context, i) {
          final r = rooms[i];
          final active = (r['is_active'] as int) == 1;
          return Card(
            margin: const EdgeInsets.only(bottom: 12),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
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
              title: Text(
                r['name'] as String,
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              subtitle: Text(
                'Kuota: ${r['max_concurrent_permits']} | Limit: ${r['daily_mitra_limit']} | ${active ? "AKTIF" : "NONAKTIF"}',
              ),
              trailing: Wrap(
                spacing: 4,
                children: [
                  IconButton(
                    icon: const Icon(Icons.edit),
                    onPressed: () => _showForm(room: r),
                  ),
                  IconButton(
                    icon: Icon(Icons.delete, color: Colors.red.shade600),
                    onPressed: () => _deleteRoom(r),
                  ),
                ],
              ),
            ),
          );
        },
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _showForm(),
        backgroundColor: primaryColor,
        child: const Icon(Icons.add),
      ),
    );
  }
}
