// Plan 58 — testes do seletor de idioma (Preferences.localeCode).
import 'package:app/data/preferences/preferences.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeStorage extends Fake implements FlutterSecureStorage {
  final Map<String, String> _store = {};
  @override
  Future<String?> read({
    required String key,
    IOSOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    MacOsOptions? mOptions,
    WindowsOptions? wOptions,
  }) async => _store[key];

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
      _store.remove(key);
    } else {
      _store[key] = value;
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
  }) async => _store.remove(key);
}

void main() {
  group('Preferences.localeCode', () {
    test('default is null (System)', () {
      final prefs = Preferences(_FakeStorage());
      expect(prefs.localeCode, isNull);
    });

    test('setLocale notifies listeners', () async {
      final prefs = Preferences(_FakeStorage());
      var notified = false;
      prefs.addListener(() => notified = true);
      await prefs.setLocale('en');
      expect(notified, isTrue);
      expect(prefs.localeCode, 'en');
    });

    test('setLocale(null) clears locale', () async {
      final prefs = Preferences(_FakeStorage());
      await prefs.setLocale('en');
      expect(prefs.localeCode, 'en');
      await prefs.setLocale(null);
      expect(prefs.localeCode, isNull);
    });

    test('setLocale same value is no-op', () async {
      final prefs = Preferences(_FakeStorage());
      await prefs.setLocale('en');
      var notified = false;
      prefs.addListener(() => notified = true);
      await prefs.setLocale('en');
      expect(notified, isFalse);
    });

    test('load restores saved locale', () async {
      final storage = _FakeStorage();
      await storage.write(key: 'prefs.locale', value: 'pt-BR');
      final prefs = Preferences(storage);
      await prefs.load();
      expect(prefs.localeCode, 'pt-BR');
    });

    test('load with no saved locale keeps null', () async {
      final prefs = Preferences(_FakeStorage());
      await prefs.load();
      expect(prefs.localeCode, isNull);
    });
  });
}
