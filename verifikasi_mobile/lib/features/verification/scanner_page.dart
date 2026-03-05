import 'dart:async';

import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../../core/services/auth_service.dart';
import '../../core/services/offline_queue.dart';
import '../../core/services/tts_service.dart';
import '../../core/theme/app_colors.dart';
import 'verification_service.dart';

class ScannerTab extends StatefulWidget {
  final bool isPengawas;

  const ScannerTab({super.key, required this.isPengawas});

  @override
  State<ScannerTab> createState() => _ScannerTabState();
}

class _ScannerTabState extends State<ScannerTab> {
  static const double _scanAreaRatio = 0.92;
  static const double _minScanAreaSize = 220.0;
  static const Duration _sameCodeCooldown = Duration(seconds: 4);
  final MobileScannerController _controller = MobileScannerController(
    detectionSpeed: DetectionSpeed.noDuplicates,
    detectionTimeoutMs: 250,
    facing: CameraFacing.back,
    formats: [BarcodeFormat.qrCode],
    cameraResolution: Size(1280, 720),
    useNewCameraSelector: false,
  );
  bool _isProcessing = false;
  String? _lastResult;
  String? _lastStatus;
  Color? _lastColor;
  bool _torchOn = false;
  Timer? _clockTimer;
  final ValueNotifier<DateTime> _currentTimeNotifier = ValueNotifier(
    DateTime.now(),
  );
  String? _lastScannedId;
  DateTime? _lastScannedAt;
  double _zoomLevel = 0.25;
  double _baseZoomLevel = 0.25;

  @override
  void initState() {
    super.initState();
    TtsService.initialize();
    _startDeviceClock();
    _flushOfflineQueue();
    // Apply default zoom after camera starts
    Future.delayed(const Duration(milliseconds: 1500), () async {
      if (mounted) {
        try {
          await _controller.setZoomScale(_zoomLevel);
        } catch (_) {}
      }
    });
  }

  @override
  void dispose() {
    _clockTimer?.cancel();
    _currentTimeNotifier.dispose();
    super.dispose();
  }

  void _startDeviceClock() {
    _clockTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (mounted) {
        _currentTimeNotifier.value = DateTime.now();
      }
    });
  }

  String _formatTime(DateTime time) {
    final h = time.hour.toString().padLeft(2, '0');
    final m = time.minute.toString().padLeft(2, '0');
    final s = time.second.toString().padLeft(2, '0');
    return '$h:$m:$s';
  }

  Future<void> _playSound(Future<void> Function() soundFunction) async {
    try {
      await soundFunction();
    } catch (e) {
      print('[TTS] Error playing sound: $e');
    }
  }

  void _handleTorchState() {
    _controller.toggleTorch();
    setState(() => _torchOn = !_torchOn);
  }

  void _resetZoom() {
    setState(() {
      _zoomLevel = 0.25;
      _baseZoomLevel = 0.25;
    });
    _controller.setZoomScale(0.25);
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
        print('[OfflineQueue] Flushed offline scan: $id ($role)');
      } catch (e) {
        print('[OfflineQueue] Retry failed for ${item['id']}: $e');
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
      print('[Scanner] Error parsing barcode: $e');
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
      print('[Scanner] Error checking pengawas approval: $e');
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
      await _playSound(TtsService.qrTidakDikenal);
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
          await _playSound(TtsService.ditolakBelumPengawas);
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
        await _playSound(
          isPengawas
              ? TtsService.duplikatPengawas
              : TtsService.duplikatSecurity,
        );
      } else {
        setState(() {
          _lastResult = '$nama (PIN: $pin)\n$message';
          _lastStatus = 'success';
          _lastColor = AppColors.success;
        });
        await _playSound(
          isPengawas
              ? TtsService.scanPengawasBerhasil
              : TtsService.scanSecurityBerhasil,
        );
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
        await _playSound(TtsService.gagalKoneksi);
      } else {
        setState(() {
          _lastResult = '$nama (PIN: $pin)\nError: $errorStr';
          _lastStatus = 'error';
          _lastColor = AppColors.error;
        });
        await _playSound(TtsService.gagalKoneksi);
      }
    } finally {
      if (mounted) {
        setState(() => _isProcessing = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isPengawas = widget.isPengawas;
    final isLocked = _isProcessing;

    return Column(
      children: [
        _buildHeader(isPengawas, isLocked),
        const SizedBox(height: 12),
        _buildAlertBox(isPengawas, isLocked),
        const SizedBox(height: 12),
        Expanded(child: _buildScannerBox(isLocked)),
        const SizedBox(height: 8),
        _buildZoomSlider(),
        const SizedBox(height: 8),
        _buildModeDescription(isPengawas),
        const SizedBox(height: 12),
        if (_lastResult != null) _buildResultBox(),
        if (_isProcessing) _buildProcessing(),
        const SizedBox(height: 8),
      ],
    );
  }

  Widget _buildHeader(bool isPengawas, bool isLocked) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.cardBorder),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: isPengawas
                  ? AppColors.pengawasSurface
                  : AppColors.securitySurface,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(
              isPengawas ? Icons.badge : Icons.security,
              color: isPengawas ? AppColors.pengawas : AppColors.security,
              size: 22,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Scanner ${isPengawas ? "Pengawas" : "Security"}',
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textPrimary,
                  ),
                ),
                Text(
                  'Mode: ${isPengawas ? "Verifikasi Layer 1" : "Verifikasi Layer 2"}',
                  style: const TextStyle(
                    fontSize: 12,
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: AppColors.background,
              borderRadius: BorderRadius.circular(8),
            ),
            child: ValueListenableBuilder<DateTime>(
              valueListenable: _currentTimeNotifier,
              builder: (context, time, _) {
                return Text(
                  _formatTime(time),
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    fontFeatures: [FontFeature.tabularFigures()],
                    color: AppColors.textPrimary,
                  ),
                );
              },
            ),
          ),
          const SizedBox(width: 4),
          IconButton(
            onPressed: _resetZoom,
            tooltip: 'Reset Zoom 25%',
            icon: const Icon(
              Icons.center_focus_strong,
              color: AppColors.textSecondary,
              size: 20,
            ),
          ),
          IconButton(
            onPressed: _handleTorchState,
            icon: Icon(
              _torchOn ? Icons.flash_on : Icons.flash_off,
              color: _torchOn ? AppColors.warning : AppColors.textSecondary,
              size: 20,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAlertBox(bool isPengawas, bool isLocked) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: isLocked
            ? AppColors.warning.withAlpha(20)
            : (isPengawas
                  ? AppColors.pengawasSurface
                  : AppColors.securitySurface),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isLocked
              ? AppColors.warning.withAlpha(60)
              : (isPengawas
                    ? AppColors.pengawas.withAlpha(40)
                    : AppColors.security.withAlpha(40)),
        ),
      ),
      child: Row(
        children: [
          Icon(
            isLocked ? Icons.hourglass_top : Icons.info_outline,
            size: 18,
            color: isLocked
                ? AppColors.warning
                : (isPengawas ? AppColors.pengawas : AppColors.security),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              isLocked
                  ? 'Sedang memproses scan... Harap tunggu.'
                  : isPengawas
                  ? 'Arahkan kamera ke QR karyawan untuk verifikasi Layer 1.'
                  : 'Arahkan kamera ke QR karyawan untuk verifikasi Layer 2.',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w500,
                color: isLocked
                    ? AppColors.warning
                    : (isPengawas ? AppColors.pengawas : AppColors.security),
              ),
            ),
          ),
        ],
      ),
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
                        : 'Kamera gagal dijalankan. Tutup dan buka ulang halaman scanner.';
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
                        ],
                      ),
                    );
                  },
                ),
                // Scanner target overlay
                _buildScannerOverlay(scanAreaSize),
                // Corner decorations
                Positioned(top: 16, left: 16, child: _corner(0)),
                Positioned(top: 16, right: 16, child: _corner(1)),
                Positioned(bottom: 16, right: 16, child: _corner(2)),
                Positioned(bottom: 16, left: 16, child: _corner(3)),
                // Zoom indicator
                Positioned(
                  bottom: 12,
                  left: 0,
                  right: 0,
                  child: Center(
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.black.withAlpha(140),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        '${(_zoomLevel * 100).toInt()}% zoom',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                ),
                // Scan border
                if (!isLocked)
                  Positioned.fill(
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

  Widget _buildScannerOverlay(double scanAreaSize) {
    return Stack(
      children: [
        // Semi-transparent background outside scan window
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
        // Central target box
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
        // Instructions
        Positioned(
          top: 20,
          left: 0,
          right: 0,
          child: const Center(
            child: Text(
              'Posisikan QR di dalam kotak',
              style: TextStyle(
                color: Colors.white,
                fontSize: 14,
                fontWeight: FontWeight.w600,
                shadows: [Shadow(color: Colors.black, blurRadius: 4)],
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildZoomSlider() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.cardBorder),
      ),
      child: Row(
        children: [
          const Icon(Icons.zoom_out, size: 18, color: AppColors.textSecondary),
          Expanded(
            child: SliderTheme(
              data: SliderTheme.of(context).copyWith(
                trackHeight: 3,
                thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 7),
                overlayShape: const RoundSliderOverlayShape(overlayRadius: 14),
                activeTrackColor: AppColors.primary,
                inactiveTrackColor: AppColors.primary.withAlpha(40),
                thumbColor: AppColors.primary,
                overlayColor: AppColors.primary.withAlpha(30),
              ),
              child: Slider(
                value: _zoomLevel,
                min: 0.0,
                max: 1.0,
                onChanged: _onZoomChanged,
              ),
            ),
          ),
          const Icon(Icons.zoom_in, size: 18, color: AppColors.textSecondary),
          const SizedBox(width: 6),
          SizedBox(
            width: 38,
            child: Text(
              '${(_zoomLevel * 100).toInt()}%',
              style: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: AppColors.textPrimary,
              ),
              textAlign: TextAlign.center,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildModeDescription(bool isPengawas) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.cardBorder),
      ),
      child: Row(
        children: [
          Icon(
            isPengawas ? Icons.verified_user : Icons.shield,
            size: 20,
            color: isPengawas ? AppColors.pengawas : AppColors.security,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              isPengawas
                  ? 'Pengawas: Scan QR untuk ACC sebelum karyawan checkout.'
                  : 'Security: Scan QR setelah karyawan mendapat ACC pengawas.',
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w400,
                color: AppColors.textSecondary,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildResultBox() {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: (_lastColor ?? AppColors.textSecondary).withAlpha(20),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: (_lastColor ?? AppColors.textSecondary).withAlpha(60),
        ),
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
            color: _lastColor ?? AppColors.textSecondary,
            size: 28,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              _lastResult ?? '',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w500,
                color: _lastColor ?? AppColors.textSecondary,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildProcessing() {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.primary.withAlpha(20),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.primary.withAlpha(60)),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 22,
            height: 22,
            child: CircularProgressIndicator(
              strokeWidth: 2.5,
              valueColor: AlwaysStoppedAnimation<Color>(AppColors.primary),
            ),
          ),
          const SizedBox(width: 12),
          const Expanded(
            child: Text(
              'Memproses scan...',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w500,
                color: AppColors.primary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
