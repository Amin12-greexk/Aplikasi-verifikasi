import 'dart:convert';
import 'dart:io';

import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';
import 'package:sqlite3/sqlite3.dart';

import 'handlers.dart' show parseBarcodeInfo;

// ─────────────────────────────────────────────────────────────────────────────
// Master karyawan + shift bulanan.
//
// - `employees`            : sumber utama (dari Excel DATA KARYAWAN).
// - `employee_shift_month` : shift dominan per karyawan per bulan (dari presensi).
// - `import_batches`       : jejak audit tiap import.
// ─────────────────────────────────────────────────────────────────────────────

const shiftPagi = 'PAGI';
const shiftSore = 'SORE';
const shiftTidakPasti = 'TIDAK_PASTI';

void ensureEmployeeSchema(Database db) {
  db.execute('''
    CREATE TABLE IF NOT EXISTS employees (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      nik TEXT UNIQUE NOT NULL,
      pin TEXT,
      nama TEXT NOT NULL,
      nama_normalized TEXT NOT NULL,
      bagian TEXT,
      shift_manual TEXT CHECK(shift_manual IN ('PAGI', 'SORE')),
      is_active INTEGER NOT NULL DEFAULT 1,
      batch_id INTEGER,
      created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
      updated_at DATETIME DEFAULT CURRENT_TIMESTAMP
    );
  ''');
  db.execute(
    'CREATE UNIQUE INDEX IF NOT EXISTS idx_employees_pin ON employees(pin) WHERE pin IS NOT NULL;',
  );
  db.execute(
    'CREATE INDEX IF NOT EXISTS idx_employees_nama ON employees(nama_normalized);',
  );

  db.execute('''
    CREATE TABLE IF NOT EXISTS employee_shift_month (
      employee_id INTEGER NOT NULL,
      periode TEXT NOT NULL,
      shift TEXT NOT NULL CHECK(shift IN ('PAGI', 'SORE', 'TIDAK_PASTI')),
      hari_pagi INTEGER NOT NULL DEFAULT 0,
      hari_sore INTEGER NOT NULL DEFAULT 0,
      batch_id INTEGER,
      PRIMARY KEY (employee_id, periode),
      FOREIGN KEY (employee_id) REFERENCES employees (id) ON DELETE CASCADE
    );
  ''');

  db.execute('''
    CREATE TABLE IF NOT EXISTS import_batches (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      jenis TEXT NOT NULL,
      nama_file TEXT,
      periode TEXT,
      ringkasan TEXT,
      created_at DATETIME DEFAULT CURRENT_TIMESTAMP
    );
  ''');
}

// ── Normalisasi ──────────────────────────────────────────────────────────────

/// Huruf besar, tanda baca jadi spasi, spasi ganda dibuang.
/// "HOO,ANTON  SISWANTO" -> "HOO ANTON SISWANTO"; "SA'ADAH" -> "SAADAH".
String normalizeName(String input) {
  final noApostrophe = input.replaceAll(RegExp("['`’]"), '');
  return noApostrophe
      .toUpperCase()
      .replaceAll(RegExp(r'[^A-Z0-9]+'), ' ')
      .trim();
}

/// Hanya digit. "@3321..." -> "3321...".
String normalizeDigits(String input) => input.replaceAll(RegExp(r'[^0-9]'), '');

// ── Lookup ───────────────────────────────────────────────────────────────────

class _Candidate {
  _Candidate(this.row);
  final Row row;
  int get id => row['id'] as int;
}

Map<String, Object?> _shiftInfo(Database db, Row emp) {
  final manual = emp['shift_manual'] as String?;
  if (manual != null && manual.isNotEmpty) {
    return {
      'kode': manual,
      'sumber': 'manual',
      'periode': null,
      'label': 'Shift ${_title(manual)} (diisi manual)',
    };
  }

  final rows = db.select(
    'SELECT periode, shift, hari_pagi, hari_sore FROM employee_shift_month '
    'WHERE employee_id=? ORDER BY periode DESC LIMIT 1',
    [emp['id']],
  );
  if (rows.isEmpty) {
    return {
      'kode': null,
      'sumber': null,
      'periode': null,
      'label': 'Karyawan baru, belum ada data shift',
    };
  }

  final r = rows.first;
  final kode = r['shift'] as String;
  final periode = r['periode'] as String;
  final label = kode == shiftTidakPasti
      ? 'Shift tidak pasti (berdasarkan ${_periodeLabel(periode)})'
      : 'Shift ${_title(kode)} (berdasarkan ${_periodeLabel(periode)})';
  return {
    'kode': kode,
    'sumber': 'presensi',
    'periode': periode,
    'hari_pagi': r['hari_pagi'],
    'hari_sore': r['hari_sore'],
    'label': label,
  };
}

String _title(String s) => s.isEmpty ? s : s[0] + s.substring(1).toLowerCase();

const _bulan = [
  'Januari', 'Februari', 'Maret', 'April', 'Mei', 'Juni', 'Juli', 'Agustus',
  'September', 'Oktober', 'November', 'Desember', //
];

String _periodeLabel(String periode) {
  final m = RegExp(r'^(\d{4})-(\d{2})$').firstMatch(periode);
  if (m == null) return periode;
  final idx = int.parse(m.group(2)!) - 1;
  if (idx < 0 || idx > 11) return periode;
  return '${_bulan[idx]} ${m.group(1)}';
}

/// NIK dan alamat sengaja TIDAK dikembalikan: endpoint ini bisa dipanggil
/// sebelum login.
Map<String, Object?> _publicEmployee(Database db, Row emp) => {
  'id': emp['id'],
  'nama': emp['nama'],
  'bagian': emp['bagian'],
  'aktif': emp['is_active'] == 1,
  'shift': _shiftInfo(db, emp),
};

/// Cocokkan isi QR / teks ke karyawan.
/// Urutan: NIK -> PIN -> nama ternormalisasi.
Map<String, Object?> lookupEmployee(Database db, String raw) {
  final text = raw.trim();
  if (text.isEmpty) {
    return {'status': 'NOT_FOUND', 'message': 'Data kosong'};
  }

  final info = parseBarcodeInfo(text);
  final nik = normalizeDigits(info['NIK'] ?? '');
  final pin = (info['PIN'] ?? '').trim();
  final nameText = (info['Nama'] ?? '').isNotEmpty ? info['Nama']! : text;

  List<_Candidate> find(String sql, List<Object?> args) =>
      db.select(sql, args).map(_Candidate.new).toList();

  var found = <_Candidate>[];
  if (nik.length >= 10) {
    found = find('SELECT * FROM employees WHERE nik=?', [nik]);
  }
  if (found.isEmpty && pin.isNotEmpty) {
    found = find('SELECT * FROM employees WHERE pin=?', [pin]);
  }
  if (found.isEmpty) {
    final norm = normalizeName(nameText);
    if (norm.isNotEmpty) {
      found = find('SELECT * FROM employees WHERE nama_normalized=?', [norm]);
    }
  }

  // Utamakan yang aktif; kalau semuanya nonaktif tetap tampilkan.
  final active = found.where((c) => c.row['is_active'] == 1).toList();
  if (active.isNotEmpty) found = active;

  if (found.isEmpty) {
    return {'status': 'NOT_FOUND', 'message': 'Tidak terdaftar'};
  }
  if (found.length > 1) {
    return {
      'status': 'AMBIGUOUS',
      'message': 'Ada ${found.length} karyawan dengan nama yang sama',
      'candidates': [
        for (final c in found)
          {'id': c.id, 'nama': c.row['nama'], 'bagian': c.row['bagian']},
      ],
    };
  }
  return {'status': 'FOUND', 'employee': _publicEmployee(db, found.first.row)};
}

Map<String, Object?> lookupEmployeeById(Database db, int id) {
  final rows = db.select('SELECT * FROM employees WHERE id=?', [id]);
  if (rows.isEmpty) return {'status': 'NOT_FOUND', 'message': 'Tidak terdaftar'};
  return {'status': 'FOUND', 'employee': _publicEmployee(db, rows.first)};
}

// ── Route ────────────────────────────────────────────────────────────────────

/// Pembatas sederhana: maks [limit] permintaan per [window] per IP.
class _RateLimiter {
  _RateLimiter(this.limit, this.window);
  final int limit;
  final Duration window;
  final _hits = <String, List<DateTime>>{};

  bool allow(String key) {
    final now = DateTime.now();
    final list = _hits.putIfAbsent(key, () => []);
    list.removeWhere((t) => now.difference(t) > window);
    if (list.length >= limit) return false;
    list.add(now);
    if (_hits.length > 5000) {
      _hits.removeWhere((_, v) => v.isEmpty || now.difference(v.last) > window);
    }
    return true;
  }
}

String _clientKey(Request req) {
  final fwd = req.headers['x-forwarded-for'];
  if (fwd != null && fwd.isNotEmpty) return fwd.split(',').first.trim();
  final info = req.context['shelf.io.connection_info'];
  if (info is HttpConnectionInfo) return info.remoteAddress.address;
  return 'unknown';
}

/// `POST /employee/lookup`
///   body: {"q": "isi QR"}  atau  {"employee_id": 12}
///
/// POST (bukan GET) supaya isi QR tidak muncul di URL / log request.
/// Env opsional `LOOKUP_API_KEY`: bila diisi, header `x-api-key` wajib.
void registerEmployeeRoutes(Router r, Database db) {
  final apiKey = Platform.environment['LOOKUP_API_KEY']?.trim() ?? '';
  final limiter = _RateLimiter(120, const Duration(minutes: 1));

  Response json(int code, Map<String, Object?> body) => Response(
    code,
    body: jsonEncode(body),
    headers: {'Content-Type': 'application/json'},
  );

  r.post('/employee/lookup', (Request req) async {
    if (apiKey.isNotEmpty && req.headers['x-api-key'] != apiKey) {
      return json(401, {'error': 'API key tidak valid'});
    }
    if (!limiter.allow(_clientKey(req))) {
      return json(429, {'error': 'Terlalu banyak permintaan'});
    }
    try {
      final body = jsonDecode(await req.readAsString());
      if (body is! Map) return json(400, {'error': 'Body tidak valid'});

      final id = body['employee_id'];
      if (id != null) {
        final intId = id is int ? id : int.tryParse(id.toString());
        if (intId == null) return json(400, {'error': 'employee_id tidak valid'});
        return json(200, lookupEmployeeById(db, intId));
      }

      final q = body['q']?.toString() ?? '';
      if (q.trim().isEmpty) return json(400, {'error': 'q wajib diisi'});
      return json(200, lookupEmployee(db, q));
    } catch (e) {
      return json(500, {'error': 'Error: $e'});
    }
  });
}
