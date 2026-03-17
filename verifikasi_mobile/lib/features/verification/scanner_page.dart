import 'dart:async';

import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../../core/services/auth_service.dart';
import '../../core/services/offline_queue.dart';
import '../../core/theme/app_colors.dart';
import '../../core/utils/wib_time.dart';
import 'verification_service.dart';

class ScannerPage extends StatefulWidget {
  final bool isPengawas;
  final bool isActive;

  const ScannerPage({
    super.key,
    required this.isPengawas,
    this.isActive = true,
  });

  @override
  State<ScannerPage> createState() => _ScannerPageState();
}

class _ScannerPageState extends State<ScannerPage> with WidgetsBindingObserver {
  static const double _scanAreaRatio = 0.96;
  static const double _minScanAreaSize = 220.0;
  static const Duration _sameCodeCooldown = Duration(seconds: 4);
  final MobileScannerController _controller = MobileScannerController(
    detectionSpeed: DetectionSpeed.noDuplicates,
    detectionTimeoutMs: 250,
    facing: CameraFacing.back,
    formats: [BarcodeFormat.qrCode],
    cameraResolution: Size(1280, 720),
    useNewCameraSelector: false,
    autoStart: false,
  );
  bool _isProcessing = false;
  String? _lastResult;
  String? _lastStatus;
  Color? _lastColor;
  Timer? _clockTimer;
  final ValueNotifier<DateTime> _currentTimeNotifier = ValueNotifier(
    WibTime.now(),
  );
  String? _lastScannedId;
  DateTime? _lastScannedAt;
  double _zoomLevel = 0.25;
  double _baseZoomLevel = 0.25;
  AppLifecycleState _appLifecycleState = AppLifecycleState.resumed;
  bool _isCameraRunning = false;
  bool _isSyncingCamera = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _startDeviceClock();
    _flushOfflineQueue();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _syncCameraState();
    });
  }

  @override
  void didUpdateWidget(covariant ScannerPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.isActive != widget.isActive) {
      _syncCameraState();
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _appLifecycleState = state;
    _syncCameraState();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _controller.stop();
    _clockTimer?.cancel();
    _currentTimeNotifier.dispose();
    super.dispose();
  }

  bool get _shouldRunCamera =>
      widget.isActive && _appLifecycleState == AppLifecycleState.resumed;

  Future<void> _syncCameraState() async {
    if (!mounted || _isSyncingCamera) return;

    _isSyncingCamera = true;
    final shouldRun = _shouldRunCamera;

    try {
      if (shouldRun) {
        if (!_isCameraRunning) {
          await _controller.start();
          _isCameraRunning = true;
        }
        await _controller.setZoomScale(_zoomLevel);
      } else if (_isCameraRunning) {
        await _controller.stop();
        _isCameraRunning = false;
      }
    } catch (e) {
      _isCameraRunning = false;
      debugPrint('[Scanner] Failed to sync camera state: $e');
    } finally {
      _isSyncingCamera = false;
    }
  }

  Future<void> _retryCamera() async {
    try {
      await _controller.stop();
    } catch (_) {}
    _isCameraRunning = false;
    await _syncCameraState();
  }

  void _startDeviceClock() {
    _clockTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (mounted) {
        _currentTimeNotifier.value = WibTime.now();
      }
    });
  }

  String _formatTime(DateTime time) {
    final h = time.hour.toString().padLeft(2, '0');
    final m = time.minute.toString().padLeft(2, '0');
    final s = time.second.toString().padLeft(2, '0');
    return '$h:$m:$s';
  }

  void _onZoomChanged(double value) {
    setState(() => _zoomLevel = value.clamp(0.0, 1.0));
    _controller.setZoomScale(_zoomLevel);
  }

  Future<void> _flushOfflineQueue() async {
    final pending = await OfflineQueueManager.getPending();
    if (pending.isEmpty) return;

    for (int i = 0; i < pending.length; i++) {
      final item = pending[i];
      try {
        final role = item['role'] ?? '';
        final id = item['id'] ?? '';

        if (role == 'pengawas') {
          await VerificationService.accPengawas(id);
        } else if (role == 'security') {
          await VerificationService.accSecurity(id);
        }

        await OfflineQueueManager.removeAt(i);
        i--;
        debugPrint('[OfflineQueue] Flushed offline scan: $id ($role)');
      } catch (e) {
        debugPrint('[OfflineQueue] Retry failed for ${item['id']}: $e');
        break;
      }
    }
  }

  /// Extract PIN, Nama, and Bagian from barcode string to match server format
  Map<String, String> _extractBarcodeInfo(String fullBarcode) {
    final info = <String, String>{};
    try {
      final parts = fullBarcode.split('|').map((p) => p.trim()).toList();
      for (final part in parts) {
        final separatorIndex = part.indexOf(':');
        if (separatorIndex > 0) {
          final rawKey = part.substring(0, separatorIndex).trim();
          final value = part.substring(separatorIndex + 1).trim();
          if (value.isEmpty) continue;

          final normalizedKey = rawKey.toLowerCase();
          if (normalizedKey == 'pin') {
            info['PIN'] = value;
          } else if (normalizedKey == 'nama') {
            info['Nama'] = value;
          } else if (normalizedKey == 'bagian') {
            info['Bagian'] = value;
          } else {
            info[rawKey] = value;
          }
        }
      }

      if (!info.containsKey('PIN')) {
        final raw = fullBarcode.trim();
        if (RegExp(r'^[0-9]{4,}$').hasMatch(raw)) {
          info['PIN'] = raw;
        }
      }
    } catch (e) {
      debugPrint('[Scanner] Error parsing barcode: $e');
    }
    return info;
  }

  /// Normalize barcode to same format as server storage:
  /// `PIN: xxx | Nama: yyy | Bagian: zzz`
  String _normalizeBarcodeForLookup(String fullBarcode) {
    final info = _extractBarcodeInfo(fullBarcode);
    final pin = info['PIN']?.trim() ?? '';
    final nama = info['Nama']?.trim() ?? '';
    final bagian = info['Bagian']?.trim() ?? '';

    if (pin.isEmpty && nama.isEmpty && bagian.isEmpty) {
      return fullBarcode;
    }

    final parts = <String>[];
    if (pin.isNotEmpty) parts.add('PIN: $pin');
    if (nama.isNotEmpty) parts.add('Nama: $nama');
    if (bagian.isNotEmpty) parts.add('Bagian: $bagian');
    return parts.join(' | ');
  }

  String _buildScanId(Map<String, String> info, String fullBarcode) {
    final pin = info['PIN']?.trim() ?? '';
    if (pin.isNotEmpty) return pin;

    final normalized = _normalizeBarcodeForLookup(fullBarcode).trim();
    if (normalized.isNotEmpty) return normalized;

    return fullBarcode.trim();
  }

  Future<bool> _checkPengawasApproval(String normalizedIdKaryawan) async {
    try {
      final lookup = normalizedIdKaryawan.trim();
      final lookupPin = _extractBarcodeInfo(lookup)['PIN']?.trim() ?? '';
      final logs = await VerificationService.fetchLogs();
      final log = logs.firstWhere((l) {
        final logId = l['id_karyawan']?.toString().trim() ?? '';
        if (logId == lookup) return true;
        if (lookupPin.isEmpty) return false;
        if (logId == lookupPin) return true;
        final logPin = _extractBarcodeInfo(logId)['PIN']?.trim() ?? '';
        return logPin.isNotEmpty && logPin == lookupPin;
      }, orElse: () => {});
      if (log.isNotEmpty) {
        final statusPengawas = log['status_pengawas'];
        return VerificationService.isApprovedStatus(statusPengawas);
      }
      return false;
    } catch (e) {
      debugPrint('[Scanner] Error checking pengawas approval: $e');
      return false;
    }
  }

  Future<void> _onDetect(BarcodeCapture capture) async {
    if (_isProcessing) return;

    Barcode? barcode;
    for (final item in capture.barcodes) {
      final value = item.rawValue?.trim();
      if (value != null && value.isNotEmpty) {
        barcode = item;
        break;
      }
    }
    if (barcode == null) return;

    final fullBarcode = barcode.rawValue!.trim();
    final info = _extractBarcodeInfo(fullBarcode);
    final scanId = _buildScanId(info, fullBarcode);
    final pin = info['PIN'] ?? '';
    final nama = info['Nama'] ?? '';
    final now = DateTime.now();

    if (_lastScannedId == scanId &&
        _lastScannedAt != null &&
        now.difference(_lastScannedAt!) < _sameCodeCooldown) {
      return;
    }
    _lastScannedId = scanId;
    _lastScannedAt = now;

    if (pin.isEmpty) {
      setState(() {
        _lastResult = 'QR tidak dikenal';
        _lastStatus = 'error';
        _lastColor = AppColors.error;
      });
      return;
    }

    setState(() => _isProcessing = true);

    final isPengawas = widget.isPengawas;

    try {
      Map<String, dynamic> result;
      if (isPengawas) {
        result = await VerificationService.accPengawas(scanId);
      } else {
        final hasPengawasApproval = await _checkPengawasApproval(scanId);
        if (!hasPengawasApproval) {
          setState(() {
            _lastResult = '$nama (PIN: $pin)\nDitolak — Belum di-ACC Pengawas';
            _lastStatus = 'rejected';
            _lastColor = AppColors.error;
            _isProcessing = false;
          });
          return;
        }
        result = await VerificationService.accSecurity(scanId);
      }

      final message = result['message'] ?? 'Berhasil';
      final isDuplicate = message.toString().toLowerCase().contains('sudah');

      if (isDuplicate) {
        setState(() {
          _lastResult = '$nama (PIN: $pin)\n$message';
          _lastStatus = 'duplicate';
          _lastColor = AppColors.warning;
        });
      } else {
        setState(() {
          _lastResult = '$nama (PIN: $pin)\n$message';
          _lastStatus = 'success';
          _lastColor = AppColors.success;
        });
      }
    } catch (e) {
      // Offline queue fallback
      final errorStr = e.toString();
      final isConnectionError =
          errorStr.contains('Connection') ||
          errorStr.contains('refused') ||
          errorStr.contains('timeout') ||
          errorStr.contains('Host');

      if (isConnectionError) {
        await OfflineQueueManager.addPending(
          id: scanId,
          role: isPengawas ? 'pengawas' : 'security',
          username: AuthService.username ?? '',
          createdAt: DateTime.now().toIso8601String(),
        );
        setState(() {
          _lastResult =
              '$nama (PIN: $pin)\nDisimpan offline — akan dikirim saat koneksi pulih';
          _lastStatus = 'offline';
          _lastColor = AppColors.warning;
        });
      } else {
        setState(() {
          _lastResult = '$nama (PIN: $pin)\nError: $errorStr';
          _lastStatus = 'error';
          _lastColor = AppColors.error;
        });
      }
    } finally {
      if (mounted) {
        setState(() => _isProcessing = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isLocked = _isProcessing;

    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Scan Pulang',
          style: TextStyle(fontWeight: FontWeight.w600, fontSize: 16),
        ),
        backgroundColor: AppColors.surface,
        foregroundColor: AppColors.textPrimary,
        elevation: 0,
        centerTitle: true,
      ),
      backgroundColor: Colors.black,
      body: _buildScannerBox(isLocked),
    );
  }

  Widget _buildScannerBox(bool isLocked) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(20),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final scannerSize = constraints.biggest;
          final shortestSide = scannerSize.shortestSide;
          final minScanAreaSize = shortestSide < _minScanAreaSize
              ? shortestSide * 0.85
              : _minScanAreaSize;
          final scanAreaSize = (shortestSide * _scanAreaRatio).clamp(
            minScanAreaSize,
            shortestSide,
          );
          final scanWindow = Rect.fromCenter(
            center: Offset(scannerSize.width / 2, scannerSize.height / 2),
            width: scanAreaSize,
            height: scanAreaSize,
          );

          return GestureDetector(
            onScaleStart: (details) {
              _baseZoomLevel = _zoomLevel;
            },
            onScaleUpdate: (details) {
              final newZoom = (_baseZoomLevel * details.scale).clamp(0.0, 1.0);
              _onZoomChanged(newZoom);
            },
            child: Stack(
              children: [
                MobileScanner(
                  controller: _controller,
                  onDetect: _onDetect,
                  scanWindow: scanWindow,
                  errorBuilder: (context, error, child) {
                    final message =
                        error.errorCode ==
                            MobileScannerErrorCode.permissionDenied
                        ? 'Izin kamera ditolak. Aktifkan izin kamera di pengaturan aplikasi.'
                        : 'Kamera gagal dijalankan. Tekan tombol di bawah untuk mencoba lagi.';
                    return Container(
                      color: Colors.black,
                      alignment: Alignment.center,
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(
                            Icons.videocam_off,
                            color: Colors.white,
                            size: 34,
                          ),
                          const SizedBox(height: 10),
                          Text(
                            message,
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 13,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          if (error.errorCode !=
                              MobileScannerErrorCode.permissionDenied) ...[
                            const SizedBox(height: 14),
                            FilledButton.icon(
                              onPressed: _retryCamera,
                              icon: const Icon(Icons.refresh),
                              label: const Text('Coba Lagi'),
                            ),
                          ],
                        ],
                      ),
                    );
                  },
                ),
                IgnorePointer(child: _buildScannerOverlay(scanAreaSize)),
                if (!isLocked)
                  Positioned.fill(
                    child: IgnorePointer(
                      child: Container(
                        decoration: BoxDecoration(
                          border: Border.all(
                            color: AppColors.primary.withAlpha(100),
                            width: 2,
                          ),
                          borderRadius: BorderRadius.circular(20),
                        ),
                      ),
                    ),
                  ),
                Positioned(top: 16, left: 16, child: _corner(0)),
                Positioned(top: 16, right: 16, child: _corner(1)),
                Positioned(bottom: 16, right: 16, child: _corner(2)),
                Positioned(bottom: 16, left: 16, child: _corner(3)),
                Positioned(top: 20, left: 20, child: _buildClockChip()),
                if (_lastResult != null)
                  Positioned(
                    left: 16,
                    right: 16,
                    bottom: 18,
                    child: _buildResultOverlay(),
                  ),
                if (isLocked)
                  Positioned.fill(
                    child: Container(
                      color: Colors.black.withAlpha(120),
                      child: const Center(
                        child: CircularProgressIndicator(
                          color: Colors.white,
                          strokeWidth: 3,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _corner(int rotation) {
    return Transform.rotate(
      angle: rotation * 1.5708,
      child: Container(
        width: 24,
        height: 24,
        decoration: BoxDecoration(
          border: Border(
            top: BorderSide(color: AppColors.primary, width: 3),
            left: BorderSide(color: AppColors.primary, width: 3),
          ),
        ),
      ),
    );
  }

  Widget _buildClockChip() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.black.withAlpha(115),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white.withAlpha(45)),
      ),
      child: ValueListenableBuilder<DateTime>(
        valueListenable: _currentTimeNotifier,
        builder: (context, time, _) {
          return Text(
            _formatTime(time),
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              fontFeatures: [FontFeature.tabularFigures()],
              color: Colors.white,
            ),
          );
        },
      ),
    );
  }

  Widget _buildScannerOverlay(double scanAreaSize) {
    return Stack(
      children: [
        ColorFiltered(
          colorFilter: ColorFilter.mode(
            Colors.black.withAlpha(100),
            BlendMode.srcOut,
          ),
          child: Stack(
            children: [
              Container(color: Colors.black),
              Center(
                child: Container(
                  width: scanAreaSize,
                  height: scanAreaSize,
                  decoration: BoxDecoration(
                    color: Colors.black,
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
              ),
            ],
          ),
        ),
        Center(
          child: Container(
            width: scanAreaSize,
            height: scanAreaSize,
            decoration: BoxDecoration(
              border: Border.all(color: AppColors.primary, width: 3),
              borderRadius: BorderRadius.circular(16),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildResultOverlay() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.black.withAlpha(135),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: (_lastColor ?? Colors.white).withAlpha(110)),
      ),
      child: Row(
        children: [
          Icon(
            _lastStatus == 'success'
                ? Icons.check_circle
                : _lastStatus == 'duplicate'
                ? Icons.info
                : _lastStatus == 'offline'
                ? Icons.cloud_off
                : Icons.error,
            color: _lastColor ?? Colors.white,
            size: 24,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              _lastResult ?? '',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: _lastColor == AppColors.warning
                    ? Colors.white
                    : (_lastColor ?? Colors.white),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
