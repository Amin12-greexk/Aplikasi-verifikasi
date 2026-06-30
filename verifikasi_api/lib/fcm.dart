import 'dart:convert';
import 'dart:io';

import 'package:googleapis_auth/auth_io.dart';

/// Result of a single FCM send attempt.
class FcmSendResult {
  final bool success;

  /// True when the target token is no longer valid and should be deleted.
  final bool invalidToken;

  const FcmSendResult({required this.success, this.invalidToken = false});
}

/// Sends push notifications via Firebase Cloud Messaging HTTP v1 API.
///
/// Configuration comes from environment variables:
///   - FCM_SERVICE_ACCOUNT_PATH : path to the service-account JSON file, OR
///   - FCM_SERVICE_ACCOUNT_JSON : the service-account JSON inline.
///   - FCM_PROJECT_ID (optional) : overrides project_id from the JSON.
///
/// If not configured, [fromEnv] returns null and push is simply disabled.
class FcmSender {
  static const List<String> _scopes = [
    'https://www.googleapis.com/auth/firebase.messaging',
  ];

  /// Must match the Android notification channel id used by the mobile app.
  static const String androidChannelId = 'toilet_expiry_channel';

  final ServiceAccountCredentials _credentials;
  final String _projectId;
  AutoRefreshingAuthClient? _client;

  FcmSender._(this._credentials, this._projectId);

  static bool _initialized = false;
  static FcmSender? _instance;

  /// Builds the sender from environment variables. Cached after first call.
  /// Returns null (and logs why) when FCM is not configured.
  static FcmSender? fromEnv() {
    if (_initialized) return _instance;
    _initialized = true;

    final env = Platform.environment;
    var jsonStr = env['FCM_SERVICE_ACCOUNT_JSON'];
    final path = env['FCM_SERVICE_ACCOUNT_PATH'];

    if ((jsonStr == null || jsonStr.trim().isEmpty) &&
        path != null &&
        path.trim().isNotEmpty) {
      try {
        jsonStr = File(path).readAsStringSync();
      } catch (e) {
        stdout.writeln('[FCM] Failed to read service account file "$path": $e');
        return null;
      }
    }

    if (jsonStr == null || jsonStr.trim().isEmpty) {
      stdout.writeln(
        '[FCM] Not configured. Set FCM_SERVICE_ACCOUNT_PATH or '
        'FCM_SERVICE_ACCOUNT_JSON to enable push. Push disabled.',
      );
      return null;
    }

    try {
      final map = jsonDecode(jsonStr) as Map<String, dynamic>;
      final envProjectId = env['FCM_PROJECT_ID']?.trim();
      final projectId = (envProjectId != null && envProjectId.isNotEmpty)
          ? envProjectId
          : map['project_id']?.toString();
      if (projectId == null || projectId.isEmpty) {
        stdout.writeln('[FCM] project_id missing in service account / env.');
        return null;
      }
      final creds = ServiceAccountCredentials.fromJson(map);
      _instance = FcmSender._(creds, projectId);
      stdout.writeln('[FCM] Configured for project "$projectId".');
      return _instance;
    } catch (e) {
      stdout.writeln('[FCM] Invalid service account JSON: $e');
      return null;
    }
  }

  Future<AutoRefreshingAuthClient> _getClient() async {
    return _client ??= await clientViaServiceAccount(_credentials, _scopes);
  }

  /// Sends a notification to a single device [token].
  Future<FcmSendResult> sendToToken({
    required String token,
    required String title,
    required String body,
    Map<String, String>? data,
  }) async {
    try {
      final client = await _getClient();
      final url = Uri.parse(
        'https://fcm.googleapis.com/v1/projects/$_projectId/messages:send',
      );
      final payload = <String, dynamic>{
        'message': {
          'token': token,
          'notification': {'title': title, 'body': body},
          'android': {
            'priority': 'HIGH',
            'notification': {
              'channel_id': androidChannelId,
              'sound': 'default',
            },
          },
          if (data != null && data.isNotEmpty) 'data': data,
        },
      };

      final resp = await client.post(
        url,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(payload),
      );

      if (resp.statusCode == 200) {
        return const FcmSendResult(success: true);
      }

      final bodyText = resp.body;
      final invalid =
          resp.statusCode == 404 ||
          bodyText.contains('UNREGISTERED') ||
          bodyText.contains('NOT_FOUND') ||
          (resp.statusCode == 400 && bodyText.contains('INVALID_ARGUMENT'));
      stdout.writeln('[FCM] send failed ${resp.statusCode}: $bodyText');
      return FcmSendResult(success: false, invalidToken: invalid);
    } catch (e) {
      stdout.writeln('[FCM] send error: $e');
      return const FcmSendResult(success: false);
    }
  }

  void dispose() {
    _client?.close();
    _client = null;
  }
}
