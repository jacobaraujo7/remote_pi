import 'dart:async';
import 'dart:io' show Platform;

import 'package:cockpit/app/app_module.dart';
import 'package:cockpit/app/app_widget.dart';
import 'package:cockpit/app/cockpit/data/hooks/claude_hook_installer_impl.dart';
import 'package:cockpit/app/cockpit/data/rpc/pi_process_registry.dart';
import 'package:cockpit/app/cockpit/data/tasks/task_process_registry.dart';
import 'package:cockpit/app/core/data/lsp/lsp_process_registry.dart';
import 'package:cockpit/app/core/data/repositories/hive_settings_store.dart';
import 'package:cockpit/app/core/data/setup/storage_location.dart';
import 'package:cockpit/app/core/domain/entities/app_settings.dart';
import 'package:cockpit/app/core/env.dart';
import 'package:cockpit/app/core/ui/menu/editor_menu_bridge.dart';
import 'package:cockpit/app/core/ui/menu/workspace_menu_bridge.dart';
import 'package:cockpit/app/core/ui/settings_controller.dart';
import 'package:cockpit/app/core/ui/themes/themes.dart';
import 'package:cockpit/app/core/ui/widgets/bootstrap_error_view.dart';
import 'package:cockpit/app/core/ui/widgets/loading_screen.dart';
import 'package:cockpit/app/core/utils/login_shell.dart';
import 'package:flutter_modular/flutter_modular.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';
import 'package:window_manager/window_manager.dart';

/// Piso do splash: evita o flash de uma tela de loading que aparece e some em
/// um frame nas máquinas rápidas. Curto de propósito — o boot nunca fica mais
/// lento que isso além do trabalho real.
const _splashFloor = Duration(milliseconds: 400);

/// Raiz do app: mostra a janela imediatamente (LoadingScreen já no tema
/// salvo), roda o bootstrap lento em background e só então monta o
/// `ModularApp`. Falha em qualquer etapa cai na [BootstrapErrorView] com
/// retry — antes o `main()` fazia tudo síncrono e uma exceção derrubava o app
/// sem feedback.
///
/// Mora fora de `core/` de propósito: o bootstrap conhece features
/// (hooks/registries do cockpit) e o `core/` não pode importar de feature.
class CockpitBootstrapper extends StatefulWidget {
  const CockpitBootstrapper({super.key});

  @override
  State<CockpitBootstrapper> createState() => _CockpitBootstrapperState();
}

class _CockpitBootstrapperState extends State<CockpitBootstrapper> {
  bool _initialized = false;
  Object? _error;
  Module? _appModule;
  SettingsController? _settings;
  Box<dynamic>? _winBox;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _initApp();
    });
  }

  Future<void> _initApp() async {
    try {
      // 1. Caminho rápido: settings (tema sem flash) + bounds da janela. No
      // retry as boxes já estão abertas — `Hive.openBox` devolve a instância
      // viva, então o caminho é idempotente.
      //
      // Raiz do Hive via StorageLocation: pasta padrão OU a escolhida nas
      // Configurações (ponteiro fixo em `~/.cockpit/storage_root`).
      // Subdiretório próprio (`cockpit`/`cockpit-debug`) separa debug de
      // produção. As boxes das features são abertas pelos próprios builders
      // async (ver buildCockpitModule); aqui só settings + window_state.
      Hive.init(await StorageLocation.hiveDir());
      final settingsBox = await Hive.openBox<dynamic>(
        HiveSettingsStore.boxName,
      );
      final settings = SettingsController(HiveSettingsStore(settingsBox));
      await settings.load();

      final winBox = await Hive.openBox<dynamic>('window_state');

      if (mounted) {
        setState(() {
          _settings = settings;
          _winBox = winBox;
        });
      }

      // 2. Restaura bounds e mostra a janela já — a árvore está renderizando a
      // LoadingScreen no tema carregado acima.
      await _setupWindow(winBox);

      // 3. Tarefas lentas atrás da tela de loading.
      final Future<void> initTask = (() async {
        // Resolve o shell de login ANTES do primeiro terminal. Aberto pelo
        // Finder/Dock não há `$SHELL` (launchd não tem shell-pai) — a
        // resolução consulta o SO (dscl/getent) e o spawn de PTY, síncrono,
        // lê do cache. Ver login_shell.dart / issue #42.
        await resolveLoginShell();

        // Mata filhos órfãos desta instância ou de instâncias já encerradas,
        // preservando agents/LSP/tasks de outros Cockpits ainda vivos.
        await Future.wait([
          PiProcessRegistry.cleanOrphans(),
          LspProcessRegistry.cleanOrphans(),
          TaskProcessRegistry.cleanOrphans(),
        ]);

        // Hooks do Cockpit no ~/.claude/settings.json (idempotente) pra
        // sessões `claude` nas abas reportarem status de turno. Não-fatal.
        unawaited(
          ClaudeHookInstallerImpl().ensureInstalled().then((r) {
            r.fold(
              (_) {},
              (e) => debugPrint('[claude-hook] install falhou: $e'),
            );
          }),
        );

        final config = await PiSpawnConfig.resolve();
        _appModule = await buildAppModule(config: config);
      })();

      await Future.wait([initTask, Future.delayed(_splashFloor)]);

      if (mounted) {
        setState(() {
          _initialized = true;
        });
      }
    } catch (e, stack) {
      // Boundary do bootstrap: qualquer falha (Hive corrompido, config, DI)
      // vira tela de erro com retry em vez de app morto sem feedback.
      debugPrint('[bootstrap] falhou: $e\n$stack');
      if (mounted) {
        setState(() {
          _error = e;
        });
      }
    }
  }

  /// Brilho efetivo pras telas fora do ModularApp (loading/erro): preferência
  /// salva ou, em `system`, o do SO.
  Brightness _brightnessFor(AppSettings s) => switch (s.themeMode) {
    AppThemeMode.dark => Brightness.dark,
    AppThemeMode.light => Brightness.light,
    AppThemeMode.system => View.of(
      context,
    ).platformDispatcher.platformBrightness,
  };

  /// Esconde a barra nativa e restaura o último tamanho E posição da janela.
  ///
  /// `waitUntilReadyToShow` mantém a janela oculta até o `show()`; os bounds
  /// salvos entram ANTES, evitando o "salto" do frame default recentralizar.
  Future<void> _setupWindow(Box<dynamic> winBox) async {
    if (!(Platform.isMacOS || Platform.isWindows || Platform.isLinux)) return;
    await windowManager.ensureInitialized();
    final w = (winBox.get('width') as num?)?.toDouble() ?? 1280;
    final h = (winBox.get('height') as num?)?.toDouble() ?? 720;
    final x = (winBox.get('x') as num?)?.toDouble();
    final y = (winBox.get('y') as num?)?.toDouble();
    final options = WindowOptions(
      titleBarStyle: TitleBarStyle.hidden,
      windowButtonVisibility: false,
      minimumSize: const Size(720, 480),
      size: Size(w, h),
      // Sem posição salva (1ª execução): centraliza.
      center: x == null || y == null,
    );
    await windowManager.waitUntilReadyToShow(options, () async {
      if (x != null && y != null) {
        await windowManager.setBounds(Rect.fromLTWH(x, y, w, h));
      }
      await windowManager.show();
      await windowManager.focus();
    });
  }

  /// Shell mínimo (tema resolvido) pras fases pré-ModularApp.
  Widget _shell(AppSettings s, Widget home) {
    final brightness = _brightnessFor(s);
    final tokens = buildTokens(brightness: brightness, settings: s);
    return ShadcnApp(
      title: 'Cockpit',
      debugShowCheckedModeBanner: false,
      theme: buildTheme(brightness: brightness, settings: s),
      home: home,
      builder: (context, child) {
        return CockpitTheme(
          colors: tokens.colors,
          typo: tokens.typo,
          syntax: tokens.syntax,
          child: child ?? const SizedBox(),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final s = _settings?.settings ?? const AppSettings();

    if (_error != null) {
      return _shell(
        s,
        BootstrapErrorView(
          error: _error!,
          onRetry: () {
            setState(() => _error = null);
            _initApp();
          },
        ),
      );
    }

    if (!_initialized) return _shell(s, const LoadingScreen());

    return WindowStateKeeper(
      box: _winBox!,
      child: ModularApp(
        module: _appModule!,
        provide: (s) => s
          ..addChangeNotifier<SettingsController>(() => _settings!)
          ..addChangeNotifier<EditorMenuBridge>(EditorMenuBridge.new)
          ..addChangeNotifier<WorkspaceMenuBridge>(WorkspaceMenuBridge.new),
        child: const AppRoot(),
      ),
    );
  }
}

/// Ouve redimensionamentos e persiste o tamanho da janela com debounce.
class WindowStateKeeper extends StatefulWidget {
  const WindowStateKeeper({super.key, required this.box, required this.child});
  final Box<dynamic> box;
  final Widget child;

  @override
  State<WindowStateKeeper> createState() => WindowStateKeeperState();
}

class WindowStateKeeperState extends State<WindowStateKeeper>
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
  void onWindowResize() => _persistBounds();

  @override
  void onWindowMove() => _persistBounds();

  /// Persiste tamanho + posição (bounds completos) com debounce. Um único
  /// caminho para resize e move — ambos alteram os bounds que restauramos no
  /// próximo boot.
  void _persistBounds() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 400), () async {
      final bounds = await windowManager.getBounds();
      await widget.box.putAll({
        'x': bounds.left,
        'y': bounds.top,
        'width': bounds.width,
        'height': bounds.height,
      });
    });
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
