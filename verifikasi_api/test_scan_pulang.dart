import 'dart:convert';
import 'dart:io';
import 'package:sqlite3/sqlite3.dart';
import 'lib/db.dart';
import 'lib/server.dart';

void main() async {
  print('=== Scan Pulang Continuous Integration Test ===\n');

  final dbFile = File('test_scan_pulang.db');
  if (dbFile.existsSync()) {
    dbFile.deleteSync();
  }

  print('[Test Setup] Initializing test database...');
  final db = await initDb('test_scan_pulang.db');
  print('✓ Database initialized successfully');

  final port = 9091;
  print('[Test Setup] Starting test server on port $port...');
  final server = await startServer(
    db: db,
    host: InternetAddress.loopbackIPv4,
    port: port,
  );
  print('✓ Server started at http://${server.address.address}:${server.port}\n');

  final client = HttpClient();

  Future<Map<String, dynamic>> post(String path, Map<String, dynamic> body) async {
    final req = await client.post('127.0.0.1', port, path);
    req.headers.contentType = ContentType.json;
    req.write(jsonEncode(body));
    final resp = await req.close();
    final respBody = await resp.transform(utf8.decoder).join();
    return {
      'statusCode': resp.statusCode,
      'body': jsonDecode(respBody),
    };
  }

  Future<Map<String, dynamic>> get(String path) async {
    final req = await client.get('127.0.0.1', port, path);
    final resp = await req.close();
    final respBody = await resp.transform(utf8.decoder).join();
    return {
      'statusCode': resp.statusCode,
      'body': jsonDecode(respBody),
    };
  }

  try {
    // ----------------------------------------------------
    // Scenario 1: Exact Match (Normal Flow)
    // ----------------------------------------------------
    print('[Scenario 1] Exact Match (Normal Flow)');
    final barcodeNormal = 'PIN: 111111 | Nama: Budi | NIK: 1111111111111111 | Bagian: IT';
    
    print('1. Pengawas scan barcode...');
    final pRes1 = await post('/scan-pengawas', {
      'id_karyawan': barcodeNormal,
      'username': 'pengawas1',
    });
    print('   Response: ${pRes1['statusCode']} - ${pRes1['body']}');
    if (pRes1['statusCode'] != 200) throw 'Failed pengawas scan';

    print('2. Security scan exact same barcode...');
    final sRes1 = await post('/scan-security', {
      'id_karyawan': barcodeNormal,
      'username': 'security1',
    });
    print('   Response: ${sRes1['statusCode']} - ${sRes1['body']}');
    if (sRes1['statusCode'] != 200) throw 'Failed security scan';
    if (sRes1['body']['status_security'] != 'ACC') throw 'Security status should be ACC';
    print('✓ Scenario 1 passed!\n');

    // ----------------------------------------------------
    // Scenario 2: Flexible Lookup (Continuous Scan with different formats - NIK)
    // ----------------------------------------------------
    print('[Scenario 2] Flexible Lookup (Continuous Scan with different formats - NIK)');
    final barcodePengawas = 'PIN: 222222 | Nama: Andi | NIK: 2222222222222222 | Bagian: QA';
    // Format scanned by security has different layout, casing, and spacing
    final barcodeSecurity = ' NIK : 2222222222222222 | NAMA : Andi | BAGIAN : QA ';

    print('1. Pengawas scan barcode...');
    final pRes2 = await post('/scan-pengawas', {
      'id_karyawan': barcodePengawas,
      'username': 'pengawas1',
    });
    print('   Response: ${pRes2['statusCode']} - ${pRes2['body']}');
    if (pRes2['statusCode'] != 200) throw 'Failed pengawas scan';

    print('2. Security scan DIFFERENT barcode format (but same NIK)...');
    final sRes2 = await post('/scan-security', {
      'id_karyawan': barcodeSecurity,
      'username': 'security1',
    });
    print('   Response: ${sRes2['statusCode']} - ${sRes2['body']}');
    if (sRes2['statusCode'] != 200) throw 'Failed security scan with flexible lookup';
    if (sRes2['body']['status_security'] != 'ACC') throw 'Security status should be ACC';
    print('✓ Scenario 2 passed!\n');

    // ----------------------------------------------------
    // Scenario 3: Flexible Lookup (Continuous Scan with different formats - PIN only)
    // ----------------------------------------------------
    print('[Scenario 3] Flexible Lookup (Continuous Scan with different formats - PIN only)');
    final pinOnlyPengawas = 'PIN: 333333 | Nama: Cici | Bagian: HR';
    final pinOnlySecurity = 'pin:333333';

    print('1. Pengawas scan PIN-only barcode...');
    final pRes3 = await post('/scan-pengawas', {
      'id_karyawan': pinOnlyPengawas,
      'username': 'pengawas1',
    });
    print('   Response: ${pRes3['statusCode']} - ${pRes3['body']}');
    if (pRes3['statusCode'] != 200) throw 'Failed pengawas scan';

    print('2. Security scan only the PIN...');
    final sRes3 = await post('/scan-security', {
      'id_karyawan': pinOnlySecurity,
      'username': 'security1',
    });
    print('   Response: ${sRes3['statusCode']} - ${sRes3['body']}');
    if (sRes3['statusCode'] != 200) throw 'Failed security scan with PIN-only flexible lookup';
    if (sRes3['body']['status_security'] != 'ACC') throw 'Security status should be ACC';
    print('✓ Scenario 3 passed!\n');

    // ----------------------------------------------------
    // Scenario 4: Get Status and Log endpoints
    // ----------------------------------------------------
    print('[Scenario 4] Status and Logs lookup using identity keys');
    
    // Status lookup by exact barcode
    final statRes1 = await get('/status/${Uri.encodeComponent(barcodePengawas)}');
    print('1. Lookup by exact barcode...');
    print('   Response: ${statRes1['statusCode']} - ${statRes1['body']}');
    if (statRes1['statusCode'] != 200) throw 'Failed status lookup';

    // Status lookup by identity key only
    final statRes2 = await get('/status/${Uri.encodeComponent('NIK: 2222222222222222')}');
    print('2. Lookup by identity key "NIK: 2222222222222222"...');
    print('   Response: ${statRes2['statusCode']} - ${statRes2['body']}');
    if (statRes2['statusCode'] != 200) throw 'Failed status lookup by identity key';

    // Logs lookup by identity key only
    final logRes = await get('/logs/${Uri.encodeComponent('NIK: 2222222222222222')}');
    print('3. Logs lookup by identity key "NIK: 2222222222222222"...');
    print('   Response: ${logRes['statusCode']} - ${logRes['body']}');
    if (logRes['statusCode'] != 200) throw 'Failed logs lookup by identity key';

    print('✓ Scenario 4 passed!\n');

    print('=== ALL INTEGRATION TESTS PASSED ===');
  } catch (e) {
    print('✗ TEST FAILED: $e');
    exitCode = 1;
  } finally {
    print('\n[Test Cleanup] Shutting down server...');
    await shutdownServer(server);
    db.dispose();
    if (dbFile.existsSync()) {
      dbFile.deleteSync();
    }
    print('✓ Cleanup complete');
  }
}
