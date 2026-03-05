import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import '../config/server_profile_manager.dart';

/// Profile-aware HTTP client with retry + timeout logic.
class BaseApiClient {
  static const int maxRetries = 3;
  static const Duration timeout = Duration(seconds: 10);
  static const Duration retryDelay = Duration(seconds: 2);

  /// Resolve base URL from active server profile
  static String get baseUrl => ServerProfileManager.activeProfile.baseUrl;

  /// Make HTTP request with auto-retry logic
  static Future<http.Response> makeRequest(
    Future<http.Response> Function() request, {
    int retries = 0,
  }) async {
    try {
      final response = await request().timeout(
        timeout,
        onTimeout: () {
          throw TimeoutException('Request timeout after ${timeout.inSeconds}s');
        },
      );
      return response;
    } on TimeoutException catch (e) {
      print('[API] Timeout: $e');
      if (retries < maxRetries) {
        print('[API] Retrying after timeout (attempt ${retries + 1}/$maxRetries)');
        await Future.delayed(retryDelay);
        return makeRequest(request, retries: retries + 1);
      }
      rethrow;
    } catch (e) {
      print('[API] Error: $e');
      if (_isConnectionError(e) && retries < maxRetries) {
        print('[API] Connection error, retrying (attempt ${retries + 1}/$maxRetries)');
        await Future.delayed(retryDelay * (retries + 1));
        return makeRequest(request, retries: retries + 1);
      }
      rethrow;
    }
  }

  static bool _isConnectionError(Object e) {
    final msg = e.toString();
    return msg.contains('Connection') ||
        msg.contains('refused') ||
        msg.contains('Host') ||
        msg.contains('unreachable');
  }

  /// Parse JSON response body safely
  static Map<String, dynamic> tryJson(String body) {
    try {
      final parsed = jsonDecode(body);
      if (parsed is Map<String, dynamic>) return parsed;
      return {'data': parsed};
    } catch (_) {
      return {'error': body};
    }
  }

  // ── Convenience HTTP methods ──

  static Future<http.Response> get(String path) {
    return makeRequest(() => http.get(Uri.parse('$baseUrl$path')));
  }

  static Future<http.Response> post(
    String path, {
    Map<String, dynamic>? body,
  }) {
    return makeRequest(
      () => http.post(
        Uri.parse('$baseUrl$path'),
        headers: {'Content-Type': 'application/json'},
        body: body != null ? jsonEncode(body) : null,
      ),
    );
  }

  static Future<http.Response> put(
    String path, {
    Map<String, dynamic>? body,
  }) {
    return makeRequest(
      () => http.put(
        Uri.parse('$baseUrl$path'),
        headers: {'Content-Type': 'application/json'},
        body: body != null ? jsonEncode(body) : null,
      ),
    );
  }

  static Future<http.Response> delete(String path) {
    return makeRequest(
      () => http.delete(
        Uri.parse('$baseUrl$path'),
        headers: {'Content-Type': 'application/json'},
      ),
    );
  }

  /// Check connectivity to specific URL (for profile testing)
  static Future<bool> checkConnectivity({String? url}) async {
    final targetUrl = url ?? baseUrl;
    try {
      final response = await http
          .get(Uri.parse('$targetUrl/logs'))
          .timeout(
            const Duration(seconds: 5),
            onTimeout: () => http.Response('timeout', 0),
          );
      return response.statusCode >= 200 && response.statusCode < 500;
    } catch (e) {
      print('[API] Connection check failed: $e');
      return false;
    }
  }
}
