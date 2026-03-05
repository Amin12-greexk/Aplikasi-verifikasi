import 'server_profile_manager.dart';

/// Backward-compatible ServerConfig that delegates to ServerProfileManager.
class ServerConfig {
  static String get baseUrl => ServerProfileManager.activeProfile.baseUrl;

  static Future<void> init() async {
    await ServerProfileManager.init();
  }

  static Future<void> setServerUrl(String url) async {
    // No-op for backward compatibility.
    // Use ServerProfileManager to change profiles.
  }

  static Future<String> getServerUrl() async {
    return baseUrl;
  }
}
