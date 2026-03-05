import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

class OfflineQueueManager {
  static const _storageKey = 'pending_scan_queue';

  static Future<List<Map<String, dynamic>>> _loadQueue() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_storageKey);
    if (raw == null || raw.isEmpty) return [];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is List) {
        return decoded
            .whereType<Map>()
            .map((e) => e.map((k, v) => MapEntry(k.toString(), v)))
            .toList();
      }
      return [];
    } catch (_) {
      return [];
    }
  }

  static Future<void> _saveQueue(List<Map<String, dynamic>> queue) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_storageKey, jsonEncode(queue));
  }

  static Future<void> addPending({
    required String id,
    required String role,
    required String username,
    required String createdAt,
  }) async {
    final queue = await _loadQueue();
    queue.add({
      'id': id,
      'role': role,
      'username': username,
      'created_at': createdAt,
    });
    await _saveQueue(queue);
  }

  static Future<List<Map<String, dynamic>>> getPending() async {
    return _loadQueue();
  }

  static Future<void> removeAt(int index) async {
    final queue = await _loadQueue();
    if (index >= 0 && index < queue.length) {
      queue.removeAt(index);
      await _saveQueue(queue);
    }
  }

  static Future<void> clear() async {
    await _saveQueue([]);
  }
}
