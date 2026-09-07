import 'package:cockpit/app/cockpit/cockpit_module.dart';
import 'package:cockpit/app/core/core_module.dart';
import 'package:cockpit/app/core/data/terminal/terminal_profile_resolver_impl.dart';
import 'package:cockpit/app/core/env.dart';
import 'package:cockpit/app/core/ui/window_activity_controller.dart';
import 'package:cockpit/app/settings/settings_module.dart';
import 'package:flutter_modular/flutter_modular.dart';

/// Módulo raiz — **só composição**. É o mapa de acoplamento do app: quais módulos
/// existem e como se conectam. Cada submódulo declara seu próprio `path` (ou a
/// ausência dele, no caso do core), então aqui é só `module(...)`.
///
/// `Future` porque o `cockpit` faz bootstrap async (abre os próprios stores JSON).
/// Os valores threadados são o [PiSpawnConfig] e o resolver de perfis de
/// terminal: ambos moram no core (root-owned) e as features os resolvem
/// **upward**; os demais async (boxes/versão/notifier) cada builder resolve
/// sozinho. Construído **uma vez** no `main` — dedup por identidade preservado.
Future<Module> buildAppModule({
  required PiSpawnConfig config,
  required WindowActivityController windowActivity,
  List<String> customShellPaths = const [],
}) async {
  // Plano 50: descobre os perfis de terminal e injeta a instância **já
  // aquecida** — o `+` resolve o padrão de forma síncrona ao criar a aba. Aqui
  // (e não no `core_module`) porque `register` é síncrono e não há bind async;
  // este builder já é `Future`. Precisa ser `addInstance` (não `.new`): o cache
  // é por instância, e um lazySingleton nasceria frio. `discover()` nunca lança.
  //
  // `customShellPaths`: shells em caminhos fora do padrão (ex.: fish num prefix
  // Homebrew personalizado) persistidos em `AppSettings`. Passados aqui para
  // que já estejam no cache aquecido — o usuário não precisa fechar e reabrir o
  // app após adicionar um shell nas configurações do boot anterior.
  final terminalProfiles = TerminalProfileResolverImpl(
    customPaths: customShellPaths.isEmpty ? null : customShellPaths,
  );
  await terminalProfiles.discover();

  final core = buildCoreModule(
    config: config,
    terminalProfiles: terminalProfiles,
  );
  final cockpit = await buildCockpitModule(windowActivity: windowActivity);
  final settings = buildSettingsModule();
  return createModule(
    register: (c) => c
      ..module(core)
      ..module(cockpit)
      ..module(settings),
  );
}
