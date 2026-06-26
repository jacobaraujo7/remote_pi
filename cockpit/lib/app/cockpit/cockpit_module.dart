import 'dart:io';

import 'package:cockpit/app/cockpit/data/filesystem/app_launcher_impl.dart';
import 'package:cockpit/app/cockpit/data/filesystem/file_reader_impl.dart';
import 'package:cockpit/app/cockpit/data/filesystem/file_searcher_impl.dart';
import 'package:cockpit/app/cockpit/data/filesystem/file_system_mutator_impl.dart';
import 'package:cockpit/app/cockpit/data/filesystem/file_system_reader_impl.dart';
import 'package:cockpit/app/cockpit/data/filesystem/folder_lister_impl.dart';
import 'package:cockpit/app/cockpit/data/filesystem/git_status_reader_impl.dart';
import 'package:cockpit/app/cockpit/data/filesystem/session_history_impl.dart';
import 'package:cockpit/app/cockpit/data/filesystem/worktree_manager_impl.dart';
import 'package:cockpit/app/cockpit/data/notifications/local_notifier.dart';
import 'package:cockpit/app/cockpit/data/repositories/hive_dismissed_update_store.dart';
import 'package:cockpit/app/cockpit/data/repositories/hive_project_repository.dart';
import 'package:cockpit/app/cockpit/data/repositories/hive_workspace_layout_store.dart';
import 'package:cockpit/app/cockpit/data/rpc/pi_rpc_process_factory.dart';
import 'package:cockpit/app/cockpit/data/setup/environment_installer_impl.dart';
import 'package:cockpit/app/cockpit/data/setup/environment_probe_impl.dart';
import 'package:cockpit/app/cockpit/data/setup/system_permissions_impl.dart';
import 'package:cockpit/app/cockpit/data/terminal/pty_terminal_gateway_factory.dart';
import 'package:cockpit/app/cockpit/data/update/update_checker_impl.dart';
import 'package:cockpit/app/cockpit/data/update/url_opener_impl.dart';
import 'package:cockpit/app/cockpit/domain/contracts/app_launcher.dart';
import 'package:cockpit/app/cockpit/domain/contracts/dismissed_update_store.dart';
import 'package:cockpit/app/cockpit/domain/contracts/environment_installer.dart';
import 'package:cockpit/app/cockpit/domain/contracts/environment_probe.dart';
import 'package:cockpit/app/cockpit/domain/contracts/file_reader.dart';
import 'package:cockpit/app/cockpit/domain/contracts/file_searcher.dart';
import 'package:cockpit/app/cockpit/domain/contracts/file_system_mutator.dart';
import 'package:cockpit/app/cockpit/domain/contracts/file_system_reader.dart';
import 'package:cockpit/app/cockpit/domain/contracts/folder_lister.dart';
import 'package:cockpit/app/cockpit/domain/contracts/git_status_reader.dart';
import 'package:cockpit/app/cockpit/domain/contracts/notifier.dart';
import 'package:cockpit/app/cockpit/domain/contracts/project_repository.dart';
import 'package:cockpit/app/cockpit/domain/contracts/rpc_gateway_factory.dart';
import 'package:cockpit/app/cockpit/domain/contracts/session_history.dart';
import 'package:cockpit/app/cockpit/domain/contracts/system_permissions.dart';
import 'package:cockpit/app/cockpit/domain/contracts/terminal_gateway_factory.dart';
import 'package:cockpit/app/cockpit/domain/contracts/update_checker.dart';
import 'package:cockpit/app/cockpit/domain/contracts/url_opener.dart';
import 'package:cockpit/app/cockpit/domain/contracts/workspace_layout_store.dart';
import 'package:cockpit/app/cockpit/domain/contracts/worktree_manager.dart';
import 'package:cockpit/app/cockpit/domain/value_objects/update_target.dart';
import 'package:cockpit/app/cockpit/ui/cockpit_page.dart';
import 'package:cockpit/app/cockpit/ui/viewmodels/cockpit_viewmodel.dart';
import 'package:cockpit/app/cockpit/ui/viewmodels/setup_viewmodel.dart';
import 'package:cockpit/app/cockpit/ui/viewmodels/update_viewmodel.dart';
import 'package:cockpit/app/core/data/repositories/hive_settings_store.dart';
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter_modular/flutter_modular.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:package_info_plus/package_info_plus.dart';

/// Feature **Cockpit** — o shell (home, `path: '/'`). Registra os binds de infra
/// do shell (filesystem, RPC, terminal, repos, setup, update) e declara a rota
/// `/` com os 3 ViewModels page-scoped.
///
/// **Bootstrap async (idioma do flutter_modular):** o builder é `Future` e abre
/// as PRÓPRIAS dependências assíncronas — Hive boxes, versão do app, notifier —
/// capturando-as no closure (box privada → `addInstance(HiveX(box))`). Assim o
/// `main` não threada esses valores: chame UMA vez e componha o módulo retornado
/// (dedup é por identidade).
///
/// **Resolução cross-module (flutter_modular >= 7.1.0):** os binds que dependem
/// do `PiSpawnConfig` usam `.new` e resolvem o config **upward** do core
/// (root-owned) — por isso o builder não recebe mais `config`. As Hive boxes,
/// porém, continuam exigindo o bootstrap async acima (não há async bind).
///
/// Como o shell fica em `/` e o Settings é **empilhado** por cima (não substitui),
/// a rota `/` nunca deixa a pilha em navegação normal → estes binds
/// feature-scoped vivem o app inteiro na prática.
Future<Module> buildCockpitModule() async {
  // Bootstrap async: abre as próprias boxes (privadas no closure), resolve a
  // versão e inicia o notifier. `Hive.initFlutter` já rodou no `main`.
  final projectBox = await Hive.openBox<dynamic>(HiveProjectRepository.boxName);
  final layoutBox = await Hive.openBox<dynamic>(
    HiveWorkspaceLayoutStore.boxName,
  );
  // Updates dispensados moram na box de settings (mesma do SettingsController);
  // `openBox` é idempotente → devolve a instância já aberta pelo `main`.
  final settingsBox = await Hive.openBox<dynamic>(HiveSettingsStore.boxName);
  final appVersion = (await PackageInfo.fromPlatform()).version;

  // Notificações do SO — init pede permissão; falha não pode derrubar o boot.
  final notifier = LocalNotifier();
  try {
    await notifier.init();
  } catch (error) {
    debugPrint('Falha ao iniciar notificações: $error');
  }

  return createModule(
    path: '/',
    register: (c) {
      c
        ..addInstance<ProjectRepository>(HiveProjectRepository(projectBox))
        ..addInstance<WorkspaceLayoutStore>(HiveWorkspaceLayoutStore(layoutBox))
        ..addInstance<DismissedUpdateStore>(
          HiveDismissedUpdateStore(settingsBox),
        )
        // Dependem do PiSpawnConfig → `.new` resolve upward do core (>= 7.1.0).
        ..addLazySingleton<RpcGatewayFactory>(PiRpcProcessFactory.new)
        ..addLazySingleton<EnvironmentProbe>(EnvironmentProbeImpl.new)
        ..addLazySingleton<EnvironmentInstaller>(EnvironmentInstallerImpl.new)
        ..addInstance<FolderLister>(const FolderListerImpl())
        ..addInstance<FileSystemReader>(const FileSystemReaderImpl())
        ..addInstance<FileSystemMutator>(const FileSystemMutatorImpl())
        ..addInstance<FileReader>(const FileReaderImpl())
        ..addInstance<FileSearcher>(FileSearcherImpl())
        ..addInstance<GitStatusReader>(GitStatusReaderImpl())
        ..addInstance<WorktreeManager>(WorktreeManagerImpl())
        ..addInstance<SessionHistory>(const SessionHistoryImpl())
        ..addInstance<TerminalGatewayFactory>(const PtyTerminalGatewayFactory())
        ..addInstance<AppLauncherGateway>(const AppLauncherImpl())
        ..addInstance<SystemPermissions>(SystemPermissionsImpl())
        ..addInstance<Notifier>(notifier)
        ..addInstance<UpdateChecker>(const UpdateCheckerImpl())
        ..addInstance<UrlOpener>(const UrlOpenerImpl())
        ..addInstance<UpdateTarget>(_updateTarget(appVersion))
        ..route(
          '/',
          // ViewModels page-scoped via tear-off `.new` → o auto_injector resolve
          // o construtor a partir dos binds acima. Os `init()`/`check()` (que
          // antes encadeavam no factory) agora rodam no `CockpitPage.initState`.
          provide: (s) => s
            ..addChangeNotifier<CockpitViewModel>(CockpitViewModel.new)
            ..addChangeNotifier<SetupViewModel>(SetupViewModel.new)
            ..addChangeNotifier<UpdateViewModel>(UpdateViewModel.new),
          child: (context, state) => const CockpitPage(),
        );
    },
  );
}

/// [UpdateTarget] da máquina atual: versão do app + plataforma/formato/arch do
/// manifest. macOS → dmg/universal; Windows → exe/x64; Linux → deb/(arm64|x64).
UpdateTarget _updateTarget(String version) {
  if (Platform.isMacOS) {
    return UpdateTarget(
      version: version,
      platform: 'macos',
      format: 'dmg',
      arch: 'universal',
    );
  }
  if (Platform.isWindows) {
    return UpdateTarget(
      version: version,
      platform: 'windows',
      format: 'exe',
      arch: 'x64',
    );
  }
  final arch = Platform.version.toLowerCase().contains('arm') ? 'arm64' : 'x64';
  return UpdateTarget(
    version: version,
    platform: 'linux',
    format: 'deb',
    arch: arch,
  );
}
