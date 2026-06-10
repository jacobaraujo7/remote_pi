import 'package:cockpit/domain/contracts/environment_installer.dart';
import 'package:cockpit/domain/contracts/environment_probe.dart';
import 'package:cockpit/domain/contracts/system_permissions.dart';
import 'package:cockpit/domain/entities/install_result.dart';
import 'package:cockpit/domain/entities/setup_check.dart';
import 'package:flutter/foundation.dart';

/// Estado das 5 checagens de onboarding + ações de re-checagem/solicitação.
///
/// Gate de "Criar Workspace" = [canCreate] (todas satisfeitas; `notApplicable`
/// conta como satisfeita). Os passos de instalação são re-checados sob demanda
/// (botão por passo); os de permissão também são re-checados automaticamente
/// quando a janela volta a ter foco (a view chama [recheckPermissions]).
class SetupViewModel extends ChangeNotifier {
  SetupViewModel(this._env, this._perms, this._installer);

  final EnvironmentProbe _env;
  final SystemPermissions _perms;
  final EnvironmentInstaller _installer;

  CheckStatus pi = CheckStatus.checking;
  CheckStatus extension = CheckStatus.checking;
  CheckStatus supervisor = CheckStatus.checking;
  CheckStatus notifications = CheckStatus.checking;

  bool _disposed = false;

  /// Todas as checagens satisfeitas → habilita "Criar Workspace".
  bool get canCreate =>
      pi.satisfied &&
      extension.satisfied &&
      supervisor.satisfied &&
      notifications.satisfied;

  /// Roda as 5 ao montar a tela.
  Future<void> recheckAll() async {
    await Future.wait([
      recheckPi(),
      recheckExtension(),
      recheckSupervisor(),
      recheckPermissions(),
    ]);
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

  Future<void> recheckNotifications() =>
      _run((s) => notifications = s, _perms.notificationStatus);

  /// Re-checa as permissões (chamado no foco da janela). Hoje só notificações.
  Future<void> recheckPermissions() => recheckNotifications();

  /// Botão "Testar" das notificações: pede permissão + dispara uma de teste.
  Future<void> requestNotifications() =>
      _run((s) => notifications = s, _perms.requestNotifications);

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
