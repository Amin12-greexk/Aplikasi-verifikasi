import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../../core/services/auth_service.dart';
import '../../core/services/offline_queue.dart';
import '../../core/services/tts_service.dart';
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

class _ScannerPageState extends State<ScannerPage>
    with WidgetsBindingObserver, SingleTickerProviderStateMixin {
  static const double _scanAreaRatio = 0.96;
  static const double _minScanAreaSize = 220.0;
  static const Duration _sameCodeCooldown = Duration(
    seconds: 1,
  ); // reset cepat antar scan
  static const Duration _hardwareScanSettleDelay = Duration(milliseconds: 150);

  final MobileScannerController _controller = MobileScannerController(
    detectionSpeed: DetectionSpeed.normal,
    detectionTimeoutMs: 250, // Lebih rileks agar sensor punya waktu fokus
    facing: CameraFacing.back,
    formats: [BarcodeFormat.qrCode],
    // cameraResolution dihilangkan agar sistem memilih yang paling optimal
    useNewCameraSelector: true,
    autoStart: false,
  );

  bool _isProcessing = false;
  String? _lastResult;
  String? _lastStatus;
  Color? _lastColor;
  String? _lastScannedId;
  DateTime? _lastScannedAt;
  String? _lastScanSource;
  Timer? _clockTimer;
  Timer? _resetTimer; // auto-reset scanner 1 detik setelah scan selesai
  Timer? _hardwareScanDebounceTimer;
  final StringBuffer _hardwareScanBuffer = StringBuffer();
  final FocusNode _hardwareScannerFocusNode = FocusNode(
    debugLabel: 'security-hardware-scanner',
  );
  final ValueNotifier<DateTime> _currentTimeNotifier = ValueNotifier(
    WibTime.now(),
  );
  late final AnimationController _pulseController;
  double _zoomLevel = 0.0;
  double _baseZoomLevel = 0.0;
  AppLifecycleState _appLifecycleState = AppLifecycleState.resumed;
  bool _isCameraRunning = false;
  bool _isSyncingCamera = false;
  bool _useCameraFallback = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    )..repeat(reverse: true);
    _clockTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      _currentTimeNotifier.value = WibTime.now();
    });
    _flushOfflineQueue();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _syncCameraState();
      _requestHardwareScannerFocus();
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
    if (state == AppLifecycleState.resumed) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _requestHardwareScannerFocus();
      });
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _controller.stop();
    _clockTimer?.cancel();
    _resetTimer?.cancel();
    _hardwareScanDebounceTimer?.cancel();
    _hardwareScannerFocusNode.dispose();
    _currentTimeNotifier.dispose();
    _pulseController.dispose();
    super.dispose();
  }

  bool get _shouldRunCamera =>
      (widget.isPengawas || _useCameraFallback) &&
      widget.isActive &&
      _appLifecycleState == AppLifecycleState.resumed;

  CameraFacing get _desiredCameraFacing =>
      widget.isPengawas ? CameraFacing.back : CameraFacing.front;

  Future<void> _syncCameraState() async {
    if (!mounted || _isSyncingCamera) return;

    _isSyncingCamera = true;
    final shouldRun = _shouldRunCamera;

    try {
      if (shouldRun) {
        if (!_isCameraRunning) {
          await _controller.start(cameraFacingOverride: _desiredCameraFacing);
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

  /// Otomatis reset scanner 1 detik setelah processing selesai.
  /// Ini mencegah bug di mana user harus keluar halaman untuk bisa scan ulang.
  void _scheduleAutoReset() {
    _resetTimer?.cancel();
    _resetTimer = Timer(const Duration(seconds: 1), () {
      if (!mounted) return;
      setState(() {
        _lastResult = null;
        _lastStatus = null;
        _lastColor = null;
        _lastScannedId = null;
        _lastScannedAt = null;
        _lastScanSource = null;
        _isProcessing = false;
      });
      // Pastikan kamera sudah running kembali
      _syncCameraState();
      _requestHardwareScannerFocus();
    });
  }

  void _requestHardwareScannerFocus() {
    if (!mounted || widget.isPengawas || _useCameraFallback) return;
    if (!_hardwareScannerFocusNode.hasFocus) {
      FocusScope.of(context).requestFocus(_hardwareScannerFocusNode);
    }
  }

  Future<void> _setSecurityCameraFallback(bool enabled) async {
    if (widget.isPengawas || _useCameraFallback == enabled) return;
    _hardwareScanBuffer.clear();
    _hardwareScanDebounceTimer?.cancel();
    setState(() {
      _useCameraFallback = enabled;
      _lastScanSource = null;
    });
    if (enabled) _hardwareScannerFocusNode.unfocus();
    await _syncCameraState();
    if (!enabled) _requestHardwareScannerFocus();
  }

  KeyEventResult _handleHardwareScannerKey(FocusNode node, KeyEvent event) {
    if (widget.isPengawas || _useCameraFallback || event is! KeyDownEvent) {
      return KeyEventResult.ignored;
    }

    if (_isProcessing) {
      _hardwareScanBuffer.clear();
      _hardwareScanDebounceTimer?.cancel();
      return KeyEventResult.handled;
    }

    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.enter ||
        key == LogicalKeyboardKey.numpadEnter ||
        key == LogicalKeyboardKey.tab) {
      _submitHardwareScanBuffer();
      return KeyEventResult.handled;
    }

    final character = event.character;
    if (character == null ||
        character.isEmpty ||
        character.codeUnits.any((unit) => unit < 32)) {
      return KeyEventResult.ignored;
    }

    _hardwareScanBuffer.write(character);
    _hardwareScanDebounceTimer?.cancel();
    _hardwareScanDebounceTimer = Timer(
      _hardwareScanSettleDelay,
      _submitHardwareScanBuffer,
    );
    return KeyEventResult.handled;
  }

  void _submitHardwareScanBuffer() {
    _hardwareScanDebounceTimer?.cancel();
    final rawScan = _hardwareScanBuffer.toString().trim();
    _hardwareScanBuffer.clear();
    if (rawScan.isEmpty) return;
    unawaited(_processRawScan(rawScan, source: 'scanner'));
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
    final raw = fullBarcode.trim();
    if (raw.isEmpty) return info;

    try {
      // 1. Cek format CSV (N, NAMA, NIK, ...) atau (NAMA, N, NIK, ...) - Prioritas Tinggi
      if (raw.contains(',') && !raw.contains(':')) {
        final parts = raw.split(',');
        if (parts.length >= 2) {
          // Cari PIN: biasanya field yang hanya berisi angka (numeric)
          // Kita cek 2 index pertama karena posisi PIN bisa di index 0 atau 1
          int pinIndex = -1;
          if (RegExp(r'^[0-9]+$').hasMatch(parts[0].trim())) {
            pinIndex = 0;
          } else if (RegExp(r'^[0-9]+$').hasMatch(parts[1].trim())) {
            pinIndex = 1;
          }

          if (pinIndex != -1) {
            final pin = parts[pinIndex].trim();
            final nama = parts[pinIndex == 0 ? 1 : 0].trim();
            if (pin.isEmpty || nama.isEmpty) return <String, String>{};

            info['PIN'] = pin;
            // Nama adalah index yang bukan PIN (antara 0 atau 1)
            info['Nama'] = nama;

            // Cari Bagian: biasanya di field yang mengandung kata 'Group' atau index ke-4 (Sarirejo...)
            // atau mengikuti header standar index ke-9. Kita coba cari yang paling masuk akal.
            if (parts.length >= 10) {
              info['Bagian'] = parts[9].trim();
            } else if (parts.length >= 4) {
              // Jika data lebih pendek, coba ambil field ke-4 (index 3)
              info['Bagian'] = parts[3].trim();
            }
            return info;
          }
        }
      }

      // 2. Format standar: PIN: xxx | Nama: yyy
      final parts = raw.split('|').map((p) => p.trim()).toList();
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
    } catch (e) {
      debugPrint('[Scanner] Error parsing barcode: $e');
    }

    final pin = info['PIN']?.trim() ?? '';
    final nama = info['Nama']?.trim() ?? '';
    if (pin.isEmpty || nama.isEmpty) return <String, String>{};

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
      return '';
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

    return '';
  }

  Future<void> _onDetect(BarcodeCapture capture) async {
    Barcode? barcode;
    for (final item in capture.barcodes) {
      final value = item.rawValue?.trim();
      if (value != null && value.isNotEmpty) {
        barcode = item;
        break;
      }
    }
    if (barcode == null) return;

    await _processRawScan(barcode.rawValue!.trim(), source: 'camera');
  }

  Future<void> _playSecurityFeedback(String status) async {
    if (widget.isPengawas) return;

    switch (status) {
      case 'success':
        await TtsService.scanSecurityBerhasil();
        break;
      case 'duplicate':
        await TtsService.duplikatSecurity();
        break;
      case 'rejected':
        await TtsService.ditolakBelumPengawas();
        break;
      case 'offline':
        await TtsService.gagalKoneksi();
        break;
      default:
        await TtsService.qrTidakDikenal();
    }
  }

  Future<void> _processRawScan(
    String fullBarcode, {
    required String source,
  }) async {
    if (_isProcessing) return;

    final raw = fullBarcode.trim();
    if (raw.isEmpty) return;

    final info = _extractBarcodeInfo(raw);
    final scanId = _buildScanId(info, raw);
    final pin = info['PIN'] ?? '';
    final nama = info['Nama'] ?? '';
    final employeeLabel = nama.isEmpty ? 'PIN: $pin' : '$nama (PIN: $pin)';
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
        _lastScanSource = source;
      });
      unawaited(_playSecurityFeedback('error'));
      _scheduleAutoReset();
      return;
    }

    setState(() {
      _isProcessing = true;
      _lastScanSource = source;
    });

    final isPengawas = widget.isPengawas;

    try {
      Map<String, dynamic> result;
      if (isPengawas) {
        result = await VerificationService.accPengawas(scanId);
      } else {
        // Langsung POST ke server — tidak perlu GET /status dulu.
        // Server sudah return error jika belum di-ACC pengawas.
        result = await VerificationService.accSecurity(scanId);
      }

      final message = result['message'] ?? 'Berhasil';
      final isDuplicate = message.toString().toLowerCase().contains('sudah');
      final status = isDuplicate ? 'duplicate' : 'success';

      setState(() {
        _lastResult = isPengawas
            ? '$employeeLabel\n$message'
            : '$employeeLabel\nSilakan pulang';
        _lastStatus = status;
        _lastColor = isDuplicate ? AppColors.warning : AppColors.success;
      });
      unawaited(_playSecurityFeedback(status));
    } catch (e) {
      final errorStr = e.toString().replaceFirst(RegExp(r'^Exception:\s*'), '');
      final isConnectionError =
          errorStr.contains('Connection') ||
          errorStr.contains('refused') ||
          errorStr.contains('timeout') ||
          errorStr.contains('Host');
      // Cek apakah server menolak karena belum di-ACC pengawas
      final isRejected =
          errorStr.toLowerCase().contains('belum') ||
          errorStr.toLowerCase().contains('pengawas');

      if (isConnectionError) {
        await OfflineQueueManager.addPending(
          id: scanId,
          role: isPengawas ? 'pengawas' : 'security',
          username: AuthService.username ?? '',
          createdAt: DateTime.now().toIso8601String(),
        );
        setState(() {
          _lastResult =
              '$employeeLabel\nDisimpan offline, akan dikirim saat koneksi pulih';
          _lastStatus = 'offline';
          _lastColor = AppColors.warning;
        });
        unawaited(_playSecurityFeedback('offline'));
      } else if (isRejected) {
        setState(() {
          _lastResult = '$employeeLabel\nDitolak, belum di-ACC Pengawas';
          _lastStatus = 'rejected';
          _lastColor = AppColors.error;
        });
        unawaited(_playSecurityFeedback('rejected'));
      } else {
        setState(() {
          _lastResult = '$employeeLabel\n$errorStr';
          _lastStatus = 'error';
          _lastColor = AppColors.error;
        });
        unawaited(_playSecurityFeedback('error'));
      }
    } finally {
      if (mounted) {
        setState(() => _isProcessing = false);
        _scheduleAutoReset(); // reset otomatis 1 detik setelah scan selesai
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isLocked = _isProcessing;
    final isPengawas = widget.isPengawas;

    return Scaffold(
      appBar: AppBar(
        title: Text(
          isPengawas ? 'Scan Pulang' : 'Gate Security',
          style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 16),
        ),
        backgroundColor: AppColors.surface,
        foregroundColor: AppColors.textPrimary,
        elevation: 0,
        centerTitle: true,
      ),
      backgroundColor: isPengawas ? Colors.black : AppColors.background,
      body: isPengawas
          ? _buildScannerBox(isLocked)
          : _buildSecuritySelfService(isLocked),
    );
  }

  Widget _buildSecuritySelfService(bool isLocked) {
    final color = _lastColor ?? AppColors.security;
    final hasResult = _lastResult != null;

    return Focus(
      focusNode: _hardwareScannerFocusNode,
      autofocus: true,
      onKeyEvent: _handleHardwareScannerKey,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: _requestHardwareScannerFocus,
        child: SafeArea(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final isWide = constraints.maxWidth >= 720;
              return SingleChildScrollView(
                padding: const EdgeInsets.all(20),
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                    minHeight: constraints.maxHeight - 40,
                  ),
                  child: Column(
                    children: [
                      Row(
                        children: [
                          _buildClockChip(),
                          const SizedBox(width: 10),
                          Expanded(child: _buildHardwareFocusChip()),
                          const SizedBox(width: 8),
                          _buildInputModeButton(),
                        ],
                      ),
                      const SizedBox(height: 20),
                      if (isWide)
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              flex: 3,
                              child: _buildSelfServiceHero(
                                isLocked: isLocked,
                                color: color,
                              ),
                            ),
                            const SizedBox(width: 18),
                            Expanded(
                              flex: 2,
                              child: _buildSelfServiceResultPanel(
                                hasResult: hasResult,
                                color: color,
                              ),
                            ),
                          ],
                        )
                      else ...[
                        _buildSelfServiceHero(isLocked: isLocked, color: color),
                        const SizedBox(height: 18),
                        _buildSelfServiceResultPanel(
                          hasResult: hasResult,
                          color: color,
                        ),
                      ],
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _buildHardwareFocusChip() {
    return AnimatedBuilder(
      animation: _hardwareScannerFocusNode,
      builder: (context, _) {
        if (_useCameraFallback) {
          return Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: AppColors.info.withAlpha(18),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppColors.info.withAlpha(45)),
            ),
            child: const Row(
              children: [
                Icon(Icons.camera_front, size: 18, color: AppColors.info),
                SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Kamera depan aktif',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: AppColors.info,
                    ),
                  ),
                ),
              ],
            ),
          );
        }

        final isFocused = _hardwareScannerFocusNode.hasFocus;
        final color = isFocused ? AppColors.success : AppColors.warning;
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: color.withAlpha(18),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: color.withAlpha(45)),
          ),
          child: Row(
            children: [
              Icon(
                isFocused ? Icons.sensors : Icons.touch_app,
                size: 18,
                color: color,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  isFocused
                      ? 'Scanner fisik aktif'
                      : 'Ketuk layar untuk scanner',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: color,
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildInputModeButton() {
    return FilledButton.icon(
      onPressed: () => _setSecurityCameraFallback(!_useCameraFallback),
      icon: Icon(
        _useCameraFallback ? Icons.sensors : Icons.camera_front,
        size: 18,
      ),
      label: Text(_useCameraFallback ? 'Scanner' : 'Kamera'),
      style: FilledButton.styleFrom(
        backgroundColor: _useCameraFallback
            ? AppColors.success
            : AppColors.info,
        foregroundColor: Colors.white,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        textStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
      ),
    );
  }

  Widget _buildSelfServiceHero({required bool isLocked, required Color color}) {
    final title = isLocked
        ? 'Memproses Scan'
        : _lastStatus == 'success'
        ? 'Silakan Pulang'
        : _lastStatus == 'rejected'
        ? 'Belum Diizinkan Pulang'
        : _lastStatus == 'offline'
        ? 'Scan Tersimpan'
        : _lastStatus == 'error'
        ? 'Scan Tidak Valid'
        : 'Perlihatkan ID Card ke scanner';
    final subtitle = isLocked
        ? 'Mohon tunggu sebentar'
        : _lastStatus == 'success'
        ? 'Gate security sudah mencatat kepulangan'
        : _lastStatus == 'rejected'
        ? 'Mitra perlu ACC pengawas terlebih dahulu'
        : _lastStatus == 'offline'
        ? 'Data akan dikirim saat koneksi pulih'
        : _lastStatus == 'error'
        ? 'Coba scan ulang ID Card'
        : 'QR akan terbaca otomatis oleh scanner';

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 28),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withAlpha(45)),
        boxShadow: [
          BoxShadow(
            color: color.withAlpha(18),
            blurRadius: 22,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        children: [
          if (_useCameraFallback)
            _buildSecurityCameraPreview(color)
          else
            AnimatedBuilder(
              animation: _pulseController,
              builder: (context, child) {
                final scale = 1 + (_pulseController.value * 0.06);
                return Transform.scale(scale: scale, child: child);
              },
              child: Container(
                width: 148,
                height: 148,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: color.withAlpha(18),
                  border: Border.all(color: color.withAlpha(70), width: 2),
                ),
                child: isLocked
                    ? Padding(
                        padding: const EdgeInsets.all(35),
                        child: CircularProgressIndicator(
                          color: color,
                          strokeWidth: 4,
                        ),
                      )
                    : Icon(
                        _lastStatus == 'success'
                            ? Icons.check_circle
                            : _lastStatus == 'rejected'
                            ? Icons.block
                            : _lastStatus == 'offline'
                            ? Icons.cloud_off
                            : _lastStatus == 'error'
                            ? Icons.error
                            : Icons.qr_code_scanner,
                        size: 78,
                        color: color,
                      ),
              ),
            ),
          const SizedBox(height: 24),
          Text(
            title,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 30,
              height: 1.1,
              fontWeight: FontWeight.w800,
              color: color,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            subtitle,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 16,
              height: 1.35,
              fontWeight: FontWeight.w600,
              color: AppColors.textSecondary,
            ),
          ),
          const SizedBox(height: 22),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: AppColors.background,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppColors.cardBorder),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(
                  Icons.badge_outlined,
                  size: 18,
                  color: AppColors.textSecondary,
                ),
                const SizedBox(width: 8),
                Flexible(
                  child: Text(
                    _lastScanSource == 'scanner'
                        ? 'Input terakhir: scanner fisik'
                        : _lastScanSource == 'camera'
                        ? 'Input terakhir: kamera depan'
                        : 'Menunggu scan ID Card',
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSecurityCameraPreview(Color color) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(18),
      child: SizedBox(
        height: 300,
        width: double.infinity,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final scannerSize = constraints.biggest;
            final scanAreaSize = (scannerSize.shortestSide * 0.72).clamp(
              170.0,
              scannerSize.shortestSide,
            );

            return Stack(
              children: [
                // Mirroring untuk kamera depan (role security)
                Transform(
                  alignment: Alignment.center,
                  transform: Matrix4.rotationY(
                    _desiredCameraFacing == CameraFacing.front ? math.pi : 0,
                  ),
                  child: MobileScanner(
                    controller: _controller,
                    onDetect: _onDetect,
                    // scanWindow dilepas agar lebih responsif mendeteksi QR
                    // meskipun sedikit di luar kotak overlay
                    errorBuilder: (context, error, child) {
                      final message =
                          error.errorCode ==
                              MobileScannerErrorCode.permissionDenied
                          ? 'Izin kamera ditolak. Aktifkan izin kamera di pengaturan aplikasi.'
                          : 'Kamera depan gagal dijalankan. Tekan tombol refresh.';

                      // Un-mirror error builder content
                      return Transform(
                        alignment: Alignment.center,
                        transform: Matrix4.rotationY(
                          _desiredCameraFacing == CameraFacing.front
                              ? math.pi
                              : 0,
                        ),
                        child: Container(
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
                        ),
                      );
                    },
                  ),
                ),
                IgnorePointer(child: _buildScannerOverlay(scanAreaSize)),
                Positioned(
                  top: 12,
                  left: 12,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 7,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.black.withAlpha(130),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: Colors.white.withAlpha(35)),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.camera_front, size: 16, color: Colors.white),
                        SizedBox(width: 6),
                        Text(
                          'Kamera depan',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: Colors.white,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                Positioned.fill(
                  child: IgnorePointer(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        border: Border.all(
                          color: color.withAlpha(120),
                          width: 2,
                        ),
                        borderRadius: BorderRadius.circular(18),
                      ),
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _buildSelfServiceResultPanel({
    required bool hasResult,
    required Color color,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.cardBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Status Scan',
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w800,
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: 12),
          if (_isProcessing)
            const _SecurityStatusTile(
              icon: Icons.sync,
              title: 'Memproses',
              subtitle: 'Data sedang dikirim ke server',
              color: AppColors.info,
              showProgress: true,
            )
          else if (hasResult)
            _SecurityStatusTile(
              icon: _resultIcon(),
              title: _resultTitle(),
              subtitle: _lastResult ?? '',
              color: color,
            )
          else
            const _SecurityStatusTile(
              icon: Icons.sensors,
              title: 'Siap',
              subtitle: 'Scanner fisik siap menerima QR ID Card',
              color: AppColors.security,
            ),
          const SizedBox(height: 14),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppColors.background,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppColors.cardBorder),
            ),
            child: const Row(
              children: [
                Icon(Icons.info_outline, size: 18, color: AppColors.info),
                SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Delay scan ulang mengikuti mode security sebelumnya.',
                    style: TextStyle(
                      fontSize: 12,
                      height: 1.35,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  IconData _resultIcon() {
    switch (_lastStatus) {
      case 'success':
        return Icons.check_circle;
      case 'duplicate':
        return Icons.info;
      case 'rejected':
        return Icons.block;
      case 'offline':
        return Icons.cloud_off;
      default:
        return Icons.error;
    }
  }

  String _resultTitle() {
    switch (_lastStatus) {
      case 'success':
        return 'Berhasil';
      case 'duplicate':
        return 'Sudah Discan';
      case 'rejected':
        return 'Ditolak';
      case 'offline':
        return 'Offline';
      default:
        return 'Error';
    }
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
                // Mirroring untuk kamera depan (jika bukan pengawas)
                Transform(
                  alignment: Alignment.center,
                  transform: Matrix4.rotationY(
                    _desiredCameraFacing == CameraFacing.front ? math.pi : 0,
                  ),
                  child: MobileScanner(
                    controller: _controller,
                    onDetect: _onDetect,
                    // scanWindow dilepas agar lebih responsif mendeteksi QR
                    // meskipun sedikit di luar kotak overlay
                    errorBuilder: (context, error, child) {
                      final message =
                          error.errorCode ==
                              MobileScannerErrorCode.permissionDenied
                          ? 'Izin kamera ditolak. Aktifkan izin kamera di pengaturan aplikasi.'
                          : 'Kamera gagal dijalankan. Tekan tombol di bawah untuk mencoba lagi.';

                      // Un-mirror error builder content
                      return Transform(
                        alignment: Alignment.center,
                        transform: Matrix4.rotationY(
                          _desiredCameraFacing == CameraFacing.front
                              ? math.pi
                              : 0,
                        ),
                        child: Container(
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
                        ),
                      );
                    },
                  ),
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
                // Zoom slider — ditampilkan di atas result overlay
                Positioned(
                  left: 16,
                  right: 16,
                  bottom: _lastResult != null ? 90 : 18,
                  child: _buildZoomSlider(),
                ),
                if (_lastResult != null)
                  Positioned(
                    left: 16,
                    right: 16,
                    bottom: 18,
                    child: _buildResultOverlay(),
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

  Widget _buildZoomSlider() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.black.withAlpha(115),
        borderRadius: BorderRadius.circular(30),
        border: Border.all(color: Colors.white.withAlpha(40)),
      ),
      child: Row(
        children: [
          const Icon(Icons.zoom_out, color: Colors.white70, size: 18),
          Expanded(
            child: SliderTheme(
              data: SliderTheme.of(context).copyWith(
                activeTrackColor: AppColors.primaryLight,
                inactiveTrackColor: Colors.white24,
                thumbColor: Colors.white,
                overlayColor: AppColors.primary.withAlpha(40),
                thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 7),
                trackHeight: 3,
              ),
              child: Slider(
                value: _zoomLevel,
                min: 0.0,
                max: 1.0,
                onChanged: _onZoomChanged,
              ),
            ),
          ),
          const Icon(Icons.zoom_in, color: Colors.white70, size: 18),
        ],
      ),
    );
  }

  Widget _buildResultOverlay() {
    final color = _lastColor ?? Colors.white;
    final IconData icon;
    final String label;
    switch (_lastStatus) {
      case 'success':
        icon = Icons.check_circle_rounded;
        label = 'BERHASIL';
        break;
      case 'duplicate':
        icon = Icons.info_rounded;
        label = 'SUDAH DI-SCAN';
        break;
      case 'rejected':
        icon = Icons.block_rounded;
        label = 'DITOLAK';
        break;
      case 'offline':
        icon = Icons.cloud_off_rounded;
        label = 'OFFLINE';
        break;
      default:
        icon = Icons.error_rounded;
        label = 'ERROR';
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
      decoration: BoxDecoration(
        // Solid — tidak transparan sama sekali agar mudah dibaca
        color: color == AppColors.success
            ? const Color(0xFF1B5E20)
            : color == AppColors.warning
            ? const Color(0xFF7B4F00)
            : color == AppColors.error
            ? const Color(0xFF7F0000)
            : const Color(0xFF1A237E),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color, width: 2),
        boxShadow: [
          BoxShadow(
            color: color.withAlpha(100),
            blurRadius: 24,
            spreadRadius: 2,
          ),
        ],
      ),
      child: Row(
        children: [
          Icon(icon, color: color, size: 40),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                    color: color,
                    letterSpacing: 1.5,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  _lastResult ?? '',
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: Colors.white,
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SecurityStatusTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final Color color;
  final bool showProgress;

  const _SecurityStatusTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.color,
    this.showProgress = false,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: color.withAlpha(14),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withAlpha(35)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 42,
            height: 42,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: color.withAlpha(22),
              borderRadius: BorderRadius.circular(12),
            ),
            child: showProgress
                ? SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.2,
                      color: color,
                    ),
                  )
                : Icon(icon, color: color, size: 24),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                    color: color,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  subtitle,
                  style: const TextStyle(
                    fontSize: 13,
                    height: 1.35,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
