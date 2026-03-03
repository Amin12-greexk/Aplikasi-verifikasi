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

/// Performs the daily reset operation.
/// Moves all current logs to history and clears the log_pulang table.
Future<Map<String, dynamic>> performDailyReset(Database db) async {
  try {
    final today = DateTime.now();
    final tanggal =
        '${today.year}-${today.month.toString().padLeft(2, '0')}-${today.day.toString().padLeft(2, '0')}';

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

        db.execute('DELETE FROM log_pulang');
        db.execute('COMMIT');

        stdout.writeln(
          '[DAILY RESET] Reset completed at ${DateTime.now().toIso8601String()}',
        );
        stdout.writeln(
          '[DAILY RESET] Moved $movedCount logs to history for date: $tanggal',
        );

        return {
          'success': true,
          'message': 'Daily reset completed',
          'tanggal': tanggal,
          'moved': movedCount,
          'timestamp': DateTime.now().toIso8601String(),
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
    final now = DateTime.now();

    final nextMidnight = DateTime(now.year, now.month, now.day + 1, 0, 0, 0);

    final duration = nextMidnight.difference(now);

    stdout.writeln(
      '[SCHEDULER] Daily reset scheduled for: ${nextMidnight.toIso8601String()}',
    );
    stdout.writeln(
      '[SCHEDULER] Time until next reset: ${duration.inHours}h ${duration.inMinutes % 60}m ${duration.inSeconds % 60}s',
    );

    _dailyResetTimer = Timer(duration, () async {
      stdout.writeln('[SCHEDULER] Triggering automatic daily reset at 00:00');

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

  // Helper function to save to history.
  void saveToHistory(
    String idKaryawan,
    String statusPengawas,
    String statusSecurity, [
    String? pengawasBy,
    String? securityBy,
    String? pengawasAt,
    String? securityAt,
  ]) {
    final today = DateTime.now();
    final nowIso = DateTime.now().toIso8601String();
    final tanggal =
        '${today.year}-${today.month.toString().padLeft(2, '0')}-${today.day.toString().padLeft(2, '0')}';
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
        final nowIso = DateTime.now().toIso8601String();
        db.execute(
          'INSERT INTO log_pulang(id_karyawan, status_pengawas, status_security, pengawas_scanned_by, pengawas_scanned_at) VALUES(?, "ACC", "PENDING", ?, ?) '
          'ON CONFLICT(id_karyawan) DO UPDATE SET status_pengawas="ACC", pengawas_scanned_by=?, pengawas_scanned_at=?;',
          [id, username, nowIso, username, nowIso],
        );
        return null;
      });

      final nowIso = DateTime.now().toIso8601String();
      saveToHistory(id, 'ACC', 'PENDING', username, null, nowIso, null);
      final row = db.select('SELECT * FROM log_pulang WHERE id_karyawan=?', [
        id,
      ]).first;
      return ok(row);
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
      final rows = db.select(
        'SELECT status_pengawas, status_security FROM log_pulang WHERE id_karyawan=?',
        [id],
      );
      if (rows.isEmpty) return bad('Belum ada ACC pengawas');
      final row = rows.first;
      if (row['status_pengawas'] != 'ACC') return bad('Pengawas belum ACC');

      final nowIso = DateTime.now().toIso8601String();
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
      return ok(updated);
    } catch (e) {
      return bad('Error: $e', code: 500);
    }
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
    return ok(rows.first);
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

  r.get('/logs', logsHandler);
  r.get('/logs/', logsHandler);

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
      return ok(row);
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
    return ok(rows.first);
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
      return ok(rows.first);
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
      return ok(rows.first);
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
      return ok(rows.first);
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
      db.execute('DELETE FROM log_pulang');
      return ok({
        'message': 'Semua log pulang berhasil dihapus',
        'deleted_count': deletedCount,
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

      db.execute('DELETE FROM log_pulang');
      db.execute('DELETE FROM log_pulang_history');

      return ok({
        'message': 'Semua log dan history berhasil dihapus',
        'deleted_logs': logCount,
        'deleted_history': historyCount,
      });
    } catch (e) {
      return bad('Error: $e', code: 500);
    }
  });

  return r;
}
