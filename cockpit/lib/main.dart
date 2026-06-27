import 'dart:async';
import 'dart:io';

import 'package:cockpit/app/app_module.dart';
import 'package:cockpit/app/app_widget.dart';
import 'package:cockpit/app/cockpit/data/rpc/pi_process_registry.dart';
import 'package:cockpit/app/core/data/lsp/lsp_process_registry.dart';
import 'package:cockpit/app/core/data/repositories/hive_settings_store.dart';
import 'package:cockpit/app/core/env.dart';
import 'package:cockpit/app/core/ui/settings_controller.dart';
import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter_modular/flutter_modular.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:media_kit/media_kit.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';
import 'package:window_manager/window_manager.dart';

/// Subdiretório raiz das boxes do Hive. Em debug usa `cockpit-debug` para não
/// colidir com as boxes da build de produção (que costuma ficar aberta em
/// paralelo durante o desenvolvimento). Todas as boxes — inclusive a
/// `window_state` — herdam esse diretório via `Hive.initFlutter`.
const String hiveSubdir = kDebugMode ? 'cockpit-debug' : 'cockpit';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Plano 46 — inicializa o media_kit (libmpv) antes de qualquer Player.
  MediaKit.ensureInitialized();

  // Mata processos `pi --mode rpc` e language servers (LSP) órfãos do ciclo
  // anterior antes de qualquer novo spawn (cobre hot restart e cold restart
  // com crash).
  await PiProcessRegistry.cleanOrphans();
  await LspProcessRegistry.cleanOrphans();

  // Subdiretório próprio; em debug separado da build de produção. As boxes das
  // features são abertas pelos próprios builders async (ver buildCockpitModule);
  // aqui só a de settings, que o SettingsController precisa antes do 1º frame.
  await Hive.initFlutter(hiveSubdir);
  final settingsBox = await Hive.openBox<dynamic>(HiveSettingsStore.boxName);

  // Preferências carregadas ANTES do primeiro frame → o app já abre no tema
  // salvo (sem flash). App-scoped: provido via `ModularApp.provide`, acima do
  // `ShadcnApp` → trocar tema/fonte repinta tudo.
  final settings = SettingsController(HiveSettingsStore(settingsBox));
  await settings.load();

  final winBox = await Hive.openBox<dynamic>('window_state');
  await _setupWindow(winBox);

  // Único valor threadado: mora no core (root-owned) e as features o resolvem
  // upward. O módulo é `Future` porque o cockpit abre as próprias boxes.
  final config = await PiSpawnConfig.resolve();
  final appModule = await buildAppModule(config: config);

  runApp(
    _WindowStateKeeper(
      box: winBox,
      child: ModularApp(
        module: appModule,
        provide: (s) => s.addChangeNotifier<SettingsController>(() => settings),
        child: const AppRoot(),
      ),
    ),
  );
}

/// Esconde a barra nativa e restaura o último tamanho da janela.
Future<void> _setupWindow(Box<dynamic> winBox) async {
  if (!(Platform.isMacOS || Platform.isWindows || Platform.isLinux)) return;
  await windowManager.ensureInitialized();
  final w = (winBox.get('width') as num?)?.toDouble() ?? 1280;
  final h = (winBox.get('height') as num?)?.toDouble() ?? 720;
  final options = WindowOptions(
    titleBarStyle: TitleBarStyle.hidden,
    windowButtonVisibility: false,
    minimumSize: const Size(720, 480),
    size: Size(w, h),
  );
  await windowManager.waitUntilReadyToShow(options, () async {
    await windowManager.show();
    await windowManager.focus();
  });
}

/// Ouve redimensionamentos e persiste o tamanho da janela com debounce.
class _WindowStateKeeper extends StatefulWidget {
  const _WindowStateKeeper({required this.box, required this.child});
  final Box<dynamic> box;
  final Widget child;

  @override
  State<_WindowStateKeeper> createState() => _WindowStateKeeperState();
}

class _WindowStateKeeperState extends State<_WindowStateKeeper>
    with WindowListener {
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    windowManager.addListener(this);
  }

  @override
  void dispose() {
    windowManager.removeListener(this);
    _debounce?.cancel();
    super.dispose();
  }

  @override
  void onWindowResize() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 400), () async {
      final size = await windowManager.getSize();
      await widget.box.put('width', size.width);
      await widget.box.put('height', size.height);
    });
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
