import 'package:sqlite3/sqlite3.dart';

Future<Database> initDb(String path) async {
  final db = sqlite3.open(path);

  // Create main table
  db.execute('''
    CREATE TABLE IF NOT EXISTS log_pulang (
      id_karyawan TEXT PRIMARY KEY,
      status_pengawas TEXT NOT NULL DEFAULT 'PENDING',
      status_security TEXT NOT NULL DEFAULT 'PENDING',
      created_at DATETIME DEFAULT CURRENT_TIMESTAMP
    );
  ''');

  // Create log history table
  db.execute('''
    CREATE TABLE IF NOT EXISTS log_pulang_history (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      id_karyawan TEXT NOT NULL,
      status_pengawas TEXT NOT NULL,
      status_security TEXT NOT NULL,
      tanggal DATE NOT NULL,
      created_at DATETIME DEFAULT CURRENT_TIMESTAMP
    );
  ''');

  // Add index for faster date queries
  db.execute('''
    CREATE INDEX IF NOT EXISTS idx_tanggal ON log_pulang_history(tanggal);
  ''');

  return db;
}
