import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import '../../core/theme/app_colors.dart';
import 'id_card_model.dart';
import 'id_card_view_page.dart';

class IDCardScannerPage extends StatefulWidget {
  const IDCardScannerPage({super.key});

  @override
  State<IDCardScannerPage> createState() => _IDCardScannerPageState();
}

class _IDCardScannerPageState extends State<IDCardScannerPage>
    with SingleTickerProviderStateMixin {
  bool _isScanned = false;

  // Konfigurasi scanner: detectionSpeed cepat, autoStart true, torch bisa diaktifkan
  final MobileScannerController _controller = MobileScannerController(
    detectionSpeed: DetectionSpeed.noDuplicates,
    returnImage: false,
    formats: [BarcodeFormat.qrCode],
  );

  late AnimationController _animController;
  late Animation<double> _scanLineAnim;

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      duration: const Duration(seconds: 2),
      vsync: this,
    )..repeat(reverse: true);

    _scanLineAnim = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _animController, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _animController.dispose();
    _controller.dispose();
    super.dispose();
  }

  void _onDetect(BarcodeCapture capture) {
    if (_isScanned) return;

    final barcodes = capture.barcodes;
    if (barcodes.isNotEmpty) {
      final String? code = barcodes.first.rawValue;
      if (code != null && code.isNotEmpty) {
        setState(() => _isScanned = true);
        _controller.stop();

        final data = IDCardData.fromQRString(code);

        if (!mounted) return;
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => IDCardViewPage(data: data)),
        );
      }
    }
  }

  void _toggleTorch() => _controller.toggleTorch();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          // ── KAMERA FULLSCREEN ──────────────────────────────────────
          Positioned.fill(
            child: MobileScanner(
              controller: _controller,
              onDetect: _onDetect,
            ),
          ),

          // ── OVERLAY GELAP ─────────────────────────────────────────
          Positioned.fill(
            child: CustomPaint(
              painter: _ScanOverlayPainter(),
            ),
          ),

          // ── SCAN LINE ANIMASI ──────────────────────────────────────
          AnimatedBuilder(
            animation: _scanLineAnim,
            builder: (_, __) {
              return _ScanLineWidget(progress: _scanLineAnim.value);
            },
          ),

          // ── CORNER BRACKETS ───────────────────────────────────────
          const _CornerBrackets(),

          // ── APPBAR TRANSPARAN ──────────────────────────────────────
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: SafeArea(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                child: Row(
                  children: [
                    // Tombol kembali
                    _GlassButton(
                      icon: Icons.arrow_back_rounded,
                      onTap: () => Navigator.pop(context),
                    ),
                    const Spacer(),
                    const Text(
                      'Scan ID Card',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 0.5,
                      ),
                    ),
                    const Spacer(),
                    // Tombol senter
                    _GlassButton(
                      icon: Icons.flashlight_on_rounded,
                      onTap: _toggleTorch,
                    ),
                  ],
                ),
              ),
            ),
          ),

          // ── LABEL BAWAH ────────────────────────────────────────────
          Positioned(
            bottom: 60,
            left: 24,
            right: 24,
            child: Column(
              children: [
                // Status scan
                AnimatedSwitcher(
                  duration: const Duration(milliseconds: 300),
                  child: _isScanned
                      ? const _StatusChip(
                          text: '✓ QR Terdeteksi',
                          color: AppColors.primaryLight,
                        )
                      : const _StatusChip(
                          text: 'Arahkan kamera ke QR Code',
                          color: Colors.white70,
                        ),
                ),
                const SizedBox(height: 12),
                // Tips scan
                ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: BackdropFilter(
                    filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 10),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.4),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: Colors.white.withValues(alpha: 0.1),
                        ),
                      ),
                      child: const Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.info_outline_rounded,
                              size: 13, color: Colors.white54),
                          SizedBox(width: 6),
                          Text(
                            'Tidak perlu pas di tengah • Otomatis terscan',
                            style: TextStyle(
                              fontSize: 11,
                              color: Colors.white54,
                            ),
                          ),
                        ],
                      ),
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
}

// ── OVERLAY GELAP DENGAN LUBANG TRANSPARAN ───────────────────────────────────
class _ScanOverlayPainter extends CustomPainter {
  static const double _boxSize = 260.0;

  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width / 2;
    final cy = size.height / 2 - 30;
    final rect = Rect.fromCenter(
      center: Offset(cx, cy),
      width: _boxSize,
      height: _boxSize,
    );
    final rrect = RRect.fromRectAndRadius(rect, const Radius.circular(16));

    final paint = Paint()
      ..color = Colors.black.withValues(alpha: 0.6)
      ..style = PaintingStyle.fill;

    final path = Path()
      ..addRect(Rect.fromLTWH(0, 0, size.width, size.height))
      ..addRRect(rrect)
      ..fillType = PathFillType.evenOdd;

    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(_ScanOverlayPainter old) => false;
}

// ── SCAN LINE ────────────────────────────────────────────────────────────────
class _ScanLineWidget extends StatelessWidget {
  final double progress;
  static const double _boxSize = 260.0;

  const _ScanLineWidget({required this.progress});

  @override
  Widget build(BuildContext context) {
    final screenSize = MediaQuery.of(context).size;
    final cx = screenSize.width / 2;
    final cy = screenSize.height / 2 - 30;

    final top = cy - _boxSize / 2 + 8;
    final bottom = cy + _boxSize / 2 - 8;
    final lineY = top + (bottom - top) * progress;

    return Positioned(
      top: lineY,
      left: cx - _boxSize / 2 + 12,
      right: screenSize.width - (cx + _boxSize / 2) + 12,
      child: Container(
        height: 2,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [
              Colors.transparent,
              AppColors.primaryLight.withValues(alpha: 0.9),
              Colors.transparent,
            ],
          ),
          borderRadius: BorderRadius.circular(2),
          boxShadow: [
            BoxShadow(
              color: AppColors.primaryLight.withValues(alpha: 0.5),
              blurRadius: 6,
            ),
          ],
        ),
      ),
    );
  }
}

// ── CORNER BRACKETS ──────────────────────────────────────────────────────────
class _CornerBrackets extends StatelessWidget {
  const _CornerBrackets();
  static const double _boxSize = 260.0;
  static const double _bracketLen = 24.0;
  static const double _bracketW = 3.0;

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final cx = size.width / 2;
    final cy = size.height / 2 - 30;
    final l = cx - _boxSize / 2;
    final t = cy - _boxSize / 2;
    final r = cx + _boxSize / 2;
    final b = cy + _boxSize / 2;

    const color = AppColors.primaryLight;

    return Stack(
      children: [
        // Top-left
        _corner(l, t, false, false, color),
        // Top-right
        _corner(r - _bracketLen, t, true, false, color),
        // Bottom-left
        _corner(l, b - _bracketLen, false, true, color),
        // Bottom-right
        _corner(r - _bracketLen, b - _bracketLen, true, true, color),
      ],
    );
  }

  Widget _corner(double x, double y, bool flipH, bool flipV, Color color) {
    return Positioned(
      left: x,
      top: y,
      child: Transform.scale(
        scaleX: flipH ? -1 : 1,
        scaleY: flipV ? -1 : 1,
        alignment: Alignment.topLeft,
        child: SizedBox(
          width: _bracketLen,
          height: _bracketLen,
          child: CustomPaint(
            painter: _CornerPainter(color: color, width: _bracketW),
          ),
        ),
      ),
    );
  }
}

class _CornerPainter extends CustomPainter {
  final Color color;
  final double width;
  const _CornerPainter({required this.color, required this.width});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = width
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;

    canvas.drawLine(Offset.zero, Offset(size.width, 0), paint);
    canvas.drawLine(Offset.zero, Offset(0, size.height), paint);
  }

  @override
  bool shouldRepaint(_CornerPainter old) => false;
}

// ── GLASS BUTTON ─────────────────────────────────────────────────────────────
class _GlassButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;

  const _GlassButton({required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
          child: Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.white.withValues(alpha: 0.2)),
            ),
            child: Icon(icon, color: Colors.white, size: 20),
          ),
        ),
      ),
    );
  }
}

// ── STATUS CHIP ───────────────────────────────────────────────────────────────
class _StatusChip extends StatelessWidget {
  final String text;
  final Color color;
  const _StatusChip({required this.text, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(30),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Text(
        text,
        style: TextStyle(
          color: color,
          fontSize: 13,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}
