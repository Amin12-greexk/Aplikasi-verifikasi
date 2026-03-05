import 'package:shared_preferences/shared_preferences.dart';
import 'server_profile.dart';

/// Manages server profiles: CRUD, active selection, persistence.
class ServerProfileManager {
  static const String _profilesKey = 'server_profiles';
  static const String _activeIdKey = 'active_profile_id';
  static const bool forceLiveServer = bool.fromEnvironment(
    'FORCE_LIVE_SERVER',
    defaultValue: true,
  );

  static List<ServerProfile> _profiles = [];
  static ServerProfile _activeProfile = ServerProfile.production;

  /// All loaded profiles
  static List<ServerProfile> get profiles => List.unmodifiable(_profiles);

  /// Currently active profile
  static ServerProfile get activeProfile => _activeProfile;

  /// Initialize: load from SharedPreferences, ensure default exists
  static Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();

    // Load profiles
    final raw = prefs.getString(_profilesKey);
    if (raw != null && raw.isNotEmpty) {
      try {
        _profiles = ServerProfile.decodeList(raw);
      } catch (_) {
        _profiles = [];
      }
    }

    // Ensure production profile always exists and always points to live server.
    final productionIndex = _profiles.indexWhere(
      (p) => p.id == ServerProfile.production.id,
    );
    if (productionIndex >= 0) {
      _profiles[productionIndex] = ServerProfile.production;
    } else {
      _profiles.insert(0, ServerProfile.production);
    }
    await _persist();

    // Load active profile
    if (forceLiveServer) {
      _activeProfile = ServerProfile.production;
      await prefs.setString(_activeIdKey, ServerProfile.production.id);
    } else {
      final activeId = prefs.getString(_activeIdKey);
      if (activeId != null) {
        _activeProfile = _profiles.firstWhere(
          (p) => p.id == activeId,
          orElse: () => _profiles.first,
        );
      } else {
        _activeProfile = _profiles.firstWhere(
          (p) => p.isDefault,
          orElse: () => _profiles.first,
        );
      }
    }
  }

  /// Set the active profile by ID
  static Future<void> setActive(String id) async {
    if (forceLiveServer && id != ServerProfile.production.id) {
      return;
    }

    final profile = _profiles.firstWhere(
      (p) => p.id == id,
      orElse: () => _profiles.first,
    );
    _activeProfile = profile;

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_activeIdKey, id);
  }

  /// Add a new profile
  static Future<void> addProfile(ServerProfile profile) async {
    _profiles.add(profile);
    await _persist();
  }

  /// Update an existing profile
  static Future<void> updateProfile(ServerProfile profile) async {
    if (forceLiveServer && profile.id == ServerProfile.production.id) {
      return;
    }

    final index = _profiles.indexWhere((p) => p.id == profile.id);
    if (index >= 0) {
      _profiles[index] = profile;

      // If the updated profile is the active one, refresh
      if (_activeProfile.id == profile.id) {
        _activeProfile = profile;
      }
      await _persist();
    }
  }

  /// Delete a profile (cannot delete default production profile)
  static Future<bool> deleteProfile(String id) async {
    // Prevent deleting production profile
    if (id == ServerProfile.production.id) return false;
    // Prevent deleting active profile
    if (id == _activeProfile.id) return false;

    _profiles.removeWhere((p) => p.id == id);
    await _persist();
    return true;
  }

  /// Generate a unique ID for new profiles
  static String generateId() {
    return 'profile_${DateTime.now().millisecondsSinceEpoch}';
  }

  static Future<void> _persist() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_profilesKey, ServerProfile.encodeList(_profiles));
  }
}
