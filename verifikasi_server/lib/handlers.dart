import 'dart:convert';

import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';
import 'package:sqlite3/sqlite3.dart';

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

  // Helper function to save to history
  void _saveToHistory(String idKaryawan, String statusPengawas, String statusSecurity) {
    final today = DateTime.now();
    final tanggal = '${today.year}-${today.month.toString().padLeft(2, '0')}-${today.day.toString().padLeft(2, '0')}';
    db.execute(
      'INSERT INTO log_pulang_history(id_karyawan, status_pengawas, status_security, tanggal) VALUES(?, ?, ?, ?)',
      [idKaryawan, statusPengawas, statusSecurity, tanggal],
    );
  }

  r.post('/scan-pengawas', (Request req) async {
    final body = jsonDecode(await req.readAsString());
    final id = body['id_karyawan']?.toString().trim();
    if (id == null || id.isEmpty) return bad('id_karyawan wajib');
    db.execute(
      'INSERT INTO log_pulang(id_karyawan, status_pengawas, status_security) VALUES(?, "ACC", "PENDING") '
      'ON CONFLICT(id_karyawan) DO UPDATE SET status_pengawas="ACC";',
      [id],
    );
    _saveToHistory(id, 'ACC', 'PENDING');
    final row = db.select('SELECT * FROM log_pulang WHERE id_karyawan=?', [id]).first;
    return ok(row);
  });

  r.post('/scan-security', (Request req) async {
    final body = jsonDecode(await req.readAsString());
    final id = body['id_karyawan']?.toString().trim();
    if (id == null || id.isEmpty) return bad('id_karyawan wajib');
    final rows = db.select('SELECT status_pengawas, status_security FROM log_pulang WHERE id_karyawan=?', [id]);
    if (rows.isEmpty) return bad('Belum ada ACC pengawas');
    final row = rows.first;
    if (row['status_pengawas'] != 'ACC') return bad('Pengawas belum ACC');
    db.execute('UPDATE log_pulang SET status_security="ACC" WHERE id_karyawan=?', [id]);
    _saveToHistory(id, 'ACC', 'ACC');
    final updated = db.select('SELECT * FROM log_pulang WHERE id_karyawan=?', [id]).first;
    return ok(updated);
  });

  r.get('/status/<id>', (Request req, String id) {
    final rows = db.select('SELECT * FROM log_pulang WHERE id_karyawan=?', [id]);
    if (rows.isEmpty) {
      return Response.notFound(jsonEncode({'error': 'not found'}),
          headers: {'Content-Type': 'application/json'});
    }
    return ok(rows.first);
  });

  Response logsHandler(Request req) {
    final rows = db.select('SELECT * FROM log_pulang ORDER BY id_karyawan ASC');
    final list = rows
        .map((r) => {
              'id_karyawan': r['id_karyawan'],
              'status_pengawas': r['status_pengawas'],
              'status_security': r['status_security'],
            })
        .toList();
    return ok({'logs': list});
  }

  r.get('/logs', logsHandler);
  r.get('/logs/', logsHandler); // handle trailing slash

  // Get logs by date
  r.get('/logs-history/<tanggal>', (Request req, String tanggal) {
    try {
      final rows = db.select(
        'SELECT * FROM log_pulang_history WHERE tanggal = ? ORDER BY id_karyawan ASC',
        [tanggal],
      );
      final list = rows
          .map((r) => {
                'id_karyawan': r['id_karyawan'],
                'status_pengawas': r['status_pengawas'],
                'status_security': r['status_security'],
                'tanggal': r['tanggal'],
              })
          .toList();
      return ok({'logs': list, 'tanggal': tanggal, 'total': list.length});
    } catch (e) {
      return bad('Error: $e', code: 500);
    }
  });

  // Get all unique dates in history
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

  // Daily reset endpoint - clears current day logs but keeps history
  r.post('/daily-reset', (Request req) async {
    try {
      final today = DateTime.now();
      final tanggal = '${today.year}-${today.month.toString().padLeft(2, '0')}-${today.day.toString().padLeft(2, '0')}';

      // First, move all current logs to history
      final currentLogs = db.select('SELECT * FROM log_pulang');
      for (final log in currentLogs) {
        final id = log['id_karyawan'];
        final pengawas = log['status_pengawas'];
        final security = log['status_security'];
        _saveToHistory(id, pengawas, security);
      }

      // Clear current logs table
      db.execute('DELETE FROM log_pulang');

      return ok({'message': 'Daily reset completed', 'tanggal': tanggal, 'cleared': currentLogs.length});
    } catch (e) {
      return bad('Error: $e', code: 500);
    }
  });

  return r;
}
