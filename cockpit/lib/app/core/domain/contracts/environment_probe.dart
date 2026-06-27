/// Verifica o que está instalado no ambiente do usuário pro onboarding:
/// o binário do Pi, a extensão remote-pi registrada no Pi, e o supervisor
/// (serviço do SO). Contrato no domínio; a impl (Process/filesystem) em `data/`.
abstract class EnvironmentProbe {
  /// O binário `pi` está instalado/acessível?
  Future<bool> piInstalled();

  /// A extensão `remote-pi` está registrada no Pi (em `~/.pi/agent/settings.json`)?
  Future<bool> extensionInstalled();

  /// O supervisor (`pi-supervisord`) está instalado como serviço do SO?
  Future<bool> supervisorInstalled();
}
