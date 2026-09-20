import 'package:cockpit/app/core/data/automation/cli_automation_gateway.dart';
import 'package:cockpit/app/core/data/lsp/lsp_client_impl.dart';
import 'package:cockpit/app/core/data/lsp/lsp_server_pool.dart';
import 'package:cockpit/app/core/data/neovim/neovim_gateway_impl.dart';
import 'package:cockpit/app/core/data/setup/system_permissions_impl.dart';
import 'package:cockpit/app/core/domain/contracts/lsp_client.dart';
import 'package:cockpit/app/core/domain/contracts/neovim_gateway.dart';
import 'package:cockpit/app/core/domain/contracts/system_permissions.dart';
import 'package:cockpit/app/core/domain/contracts/terminal_profile_resolver.dart';
import 'package:cockpit/app/core/ui/automation_controller.dart';
import 'package:flutter_modular/flutter_modular.dart';

/// Kernel transversal — módulo **sem `path`** → binds root-owned (vivem o app
/// inteiro, nunca descartados em navegação).
///
/// Mora aqui o que é compartilhado por 2+ features.
///
/// O `SettingsStore`/`SettingsController` são **app-scoped** (construídos no
/// `main`, antes do 1º frame → sem flash de tema), então não entram no grafo aqui.
///
/// - [LspServerPool]: pool **global** de language servers (LSP), compartilhado
///   por todos os workspaces. Root-owned aqui; o `CockpitViewModel` (page-scoped)
///   o injeta para abrir documentos e rotear diagnostics ao editor.
///
/// - [AutomationController]: descoberta e execução app-scoped dos harnesses CLI
///   usados por Settings e Source Control.
///
/// - [SystemPermissions]: permissões do SO (notificações), usado pela aba de
///   Notificações do settings.
///
/// - [TerminalProfileResolver]: descoberta dos shells disponíveis (plano 50).
///   Compartilhado — o cockpit resolve o perfil ao abrir uma aba (o `+` e seu
///   seletor) e o settings lista os perfis para escolher o padrão. Chega **já
///   aquecido** do `buildAppModule` (a descoberta é async; `register` não é).
Module buildCoreModule({required TerminalProfileResolver terminalProfiles}) {
  const lspFactory = LspClientFactoryImpl();
  final automation = AutomationController(CliAutomationGateway());
  return createModule(
    register: (c) => c
      ..addInstance<TerminalProfileResolver>(terminalProfiles)
      ..addInstance<LspClientFactory>(lspFactory)
      ..addInstance<AutomationController>(automation)
      ..addLazySingleton<NeovimGateway>(NeovimGatewayImpl.new)
      ..addLazySingleton<LspServerPool>(LspServerPool.new)
      ..addInstance<SystemPermissions>(SystemPermissionsImpl()),
  );
}
