import 'dart:async';
import 'dart:io' show Platform;
import 'dart:ui' show AppExitResponse;

import 'package:cockpit/app/app_module.dart';
import 'package:cockpit/app/app_widget.dart';
import 'package:cockpit/app/cockpit/data/hooks/claude_hook_installer_impl.dart';
import 'package:cockpit/app/cockpit/data/hooks/codex_hook_installer_impl.dart';
import 'package:cockpit/app/cockpit/data/rpc/pi_process_registry.dart';
import 'package:cockpit/app/cockpit/data/tasks/task_process_registry.dart';
import 'package:cockpit/app/cockpit/domain/contracts/hook_installer.dart';
import 'package:cockpit/app/core/data/diagnostics/diagnostics_log.dart';
import 'package:cockpit/app/core/data/lsp/lsp_process_registry.dart';
import 'package:cockpit/app/core/data/repositories/json_settings_store.dart';
import 'package:cockpit/app/core/data/setup/hive_migration.dart';
import 'package:cockpit/app/core/data/setup/json_state_store.dart';
import 'package:cockpit/app/core/data/setup/storage_location.dart';
import 'package:cockpit/app/core/data/theme_store.dart';
import 'package:cockpit/app/core/domain/entities/app_settings.dart';
import 'package:cockpit/app/core/env.dart';
import 'package:cockpit/app/core/ui/automation_controller.dart';
import 'package:cockpit/app/core/ui/menu/editor_menu_bridge.dart';
import 'package:cockpit/app/core/ui/menu/workspace_menu_bridge.dart';
import 'package:cockpit/app/core/ui/settings_controller.dart';
import 'package:cockpit/i18n/strings.g.dart';
import 'package:cockpit/app/core/ui/themes/themes.dart';
import 'package:cockpit/app/core/ui/widgets/bootstrap_error_view.dart';
import 'package:cockpit/app/core/ui/widgets/devtools_inspector.dart';
import 'package:cockpit/app/core/ui/widgets/error_report_dialog.dart';
import 'package:cockpit/app/core/ui/widgets/loading_screen.dart';
import 'package:cockpit/app/cockpit/ui/widgets/confirm_dialog.dart';
import 'package:cockpit/app/core/utils/login_shell.dart';
import 'package:flutter_modular/flutter_modular.dart';
import 'package:package_info_plus/package_info_plus.dart';
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
  JsonStateStore? _winStore;

  AppLifecycleListener? _lifecycle;

  /// Chave do Navigator raiz (dentro do `ModularApp`). O `context` deste
  /// State fica **acima** do `ShadcnApp`, então `showDialog` a partir dele
  /// não acha Navigator — era exatamente isso que quebrava a oferta de
  /// crash report no boot (loop de crash no Windows).
  final GlobalKey<NavigatorState> _navigatorKey = GlobalKey<NavigatorState>();

  @override
  void initState() {
    super.initState();
    // Saída pela janela/menu conta como limpa — sem isso o boot seguinte
    // acusaria crash em todo fechamento normal, e o aviso viraria ruído que o
    // usuário aprende a ignorar.
    _lifecycle = AppLifecycleListener(
      onExitRequested: () async {
        // Descarrega qualquer escrita ainda na janela de debounce dos stores
        // (bounds da janela, layout) antes do processo morrer.
        try {
          await JsonStateStore.flushAll();
        } on Object catch (e, stack) {
          DiagnosticsLog.instance.logError('exit-flush', e, stack);
        }
        DiagnosticsLog.instance.markCleanExit();
        return AppExitResponse.exit;
      },
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _initApp();
    });
  }

  @override
  void dispose() {
    _lifecycle?.dispose();
    super.dispose();
  }

  Future<void> _initApp() async {
    try {
      // 1. Caminho rápido: settings (tema sem flash) + bounds da janela. No
      // retry os stores já estão em cache — `JsonStateStore.open` devolve a
      // instância viva, então o caminho é idempotente.
      //
      // Raiz do estado via StorageLocation: pasta padrão OU a escolhida nas
      // Configurações (ponteiro fixo em `~/.cockpit/storage_root`).
      // Subdiretório próprio (`cockpit`/`cockpit-debug`) separa debug de
      // produção. Os stores das features são abertos pelos próprios builders
      // async (ver buildCockpitModule); aqui só settings + window_state.
      //
      // Migração one-shot Hive→JSON: dados legados (boxes .hive, inclusive no
      // default antigo do Windows em Documents) são despejados nos JSONs de
      // `state/` uma única vez (marcador `migration.json`). O Hive vive só
      // dentro do migrador.
      await HiveToJsonMigration(appVersion: await _appVersion()).runIfNeeded();
      final stateDir = await StorageLocation.stateDir();
      final settingsStore = await JsonStateStore.open(
        stateDir,
        JsonSettingsStore.storeName,
      );
      final settings = SettingsController(
        JsonSettingsStore(settingsStore),
        const ThemeStore(),
      );
      await settings.load();

      final winStore = await JsonStateStore.open(stateDir, 'window_state');

      if (mounted) {
        setState(() {
          _settings = settings;
          _winStore = winStore;
        });
      }

      // 2. Restaura bounds e mostra a janela já — a árvore está renderizando a
      // LoadingScreen no tema carregado acima.
      await _setupWindow(winStore);

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

        // Hooks do Cockpit nos harnesses suportados (idempotente) pra sessões
        // de agente nas abas reportarem status de turno: Claude Code em
        // ~/.claude/settings.json, Codex CLI em ~/.codex/hooks.json (+ trust no
        // config.toml). Não-fatal e independentes: falha de um não impede o
        // outro.
        for (final installer in const <HookInstaller>[
          ClaudeHookInstallerImpl(),
          CodexHookInstallerImpl(),
        ]) {
          unawaited(
            installer.ensureInstalled().then((r) {
              r.fold((_) {}, (e) => debugPrint('[hook] install falhou: $e'));
            }),
          );
        }

        final config = await PiSpawnConfig.resolve();
        _appModule = await buildAppModule(config: config);
      })();

      await Future.wait([initTask, Future.delayed(_splashFloor)]);

      if (mounted) {
        setState(() {
          _initialized = true;
        });
      }

      // Sessão anterior morreu sem passar pelo encerramento limpo (SIGPIPE,
      // segfault, força bruta). Nenhum handler Dart vê isso — só o marcador.
      // Oferecido depois do boot pra não competir com a tela de loading.
      //
      // Sessão de **debug** não gera aviso: lá o processo é morto a cada hot
      // restart e a cada stop da IDE, então o marcador sujo é a regra, não a
      // exceção. Segue registrado no log — só não interrompe quem está
      // desenvolvendo.
      final crash = DiagnosticsLog.instance.previousCrash;
      if (crash != null && !crash.debug && mounted) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) unawaited(_offerCrashReport(crash));
        });
      }
    } catch (e, stack) {
      // Boundary do bootstrap: qualquer falha (migração, config, DI)
      // vira tela de erro com retry em vez de app morto sem feedback.
      DiagnosticsLog.instance.logError('bootstrap', e, stack);
      if (mounted) {
        setState(() {
          _error = e;
        });
      }
    }
  }

  /// Versão do app pro marcador da migração — informativa; se o PackageInfo
  /// falhar (plugin indisponível), a migração segue sem ela.
  Future<String?> _appVersion() async {
    try {
      return (await PackageInfo.fromPlatform()).version;
    } on Object catch (_) {
      return null;
    }
  }

  /// Avisa que a sessão anterior morreu e oferece reportar. Discreto de
  /// propósito: um dialog dispensável, não um bloqueio — o usuário abriu o app
  /// pra trabalhar, não pra preencher relatório.
  ///
  /// Roda **sobre o Navigator raiz** (`_navigatorKey`), não sobre o context
  /// deste State — que é ancestral do `ShadcnApp` e não tem Navigator. E
  /// nunca lança: aviso de crash que crasha o app vira loop de boot.
  Future<void> _offerCrashReport(DirtySession crash) async {
    final navContext = await _waitForNavigatorContext();
    if (navContext == null || !navContext.mounted) return;
    try {
      await _showCrashReport(navContext, crash);
    } on Object catch (e, stack) {
      DiagnosticsLog.instance.logError('crash-report', e, stack);
    }
  }

  /// O Navigator raiz só existe depois que o `ModularApp` monta a primeira
  /// rota — que pode levar alguns frames. Tenta por até ~2s e desiste em
  /// silêncio (o crash já está no log; o dialog é cortesia).
  Future<BuildContext?> _waitForNavigatorContext() async {
    for (var i = 0; i < 20; i++) {
      if (!mounted) return null;
      final ctx = _navigatorKey.currentContext;
      if (ctx != null && ctx.mounted) return ctx;
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
    return null;
  }

  Future<void> _showCrashReport(
    BuildContext context,
    DirtySession crash,
  ) async {
    final tr = context.t.core.crash;
    final ok = await showConfirmDialog(
      context,
      title: tr.bannerTitle,
      message: tr.crashMessage(version: crash.appVersion),
      confirmLabel: tr.report,
      cancelLabel: tr.dismiss,
    );
    if (!ok || !context.mounted) return;
    await showErrorReportDialog(
      context,
      title: tr.title,
      error: tr.crashError(
        startedAt: crash.startedAt.toIso8601String(),
        pid: crash.pid,
      ),
      description: tr.crashDescription,
    );
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
  Future<void> _setupWindow(JsonStateStore winStore) async {
    if (!(Platform.isMacOS || Platform.isWindows || Platform.isLinux)) return;
    await windowManager.ensureInitialized();
    final w = (winStore.get('width') as num?)?.toDouble() ?? 1280;
    final h = (winStore.get('height') as num?)?.toDouble() ?? 720;
    final x = (winStore.get('x') as num?)?.toDouble();
    final y = (winStore.get('y') as num?)?.toDouble();
    final options = WindowOptions(
      titleBarStyle: TitleBarStyle.hidden,
      windowButtonVisibility: false,
      minimumSize: const Size(720, 480),
      size: Size(w, h),
      // Sem posição salva (1ª execução): centraliza.
      center: x == null || y == null,
    );
    // Assume o fechamento da janela: sem isso, o X da barra de título e o Quit
    // do menu (ambos `windowManager.close()`) destroem a janela sem passar pelo
    // Dart, e a sessão nunca é marcada como encerrada. Ver
    // [WindowStateKeeperState.onWindowClose].
    //
    // Ligado aqui, e não no listener, porque a janela já é fechável antes de o
    // shell montar — um fechamento nessa janela de tempo escaparia.
    await windowManager.setPreventClose(true);
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
          terminal: tokens.terminal,
          child: DevToolsInspector(child: child ?? const SizedBox()),
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
      store: _winStore!,
      child: ModularApp(
        module: _appModule!,
        navigatorKey: _navigatorKey,
        provide: (s) => s
          ..addChangeNotifier<SettingsController>(() => _settings!)
          // A mesma instância root-owned é observada por Settings e Source
          // Control e também injetada no CockpitViewModel.
          ..addChangeNotifier<AutomationController>(
            () => inject<AutomationController>(),
          )
          ..addChangeNotifier<EditorMenuBridge>(EditorMenuBridge.new)
          ..addChangeNotifier<WorkspaceMenuBridge>(WorkspaceMenuBridge.new),
        child: const AppRoot(),
      ),
    );
  }
}

/// Ouve redimensionamentos e persiste o tamanho da janela com debounce.
class WindowStateKeeper extends StatefulWidget {
  const WindowStateKeeper({
    super.key,
    required this.store,
    required this.child,
  });
  final JsonStateStore store;
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

  /// Fechamento da janela: **este** é o encerramento limpo do Cockpit.
  ///
  /// Só chega aqui porque o boot liga `setPreventClose(true)`. Sem isso, tanto
  /// o X da barra de título quanto o Quit do menu chamam `windowManager.close()`
  /// e o processo morre sem o Dart saber — e o boot seguinte encontra o
  /// marcador de sessão viva e acusa crash. Era o motivo de o aviso "o Cockpit
  /// fechou inesperadamente" voltar a **cada** inicialização no Windows: o app
  /// nunca conseguia registrar uma saída limpa. No macOS o ⌘Q passa pelo
  /// handshake de saída do engine (`onExitRequested`), que já marcava — por
  /// isso lá o sintoma não aparecia.
  ///
  /// Nada aqui pode lançar: com `preventClose` ligado, uma exceção antes do
  /// `destroy()` deixaria uma janela que **não fecha**. Cada passo é isolado, e
  /// o `destroy()` roda no `finally`.
  @override
  Future<void> onWindowClose() async {
    try {
      // Bounds pendentes no debounce: fechar 400 ms depois de mover a janela
      // perderia a posição.
      _debounce?.cancel();
      await _persistBoundsNow();
    } on Object catch (e, stack) {
      DiagnosticsLog.instance.logError('close-bounds', e, stack);
    }
    try {
      await JsonStateStore.flushAll();
    } on Object catch (e, stack) {
      DiagnosticsLog.instance.logError('close-flush', e, stack);
    }
    try {
      DiagnosticsLog.instance.markCleanExit();
    } on Object catch (_) {
      /* o próprio markCleanExit já é best-effort */
    } finally {
      await windowManager.destroy();
    }
  }

  /// Persiste tamanho + posição (bounds completos) com debounce. Um único
  /// caminho para resize e move — ambos alteram os bounds que restauramos no
  /// próximo boot.
  void _persistBounds() {
    _debounce?.cancel();
    _debounce = Timer(
      const Duration(milliseconds: 400),
      () => unawaited(_persistBoundsNow()),
    );
  }

  Future<void> _persistBoundsNow() async {
    final bounds = await windowManager.getBounds();
    await widget.store.putAll({
      'x': bounds.left,
      'y': bounds.top,
      'width': bounds.width,
      'height': bounds.height,
    });
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
