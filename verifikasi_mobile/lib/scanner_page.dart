import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'api_client.dart';
import 'auth_service.dart';

class ScannerTab extends StatefulWidget {
  final bool isPengawas;
  const ScannerTab({super.key, required this.isPengawas});

  @override
  State<ScannerTab> createState() => _ScannerTabState();
}

class _ScannerTabState extends State<ScannerTab> {
  bool _processing = false;
  String? _info;
  String? _lastScannedId;

  @override
  void initState() {
    super.initState();
  }

  Future<bool> _checkPengawasApproval(String idKaryawan) async {
    try {
      final logs = await fetchLogs();
      // Cek apakah ID ini sudah ACC pengawas
      final hasPengawasApproval = logs.any(
        (log) => log['id_karyawan'].toString() == idKaryawan &&
                log['status_pengawas'] == 'ACC'
      );
      return hasPengawasApproval;
    } catch (e) {
      return false;
    }
  }

  Future<void> _onDetect(BarcodeCapture capture) async {
    if (_processing) return;
    final code = capture.barcodes.first.rawValue;
    if (code == null || code.isEmpty) return;

    // Validasi untuk scan security - check per ID
    if (!widget.isPengawas) {
      final hasPengawasApproval = await _checkPengawasApproval(code);
      if (!hasPengawasApproval) {
        setState(() => _info = '⚠️ ID $code belum scan pengawas');
        return;
      }
    }

    setState(() {
      _processing = true;
      _info = 'Mengirim $code...';
    });
    try {
      final data = widget.isPengawas ? await accPengawas(code) : await accSecurity(code);
      final pengawas = data['status_pengawas'] ?? 'UNKNOWN';
      final security = data['status_security'] ?? 'UNKNOWN';

      // User-friendly success message
      if (widget.isPengawas) {
        setState(() => _info = '✓ ACC Pengawas: $pengawas');
      } else {
        setState(() => _info = '✓ ACC Security: $security');
      }
    } catch (e) {
      // User-friendly error messages
      String errorMsg = 'Error: Koneksi gagal';
      if (e.toString().contains('timeout')) {
        errorMsg = '❌ Timeout - Server tidak merespons';
      } else if (e.toString().contains('Connection')) {
        errorMsg = '❌ Koneksi error - Cek server';
      } else {
        errorMsg = '❌ ${e.toString()}';
      }
      setState(() => _info = errorMsg);
    } finally {
      setState(() => _processing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isPengawas = widget.isPengawas;

    // Check if user has the correct role
    final userRole = AuthService.role;
    final hasCorrectRole = (isPengawas && AuthService.isPengawas()) ||
        (!isPengawas && AuthService.isSecurity());

    if (!hasCorrectRole) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.lock_outline,
              size: 64,
              color: Colors.red.shade400,
            ),
            const SizedBox(height: 16),
            Text(
              'Akses Terbatas',
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.bold,
                color: Colors.red.shade700,
              ),
            ),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Text(
                isPengawas
                    ? 'Hanya pengawas yang dapat mengakses menu ini'
                    : 'Hanya security yang dapat mengakses menu ini',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.grey.shade600,
                  fontSize: 14,
                ),
              ),
            ),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: () async {
                await AuthService.logout();
                if (context.mounted) {
                  Navigator.of(context).pushNamedAndRemoveUntil('/login', (route) => false);
                }
              },
              icon: const Icon(Icons.logout),
              label: const Text('Login dengan akun yang benar'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red.shade600,
              ),
            ),
          ],
        ),
      );
    }

    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Header dengan status
          _buildHeader(isPengawas, false),
          const SizedBox(height: 16),

          // Alert/Info Box
          _buildAlertBox(isPengawas, false),
          const SizedBox(height: 16),

          // Camera Scanner
          _buildScannerBox(false),
          const SizedBox(height: 16),

          // Mode Description
          _buildModeDescription(isPengawas),
          const SizedBox(height: 12),

          // Status Result
          if (_info != null) _buildResultBox(),
          const SizedBox(height: 12),

          // Processing Indicator
          if (_processing) _buildProcessing(),
        ],
      ),
    );
  }

  Widget _buildHeader(bool isPengawas, bool isLocked) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: isPengawas
              ? [Colors.blue.shade600, Colors.blue.shade400]
              : [Colors.green.shade600, Colors.green.shade400],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: isPengawas
                ? Colors.blue.shade300.withAlpha(100)
                : Colors.green.shade300.withAlpha(100),
            blurRadius: 8,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.white.withAlpha(200),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  isPengawas ? Icons.badge : Icons.security,
                  color: isPengawas ? Colors.blue.shade600 : Colors.green.shade600,
                  size: 28,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      isPengawas ? 'SCAN PENGAWAS' : 'SCAN SECURITY',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 0.5,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      isPengawas
                          ? 'Approval dari Pengawas'
                          : 'Approval dari Security',
                      style: TextStyle(
                        color: Colors.white.withAlpha(220),
                        fontSize: 12,
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
    );
  }

  Widget _buildAlertBox(bool isPengawas, bool isLocked) {
    if (isPengawas) {
      // Info box untuk pengawas
      return Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.blue.shade50,
          border: Border.all(color: Colors.blue.shade200),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            Icon(Icons.info_outline, color: Colors.blue.shade600, size: 20),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                'Scan ID karyawan untuk approval pengawas',
                style: TextStyle(color: Colors.blue.shade700, fontSize: 13),
              ),
            ),
          ],
        ),
      );
    } else {
      // Info box untuk security
      return Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.green.shade50,
          border: Border.all(color: Colors.green.shade200),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: Colors.green.shade100,
                shape: BoxShape.circle,
              ),
              child: Icon(Icons.check_circle, color: Colors.green.shade600, size: 18),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                'Scan ID yang sudah ACC pengawas untuk approval security',
                style: TextStyle(color: Colors.green.shade700, fontSize: 13),
              ),
            ),
          ],
        ),
      );
    }
  }

  Widget _buildScannerBox(bool isLocked) {
    return Container(
      padding: const EdgeInsets.all(2),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withAlpha(30),
            blurRadius: 8,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(14),
        child: SizedBox(
          height: 320,
          child: MobileScanner(
            onDetect: _onDetect,
          ),
        ),
      ),
    );
  }

  Widget _buildModeDescription(bool isPengawas) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.grey.shade50,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                isPengawas ? Icons.badge : Icons.security,
                size: 20,
                color: isPengawas ? Colors.blue.shade600 : Colors.green.shade600,
              ),
              const SizedBox(width: 8),
              Text(
                isPengawas ? 'Mode Pengawas' : 'Mode Security',
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            isPengawas
                ? 'Scan QR Code atau ID Karyawan untuk memberikan approval sebagai pengawas.'
                : 'Scan QR Code atau ID Karyawan yang telah disetujui pengawas untuk approval security.',
            style: TextStyle(
              color: Colors.grey.shade700,
              fontSize: 13,
              height: 1.5,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildResultBox() {
    final isError = _info!.contains('❌');
    final isSuccess = _info!.contains('✓');
    final isWarning = _info!.contains('⚠️');

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: isError
            ? Colors.red.shade50
            : isSuccess
                ? Colors.green.shade50
                : Colors.yellow.shade50,
        border: Border.all(
          color: isError
              ? Colors.red.shade300
              : isSuccess
                  ? Colors.green.shade300
                  : Colors.yellow.shade300,
        ),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Icon(
            isError
                ? Icons.error_outline
                : isSuccess
                    ? Icons.check_circle_outline
                    : Icons.warning_amber_outlined,
            color: isError
                ? Colors.red.shade700
                : isSuccess
                    ? Colors.green.shade700
                    : Colors.yellow.shade700,
            size: 24,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              _info!,
              style: TextStyle(
                color: isError
                    ? Colors.red.shade700
                    : isSuccess
                        ? Colors.green.shade700
                        : Colors.yellow.shade700,
                fontWeight: FontWeight.w500,
                fontSize: 13,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildProcessing() {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Column(
        children: [
          CircularProgressIndicator(
            strokeWidth: 3,
            valueColor: AlwaysStoppedAnimation<Color>(Colors.blue.shade600),
          ),
          const SizedBox(height: 12),
          Text(
            'Sedang memproses...',
            style: TextStyle(
              color: Colors.grey.shade700,
              fontSize: 13,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}
