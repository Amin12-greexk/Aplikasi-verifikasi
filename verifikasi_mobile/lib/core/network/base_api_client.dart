import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../config/server_profile_manager.dart';

/// Profile-aware HTTP client with retry + timeout logic.
class BaseApiClient {
  static const int maxRetries = 1;          // scanner real-time: cukup 1x retry
  static const Duration timeout = Duration(seconds: 5); // 5s cukup, tidak perlu tunggu lama
  static const Duration retryDelay = Duration(milliseconds: 500); // retry cepat

  /// Persistent client for connection pooling/keep-alive
  static final http.Client _client = http.Client();

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
      debugPrint('[API] Timeout: $e');
      if (retries < maxRetries) {
        debugPrint('[API] Retrying after timeout (attempt ${retries + 1}/$maxRetries)');
        await Future.delayed(retryDelay);
        return makeRequest(request, retries: retries + 1);
      }
      rethrow;
    } catch (e) {
      debugPrint('[API] Error: $e');
      if (_isConnectionError(e) && retries < maxRetries) {
        debugPrint('[API] Connection error, retrying (attempt ${retries + 1}/$maxRetries)');
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
    return makeRequest(() => _client.get(Uri.parse('$baseUrl$path')));
  }

  static Future<http.Response> post(
    String path, {
    Map<String, dynamic>? body,
  }) {
    return makeRequest(
      () => _client.post(
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
      () => _client.put(
        Uri.parse('$baseUrl$path'),
        headers: {'Content-Type': 'application/json'},
        body: body != null ? jsonEncode(body) : null,
      ),
    );
  }

  static Future<http.Response> delete(String path) {
    return makeRequest(
      () => _client.delete(
        Uri.parse('$baseUrl$path'),
        headers: {'Content-Type': 'application/json'},
      ),
    );
  }

  /// Check connectivity to specific URL (for profile testing)
  static Future<bool> checkConnectivity({String? url}) async {
    final targetUrl = url ?? baseUrl;
    try {
      final response = await _client
          .get(Uri.parse('$targetUrl/logs'))
          .timeout(
            const Duration(seconds: 5),
            onTimeout: () => http.Response('timeout', 0),
          );
      return response.statusCode >= 200 && response.statusCode < 500;
    } catch (e) {
      debugPrint('[API] Connection check failed: $e');
      return false;
    }
  }
}
