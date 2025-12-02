import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;
import 'config.dart';

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

  // Login untuk pengawas
  static Future<void> loginPengawas(String username, String password) async {
    await _login(username, password, UserRole.pengawas);
  }

  // Login untuk security
  static Future<void> loginSecurity(String username, String password) async {
    await _login(username, password, UserRole.security);
  }

  // Internal login function
  static Future<void> _login(String username, String password, UserRole role) async {
    try {
      final response = await http.post(
        Uri.parse('${ServerConfig.baseUrl}/auth/login'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'username': username,
          'password': password,
          'role': role == UserRole.pengawas ? 'pengawas' : 'security',
        }),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        _token = data['token'];
        _user = data['username'];
        _role = role;

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
