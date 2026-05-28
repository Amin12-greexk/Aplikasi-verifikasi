import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../../core/theme/app_colors.dart';
import '../../core/services/auth_service.dart';
import '../../core/services/tts_service.dart';
import '../../core/utils/wib_time.dart';
import 'toilet_expiry_monitor_service.dart';
import 'toilet_permit_service.dart';

class ToiletScannerPage extends StatefulWidget {
  final bool isPengawas;
  final bool isActive;

  const ToiletScannerPage({
    super.key,
    required this.isPengawas,
    this.isActive = true,
  });

  @override
  State<ToiletScannerPage> createState() => _ToiletScannerPageState();
}

class _ToiletScannerPageState extends State<ToiletScannerPage>
    with WidgetsBindingObserver, SingleTickerProviderStateMixin {
  static const double _scanAreaRatio = 0.96;
  static const double _minScanAreaSize = 220.0;
  static const Duration _sameCodeCooldown = Duration(
    seconds: 1,
  ); // reset cepat antar scan
  static const Duration _hardwareScanSettleDelay = Duration(milliseconds: 80);
  static const Duration _hardwareScanIncompleteDelay = Duration(
    milliseconds: 650,
  );
  static const List<int> _durationOptions = [5, 10, 20];

  final MobileScannerController _controller = MobileScannerController(
    detectionSpeed: DetectionSpeed.unrestricted,
    detectionTimeoutMs: 150,
    facing: CameraFacing.back,
    formats: [BarcodeFormat.qrCode],
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
    debugLabel: 'toilet-security-hardware-scanner',
  );
  final ValueNotifier<DateTime> _currentTimeNotifier = ValueNotifier(
    WibTime.now(),
  );
  late final AnimationController _pulseController;
  double _zoomLevel = 0.0; // mulai dari wide — field of view paling lebar
  double _baseZoomLevel = 0.0;
  int _selectedDuration = 10;
  AppLifecycleState _appLifecycleState = AppLifecycleState.resumed;
  bool _isCameraRunning = false;
  bool _isSyncingCamera = false;
  bool _useCameraFallback = false;
  CameraFacing _securityCameraFacing = CameraFacing.front;

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
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _syncCameraState();
      _requestHardwareScannerFocus();
    });
  }

  @override
  void didUpdateWidget(covariant ToiletScannerPage oldWidget) {
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
      widget.isPengawas ? CameraFacing.back : _securityCameraFacing;

  String get _securityCameraLabel => _securityCameraFacing == CameraFacing.front
      ? 'Kamera depan'
      : 'Kamera belakang';

  IconData get _securityCameraIcon =>
      _securityCameraFacing == CameraFacing.front
      ? Icons.camera_front
      : Icons.camera_rear;

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

  Future<void> _setSecurityCameraFacing(CameraFacing facing) async {
    if (widget.isPengawas || _securityCameraFacing == facing) return;
    setState(() => _securityCameraFacing = facing);
    if (!_useCameraFallback) return;

    try {
      await _controller.stop();
    } catch (_) {}
    _isCameraRunning = false;
    await _syncCameraState();
  }

  Future<void> _toggleSecurityCameraFacing() async {
    await _setSecurityCameraFacing(
      _securityCameraFacing == CameraFacing.front
          ? CameraFacing.back
          : CameraFacing.front,
    );
  }

  /// Otomatis reset scanner 1 detik setelah processing selesai.
  /// Mencegah bug harus keluar halaman untuk bisa scan ulang.
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
      _submitHardwareScanBuffer(force: true);
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

  bool _hasCompleteHardwareScanPayload(String rawScan) {
    return rawScan.trim().isNotEmpty;
  }

  void _submitHardwareScanBuffer({bool force = false}) {
    _hardwareScanDebounceTimer?.cancel();
    final rawScan = _hardwareScanBuffer.toString().trim();
    if (rawScan.isEmpty) return;

    if (!force && !_hasCompleteHardwareScanPayload(rawScan)) {
      _hardwareScanDebounceTimer = Timer(
        _hardwareScanIncompleteDelay,
        () => _submitHardwareScanBuffer(force: true),
      );
      return;
    }

    _hardwareScanBuffer.clear();
    unawaited(_processRawScan(rawScan, source: 'scanner'));
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

  String _cleanBarcodeValue(String value) {
    var cleaned = value.trim();
    while (cleaned.startsWith("'") ||
        cleaned.startsWith('"') ||
        cleaned.startsWith('`')) {
      cleaned = cleaned.substring(1).trimLeft();
    }
    while (cleaned.endsWith("'") ||
        cleaned.endsWith('"') ||
        cleaned.endsWith('`')) {
      cleaned = cleaned.substring(0, cleaned.length - 1).trimRight();
    }
    return cleaned;
  }

  void _putBarcodeField(Map<String, String> info, String key, String value) {
    final cleanedValue = _cleanBarcodeValue(value);
    if (cleanedValue.isEmpty) return;

    final normalizedKey = key.trim().toLowerCase();
    if (normalizedKey == 'pin') {
      info['PIN'] = cleanedValue;
    } else if (normalizedKey == 'nama' || normalizedKey == 'name') {
      info['Nama'] = cleanedValue;
    } else if (normalizedKey == 'nik') {
      info['NIK'] = cleanedValue;
    } else if (normalizedKey == 'bagian' || normalizedKey == 'department') {
      info['Bagian'] = cleanedValue;
    }
  }

  Map<String, String> _extractBarcodeInfo(String fullBarcode) {
    final info = <String, String>{};
    final raw = fullBarcode.trim();
    if (raw.isEmpty) return info;

    try {
      // 1. Cek format CSV (N, NAMA, NIK, ...) atau (NAMA, N, NIK, ...) - Prioritas Tinggi
      if (raw.contains(',') && !raw.contains(':')) {
        final parts = raw.split(',').map(_cleanBarcodeValue).toList();
        if (parts.length >= 2) {
          // Cari PIN: biasanya field yang hanya berisi angka (numeric)
          int pinIndex = -1;
          if (RegExp(r'^[0-9]+$').hasMatch(parts[0])) {
            pinIndex = 0;
          } else if (RegExp(r'^[0-9]+$').hasMatch(parts[1])) {
            pinIndex = 1;
          }

          if (pinIndex != -1) {
            final pin = parts[pinIndex];
            final nama = parts[pinIndex == 0 ? 1 : 0];
            if (pin.isEmpty || nama.isEmpty) return <String, String>{};

            info['PIN'] = pin;
            info['Nama'] = nama;
            if (parts.length >= 3 && parts[2].isNotEmpty) {
              info['NIK'] = parts[2];
            }
            if (parts.length >= 10) {
              info['Bagian'] = parts[9];
            } else if (parts.length >= 4) {
              info['Bagian'] = parts[3];
            }
            return info;
          }
        }
      }

      // 2. Format standar: PIN: xxx | Nama: yyy
      final parts = raw
          .split(RegExp(r'[|\r\n]+'))
          .map((p) => p.trim())
          .toList();
      for (final part in parts) {
        final separatorIndex = part.indexOf(':');
        if (separatorIndex <= 0) continue;

        final rawKey = part.substring(0, separatorIndex).trim();
        final value = part.substring(separatorIndex + 1).trim();
        _putBarcodeField(info, rawKey, value);
      }
    } catch (_) {}

    return info; // BYPASS
  }

  String _normalizeBarcodeInfoForLookup(Map<String, String> info) {
    final pin = info['PIN']?.trim() ?? '';
    final nik = info['NIK']?.trim() ?? '';
    final nama = info['Nama']?.trim() ?? '';
    final bagian = info['Bagian']?.trim() ?? '';

    if (pin.isEmpty && nik.isEmpty) {
      return '';
    }

    final parts = <String>[];
    if (nik.isNotEmpty) {
      parts.add('NIK: $nik');
    } else {
      parts.add('PIN: $pin');
    }
    if (nama.isNotEmpty) parts.add('Nama: $nama');
    if (bagian.isNotEmpty) parts.add('Bagian: $bagian');
    return parts.join(' | ');
  }

  String _employeeLabel(Map<String, String> info) {
    final pin = info['PIN']?.trim() ?? '';
    final nik = info['NIK']?.trim() ?? '';
    final nama = info['Nama']?.trim() ?? '';

    if (nama.isNotEmpty && pin.isNotEmpty) return '$nama (PIN: $pin)';
    if (nama.isNotEmpty && nik.isNotEmpty) return '$nama (NIK: $nik)';
    if (pin.isNotEmpty) return 'PIN: $pin';
    if (nik.isNotEmpty) return 'NIK: $nik';
    return 'ID Card';
  }

  String _buildScanId(Map<String, String> info) {
    return _normalizeBarcodeInfoForLookup(info).trim();
  }

  Future<String?> _showBypassDialog({
    required String employeeLabel,
    required String message,
  }) async {
    final controller = TextEditingController();

    return showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        return AlertDialog(
          title: const Row(
            children: [
              Icon(Icons.warning_amber_rounded, color: Colors.orange),
              SizedBox(width: 8),
              Text('Limit Tercapai', style: TextStyle(fontSize: 18)),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                employeeLabel,
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 12),
              Text(message, style: const TextStyle(fontSize: 13)),
              const SizedBox(height: 16),
              const Text(
                'Alasan Bypass (misal: Diare):',
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: controller,
                autofocus: true,
                decoration: const InputDecoration(
                  hintText: 'Contoh: Sedang sakit perut/diare',
                  border: OutlineInputBorder(),
                  contentPadding: EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(null),
              child: const Text('Batal'),
            ),
            FilledButton(
              onPressed: () {
                final reason = controller.text.trim();
                if (reason.isEmpty) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Alasan bypass wajib diisi')),
                  );
                  return;
                }
                Navigator.of(context).pop(reason);
              },
              style: FilledButton.styleFrom(
                backgroundColor: Colors.orange.shade800,
              ),
              child: const Text('Bypass Izin'),
            ),
          ],
        );
      },
    );
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
        await TtsService.speak('Silakan ke toilet.');
        break;
      case 'duplicate':
        await TtsService.speak('Sudah discan.');
        break;
      case 'waiting':
        await TtsService.speak('Izin valid.');
        break;
      default:
        await TtsService.speak('Ditolak.');
    }
  }

  Future<void> _processRawScan(
    String fullBarcode, {
    required String source,
  }) async {
    if (_isProcessing) return;

    final raw = fullBarcode.trim();
    if (raw.isEmpty) return;

    final isPengawas = widget.isPengawas;
    final info = _extractBarcodeInfo(raw);
    final parsedScanId = _buildScanId(info);
    
    // BYPASS: Gunakan parsedScanId jika ada, jika tidak ada gunakan raw data langsung.
    final scanId = parsedScanId.isNotEmpty ? parsedScanId : raw;
    final employeeLabel = parsedScanId.isNotEmpty
        ? _employeeLabel(info)
        : 'QR ID Card';
    final now = DateTime.now();

    if (_lastScannedId == scanId &&
        _lastScannedAt != null &&
        now.difference(_lastScannedAt!) < _sameCodeCooldown) {
      return;
    }
    _lastScannedId = scanId;
    _lastScannedAt = now;

    if (scanId.isEmpty) {
      setState(() {
        _lastResult = 'Data QR Kosong';
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

    try {
      Map<String, dynamic> result;
      if (isPengawas) {
        try {
          result = await ToiletPermitService.approvePermit(
            scanId,
            durationMinutes: _selectedDuration,
          );
        } on LimitExceededException catch (e) {
          // Show bypass dialog
          final bypassData = await _showBypassDialog(
            employeeLabel: employeeLabel,
            message: e.message,
          );
          if (bypassData == null || !mounted) {
            setState(() => _isProcessing = false);
            return;
          }

          setState(() => _isProcessing = true);
          result = await ToiletPermitService.approvePermit(
            scanId,
            durationMinutes: _selectedDuration,
            isBypass: true,
            bypassReason: bypassData,
          );
        } on QuotaFullException catch (e) {
          setState(() {
            _lastResult = '$employeeLabel\n${e.message}';
            _lastStatus = 'error';
            _lastColor = AppColors.error;
          });
          return;
        }
      } else {
        // Optimasi Performance: Langsung panggil proofScan tanpa fetchPermitStatus dulu.
        // Server akan mengembalikan error jika izin sudah habis atau sudah discan.
        // Ini menghemat 1 round-trip network (lebih cepat ~500ms).
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
        _lastResult = '$employeeLabel\n$details';
        _lastStatus = isDuplicate ? 'duplicate' : 'success';
        _lastColor = isDuplicate ? AppColors.warning : AppColors.success;
      });
      unawaited(_playSecurityFeedback(isDuplicate ? 'duplicate' : 'success'));
      await ToiletExpiryMonitorService.refreshNow();
    } catch (e) {
      final errorStr = _userErrorMessage(e);
      setState(() {
        _lastResult = '$employeeLabel\n$errorStr';
        _lastStatus = 'error';
        _lastColor = AppColors.error;
      });
      unawaited(_playSecurityFeedback('error'));
    } finally {
      if (mounted) {
        setState(() => _isProcessing = false);
        _scheduleAutoReset(); // reset otomatis 1 detik setelah scan selesai
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isPengawas = widget.isPengawas;
    final isLocked = _isProcessing;

    return Scaffold(
      appBar: AppBar(
        title: Column(
          children: [
            Text(
              isPengawas ? 'Scan Toilet' : 'Gate Toilet',
              style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 16),
            ),
            if (isPengawas && AuthService.roomName != null)
              Text(
                'Ruang: ${AuthService.roomName}',
                style: const TextStyle(
                  fontSize: 11,
                  color: AppColors.textSecondary,
                ),
              ),
          ],
        ),
        backgroundColor: AppColors.surface,
        foregroundColor: AppColors.textPrimary,
        elevation: 0,
        centerTitle: true,
      ),
      backgroundColor: isPengawas ? Colors.black : AppColors.background,
      body: isPengawas
          ? _buildScannerBox(isPengawas, isLocked)
          : _buildSecuritySelfService(isLocked),
    );
  }

  Widget _buildSecuritySelfService(bool isLocked) {
    final color = _lastColor ?? AppColors.warning;
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
                          if (_useCameraFallback) ...[
                            _buildCameraFacingButton(),
                            const SizedBox(width: 8),
                          ],
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
            child: Row(
              children: [
                Icon(_securityCameraIcon, size: 18, color: AppColors.info),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '$_securityCameraLabel aktif',
                    style: const TextStyle(
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

  Widget _buildCameraFacingButton() {
    return FilledButton.icon(
      onPressed: _toggleSecurityCameraFacing,
      icon: const Icon(Icons.cameraswitch, size: 18),
      label: Text(
        _securityCameraFacing == CameraFacing.front ? 'Depan' : 'Belakang',
      ),
      style: FilledButton.styleFrom(
        backgroundColor: AppColors.warning,
        foregroundColor: Colors.white,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        textStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
      ),
    );
  }

  Widget _buildSelfServiceHero({required bool isLocked, required Color color}) {
    final title = isLocked
        ? 'Memproses Izin'
        : _lastStatus == 'success'
        ? 'Izin Aktif'
        : _lastStatus == 'duplicate'
        ? 'Sudah Discan'
        : _lastStatus == 'error'
        ? 'Izin Tidak Valid'
        : 'Perlihatkan ID Card ke scanner';
    final subtitle = isLocked
        ? 'Mohon tunggu sebentar'
        : _lastStatus == 'success'
        ? 'Timer toilet dimulai dari scan security ini'
        : _lastStatus == 'duplicate'
        ? 'Mitra sudah pernah melakukan scan security'
        : _lastStatus == 'error'
        ? 'Cek izin pengawas atau coba scan ulang'
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
                            ? Icons.timer
                            : _lastStatus == 'duplicate'
                            ? Icons.info
                            : _lastStatus == 'error'
                            ? Icons.error
                            : Icons.wc,
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
                        ? 'Input terakhir: ${_securityCameraLabel.toLowerCase()}'
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
                Transform(
                  alignment: Alignment.center,
                  transform: Matrix4.rotationY(
                    _desiredCameraFacing == CameraFacing.front ? math.pi : 0,
                  ),
                  child: MobileScanner(
                    controller: _controller,
                    onDetect: _onDetect,
                    errorBuilder: (context, error, child) {
                      final message =
                          error.errorCode ==
                              MobileScannerErrorCode.permissionDenied
                          ? 'Izin kamera ditolak. Aktifkan izin kamera di pengaturan aplikasi.'
                          : '$_securityCameraLabel gagal dijalankan. Tekan tombol refresh.';
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
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          _securityCameraIcon,
                          size: 16,
                          color: Colors.white,
                        ),
                        const SizedBox(width: 6),
                        Text(
                          _securityCameraLabel,
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
            'Status Izin Toilet',
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
              subtitle: 'Data izin sedang dikirim ke server',
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
              color: AppColors.warning,
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
        return Icons.timer;
      case 'duplicate':
        return Icons.info;
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
      default:
        return 'Error';
    }
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
                Positioned(
                  top: 20,
                  left: 20,
                  right: 20,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      _buildClockChip(),
                      if (isPengawas) _buildDurationSelection(isLocked),
                    ],
                  ),
                ),
                // Zoom slider — di atas result overlay
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

  Widget _buildDurationSelection(bool isLocked) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.black.withAlpha(115),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withAlpha(45)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: _durationOptions.map((duration) {
          final isSelected = _selectedDuration == duration;
          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: InkWell(
              onTap: isLocked
                  ? null
                  : () => setState(() => _selectedDuration = duration),
              borderRadius: BorderRadius.circular(10),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: isSelected ? AppColors.pengawas : Colors.transparent,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  '${duration}m',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: isSelected ? FontWeight.w800 : FontWeight.w600,
                    color: Colors.white,
                  ),
                ),
              ),
            ),
          );
        }).toList(),
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
      case 'error':
        icon = Icons.error_rounded;
        label = 'ERROR';
        break;
      default:
        icon = Icons.info_rounded;
        label = 'INFO';
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
      decoration: BoxDecoration(
        // Solid — tidak transparan agar mudah dibaca
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
