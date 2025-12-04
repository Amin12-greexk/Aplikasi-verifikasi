import 'package:flutter/material.dart';
import 'api_client_retry.dart'; // Use retry version

class CRUDLogPage extends StatefulWidget {
  const CRUDLogPage({super.key});

  @override
  State<CRUDLogPage> createState() => _CRUDLogPageState();
}

class _CRUDLogPageState extends State<CRUDLogPage> {
  late Future<List<Map<String, dynamic>>> _logsFuture;
  late TextEditingController _idController;
  late TextEditingController _pengawasController;
  late TextEditingController _securityController;
  String? _editingId;

  @override
  void initState() {
    super.initState();
    _idController = TextEditingController();
    _pengawasController = TextEditingController();
    _securityController = TextEditingController();
    _loadLogs();
  }

  @override
  void dispose() {
    _idController.dispose();
    _pengawasController.dispose();
    _securityController.dispose();
    super.dispose();
  }

  void _loadLogs() {
    _logsFuture = ApiClientRetry.fetchLogs();
  }

  void _resetForm() {
    _idController.clear();
    _pengawasController.clear();
    _securityController.clear();
    _editingId = null;
  }

  /// Parse barcode string to extract Nama, PIN, and Bagian
  String _extractEmployeeInfo(String fullBarcode) {
    try {
      final nama = _extractValue(fullBarcode, 'Nama');
      final pin = _extractValue(fullBarcode, 'PIN');
      final bagian = _extractValue(fullBarcode, 'Bagian');

      if (nama.isEmpty && pin.isEmpty && bagian.isEmpty) {
        return fullBarcode.length > 30 ? '${fullBarcode.substring(0, 30)}...' : fullBarcode;
      }

      final List<String> parts = [];
      if (nama.isNotEmpty) parts.add(nama);
      if (pin.isNotEmpty) parts.add('PIN: $pin');
      if (bagian.isNotEmpty) parts.add(bagian);

      return parts.join(' | ');
    } catch (e) {
      return fullBarcode.length > 30 ? '${fullBarcode.substring(0, 30)}...' : fullBarcode;
    }
  }

  String _extractValue(String barcode, String key) {
    try {
      final regex = RegExp('$key:\\s*([^|]+)');
      final match = regex.firstMatch(barcode);
      if (match != null) {
        return match.group(1)?.trim() ?? '';
      }
    } catch (e) {
      // Silent fail
    }
    return '';
  }

  void _showFormDialog({Map<String, dynamic>? log}) {
    if (log != null) {
      _editingId = log['id_karyawan'];
      _idController.text = log['id_karyawan'];
      _pengawasController.text = log['status_pengawas'] ?? 'PENDING';
      _securityController.text = log['status_security'] ?? 'PENDING';
    } else {
      _resetForm();
    }

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(_editingId != null ? 'Edit Log' : 'Tambah Log Baru'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: _idController,
                enabled: _editingId == null,
                decoration: InputDecoration(
                  labelText: 'ID Karyawan',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                value: _pengawasController.text.isEmpty
                    ? 'PENDING'
                    : _pengawasController.text,
                items: ['PENDING', 'ACC', 'REJECTED']
                    .map((e) => DropdownMenuItem(value: e, child: Text(e)))
                    .toList(),
                onChanged: (val) {
                  if (val != null) _pengawasController.text = val;
                },
                decoration: InputDecoration(
                  labelText: 'Status Pengawas',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                value: _securityController.text.isEmpty
                    ? 'PENDING'
                    : _securityController.text,
                items: ['PENDING', 'ACC', 'REJECTED']
                    .map((e) => DropdownMenuItem(value: e, child: Text(e)))
                    .toList(),
                onChanged: (val) {
                  if (val != null) _securityController.text = val;
                },
                decoration: InputDecoration(
                  labelText: 'Status Security',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () {
              _resetForm();
              Navigator.pop(context);
            },
            child: const Text('Batal'),
          ),
          ElevatedButton(
            onPressed: () async {
              if (_idController.text.isEmpty) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('ID Karyawan tidak boleh kosong')),
                );
                return;
              }

              try {
                if (_editingId != null) {
                  await ApiClientRetry.updateLogStatus(
                    _idController.text,
                    _pengawasController.text,
                    _securityController.text,
                  );
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Log berhasil diupdate')),
                  );
                } else {
                  await ApiClientRetry.createLog(
                    _idController.text,
                    _pengawasController.text,
                    _securityController.text,
                  );
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Log berhasil ditambah')),
                  );
                }

                _resetForm();
                setState(() => _loadLogs());
                Navigator.pop(context);
              } catch (e) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('Error: ${e.toString()}')),
                );
              }
            },
            child: Text(_editingId != null ? 'Update' : 'Tambah'),
          ),
        ],
      ),
    );
  }

  void _deleteLog(String idKaryawan) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Konfirmasi Hapus'),
        content: Text('Yakin hapus log untuk ID: $idKaryawan?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Batal'),
          ),
          ElevatedButton(
            onPressed: () async {
              try {
                await ApiClientRetry.deleteLog(idKaryawan);
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Log berhasil dihapus')),
                );
                setState(() => _loadLogs());
                Navigator.pop(context);
              } catch (e) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('Error: ${e.toString()}')),
                );
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red.shade600,
            ),
            child: const Text('Hapus'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('CRUD Log Data'),
        elevation: 0,
      ),
      body: FutureBuilder<List<Map<String, dynamic>>>(
        future: _logsFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          if (snapshot.hasError) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.error, size: 64, color: Colors.red.shade400),
                  const SizedBox(height: 16),
                  Text('Error: ${snapshot.error}'),
                  const SizedBox(height: 16),
                  ElevatedButton(
                    onPressed: () => setState(() => _loadLogs()),
                    child: const Text('Retry'),
                  ),
                ],
              ),
            );
          }

          final logs = snapshot.data ?? [];
          // Logs are already sorted newest first from server

          if (logs.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.inbox, size: 64, color: Colors.grey.shade400),
                  const SizedBox(height: 16),
                  Text(
                    'Tidak ada data log',
                    style: TextStyle(color: Colors.grey.shade600),
                  ),
                ],
              ),
            );
          }

          return ListView.builder(
            padding: const EdgeInsets.all(12),
            itemCount: logs.length,
            itemBuilder: (context, index) {
              final log = logs[index];
              final fullBarcode = log['id_karyawan'];
              final displayName = _extractEmployeeInfo(fullBarcode.toString());
              final pengawas = log['status_pengawas'] ?? 'UNKNOWN';
              final security = log['status_security'] ?? 'UNKNOWN';

              return Card(
                margin: const EdgeInsets.symmetric(vertical: 8),
                child: ListTile(
                  contentPadding: const EdgeInsets.all(16),
                  leading: CircleAvatar(
                    backgroundColor: Colors.blue.shade100,
                    child: Text(
                      displayName.substring(0, 1).toUpperCase(),
                      style: TextStyle(
                        color: Colors.blue.shade700,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  title: Text(
                    displayName,
                    style: const TextStyle(fontWeight: FontWeight.bold),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  subtitle: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Expanded(
                            child: _buildStatusBadge('Pengawas', pengawas),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: _buildStatusBadge('Security', security),
                          ),
                        ],
                      ),
                    ],
                  ),
                  trailing: PopupMenuButton(
                    itemBuilder: (context) => [
                      PopupMenuItem(
                        child: const Row(
                          children: [
                            Icon(Icons.edit, size: 20),
                            SizedBox(width: 8),
                            Text('Edit'),
                          ],
                        ),
                        onTap: () => _showFormDialog(log: log),
                      ),
                      PopupMenuItem(
                        child: const Row(
                          children: [
                            Icon(Icons.delete, size: 20, color: Colors.red),
                            SizedBox(width: 8),
                            Text('Hapus', style: TextStyle(color: Colors.red)),
                          ],
                        ),
                        onTap: () => _deleteLog(log['id_karyawan']),
                      ),
                    ],
                  ),
                ),
              );
            },
          );
        },
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _showFormDialog(),
        tooltip: 'Tambah Log',
        child: const Icon(Icons.add),
      ),
    );
  }

  Widget _buildStatusBadge(String label, String status) {
    final color = status == 'ACC'
        ? Colors.green
        : status == 'REJECTED'
            ? Colors.red
            : Colors.orange;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.shade100,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(fontSize: 10, color: Colors.grey),
          ),
          Text(
            status,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.bold,
              color: color.shade700,
            ),
          ),
        ],
      ),
    );
  }
}
