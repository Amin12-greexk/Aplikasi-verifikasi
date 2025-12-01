import 'dart:convert';

import 'package:http/http.dart' as http;

import 'config.dart';

Map<String, dynamic> _tryJson(String body) {
  try {
    final parsed = jsonDecode(body);
    if (parsed is Map<String, dynamic>) return parsed;
    return {'data': parsed};
  } catch (_) {
    return {'error': body};
  }
}

Future<Map<String, dynamic>> accPengawas(String id) async {
  final res = await http.post(
    Uri.parse('$baseUrl/scan-pengawas'),
    headers: {'Content-Type': 'application/json'},
    body: jsonEncode({'id_karyawan': id}),
  );
  final data = _tryJson(res.body);
  if (res.statusCode >= 400) {
    throw Exception(data['error'] ?? 'Gagal ACC pengawas');
  }
  return data;
}

Future<Map<String, dynamic>> accSecurity(String id) async {
  final res = await http.post(
    Uri.parse('$baseUrl/scan-security'),
    headers: {'Content-Type': 'application/json'},
    body: jsonEncode({'id_karyawan': id}),
  );
  final data = _tryJson(res.body);
  if (res.statusCode >= 400) {
    throw Exception(data['error'] ?? 'Gagal ACC security');
  }
  return data;
}

Future<List<Map<String, dynamic>>> fetchLogs() async {
  final res = await http.get(Uri.parse('$baseUrl/logs'));
  if (res.statusCode >= 400) {
    final body = _tryJson(res.body);
    throw Exception(body['error'] ?? 'Gagal mengambil data');
  }
  final body = _tryJson(res.body);
  final List<dynamic> logs = body['logs'] ?? [];
  return logs.cast<Map<String, dynamic>>();
}
