import 'package:cockpit/app/core/domain/contracts/settings_store.dart';
import 'package:cockpit/app/core/domain/entities/app_settings.dart';
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
    if (raw is Map) {
      final settings = AppSettings.fromJson(raw);
      // Migração: um registro salvo por uma versão ANTERIOR à flag `enableAgent`
      // não tem essa chave. Esses usuários já usavam agentes → preservamos
      // ligando a flag (e persistindo, pra não re-migrar). Instalação nova nunca
      // cai aqui: ou não tem registro (fresh), ou já grava a chave (= false).
      if (!raw.containsKey('enableAgent')) {
        final migrated = settings.copyWith(enableAgent: true);
        await save(migrated);
        return migrated;
      }
      // Migração: registro sem `showCockpit` (versão anterior à flag) → liga o
      // workspace de sistema e persiste (default já é true; grava pra não
      // re-migrar e alinhar com o padrão de `enableAgent`).
      if (!raw.containsKey('showCockpit')) {
        final migrated = settings.copyWith(showCockpit: true);
        await save(migrated);
        return migrated;
      }
      return settings;
    }
    return const AppSettings();
  }

  @override
  Future<void> save(AppSettings settings) => _box.put(_key, settings.toJson());
}
