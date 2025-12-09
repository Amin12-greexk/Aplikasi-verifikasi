import 'dart:async';

import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import 'api_client_retry.dart'; // Use retry version
import 'auth_service.dart';

class ScannerTab extends StatefulWidget {
  final bool isPengawas;
  const ScannerTab({super.key, required this.isPengawas});

  @override
  State<ScannerTab> createState() => _ScannerTabState();
}

class _ScannerTabState extends State<ScannerTab> {
  late final MobileScannerController _cameraController;
  bool _processing = false;
  String? _info;
  String? _lastScannedId;
  String _deviceTimeLabel = '';
  String? _lastScanTimeLabel;
  Timer? _clockTimer;
  bool _isTorchOn = false;
  bool _initialZoomApplied = false;
  final double _initialZoomScale = 0.4; // 0..1 (40% of max) for easier small-code scan

  @override
  void initState() {
    super.initState();
    _cameraController = MobileScannerController(
      // High sensitivity: proses setiap frame tanpa jeda
      detectionSpeed: DetectionSpeed.unrestricted,
      detectionTimeoutMs: 0,
      facing: CameraFacing.back,
      formats: const [BarcodeFormat.qrCode],
      returnImage: false,
    );
    _cameraController.torchState.addListener(_handleTorchState);
    WidgetsBinding.instance.addPostFrameCallback((_) => _applyInitialZoom());
    _startDeviceClock();
  }

  @override
  void dispose() {
    _clockTimer?.cancel();
    _cameraController.torchState.removeListener(_handleTorchState);
    _cameraController.dispose();
    super.dispose();
  }

  void _startDeviceClock() {
    _deviceTimeLabel = _formatTime(DateTime.now());
    _clockTimer?.cancel();
    _clockTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      setState(() => _deviceTimeLabel = _formatTime(DateTime.now()));
    });
  }

  String _formatTime(DateTime time) {
    final hour = time.hour.toString().padLeft(2, '0');
    final minute = time.minute.toString().padLeft(2, '0');
    final second = time.second.toString().padLeft(2, '0');
    return '$hour:$minute:$second';
  }

  void _handleTorchState() {
    final isOn = _cameraController.torchState.value == TorchState.on;
    if (_isTorchOn != isOn) {
      setState(() => _isTorchOn = isOn);
    }
  }

  void _applyInitialZoom({int retries = 3}) {
    if (_initialZoomApplied || !mounted) return;
    _cameraController
        .setZoomScale(_initialZoomScale.clamp(0.0, 1.0))
        .then((_) {
      if (mounted) {
        setState(() => _initialZoomApplied = true);
      }
    }).catchError((_) {
      if (retries > 0 && mounted) {
        Future.delayed(const Duration(milliseconds: 200), () {
          _applyInitialZoom(retries: retries - 1);
        });
      }
    });
  }

  /// Extract PIN, Nama, and Bagian from barcode string to match server format
  String _extractBarcodeInfo(String fullBarcode) {
    try {
      final namaMatch = RegExp(r'Nama:\s*([^|]+)').firstMatch(fullBarcode);
      final pinMatch = RegExp(r'PIN:\s*([^|]+)').firstMatch(fullBarcode);
      final bagianMatch = RegExp(r'Bagian:\s*([^|]+)').firstMatch(fullBarcode);

      final nama = namaMatch?.group(1)?.trim() ?? '';
      final pin = pinMatch?.group(1)?.trim() ?? '';
      final bagian = bagianMatch?.group(1)?.trim() ?? '';

      if (nama.isEmpty && pin.isEmpty && bagian.isEmpty) {
        // If parsing fails, return original string
        return fullBarcode;
      }

      // Format: "PIN: 12053 | Nama: SURATI | Bagian: Cuci Hancuran"
      final List<String> parts = [];
      if (pin.isNotEmpty) parts.add('PIN: $pin');
      if (nama.isNotEmpty) parts.add('Nama: $nama');
      if (bagian.isNotEmpty) parts.add('Bagian: $bagian');

      return parts.join(' | ');
    } catch (e) {
      return fullBarcode;
    }
  }

  Future<bool> _checkPengawasApproval(String idKaryawan) async {
    try {
      final logs = await ApiClientRetry.fetchLogs();
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
    if (capture.barcodes.isEmpty) return;
    final code = capture.barcodes.first.rawValue;
    if (code == null || code.isEmpty) return;

    // Extract barcode to match server format: "PIN: XXX | Nama: XXX | Bagian: XXX"
    final extractedCode = _extractBarcodeInfo(code);
    final nowLabel = _formatTime(DateTime.now());

    // Prevent duplicate scans - jangan process ID yang sama 2x berturut-turut
    if (_lastScannedId == extractedCode) {
      return;
    }

    // Validasi untuk scan security - check per ID
    if (!widget.isPengawas) {
      final hasPengawasApproval = await _checkPengawasApproval(extractedCode);
      if (!hasPengawasApproval) {
        // Show alert without the employee name for security
        setState(() {
          _info = '[WARN] Belum scan pengawas';
          _lastScanTimeLabel = 'Jam perangkat: $nowLabel';
          _lastScannedId = extractedCode; // Set last scanned to prevent re-trigger
        });
        return;
      }
    }

    setState(() {
      _processing = true;
      _info = 'Mengirim...';
      _lastScannedId = extractedCode; // Track this scan
      _lastScanTimeLabel = 'Jam perangkat: $nowLabel';
    });
    try {
      final data = widget.isPengawas ? await ApiClientRetry.accPengawas(extractedCode) : await ApiClientRetry.accSecurity(extractedCode);
      final pengawas = data['status_pengawas'] ?? 'UNKNOWN';
      final security = data['status_security'] ?? 'UNKNOWN';
      final successTime = _formatTime(DateTime.now());

      // User-friendly success message
      if (widget.isPengawas) {
        setState(() {
          _info = '[OK] ACC Pengawas: $pengawas';
          _lastScanTimeLabel = 'Jam perangkat: $successTime';
        });
      } else {
        setState(() {
          _info = '[OK] ACC Security: $security';
          _lastScanTimeLabel = 'Jam perangkat: $successTime';
        });
      }
    } catch (e) {
      // User-friendly error messages
      String errorMsg = '[ERR] Koneksi gagal';
      if (e.toString().contains('timeout')) {
        errorMsg = '[ERR] Timeout - Server tidak merespons';
      } else if (e.toString().contains('Connection')) {
        errorMsg = '[ERR] Koneksi error - Cek server';
      } else {
        errorMsg = '[ERR] ${e.toString()}';
      }
      final errorTime = _formatTime(DateTime.now());
      setState(() {
        _info = errorMsg;
        _lastScanTimeLabel = 'Jam perangkat: $errorTime';
      });
    } finally {
      await Future.delayed(const Duration(milliseconds: 500));
      if (mounted) {
        setState(() => _processing = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isPengawas = widget.isPengawas;

    // Check if user has the correct role
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

    return Stack(
      children: [
        SingleChildScrollView(
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
              const SizedBox(height: 24),
            ],
          ),
        ),
        // Floating Alert/Status Result - displayed on top of camera
        Positioned(
          top: 190,
          left: 16,
          right: 16,
          child: Column(
            children: [
              // Status Result Box
              if (_info != null) _buildResultBox(),
              const SizedBox(height: 12),

              // Processing Indicator
              if (_processing) _buildProcessing(),
            ],
          ),
        ),
      ],
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
                    const SizedBox(height: 4),
                    if (_deviceTimeLabel.isNotEmpty)
                      Text(
                        'Jam perangkat: $_deviceTimeLabel',
                        style: TextStyle(
                          color: Colors.white.withAlpha(220),
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
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
          height: 400,
          child: Stack(
            children: [
              MobileScanner(
                controller: _cameraController,
                onDetect: _onDetect,
                fit: BoxFit.cover,
              ),
              Center(
                child: Container(
                  width: 280,
                  height: 280,
                  decoration: BoxDecoration(
                    border: Border.all(color: Colors.white.withOpacity(0.4), width: 2),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [_corner(0), _corner(1)],
                      ),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [_corner(3), _corner(2)],
                      ),
                    ],
                  ),
                ),
              ),
              Positioned(
                bottom: 20,
                right: 20,
                child: FloatingActionButton.small(
                  backgroundColor: Colors.white.withOpacity(0.85),
                  elevation: 0,
                  onPressed: () async {
                    await _cameraController.toggleTorch();
                  },
                  child: Icon(
                    _isTorchOn ? Icons.flash_on : Icons.flash_off,
                    color: Colors.black87,
                  ),
                ),
              ),
              Positioned(
                bottom: 20,
                left: 20,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: Colors.black45,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: const Text(
                    'Mode Cepat',
                    style: TextStyle(color: Colors.white, fontSize: 12),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _corner(int rotation) {
    return RotatedBox(
      quarterTurns: rotation,
      child: Container(
        width: 20,
        height: 20,
        decoration: const BoxDecoration(
          border: Border(
            top: BorderSide(color: Colors.white, width: 4),
            left: BorderSide(color: Colors.white, width: 4),
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
        'Mode sensitivitas tinggi aktif. Arahkan kamera ke QR, sistem akan membaca seketika meski kode kecil/kurang jelas.',
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
    final isError = _info!.startsWith('[ERR]');
    final isSuccess = _info!.startsWith('[OK]');

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isError
            ? Colors.red.shade600
            : isSuccess
                ? Colors.green.shade600
                : Colors.orange.shade600,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: (isError ? Colors.red : isSuccess ? Colors.green : Colors.orange)
                .withAlpha(100),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                isError
                    ? Icons.error_outline
                    : isSuccess
                        ? Icons.check_circle_outline
                        : Icons.warning_amber_outlined,
                color: Colors.white,
                size: 28,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  _info!,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                  ),
                  maxLines: 3,
                ),
              ),
            ],
          ),
          if (_lastScanTimeLabel != null)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Row(
                children: [
                  Icon(
                    Icons.schedule,
                    size: 16,
                    color: Colors.white.withAlpha(230),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    _lastScanTimeLabel!,
                    style: TextStyle(
                      color: Colors.white.withAlpha(230),
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildProcessing() {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 16),
      decoration: BoxDecoration(
        color: Colors.blue.shade600,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.blue.shade400.withAlpha(100),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        children: [
          CircularProgressIndicator(
            strokeWidth: 3,
            valueColor: const AlwaysStoppedAnimation<Color>(Colors.white),
          ),
          const SizedBox(height: 12),
          const Text(
            'Sedang memproses...',
            style: TextStyle(
              color: Colors.white,
              fontSize: 14,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }
}
