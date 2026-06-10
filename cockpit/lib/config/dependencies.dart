import 'package:cockpit/config/env.dart';
import 'package:cockpit/config/utils/injector.dart';
import 'package:cockpit/data/filesystem/app_launcher_impl.dart';
import 'package:cockpit/data/filesystem/file_reader_impl.dart';
import 'package:cockpit/data/filesystem/file_searcher_impl.dart';
import 'package:cockpit/data/filesystem/file_system_reader_impl.dart';
import 'package:cockpit/data/filesystem/git_status_reader_impl.dart';
import 'package:cockpit/data/filesystem/worktree_manager_impl.dart';
import 'package:cockpit/data/filesystem/folder_lister_impl.dart';
import 'package:cockpit/data/filesystem/session_history_impl.dart';
import 'package:cockpit/data/daemon/supervisor_client_impl.dart';
import 'package:cockpit/data/notifications/local_notifier.dart';
import 'package:cockpit/data/relay/pairing_gateway_impl.dart';
import 'package:cockpit/data/relay/relay_gateway_impl.dart';
import 'package:cockpit/data/relay/revoke_gateway_impl.dart';
import 'package:cockpit/data/repositories/hive_project_repository.dart';
import 'package:cockpit/data/repositories/hive_settings_store.dart';
import 'package:cockpit/data/repositories/hive_workspace_layout_store.dart';
import 'package:cockpit/data/rpc/pi_process_registry.dart';
import 'package:cockpit/data/rpc/pi_rpc_process_factory.dart';
import 'package:cockpit/data/setup/environment_installer_impl.dart';
import 'package:cockpit/data/setup/environment_probe_impl.dart';
import 'package:cockpit/data/setup/system_permissions_impl.dart';
import 'package:cockpit/data/terminal/pty_terminal_gateway_factory.dart';
import 'package:cockpit/domain/contracts/app_launcher.dart';
import 'package:cockpit/domain/contracts/file_reader.dart';
import 'package:cockpit/domain/contracts/file_searcher.dart';
import 'package:cockpit/domain/contracts/file_system_reader.dart';
import 'package:cockpit/domain/contracts/folder_lister.dart';
import 'package:cockpit/domain/contracts/git_status_reader.dart';
import 'package:cockpit/domain/contracts/worktree_manager.dart';
import 'package:cockpit/domain/contracts/environment_installer.dart';
import 'package:cockpit/domain/contracts/environment_probe.dart';
import 'package:cockpit/domain/contracts/cron_gateway.dart';
import 'package:cockpit/domain/contracts/daemon_supervisor.dart';
import 'package:cockpit/domain/contracts/notifier.dart';
import 'package:cockpit/domain/contracts/project_repository.dart';
import 'package:cockpit/domain/contracts/relay_gateway.dart';
import 'package:cockpit/domain/contracts/system_permissions.dart';
import 'package:cockpit/domain/contracts/rpc_gateway_factory.dart';
import 'package:cockpit/domain/contracts/session_history.dart';
import 'package:cockpit/domain/contracts/settings_store.dart';
import 'package:cockpit/domain/contracts/terminal_gateway_factory.dart';
import 'package:cockpit/domain/contracts/workspace_layout_store.dart';
import 'package:flutter/foundation.dart';
import 'package:cockpit/ui/cockpit/viewmodels/cockpit_viewmodel.dart';
import 'package:cockpit/ui/cockpit/viewmodels/setup_viewmodel.dart';
import 'package:cockpit/ui/settings/connectivity_viewmodel.dart';
import 'package:cockpit/ui/settings/cron_viewmodel.dart';
import 'package:cockpit/ui/settings/daemons_viewmodel.dart';
import 'package:cockpit/ui/settings/settings_controller.dart';
import 'package:hive_flutter/hive_flutter.dart';

final CustomInjector _injector = CustomInjector();

/// Acesso direto ao injector — só para bootstrap e composição de rotas.
CustomInjector get injector => _injector;

/// Inicializa Hive e registra as dependências. Chamado uma vez no `main`.
Future<void> setupDependencies() async {
  // Mata processos `pi --mode rpc` órfãos do ciclo anterior antes de qualquer
  // novo spawn. Cobre hot restart (main() re-executa mas Process.start não mata
  // os filhos) e cold restart com crash (processo morre, filhos ficam órfãos).
  await PiProcessRegistry.cleanOrphans();

  // Subdiretório próprio (evita poluir a raiz de ~/Documents).
  await Hive.initFlutter('cockpit');
  final box = await Hive.openBox<dynamic>(HiveProjectRepository.boxName);
  final layoutBox = await Hive.openBox<dynamic>(
    HiveWorkspaceLayoutStore.boxName,
  );
  final settingsBox = await Hive.openBox<dynamic>(HiveSettingsStore.boxName);

  final config = await PiSpawnConfig.resolve();

  _injector.addInstance<PiSpawnConfig>(config);
  _injector.addInstance<ProjectRepository>(HiveProjectRepository(box));
  _injector.addInstance<WorkspaceLayoutStore>(
    HiveWorkspaceLayoutStore(layoutBox),
  );
  _injector.addInstance<SettingsStore>(HiveSettingsStore(settingsBox));
  _injector.addInstance<FolderLister>(const FolderListerImpl());
  _injector.addInstance<FileSystemReader>(const FileSystemReaderImpl());
  _injector.addInstance<FileReader>(const FileReaderImpl());
  _injector.addInstance<FileSearcher>(FileSearcherImpl());
  _injector.addInstance<GitStatusReader>(GitStatusReaderImpl());
  _injector.addInstance<WorktreeManager>(WorktreeManagerImpl());
  _injector.addInstance<SessionHistory>(const SessionHistoryImpl());
  _injector.addInstance<RpcGatewayFactory>(PiRpcProcessFactory(config));
  _injector.addInstance<TerminalGatewayFactory>(
    const PtyTerminalGatewayFactory(),
  );
  _injector.addInstance<AppLauncherGateway>(const AppLauncherImpl());

  // Onboarding: checagens de ambiente + permissões do SO + instaladores.
  _injector.addInstance<EnvironmentProbe>(EnvironmentProbeImpl(config));
  _injector.addInstance<EnvironmentInstaller>(EnvironmentInstallerImpl(config));
  _injector.addInstance<SystemPermissions>(SystemPermissionsImpl());

  // Conectividade: relay global + aparelhos pareados (shell-out do `remote-pi`).
  _injector.addInstance<RelayGateway>(RelayGatewayImpl());

  // Daemon Agents + Agendamentos (cron): mesmo control-plane UDS do
  // `pi-supervisord` → uma instância sob os dois contratos.
  final supervisorClient = SupervisorClientImpl();
  _injector.addInstance<DaemonSupervisor>(supervisorClient);
  _injector.addInstance<CronGateway>(supervisorClient);

  // Notificações do SO — inicializa (pede permissão). Falha de init não pode
  // derrubar o boot do app.
  final notifier = LocalNotifier();
  try {
    await notifier.init();
  } catch (error) {
    debugPrint('Falha ao iniciar notificações: $error');
  }
  _injector.addInstance<Notifier>(notifier);

  _injector.commit();
}

/// Constrói o ViewModel do shell. Criado pela rota (provider é dono do ciclo de
/// vida → `dispose` mata as sessões/processos vivos).
CockpitViewModel buildCockpitViewModel() {
  return CockpitViewModel(
    _injector.get<ProjectRepository>(),
    _injector.get<RpcGatewayFactory>(),
    _injector.get<FolderLister>(),
    _injector.get<SessionHistory>(),
    _injector.get<Notifier>(),
    _injector.get<FileSystemReader>(),
    _injector.get<TerminalGatewayFactory>(),
    _injector.get<FileReader>(),
    _injector.get<WorkspaceLayoutStore>(),
    _injector.get<GitStatusReader>(),
    _injector.get<FileSearcher>(),
    _injector.get<AppLauncherGateway>(),
    _injector.get<WorktreeManager>(),
  );
}

/// ViewModel da tela de onboarding (checagens de ambiente/permissão).
SetupViewModel buildSetupViewModel() {
  return SetupViewModel(
    _injector.get<EnvironmentProbe>(),
    _injector.get<SystemPermissions>(),
    _injector.get<EnvironmentInstaller>(),
  );
}

/// Controller global de preferências (tema/fonte/syntax). Vive acima do
/// `MaterialApp`; criado uma vez no boot.
SettingsController buildSettingsController() {
  return SettingsController(_injector.get<SettingsStore>());
}

/// ViewModel da aba Conectividade das Configurações (relay + aparelhos +
/// pareamento). Criado pela rota `/settings`; carrega sob demanda quando a aba
/// abre. Recebe a factory de [PairingGateway] — cada dialog de pareamento sobe
/// um `pi --mode rpc` efêmero próprio.
ConnectivityViewModel buildConnectivityViewModel() {
  return ConnectivityViewModel(
    _injector.get<RelayGateway>(),
    () => PairingGatewayImpl(_injector.get<PiSpawnConfig>()),
    () => RevokeGatewayImpl(_injector.get<PiSpawnConfig>()),
  );
}

/// ViewModel da aba Daemon Agents das Configurações (agentes 24/7). Criado pela
/// rota `/settings`; carrega sob demanda quando a aba abre.
DaemonsViewModel buildDaemonsViewModel() {
  return DaemonsViewModel(_injector.get<DaemonSupervisor>());
}

/// ViewModel da aba Agendamentos (cron). Usa o [CronGateway] + a lista de
/// daemons (nomes + dropdown). Criado pela rota `/settings`.
CronViewModel buildCronViewModel() {
  return CronViewModel(
    _injector.get<CronGateway>(),
    _injector.get<DaemonSupervisor>(),
  );
}
