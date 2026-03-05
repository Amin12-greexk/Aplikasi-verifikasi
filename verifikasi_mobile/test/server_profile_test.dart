import 'package:flutter_test/flutter_test.dart';
import 'package:verifikasi_mobile/core/config/server_profile.dart';

void main() {
  group('ServerProfile', () {
    test('production profile has correct defaults', () {
      final p = ServerProfile.production;
      expect(p.id, 'production');
      expect(p.name, 'Production');
      expect(p.baseUrl, 'https://veriv.tunasestaindonesia.com');
      expect(p.isDefault, true);
      expect(p.enabledModules, contains('verification'));
      expect(p.enabledModules, contains('history'));
    });

    test('toJson and fromJson roundtrip', () {
      const profile = ServerProfile(
        id: 'test_1',
        name: 'Test Server',
        baseUrl: 'https://test.example.com',
        enabledModules: ['verification', 'attendance'],
        isDefault: false,
      );

      final json = profile.toJson();
      final restored = ServerProfile.fromJson(json);

      expect(restored.id, profile.id);
      expect(restored.name, profile.name);
      expect(restored.baseUrl, profile.baseUrl);
      expect(restored.enabledModules, profile.enabledModules);
      expect(restored.isDefault, profile.isDefault);
    });

    test('encodeList and decodeList roundtrip', () {
      final profiles = [
        ServerProfile.production,
        const ServerProfile(
          id: 'dev',
          name: 'Development',
          baseUrl: 'http://localhost:3000',
          enabledModules: ['verification'],
        ),
      ];

      final encoded = ServerProfile.encodeList(profiles);
      final decoded = ServerProfile.decodeList(encoded);

      expect(decoded.length, 2);
      expect(decoded[0].id, 'production');
      expect(decoded[1].id, 'dev');
      expect(decoded[1].name, 'Development');
      expect(decoded[1].baseUrl, 'http://localhost:3000');
    });

    test('copyWith creates new instance with updated fields', () {
      const original = ServerProfile(
        id: 'orig',
        name: 'Original',
        baseUrl: 'https://orig.com',
        enabledModules: ['verification'],
      );

      final updated = original.copyWith(name: 'Updated', baseUrl: 'https://new.com');

      expect(updated.id, 'orig');
      expect(updated.name, 'Updated');
      expect(updated.baseUrl, 'https://new.com');
      expect(updated.enabledModules, ['verification']);
    });

    test('isModuleEnabled checks correctly', () {
      const profile = ServerProfile(
        id: 'test',
        name: 'Test',
        baseUrl: 'https://test.com',
        enabledModules: ['verification', 'history'],
      );

      expect(profile.isModuleEnabled('verification'), true);
      expect(profile.isModuleEnabled('history'), true);
      expect(profile.isModuleEnabled('attendance'), false);
    });

    test('equality is based on id', () {
      const a = ServerProfile(id: 'same', name: 'A', baseUrl: 'https://a.com');
      const b = ServerProfile(id: 'same', name: 'B', baseUrl: 'https://b.com');
      const c = ServerProfile(id: 'diff', name: 'A', baseUrl: 'https://a.com');

      expect(a, equals(b));
      expect(a, isNot(equals(c)));
    });

    test('fromJson handles missing enabledModules gracefully', () {
      final json = {'id': 'x', 'name': 'X', 'baseUrl': 'https://x.com'};
      final profile = ServerProfile.fromJson(json);

      expect(profile.enabledModules, ['verification', 'history']);
      expect(profile.isDefault, false);
    });
  });
}
