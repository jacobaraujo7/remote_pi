import 'package:cockpit/domain/entities/install_result.dart';

/// Executa as instalações oferecidas no onboarding: a extensão `remote-pi` no
/// Pi e o supervisor (serviço do SO). Contrato no domínio; a impl (Process) em
/// `data/`. Tudo best-effort: falha de IO vira [InstallResult.failure].
abstract class EnvironmentInstaller {
  /// `pi install npm:remote-pi` — registra a extensão no Pi.
  Future<InstallResult> installExtension();

  /// `node <remote-pi>/dist/index.js install` — instala o serviço do supervisor.
  /// Pré-requisito: a extensão já instalada (é de lá que vem o `index.js`).
  Future<InstallResult> installSupervisor();
}
