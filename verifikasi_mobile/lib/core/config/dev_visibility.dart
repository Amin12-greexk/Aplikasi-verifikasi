import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Controls dev-only UI blocks (server info/settings).
///
/// Behavior:
/// - Release/Profile build: always hidden.
/// - Debug build: can be shown/hidden via runtime toggle.
class DevVisibility {
  static const String _showServerSectionKey = 'dev_show_server_section';

  static final ValueNotifier<bool> showServerSection = ValueNotifier<bool>(
    false,
  );

  static bool get canControlServerSection => kDebugMode;

  static bool get shouldShowServerSection =>
      canControlServerSection && showServerSection.value;

  static Future<void> init() async {
    if (!canControlServerSection) {
      showServerSection.value = false;
      return;
    }

    final prefs = await SharedPreferences.getInstance();
    showServerSection.value = prefs.getBool(_showServerSectionKey) ?? true;
  }

  static Future<void> setShowServerSection(bool value) async {
    if (!canControlServerSection) return;

    showServerSection.value = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_showServerSectionKey, value);
  }
}
