import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import 'auth_service.dart';
import 'config.dart';

class SettingsPage extends StatefulWidget {
  final bool isFromLogin;

  const SettingsPage({super.key, this.isFromLogin = false});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  late TextEditingController _serverController;
  bool _isTesting = false;
  String? _testResult;

  @override
  void initState() {
    super.initState();
    _serverController = TextEditingController(text: ServerConfig.baseUrl);
  }

  @override
  void dispose() {
    _serverController.dispose();
    super.dispose();
  }

  Future<void> _testConnection() async {
    setState(() {
      _isTesting = true;
      _testResult = null;
    });

    try {
      final url = _serverController.text.trim();
      if (url.isEmpty) {
        setState(() {
          _testResult = 'URL tidak boleh kosong';
          _isTesting = false;
        });
        return;
      }

      // Test koneksi ke endpoint /logs dengan timeout 5 detik
      final uri = Uri.parse('$url/logs');
      final response = await http.get(uri).timeout(
        const Duration(seconds: 5),
        onTimeout: () => throw Exception('Connection timeout - Server tidak merespons'),
      );

      if (response.statusCode == 200) {
        setState(() {
          _testResult = 'Koneksi berhasil! ✓';
          _isTesting = false;
        });
      } else {
        setState(() {
          _testResult = 'Server merespons dengan error: ${response.statusCode}';
          _isTesting = false;
        });
      }
    } catch (e) {
      setState(() {
        _testResult = 'Error: ${e.toString()}';
        _isTesting = false;
      });
    }
  }

  Future<void> _saveServer() async {
    final url = _serverController.text.trim();
    if (url.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('URL tidak boleh kosong')),
      );
      return;
    }

    await ServerConfig.setServerUrl(url);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Server URL berhasil disimpan')),
      );
      Navigator.pop(context, true);
    }
  }

  Future<void> _handleLogout() async {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Konfirmasi Logout'),
        content: const Text('Apakah Anda yakin ingin logout?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Batal'),
          ),
          ElevatedButton(
            onPressed: () async {
              await AuthService.logout();
              if (mounted) {
                Navigator.of(context).pushNamedAndRemoveUntil('/login', (route) => false);
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red.shade600,
            ),
            child: const Text('Logout'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.isFromLogin ? 'Server Settings' : 'Pengaturan'),
        elevation: 0,
        leading: widget.isFromLogin
            ? IconButton(
                icon: const Icon(Icons.close),
                onPressed: () => Navigator.pop(context),
              )
            : null,
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          // User Info Section - Only show if logged in
          if (!widget.isFromLogin) ...[
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.blue.shade50,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.blue.shade200),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(
                        AuthService.isPengawas() ? Icons.badge : Icons.security,
                        color: Colors.blue.shade700,
                        size: 28,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'User Login',
                              style: TextStyle(fontSize: 12, color: Colors.grey),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              AuthService.username ?? 'Unknown',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                                color: Colors.blue.shade700,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              AuthService.isPengawas() ? 'Pengawas' : 'Security',
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.blue.shade600,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 32),
          ],
          Text(
            'Server Configuration',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: Colors.grey.shade700,
            ),
          ),
          const SizedBox(height: 20),
          const Text(
            'Server Address',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w500,
              color: Colors.grey,
            ),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _serverController,
            decoration: InputDecoration(
              hintText: 'http://192.168.x.x:8080',
              prefixIcon: const Icon(Icons.link),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              filled: true,
              fillColor: Colors.grey.shade50,
            ),
            keyboardType: TextInputType.url,
          ),
          const SizedBox(height: 20),
          Row(
            children: [
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: _isTesting ? null : _testConnection,
                  icon: _isTesting
                      ? SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            valueColor: AlwaysStoppedAnimation<Color>(
                              Colors.white.withAlpha(200),
                            ),
                          ),
                        )
                      : const Icon(Icons.check_circle),
                  label: Text(_isTesting ? 'Testing...' : 'Test Connection'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: _saveServer,
                  icon: const Icon(Icons.save),
                  label: const Text('Simpan'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.green.shade600,
                  ),
                ),
              ),
            ],
          ),
          if (_testResult != null) ...[
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: _testResult!.contains('berhasil')
                    ? Colors.green.shade50
                    : Colors.red.shade50,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: _testResult!.contains('berhasil')
                      ? Colors.green.shade300
                      : Colors.red.shade300,
                ),
              ),
              child: Text(
                _testResult!,
                style: TextStyle(
                  color: _testResult!.contains('berhasil')
                      ? Colors.green.shade700
                      : Colors.red.shade700,
                ),
              ),
            ),
          ],
          const SizedBox(height: 40),
          const Divider(),
          const SizedBox(height: 20),
          const Text(
            'Current Server',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w500,
              color: Colors.grey,
            ),
          ),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.blue.shade50,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.blue.shade200),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'URL Aktif:',
                  style: TextStyle(fontSize: 12, color: Colors.grey),
                ),
                const SizedBox(height: 4),
                Text(
                  ServerConfig.baseUrl,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: Colors.blue.shade700,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          Text(
            'Ubah server address untuk terhubung ke server Verifikasi di jaringan WiFi yang berbeda.',
            style: TextStyle(
              fontSize: 12,
              color: Colors.grey.shade600,
            ),
          ),
          const SizedBox(height: 48),
          if (!widget.isFromLogin) ...[
            const Divider(),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: _handleLogout,
              icon: const Icon(Icons.logout),
              label: const Text('Logout'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red.shade600,
                padding: const EdgeInsets.symmetric(vertical: 16),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
