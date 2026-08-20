import 'package:app/config/dependencies.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Legacy secure storage com dados pré-populados, simulando o que um usuário
/// existente teria persistido ANTES da migração para shared_preferences.
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
  TestWidgetsFlutterBinding.ensureInitialized();

  group('loadPreferencesWithMigration', () {
    test(
      'existing user keeps persisted UI prefs after boot (no data loss)',
      () async {
        // Target shared_preferences come up empty — this simulates a cold
        // install that hasn't written anything yet.
        SharedPreferences.setMockInitialValues({});

        // Legacy secure storage has what a pre-migration user persisted.
        final legacy = _LegacySecureStorage();
        await legacy.write(key: 'prefs.theme_mode', value: 'dark');
        await legacy.write(
          key: 'prefs.relay_url',
          value: 'https://custom.example',
        );
        await legacy.write(
          key: 'prefs.selected_peer_epk',
          value: 'abc123:main',
        );
        await legacy.write(key: 'prefs.hide_tool_calls', value: 'true');

        final prefs = await loadPreferencesWithMigration(
          getPrefs: SharedPreferences.getInstance,
          legacy: legacy,
        );

        // The invariant: values that lived in secure storage are now visible
        // through the hydrated Preferences — regardless of the internal
        // ordering (migrate→load), a user never loses their settings.
        expect(prefs.themeMode.name, 'dark');
        expect(prefs.relayUrl, 'https://custom.example');
        expect(prefs.selectedPeerEpk, 'abc123');
        expect(prefs.hideToolCalls, isTrue);

        // Legacy secure storage was drained by the migration.
        expect(legacy.map, isEmpty);
      },
    );

    test('fresh install (empty legacy) leaves defaults intact', () async {
      SharedPreferences.setMockInitialValues({});
      final legacy = _LegacySecureStorage(); // vazio

      final prefs = await loadPreferencesWithMigration(
        getPrefs: SharedPreferences.getInstance,
        legacy: legacy,
      );

      // Defaults, nothing surprising when there's nothing to migrate.
      expect(prefs.themeMode.name, 'system');
      expect(prefs.relayUrl, isNull);
      expect(prefs.selectedPeerEpk, isNull);
      expect(prefs.hideToolCalls, isFalse);
    });
  });
}
