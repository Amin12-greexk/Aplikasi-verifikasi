import 'package:shared_preferences/shared_preferences.dart';

class DailyRefreshManager {
  static const String _lastRefreshKey = 'last_daily_refresh_date';

  /// Check if we need to refresh based on day change
  static Future<bool> shouldRefreshDaily() async {
    final prefs = await SharedPreferences.getInstance();
    final lastRefreshDate = prefs.getString(_lastRefreshKey);

    final today = DateTime.now();
    final todayDate = '${today.year}-${today.month.toString().padLeft(2, '0')}-${today.day.toString().padLeft(2, '0')}';

    if (lastRefreshDate == null || lastRefreshDate != todayDate) {
      // Save today's date as last refresh
      await prefs.setString(_lastRefreshKey, todayDate);
      return true;
    }

    return false;
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
