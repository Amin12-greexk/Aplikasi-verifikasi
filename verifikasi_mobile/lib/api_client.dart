import 'dart:convert';

import 'package:http/http.dart' as http;

import 'config.dart' as config_module;

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
    Uri.parse('${config_module.ServerConfig.baseUrl}/scan-pengawas'),
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
    Uri.parse('${config_module.ServerConfig.baseUrl}/scan-security'),
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
  final res = await http.get(Uri.parse('${config_module.ServerConfig.baseUrl}/logs'));
  if (res.statusCode >= 400) {
    final body = _tryJson(res.body);
    throw Exception(body['error'] ?? 'Gagal mengambil data');
  }
  final body = _tryJson(res.body);
  final List<dynamic> logs = body['logs'] ?? [];
  return logs.cast<Map<String, dynamic>>();
}

Future<Map<String, dynamic>> dailyReset() async {
  final res = await http.post(
    Uri.parse('${config_module.ServerConfig.baseUrl}/daily-reset'),
    headers: {'Content-Type': 'application/json'},
  );
  final data = _tryJson(res.body);
  if (res.statusCode >= 400) {
    throw Exception(data['error'] ?? 'Gagal melakukan daily reset');
  }
  return data;
}
