import 'package:cockpit/app/core/domain/contracts/environment_probe.dart';
import 'package:flutter/foundation.dart';

/// Decide se as abas que dependem do ambiente remote-pi (Conectividade, Daemon
/// Agents, Agendamentos) aparecem nas Configurações. Sem a extensão remote-pi e
/// o supervisor instalados não há o que configurar, então essas abas ficam
/// ocultas — o ambiente é instalado pelo checklist da aba de agente.
///
/// Page-scoped: nasce ao abrir as Configurações e roda [check] no `initState`.
class SettingsEnvGate extends ChangeNotifier {
  SettingsEnvGate(this._env);

  final EnvironmentProbe _env;

  bool _remoteReady = false;
  bool _disposed = false;

  /// `true` quando extensão remote-pi **e** supervisor estão instalados.
  bool get remoteReady => _remoteReady;

  /// Re-sonda o ambiente. Chamado ao montar a tela (e pode ser re-chamado se o
  /// usuário instalar o ambiente sem sair das Configurações).
  Future<void> check() async {
    final extension = await _env.extensionInstalled();
    final supervisor = await _env.supervisorInstalled();
    final next = extension && supervisor;
    if (next == _remoteReady) return;
    _remoteReady = next;
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
