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
      pengawas_scanned_at DATETIME,
      security_scanned_at DATETIME,
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
      pengawas_scanned_at DATETIME,
      security_scanned_at DATETIME,
      tanggal DATE NOT NULL,
      created_at DATETIME DEFAULT CURRENT_TIMESTAMP
    );
  ''');

  // Add index for faster date queries
  db.execute('''
    CREATE INDEX IF NOT EXISTS idx_tanggal ON log_pulang_history(tanggal);
  ''');

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
      created_at DATETIME DEFAULT CURRENT_TIMESTAMP
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
      tanggal DATE NOT NULL,
      created_at DATETIME DEFAULT CURRENT_TIMESTAMP
    );
  ''');

  db.execute('''
    CREATE INDEX IF NOT EXISTS idx_toilet_permit_history_tanggal
    ON toilet_permit_history(tanggal);
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
    db.execute(
      'ALTER TABLE log_pulang ADD COLUMN pengawas_scanned_at DATETIME;',
    );
  } catch (_) {
    // Column already exists
  }

  try {
    db.execute(
      'ALTER TABLE log_pulang ADD COLUMN security_scanned_at DATETIME;',
    );
  } catch (_) {
    // Column already exists
  }

  try {
    db.execute(
      'ALTER TABLE log_pulang_history ADD COLUMN pengawas_scanned_by TEXT;',
    );
  } catch (_) {
    // Column already exists
  }

  try {
    db.execute(
      'ALTER TABLE log_pulang_history ADD COLUMN security_scanned_by TEXT;',
    );
  } catch (_) {
    // Column already exists
  }

  try {
    db.execute(
      'ALTER TABLE log_pulang_history ADD COLUMN pengawas_scanned_at DATETIME;',
    );
  } catch (_) {
    // Column already exists
  }

  try {
    db.execute(
      'ALTER TABLE log_pulang_history ADD COLUMN security_scanned_at DATETIME;',
    );
  } catch (_) {
    // Column already exists
  }

  try {
    db.execute(
      'ALTER TABLE toilet_permit ADD COLUMN duration_minutes INTEGER;',
    );
  } catch (_) {
    // Column already exists
  }

  try {
    db.execute('ALTER TABLE toilet_permit ADD COLUMN approved_by TEXT;');
  } catch (_) {
    // Column already exists
  }

  try {
    db.execute('ALTER TABLE toilet_permit ADD COLUMN approved_at DATETIME;');
  } catch (_) {
    // Column already exists
  }

  try {
    db.execute('ALTER TABLE toilet_permit ADD COLUMN expires_at DATETIME;');
  } catch (_) {
    // Column already exists
  }

  try {
    db.execute('ALTER TABLE toilet_permit ADD COLUMN proof_scanned_by TEXT;');
  } catch (_) {
    // Column already exists
  }

  try {
    db.execute(
      'ALTER TABLE toilet_permit ADD COLUMN proof_scanned_at DATETIME;',
    );
  } catch (_) {
    // Column already exists
  }

  try {
    db.execute(
      'ALTER TABLE toilet_permit ADD COLUMN proof_status TEXT DEFAULT "PENDING";',
    );
  } catch (_) {
    // Column already exists
  }

  try {
    db.execute(
      'ALTER TABLE toilet_permit_history ADD COLUMN duration_minutes INTEGER;',
    );
  } catch (_) {
    // Column already exists
  }

  try {
    db.execute(
      'ALTER TABLE toilet_permit_history ADD COLUMN approved_by TEXT;',
    );
  } catch (_) {
    // Column already exists
  }

  try {
    db.execute(
      'ALTER TABLE toilet_permit_history ADD COLUMN approved_at DATETIME;',
    );
  } catch (_) {
    // Column already exists
  }

  try {
    db.execute(
      'ALTER TABLE toilet_permit_history ADD COLUMN expires_at DATETIME;',
    );
  } catch (_) {
    // Column already exists
  }

  try {
    db.execute(
      'ALTER TABLE toilet_permit_history ADD COLUMN proof_scanned_by TEXT;',
    );
  } catch (_) {
    // Column already exists
  }

  try {
    db.execute(
      'ALTER TABLE toilet_permit_history ADD COLUMN proof_scanned_at DATETIME;',
    );
  } catch (_) {
    // Column already exists
  }

  try {
    db.execute(
      'ALTER TABLE toilet_permit_history ADD COLUMN proof_status TEXT DEFAULT "PENDING";',
    );
  } catch (_) {
    // Column already exists
  }

  try {
    db.execute(
      'ALTER TABLE toilet_permit_history ADD COLUMN permit_state TEXT DEFAULT "ACTIVE";',
    );
  } catch (_) {
    // Column already exists
  }

  // Backfill timestamps for existing data
  db.execute(
    'UPDATE log_pulang SET pengawas_scanned_at = COALESCE(pengawas_scanned_at, created_at) WHERE status_pengawas = "ACC";',
  );
  db.execute(
    'UPDATE log_pulang SET security_scanned_at = COALESCE(security_scanned_at, created_at) WHERE status_security = "ACC";',
  );
  db.execute(
    'UPDATE toilet_permit SET duration_minutes = COALESCE(duration_minutes, 10);',
  );
  db.execute(
    'UPDATE toilet_permit SET proof_status = COALESCE(proof_status, "PENDING");',
  );
  db.execute(
    'UPDATE toilet_permit_history SET duration_minutes = COALESCE(duration_minutes, 10);',
  );
  db.execute(
    'UPDATE toilet_permit_history SET proof_status = COALESCE(proof_status, "PENDING");',
  );
  db.execute(
    'UPDATE toilet_permit_history SET permit_state = COALESCE(permit_state, "ACTIVE");',
  );

  // Create default users if they don't exist
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

  return db;
}
