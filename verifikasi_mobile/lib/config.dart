import 'package:shared_preferences/shared_preferences.dart';

class ServerConfig {
  static const String _serverKey = 'server_url';
  static const String _defaultUrl = 'http://192.168.29.45:8080';

  static String _baseUrl = _defaultUrl;

  static String get baseUrl => _baseUrl;

  static Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();
    _baseUrl = prefs.getString(_serverKey) ?? _defaultUrl;
  }

  static Future<void> setServerUrl(String url) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_serverKey, url);
    _baseUrl = url;
  }

  static Future<String> getServerUrl() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_serverKey) ?? _defaultUrl;
  }
}
