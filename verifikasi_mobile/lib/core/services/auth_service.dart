import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;
import '../config/config.dart';

enum UserRole { pengawas, security }

class AuthService {
  static const String _tokenKey = 'auth_token';
  static const String _userKey = 'auth_user';
  static const String _roleKey = 'auth_role';

  static String? _token;
  static String? _user;
  static UserRole? _role;

  // Getter
  static String? get token => _token;
  static String? get username => _user;
  static UserRole? get role => _role;
  static bool get isLoggedIn => _token != null;

  // Initialize from saved preferences
  static Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();
    _token = prefs.getString(_tokenKey);
    _user = prefs.getString(_userKey);
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
        final roleStr = data['role']?.toString().toLowerCase();

        if (roleStr == 'pengawas') {
          _role = UserRole.pengawas;
        } else if (roleStr == 'security') {
          _role = UserRole.security;
        } else {
          throw Exception('Unknown role: $roleStr');
        }

        final prefs = await SharedPreferences.getInstance();
        await prefs.setString(_tokenKey, _token!);
        await prefs.setString(_userKey, _user!);
        await prefs.setString(_roleKey, _role.toString());
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

    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_tokenKey);
    await prefs.remove(_userKey);
    await prefs.remove(_roleKey);
  }

  // Check if user has pengawas role
  static bool isPengawas() => _role == UserRole.pengawas;

  // Check if user has security role
  static bool isSecurity() => _role == UserRole.security;
}
