import 'package:sqlite3/sqlite3.dart';

Future<Database> initDb(String path) async {
  final db = sqlite3.open(path);
  db.execute('''
    CREATE TABLE IF NOT EXISTS log_pulang (
      id_karyawan TEXT PRIMARY KEY,
      status_pengawas TEXT NOT NULL DEFAULT 'PENDING',
      status_security TEXT NOT NULL DEFAULT 'PENDING'
    );
  ''');
  return db;
}
