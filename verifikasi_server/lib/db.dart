import 'package:sqlite3/sqlite3.dart';

Future<Database> initDb(String path) async {
  final db = sqlite3.open(path);

  // Set busy timeout - wait up to 5 seconds if database is locked
  db.execute('PRAGMA busy_timeout = 5000;');

  // Enable WAL mode for better concurrency
  db.execute('PRAGMA journal_mode = WAL;');

  // ── ROOMS ─────────────────────────────────────────────────────────────────────
  db.execute('''
    CREATE TABLE IF NOT EXISTS rooms (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      name TEXT UNIQUE NOT NULL,
      max_concurrent_permits INTEGER NOT NULL DEFAULT 5,
      daily_mitra_limit INTEGER NOT NULL DEFAULT 5,
      is_active INTEGER NOT NULL DEFAULT 1,
      created_at DATETIME DEFAULT CURRENT_TIMESTAMP
    );
  ''');

  // ── USERS ─────────────────────────────────────────────────────────────────────
  db.execute('''
    CREATE TABLE IF NOT EXISTS users (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      username TEXT UNIQUE NOT NULL,
      password TEXT NOT NULL,
      role TEXT NOT NULL CHECK(role IN ('pengawas', 'security', 'manager', 'admin')),
      room_id INTEGER,
      created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
      FOREIGN KEY (room_id) REFERENCES rooms (id) ON DELETE SET NULL
    );
  ''');

  // ── LOG PULANG ────────────────────────────────────────────────────────────────
  db.execute('''
    CREATE TABLE IF NOT EXISTS log_pulang (
      id_karyawan TEXT PRIMARY KEY,
      status_pengawas TEXT NOT NULL DEFAULT 'PENDING',
      status_security TEXT NOT NULL DEFAULT 'PENDING',
      pengawas_scanned_by TEXT,
      security_scanned_by TEXT,
      pengawas_scanned_at DATETIME,
      security_scanned_at DATETIME,
      created_at DATETIME DEFAULT CURRENT_TIMESTAMP
    );
  ''');

  db.execute('''
    CREATE TABLE IF NOT EXISTS log_pulang_history (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      id_karyawan TEXT NOT NULL,
      status_pengawas TEXT NOT NULL,
      status_security TEXT NOT NULL,
      pengawas_scanned_by TEXT,
      security_scanned_by TEXT,
      pengawas_scanned_at DATETIME,
      security_scanned_at DATETIME,
      tanggal DATE NOT NULL,
      created_at DATETIME DEFAULT CURRENT_TIMESTAMP
    );
  ''');

  db.execute(
    'CREATE INDEX IF NOT EXISTS idx_tanggal ON log_pulang_history(tanggal);',
  );
  db.execute(
    'CREATE INDEX IF NOT EXISTS idx_log_pulang_history_id_karyawan ON log_pulang_history(id_karyawan);',
  );

  // ── TOILET PERMIT ─────────────────────────────────────────────────────────────
  db.execute('''
    CREATE TABLE IF NOT EXISTS toilet_permit (
      id_karyawan TEXT PRIMARY KEY,
      duration_minutes INTEGER NOT NULL DEFAULT 10,
      approved_by TEXT,
      approved_at DATETIME,
      expires_at DATETIME,
      proof_scanned_by TEXT,
      proof_scanned_at DATETIME,
      proof_status TEXT NOT NULL DEFAULT 'PENDING',
      room_id INTEGER,
      is_bypass INTEGER NOT NULL DEFAULT 0,
      bypass_reason TEXT,
      created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
      FOREIGN KEY (room_id) REFERENCES rooms (id) ON DELETE SET NULL
    );
  ''');

  db.execute('''
    CREATE TABLE IF NOT EXISTS toilet_permit_history (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      id_karyawan TEXT NOT NULL,
      duration_minutes INTEGER NOT NULL,
      approved_by TEXT,
      approved_at DATETIME,
      expires_at DATETIME,
      proof_scanned_by TEXT,
      proof_scanned_at DATETIME,
      proof_status TEXT NOT NULL,
      permit_state TEXT NOT NULL,
      room_id INTEGER,
      is_bypass INTEGER NOT NULL DEFAULT 0,
      bypass_reason TEXT,
      tanggal DATE NOT NULL,
      created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
      FOREIGN KEY (room_id) REFERENCES rooms (id) ON DELETE SET NULL
    );
  ''');

  db.execute(
    'CREATE INDEX IF NOT EXISTS idx_toilet_permit_history_tanggal ON toilet_permit_history(tanggal);',
  );

  // ── MIGRATIONS ────────────────────────────────────────────────────────────────
  try {
    db.execute(
      'ALTER TABLE users ADD COLUMN role TEXT CHECK(role IN ("pengawas", "security", "manager", "admin"));',
    );
  } catch (_) {}
  try {
    db.execute('ALTER TABLE users ADD COLUMN room_id INTEGER;');
  } catch (_) {}
  try {
    db.execute(
      'ALTER TABLE rooms ADD COLUMN max_concurrent_permits INTEGER DEFAULT 5;',
    );
  } catch (_) {}
  try {
    db.execute(
      'ALTER TABLE rooms ADD COLUMN daily_mitra_limit INTEGER DEFAULT 5;',
    );
  } catch (_) {}
  try {
    db.execute('ALTER TABLE rooms ADD COLUMN is_active INTEGER DEFAULT 1;');
  } catch (_) {}
  try {
    db.execute('ALTER TABLE toilet_permit ADD COLUMN room_id INTEGER;');
  } catch (_) {}
  try {
    db.execute(
      'ALTER TABLE toilet_permit ADD COLUMN is_bypass INTEGER DEFAULT 0;',
    );
  } catch (_) {}
  try {
    db.execute('ALTER TABLE toilet_permit ADD COLUMN bypass_reason TEXT;');
  } catch (_) {}
  try {
    db.execute('ALTER TABLE toilet_permit_history ADD COLUMN room_id INTEGER;');
  } catch (_) {}
  try {
    db.execute(
      'ALTER TABLE toilet_permit_history ADD COLUMN is_bypass INTEGER DEFAULT 0;',
    );
  } catch (_) {}
  try {
    db.execute(
      'ALTER TABLE toilet_permit_history ADD COLUMN bypass_reason TEXT;',
    );
  } catch (_) {}

  // Backfill
  db.execute(
    'UPDATE rooms SET max_concurrent_permits = COALESCE(max_concurrent_permits, 5);',
  );
  db.execute(
    'UPDATE rooms SET daily_mitra_limit = COALESCE(daily_mitra_limit, 5);',
  );
  db.execute('UPDATE rooms SET is_active = COALESCE(is_active, 1);');
  db.execute(
    'UPDATE toilet_permit SET duration_minutes = COALESCE(duration_minutes, 10);',
  );
  db.execute(
    'UPDATE toilet_permit SET proof_status = COALESCE(proof_status, "PENDING");',
  );

  // Default Users
  try {
    db.execute('INSERT INTO users(username, password, role) VALUES(?, ?, ?)', [
      'pengawas',
      'pengawas123',
      'pengawas',
    ]);
  } catch (_) {}
  try {
    db.execute('INSERT INTO users(username, password, role) VALUES(?, ?, ?)', [
      'security',
      'security123',
      'security',
    ]);
  } catch (_) {}
  try {
    db.execute('INSERT INTO users(username, password, role) VALUES(?, ?, ?)', [
      'admin',
      'admin123',
      'admin',
    ]);
  } catch (_) {}

  return db;
}
