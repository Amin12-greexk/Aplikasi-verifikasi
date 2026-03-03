import 'package:shared_preferences/shared_preferences.dart';

class DailyRefreshManager {
  static const String _lastRefreshKey = 'last_daily_refresh_date';

  /// Get today's date in YYYY-MM-DD format
  static String _getTodayDate() {
    final today = DateTime.now();
    return '${today.year}-${today.month.toString().padLeft(2, '0')}-${today.day.toString().padLeft(2, '0')}';
  }

  /// Check if we need to refresh based on day change
  /// NOTE: This only checks, it does NOT mark as refreshed
  /// Call markAsRefreshed() after the API call succeeds
  static Future<bool> shouldRefreshDaily() async {
    final prefs = await SharedPreferences.getInstance();
    final lastRefreshDate = prefs.getString(_lastRefreshKey);
    final todayDate = _getTodayDate();

    // Return true if it's a new day
    return lastRefreshDate == null || lastRefreshDate != todayDate;
  }

  /// Mark today as refreshed
  /// Call this ONLY after the daily reset API call succeeds
  static Future<void> markAsRefreshed() async {
    final prefs = await SharedPreferences.getInstance();
    final todayDate = _getTodayDate();
    await prefs.setString(_lastRefreshKey, todayDate);
  }

  /// Get the last refresh date
  static Future<String?> getLastRefreshDate() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_lastRefreshKey);
  }

  /// Reset the refresh date (useful for testing)
  static Future<void> resetRefreshDate() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_lastRefreshKey);
  }
}
