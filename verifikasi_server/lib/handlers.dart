import 'dart:async';
import 'dart:convert';

import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';
import 'package:sqlite3/sqlite3.dart';

String _generateToken(String username, String role) {
  return 'token_${username}_${role}_${DateTime.now().millisecondsSinceEpoch}';
}

String _cleanBarcodeValue(String value) {
  var cleaned = value.trim();
  while (cleaned.startsWith("'") ||
      cleaned.startsWith('"') ||
      cleaned.startsWith('`')) {
    cleaned = cleaned.substring(1).trimLeft();
  }
  while (cleaned.endsWith("'") ||
      cleaned.endsWith('"') ||
      cleaned.endsWith('`')) {
    cleaned = cleaned.substring(0, cleaned.length - 1).trimRight();
  }
  return cleaned;
}

void _putBarcodeField(Map<String, String> info, String key, String value) {
  final cleanedValue = _cleanBarcodeValue(value);
  if (cleanedValue.isEmpty) return;

  final normalizedKey = key.trim().toLowerCase();
  if (normalizedKey == 'pin') {
    info['PIN'] = cleanedValue;
  } else if (normalizedKey == 'nama' || normalizedKey == 'name') {
    info['Nama'] = cleanedValue;
  } else if (normalizedKey == 'nik') {
    info['NIK'] = cleanedValue;
  } else if (normalizedKey == 'bagian' || normalizedKey == 'department') {
    info['Bagian'] = cleanedValue;
  }
}

Map<String, String> _parseBarcodeInfo(String fullBarcode) {
  final info = <String, String>{};
  final raw = fullBarcode.trim();
  if (raw.isEmpty) return info;

  try {
    if (raw.contains(',') && !raw.contains(':')) {
      final parts = raw.split(',').map(_cleanBarcodeValue).toList();
      if (parts.length >= 2) {
        var pinIndex = -1;
        if (RegExp(r'^[0-9]+$').hasMatch(parts[0])) {
          pinIndex = 0;
        } else if (RegExp(r'^[0-9]+$').hasMatch(parts[1])) {
          pinIndex = 1;
        }

        if (pinIndex != -1) {
          final pin = parts[pinIndex];
          final nama = parts[pinIndex == 0 ? 1 : 0];
          if (pin.isEmpty || nama.isEmpty) return <String, String>{};

          info['PIN'] = pin;
          info['Nama'] = nama;
          if (parts.length >= 3 && parts[2].isNotEmpty) {
            info['NIK'] = parts[2];
          }
          if (parts.length >= 10) {
            info['Bagian'] = parts[9];
          } else if (parts.length >= 4) {
            info['Bagian'] = parts[3];
          }
          return info;
        }
      }
    }

    final parts = raw
        .split(RegExp(r'[|\r\n]+'))
        .map((part) => part.trim())
        .toList();
    for (final part in parts) {
      final separatorIndex = part.indexOf(':');
      if (separatorIndex <= 0) continue;

      final key = part.substring(0, separatorIndex).trim();
      final value = part.substring(separatorIndex + 1).trim();
      _putBarcodeField(info, key, value);
    }
  } catch (_) {
    return <String, String>{};
  }

  final pin = info['PIN']?.trim() ?? '';
  final nik = info['NIK']?.trim() ?? '';
  final nama = info['Nama']?.trim() ?? '';
  if (nama.isEmpty || (pin.isEmpty && nik.isEmpty)) {
    return <String, String>{};
  }

  return info;
}

String _extractBarcodeInfo(String fullBarcode) {
  final raw = fullBarcode.trim();
  if (raw.isEmpty) return '';

  try {
    // 1. Cek format CSV (N, NAMA, NIK, ...) atau (NAMA, N, NIK, ...)
    if (raw.contains(',') && !raw.contains(':')) {
      final info = _parseBarcodeInfo(raw);
      final pin = info['PIN']?.trim() ?? '';
      final nik = info['NIK']?.trim() ?? '';
      final nama = info['Nama']?.trim() ?? '';
      final bagian = info['Bagian']?.trim() ?? '';

      if (pin.isNotEmpty || nik.isNotEmpty) {
        final parts = <String>[];
        if (nik.isNotEmpty) {
          parts.add('NIK: $nik');
        } else {
          parts.add('PIN: $pin');
        }
        if (nama.isNotEmpty) parts.add('Nama: $nama');
        if (bagian.isNotEmpty) parts.add('Bagian: $bagian');
        return parts.join(' | ');
      }
    }

    // 2. ULTRA-ROBUST REGEX PARSING
    // Menangani teks yang "smashed" (menyambung tanpa spasi/newline)
    final patterns = {
      'PIN': RegExp(
        r'PIN\s*:\s*(.*?)(?=NAMA|NIK|BAGIAN|ALAMAT|ALAMAT|$)',
        caseSensitive: false,
        dotAll: true,
      ),
      'Nama': RegExp(
        r'NAMA\s*:\s*(.*?)(?=PIN|NIK|BAGIAN|ALAMAT|ALAMAT|$)',
        caseSensitive: false,
        dotAll: true,
      ),
      'NIK': RegExp(
        r'NIK\s*:\s*(.*?)(?=PIN|NAMA|BAGIAN|ALAMAT|ALAMAT|$)',
        caseSensitive: false,
        dotAll: true,
      ),
      'Bagian': RegExp(
        r'BAGIAN\s*:\s*(.*?)(?=PIN|NAMA|NIK|ALAMAT|ALAMAT|$)',
        caseSensitive: false,
        dotAll: true,
      ),
    };

    final info = <String, String>{};
    bool foundAny = false;

    patterns.forEach((key, regex) {
      final match = regex.firstMatch(raw);
      if (match != null) {
        var val = match.group(1)?.trim() ?? '';
        // Bersihkan trailing delimiters jika ada (misal pipe atau koma di akhir value)
        val = val.replaceAll(RegExp(r'[|,\r\n]+$'), '').trim();
        if (val.isNotEmpty) {
          info[key] = val;
          foundAny = true;
        }
      }
    });

    if (foundAny) {
      final pin = info['PIN'] ?? '';
      final nik = info['NIK'] ?? '';
      final nama = info['Nama'] ?? '';
      final bagian = info['Bagian'] ?? '';

      final parts = <String>[];
      if (nik.isNotEmpty) {
        parts.add('NIK: $nik');
      } else if (pin.isNotEmpty) {
        parts.add('PIN: $pin');
      }

      if (parts.isNotEmpty) {
        if (nama.isNotEmpty) parts.add('Nama: $nama');
        if (bagian.isNotEmpty) parts.add('Bagian: $bagian');
        return parts.join(' | ');
      }
    }
  } catch (e) {
    print('[Scanner] Error parsing barcode: $e');
  }

  // 3. FALLBACK: "Accept all kind of string"
  // Kembalikan data mentah yang sudah dibersihkan dari karakter kontrol
  // Gunakan spasi tunggal untuk menggantikan newline/tab agar konsisten antar scanner
  return raw
      .replaceAll(RegExp(r'[\r\n\t]+'), ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
}

String _extractIdentityLookupKey(String value) {
  final raw = value.trim();
  if (raw.isEmpty) return '';

  final nikMatch = RegExp(
    r'NIK\s*:\s*([0-9]{8,30})',
    caseSensitive: false,
  ).firstMatch(raw);
  if (nikMatch != null) {
    return 'NIK: ${nikMatch.group(1)}';
  }

  final pinMatch = RegExp(
    r'PIN\s*:\s*([0-9]{3,20})',
    caseSensitive: false,
  ).firstMatch(raw);
  if (pinMatch != null) {
    return 'PIN: ${pinMatch.group(1)}';
  }

  final parsed = _extractBarcodeInfo(raw);
  final firstPart = parsed.split('|').first.trim();
  final separatorIndex = firstPart.indexOf(':');
  if (separatorIndex <= 0) return '';

  final key = firstPart.substring(0, separatorIndex).trim().toUpperCase();
  if (key != 'NIK' && key != 'PIN') return '';

  final idValue = firstPart.substring(separatorIndex + 1).trim();
  if (idValue.isEmpty) return '';
  return '$key: $idValue';
}

Map<String, Object?>? _findToiletPermitByLookupId(
  Database db,
  String lookupId,
) {
  final cleanedLookup = lookupId.trim();
  if (cleanedLookup.isEmpty) return null;

  final exactRows = db.select(
    'SELECT * FROM toilet_permit WHERE id_karyawan=? ORDER BY approved_at DESC LIMIT 1',
    [cleanedLookup],
  );
  if (exactRows.isNotEmpty) {
    return Map<String, Object?>.from(exactRows.first);
  }

  final identityKey = _extractIdentityLookupKey(cleanedLookup);
  if (identityKey.isEmpty) return null;

  final fallbackRows = db.select(
    'SELECT * FROM toilet_permit WHERE id_karyawan=? OR id_karyawan LIKE ? ORDER BY approved_at DESC LIMIT 1',
    [identityKey, '$identityKey%'],
  );
  if (fallbackRows.isEmpty) return null;
  return Map<String, Object?>.from(fallbackRows.first);
}

/// Flexible lookup for log_pulang — mirrors _findToiletPermitByLookupId.
/// 1. Exact match on id_karyawan.
/// 2. Fallback: extract identity key (PIN/NIK) and search with exact + LIKE.
Map<String, Object?>? _findLogPulangByLookupId(
  Database db,
  String lookupId,
) {
  final cleaned = lookupId.trim();
  if (cleaned.isEmpty) return null;

  // 1. Exact match
  final exactRows = db.select(
    'SELECT * FROM log_pulang WHERE id_karyawan=? LIMIT 1',
    [cleaned],
  );
  if (exactRows.isNotEmpty) {
    return Map<String, Object?>.from(exactRows.first);
  }

  // 2. Fallback: identity key (PIN/NIK) based search
  final identityKey = _extractIdentityLookupKey(cleaned);
  if (identityKey.isEmpty) return null;

  final fallbackRows = db.select(
    'SELECT * FROM log_pulang WHERE id_karyawan=? OR id_karyawan LIKE ? '
    'ORDER BY COALESCE(pengawas_scanned_at, created_at) DESC LIMIT 1',
    [identityKey, '$identityKey%'],
  );
  if (fallbackRows.isEmpty) return null;
  return Map<String, Object?>.from(fallbackRows.first);
}

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

String _formatDate(DateTime value) {
  final wib = _toWib(value);
  return '${wib.year}-${_twoDigits(wib.month)}-${_twoDigits(wib.day)}';
}

DateTime? _tryParseDateTime(Object? raw) {
  final value = raw?.toString().trim();
  if (value == null || value.isEmpty) return null;
  try {
    final normalized = value.replaceFirst(' ', 'T');
    if (normalized.endsWith('Z') ||
        RegExp(r'[+-]\d{2}:\d{2}$').hasMatch(normalized)) {
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

int _normalizePositiveInt(Object? raw, {int fallback = 5}) {
  final parsed = int.tryParse(raw?.toString() ?? '');
  if (parsed == null) return fallback;
  return parsed < 1 ? 1 : parsed;
}

bool _hasToiletTimerStarted(Object? proofStatusRaw, Object? expiresAtRaw) {
  final proofStatus = proofStatusRaw?.toString().trim().toUpperCase() ?? '';
  if (proofStatus != 'SCANNED') return false;
  return _tryParseDateTime(expiresAtRaw) != null;
}

String _resolveToiletPermitState(
  Object? expiresAtRaw, {
  Object? proofStatusRaw,
  DateTime? now,
}) {
  if (!_hasToiletTimerStarted(proofStatusRaw, expiresAtRaw)) {
    return 'WAITING_SECURITY';
  }
  final expiresAt = _tryParseDateTime(expiresAtRaw);
  if (expiresAt == null) return 'WAITING_SECURITY';
  final reference = now ?? _nowUtc();
  return expiresAt.isAfter(reference) ? 'ACTIVE' : 'EXPIRED';
}

int _remainingPermitSeconds(
  Object? expiresAtRaw, {
  Object? proofStatusRaw,
  Object? durationMinutesRaw,
  DateTime? now,
}) {
  if (!_hasToiletTimerStarted(proofStatusRaw, expiresAtRaw)) {
    return _normalizeDurationMinutes(durationMinutesRaw) * 60;
  }
  final expiresAt = _tryParseDateTime(expiresAtRaw);
  if (expiresAt == null) return 0;
  final reference = now ?? _nowUtc();
  final remaining = expiresAt.difference(reference).inSeconds;
  return remaining > 0 ? remaining : 0;
}

int _countTodayToiletPermitApprovals(
  Database db,
  String idKaryawan, {
  DateTime? now,
}) {
  final reference = now ?? _nowUtc();
  final result = db.select(
    'SELECT COUNT(*) AS count FROM toilet_permit_history '
    'WHERE id_karyawan=? AND tanggal=? AND approved_at IS NOT NULL',
    [idKaryawan, _formatDate(reference)],
  );
  if (result.isEmpty) return 0;
  return int.tryParse(result.first['count']?.toString() ?? '0') ?? 0;
}

int _countActivePermitsInRoom(Database db, int? roomId, {DateTime? now}) {
  if (roomId == null) return 0;
  final reference = now ?? _nowUtc();
  final rows = db.select(
    'SELECT expires_at, proof_status FROM toilet_permit WHERE room_id = ?',
    [roomId],
  );
  int count = 0;
  for (final row in rows) {
    final state = _resolveToiletPermitState(
      row['expires_at'],
      proofStatusRaw: row['proof_status'],
      now: reference,
    );
    if (state == 'ACTIVE' || state == 'WAITING_SECURITY') count++;
  }
  return count;
}

Map<String, Object?>? _getRoomById(Database db, int? roomId) {
  if (roomId == null) return null;
  final rows = db.select('SELECT * FROM rooms WHERE id = ?', [roomId]);
  return rows.isEmpty ? null : Map<String, Object?>.from(rows.first);
}

Map<String, Object?> _mapToiletPermitRow(
  Map<String, Object?> row, {
  DateTime? now,
}) {
  final reference = now ?? _nowUtc();
  return {
    'id_karyawan': row['id_karyawan'],
    'duration_minutes': _normalizeDurationMinutes(row['duration_minutes']),
    'approved_by': row['approved_by'],
    'approved_at': row['approved_at'],
    'expires_at': row['expires_at'],
    'proof_scanned_by': row['proof_scanned_by'],
    'proof_scanned_at': row['proof_scanned_at'],
    'proof_status': row['proof_status']?.toString() ?? 'PENDING',
    'permit_state': _resolveToiletPermitState(
      row['expires_at'],
      proofStatusRaw: row['proof_status'],
      now: reference,
    ),
    'room_id': row['room_id'],
    'is_bypass': row['is_bypass'] == 1,
    'bypass_reason': row['bypass_reason'],
    'remaining_seconds': _remainingPermitSeconds(
      row['expires_at'],
      proofStatusRaw: row['proof_status'],
      durationMinutesRaw: row['duration_minutes'],
      now: reference,
    ),
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
    'INSERT INTO toilet_permit_history(id_karyawan, duration_minutes, approved_by, approved_at, expires_at, proof_scanned_by, proof_scanned_at, proof_status, permit_state, room_id, is_bypass, bypass_reason, tanggal) VALUES(?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)',
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
          _resolveToiletPermitState(
            permitRow['expires_at'],
            proofStatusRaw: permitRow['proof_status'],
            now: reference,
          ),
      permitRow['room_id'],
      (permitRow['is_bypass'] == true || permitRow['is_bypass'] == 1) ? 1 : 0,
      permitRow['bypass_reason'],
      _formatDate(reference),
    ],
  );
}

Future<Map<String, dynamic>> performDailyReset(Database db) async {
  try {
    final today = _nowUtc();
    final tanggal = _formatDate(today);
    return await _retryDbOperation(() async {
      db.execute('BEGIN TRANSACTION');
      try {
        final currentLogs = db.select('SELECT * FROM log_pulang');
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
        }
        db.execute('DELETE FROM log_pulang');
        db.execute('DELETE FROM toilet_permit');
        db.execute('COMMIT');
        return {
          'success': true,
          'message': 'Daily reset completed',
          'tanggal': tanggal,
          'moved': currentLogs.length,
          'timestamp': _formatWibIso(_nowUtc()),
        };
      } catch (e) {
        db.execute('ROLLBACK');
        rethrow;
      }
    });
  } catch (e) {
    return {
      'success': false,
      'message': 'Daily reset failed',
      'error': e.toString(),
    };
  }
}

Timer? _dailyResetTimer;
void startDailyResetScheduler(Database db) {
  _dailyResetTimer?.cancel();
  void scheduleNextReset() {
    final nowUtc = _nowUtc();
    final nextMidnightUtc = _nextWibMidnightUtc(nowUtc);
    final duration = nextMidnightUtc.difference(nowUtc);
    _dailyResetTimer = Timer(duration, () async {
      await performDailyReset(db);
      scheduleNextReset();
    });
  }

  scheduleNextReset();
}

void stopDailyResetScheduler() {
  _dailyResetTimer?.cancel();
  _dailyResetTimer = null;
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

  void saveLogHistory(
    String idKaryawan,
    String statusPengawas,
    String statusSecurity, {
    String? pengawasBy,
    String? securityBy,
    String? pengawasAt,
    String? securityAt,
  }) {
    final today = _nowUtc();
    final nowIso = _formatWibIso(today);
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
        _formatDate(today),
      ],
    );
  }

  r.post('/auth/login', (Request req) async {
    try {
      final body = jsonDecode(await req.readAsString());
      final u = body['username']?.toString().trim();
      final p = body['password']?.toString().trim();
      if (u == null || u.isEmpty || p == null || p.isEmpty) {
        return bad('Username/Password wajib');
      }
      final rows = db.select(
        'SELECT id, username, role, room_id FROM users WHERE username = ? AND password = ?',
        [u, p],
      );
      if (rows.isEmpty) return bad('Username atau password salah', code: 401);
      final user = rows.first;
      final roomId = user['room_id'] as int?;
      String? roomName;
      if (roomId != null) {
        final room = _getRoomById(db, roomId);
        roomName = room?['name']?.toString();
      }
      return ok({
        'token': _generateToken(u, user['role']?.toString() ?? ''),
        'username': user['username'],
        'role': user['role'],
        'room_id': roomId,
        'room_name': roomName,
      });
    } catch (e) {
      return bad('Error: $e', code: 500);
    }
  });

  r.post('/toilet-permit/approve', (Request req) async {
    try {
      final body = jsonDecode(await req.readAsString());
      final rawId = body['id_karyawan']?.toString().trim() ?? '';
      var id = _extractBarcodeInfo(rawId);
      if (id.isEmpty) id = rawId;

      final username = body['username']?.toString().trim();
      final duration = _normalizeDurationMinutes(body['duration_minutes']);
      final isBypass = body['is_bypass'] == true;
      final bypassReason = body['bypass_reason']?.toString().trim();

      if (id.isEmpty) return bad('Data QR kosong');
      if (username == null || username.isEmpty) return bad('Username wajib');

      final supervisor = db.select(
        'SELECT room_id FROM users WHERE username = ?',
        [username],
      );
      if (supervisor.isEmpty) return bad('Pengawas tidak ditemukan');
      final roomId = supervisor.first['room_id'] as int?;
      if (roomId == null) return bad('Pengawas belum ditugaskan ke ruangan');

      final room = _getRoomById(db, roomId);
      if (room == null || room['is_active'] == 0) {
        return bad('Ruangan tidak aktif');
      }

      if (isBypass && (bypassReason == null || bypassReason.isEmpty)) {
        return bad('Alasan bypass wajib diisi');
      }

      final now = _nowUtc();
      final nowIso = _formatWibIso(now);
      Response? limitResponse;
      await _retryDbOperation(() async {
        db.execute('BEGIN IMMEDIATE TRANSACTION');
        try {
          final dailyLimit = _normalizePositiveInt(room['daily_mitra_limit']);
          final todayCount = _countTodayToiletPermitApprovals(db, id, now: now);
          if (todayCount >= dailyLimit && !isBypass) {
            limitResponse = Response(
              403,
              body: jsonEncode({
                'error': 'LIMIT_EXCEEDED',
                'message':
                    'Mitra sudah ke toilet $todayCount kali hari ini. Gunakan bypass jika darurat.',
              }),
              headers: {'Content-Type': 'application/json'},
            );
            db.execute('ROLLBACK');
            return;
          }

          final maxConcurrent = _normalizePositiveInt(
            room['max_concurrent_permits'],
          );
          final activeCount = _countActivePermitsInRoom(db, roomId, now: now);
          if (activeCount >= maxConcurrent) {
            limitResponse = Response(
              403,
              body: jsonEncode({
                'error': 'QUOTA_FULL',
                'message':
                    'Kuota ruangan penuh ($activeCount/$maxConcurrent aktif).',
              }),
              headers: {'Content-Type': 'application/json'},
            );
            db.execute('ROLLBACK');
            return;
          }

          db.execute(
            'INSERT INTO toilet_permit(id_karyawan, duration_minutes, approved_by, approved_at, proof_status, room_id, is_bypass, bypass_reason) VALUES(?, ?, ?, ?, "PENDING", ?, ?, ?) '
            'ON CONFLICT(id_karyawan) DO UPDATE SET duration_minutes=?, approved_by=?, approved_at=?, expires_at=NULL, proof_scanned_by=NULL, proof_scanned_at=NULL, proof_status="PENDING", room_id=?, is_bypass=?, bypass_reason=?;',
            [
              id,
              duration,
              username,
              nowIso,
              roomId,
              isBypass ? 1 : 0,
              bypassReason,
              duration,
              username,
              nowIso,
              roomId,
              isBypass ? 1 : 0,
              bypassReason,
            ],
          );
          _saveToiletPermitHistory(db, {
            'id_karyawan': id,
            'duration_minutes': duration,
            'approved_by': username,
            'approved_at': nowIso,
            'proof_status': 'PENDING',
            'room_id': roomId,
            'is_bypass': isBypass,
            'bypass_reason': bypassReason,
          }, now: now);
          db.execute('COMMIT');
        } catch (e) {
          db.execute('ROLLBACK');
          rethrow;
        }
      });
      if (limitResponse != null) return limitResponse!;

      final row = Map<String, Object?>.from(
        db.select('SELECT * FROM toilet_permit WHERE id_karyawan=?', [
          id,
        ]).first,
      );
      return ok(_mapToiletPermitRow(row, now: now));
    } catch (e) {
      return bad('Error: $e', code: 500);
    }
  });

  r.post('/toilet-permit/proof-scan', (Request req) async {
    try {
      final body = jsonDecode(await req.readAsString());
      final rawId = body['id_karyawan']?.toString().trim() ?? '';
      var id = _extractBarcodeInfo(rawId);
      if (id.isEmpty) id = rawId;
      final username = body['username']?.toString().trim();

      print('[Server] Received Toilet-Proof-Scan: raw="$rawId" -> parsed="$id"');

      if (id.isEmpty) return bad('Data QR kosong');
      if (username == null || username.isEmpty) return bad('Username wajib');
      final permit = _findToiletPermitByLookupId(db, id);
      if (permit == null) return bad('Belum ada izin toilet dari pengawas');
      final storedId = permit['id_karyawan']?.toString().trim() ?? id;
      if (permit['proof_scanned_at'] != null) {
        return ok(_mapToiletPermitRow(permit));
      }

      final now = _nowUtc();
      final nowIso = _formatWibIso(now);
      final expiresAtIso = _formatWibIso(
        now.add(
          Duration(
            minutes: _normalizeDurationMinutes(permit['duration_minutes']),
          ),
        ),
      );

      await _retryDbOperation(() async {
        db.execute(
          'UPDATE toilet_permit SET proof_scanned_by=?, proof_scanned_at=?, expires_at=?, proof_status="SCANNED" WHERE id_karyawan=?',
          [username, nowIso, expiresAtIso, storedId],
        );
        db.execute(
          'UPDATE toilet_permit_history SET proof_scanned_by=?, proof_scanned_at=?, expires_at=?, proof_status="SCANNED", permit_state="ACTIVE" WHERE id_karyawan=? AND approved_at=?',
          [username, nowIso, expiresAtIso, storedId, permit['approved_at']],
        );
      });
      final updated = _findToiletPermitByLookupId(db, storedId) ?? permit;
      return ok(_mapToiletPermitRow(updated, now: now));
    } catch (e) {
      return bad('Error: $e', code: 500);
    }
  });

  r.post('/toilet-permit/return', (Request req) async {
    try {
      final body = jsonDecode(await req.readAsString());
      final rawId = body['id_karyawan']?.toString().trim() ?? '';
      var id = _extractBarcodeInfo(rawId);
      if (id.isEmpty) id = rawId;

      final username = body['username']?.toString().trim();
      if (id.isEmpty) return bad('Data QR kosong');
      if (username == null || username.isEmpty) return bad('Username wajib');
      final permit = _findToiletPermitByLookupId(db, id);
      if (permit == null) {
        return bad('Izin toilet aktif tidak ditemukan', code: 404);
      }
      final storedId = permit['id_karyawan']?.toString().trim() ?? id;
      await _retryDbOperation(() async {
        db.execute('BEGIN IMMEDIATE TRANSACTION');
        try {
          db.execute(
            'UPDATE toilet_permit_history SET permit_state="RETURNED" WHERE id_karyawan=? AND approved_at=?',
            [storedId, permit['approved_at']],
          );
          db.execute('DELETE FROM toilet_permit WHERE id_karyawan=?', [
            storedId,
          ]);
          db.execute('COMMIT');
        } catch (e) {
          db.execute('ROLLBACK');
          rethrow;
        }
      });

      return ok({
        'message': 'Mitra ditandai sudah kembali',
        'id_karyawan': storedId,
        'returned_by': username,
        'returned_at': _formatWibIso(_nowUtc()),
      });
    } catch (e) {
      return bad('Error: $e', code: 500);
    }
  });

  r.post('/toilet-permit/security-close', (Request req) async {
    try {
      final body = jsonDecode(await req.readAsString());
      final rawId = body['id_karyawan']?.toString().trim() ?? '';
      var id = _extractBarcodeInfo(rawId);
      if (id.isEmpty) id = rawId;
      final username = body['username']?.toString().trim();
      if (id.isEmpty) return bad('Data izin toilet kosong');
      if (username == null || username.isEmpty) return bad('Username wajib');

      final userRows = db.select('SELECT role FROM users WHERE username = ?', [
        username,
      ]);
      if (userRows.isEmpty) return bad('Security tidak ditemukan', code: 404);
      final role = userRows.first['role']?.toString().toLowerCase();
      if (role != 'security') {
        return bad('Akses hanya untuk security', code: 403);
      }
      final permit = _findToiletPermitByLookupId(db, id);
      if (permit == null) {
        return bad('Izin toilet aktif tidak ditemukan', code: 404);
      }
      final storedId = permit['id_karyawan']?.toString().trim() ?? id;
      final proofStatus = permit['proof_status']?.toString().toUpperCase();
      final proofScannedAt = _tryParseDateTime(permit['proof_scanned_at']);
      if (proofStatus != 'SCANNED' || proofScannedAt == null) {
        return bad('Izin belum masuk status security');
      }

      final elapsed = _nowUtc().difference(proofScannedAt);
      if (elapsed < const Duration(minutes: 5)) {
        return bad(
          'Izin baru bisa ditutup setelah 5 menit dari scan security',
          code: 403,
        );
      }

      await _retryDbOperation(() async {
        db.execute('BEGIN IMMEDIATE TRANSACTION');
        try {
          db.execute(
            'UPDATE toilet_permit_history SET permit_state="RETURNED" WHERE id_karyawan=? AND approved_at=?',
            [storedId, permit['approved_at']],
          );
          db.execute('DELETE FROM toilet_permit WHERE id_karyawan=?', [
            storedId,
          ]);
          db.execute('COMMIT');
        } catch (e) {
          db.execute('ROLLBACK');
          rethrow;
        }
      });

      return ok({
        'message': 'Izin toilet aktif berhasil ditutup security',
        'id_karyawan': storedId,
        'closed_by': username,
        'closed_at': _formatWibIso(_nowUtc()),
      });
    } catch (e) {
      return bad('Error: $e', code: 500);
    }
  });

  r.get('/toilet-permit/status/<id>', (Request req, String rawId) {
    try {
      final id = _extractBarcodeInfo(Uri.decodeComponent(rawId).trim());
      if (id.isEmpty) return bad('QR tidak dikenal');
      final permit = _findToiletPermitByLookupId(db, id);
      if (permit == null) {
        return bad('Belum ada izin toilet dari pengawas', code: 404);
      }
      return ok(_mapToiletPermitRow(permit));
    } catch (e) {
      return bad('Error: $e', code: 500);
    }
  });

  r.get('/toilet-permits-alerts', (Request req) {
    try {
      final now = _nowUtc();
      final alerts = db
          .select('SELECT * FROM toilet_permit ORDER BY approved_at DESC')
          .map(
            (r) => _mapToiletPermitRow(Map<String, Object?>.from(r), now: now),
          )
          .where((permit) => permit['permit_state'] == 'EXPIRED')
          .toList();
      return ok({'alerts': alerts});
    } catch (e) {
      return bad('Error: $e', code: 500);
    }
  });

  r.get('/admin/rooms', (Request req) {
    try {
      return ok({
        'rooms': db.select('SELECT * FROM rooms ORDER BY name ASC').toList(),
      });
    } catch (e) {
      return bad('Error: $e', code: 500);
    }
  });

  r.post('/admin/rooms', (Request req) async {
    try {
      final body = jsonDecode(await req.readAsString());
      final name = body['name']?.toString().trim();
      if (name == null || name.isEmpty) return bad('Nama wajib');
      final maxConcurrent = _normalizePositiveInt(
        body['max_concurrent_permits'],
      );
      final dailyLimit = _normalizePositiveInt(body['daily_mitra_limit']);
      final isActive = body['is_active'] == false || body['is_active'] == 0
          ? 0
          : 1;
      db.execute(
        'INSERT INTO rooms(name, max_concurrent_permits, daily_mitra_limit, is_active) VALUES(?, ?, ?, ?)',
        [name, maxConcurrent, dailyLimit, isActive],
      );
      return ok({'message': 'Ruangan berhasil dibuat'});
    } catch (e) {
      return bad('Error: $e', code: 500);
    }
  });

  r.put('/admin/rooms/<id>', (Request req, String id) async {
    try {
      final body = jsonDecode(await req.readAsString());
      final maxConcurrent = body.containsKey('max_concurrent_permits')
          ? _normalizePositiveInt(body['max_concurrent_permits'])
          : null;
      final dailyLimit = body.containsKey('daily_mitra_limit')
          ? _normalizePositiveInt(body['daily_mitra_limit'])
          : null;
      db.execute(
        'UPDATE rooms SET name=COALESCE(?, name), max_concurrent_permits=COALESCE(?, max_concurrent_permits), daily_mitra_limit=COALESCE(?, daily_mitra_limit), is_active=COALESCE(?, is_active) WHERE id=?',
        [body['name'], maxConcurrent, dailyLimit, body['is_active'], id],
      );
      return ok({'message': 'Ruangan berhasil diupdate'});
    } catch (e) {
      return bad('Error: $e', code: 500);
    }
  });

  r.delete('/admin/rooms/<id>', (Request req, String id) async {
    try {
      final roomId = int.tryParse(id);
      if (roomId == null) return bad('ID ruangan tidak valid');
      final exists = db.select('SELECT id FROM rooms WHERE id=?', [roomId]);
      if (exists.isEmpty) return bad('Ruangan tidak ditemukan', code: 404);
      await _retryDbOperation(() async {
        db.execute('BEGIN IMMEDIATE TRANSACTION');
        try {
          db.execute('UPDATE users SET room_id=NULL WHERE room_id=?', [roomId]);
          db.execute('UPDATE toilet_permit SET room_id=NULL WHERE room_id=?', [
            roomId,
          ]);
          db.execute(
            'UPDATE toilet_permit_history SET room_id=NULL WHERE room_id=?',
            [roomId],
          );
          db.execute('DELETE FROM rooms WHERE id=?', [roomId]);
          db.execute('COMMIT');
        } catch (e) {
          db.execute('ROLLBACK');
          rethrow;
        }
      });
      return ok({'message': 'Ruangan berhasil dihapus'});
    } catch (e) {
      return bad('Error: $e', code: 500);
    }
  });

  r.get('/admin/users', (Request req) {
    try {
      final rows = db.select(
        'SELECT u.*, r.name as room_name FROM users u LEFT JOIN rooms r ON u.room_id = r.id ORDER BY u.id DESC',
      );
      return ok({'users': rows.toList()});
    } catch (e) {
      return bad('Error: $e', code: 500);
    }
  });

  r.post('/admin/users', (Request req) async {
    try {
      final body = jsonDecode(await req.readAsString());
      db.execute(
        'INSERT INTO users(username, password, role, room_id) VALUES(?, ?, ?, ?)',
        [body['username'], body['password'], body['role'], body['room_id']],
      );
      return ok({'message': 'User berhasil dibuat'});
    } catch (e) {
      return bad('Error: $e', code: 500);
    }
  });

  r.put('/admin/users/<id>', (Request req, String id) async {
    try {
      final body = jsonDecode(await req.readAsString());
      db.execute(
        'UPDATE users SET password=COALESCE(?, password), role=COALESCE(?, role), room_id=COALESCE(?, room_id) WHERE id=?',
        [body['password'], body['role'], body['room_id'], id],
      );
      return ok({'message': 'User berhasil diupdate'});
    } catch (e) {
      return bad('Error: $e', code: 500);
    }
  });

  r.delete('/admin/users/<id>', (Request req, String id) async {
    try {
      final rows = db.select('SELECT username FROM users WHERE id=?', [id]);
      if (rows.isEmpty) return bad('User tidak ditemukan', code: 404);
      db.execute('DELETE FROM users WHERE id=?', [id]);
      return ok({
        'message': 'User berhasil dihapus',
        'id': id,
        'username': rows.first['username'],
      });
    } catch (e) {
      return bad('Error: $e', code: 500);
    }
  });

  r.post('/admin/login', (Request req) async {
    try {
      final body = jsonDecode(await req.readAsString());
      final u = body['username']?.toString().trim();
      final p = body['password']?.toString().trim();
      final rows = db.select(
        'SELECT role FROM users WHERE username=? AND password=? AND role="admin"',
        [u, p],
      );
      if (rows.isEmpty && !(u == 'admin' && p == 'admin123')) {
        return bad('Akses ditolak', code: 401);
      }
      return ok({
        'token': 'admin_${DateTime.now().millisecondsSinceEpoch}',
        'role': 'admin',
      });
    } catch (e) {
      return bad('Error: $e', code: 500);
    }
  });

  r.get(
    '/logs',
    (Request req) => ok({
      'logs': db
          .select(
            'SELECT * FROM log_pulang ORDER BY COALESCE(security_scanned_at, pengawas_scanned_at, created_at) DESC',
          )
          .toList(),
    }),
  );
  r.get(
    '/toilet-permits',
    (Request req) => ok({
      'permits': db
          .select('SELECT * FROM toilet_permit ORDER BY approved_at DESC')
          .map((r) => _mapToiletPermitRow(Map<String, Object?>.from(r)))
          .toList(),
    }),
  );

  r.get('/status/<id>', (Request req, String rawId) {
    final id = _extractBarcodeInfo(Uri.decodeComponent(rawId).trim());
    if (id.isEmpty) return bad('QR tidak dikenal');
    final found = _findLogPulangByLookupId(db, id);
    if (found == null) return bad('Log tidak ditemukan', code: 404);
    return ok(found);
  });

  r.post('/logs', (Request req) async {
    try {
      final body = jsonDecode(await req.readAsString());
      final id = _extractBarcodeInfo(
        body['id_karyawan']?.toString().trim() ?? '',
      );
      if (id.isEmpty) return bad('QR tidak dikenal');
      final pengawas = body['status_pengawas']?.toString().trim() ?? 'PENDING';
      final security = body['status_security']?.toString().trim() ?? 'PENDING';
      db.execute(
        'INSERT INTO log_pulang(id_karyawan, status_pengawas, status_security) VALUES(?, ?, ?) ON CONFLICT(id_karyawan) DO UPDATE SET status_pengawas=?, status_security=?',
        [id, pengawas, security, pengawas, security],
      );
      saveLogHistory(id, pengawas, security);
      return ok(
        Map<String, Object?>.from(
          db.select('SELECT * FROM log_pulang WHERE id_karyawan=?', [id]).first,
        ),
      );
    } catch (e) {
      return bad('Error: $e', code: 500);
    }
  });

  r.get('/logs/<id>', (Request req, String rawId) {
    final id = _extractBarcodeInfo(Uri.decodeComponent(rawId).trim());
    if (id.isEmpty) return bad('QR tidak dikenal');
    final found = _findLogPulangByLookupId(db, id);
    if (found == null) return bad('Log tidak ditemukan', code: 404);
    return ok(found);
  });

  r.put('/logs/<id>', (Request req, String rawId) async {
    try {
      final id = _extractBarcodeInfo(Uri.decodeComponent(rawId).trim());
      if (id.isEmpty) return bad('QR tidak dikenal');
      final found = _findLogPulangByLookupId(db, id);
      if (found == null) return bad('Log tidak ditemukan', code: 404);
      final storedId = found['id_karyawan']?.toString().trim() ?? id;
      final body = jsonDecode(await req.readAsString());
      final pengawas = body['status_pengawas']?.toString().trim() ?? 'PENDING';
      final security = body['status_security']?.toString().trim() ?? 'PENDING';
      db.execute(
        'UPDATE log_pulang SET status_pengawas=?, status_security=? WHERE id_karyawan=?',
        [pengawas, security, storedId],
      );
      saveLogHistory(storedId, pengawas, security);
      final rows = db.select('SELECT * FROM log_pulang WHERE id_karyawan=?', [
        storedId,
      ]);
      if (rows.isEmpty) return bad('Log tidak ditemukan', code: 404);
      return ok(Map<String, Object?>.from(rows.first));
    } catch (e) {
      return bad('Error: $e', code: 500);
    }
  });

  r.delete('/logs/<id>', (Request req, String rawId) {
    try {
      final id = _extractBarcodeInfo(Uri.decodeComponent(rawId).trim());
      if (id.isEmpty) return bad('QR tidak dikenal');
      final found = _findLogPulangByLookupId(db, id);
      if (found == null) return bad('Log tidak ditemukan', code: 404);
      final storedId = found['id_karyawan']?.toString().trim() ?? id;
      db.execute('DELETE FROM log_pulang WHERE id_karyawan=?', [storedId]);
      return ok({'message': 'Log berhasil dihapus', 'id_karyawan': storedId});
    } catch (e) {
      return bad('Error: $e', code: 500);
    }
  });

  // ── TOILET PERMITS CRUD ───────────────────────────────────────────────────

  r.get('/toilet-permits/<id>', (Request req, String rawId) {
    final id = _extractBarcodeInfo(Uri.decodeComponent(rawId).trim());
    if (id.isEmpty) return bad('QR tidak dikenal');
    final rows = db.select('SELECT * FROM toilet_permit WHERE id_karyawan=?', [
      id,
    ]);
    if (rows.isEmpty) return bad('Izin tidak ditemukan', code: 404);
    return ok(_mapToiletPermitRow(Map<String, Object?>.from(rows.first)));
  });

  r.put('/toilet-permits/<id>', (Request req, String rawId) async {
    try {
      final id = _extractBarcodeInfo(Uri.decodeComponent(rawId).trim());
      if (id.isEmpty) return bad('QR tidak dikenal');
      final body = jsonDecode(await req.readAsString());

      final rows = db.select(
        'SELECT * FROM toilet_permit WHERE id_karyawan=?',
        [id],
      );
      if (rows.isEmpty) return bad('Izin tidak ditemukan', code: 404);

      final proofStatus =
          body['proof_status']?.toString().toUpperCase() ?? 'PENDING';
      final duration = _normalizeDurationMinutes(body['duration_minutes']);

      db.execute(
        'UPDATE toilet_permit SET proof_status=?, duration_minutes=? WHERE id_karyawan=?',
        [proofStatus, duration, id],
      );

      final updatedRows = db.select(
        'SELECT * FROM toilet_permit WHERE id_karyawan=?',
        [id],
      );
      final permit = Map<String, Object?>.from(updatedRows.first);

      _saveToiletPermitHistory(
        db,
        permit,
        permitState: proofStatus == 'SCANNED' ? 'ACTIVE' : 'PENDING',
      );

      return ok(_mapToiletPermitRow(permit));
    } catch (e) {
      return bad('Error: $e', code: 500);
    }
  });

  r.delete('/toilet-permits/<id>', (Request req, String rawId) {
    try {
      final id = _extractBarcodeInfo(Uri.decodeComponent(rawId).trim());
      if (id.isEmpty) return bad('QR tidak dikenal');
      final rows = db.select(
        'SELECT * FROM toilet_permit WHERE id_karyawan=?',
        [id],
      );
      if (rows.isEmpty) return bad('Izin tidak ditemukan', code: 404);
      db.execute('DELETE FROM toilet_permit WHERE id_karyawan=?', [id]);
      return ok({'message': 'Izin toilet berhasil dihapus', 'id_karyawan': id});
    } catch (e) {
      return bad('Error: $e', code: 500);
    }
  });

  r.post('/scan-pengawas', (Request req) async {
    try {
      final body = jsonDecode(await req.readAsString());
      final rawId = body['id_karyawan']?.toString().trim() ?? '';
      var id = _extractBarcodeInfo(rawId);
      if (id.isEmpty) id = rawId;
      if (id.isEmpty) return bad('Data QR kosong');

      // Check if this identity already exists under a different stored key
      final existing = _findLogPulangByLookupId(db, id);
      final storedId = existing?['id_karyawan']?.toString().trim() ?? id;

      final nowIso = _formatWibIso(_nowUtc());
      await _retryDbOperation(() async {
        db.execute(
          'INSERT INTO log_pulang(id_karyawan, status_pengawas, status_security, pengawas_scanned_by, pengawas_scanned_at) '
          'VALUES(?, "ACC", "PENDING", ?, ?) '
          'ON CONFLICT(id_karyawan) DO UPDATE SET status_pengawas="ACC", pengawas_scanned_by=?, pengawas_scanned_at=?;',
          [storedId, body['username'], nowIso, body['username'], nowIso],
        );
      });
      return ok(
        Map<String, Object?>.from(
          db.select('SELECT * FROM log_pulang WHERE id_karyawan=?', [storedId]).first,
        ),
      );
    } catch (e) {
      return bad('Error: $e', code: 500);
    }
  });

  r.post('/scan-security', (Request req) async {
    try {
      final body = jsonDecode(await req.readAsString());
      final rawId = body['id_karyawan']?.toString().trim() ?? '';
      var id = _extractBarcodeInfo(rawId);
      if (id.isEmpty) id = rawId;

      print('[Server] Received Scan-Security: raw="$rawId" -> parsed="$id"');

      if (id.isEmpty) return bad('Data QR kosong');
      final nowIso = _formatWibIso(_nowUtc());

      // Flexible lookup: exact match + identity key fallback
      final current = _findLogPulangByLookupId(db, id);
      if (current == null) {
        return bad('Belum ada ACC pengawas untuk ID Card ini', code: 404);
      }

      // Use the stored id_karyawan from database for all subsequent operations
      final storedId = current['id_karyawan']?.toString().trim() ?? id;

      final statusPengawas = current['status_pengawas']?.toString().toUpperCase();
      if (statusPengawas != 'ACC') {
        return bad('Belum di-ACC Pengawas', code: 403);
      }

      final statusSecurity = current['status_security']?.toString().toUpperCase();
      if (statusSecurity == 'ACC') {
        current['message'] = 'Sudah di-scan Security';
        return ok(current);
      }

      await _retryDbOperation(() async {
        db.execute(
          'UPDATE log_pulang SET status_security="ACC", security_scanned_by=?, security_scanned_at=? WHERE id_karyawan=?',
          [body['username'], nowIso, storedId],
        );
      });
      final rows = db.select('SELECT * FROM log_pulang WHERE id_karyawan=?', [
        storedId,
      ]);
      final result = Map<String, Object?>.from(rows.first);
      result['message'] = 'Berhasil ACC security';
      return ok(result);
    } catch (e) {
      return bad('Error: $e', code: 500);
    }
  });

  r.get(
    '/dates-history',
    (Request req) => ok({
      'dates': db
          .select(
            'SELECT DISTINCT tanggal FROM log_pulang_history ORDER BY tanggal DESC',
          )
          .map((r) => r['tanggal'])
          .toList(),
    }),
  );
  r.get(
    '/logs-history/<tanggal>',
    (Request req, String t) => ok({
      'logs': db.select('SELECT * FROM log_pulang_history WHERE tanggal = ?', [
        t,
      ]).toList(),
    }),
  );
  r.get(
    '/toilet-permits-history/<tanggal>',
    (Request req, String t) => ok({
      'permits': db
          .select(
            'SELECT * FROM toilet_permit_history WHERE tanggal = ? ORDER BY approved_at DESC',
            [t],
          )
          .map((r) => _mapToiletPermitRow(Map<String, Object?>.from(r)))
          .toList(),
    }),
  );
  r.get(
    '/toilet-permits-dates-history',
    (Request req) => ok({
      'dates': db
          .select(
            'SELECT DISTINCT tanggal FROM toilet_permit_history ORDER BY tanggal DESC',
          )
          .map((r) => r['tanggal'])
          .toList(),
    }),
  );

  r.post('/daily-reset', (Request req) async {
    final result = await performDailyReset(db);
    if (result['success'] == true) return ok(result);
    return bad(result['error']?.toString() ?? 'Daily reset failed', code: 500);
  });

  r.post('/admin/clear-logs', (Request req) {
    try {
      final logCount =
          int.tryParse(
            db
                    .select('SELECT COUNT(*) AS count FROM log_pulang')
                    .first['count']
                    ?.toString() ??
                '0',
          ) ??
          0;
      final permitCount =
          int.tryParse(
            db
                    .select('SELECT COUNT(*) AS count FROM toilet_permit')
                    .first['count']
                    ?.toString() ??
                '0',
          ) ??
          0;
      db.execute('DELETE FROM log_pulang');
      db.execute('DELETE FROM toilet_permit');
      return ok({
        'message': 'Semua log aktif berhasil dihapus',
        'deleted_count': logCount,
        'deleted_toilet_permits': permitCount,
        'history_preserved': true,
      });
    } catch (e) {
      return bad('Error: $e', code: 500);
    }
  });

  r.post('/admin/clear-all-data', (Request req) {
    try {
      final logCount =
          int.tryParse(
            db
                    .select('SELECT COUNT(*) AS count FROM log_pulang')
                    .first['count']
                    ?.toString() ??
                '0',
          ) ??
          0;
      final historyCount =
          int.tryParse(
            db
                    .select('SELECT COUNT(*) AS count FROM log_pulang_history')
                    .first['count']
                    ?.toString() ??
                '0',
          ) ??
          0;
      final permitCount =
          int.tryParse(
            db
                    .select('SELECT COUNT(*) AS count FROM toilet_permit')
                    .first['count']
                    ?.toString() ??
                '0',
          ) ??
          0;
      final permitHistoryCount =
          int.tryParse(
            db
                    .select(
                      'SELECT COUNT(*) AS count FROM toilet_permit_history',
                    )
                    .first['count']
                    ?.toString() ??
                '0',
          ) ??
          0;
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
