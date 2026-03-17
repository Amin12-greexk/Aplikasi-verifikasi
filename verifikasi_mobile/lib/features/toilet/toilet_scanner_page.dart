import 'dart:async';
import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../../core/theme/app_colors.dart';
import '../../core/services/tts_service.dart';
import 'toilet_permit_service.dart';

class ToiletScannerTab extends StatefulWidget {
  final bool isPengawas;

  const ToiletScannerTab({super.key, required this.isPengawas});

  @override
  State<ToiletScannerTab> createState() => _ToiletScannerTabState();
}

class _ToiletScannerTabState extends State<ToiletScannerTab> {
  static const double _scanAreaRatio = 0.92;
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
  );

  bool _isProcessing = false;
  bool _torchOn = false;
  String? _lastResult;
  String? _lastStatus;
  Color? _lastColor;
  String? _lastScannedId;
  DateTime? _lastScannedAt;
  Timer? _clockTimer;
  final ValueNotifier<DateTime> _currentTimeNotifier = ValueNotifier(
    DateTime.now(),
  );
  double _zoomLevel = 0.25;
  double _baseZoomLevel = 0.25;
  int _selectedDuration = 10;

  @override
  void initState() {
    super.initState();
    TtsService.initialize();
    _clockTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      _currentTimeNotifier.value = DateTime.now();
    });
    Future.delayed(const Duration(milliseconds: 1500), () async {
      if (!mounted) return;
      try {
        await _controller.setZoomScale(_zoomLevel);
      } catch (_) {}
    });
  }

  @override
  void dispose() {
    _clockTimer?.cancel();
    _currentTimeNotifier.dispose();
    super.dispose();
  }

  String _formatClock(DateTime value) {
    final h = value.hour.toString().padLeft(2, '0');
    final m = value.minute.toString().padLeft(2, '0');
    final s = value.second.toString().padLeft(2, '0');
    return '$h:$m:$s';
  }

  String _formatTimeLabel(String? raw) {
    final parsed = ToiletPermitService.parseDateTime(raw);
    if (parsed == null) return '-';

    final local = parsed.toLocal();
    final h = local.hour.toString().padLeft(2, '0');
    final m = local.minute.toString().padLeft(2, '0');
    return '$h:$m';
  }

  Future<void> _playSound(Future<void> Function() soundFunction) async {
    try {
      await soundFunction();
    } catch (_) {}
  }

  void _toggleTorch() {
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

    try {
      Map<String, dynamic> result;
      if (widget.isPengawas) {
        result = await ToiletPermitService.approvePermit(
          scanId,
          durationMinutes: _selectedDuration,
        );
      } else {
        result = await ToiletPermitService.proofScan(scanId);
      }

      final message = result['message']?.toString() ?? 'Berhasil';
      final isDuplicate = message.toLowerCase().contains('sudah');
      final remaining = ToiletPermitService.remainingSecondsForPermit(result);
      final expiryLabel = _formatTimeLabel(result['expires_at']?.toString());

      final details = widget.isPengawas
          ? '$message\nDurasi: ${result['duration_minutes']} menit • Batas: $expiryLabel'
          : '$message\nSisa waktu: ${ToiletPermitService.formatRemainingLabel(remaining)} • Batas: $expiryLabel';

      setState(() {
        _lastResult = '$nama (PIN: $pin)\n$details';
        _lastStatus = isDuplicate ? 'duplicate' : 'success';
        _lastColor = isDuplicate ? AppColors.warning : AppColors.success;
      });

      await _playSound(
        isDuplicate
            ? (widget.isPengawas
                  ? TtsService.duplikatPengawas
                  : TtsService.duplikatSecurity)
            : (widget.isPengawas
                  ? TtsService.scanPengawasBerhasil
                  : TtsService.scanSecurityBerhasil),
      );
    } catch (e) {
      final errorStr = e.toString();
      setState(() {
        _lastResult = '$nama (PIN: $pin)\n$errorStr';
        _lastStatus = 'error';
        _lastColor = AppColors.error;
      });
      await _playSound(TtsService.gagalKoneksi);
    } finally {
      if (mounted) {
        setState(() => _isProcessing = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isPengawas = widget.isPengawas;

    return Column(
      children: [
        _buildHeader(isPengawas),
        const SizedBox(height: 12),
        _buildAlertBox(isPengawas),
        if (isPengawas) ...[
          const SizedBox(height: 12),
          _buildDurationSelector(),
        ],
        const SizedBox(height: 12),
        Expanded(child: _buildScannerBox()),
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

  Widget _buildHeader(bool isPengawas) {
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
              Icons.wc,
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
                  isPengawas
                      ? 'Scanner Izin Toilet Pengawas'
                      : 'Scanner Proof Toilet Security',
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textPrimary,
                  ),
                ),
                Text(
                  isPengawas
                      ? 'Buat izin toilet dan timer mitra'
                      : 'Validasi QR mitra yang sudah diizinkan',
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
                  _formatClock(time),
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
            onPressed: _toggleTorch,
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

  Widget _buildAlertBox(bool isPengawas) {
    final color = _isProcessing
        ? AppColors.warning
        : (isPengawas ? AppColors.pengawas : AppColors.security);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: color.withAlpha(18),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withAlpha(45)),
      ),
      child: Row(
        children: [
          Icon(
            _isProcessing ? Icons.hourglass_top : Icons.info_outline,
            size: 18,
            color: color,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              _isProcessing
                  ? 'Sedang memproses izin toilet... Harap tunggu.'
                  : isPengawas
                  ? 'Scan QR mitra untuk memberi izin toilet dan mengaktifkan timer.'
                  : 'Scan QR mitra untuk memastikan izin toilet masih aktif.',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w500,
                color: color,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDurationSelector() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.cardBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Durasi Izin Toilet',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: _durationOptions.map((option) {
              final isSelected = _selectedDuration == option;
              return InkWell(
                onTap: () => setState(() => _selectedDuration = option),
                borderRadius: BorderRadius.circular(10),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: isSelected
                        ? AppColors.pengawas
                        : AppColors.background,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: isSelected
                          ? AppColors.pengawas
                          : AppColors.cardBorder,
                    ),
                  ),
                  child: Text(
                    '$option menit',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: isSelected
                          ? Colors.white
                          : AppColors.textSecondary,
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }

  Widget _buildScannerBox() {
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
                _buildScannerOverlay(scanAreaSize),
                Positioned(top: 16, left: 16, child: _corner(0)),
                Positioned(top: 16, right: 16, child: _corner(1)),
                Positioned(bottom: 16, right: 16, child: _corner(2)),
                Positioned(bottom: 16, left: 16, child: _corner(3)),
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
        const Positioned(
          top: 20,
          left: 0,
          right: 0,
          child: Center(
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
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: AppColors.textPrimary,
              ),
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
            Icons.info_outline,
            size: 20,
            color: isPengawas ? AppColors.pengawas : AppColors.security,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              isPengawas
                  ? 'Pengawas: scan QR untuk membuat izin toilet dengan timer aktif.'
                  : 'Security: scan QR untuk membuktikan bahwa izin toilet masih berlaku.',
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
      child: const Row(
        children: [
          SizedBox(
            width: 22,
            height: 22,
            child: CircularProgressIndicator(
              strokeWidth: 2.5,
              valueColor: AlwaysStoppedAnimation<Color>(AppColors.primary),
            ),
          ),
          SizedBox(width: 12),
          Expanded(
            child: Text(
              'Memproses izin toilet...',
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
