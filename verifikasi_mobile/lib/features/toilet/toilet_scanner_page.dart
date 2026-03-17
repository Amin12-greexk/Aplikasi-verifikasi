import 'dart:async';
import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../../core/theme/app_colors.dart';
import '../../core/utils/wib_time.dart';
import 'toilet_expiry_monitor_service.dart';
import 'toilet_permit_service.dart';

class ToiletScannerTab extends StatefulWidget {
  final bool isPengawas;
  final bool isActive;

  const ToiletScannerTab({
    super.key,
    required this.isPengawas,
    required this.isActive,
  });

  @override
  State<ToiletScannerTab> createState() => _ToiletScannerTabState();
}

class _ToiletScannerTabState extends State<ToiletScannerTab>
    with WidgetsBindingObserver {
  static const double _scanAreaRatio = 0.96;
  static const double _minScanAreaSize = 220.0;
  static const Duration _sameCodeCooldown = Duration(seconds: 4);
  static const List<int> _durationOptions = [5, 10, 15, 20, 30];

  final MobileScannerController _controller = MobileScannerController(
    detectionSpeed: DetectionSpeed.noDuplicates,
    detectionTimeoutMs: 250,
    facing: CameraFacing.back,
    formats: [BarcodeFormat.qrCode],
    cameraResolution: const Size(1280, 720),
    useNewCameraSelector: false,
    autoStart: false,
  );

  bool _isProcessing = false;
  String? _lastResult;
  String? _lastStatus;
  Color? _lastColor;
  String? _lastScannedId;
  DateTime? _lastScannedAt;
  Timer? _clockTimer;
  final ValueNotifier<DateTime> _currentTimeNotifier = ValueNotifier(
    WibTime.now(),
  );
  double _zoomLevel = 0.25;
  double _baseZoomLevel = 0.25;
  int _selectedDuration = 10;
  AppLifecycleState _appLifecycleState = AppLifecycleState.resumed;
  bool _isCameraRunning = false;
  bool _isSyncingCamera = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _clockTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      _currentTimeNotifier.value = WibTime.now();
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _syncCameraState();
    });
  }

  @override
  void didUpdateWidget(covariant ToiletScannerTab oldWidget) {
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
      debugPrint('[ToiletScanner] Failed to sync camera state: $e');
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

  String _formatClock(DateTime value) {
    final h = value.hour.toString().padLeft(2, '0');
    final m = value.minute.toString().padLeft(2, '0');
    final s = value.second.toString().padLeft(2, '0');
    return '$h:$m:$s';
  }

  String _formatTimeLabel(String? raw, {bool withSeconds = false}) {
    return WibTime.formatTime(raw, withSeconds: withSeconds);
  }

  String _userErrorMessage(Object error) {
    final message = error.toString().replaceFirst(
      RegExp(r'^Exception:\s*'),
      '',
    );
    return message.trim().isEmpty
        ? 'Terjadi kesalahan saat memproses scan'
        : message.trim();
  }

  void _onZoomChanged(double value) {
    final clamped = value.clamp(0.0, 1.0);
    setState(() => _zoomLevel = clamped);
    _controller.setZoomScale(clamped);
  }

  Map<String, String> _extractBarcodeInfo(String fullBarcode) {
    final info = <String, String>{};
    try {
      final parts = fullBarcode.split('|').map((p) => p.trim()).toList();
      for (final part in parts) {
        final separatorIndex = part.indexOf(':');
        if (separatorIndex <= 0) continue;

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

      if (!info.containsKey('PIN')) {
        final raw = fullBarcode.trim();
        if (RegExp(r'^[0-9]{4,}$').hasMatch(raw)) {
          info['PIN'] = raw;
        }
      }
    } catch (_) {}
    return info;
  }

  String _normalizeBarcodeForLookup(String fullBarcode) {
    final info = _extractBarcodeInfo(fullBarcode);
    final pin = info['PIN']?.trim() ?? '';
    final nama = info['Nama']?.trim() ?? '';
    final bagian = info['Bagian']?.trim() ?? '';

    if (pin.isEmpty && nama.isEmpty && bagian.isEmpty) {
      return fullBarcode.trim();
    }

    final parts = <String>[];
    if (pin.isNotEmpty) parts.add('PIN: $pin');
    if (nama.isNotEmpty) parts.add('Nama: $nama');
    if (bagian.isNotEmpty) parts.add('Bagian: $bagian');
    return parts.join(' | ');
  }

  String _buildScanId(Map<String, String> info, String fullBarcode) {
    final normalized = _normalizeBarcodeForLookup(fullBarcode).trim();
    if (normalized.isNotEmpty) return normalized;

    final pin = info['PIN']?.trim() ?? '';
    if (pin.isNotEmpty) return pin;

    return fullBarcode.trim();
  }

  Future<bool> _showSecurityApprovalDialog({
    required String nama,
    required String pin,
    required Map<String, dynamic> permit,
  }) async {
    final durationMinutes = permit['duration_minutes'] as int? ?? 10;
    final approvedBy = permit['approved_by']?.toString().trim() ?? '';
    final approvedAt = _formatTimeLabel(
      permit['approved_at']?.toString(),
      withSeconds: true,
    );
    final expiresAt = _formatTimeLabel(
      permit['expires_at']?.toString(),
      withSeconds: true,
    );
    final remaining = ToiletPermitService.remainingSecondsForPermit(permit);
    final alreadyScanned = ToiletPermitService.isProofScanned(permit);
    final proofBy = permit['proof_scanned_by']?.toString().trim() ?? '';
    final proofAt = _formatTimeLabel(
      permit['proof_scanned_at']?.toString(),
      withSeconds: true,
    );
    final employeeLabel = nama.isNotEmpty ? '$nama (PIN: $pin)' : 'PIN: $pin';
    final waitingSecurity = ToiletPermitService.isWaitingSecurity(permit);

    final proceed = await showDialog<bool>(
      context: context,
      barrierDismissible: !alreadyScanned,
      builder: (context) {
        return AlertDialog(
          title: Row(
            children: [
              Icon(
                alreadyScanned ? Icons.verified_user : Icons.badge,
                color: alreadyScanned ? AppColors.success : AppColors.pengawas,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  alreadyScanned
                      ? 'Izin Sudah Pernah Discan'
                      : 'Sudah Izin Pengawas',
                  style: const TextStyle(fontSize: 18),
                ),
              ),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                employeeLabel,
                style: const TextStyle(
                  fontWeight: FontWeight.w700,
                  color: AppColors.textPrimary,
                ),
              ),
              const SizedBox(height: 12),
              _modalInfoRow(
                'Disetujui oleh',
                approvedBy.isEmpty ? 'Pengawas belum tercatat' : approvedBy,
              ),
              const SizedBox(height: 8),
              _modalInfoRow(
                'Jam disetujui',
                approvedAt == '-' ? 'Belum ada jam persetujuan' : approvedAt,
              ),
              const SizedBox(height: 8),
              _modalInfoRow(
                waitingSecurity ? 'Durasi izin' : 'Batas kembali',
                waitingSecurity
                    ? '$durationMinutes menit'
                    : (expiresAt == '-' ? 'Batas belum tersedia' : expiresAt),
              ),
              const SizedBox(height: 8),
              _modalInfoRow(
                waitingSecurity ? 'Timer mulai' : 'Sisa waktu',
                waitingSecurity
                    ? 'Saat security scan ini'
                    : ToiletPermitService.formatRemainingDetailedLabel(
                        remaining,
                      ),
              ),
              if (alreadyScanned) ...[
                const SizedBox(height: 8),
                _modalInfoRow(
                  'Security',
                  '${proofBy.isEmpty ? 'Sudah discan security' : proofBy} ${proofAt == '-' ? '' : 'pada $proofAt'}'
                      .trim(),
                ),
              ],
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: Text(alreadyScanned ? 'Tutup' : 'Batal'),
            ),
            if (!alreadyScanned)
              FilledButton(
                onPressed: () => Navigator.of(context).pop(true),
                child: const Text('Lanjut Proof Scan'),
              ),
          ],
        );
      },
    );

    return proceed ?? false;
  }

  Widget _modalInfoRow(String label, String value) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w600,
            color: AppColors.textSecondary,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          value,
          style: const TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: AppColors.textPrimary,
          ),
        ),
      ],
    );
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

    try {
      Map<String, dynamic> result;
      if (widget.isPengawas) {
        result = await ToiletPermitService.approvePermit(
          scanId,
          durationMinutes: _selectedDuration,
        );
      } else {
        final permitStatus = await ToiletPermitService.fetchPermitStatus(
          scanId,
        );
        if (ToiletPermitService.isExpiredPermit(permitStatus)) {
          setState(() {
            _lastResult = '$nama (PIN: $pin)\nIzin toilet sudah habis';
            _lastStatus = 'error';
            _lastColor = AppColors.error;
          });
          return;
        }

        final shouldContinue = await _showSecurityApprovalDialog(
          nama: nama,
          pin: pin,
          permit: permitStatus,
        );
        if (!mounted) return;
        if (!shouldContinue) {
          if (ToiletPermitService.isProofScanned(permitStatus)) {
            final proofBy = permitStatus['proof_scanned_by']?.toString().trim();
            final proofAt = _formatTimeLabel(
              permitStatus['proof_scanned_at']?.toString(),
              withSeconds: true,
            );
            setState(() {
              _lastResult =
                  '$nama (PIN: $pin)\nSudah pernah discan security${proofBy == null || proofBy.isEmpty ? '' : ' oleh $proofBy'}${proofAt == '-' ? '' : ' pada $proofAt'}';
              _lastStatus = 'duplicate';
              _lastColor = AppColors.warning;
            });
          }
          return;
        }
        result = await ToiletPermitService.proofScan(scanId);
      }

      final message = result['message']?.toString() ?? 'Berhasil';
      final isDuplicate = message.toLowerCase().contains('sudah');
      final remaining = ToiletPermitService.remainingSecondsForPermit(result);
      final expiryLabel = _formatTimeLabel(result['expires_at']?.toString());
      final proofStartLabel = _formatTimeLabel(
        result['proof_scanned_at']?.toString(),
        withSeconds: true,
      );

      final details = widget.isPengawas
          ? '$message\nDurasi: ${result['duration_minutes']} menit | Timer mulai setelah security scan'
          : '$message\nMulai: $proofStartLabel | Batas: $expiryLabel\nSisa waktu: ${ToiletPermitService.formatRemainingLabel(remaining)}';

      setState(() {
        _lastResult = '$nama (PIN: $pin)\n$details';
        _lastStatus = isDuplicate ? 'duplicate' : 'success';
        _lastColor = isDuplicate ? AppColors.warning : AppColors.success;
      });
      await ToiletExpiryMonitorService.refreshNow();
    } catch (e) {
      final errorStr = _userErrorMessage(e);
      setState(() {
        _lastResult = '$nama (PIN: $pin)\n$errorStr';
        _lastStatus = 'error';
        _lastColor = AppColors.error;
      });
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
      children: [Expanded(child: _buildScannerBox(isPengawas, isLocked))],
    );
  }

  Widget _buildScannerBox(bool isPengawas, bool isLocked) {
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
            onScaleStart: (_) {
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
                if (isPengawas)
                  Positioned(
                    top: 20,
                    right: 20,
                    child: _buildDurationChip(isLocked),
                  ),
                if (_lastResult != null)
                  Positioned(
                    left: 16,
                    right: 16,
                    bottom: 18,
                    child: _buildResultOverlay(),
                  ),
                if (_isProcessing)
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
        decoration: const BoxDecoration(
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
            _formatClock(time),
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

  Widget _buildDurationChip(bool isLocked) {
    return Material(
      color: Colors.transparent,
      child: PopupMenuButton<int>(
        tooltip: 'Pilih Durasi Izin',
        initialValue: _selectedDuration,
        enabled: !isLocked,
        padding: EdgeInsets.zero,
        position: PopupMenuPosition.under,
        onSelected: (value) => setState(() => _selectedDuration = value),
        itemBuilder: (context) => _durationOptions
            .map(
              (option) => PopupMenuItem<int>(
                value: option,
                child: Text('$option menit'),
              ),
            )
            .toList(),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: Colors.black.withAlpha(isLocked ? 155 : 115),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: isLocked
                  ? Colors.white.withAlpha(70)
                  : AppColors.pengawas.withAlpha(95),
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.timer_outlined,
                size: 16,
                color: isLocked ? Colors.white : AppColors.pengawasSurface,
              ),
              const SizedBox(width: 6),
              Text(
                '${_selectedDuration}m',
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: Colors.white,
                ),
              ),
            ],
          ),
        ),
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
