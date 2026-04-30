import 'dart:convert';

import 'package:http/http.dart' as http;

class RemoteApiService {
  RemoteApiService(String baseUrl) : _baseUrl = _normalizeBaseUrl(baseUrl);

  final String _baseUrl;
  String? _adminToken;

  static String _normalizeBaseUrl(String raw) {
    final trimmed = raw.trim();
    if (trimmed.endsWith('/')) {
      return trimmed.substring(0, trimmed.length - 1);
    }
    return trimmed;
  }

  String get baseUrl => _baseUrl;

  void logout() {
    _adminToken = null;
  }

  Uri _uri(String path) => Uri.parse('$_baseUrl$path');

  Map<String, String> _headers({bool withJson = false}) {
    final headers = <String, String>{};
    if (withJson) {
      headers['Content-Type'] = 'application/json';
    }
    if (_adminToken != null && _adminToken!.isNotEmpty) {
      headers['Authorization'] = 'Bearer $_adminToken';
    }
    return headers;
  }

  Map<String, dynamic> _decodeMap(String body) {
    if (body.trim().isEmpty) {
      return <String, dynamic>{};
    }
    final decoded = jsonDecode(body);
    if (decoded is Map<String, dynamic>) {
      return decoded;
    }
    return <String, dynamic>{'data': decoded};
  }

  Exception _toException(http.Response response) {
    try {
      final decoded = _decodeMap(response.body);
      final message =
          decoded['error']?.toString() ??
          decoded['message']?.toString() ??
          'HTTP ${response.statusCode}';
      return Exception(message);
    } catch (_) {
      return Exception('HTTP ${response.statusCode}: ${response.body}');
    }
  }

  Future<Map<String, dynamic>> _sendJson({
    required String method,
    required String path,
    Map<String, dynamic>? body,
  }) async {
    late http.Response response;
    final uri = _uri(path);
    final headers = _headers(withJson: true);

    switch (method) {
      case 'GET':
        response = await http.get(uri, headers: headers);
      case 'POST':
        response = await http.post(
          uri,
          headers: headers,
          body: body == null ? null : jsonEncode(body),
        );
      case 'PUT':
        response = await http.put(
          uri,
          headers: headers,
          body: body == null ? null : jsonEncode(body),
        );
      case 'DELETE':
        response = await http.delete(uri, headers: headers);
      default:
        throw Exception('Unsupported method: $method');
    }

    if (response.statusCode >= 400) {
      throw _toException(response);
    }

    return _decodeMap(response.body);
  }

  Future<void> loginAdmin({
    required String username,
    required String password,
  }) async {
    final data = await _sendJson(
      method: 'POST',
      path: '/admin/login',
      body: {'username': username, 'password': password},
    );
    _adminToken = data['token']?.toString();
  }

  Future<List<Map<String, dynamic>>> fetchLogs() async {
    final data = await _sendJson(method: 'GET', path: '/logs');
    final logs = data['logs'];
    if (logs is! List) return <Map<String, dynamic>>[];
    return logs.map((e) => Map<String, dynamic>.from(e as Map)).toList();
  }

  Future<List<Map<String, dynamic>>> fetchLogsByDate(String tanggal) async {
    final data = await _sendJson(method: 'GET', path: '/logs-history/$tanggal');
    final logs = data['logs'];
    if (logs is! List) return <Map<String, dynamic>>[];
    return logs.map((e) => Map<String, dynamic>.from(e as Map)).toList();
  }

  Future<List<String>> fetchHistoryDates() async {
    final data = await _sendJson(method: 'GET', path: '/dates-history');
    final dates = data['dates'];
    if (dates is! List) return <String>[];
    return dates.map((e) => e.toString()).toList();
  }

  Future<List<Map<String, dynamic>>> fetchUsers() async {
    final data = await _sendJson(method: 'GET', path: '/admin/users');
    final users = data['users'];
    if (users is! List) return <Map<String, dynamic>>[];
    return users.map((e) => Map<String, dynamic>.from(e as Map)).toList();
  }

  Future<List<Map<String, dynamic>>> fetchRooms() async {
    final data = await _sendJson(method: 'GET', path: '/admin/rooms');
    final rooms = data['rooms'];
    if (rooms is! List) return <Map<String, dynamic>>[];
    return rooms.map((e) => Map<String, dynamic>.from(e as Map)).toList();
  }

  Future<void> createRoom({
    required String name,
    required int maxConcurrentPermits,
    required int dailyMitraLimit,
    required bool isActive,
  }) async {
    await _sendJson(
      method: 'POST',
      path: '/admin/rooms',
      body: {
        'name': name,
        'max_concurrent_permits': maxConcurrentPermits,
        'daily_mitra_limit': dailyMitraLimit,
        'is_active': isActive ? 1 : 0,
      },
    );
  }

  Future<void> updateRoom({
    required int id,
    required String name,
    required int maxConcurrentPermits,
    required int dailyMitraLimit,
    required bool isActive,
  }) async {
    await _sendJson(
      method: 'PUT',
      path: '/admin/rooms/$id',
      body: {
        'name': name,
        'max_concurrent_permits': maxConcurrentPermits,
        'daily_mitra_limit': dailyMitraLimit,
        'is_active': isActive ? 1 : 0,
      },
    );
  }

  Future<void> deleteRoom(int id) async {
    await _sendJson(method: 'DELETE', path: '/admin/rooms/$id');
  }

  Future<void> createUser({
    required String username,
    required String password,
    required String role,
    int? roomId,
  }) async {
    await _sendJson(
      method: 'POST',
      path: '/admin/users',
      body: {
        'username': username,
        'password': password,
        'role': role,
        'room_id': roomId,
      },
    );
  }

  Future<void> updateUser({
    required int id,
    required String password,
    required String role,
    int? roomId,
  }) async {
    await _sendJson(
      method: 'PUT',
      path: '/admin/users/$id',
      body: {'password': password, 'role': role, 'room_id': roomId},
    );
  }

  Future<void> deleteUser(int id) async {
    await _sendJson(method: 'DELETE', path: '/admin/users/$id');
  }

  Future<Map<String, dynamic>> clearLogsOnly() async {
    return _sendJson(method: 'POST', path: '/admin/clear-logs');
  }

  Future<Map<String, dynamic>> clearAllData() async {
    return _sendJson(method: 'POST', path: '/admin/clear-all-data');
  }
}
