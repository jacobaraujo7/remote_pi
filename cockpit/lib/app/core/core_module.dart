import 'package:cockpit/app/core/data/lsp/lsp_client_impl.dart';
import 'package:cockpit/app/core/data/lsp/lsp_server_pool.dart';
import 'package:cockpit/app/core/data/relay/pairing_gateway_impl.dart';
import 'package:cockpit/app/core/data/relay/revoke_gateway_impl.dart';
import 'package:cockpit/app/core/data/setup/environment_probe_impl.dart';
import 'package:cockpit/app/core/data/setup/system_permissions_impl.dart';
import 'package:cockpit/app/core/domain/contracts/environment_probe.dart';
import 'package:cockpit/app/core/domain/contracts/lsp_client.dart';
import 'package:cockpit/app/core/domain/contracts/pairing_gateway.dart';
import 'package:cockpit/app/core/domain/contracts/revoke_gateway.dart';
import 'package:cockpit/app/core/domain/contracts/system_permissions.dart';
import 'package:cockpit/app/core/env.dart';
import 'package:flutter_modular/flutter_modular.dart';

/// Kernel transversal — módulo **sem `path`** → binds root-owned (vivem o app
/// inteiro, nunca descartados em navegação).
///
/// Mora aqui o que é compartilhado **e** o que precisa resolver outro bind do
/// core pelo construtor: um bind de **feature** (módulo com `path`) não enxerga o
/// core na resolução do `auto_injector` — só o `provide` page-scoped e o próprio
/// core enxergam. Por isso:
///
/// - [PiSpawnConfig]: o cockpit injeta para spawnar `pi --mode rpc`; o settings,
///   para o `pi` efêmero de pareamento/revoke.
/// - [PairingGatewayFactory] / [RevokeGatewayFactory]: criam um `pi --mode rpc`
///   efêmero por dialog e recebem o [PiSpawnConfig] no construtor. Root-owned
///   aqui, resolvem o config (mesmo escopo) e ficam visíveis ao
///   `ConnectivityViewModel` (page-scoped) da feature settings.
///
/// O `SettingsStore`/`SettingsController` são **app-scoped** (construídos no
/// `main`, antes do 1º frame → sem flash de tema), então não entram no grafo aqui.
///
/// - [LspServerPool]: pool **global** de language servers (LSP), compartilhado
///   por todos os workspaces. Root-owned aqui; o `CockpitViewModel` (page-scoped)
///   o injeta para abrir documentos e rotear diagnostics ao editor.
///
/// - [EnvironmentProbe] / [SystemPermissions]: compartilhados pelas duas
///   features — o cockpit usa no checklist do agente (`SetupViewModel`) e o
///   settings para ocultar abas remotas até o ambiente estar instalado e para a
///   aba de Notificações. [EnvironmentProbeImpl] resolve o [PiSpawnConfig] daqui.
Module buildCoreModule({required PiSpawnConfig config}) => createModule(
  register: (c) => c
    ..addInstance<PiSpawnConfig>(config)
    ..addInstance<LspClientFactory>(const LspClientFactoryImpl())
    ..addLazySingleton<LspServerPool>(LspServerPool.new)
    ..add<PairingGatewayFactory>(PairingGatewayFactoryImpl.new)
    ..add<RevokeGatewayFactory>(RevokeGatewayFactoryImpl.new)
    ..addLazySingleton<EnvironmentProbe>(EnvironmentProbeImpl.new)
    ..addInstance<SystemPermissions>(SystemPermissionsImpl()),
);
