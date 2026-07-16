import 'package:cockpit/app/cockpit/cockpit_module.dart';
import 'package:cockpit/app/core/core_module.dart';
import 'package:cockpit/app/core/data/terminal/terminal_profile_resolver_impl.dart';
import 'package:cockpit/app/core/env.dart';
import 'package:cockpit/app/settings/settings_module.dart';
import 'package:flutter_modular/flutter_modular.dart';

/// Módulo raiz — **só composição**. É o mapa de acoplamento do app: quais módulos
/// existem e como se conectam. Cada submódulo declara seu próprio `path` (ou a
/// ausência dele, no caso do core), então aqui é só `module(...)`.
///
/// `Future` porque o `cockpit` faz bootstrap async (abre as próprias Hive boxes).
/// Os valores threadados são o [PiSpawnConfig] e o resolver de perfis de
/// terminal: ambos moram no core (root-owned) e as features os resolvem
/// **upward**; os demais async (boxes/versão/notifier) cada builder resolve
/// sozinho. Construído **uma vez** no `main` — dedup por identidade preservado.
Future<Module> buildAppModule({required PiSpawnConfig config}) async {
  // Plano 50: descobre os perfis de terminal e injeta a instância **já
  // aquecida** — o `+` resolve o padrão de forma síncrona ao criar a aba. Aqui
  // (e não no `core_module`) porque `register` é síncrono e não há bind async;
  // este builder já é `Future`. Precisa ser `addInstance` (não `.new`): o cache
  // é por instância, e um lazySingleton nasceria frio. `discover()` nunca lança.
  final terminalProfiles = TerminalProfileResolverImpl();
  await terminalProfiles.discover();

  final core = buildCoreModule(config: config, terminalProfiles: terminalProfiles);
  final cockpit = await buildCockpitModule();
  final settings = buildSettingsModule();
  return createModule(
    register: (c) => c
      ..module(core)
      ..module(cockpit)
      ..module(settings),
  );
}
