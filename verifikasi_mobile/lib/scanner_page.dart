import 'dart:async';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import 'api_client_retry.dart'; // Use retry version
import 'auth_service.dart';
import 'offline_queue.dart';
import 'tts_service.dart';

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
  bool _flushingQueue = false;
  DateTime? _lastSoundTime; // Track last time sound was played
  static const _soundCooldown = Duration(seconds: 3); // Cooldown between sounds

  @override
  void initState() {
    super.initState();
    _cameraController = MobileScannerController(
      // Optimized for small QR codes: fastest detection with high resolution
      detectionSpeed: DetectionSpeed.unrestricted,
      detectionTimeoutMs: 50, // Very fast detection for instant reading
      facing: CameraFacing.back,
      formats: const [BarcodeFormat.qrCode],
      returnImage: false,
      cameraResolution: const Size(1920, 1080), // High resolution for small codes
    );
    _cameraController.torchState.addListener(_handleTorchState);
    _startDeviceClock();
    _flushOfflineQueue();
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

  // Helper to play sound only if cooldown has passed
  Future<void> _playSound(Future<void> Function() soundFunction) async {
    final now = DateTime.now();
    if (_lastSoundTime == null ||
        now.difference(_lastSoundTime!) >= _soundCooldown) {
      _lastSoundTime = now;
      await soundFunction();
    }
  }

  void _handleTorchState() {
    final isOn = _cameraController.torchState.value == TorchState.on;
    if (_isTorchOn != isOn) {
      setState(() => _isTorchOn = isOn);
    }
  }

  Future<void> _flushOfflineQueue() async {
    if (_flushingQueue) return;
    _flushingQueue = true;
    try {
      final queue = await OfflineQueueManager.getPending();
      for (int i = queue.length - 1; i >= 0; i--) {
        final item = queue[i];
        final role = item['role']?.toString() ?? '';
        final id = item['id']?.toString() ?? '';
        if (id.isEmpty || (role != 'pengawas' && role != 'security')) continue;
        try {
          if (role == 'pengawas') {
            await ApiClientRetry.accPengawas(id);
          } else {
            await ApiClientRetry.accSecurity(id);
          }
          await OfflineQueueManager.removeAt(i);
        } catch (_) {
          // Stop flush on first failure to retry later
          break;
        }
      }
    } finally {
      _flushingQueue = false;
    }
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
      // Play duplicate sound based on role (with cooldown)
      if (widget.isPengawas) {
        _playSound(TtsService.duplikatPengawas);
      } else {
        _playSound(TtsService.duplikatSecurity);
      }
      return;
    }

    // Validasi untuk scan security - check per ID
    if (!widget.isPengawas) {
      final hasPengawasApproval = await _checkPengawasApproval(extractedCode);
      if (!hasPengawasApproval) {
        // Show alert - JANGAN set _lastScannedId agar user bisa coba lagi
        _playSound(TtsService.ditolakBelumPengawas);
        setState(() {
          _info = '[WARN] Belum scan pengawas';
          _lastScanTimeLabel = 'Jam perangkat: $nowLabel';
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
        _playSound(TtsService.scanPengawasBerhasil);
        setState(() {
          _info = '[OK] ACC Pengawas: $pengawas';
          _lastScanTimeLabel = 'Jam perangkat: $successTime';
        });
      } else {
        _playSound(TtsService.scanSecurityBerhasil);
        setState(() {
          _info = '[OK] ACC Security: $security';
          _lastScanTimeLabel = 'Jam perangkat: $successTime';
        });
      }
      _flushOfflineQueue();
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

      // Play error sound (with cooldown)
      _playSound(TtsService.gagalKoneksi);

      final errorTime = _formatTime(DateTime.now());
      // Simpan ke antrean offline agar bisa di-sync nanti
      OfflineQueueManager.addPending(
        id: extractedCode,
        role: widget.isPengawas ? 'pengawas' : 'security',
        username: AuthService.username ?? '',
        createdAt: DateTime.now().toIso8601String(),
      );
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
        Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Header dengan status
            _buildHeader(isPengawas, false),
            const SizedBox(height: 12),

            // Alert/Info Box
            _buildAlertBox(isPengawas, false),
            const SizedBox(height: 12),

            // Camera Scanner
            Expanded(
              child: _buildScannerBox(false),
            ),
            const SizedBox(height: 8),

            // Mode Description
            _buildModeDescription(isPengawas),
            const SizedBox(height: 12),
          ],
        ),
        // Floating Alert/Status Result - displayed on top of camera
        Positioned(
          top: 170,
          left: 16,
          right: 16,
          child: Column(
            children: [
              // Status Result Box
              if (_info != null) _buildResultBox(),
              const SizedBox(height: 8),

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
      margin: const EdgeInsets.all(12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: isPengawas
              ? [Colors.blue.shade600, Colors.blue.shade400]
              : [Colors.green.shade600, Colors.green.shade400],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: isPengawas
                ? Colors.blue.shade300.withAlpha(100)
                : Colors.green.shade300.withAlpha(100),
            blurRadius: 6,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Colors.white.withAlpha(200),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(
              isPengawas ? Icons.badge : Icons.security,
              color: isPengawas ? Colors.blue.shade600 : Colors.green.shade600,
              size: 24,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  isPengawas ? 'SCAN PENGAWAS' : 'SCAN SECURITY',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 0.5,
                  ),
                ),
                const SizedBox(height: 2),
                if (_deviceTimeLabel.isNotEmpty)
                  Text(
                    'Jam: $_deviceTimeLabel',
                    style: TextStyle(
                      color: Colors.white.withAlpha(220),
                      fontSize: 11,
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

  Widget _buildAlertBox(bool isPengawas, bool isLocked) {
    if (isPengawas) {
      // Info box untuk pengawas
      return Container(
        margin: const EdgeInsets.symmetric(horizontal: 12),
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: Colors.blue.shade50,
          border: Border.all(color: Colors.blue.shade200),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          children: [
            Icon(Icons.info_outline, color: Colors.blue.shade600, size: 18),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                'Scan ID karyawan untuk approval pengawas',
                style: TextStyle(color: Colors.blue.shade700, fontSize: 12),
              ),
            ),
          ],
        ),
      );
    } else {
      // Info box untuk security
      return Container(
        margin: const EdgeInsets.symmetric(horizontal: 12),
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: Colors.green.shade50,
          border: Border.all(color: Colors.green.shade200),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(5),
              decoration: BoxDecoration(
                color: Colors.green.shade100,
                shape: BoxShape.circle,
              ),
              child: Icon(Icons.check_circle, color: Colors.green.shade600, size: 16),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                'Scan ID yang sudah ACC pengawas',
                style: TextStyle(color: Colors.green.shade700, fontSize: 12),
              ),
            ),
          ],
        ),
      );
    }
  }

  Widget _buildScannerBox(bool isLocked) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
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
        child: Stack(
          children: [
            MobileScanner(
              controller: _cameraController,
              onDetect: _onDetect,
              fit: BoxFit.cover,
            ),
            Center(
              child: Container(
                width: 200,
                height: 200,
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
              bottom: 12,
              right: 12,
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
              bottom: 12,
              left: 12,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: Colors.black45,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: const Text(
                  'Deteksi Instan',
                  style: TextStyle(color: Colors.white, fontSize: 11),
                ),
              ),
            ),
          ],
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
      margin: const EdgeInsets.symmetric(horizontal: 12),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.grey.shade50,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Row(
        children: [
          Icon(
            Icons.speed,
            size: 16,
            color: isPengawas ? Colors.blue.shade600 : Colors.green.shade600,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'Deteksi instan aktif - QR kecil terdeteksi otomatis',
              style: TextStyle(
                color: Colors.grey.shade700,
                fontSize: 11,
              ),
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
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: isError
            ? Colors.red.shade600
            : isSuccess
                ? Colors.green.shade600
                : Colors.orange.shade600,
        borderRadius: BorderRadius.circular(10),
        boxShadow: [
          BoxShadow(
            color: (isError ? Colors.red : isSuccess ? Colors.green : Colors.orange)
                .withAlpha(100),
            blurRadius: 8,
            offset: const Offset(0, 3),
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
                size: 24,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  _info!,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 13,
                  ),
                  maxLines: 2,
                ),
              ),
            ],
          ),
          if (_lastScanTimeLabel != null)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Row(
                children: [
                  Icon(
                    Icons.schedule,
                    size: 14,
                    color: Colors.white.withAlpha(230),
                  ),
                  const SizedBox(width: 4),
                  Text(
                    _lastScanTimeLabel!,
                    style: TextStyle(
                      color: Colors.white.withAlpha(230),
                      fontSize: 11,
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
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.blue.shade600,
        borderRadius: BorderRadius.circular(10),
        boxShadow: [
          BoxShadow(
            color: Colors.blue.shade400.withAlpha(100),
            blurRadius: 8,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(
              strokeWidth: 2.5,
              valueColor: const AlwaysStoppedAnimation<Color>(Colors.white),
            ),
          ),
          const SizedBox(width: 10),
          const Text(
            'Memproses...',
            style: TextStyle(
              color: Colors.white,
              fontSize: 13,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }
}
