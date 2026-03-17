import 'dart:convert';

/// Represents a server profile for multi-server support.
/// Each module/feature can be enabled or disabled per profile.
class ServerProfile {
  final String id;
  final String name;
  final String baseUrl;
  final List<String> enabledModules;
  final bool isDefault;

  const ServerProfile({
    required this.id,
    required this.name,
    required this.baseUrl,
    this.enabledModules = const ['verification', 'toilet', 'history'],
    this.isDefault = false,
  });

  /// Default production profile
  static const ServerProfile production = ServerProfile(
    id: 'production',
    name: 'Production',
    baseUrl: 'https://veriv.tunasestaindonesia.com',
    enabledModules: ['verification', 'toilet', 'history'],
    isDefault: true,
  );

  /// All available module keys
  static const List<String> allModules = [
    'verification',
    'toilet',
    'attendance',
    'history',
  ];

  /// Module display names
  static const Map<String, String> moduleLabels = {
    'verification': 'Verifikasi',
    'toilet': 'Izin Toilet',
    'attendance': 'Absensi',
    'history': 'Riwayat',
  };

  bool isModuleEnabled(String module) => enabledModules.contains(module);

  ServerProfile copyWith({
    String? id,
    String? name,
    String? baseUrl,
    List<String>? enabledModules,
    bool? isDefault,
  }) {
    return ServerProfile(
      id: id ?? this.id,
      name: name ?? this.name,
      baseUrl: baseUrl ?? this.baseUrl,
      enabledModules: enabledModules ?? this.enabledModules,
      isDefault: isDefault ?? this.isDefault,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'baseUrl': baseUrl,
      'enabledModules': enabledModules,
      'isDefault': isDefault,
    };
  }

  factory ServerProfile.fromJson(Map<String, dynamic> json) {
    return ServerProfile(
      id: json['id'] as String,
      name: json['name'] as String,
      baseUrl: json['baseUrl'] as String,
      enabledModules:
          (json['enabledModules'] as List<dynamic>?)
              ?.map((e) => e.toString())
              .toList() ??
          ['verification', 'toilet', 'history'],
      isDefault: json['isDefault'] as bool? ?? false,
    );
  }

  static String encodeList(List<ServerProfile> profiles) {
    return jsonEncode(profiles.map((p) => p.toJson()).toList());
  }

  static List<ServerProfile> decodeList(String jsonStr) {
    final list = jsonDecode(jsonStr) as List<dynamic>;
    return list
        .map((e) => ServerProfile.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ServerProfile &&
          runtimeType == other.runtimeType &&
          id == other.id;

  @override
  int get hashCode => id.hashCode;

  @override
  String toString() => 'ServerProfile(id: $id, name: $name, baseUrl: $baseUrl)';
}
