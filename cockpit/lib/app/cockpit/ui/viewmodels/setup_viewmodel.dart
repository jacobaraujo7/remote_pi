import 'package:cockpit/app/cockpit/domain/contracts/environment_installer.dart';
import 'package:cockpit/app/cockpit/domain/entities/install_result.dart';
import 'package:cockpit/app/core/domain/contracts/environment_probe.dart';
import 'package:cockpit/app/core/domain/entities/setup_check.dart';
import 'package:flutter/foundation.dart';

/// Estado das 3 checagens do ambiente de **agente** (pi + extensão remote-pi +
/// supervisor) + ações de re-checagem/instalação.
///
/// Gate de "Create agent" = [agentReady] (o trio satisfeito; `notApplicable`
/// conta como satisfeito). Os passos de instalação são re-checados sob demanda
/// (botão por passo). Antes ficava no onboarding do boot; agora dispara só
/// quando o usuário abre uma aba de agente (ver `AgentSetupChecklist`).
/// Notificações saíram daqui — viraram aba própria nas Configurações.
class SetupViewModel extends ChangeNotifier {
  SetupViewModel(this._env, this._installer);

  final EnvironmentProbe _env;
  final EnvironmentInstaller _installer;

  CheckStatus pi = CheckStatus.checking;
  CheckStatus extension = CheckStatus.checking;
  CheckStatus supervisor = CheckStatus.checking;

  bool _disposed = false;

  /// O trio satisfeito → habilita criar o agente.
  bool get agentReady =>
      pi.satisfied && extension.satisfied && supervisor.satisfied;

  /// Roda as 3 ao abrir o checklist do agente.
  Future<void> recheckAll() async {
    await Future.wait([recheckPi(), recheckExtension(), recheckSupervisor()]);
  }

  Future<void> recheckPi() => _run(
    (s) => pi = s,
    () async => await _env.piInstalled() ? CheckStatus.ok : CheckStatus.missing,
  );

  Future<void> recheckExtension() => _run(
    (s) => extension = s,
    () async =>
        await _env.extensionInstalled() ? CheckStatus.ok : CheckStatus.missing,
  );

  Future<void> recheckSupervisor() => _run(
    (s) => supervisor = s,
    () async =>
        await _env.supervisorInstalled() ? CheckStatus.ok : CheckStatus.missing,
  );

  /// Botão "Instalar" do passo da extensão: roda `pi install npm:remote-pi` e,
  /// em caso de sucesso, re-checa a extensão (e o supervisor, agora possível).
  Future<InstallResult> installExtension() async {
    final result = await _installer.installExtension();
    if (result.ok) {
      await recheckExtension();
      await recheckSupervisor();
    }
    return result;
  }

  /// Botão "Instalar" do passo do supervisor: roda o instalador via `node` e,
  /// em caso de sucesso, re-checa o supervisor.
  Future<InstallResult> installSupervisor() async {
    final result = await _installer.installSupervisor();
    if (result.ok) await recheckSupervisor();
    return result;
  }

  /// Marca o passo como `checking`, roda [probe], grava o resultado. Resolve um
  /// `bool`/`CheckStatus` de forma uniforme.
  Future<void> _run(
    void Function(CheckStatus) set,
    Future<CheckStatus> Function() probe,
  ) async {
    set(CheckStatus.checking);
    _safeNotify();
    final result = await probe();
    set(result);
    _safeNotify();
  }

  void _safeNotify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
