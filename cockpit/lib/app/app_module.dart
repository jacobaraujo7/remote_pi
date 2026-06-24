import 'package:cockpit/app/cockpit/cockpit_module.dart';
import 'package:cockpit/app/core/core_module.dart';
import 'package:cockpit/app/core/env.dart';
import 'package:cockpit/app/settings/settings_module.dart';
import 'package:flutter_modular/flutter_modular.dart';

/// Módulo raiz — **só composição**. É o mapa de acoplamento do app: quais módulos
/// existem e como se conectam. Cada submódulo declara seu próprio `path` (ou a
/// ausência dele, no caso do core), então aqui é só `module(...)`.
///
/// `Future` porque o `cockpit` faz bootstrap async (abre as próprias Hive boxes).
/// O único valor threadado é o [PiSpawnConfig]: mora no core (root-owned) e as
/// features o resolvem **upward**; os demais async (boxes/versão/notifier) cada
/// builder resolve sozinho. Construído **uma vez** no `main` — dedup por
/// identidade preservado.
Future<Module> buildAppModule({required PiSpawnConfig config}) async {
  final core = buildCoreModule(config: config);
  final cockpit = await buildCockpitModule();
  final settings = buildSettingsModule();
  return createModule(
    register: (c) => c
      ..module(core)
      ..module(cockpit)
      ..module(settings),
  );
}
