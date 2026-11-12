import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../core/theme/app_colors.dart';
import 'employee_lookup_service.dart';
import 'id_card_model.dart';

class IDCardViewPage extends StatefulWidget {
  final IDCardData data;

  const IDCardViewPage({super.key, required this.data});

  @override
  State<IDCardViewPage> createState() => _IDCardViewPageState();
}

class _IDCardViewPageState extends State<IDCardViewPage> {
  IDCardData get data => widget.data;

  bool _loading = true;
  String? _error;
  LookupResult? _result;

  @override
  void initState() {
    super.initState();
    _run(() => EmployeeLookupService.lookup(data.rawValue));
  }

  Future<void> _run(Future<LookupResult> Function() task) async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final r = await task();
      if (!mounted) return;
      setState(() {
        _result = r;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString().replaceAll('Exception: ', '');
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0D1B2A),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: const Text(
          'Hasil Scan ID Card',
          style: TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.5,
          ),
        ),
        foregroundColor: Colors.white,
        systemOverlayStyle: const SystemUiOverlayStyle(
          statusBarColor: Colors.transparent,
          statusBarIconBrightness: Brightness.light,
        ),
      ),
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Color(0xFF0D1B2A),
              Color(0xFF162032),
              Color(0xFF0D1B2A),
            ],
          ),
        ),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
            child: Column(
              children: [
                // ── CARD ────────────────────────────────────────────────
                Expanded(
                  child: SingleChildScrollView(
                    child: _IDCard(
                      rawValue: data.rawValue,
                      detail: _ShiftResult(
                        loading: _loading,
                        error: _error,
                        result: _result,
                        onRetry: () => _run(
                          () => EmployeeLookupService.lookup(data.rawValue),
                        ),
                        onPick: (id) => _run(
                          () => EmployeeLookupService.lookupById(id),
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 20),

                // ── TOMBOL SCAN ULANG ────────────────────────────────────
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () => Navigator.pop(context),
                        icon: const Icon(Icons.qr_code_scanner_rounded, size: 18),
                        label: const Text(
                          'Scan Ulang',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Colors.white70,
                          side: const BorderSide(color: Colors.white24),
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      flex: 2,
                      child: ElevatedButton.icon(
                        onPressed: () => Navigator.pop(context),
                        icon: const Icon(Icons.check_rounded, size: 18),
                        label: const Text(
                          'Tutup',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.primary,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                          elevation: 0,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ── ID CARD WIDGET ────────────────────────────────────────────────────────────
class _IDCard extends StatelessWidget {
  final String rawValue;
  final Widget detail;
  const _IDCard({required this.rawValue, required this.detail});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: AppColors.primary.withValues(alpha: 0.35),
            blurRadius: 40,
            offset: const Offset(0, 16),
            spreadRadius: -4,
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // ── HEADER GRADIEN ────────────────────────────────────────
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    Color(0xFF1B5E20),
                    Color(0xFF2E7D32),
                    Color(0xFF388E3C),
                  ],
                ),
              ),
              child: Row(
                children: [
                  // Logo
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(12),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.2),
                          blurRadius: 8,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: Image.asset(
                      'assets/logo.jpg',
                      width: 38,
                      height: 38,
                      fit: BoxFit.contain,
                    ),
                  ),
                  const SizedBox(width: 14),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'PT TEI',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 20,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 1.5,
                          ),
                        ),
                        Text(
                          'EMPLOYEE IDENTITY CARD',
                          style: TextStyle(
                            color: Colors.white70,
                            fontSize: 10,
                            fontWeight: FontWeight.w500,
                            letterSpacing: 1.2,
                          ),
                        ),
                      ],
                    ),
                  ),
                  // Chip dekoratif
                  _ChipDecor(),
                ],
              ),
            ),

            // ── BODY PUTIH ────────────────────────────────────────────
            Container(
              color: const Color(0xFFF8FAFB),
              padding: const EdgeInsets.fromLTRB(20, 28, 20, 0),
              child: Column(
                children: [
                  // Avatar lingkaran hijau
                  Container(
                    width: 90,
                    height: 90,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: const LinearGradient(
                        colors: [Color(0xFF2E7D32), Color(0xFF66BB6A)],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: AppColors.primary.withValues(alpha: 0.35),
                          blurRadius: 20,
                          offset: const Offset(0, 8),
                        ),
                      ],
                    ),
                    child: const Icon(
                      Icons.person_rounded,
                      size: 52,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 20),

                  // Divider dengan icon
                  Row(
                    children: [
                      const Expanded(child: Divider()),
                      const SizedBox(width: 10),
                      Icon(
                        Icons.qr_code_rounded,
                        size: 14,
                        color: AppColors.primary.withValues(alpha: 0.5),
                      ),
                      const SizedBox(width: 10),
                      const Expanded(child: Divider()),
                    ],
                  ),
                  const SizedBox(height: 16),

                  // ── HASIL LOOKUP (nama, bagian, shift) ─────────────
                  detail,
                  const SizedBox(height: 16),

                  // ── DATA MENTAH QR ─────────────────────────────────
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: const Color(0xFF1A1A2E),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                        color: AppColors.primary.withValues(alpha: 0.3),
                        width: 1,
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Label
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(4),
                              decoration: BoxDecoration(
                                color: AppColors.primary.withValues(alpha: 0.2),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: const Icon(
                                Icons.data_object_rounded,
                                size: 12,
                                color: Color(0xFF66BB6A),
                              ),
                            ),
                            const SizedBox(width: 8),
                            const Text(
                              'DATA QR',
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.w700,
                                color: Color(0xFF66BB6A),
                                letterSpacing: 1.5,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),

                        // Isi data mentah
                        SelectableText(
                          rawValue.isEmpty ? '(tidak ada data)' : rawValue,
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                            color: rawValue.isEmpty
                                ? Colors.white38
                                : Colors.white,
                            height: 1.6,
                            letterSpacing: 0.3,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),
                ],
              ),
            ),

            // ── FOOTER STRIP ─────────────────────────────────────────
            Container(
              height: 6,
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    Color(0xFF1B5E20),
                    Color(0xFF66BB6A),
                    Color(0xFF1B5E20),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── CHIP DEKORATIF (kartu ID) ─────────────────────────────────────────────────
class _ChipDecor extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      width: 36,
      height: 28,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(4),
        gradient: const LinearGradient(
          colors: [Color(0xFFFDD835), Color(0xFFF9A825)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: GridView.count(
        crossAxisCount: 3,
        padding: const EdgeInsets.all(4),
        mainAxisSpacing: 2,
        crossAxisSpacing: 2,
        physics: const NeverScrollableScrollPhysics(),
        children: List.generate(
          9,
          (_) => Container(
            decoration: BoxDecoration(
              color: Colors.amber.shade600.withValues(alpha: 0.5),
              borderRadius: BorderRadius.circular(1),
            ),
          ),
        ),
      ),
    );
  }
}

// ── HASIL LOOKUP: NAMA, BAGIAN, SHIFT ─────────────────────────────────────────
class _ShiftResult extends StatelessWidget {
  final bool loading;
  final String? error;
  final LookupResult? result;
  final VoidCallback onRetry;
  final void Function(int id) onPick;

  const _ShiftResult({
    required this.loading,
    required this.error,
    required this.result,
    required this.onRetry,
    required this.onPick,
  });

  @override
  Widget build(BuildContext context) {
    if (loading) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 12),
        child: SizedBox(
          width: 24,
          height: 24,
          child: CircularProgressIndicator(strokeWidth: 2.5),
        ),
      );
    }

    if (error != null) {
      return _notice(
        icon: Icons.wifi_off_rounded,
        color: AppColors.error,
        title: 'Gagal memeriksa data',
        subtitle: error!,
        action: TextButton.icon(
          onPressed: onRetry,
          icon: const Icon(Icons.refresh_rounded, size: 18),
          label: const Text('Coba lagi'),
        ),
      );
    }

    final r = result;
    if (r == null) return const SizedBox.shrink();

    switch (r.status) {
      case LookupStatus.notFound:
        return _notice(
          icon: Icons.help_outline_rounded,
          color: AppColors.warning,
          title: 'Tidak terdaftar',
          subtitle: 'QR ini tidak cocok dengan data karyawan.',
        );
      case LookupStatus.ambiguous:
        return Column(
          children: [
            _notice(
              icon: Icons.people_alt_rounded,
              color: AppColors.info,
              title: 'Pilih karyawan',
              subtitle: r.message,
            ),
            const SizedBox(height: 8),
            for (final c in r.candidates)
              Card(
                margin: const EdgeInsets.only(bottom: 6),
                child: ListTile(
                  dense: true,
                  title: Text(
                    c.nama,
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  subtitle: Text(c.bagian ?? '-'),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: () => onPick(c.id),
                ),
              ),
          ],
        );
      case LookupStatus.found:
        final e = r.employee!;
        final (color, icon) = switch (e.shift.kode) {
          'PAGI' => (const Color(0xFFF9A825), Icons.wb_sunny_rounded),
          'SORE' => (const Color(0xFF5C6BC0), Icons.wb_twilight_rounded),
          'TIDAK_PASTI' => (AppColors.warning, Icons.help_outline_rounded),
          _ => (AppColors.textSecondary, Icons.person_add_alt_1_rounded),
        };
        return Column(
          children: [
            Text(
              e.nama,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w800,
                color: AppColors.textPrimary,
              ),
            ),
            if (e.bagian != null && e.bagian!.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Text(
                  e.bagian!,
                  style: const TextStyle(color: AppColors.textSecondary),
                ),
              ),
            if (!e.aktif)
              const Padding(
                padding: EdgeInsets.only(top: 6),
                child: Text(
                  'Karyawan nonaktif',
                  style: TextStyle(
                    color: AppColors.error,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            const SizedBox(height: 12),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 12),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: color.withValues(alpha: 0.5)),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(icon, color: color),
                  const SizedBox(width: 10),
                  Flexible(
                    child: Text(
                      e.shift.label,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: color,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        );
    }
  }

  Widget _notice({
    required IconData icon,
    required Color color,
    required String title,
    required String subtitle,
    Widget? action,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Column(
        children: [
          Icon(icon, color: color),
          const SizedBox(height: 6),
          Text(
            title,
            style: TextStyle(fontWeight: FontWeight.w700, color: color),
          ),
          if (subtitle.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(
                subtitle,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 12,
                  color: AppColors.textSecondary,
                ),
              ),
            ),
          if (action != null) action,
        ],
      ),
    );
  }
}
