import 'dart:convert';

import '../../core/network/base_api_client.dart';

/// API key untuk endpoint lookup (opsional). Isi saat build:
/// `flutter build apk --dart-define=LOOKUP_API_KEY=xxxx`
const String _lookupApiKey = String.fromEnvironment('LOOKUP_API_KEY');

enum LookupStatus { found, ambiguous, notFound }

class ShiftInfo {
  final String? kode; // PAGI | SORE | TIDAK_PASTI | null
  final String label;

  const ShiftInfo({required this.kode, required this.label});

  factory ShiftInfo.fromJson(Map<String, dynamic> j) => ShiftInfo(
    kode: j['kode'] as String?,
    label: (j['label'] as String?) ?? '',
  );
}

class EmployeeInfo {
  final int id;
  final String nama;
  final String? bagian;
  final bool aktif;
  final ShiftInfo shift;

  const EmployeeInfo({
    required this.id,
    required this.nama,
    required this.bagian,
    required this.aktif,
    required this.shift,
  });

  factory EmployeeInfo.fromJson(Map<String, dynamic> j) => EmployeeInfo(
    id: j['id'] as int,
    nama: (j['nama'] as String?) ?? '',
    bagian: j['bagian'] as String?,
    aktif: j['aktif'] as bool? ?? true,
    shift: ShiftInfo.fromJson((j['shift'] as Map).cast<String, dynamic>()),
  );
}

class EmployeeCandidate {
  final int id;
  final String nama;
  final String? bagian;

  const EmployeeCandidate({
    required this.id,
    required this.nama,
    required this.bagian,
  });
}

class LookupResult {
  final LookupStatus status;
  final String message;
  final EmployeeInfo? employee;
  final List<EmployeeCandidate> candidates;

  const LookupResult({
    required this.status,
    this.message = '',
    this.employee,
    this.candidates = const [],
  });
}

class EmployeeLookupService {
  /// Cari karyawan dari isi QR. Melempar [Exception] bila jaringan/server gagal.
  static Future<LookupResult> lookup(String qrText) =>
      _post({'q': qrText});

  /// Dipakai setelah petugas memilih salah satu kandidat (nama kembar).
  static Future<LookupResult> lookupById(int id) =>
      _post({'employee_id': id});

  static Future<LookupResult> _post(Map<String, dynamic> body) async {
    final res = await BaseApiClient.post(
      '/employee/lookup',
      body: body,
      headers: _lookupApiKey.isEmpty ? null : {'x-api-key': _lookupApiKey},
    );
    final json = BaseApiClient.tryJson(utf8.decode(res.bodyBytes));

    if (res.statusCode == 401) {
      throw Exception('API key tidak valid');
    }
    if (res.statusCode == 429) {
      throw Exception('Terlalu banyak scan, coba lagi sebentar');
    }
    if (res.statusCode != 200) {
      throw Exception((json['error'] as String?) ?? 'Server error (${res.statusCode})');
    }

    switch (json['status']) {
      case 'FOUND':
        return LookupResult(
          status: LookupStatus.found,
          employee: EmployeeInfo.fromJson(
            (json['employee'] as Map).cast<String, dynamic>(),
          ),
        );
      case 'AMBIGUOUS':
        return LookupResult(
          status: LookupStatus.ambiguous,
          message: (json['message'] as String?) ?? '',
          candidates: [
            for (final c in (json['candidates'] as List))
              EmployeeCandidate(
                id: c['id'] as int,
                nama: (c['nama'] as String?) ?? '',
                bagian: c['bagian'] as String?,
              ),
          ],
        );
      default:
        return LookupResult(
          status: LookupStatus.notFound,
          message: (json['message'] as String?) ?? 'Tidak terdaftar',
        );
    }
  }
}
