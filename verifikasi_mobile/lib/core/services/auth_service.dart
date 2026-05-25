import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;
import '../config/config.dart';

enum UserRole { pengawas, security, manager, admin }

class AuthService {
  static const String _tokenKey = 'auth_token';
  static const String _userKey = 'auth_user';
  static const String _roleKey = 'auth_role';
  static const String _roomIdKey = 'auth_room_id';
  static const String _roomNameKey = 'auth_room_name';

  static String? _token;
  static String? _user;
  static UserRole? _role;
  static int? _roomId;
  static String? _roomName;

  // Getter
  static String? get token => _token;
  static String? get username => _user;
  static UserRole? get role => _role;
  static int? get roomId => _roomId;
  static String? get roomName => _roomName;
  static bool get isLoggedIn => _token != null;

  // Initialize from saved preferences
  static Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();
    _token = prefs.getString(_tokenKey);
    _user = prefs.getString(_userKey);
    _roomId = prefs.getInt(_roomIdKey);
    _roomName = prefs.getString(_roomNameKey);
    final roleStr = prefs.getString(_roleKey);
    if (roleStr != null) {
      _role = UserRole.values.firstWhere((e) => e.toString() == roleStr);
    }
  }

  // Login
  static Future<void> login(String username, String password) async {
    try {
      final response = await http.post(
        Uri.parse('${ServerConfig.baseUrl}/auth/login'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'username': username,
          'password': password,
        }),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        _token = data['token'];
        _user = data['username'];
        _roomId = data['room_id'] as int?;
        _roomName = data['room_name']?.toString();
        final roleStr = data['role']?.toString().toLowerCase();

        if (roleStr == 'pengawas') {
          _role = UserRole.pengawas;
        } else if (roleStr == 'security') {
          _role = UserRole.security;
        } else if (roleStr == 'manager') {
          _role = UserRole.manager;
        } else if (roleStr == 'admin') {
          _role = UserRole.admin;
        } else {
          throw Exception('Unknown role: $roleStr');
        }

        final prefs = await SharedPreferences.getInstance();
        await prefs.setString(_tokenKey, _token!);
        await prefs.setString(_userKey, _user!);
        await prefs.setString(_roleKey, _role.toString());
        if (_roomId != null) await prefs.setInt(_roomIdKey, _roomId!);
        if (_roomName != null) await prefs.setString(_roomNameKey, _roomName!);
      } else {
        final error = jsonDecode(response.body);
        throw Exception(error['error'] ?? 'Login failed');
      }
    } catch (e) {
      rethrow;
    }
  }

  // Logout
  static Future<void> logout() async {
    _token = null;
    _user = null;
    _role = null;
    _roomId = null;
    _roomName = null;

    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_tokenKey);
    await prefs.remove(_userKey);
    await prefs.remove(_roleKey);
    await prefs.remove(_roomIdKey);
    await prefs.remove(_roomNameKey);
  }

  // Check if user has pengawas role
  static bool isPengawas() => _role == UserRole.pengawas;

  // Check if user has security role
  static bool isSecurity() => _role == UserRole.security;

  // Check if user has manager role
  static bool isManager() => _role == UserRole.manager;
}
