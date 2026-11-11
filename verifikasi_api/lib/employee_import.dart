import 'dart:convert';
import 'dart:io';

import 'package:excel/excel.dart';
import 'package:sqlite3/sqlite3.dart';

import 'employees.dart';

/// Batas jam masuk: sebelum 12:00 = PAGI, selain itu SORE.
const shiftCutoffHour = 12;

/// Minimal hari hadir agar shift dianggap pasti.
const minHariHadir = 5;

/// Porsi minimal shift dominan agar dianggap pasti.
const minDominanRatio = 0.6;

class ImportReport {
  ImportReport(this.jenis);
  final String jenis;
  final Map<String, Object?> summary = {};
  final List<Map<String, Object?>> issues = [];

  void issue(String type, Map<String, Object?> data) =>
      issues.add({'type': type, ...data});

  Map<String, Object?> toJson() => {
    'jenis': jenis,
    'ringkasan': summary,
    'masalah': issues,
  };

  String pretty() {
    final b = StringBuffer('== Laporan import $jenis ==\n');
    summary.forEach((k, v) => b.writeln('  $k: $v'));
    final byType = <String, int>{};
    for (final i in issues) {
      byType.update(i['type'] as String, (n) => n + 1, ifAbsent: () => 1);
    }
    if (byType.isNotEmpty) {
      b.writeln('  Masalah:');
      byType.forEach((k, v) => b.writeln('    - $k: $v'));
    }
    return b.toString();
  }
}

// ── Excel helpers ────────────────────────────────────────────────────────────

String _cell(Data? d) {
  final v = d?.value;
  if (v == null) return '';
  return switch (v) {
    TextCellValue() => v.value.toString(),
    IntCellValue() => v.value.toString(),
    DoubleCellValue() =>
      v.value == v.value.roundToDouble()
          ? v.value.toInt().toString()
          : v.value.toString(),
    _ => v.toString(),
  }.trim();
}

Sheet _sheet(Excel xl, String name) {
  final wanted = name.trim().toUpperCase();
  for (final entry in xl.tables.entries) {
    if (entry.key.trim().toUpperCase() == wanted) return entry.value;
  }
  throw ArgumentError(
    'Sheet "$name" tidak ditemukan. Sheet tersedia: ${xl.tables.keys.join(', ')}',
  );
}

Excel _open(String path) => Excel.decodeBytes(File(path).readAsBytesSync());

int _insertBatch(
  Database db,
  String jenis,
  String file,
  String? periode,
  ImportReport rep,
) {
  db.execute(
    'INSERT INTO import_batches(jenis, nama_file, periode, ringkasan) VALUES(?, ?, ?, ?)',
    [jenis, file, periode, jsonEncode(rep.summary)],
  );
  return db.lastInsertRowId;
}

// ── Master karyawan ──────────────────────────────────────────────────────────

/// Import sheet master (kolom: PIN, NAMA, NIK, BAGIAN, opsional SHIFT).
/// Upsert berdasarkan NIK. Tulis ke DB hanya bila [commit] true.
ImportReport importEmployees(
  Database db,
  String path, {
  String sheet = 'DATA KARYAWAN',
  bool commit = false,
  bool deactivateMissing = false,
}) {
  final rep = ImportReport('master karyawan');
  final rows = _sheet(_open(path), sheet).rows;

  // Cari baris header (yang memuat NAMA dan NIK).
  var headerIdx = -1;
  late Map<String, int> col;
  for (var i = 0; i < rows.length && i < 15; i++) {
    final names = {
      for (var c = 0; c < rows[i].length; c++)
        _cell(rows[i][c]).toUpperCase(): c,
    };
    if (names.containsKey('NAMA') && names.containsKey('NIK')) {
      headerIdx = i;
      col = names;
      break;
    }
  }
  if (headerIdx < 0) {
    throw StateError('Header (NAMA, NIK) tidak ditemukan di sheet "$sheet"');
  }

  String at(List<Data?> r, String name) {
    final c = col[name];
    return (c == null || c >= r.length) ? '' : _cell(r[c]);
  }

  final seenNik = <String>{};
  final seenPin = <String, String>{};
  final parsed = <Map<String, String>>[];
  var skipped = 0;

  for (var i = headerIdx + 1; i < rows.length; i++) {
    final r = rows[i];
    final nama = at(r, 'NAMA');
    final nikRaw = at(r, 'NIK');
    if (nama.isEmpty && nikRaw.isEmpty) continue;
    final line = i + 1;

    final nik = normalizeDigits(nikRaw);
    if (nama.isEmpty || nik.isEmpty) {
      skipped++;
      rep.issue('BARIS_DILEWATI_NAMA_ATAU_NIK_KOSONG', {
        'baris': line,
        'nama': nama,
      });
      continue;
    }
    if (nik.length != 16) {
      rep.issue('NIK_BUKAN_16_DIGIT', {
        'baris': line,
        'nama': nama,
        'nik_panjang': nik.length,
      });
    }
    if (nik != nikRaw) {
      rep.issue('NIK_DIBERSIHKAN', {'baris': line, 'nama': nama});
    }
    if (!seenNik.add(nik)) {
      skipped++;
      rep.issue('NIK_KEMBAR_DILEWATI', {'baris': line, 'nama': nama});
      continue;
    }

    var pin = at(r, 'PIN');
    if (pin.isNotEmpty) {
      final prev = seenPin[pin];
      if (prev != null) {
        rep.issue('PIN_KEMBAR_DIABAIKAN', {
          'baris': line,
          'nama': nama,
          'pin': pin,
          'sama_dengan': prev,
        });
        pin = '';
      } else {
        seenPin[pin] = nama;
      }
    }

    var shift = at(r, 'SHIFT').toUpperCase();
    if (shift.isNotEmpty && shift != shiftPagi && shift != shiftSore) {
      rep.issue('SHIFT_MANUAL_TIDAK_VALID', {
        'baris': line,
        'nama': nama,
        'nilai': shift,
      });
      shift = '';
    }

    parsed.add({
      'nik': nik,
      'pin': pin,
      'nama': nama,
      'bagian': at(r, 'BAGIAN'),
      'shift': shift,
    });
  }

  // Nama kembar: bukan error, hanya info (lookup akan menampilkan pilihan).
  final byName = <String, List<String>>{};
  for (final p in parsed) {
    byName.putIfAbsent(normalizeName(p['nama']!), () => []).add(p['nik']!);
  }
  byName.forEach((n, niks) {
    if (niks.length > 1) {
      rep.issue('NAMA_KEMBAR', {'nama': n, 'jumlah': niks.length});
    }
  });

  var baru = 0, diperbarui = 0;
  final existing = {
    for (final r in db.select('SELECT nik FROM employees')) r['nik'] as String,
  };
  for (final p in parsed) {
    existing.contains(p['nik']) ? diperbarui++ : baru++;
  }
  final hilang = existing.difference({for (final p in parsed) p['nik']!});

  rep.summary.addAll({
    'baris_terbaca': parsed.length + skipped,
    'baru': baru,
    'diperbarui': diperbarui,
    'dilewati': skipped,
    'ada_di_db_tapi_tidak_di_file': hilang.length,
    'mode': commit ? 'COMMIT' : 'DRY-RUN (tidak ada yang ditulis)',
  });
  if (!commit) return rep;

  db.execute('BEGIN');
  try {
    final batchId = _insertBatch(db, 'master', path, null, rep);
    final upsert = db.prepare('''
      INSERT INTO employees(nik, pin, nama, nama_normalized, bagian, shift_manual, is_active, batch_id)
      VALUES(?, ?, ?, ?, ?, ?, 1, ?)
      ON CONFLICT(nik) DO UPDATE SET
        pin=excluded.pin, nama=excluded.nama, nama_normalized=excluded.nama_normalized,
        bagian=excluded.bagian,
        shift_manual=COALESCE(excluded.shift_manual, employees.shift_manual),
        is_active=1, batch_id=excluded.batch_id, updated_at=CURRENT_TIMESTAMP
    ''');
    for (final p in parsed) {
      upsert.execute([
        p['nik'],
        p['pin']!.isEmpty ? null : p['pin'],
        p['nama'],
        normalizeName(p['nama']!),
        p['bagian']!.isEmpty ? null : p['bagian'],
        p['shift']!.isEmpty ? null : p['shift'],
        batchId,
      ]);
    }
    upsert.dispose();
    if (deactivateMissing) {
      final off = db.prepare(
        'UPDATE employees SET is_active=0, updated_at=CURRENT_TIMESTAMP WHERE nik=?',
      );
      for (final nik in hilang) {
        off.execute([nik]);
      }
      off.dispose();
    }
    db.execute('COMMIT');
  } catch (_) {
    db.execute('ROLLBACK');
    rethrow;
  }
  return rep;
}

// ── Presensi -> shift bulanan ────────────────────────────────────────────────

class _Count {
  int pagi = 0;
  int sore = 0;
}

/// "01/10/26" -> (2026, 10). Mengembalikan null bila bukan tanggal.
({int year, int month})? _parseDate(String s) {
  final m = RegExp(r'^(\d{1,2})/(\d{1,2})/(\d{2}|\d{4})$').firstMatch(s);
  if (m == null) return null;
  final month = int.parse(m.group(2)!);
  var year = int.parse(m.group(3)!);
  if (year < 100) year += 2000;
  if (month < 1 || month > 12) return null;
  return (year: year, month: month);
}

/// Jam dari "07:58" / "7.58" / "07:58:12". null bila tidak valid.
int? _parseHour(String s) {
  final m = RegExp(r'^(\d{1,2})[:.](\d{2})').firstMatch(s);
  if (m == null) return null;
  final h = int.parse(m.group(1)!);
  return (h >= 0 && h <= 23) ? h : null;
}

String decideShift(int pagi, int sore) {
  final total = pagi + sore;
  if (total < minHariHadir) return shiftTidakPasti;
  if (pagi / total >= minDominanRatio) return shiftPagi;
  if (sore / total >= minDominanRatio) return shiftSore;
  return shiftTidakPasti;
}

/// Hitung shift dominan per karyawan dari sheet presensi bulanan lalu simpan
/// ke `employee_shift_month`. Penghubung ke master adalah PIN.
ImportReport importPresensi(
  Database db,
  String path, {
  required String sheet,
  String? periode,
  bool commit = false,
}) {
  final rep = ImportReport('presensi $sheet');
  final rows = _sheet(_open(path), sheet).rows;
  if (rows.length < 3) throw StateError('Sheet "$sheet" terlalu pendek');

  // Baris 1: tanggal (di kolom IN, kolom berikutnya kosong). Baris 2: IN/OUT.
  final dateRow = rows[0];
  final inCols = <int>[];
  final months = <String, int>{};
  for (var c = 2; c < dateRow.length; c++) {
    final d = _parseDate(_cell(dateRow[c]));
    if (d == null) continue;
    inCols.add(c);
    final key = '${d.year}-${d.month.toString().padLeft(2, '0')}';
    months.update(key, (n) => n + 1, ifAbsent: () => 1);
  }
  if (inCols.isEmpty) {
    throw StateError('Tidak ada kolom tanggal di baris pertama sheet "$sheet"');
  }
  final detected = (months.entries.toList()
        ..sort((a, b) => b.value.compareTo(a.value)))
      .first
      .key;
  final per = periode ?? detected;
  if (periode != null && periode != detected) {
    rep.issue('PERIODE_BEDA_DARI_TANGGAL_DI_SHEET', {
      'diminta': periode,
      'terdeteksi': detected,
    });
  }

  // Satu PIN bisa muncul di beberapa baris (blok shift 1 & 2): gabungkan.
  final perPin = <String, _Count>{};
  final namaPin = <String, String>{};
  for (var i = 2; i < rows.length; i++) {
    final r = rows[i];
    if (r.length < 2) continue;
    final pin = _cell(r[0]);
    if (!RegExp(r'^\d+$').hasMatch(pin)) continue;
    namaPin.putIfAbsent(pin, () => _cell(r[1]));
    final cnt = perPin.putIfAbsent(pin, _Count.new);
    for (final c in inCols) {
      if (c >= r.length) continue;
      final h = _parseHour(_cell(r[c]));
      if (h == null) continue;
      h < shiftCutoffHour ? cnt.pagi++ : cnt.sore++;
    }
  }

  final empByPin = {
    for (final r in db.select(
      'SELECT id, pin, nama FROM employees WHERE pin IS NOT NULL',
    ))
      r['pin'] as String: r,
  };

  final toSave = <({int id, String shift, int pagi, int sore})>[];
  final dist = <String, int>{shiftPagi: 0, shiftSore: 0, shiftTidakPasti: 0};
  var tanpaHadir = 0;
  for (final e in perPin.entries) {
    final emp = empByPin[e.key];
    if (emp == null) {
      rep.issue('PIN_TIDAK_ADA_DI_MASTER', {
        'pin': e.key,
        'nama': namaPin[e.key],
      });
      continue;
    }
    final cnt = e.value;
    if (cnt.pagi + cnt.sore == 0) tanpaHadir++;
    final shift = decideShift(cnt.pagi, cnt.sore);
    dist.update(shift, (n) => n + 1);
    toSave.add((id: emp['id'] as int, shift: shift, pagi: cnt.pagi, sore: cnt.sore));
    if (shift == shiftTidakPasti) {
      rep.issue('SHIFT_TIDAK_PASTI', {
        'pin': e.key,
        'nama': emp['nama'],
        'hari_pagi': cnt.pagi,
        'hari_sore': cnt.sore,
      });
    }
  }

  final sudahDiShift = {for (final s in toSave) s.id};
  final totalTanpaManual = db
      .select(
        'SELECT COUNT(*) AS n FROM employees WHERE is_active=1 '
        'AND shift_manual IS NULL',
      )
      .first['n'] as int;
  final masterTanpaPresensi = totalTanpaManual - sudahDiShift.length;

  rep.summary.addAll({
    'periode': per,
    'tanggal_di_sheet': inCols.length,
    'pin_unik_di_presensi': perPin.length,
    'cocok_dengan_master': toSave.length,
    'pin_tidak_ada_di_master': perPin.length - toSave.length,
    'pin_tanpa_kehadiran': tanpaHadir,
    'shift_PAGI': dist[shiftPagi],
    'shift_SORE': dist[shiftSore],
    'shift_TIDAK_PASTI': dist[shiftTidakPasti],
    'master_aktif_tanpa_shift_presensi_atau_manual':
        masterTanpaPresensi < 0 ? 0 : masterTanpaPresensi,
    'mode': commit ? 'COMMIT' : 'DRY-RUN (tidak ada yang ditulis)',
  });
  if (!commit) return rep;

  db.execute('BEGIN');
  try {
    final batchId = _insertBatch(db, 'presensi', path, per, rep);
    final up = db.prepare('''
      INSERT INTO employee_shift_month(employee_id, periode, shift, hari_pagi, hari_sore, batch_id)
      VALUES(?, ?, ?, ?, ?, ?)
      ON CONFLICT(employee_id, periode) DO UPDATE SET
        shift=excluded.shift, hari_pagi=excluded.hari_pagi,
        hari_sore=excluded.hari_sore, batch_id=excluded.batch_id
    ''');
    for (final s in toSave) {
      up.execute([s.id, per, s.shift, s.pagi, s.sore, batchId]);
    }
    up.dispose();
    db.execute('COMMIT');
  } catch (_) {
    db.execute('ROLLBACK');
    rethrow;
  }
  return rep;
}
