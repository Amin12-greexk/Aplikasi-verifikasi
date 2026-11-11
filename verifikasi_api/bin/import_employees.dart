import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:verifikasi_api/db.dart';
import 'package:verifikasi_api/employee_import.dart';

const _usage = '''
Import data karyawan & shift dari Excel.

  Master karyawan:
    import_employees master --file DATA.xlsx [--sheet "DATA KARYAWAN"]
                            [--deactivate-missing] [--commit]

  Shift dari presensi bulan lalu:
    import_employees presensi --file PRESENSI.xlsx --sheet OKTOBER
                              [--periode 2026-10] [--commit]

Opsi umum:
  --db PATH       Path database (default: env DB_PATH atau data/log.db)
  --report PATH   Simpan laporan lengkap (JSON), termasuk daftar masalah
  --commit        Tulis ke database. Tanpa ini hanya DRY-RUN (pratinjau).

Urutan: import master dulu, baru presensi.
''';

Future<void> main(List<String> args) async {
  if (args.isEmpty || args.first == '-h' || args.first == '--help') {
    stdout.write(_usage);
    return;
  }
  final cmd = args.first;
  final opts = <String, String>{};
  final flags = <String>{};
  for (var i = 1; i < args.length; i++) {
    final a = args[i];
    if (!a.startsWith('--')) {
      stderr.writeln('Argumen tidak dikenal: $a');
      exit(64);
    }
    final key = a.substring(2);
    if (key == 'commit' || key == 'deactivate-missing') {
      flags.add(key);
    } else if (i + 1 < args.length) {
      opts[key] = args[++i];
    } else {
      stderr.writeln('Opsi --$key butuh nilai');
      exit(64);
    }
  }

  final file = opts['file'];
  if (file == null || !File(file).existsSync()) {
    stderr.writeln('--file wajib dan harus ada.\n$_usage');
    exit(64);
  }

  final dbPath =
      opts['db'] ?? Platform.environment['DB_PATH'] ?? p.join('data', 'log.db');
  final dir = p.dirname(dbPath);
  if (dir.isNotEmpty && dir != '.') {
    Directory(dir).createSync(recursive: true);
  }
  final db = await initDb(dbPath);

  try {
    final commit = flags.contains('commit');
    final ImportReport rep;
    switch (cmd) {
      case 'master':
        rep = importEmployees(
          db,
          file,
          sheet: opts['sheet'] ?? 'DATA KARYAWAN',
          commit: commit,
          deactivateMissing: flags.contains('deactivate-missing'),
        );
      case 'presensi':
        final sheet = opts['sheet'];
        if (sheet == null) {
          stderr.writeln('--sheet wajib untuk presensi (mis. OKTOBER)');
          exit(64);
        }
        rep = importPresensi(
          db,
          file,
          sheet: sheet,
          periode: opts['periode'],
          commit: commit,
        );
      default:
        stderr.writeln('Perintah tidak dikenal: $cmd\n$_usage');
        exit(64);
    }

    stdout.write(rep.pretty());
    final reportPath = opts['report'];
    if (reportPath != null) {
      File(reportPath).writeAsStringSync(
        const JsonEncoder.withIndent('  ').convert(rep.toJson()),
      );
      stdout.writeln('Laporan lengkap: $reportPath');
    }
    if (!commit) {
      stdout.writeln('\nDRY-RUN. Tambahkan --commit untuk menyimpan.');
    }
  } finally {
    db.dispose();
  }
}
