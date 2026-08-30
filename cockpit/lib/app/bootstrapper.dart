import 'dart:async';
import 'dart:io' show Platform;
import 'dart:ui' show AppExitResponse;

import 'package:cockpit/app/app_module.dart';
import 'package:cockpit/app/app_widget.dart';
import 'package:cockpit/app/cockpit/data/hooks/claude_hook_installer_impl.dart';
import 'package:cockpit/app/cockpit/data/hooks/codex_hook_installer_impl.dart';
import 'package:cockpit/app/cockpit/data/rpc/pi_process_registry.dart';
import 'package:cockpit/app/cockpit/data/terminal/sidecar/sidecar_terminal_connector.dart';
import 'package:cockpit/app/cockpit/data/tasks/task_process_registry.dart';
import 'package:cockpit/app/cockpit/domain/contracts/hook_installer.dart';
import 'package:cockpit/app/core/data/diagnostics/diagnostics_log.dart';
import 'package:cockpit/app/core/data/lsp/lsp_process_registry.dart';
import 'package:cockpit/app/core/data/repositories/json_settings_store.dart';
import 'package:cockpit/app/core/utils/platform_kind.dart';
import 'package:cockpit/app/core/data/setup/hive_migration.dart';
import 'package:cockpit/app/core/data/setup/local_network_permission.dart';
import 'package:cockpit/app/core/data/setup/json_state_store.dart';
import 'package:cockpit/app/core/data/setup/storage_location.dart';
import 'package:cockpit/app/core/data/theme_store.dart';
import 'package:cockpit/app/core/domain/entities/app_settings.dart';
import 'package:cockpit/app/core/domain/services/window_placement.dart';
import 'package:cockpit/app/core/env.dart';
import 'package:cockpit/app/core/ui/automation_controller.dart';
import 'package:cockpit/app/core/ui/menu/editor_menu_bridge.dart';
import 'package:cockpit/app/core/ui/menu/workspace_menu_bridge.dart';
import 'package:cockpit/app/core/ui/settings_controller.dart';
import 'package:cockpit/app/core/ui/window_activity_controller.dart';
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
import 'package:screen_retriever/screen_retriever.dart';
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
  final WindowActivityController _windowActivity = WindowActivityController();

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
        // Com teto, pelo mesmo motivo do fechamento pela janela: o engine
        // espera esta resposta para encerrar, e um flush lento vira app que
        // não morre.
        try {
          await JsonStateStore.flushAll().timeout(const Duration(seconds: 2));
        } on TimeoutException {
          DiagnosticsLog.instance.log('exit', 'flush estourou 2s — saindo');
        } on Object catch (e, stack) {
          DiagnosticsLog.instance.logError('exit-flush', e, stack);
        }
        // Encerra o sidecar JUNTO com o app. Sem isto, o `cockpit-server`
        // sobrevivia ao fechamento e — como o self-update troca o binário no
        // disco embaixo do processo vivo — o host seguia servindo código
        // antigo indefinidamente. O `--exit-on-parent-close` cobre a morte
        // abrupta; aqui é a saída limpa, que não precisa esperar o EOF.
        try {
          inject<SidecarTerminalConnector>().dispose();
        } on Object catch (e, stack) {
          DiagnosticsLog.instance.logError('exit-sidecar', e, stack);
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
        // Mobile: sem shell local (e `Process.run` é proibido no iOS real, só
        // funciona no simulador que é macOS por baixo) → pula.
        if (!isMobilePlatform) await resolveLoginShell();

        // iOS: provoca o diálogo de rede local agora, enquanto nada depende
        // dele. A tentativa que provoca o pedido sempre falha (ele aparece
        // depois dela), e era isso que fazia o cadastro de um host da LAN dar
        // erro na primeira vez, só funcionando após reabrir o app. Não
        // aguardamos: o boot não fica refém da resposta do usuário.
        unawaited(LocalNetworkPermission.prime());

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
        // config.toml). Não-fatal e independentes. Desktop-only (mobile não tem
        // ~/.claude nem ~/.codex, plano 59).
        if (!isMobilePlatform) {
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
        }

        final config = await PiSpawnConfig.resolve();
        _appModule = await buildAppModule(
          config: config,
          windowActivity: _windowActivity,
        );
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
    const minSize = Size(720, 480);
    var w = (winStore.get('width') as num?)?.toDouble() ?? 1280;
    var h = (winStore.get('height') as num?)?.toDouble() ?? 720;
    var x = (winStore.get('x') as num?)?.toDouble();
    var y = (winStore.get('y') as num?)?.toDouble();

    // Os bounds salvos descrevem o arranjo de telas do último encerramento.
    // Reencaixa no arranjo de agora (ver [fitWindowBounds]) — desacoplar um
    // monitor externo, ou vir de um maior pra um menor, senão faz a janela
    // reabrir fora da vista.
    if (x != null && y != null) {
      final fitted = fitWindowBounds(
        saved: Rect.fromLTWH(x, y, w, h),
        workAreas: await _workAreas(),
        minSize: minSize,
      );
      x = fitted.left;
      y = fitted.top;
      w = fitted.width;
      h = fitted.height;
    }

    final options = WindowOptions(
      titleBarStyle: TitleBarStyle.hidden,
      windowButtonVisibility: false,
      minimumSize: minSize,
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
    final wasMaximized = winStore.get('maximized') == true;
    await windowManager.waitUntilReadyToShow(options, () async {
      if (x != null && y != null) {
        await windowManager.setBounds(Rect.fromLTWH(x, y, w, h));
      }
      // Maximizada é um ESTADO, não um tamanho: restaurar por bounds daria uma
      // janela do tamanho da tela sem estar maximizada (no Win/Linux os bounds
      // de uma janela maximizada extrapolam a work area pelas bordas
      // invisíveis, então ela ainda cobriria a barra de tarefas, e o botão
      // restaurar não teria o que restaurar). Os bounds salvos acima são os do
      // último estado NÃO maximizado — é pra eles que o restaurar volta.
      if (wasMaximized) await windowManager.maximize();
      await windowManager.show();
      await windowManager.focus();
    });
  }

  /// Áreas úteis (sem barra de tarefas/dock) de cada monitor, a primária
  /// primeiro — a ordem que [fitWindowBounds] usa como desempate. Falha do
  /// plugin devolve lista vazia, e o encaixe vira no-op (melhor abrir na
  /// posição salva do que travar o boot por causa de geometria).
  Future<List<Rect>> _workAreas() async {
    try {
      final primary = await screenRetriever.getPrimaryDisplay();
      final displays = await screenRetriever.getAllDisplays();
      final ordered = [primary, ...displays.where((d) => d.id != primary.id)];
      return [
        for (final d in ordered)
          (d.visiblePosition ?? Offset.zero) & (d.visibleSize ?? d.size),
      ];
    } on Object catch (e, stack) {
      DiagnosticsLog.instance.logError('window-displays', e, stack);
      return const [];
    }
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
      activity: _windowActivity,
      child: ModularApp(
        module: _appModule!,
        navigatorKey: _navigatorKey,
        provide: (s) => s
          ..addChangeNotifier<SettingsController>(() => _settings!)
          ..addChangeNotifier<WindowActivityController>(() => _windowActivity)
          // A mesma instância bootstrap-owned é observada por Settings e Source
          // Control e injetada nos controllers da feature Cockpit.
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
    required this.activity,
    required this.child,
  });
  final JsonStateStore store;
  final WindowActivityController activity;
  final Widget child;

  @override
  State<WindowStateKeeper> createState() => WindowStateKeeperState();
}

class WindowStateKeeperState extends State<WindowStateKeeper>
    with WindowListener {
  Timer? _debounce;

  /// O fechamento começou — daqui pra frente **nada** pergunta nada à janela.
  ///
  /// Existe por causa de um SIGSEGV em TODO fechamento no Linux: destruir a
  /// `GtkWindow` faz o GTK emitir os eventos finais (resize/unmaximize), o
  /// `onWindowResize` reagenda o debounce, e o `isMaximized` que vem depois cai
  /// em `gtk_window_is_maximized(NULL)` — o `window_manager` repassa sem
  /// checar. O processo derrubava core (~30 MB) a cada saída, e os "segundos
  /// travado" que o usuário via eram o kernel escrevendo o dump.
  ///
  /// Pior que o incômodo: o `markCleanExit()` roda ANTES do `destroy()`, então
  /// o app registrava saída limpa e só então quebrava — o detector de crash
  /// ficava cego justamente para o crash mais frequente que ele tinha.
  bool _closing = false;
  late final WindowActivitySynchronizer _activitySync;

  @override
  void initState() {
    super.initState();
    _activitySync = WindowActivitySynchronizer(
      activity: widget.activity,
      readSnapshot: _readNativeActivity,
    );
    // O listener entra antes do snapshot: se a janela mudar durante os awaits,
    // o synchronizer preserva o evento mais novo e descarta a leitura obsoleta.
    windowManager.addListener(this);
    unawaited(_activitySync.synchronize());
  }

  Future<WindowActivitySnapshot> _readNativeActivity() async =>
      WindowActivitySnapshot(
        focused: await windowManager.isFocused(),
        minimized: await windowManager.isMinimized(),
      );

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

  @override
  void onWindowFocus() => _activitySync.focus();

  @override
  void onWindowBlur() => _activitySync.blur();

  @override
  void onWindowMinimize() => _activitySync.minimize();

  @override
  void onWindowRestore() => _activitySync.restore();

  @override
  void onWindowMaximize() => _persistMaximized(true);

  @override
  void onWindowUnmaximize() => _persistMaximized(false);

  /// Teto de cada etapa do fechamento. Curto de propósito: o usuário já clicou
  /// em fechar, e uma janela que não responde é pior do que perder a última
  /// gravação de bounds.
  static const _closeStepTimeout = Duration(seconds: 2);

  /// Roda uma etapa do fechamento com teto de tempo e **registra quanto
  /// demorou**.
  ///
  /// O fechamento roda com a janela já interceptada (`setPreventClose`), então
  /// tudo o que demora aqui aparece como tela travada. Sem medição não havia
  /// como saber qual etapa era a lenta numa máquina que não é a nossa — e no
  /// Windows a escrita atômica pode custar caro (antivírus, pasta
  /// sincronizada), sem nada disso aparecer no macOS.
  Future<void> _closeStep(String tag, Future<void> Function() step) async {
    final started = DateTime.now();
    try {
      await step().timeout(_closeStepTimeout);
    } on TimeoutException {
      DiagnosticsLog.instance.log(
        'close',
        '$tag estourou ${_closeStepTimeout.inSeconds}s — seguindo sem esperar',
      );
      return;
    } on Object catch (e, stack) {
      DiagnosticsLog.instance.logError('close-$tag', e, stack);
      return;
    }
    final ms = DateTime.now().difference(started).inMilliseconds;
    // Só o que demora vira linha de log; fechamento normal não polui o arquivo.
    if (ms >= 250) DiagnosticsLog.instance.log('close', '$tag levou ${ms}ms');
  }

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
    // ORDEM IMPORTA. O listener sai PRIMEIRO: destruir a janela faz o GTK
    // emitir os eventos finais, e um `onWindowResize` atendido depois disso
    // pergunta a uma janela morta se está maximizada — SIGSEGV dentro do GTK.
    // Era o motivo de o app derrubar core em todo fechamento.
    windowManager.removeListener(this);
    // Bounds pendentes no debounce: fechar 400 ms depois de mover a janela
    // perderia a posição.
    _debounce?.cancel();
    // A gravação final acontece com a janela ainda VIVA (antes do `destroy()`),
    // então o guard só entra em vigor depois dela.
    await _closeStep('bounds', _persistBoundsNow);
    _closing = true;
    await _closeStep('flush', JsonStateStore.flushAll);
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
    if (_closing) return;
    _debounce?.cancel();
    _debounce = Timer(
      const Duration(milliseconds: 400),
      () => unawaited(_persistBoundsNow()),
    );
  }

  Future<void> _persistBoundsNow() async {
    // Cinto e suspensório: um callback já em voo pode chegar depois do
    // `removeListener`, e aí a pergunta à janela morta mata o processo.
    if (_closing) return;
    // Maximizada, os bounds são os da tela — gravá-los apagaria o tamanho
    // "normal" pro qual o restaurar volta, e o boot seguinte abriria uma janela
    // de tela cheia que não desmaximiza. Só o flag muda nesse estado; os bounds
    // ficam congelados no último tamanho normal.
    if (await windowManager.isMaximized()) return;
    final bounds = await windowManager.getBounds();
    await widget.store.putAll({
      'x': bounds.left,
      'y': bounds.top,
      'width': bounds.width,
      'height': bounds.height,
    });
  }

  /// Grava o estado maximizado na hora (sem debounce): é um evento discreto,
  /// não um fluxo contínuo como resize/move.
  void _persistMaximized(bool maximized) {
    if (_closing) return;
    // Um maximize dispara resize junto; cancelar o debounce pendente evita que
    // ele grave bounds de tela cheia por chegar antes do flag valer.
    _debounce?.cancel();
    unawaited(widget.store.put('maximized', maximized));
  }

  @override
  Widget build(BuildContext context) =>
      WindowActivityBoundary(activity: widget.activity, child: widget.child);
}
