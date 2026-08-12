import 'package:app/data/preferences/preferences_migration.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/fake_key_value_store.dart';

/// Legacy secure storage que simula o `flutter_secure_storage` onde as prefs
/// de UI viviam antes da migração para `shared_preferences`.
class _LegacySecureStorage implements FlutterSecureStorage {
  final Map<String, String> map = {};

  @override
  Future<String?> read({
    required String key,
    IOSOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    MacOsOptions? mOptions,
    WindowsOptions? wOptions,
  }) async => map[key];

  @override
  Future<void> write({
    required String key,
    required String? value,
    IOSOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    MacOsOptions? mOptions,
    WindowsOptions? wOptions,
  }) async {
    if (value == null) {
      map.remove(key);
    } else {
      map[key] = value;
    }
  }

  @override
  Future<void> delete({
    required String key,
    IOSOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    MacOsOptions? mOptions,
    WindowsOptions? wOptions,
  }) async {
    map.remove(key);
  }

  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

void main() {
  group('migrateLegacySecurePrefs', () {
    test(
      'copies legacy values into the target store and clears the legacy',
      () async {
        final legacy = _LegacySecureStorage();
        final target = FakeKeyValueStore();

        // Pre-populate the legacy secure storage with UI prefs.
        await legacy.write(key: 'prefs.hide_tool_calls', value: 'true');
        await legacy.write(
          key: 'prefs.selected_peer_epk',
          value: 'abc123:main',
        );
        await legacy.write(
          key: 'prefs.relay_url',
          value: 'https://custom.example',
        );
        await legacy.write(key: 'prefs.onboarding_completed', value: 'true');
        await legacy.write(key: 'prefs.theme_mode', value: 'dark');
        await legacy.write(key: 'prefs.font_scale', value: 'large');

        await migrateLegacySecurePrefs(legacy, target);

        // Target has the copied values.
        expect(await target.read('prefs.hide_tool_calls'), 'true');
        expect(await target.read('prefs.selected_peer_epk'), 'abc123:main');
        expect(await target.read('prefs.relay_url'), 'https://custom.example');
        expect(await target.read('prefs.onboarding_completed'), 'true');
        expect(await target.read('prefs.theme_mode'), 'dark');
        expect(await target.read('prefs.font_scale'), 'large');

        // Legacy secure storage is emptied.
        expect(legacy.map, isEmpty);
      },
    );

    test('does not overwrite an existing target value', () async {
      final legacy = _LegacySecureStorage();
      final target = FakeKeyValueStore();

      // Target already has a value (e.g. the user already migrated on a
      // previous launch, or set a fresh pref before migration ran).
      await target.write('prefs.theme_mode', 'light');
      // Legacy still has an older value.
      await legacy.write(key: 'prefs.theme_mode', value: 'dark');

      await migrateLegacySecurePrefs(legacy, target);

      // Target value wins — not overwritten by the stale legacy value.
      expect(await target.read('prefs.theme_mode'), 'light');
      // Legacy is still cleared (value consumed).
      expect(legacy.map, isEmpty);
    });

    test('a missing legacy key does not touch the target', () async {
      final legacy = _LegacySecureStorage(); // empty
      final target = FakeKeyValueStore();
      await target.write('prefs.theme_mode', 'dark');

      await migrateLegacySecurePrefs(legacy, target);

      expect(await target.read('prefs.theme_mode'), 'dark');
    });

    test('an empty-string legacy value is dropped (not copied)', () async {
      final legacy = _LegacySecureStorage();
      final target = FakeKeyValueStore();

      // Empty string is treated the same as "absent" — nothing useful to
      // migrate, and the legacy entry is cleaned up.
      await legacy.write(key: 'prefs.theme_mode', value: '');

      await migrateLegacySecurePrefs(legacy, target);

      expect(await target.read('prefs.theme_mode'), isNull);
      expect(legacy.map, isEmpty);
    });

    test(
      'keys outside the migration list are left untouched in the legacy',
      () async {
        final legacy = _LegacySecureStorage();
        final target = FakeKeyValueStore();

        // Secret / unrelated keys that must NEVER be swept by the migration.
        await legacy.write(key: 'dev.remotepi.peers', value: 'paired-secret');
        await legacy.write(key: 'owner.key', value: 'private-key-material');
        // One in-scope UI pref, to prove the migration still runs.
        await legacy.write(key: 'prefs.theme_mode', value: 'dark');

        await migrateLegacySecurePrefs(legacy, target);

        // In-scope key was migrated.
        expect(await target.read('prefs.theme_mode'), 'dark');
        // Out-of-scope keys remain in the legacy store untouched.
        expect(legacy.map['dev.remotepi.peers'], 'paired-secret');
        expect(legacy.map['owner.key'], 'private-key-material');
        expect(legacy.map.containsKey('prefs.theme_mode'), isFalse);
      },
    );
  });
}
