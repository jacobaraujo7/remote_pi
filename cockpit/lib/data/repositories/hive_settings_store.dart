import 'package:cockpit/domain/contracts/settings_store.dart';
import 'package:cockpit/domain/entities/app_settings.dart';
import 'package:hive/hive.dart';

/// Persiste as [AppSettings] numa Box do Hive (um único registro JSON sob a
/// chave [_key]). Só tipos primitivos → sem TypeAdapters.
class HiveSettingsStore implements SettingsStore {
  HiveSettingsStore(this._box);

  final Box<dynamic> _box;

  static const String boxName = 'settings';
  static const String _key = 'app';

  @override
  Future<AppSettings> load() async {
    final raw = _box.get(_key);
    if (raw is Map) return AppSettings.fromJson(raw);
    return const AppSettings();
  }

  @override
  Future<void> save(AppSettings settings) => _box.put(_key, settings.toJson());
}
