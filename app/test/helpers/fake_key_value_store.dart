import 'package:app/domain/contracts/key_value_store.dart';

/// Fake in-memory [KeyValueStore] compartilhado por testes. Substitui os
/// antigos `_FakeSecureStorage` espalhados quando o [Preferences] migrou de
/// `flutter_secure_storage` para `shared_preferences`.
///
/// Mantém um mapa em memória e expõe [map] para inspeção direta nos asserts.
class FakeKeyValueStore implements KeyValueStore {
  final Map<String, String> map = {};

  @override
  Future<String?> read(String key) async => map[key];

  @override
  Future<void> write(String key, String value) async {
    map[key] = value;
  }

  @override
  Future<void> delete(String key) async {
    map.remove(key);
  }
}
