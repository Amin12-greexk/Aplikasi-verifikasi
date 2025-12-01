import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import 'api_client.dart';

class ScannerTab extends StatefulWidget {
  final bool isPengawas;
  const ScannerTab({super.key, required this.isPengawas});

  @override
  State<ScannerTab> createState() => _ScannerTabState();
}

class _ScannerTabState extends State<ScannerTab> {
  bool _processing = false;
  String? _info;

  Future<void> _onDetect(BarcodeCapture capture) async {
    if (_processing) return;
    final code = capture.barcodes.first.rawValue;
    if (code == null || code.isEmpty) return;
    setState(() {
      _processing = true;
      _info = 'Mengirim $code...';
    });
    try {
      final data = widget.isPengawas ? await accPengawas(code) : await accSecurity(code);
      setState(() => _info = 'Sukses: ${data['status_pengawas']}/${data['status_security']}');
    } catch (e) {
      setState(() => _info = 'Error: $e');
    } finally {
      setState(() => _processing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final title = widget.isPengawas ? 'Scan Pengawas' : 'Scan Security';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(title, style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [Colors.green.shade700, Colors.green.shade400],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(16),
            boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 6, offset: Offset(0, 3))],
          ),
          height: 320,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: MobileScanner(
              onDetect: _onDetect,
            ),
          ),
        ),
        const SizedBox(height: 12),
        Card(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(widget.isPengawas ? Icons.badge : Icons.security, color: Colors.green.shade700),
                    const SizedBox(width: 8),
                    Text(widget.isPengawas ? 'Mode Pengawas' : 'Mode Security',
                        style: const TextStyle(fontWeight: FontWeight.bold)),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  widget.isPengawas
                      ? 'Scan ID karyawan untuk ACC Pengawas.'
                      : 'Scan ID yang sudah ACC Pengawas untuk ACC Security.',
                  style: const TextStyle(color: Colors.black87),
                ),
              ],
            ),
          ),
        ),
        if (_processing) const Center(child: CircularProgressIndicator()),
        if (_info != null)
          Card(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Text(_info!),
            ),
          ),
      ],
    );
  }
}
