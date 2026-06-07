import 'package:cockpit/domain/entities/app_settings.dart';

/// Persiste as [AppSettings] localmente. Contrato no domínio; impl (Hive) em
/// `data/`.
abstract class SettingsStore {
  /// Carrega as preferências salvas (ou os defaults se nunca salvou).
  Future<AppSettings> load();

  /// Persiste as preferências.
  Future<void> save(AppSettings settings);
}
