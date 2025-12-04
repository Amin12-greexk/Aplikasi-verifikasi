import 'package:sqlite3/sqlite3.dart';

Future<Database> initDb(String path) async {
  final db = sqlite3.open(path);

  // Set busy timeout - wait up to 5 seconds if database is locked
  db.execute('PRAGMA busy_timeout = 5000;');

  // Enable WAL mode for better concurrency
  db.execute('PRAGMA journal_mode = WAL;');

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
      pengawas_scanned_by TEXT,
      security_scanned_by TEXT,
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
      pengawas_scanned_by TEXT,
      security_scanned_by TEXT,
      tanggal DATE NOT NULL,
      created_at DATETIME DEFAULT CURRENT_TIMESTAMP
    );
  ''');

  // Add index for faster date queries
  db.execute('''
    CREATE INDEX IF NOT EXISTS idx_tanggal ON log_pulang_history(tanggal);
  ''');

  // Migration: Add pengawas_scanned_by and security_scanned_by columns if they don't exist
  try {
    db.execute('ALTER TABLE log_pulang ADD COLUMN pengawas_scanned_by TEXT;');
  } catch (_) {
    // Column already exists
  }

  try {
    db.execute('ALTER TABLE log_pulang ADD COLUMN security_scanned_by TEXT;');
  } catch (_) {
    // Column already exists
  }

  try {
    db.execute('ALTER TABLE log_pulang_history ADD COLUMN pengawas_scanned_by TEXT;');
  } catch (_) {
    // Column already exists
  }

  try {
    db.execute('ALTER TABLE log_pulang_history ADD COLUMN security_scanned_by TEXT;');
  } catch (_) {
    // Column already exists
  }

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
