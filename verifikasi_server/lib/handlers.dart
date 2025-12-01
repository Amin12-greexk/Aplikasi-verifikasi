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

  r.post('/scan-pengawas', (Request req) async {
    final body = jsonDecode(await req.readAsString());
    final id = body['id_karyawan']?.toString().trim();
    if (id == null || id.isEmpty) return bad('id_karyawan wajib');
    db.execute(
      'INSERT INTO log_pulang(id_karyawan, status_pengawas, status_security) VALUES(?, "ACC", "PENDING") '
      'ON CONFLICT(id_karyawan) DO UPDATE SET status_pengawas="ACC";',
      [id],
    );
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

  return r;
}
