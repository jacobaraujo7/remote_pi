import 'package:app/domain/contracts/key_value_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Implementação de [KeyValueStore] sobre `shared_preferences` (armazenamento
/// plano do SO — Android SharedPreferences, iOS NSUserDefaults). Para dados
/// não-sensíveis; segredos continuam em `flutter_secure_storage`.
class SharedPrefsKeyValueStore implements KeyValueStore {
  final SharedPreferences _prefs;

  SharedPrefsKeyValueStore(this._prefs);

  @override
  Future<String?> read(String key) async => _prefs.getString(key);

  @override
  Future<void> write(String key, String value) async {
    await _prefs.setString(key, value);
  }

  @override
  Future<void> delete(String key) async {
    await _prefs.remove(key);
  }
}
