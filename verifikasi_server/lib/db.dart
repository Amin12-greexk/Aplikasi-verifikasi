import 'package:sqlite3/sqlite3.dart';

Future<Database> initDb(String path) async {
  final db = sqlite3.open(path);

  // Create users table for authentication
  db.execute('''
    CREATE TABLE IF NOT EXISTS users (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      username TEXT UNIQUE NOT NULL,
      password TEXT NOT NULL,
      role TEXT NOT NULL CHECK(role IN ('pengawas', 'security')),
      created_at DATETIME DEFAULT CURRENT_TIMESTAMP
    );
  ''');

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

  // Create default users if they don't exist
  try {
    db.execute(
      'INSERT INTO users(username, password, role) VALUES(?, ?, ?)',
      ['pengawas', 'pengawas123', 'pengawas'],
    );
  } catch (_) {}

  try {
    db.execute(
      'INSERT INTO users(username, password, role) VALUES(?, ?, ?)',
      ['security', 'security123', 'security'],
    );
  } catch (_) {}

  return db;
}
