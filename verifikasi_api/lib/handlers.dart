import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';
import 'package:sqlite3/sqlite3.dart';

String _generateToken(String username, String role) {
  // Simple token generation - in production use JWT.
  return 'token_${username}_${role}_${DateTime.now().millisecondsSinceEpoch}';
}

String _extractBarcodeInfo(String fullBarcode) {
  // Extract PIN, Nama, and Bagian from barcode string.
  try {
    final namaMatch = RegExp(r'Nama:\s*([^|]+)').firstMatch(fullBarcode);
    final pinMatch = RegExp(r'PIN:\s*([^|]+)').firstMatch(fullBarcode);
    final bagianMatch = RegExp(r'Bagian:\s*([^|]+)').firstMatch(fullBarcode);

    final nama = namaMatch?.group(1)?.trim() ?? '';
    final pin = pinMatch?.group(1)?.trim() ?? '';
    final bagian = bagianMatch?.group(1)?.trim() ?? '';

    if (nama.isEmpty && pin.isEmpty && bagian.isEmpty) {
      return fullBarcode;
    }

    final parts = <String>[];
    if (pin.isNotEmpty) parts.add('PIN: $pin');
    if (nama.isNotEmpty) parts.add('Nama: $nama');
    if (bagian.isNotEmpty) parts.add('Bagian: $bagian');

    return parts.join(' | ');
  } catch (_) {
    return fullBarcode;
  }
}

// Retry logic for database operations.
Future<T> _retryDbOperation<T>(
  Future<T> Function() operation, {
  int maxRetries = 3,
}) async {
  for (int i = 0; i < maxRetries; i++) {
    try {
      return await operation();
    } catch (e) {
      if (e.toString().contains('database is locked') && i < maxRetries - 1) {
        await Future.delayed(Duration(milliseconds: 100 * (i + 1)));
        continue;
      }
      rethrow;
    }
  }
  throw Exception('Max retries exceeded');
}

const Duration _wibOffset = Duration(hours: 7);

DateTime _nowUtc() => DateTime.now().toUtc();

DateTime _toWib(DateTime value) => value.toUtc().add(_wibOffset);

String _twoDigits(int value) => value.toString().padLeft(2, '0');

String _threeDigits(int value) => value.toString().padLeft(3, '0');

String _formatWibIso(DateTime value) {
  final wib = _toWib(value);
  return '${wib.year}-${_twoDigits(wib.month)}-${_twoDigits(wib.day)}T'
      '${_twoDigits(wib.hour)}:${_twoDigits(wib.minute)}:${_twoDigits(wib.second)}.'
      '${_threeDigits(wib.millisecond)}+07:00';
}

DateTime _nextWibMidnightUtc([DateTime? referenceUtc]) {
  final nowUtc = referenceUtc ?? _nowUtc();
  final nowWib = _toWib(nowUtc);
  return DateTime.utc(
    nowWib.year,
    nowWib.month,
    nowWib.day + 1,
  ).subtract(_wibOffset);
}

bool _hasExplicitTimezone(String value) {
  return value.endsWith('Z') ||
      RegExp(r'[+-]\d{2}:\d{2}$').hasMatch(value) ||
      RegExp(r'[+-]\d{4}$').hasMatch(value);
}

String _formatDate(DateTime value) {
  final wib = _toWib(value);
  return '${wib.year}-${_twoDigits(wib.month)}-${_twoDigits(wib.day)}';
}

DateTime? _tryParseDateTime(Object? raw) {
  final value = raw?.toString().trim();
  if (value == null || value.isEmpty) return null;

  try {
    final normalized = value.replaceFirst(' ', 'T');
    if (_hasExplicitTimezone(normalized)) {
      return DateTime.parse(normalized).toUtc();
    }

    final parsed = DateTime.parse(normalized);
    return DateTime.utc(
      parsed.year,
      parsed.month,
      parsed.day,
      parsed.hour,
      parsed.minute,
      parsed.second,
      parsed.millisecond,
      parsed.microsecond,
    ).subtract(_wibOffset);
  } catch (_) {
    return null;
  }
}

int _normalizeDurationMinutes(Object? raw) {
  final parsed = int.tryParse(raw?.toString() ?? '');
  if (parsed == null) return 10;
  if (parsed < 1) return 1;
  if (parsed > 120) return 120;
  return parsed;
}

String _resolveToiletPermitState(Object? expiresAtRaw, {DateTime? now}) {
  final expiresAt = _tryParseDateTime(expiresAtRaw);
  if (expiresAt == null) return 'ACTIVE';

  final reference = now ?? _nowUtc();
  return expiresAt.isAfter(reference) ? 'ACTIVE' : 'EXPIRED';
}

int _remainingPermitSeconds(Object? expiresAtRaw, {DateTime? now}) {
  final expiresAt = _tryParseDateTime(expiresAtRaw);
  if (expiresAt == null) return 0;

  final reference = now ?? _nowUtc();
  final remaining = expiresAt.difference(reference).inSeconds;
  return remaining > 0 ? remaining : 0;
}

Map<String, Object?> _mapToiletPermitRow(
  Map<String, Object?> row, {
  DateTime? now,
}) {
  final reference = now ?? _nowUtc();
  final permitState = _resolveToiletPermitState(
    row['expires_at'],
    now: reference,
  );

  return {
    'id_karyawan': row['id_karyawan'],
    'duration_minutes': _normalizeDurationMinutes(row['duration_minutes']),
    'approved_by': row['approved_by'],
    'approved_at': row['approved_at'],
    'expires_at': row['expires_at'],
    'proof_scanned_by': row['proof_scanned_by'],
    'proof_scanned_at': row['proof_scanned_at'],
    'proof_status': row['proof_status']?.toString() ?? 'PENDING',
    'permit_state': permitState,
    'remaining_seconds': _remainingPermitSeconds(
      row['expires_at'],
      now: reference,
    ),
    'created_at': row['created_at'],
  };
}

Map<String, Object?> _mapToiletPermitHistoryRow(Map<String, Object?> row) {
  return {
    'id': row['id'],
    'id_karyawan': row['id_karyawan'],
    'duration_minutes': _normalizeDurationMinutes(row['duration_minutes']),
    'approved_by': row['approved_by'],
    'approved_at': row['approved_at'],
    'expires_at': row['expires_at'],
    'proof_scanned_by': row['proof_scanned_by'],
    'proof_scanned_at': row['proof_scanned_at'],
    'proof_status': row['proof_status']?.toString() ?? 'PENDING',
    'permit_state':
        row['permit_state']?.toString() ??
        _resolveToiletPermitState(row['expires_at']),
    'tanggal': row['tanggal'],
    'created_at': row['created_at'],
  };
}

void _saveToiletPermitHistory(
  Database db,
  Map<String, Object?> permitRow, {
  DateTime? now,
  String? permitState,
}) {
  final reference = now ?? _nowUtc();
  db.execute(
    'INSERT INTO toilet_permit_history(id_karyawan, duration_minutes, approved_by, approved_at, expires_at, proof_scanned_by, proof_scanned_at, proof_status, permit_state, tanggal) VALUES(?, ?, ?, ?, ?, ?, ?, ?, ?, ?)',
    [
      permitRow['id_karyawan'],
      _normalizeDurationMinutes(permitRow['duration_minutes']),
      permitRow['approved_by'],
      permitRow['approved_at'],
      permitRow['expires_at'],
      permitRow['proof_scanned_by'],
      permitRow['proof_scanned_at'],
      permitRow['proof_status']?.toString() ?? 'PENDING',
      permitState ??
          _resolveToiletPermitState(permitRow['expires_at'], now: reference),
      _formatDate(reference),
    ],
  );
}

/// Performs the daily reset operation.
/// Moves all current logs to history and clears the active tables.
Future<Map<String, dynamic>> performDailyReset(Database db) async {
  try {
    final today = _nowUtc();
    final tanggal = _formatDate(today);

    return await _retryDbOperation(() async {
      db.execute('BEGIN TRANSACTION');

      try {
        final currentLogs = db.select('SELECT * FROM log_pulang');
        var movedCount = 0;

        for (final log in currentLogs) {
          db.execute(
            'INSERT INTO log_pulang_history(id_karyawan, status_pengawas, status_security, pengawas_scanned_by, security_scanned_by, pengawas_scanned_at, security_scanned_at, tanggal) VALUES(?, ?, ?, ?, ?, ?, ?, ?)',
            [
              log['id_karyawan'],
              log['status_pengawas'],
              log['status_security'],
              log['pengawas_scanned_by'],
              log['security_scanned_by'],
              log['pengawas_scanned_at'],
              log['security_scanned_at'],
              tanggal,
            ],
          );
          movedCount++;
        }

        final currentPermits = db.select('SELECT * FROM toilet_permit');
        var movedPermitCount = 0;
        for (final permit in currentPermits) {
          _saveToiletPermitHistory(
            db,
            Map<String, Object?>.from(permit),
            now: today,
          );
          movedPermitCount++;
        }

        db.execute('DELETE FROM log_pulang');
        db.execute('DELETE FROM toilet_permit');
        db.execute('COMMIT');

        stdout.writeln(
          '[DAILY RESET] Reset completed at ${_formatWibIso(_nowUtc())}',
        );
        stdout.writeln(
          '[DAILY RESET] Moved $movedCount logs and $movedPermitCount toilet permits to history for date: $tanggal',
        );

        return {
          'success': true,
          'message': 'Daily reset completed',
          'tanggal': tanggal,
          'moved': movedCount,
          'moved_toilet_permits': movedPermitCount,
          'timestamp': _formatWibIso(_nowUtc()),
        };
      } catch (e) {
        db.execute('ROLLBACK');
        stderr.writeln('[DAILY RESET] Error during reset: $e');
        rethrow;
      }
    });
  } catch (e) {
    stderr.writeln('[DAILY RESET] Failed to perform daily reset: $e');
    return {
      'success': false,
      'message': 'Daily reset failed',
      'error': e.toString(),
    };
  }
}

/// Starts the automatic daily reset scheduler.
/// Resets data at 00:00 every day.
Timer? _dailyResetTimer;

void startDailyResetScheduler(Database db) {
  _dailyResetTimer?.cancel();

  void scheduleNextReset() {
    final nowUtc = _nowUtc();
    final nextMidnightUtc = _nextWibMidnightUtc(nowUtc);
    final duration = nextMidnightUtc.difference(nowUtc);

    stdout.writeln(
      '[SCHEDULER] Daily reset scheduled for WIB: ${_formatWibIso(nextMidnightUtc)}',
    );
    stdout.writeln(
      '[SCHEDULER] Time until next reset: ${duration.inHours}h ${duration.inMinutes % 60}m ${duration.inSeconds % 60}s',
    );

    _dailyResetTimer = Timer(duration, () async {
      stdout.writeln(
        '[SCHEDULER] Triggering automatic daily reset at 00:00 WIB',
      );

      final result = await performDailyReset(db);

      if (result['success'] == true) {
        stdout.writeln(
          '[SCHEDULER] Automatic reset successful: ${result['message']}',
        );
      } else {
        stderr.writeln(
          '[SCHEDULER] Automatic reset failed: ${result['error']}',
        );
      }

      scheduleNextReset();
    });
  }

  scheduleNextReset();
  stdout.writeln('[SCHEDULER] Daily reset scheduler initialized');
}

/// Stops the daily reset scheduler.
void stopDailyResetScheduler() {
  _dailyResetTimer?.cancel();
  _dailyResetTimer = null;
  stdout.writeln('[SCHEDULER] Daily reset scheduler stopped');
}

Future<Router> buildRouter(Database db) async {
  final r = Router();

  Response bad(String msg, {int code = 400}) => Response(
    code,
    body: jsonEncode({'error': msg}),
    headers: {'Content-Type': 'application/json'},
  );

  Response ok(Map<String, Object?> data) => Response.ok(
    jsonEncode(data),
    headers: {'Content-Type': 'application/json'},
  );

  void saveToHistory(
    String idKaryawan,
    String statusPengawas,
    String statusSecurity, [
    String? pengawasBy,
    String? securityBy,
    String? pengawasAt,
    String? securityAt,
  ]) {
    final today = _nowUtc();
    final nowIso = _formatWibIso(today);
    final tanggal = _formatDate(today);
    db.execute(
      'INSERT INTO log_pulang_history(id_karyawan, status_pengawas, status_security, pengawas_scanned_by, security_scanned_by, pengawas_scanned_at, security_scanned_at, tanggal) VALUES(?, ?, ?, ?, ?, ?, ?, ?)',
      [
        idKaryawan,
        statusPengawas,
        statusSecurity,
        pengawasBy,
        securityBy,
        pengawasAt ?? nowIso,
        securityAt ?? nowIso,
        tanggal,
      ],
    );
  }

  // Login endpoint.
  r.post('/auth/login', (Request req) async {
    try {
      final body = jsonDecode(await req.readAsString());
      final username = body['username']?.toString().trim();
      final password = body['password']?.toString().trim();
      final role = body['role']?.toString().trim();

      if (username == null || username.isEmpty) {
        return bad('Username wajib diisi');
      }
      if (password == null || password.isEmpty) {
        return bad('Password wajib diisi');
      }
      if (role == null || role.isEmpty) return bad('Role wajib diisi');
      if (role != 'pengawas' && role != 'security') {
        return bad('Role tidak valid');
      }

      final rows = db.select(
        'SELECT * FROM users WHERE username = ? AND password = ? AND role = ?',
        [username, password, role],
      );

      if (rows.isEmpty) return bad('Username atau password salah', code: 401);

      final user = rows.first;
      final token = _generateToken(username, role);

      return ok({
        'message': 'Login berhasil',
        'token': token,
        'username': user['username'],
        'role': user['role'],
      });
    } catch (e) {
      return bad('Error: $e', code: 500);
    }
  });

  r.post('/scan-pengawas', (Request req) async {
    final body = jsonDecode(await req.readAsString());
    var id = body['id_karyawan']?.toString().trim();
    final username = body['username']?.toString().trim();
    if (id == null || id.isEmpty) return bad('id_karyawan wajib');

    id = _extractBarcodeInfo(id);

    try {
      await _retryDbOperation(() async {
        final nowIso = _formatWibIso(_nowUtc());
        db.execute(
          'INSERT INTO log_pulang(id_karyawan, status_pengawas, status_security, pengawas_scanned_by, pengawas_scanned_at) VALUES(?, "ACC", "PENDING", ?, ?) '
          'ON CONFLICT(id_karyawan) DO UPDATE SET status_pengawas="ACC", pengawas_scanned_by=?, pengawas_scanned_at=?;',
          [id, username, nowIso, username, nowIso],
        );
        return null;
      });

      final nowIso = _formatWibIso(_nowUtc());
      saveToHistory(id, 'ACC', 'PENDING', username, null, nowIso, null);
      final row = db.select('SELECT * FROM log_pulang WHERE id_karyawan=?', [
        id,
      ]).first;
      return ok(Map<String, Object?>.from(row));
    } catch (e) {
      return bad('Error: $e', code: 500);
    }
  });

  r.post('/scan-security', (Request req) async {
    final body = jsonDecode(await req.readAsString());
    var id = body['id_karyawan']?.toString().trim();
    final username = body['username']?.toString().trim();
    if (id == null || id.isEmpty) return bad('id_karyawan wajib');

    id = _extractBarcodeInfo(id);

    try {
      final rows = db.select('SELECT * FROM log_pulang WHERE id_karyawan=?', [
        id,
      ]);
      if (rows.isEmpty) return bad('Belum ada ACC pengawas');

      final row = Map<String, Object?>.from(rows.first);
      if (row['status_pengawas'] != 'ACC') return bad('Pengawas belum ACC');

      final nowIso = _formatWibIso(_nowUtc());
      await _retryDbOperation(() async {
        db.execute(
          'UPDATE log_pulang SET status_security="ACC", security_scanned_by=?, security_scanned_at=? WHERE id_karyawan=?',
          [username, nowIso, id],
        );
        return null;
      });

      saveToHistory(
        id,
        'ACC',
        'ACC',
        row['pengawas_scanned_by']?.toString(),
        username,
        row['pengawas_scanned_at']?.toString(),
        nowIso,
      );
      final updated = db.select(
        'SELECT * FROM log_pulang WHERE id_karyawan=?',
        [id],
      ).first;
      return ok(Map<String, Object?>.from(updated));
    } catch (e) {
      return bad('Error: $e', code: 500);
    }
  });

  r.post('/toilet-permit/approve', (Request req) async {
    try {
      final body = jsonDecode(await req.readAsString());
      var id = body['id_karyawan']?.toString().trim();
      final username = body['username']?.toString().trim();
      final durationMinutes = _normalizeDurationMinutes(
        body['duration_minutes'],
      );

      if (id == null || id.isEmpty) return bad('id_karyawan wajib');
      if (username == null || username.isEmpty) return bad('username wajib');

      id = _extractBarcodeInfo(id);
      final now = _nowUtc();
      final expiresAtIso = _formatWibIso(
        now.add(Duration(minutes: durationMinutes)),
      );
      final approvedAtIso = _formatWibIso(now);
      final existing = db.select(
        'SELECT id_karyawan FROM toilet_permit WHERE id_karyawan=?',
        [id],
      );

      await _retryDbOperation(() async {
        db.execute(
          'INSERT INTO toilet_permit(id_karyawan, duration_minutes, approved_by, approved_at, expires_at, proof_scanned_by, proof_scanned_at, proof_status) VALUES(?, ?, ?, ?, ?, NULL, NULL, "PENDING") '
          'ON CONFLICT(id_karyawan) DO UPDATE SET duration_minutes=?, approved_by=?, approved_at=?, expires_at=?, proof_scanned_by=NULL, proof_scanned_at=NULL, proof_status="PENDING";',
          [
            id,
            durationMinutes,
            username,
            approvedAtIso,
            expiresAtIso,
            durationMinutes,
            username,
            approvedAtIso,
            expiresAtIso,
          ],
        );
        return null;
      });

      final row = Map<String, Object?>.from(
        db.select('SELECT * FROM toilet_permit WHERE id_karyawan=?', [
          id,
        ]).first,
      );
      _saveToiletPermitHistory(db, row, now: now, permitState: 'ACTIVE');

      return ok({
        ..._mapToiletPermitRow(row, now: now),
        'message': existing.isEmpty
            ? 'Izin toilet disetujui'
            : 'Izin toilet diperbarui',
      });
    } catch (e) {
      return bad('Error: $e', code: 500);
    }
  });

  r.post('/toilet-permit/proof-scan', (Request req) async {
    try {
      final body = jsonDecode(await req.readAsString());
      var id = body['id_karyawan']?.toString().trim();
      final username = body['username']?.toString().trim();

      if (id == null || id.isEmpty) return bad('id_karyawan wajib');
      if (username == null || username.isEmpty) return bad('username wajib');

      id = _extractBarcodeInfo(id);

      final rows = db.select(
        'SELECT * FROM toilet_permit WHERE id_karyawan=?',
        [id],
      );
      if (rows.isEmpty) return bad('Belum ada izin toilet dari pengawas');

      final now = _nowUtc();
      final permit = Map<String, Object?>.from(rows.first);
      final permitState = _resolveToiletPermitState(
        permit['expires_at'],
        now: now,
      );
      if (permitState == 'EXPIRED') {
        return bad('Izin toilet sudah habis');
      }

      final existingProof = permit['proof_scanned_at']?.toString().trim() ?? '';
      if (existingProof.isNotEmpty) {
        return ok({
          ..._mapToiletPermitRow(permit, now: now),
          'message': 'Bukti scan sudah tercatat',
        });
      }

      final nowIso = _formatWibIso(now);
      await _retryDbOperation(() async {
        db.execute(
          'UPDATE toilet_permit SET proof_scanned_by=?, proof_scanned_at=?, proof_status="SCANNED" WHERE id_karyawan=?',
          [username, nowIso, id],
        );
        return null;
      });

      final updated = Map<String, Object?>.from(
        db.select('SELECT * FROM toilet_permit WHERE id_karyawan=?', [
          id,
        ]).first,
      );
      _saveToiletPermitHistory(db, updated, now: now, permitState: 'ACTIVE');

      return ok({
        ..._mapToiletPermitRow(updated, now: now),
        'message': 'Izin toilet tervalidasi',
      });
    } catch (e) {
      return bad('Error: $e', code: 500);
    }
  });

  r.get('/toilet-permit/status/<id>', (Request req, String id) {
    final decodedId = _extractBarcodeInfo(Uri.decodeComponent(id));
    final rows = db.select('SELECT * FROM toilet_permit WHERE id_karyawan=?', [
      decodedId,
    ]);
    if (rows.isEmpty) {
      return Response.notFound(
        jsonEncode({'error': 'not found'}),
        headers: {'Content-Type': 'application/json'},
      );
    }
    return ok(_mapToiletPermitRow(Map<String, Object?>.from(rows.first)));
  });

  r.get('/status/<id>', (Request req, String id) {
    final decodedId = Uri.decodeComponent(id);
    final rows = db.select('SELECT * FROM log_pulang WHERE id_karyawan=?', [
      decodedId,
    ]);
    if (rows.isEmpty) {
      return Response.notFound(
        jsonEncode({'error': 'not found'}),
        headers: {'Content-Type': 'application/json'},
      );
    }
    return ok(Map<String, Object?>.from(rows.first));
  });

  Response logsHandler(Request req) {
    final rows = db.select('SELECT * FROM log_pulang ORDER BY rowid DESC');
    final list = rows
        .map(
          (r) => {
            'id_karyawan': r['id_karyawan'],
            'status_pengawas': r['status_pengawas'],
            'status_security': r['status_security'],
            'pengawas_scanned_by': r['pengawas_scanned_by'],
            'security_scanned_by': r['security_scanned_by'],
            'pengawas_scanned_at': r['pengawas_scanned_at'],
            'security_scanned_at': r['security_scanned_at'],
            'created_at': r['created_at'],
          },
        )
        .toList();
    return ok({'logs': list});
  }

  Response toiletPermitHandler(Request req) {
    final rows = db.select(
      'SELECT * FROM toilet_permit ORDER BY approved_at DESC',
    );
    final list = rows
        .map((r) => _mapToiletPermitRow(Map<String, Object?>.from(r)))
        .toList();
    return ok({'permits': list});
  }

  r.get('/logs', logsHandler);
  r.get('/logs/', logsHandler);
  r.get('/toilet-permits', toiletPermitHandler);
  r.get('/toilet-permits/', toiletPermitHandler);

  // Get logs by date.
  r.get('/logs-history/<tanggal>', (Request req, String tanggal) {
    try {
      final rows = db.select(
        'SELECT * FROM log_pulang_history WHERE tanggal = ? ORDER BY rowid DESC',
        [tanggal],
      );
      final list = rows
          .map(
            (r) => {
              'id_karyawan': r['id_karyawan'],
              'status_pengawas': r['status_pengawas'],
              'status_security': r['status_security'],
              'pengawas_scanned_by': r['pengawas_scanned_by'],
              'security_scanned_by': r['security_scanned_by'],
              'pengawas_scanned_at': r['pengawas_scanned_at'],
              'security_scanned_at': r['security_scanned_at'],
              'tanggal': r['tanggal'],
              'created_at': r['created_at'],
            },
          )
          .toList();
      return ok({'logs': list, 'tanggal': tanggal, 'total': list.length});
    } catch (e) {
      return bad('Error: $e', code: 500);
    }
  });

  r.get('/toilet-permits-history/<tanggal>', (Request req, String tanggal) {
    try {
      final rows = db.select(
        'SELECT * FROM toilet_permit_history WHERE tanggal = ? ORDER BY rowid DESC',
        [tanggal],
      );
      final list = rows
          .map((r) => _mapToiletPermitHistoryRow(Map<String, Object?>.from(r)))
          .toList();
      return ok({'permits': list, 'tanggal': tanggal, 'total': list.length});
    } catch (e) {
      return bad('Error: $e', code: 500);
    }
  });

  // Get all unique dates in history.
  r.get('/dates-history', (Request req) {
    try {
      final rows = db.select(
        'SELECT DISTINCT tanggal FROM log_pulang_history ORDER BY tanggal DESC',
      );
      final dates = rows.map((r) => r['tanggal']).toList();
      return ok({'dates': dates});
    } catch (e) {
      return bad('Error: $e', code: 500);
    }
  });

  // Daily reset endpoint - clears current day logs but keeps history.
  r.post('/daily-reset', (Request req) async {
    try {
      final result = await performDailyReset(db);
      if (result['success'] == true) {
        return ok({
          'message': result['message'],
          'tanggal': result['tanggal'],
          'cleared': result['moved'],
          'cleared_toilet_permits': result['moved_toilet_permits'],
          'timestamp': result['timestamp'],
        });
      }
      return bad(result['error'].toString(), code: 500);
    } catch (e) {
      return bad('Error: $e', code: 500);
    }
  });

  // CRUD Log Endpoints.
  r.post('/logs', (Request req) async {
    try {
      final body = jsonDecode(await req.readAsString());
      var id = body['id_karyawan']?.toString().trim();
      final pengawas = body['status_pengawas']?.toString().trim() ?? 'PENDING';
      final security = body['status_security']?.toString().trim() ?? 'PENDING';

      if (id == null || id.isEmpty) return bad('id_karyawan wajib');
      id = _extractBarcodeInfo(id);

      db.execute(
        'INSERT INTO log_pulang(id_karyawan, status_pengawas, status_security) VALUES(?, ?, ?) '
        'ON CONFLICT(id_karyawan) DO UPDATE SET status_pengawas=?, status_security=?',
        [id, pengawas, security, pengawas, security],
      );
      saveToHistory(id, pengawas, security);

      final row = db.select('SELECT * FROM log_pulang WHERE id_karyawan=?', [
        id,
      ]).first;
      return ok(Map<String, Object?>.from(row));
    } catch (e) {
      return bad('Error: $e', code: 500);
    }
  });

  r.get('/logs/<id>', (Request req, String id) {
    final decodedId = Uri.decodeComponent(id);
    final rows = db.select('SELECT * FROM log_pulang WHERE id_karyawan=?', [
      decodedId,
    ]);
    if (rows.isEmpty) return bad('Log tidak ditemukan', code: 404);
    return ok(Map<String, Object?>.from(rows.first));
  });

  r.put('/logs/<id>', (Request req, String id) async {
    try {
      final decodedId = Uri.decodeComponent(id);
      final body = jsonDecode(await req.readAsString());
      final pengawas = body['status_pengawas']?.toString().trim() ?? 'PENDING';
      final security = body['status_security']?.toString().trim() ?? 'PENDING';

      db.execute(
        'UPDATE log_pulang SET status_pengawas=?, status_security=? WHERE id_karyawan=?',
        [pengawas, security, decodedId],
      );
      saveToHistory(decodedId, pengawas, security);

      final rows = db.select('SELECT * FROM log_pulang WHERE id_karyawan=?', [
        decodedId,
      ]);
      if (rows.isEmpty) return bad('Log tidak ditemukan', code: 404);
      return ok(Map<String, Object?>.from(rows.first));
    } catch (e) {
      return bad('Error: $e', code: 500);
    }
  });

  r.delete('/logs/<id>', (Request req, String id) async {
    try {
      final decodedId = Uri.decodeComponent(id);
      final rows = db.select('SELECT * FROM log_pulang WHERE id_karyawan=?', [
        decodedId,
      ]);
      if (rows.isEmpty) return bad('Log tidak ditemukan', code: 404);

      db.execute('DELETE FROM log_pulang WHERE id_karyawan=?', [decodedId]);
      return ok({'message': 'Log berhasil dihapus', 'id_karyawan': decodedId});
    } catch (e) {
      return bad('Error: $e', code: 500);
    }
  });

  // Admin Endpoints.
  r.post('/admin/login', (Request req) async {
    try {
      final body = jsonDecode(await req.readAsString());
      final username = body['username']?.toString().trim();
      final password = body['password']?.toString().trim();

      if (username == null || username.isEmpty) {
        return bad('Username wajib diisi');
      }
      if (password == null || password.isEmpty) {
        return bad('Password wajib diisi');
      }

      if (username == 'admin' && password == 'admin123') {
        final token = 'admin_token_${DateTime.now().millisecondsSinceEpoch}';
        return ok({
          'message': 'Admin login berhasil',
          'token': token,
          'username': 'admin',
          'role': 'admin',
        });
      }

      return bad('Username atau password salah', code: 401);
    } catch (e) {
      return bad('Error: $e', code: 500);
    }
  });

  r.get('/admin/users', (Request req) {
    try {
      final rows = db.select(
        'SELECT id, username, role, created_at FROM users ORDER BY id DESC',
      );
      return ok({'users': rows});
    } catch (e) {
      return bad('Error: $e', code: 500);
    }
  });

  r.post('/admin/users', (Request req) async {
    try {
      final body = jsonDecode(await req.readAsString());
      final username = body['username']?.toString().trim();
      final password = body['password']?.toString().trim();
      final role = body['role']?.toString().trim();

      if (username == null || username.isEmpty) {
        return bad('Username wajib diisi');
      }
      if (password == null || password.isEmpty) {
        return bad('Password wajib diisi');
      }
      if (role == null || role.isEmpty) return bad('Role wajib diisi');
      if (role != 'pengawas' && role != 'security') {
        return bad('Role hanya bisa pengawas atau security');
      }

      db.execute(
        'INSERT INTO users(username, password, role) VALUES(?, ?, ?)',
        [username, password, role],
      );

      final rows = db.select(
        'SELECT id, username, role, created_at FROM users WHERE username=?',
        [username],
      );
      return ok(Map<String, Object?>.from(rows.first));
    } catch (e) {
      if (e.toString().contains('UNIQUE constraint failed')) {
        return bad('Username sudah terdaftar');
      }
      return bad('Error: $e', code: 500);
    }
  });

  r.put('/admin/users/<id>', (Request req, String id) async {
    try {
      final body = jsonDecode(await req.readAsString());
      final password = body['password']?.toString().trim();
      final role = body['role']?.toString().trim();

      if (password == null || password.isEmpty) {
        return bad('Password wajib diisi');
      }
      if (role == null || role.isEmpty) return bad('Role wajib diisi');
      if (role != 'pengawas' && role != 'security') {
        return bad('Role hanya bisa pengawas atau security');
      }

      db.execute('UPDATE users SET password=?, role=? WHERE id=?', [
        password,
        role,
        id,
      ]);

      final rows = db.select(
        'SELECT id, username, role, created_at FROM users WHERE id=?',
        [id],
      );

      if (rows.isEmpty) return bad('User tidak ditemukan', code: 404);
      return ok(Map<String, Object?>.from(rows.first));
    } catch (e) {
      return bad('Error: $e', code: 500);
    }
  });

  r.delete('/admin/users/<id>', (Request req, String id) async {
    try {
      final rows = db.select('SELECT username FROM users WHERE id=?', [id]);
      if (rows.isEmpty) return bad('User tidak ditemukan', code: 404);

      final username = rows.first['username'];
      db.execute('DELETE FROM users WHERE id=?', [id]);

      return ok({
        'message': 'User berhasil dihapus',
        'id': id,
        'username': username,
      });
    } catch (e) {
      return bad('Error: $e', code: 500);
    }
  });

  r.post('/admin/clear-logs', (Request req) async {
    try {
      final deletedCount =
          db.select('SELECT COUNT(*) as count FROM log_pulang').first['count']
              as int;
      final deletedPermitCount =
          db
                  .select('SELECT COUNT(*) as count FROM toilet_permit')
                  .first['count']
              as int;

      db.execute('DELETE FROM log_pulang');
      db.execute('DELETE FROM toilet_permit');

      return ok({
        'message': 'Semua log aktif berhasil dihapus',
        'deleted_count': deletedCount,
        'deleted_toilet_permits': deletedPermitCount,
        'history_preserved': true,
      });
    } catch (e) {
      return bad('Error: $e', code: 500);
    }
  });

  r.post('/admin/clear-all-data', (Request req) async {
    try {
      final logCount =
          db.select('SELECT COUNT(*) as count FROM log_pulang').first['count']
              as int;
      final historyCount =
          db
                  .select('SELECT COUNT(*) as count FROM log_pulang_history')
                  .first['count']
              as int;
      final permitCount =
          db
                  .select('SELECT COUNT(*) as count FROM toilet_permit')
                  .first['count']
              as int;
      final permitHistoryCount =
          db
                  .select('SELECT COUNT(*) as count FROM toilet_permit_history')
                  .first['count']
              as int;

      db.execute('DELETE FROM log_pulang');
      db.execute('DELETE FROM log_pulang_history');
      db.execute('DELETE FROM toilet_permit');
      db.execute('DELETE FROM toilet_permit_history');

      return ok({
        'message': 'Semua log dan history berhasil dihapus',
        'deleted_logs': logCount,
        'deleted_history': historyCount,
        'deleted_toilet_permits': permitCount,
        'deleted_toilet_permit_history': permitHistoryCount,
      });
    } catch (e) {
      return bad('Error: $e', code: 500);
    }
  });

  return r;
}
