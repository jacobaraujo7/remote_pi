import 'dart:async';

import 'package:auto_updater/auto_updater.dart';
import 'package:cockpit/app/cockpit/domain/contracts/self_updater.dart';
import 'package:flutter/foundation.dart';

/// Self-update nativo via [autoUpdater] (Sparkle no macOS, WinSparkle no
/// Windows). Implementa [SelfUpdater] e ouve os eventos do motor via
/// [UpdaterListener], traduzindo-os pra [SelfUpdateState].
///
/// **Os dois motores têm contratos diferentes** e a fachada precisa saber com
/// qual está falando — é o que [autoDownloads] diz:
///
/// - **macOS (Sparkle, `autoDownloads: true`)**: com `SUEnableAutomaticChecks`/
///   `SUAutomaticallyUpdate` no Info.plist o motor baixa em background e instala
///   no próximo quit. Fases: `checking → downloading → downloaded`.
/// - **Windows (WinSparkle, `autoDownloads: false`)**: o motor **não baixa
///   sozinho** e a `WinSparkle.dll` 0.8.1 **não tem callback de "baixou"** — o
///   plugin só emite `checking-for-update`, `update-available`,
///   `update-not-available`, `error` e `before-quit-for-update`. Logo
///   [onUpdaterUpdateDownloaded] é código morto aqui e a fase para em
///   [SelfUpdatePhase.available]; [applyUpdate] é que dispara download+install.
///
/// Tratar os dois como iguais foi o bug original: o Windows ficava preso em
/// `downloading` pra sempre e o clique no card era no-op.
///
/// Depois do download, o WinSparkle lança o instalador e emite
/// `before-quit-for-update`: a partir daí quem precisa encerrar o app é o host
/// ([quitForUpdate]), senão o instalador não consegue trocar os arquivos.
///
/// Limite conhecido (risco do plano): o passo final de install mostra UI nativa
/// (`SPUStandardUserDriver` no macOS; o diálogo do WinSparkle no Windows) — não
/// dá pra suprimir 100% pela fachada.
class AutoUpdaterSelfUpdater with UpdaterListener implements SelfUpdater {
  AutoUpdaterSelfUpdater({
    required this.feedUrl,
    required this.autoDownloads,
    this.checkInterval = const Duration(hours: 24),
    this.quitForUpdate,
  });

  /// Encerra o app quando o motor pede (`before-quit-for-update`). Só é chamado
  /// quando o motor **não** encerra o app por conta própria ([autoDownloads]
  /// `false` = WinSparkle): o WinSparkle lança o instalador e só *pede* pro host
  /// sair (`win_sparkle_set_shutdown_request_callback`). Sem sair, o instalador
  /// silencioso encontra `cockpit.exe`, o sidecar e os `OpenConsole.exe` vivos
  /// na pasta de instalação e aborta sem avisar (#330). O módulo passa o
  /// fechamento limpo da janela, o mesmo do X da barra de título.
  final Future<void> Function()? quitForUpdate;

  /// Appcast da plataforma (`appcast-macos.xml` / `appcast-windows.xml`).
  final String feedUrl;

  /// O motor baixa o artefato sozinho em background? `true` = Sparkle/macOS,
  /// `false` = WinSparkle/Windows (ver doc da classe). Decide se
  /// `update-available` vira [SelfUpdatePhase.downloading] ou
  /// [SelfUpdatePhase.available].
  final bool autoDownloads;

  /// Intervalo da checagem periódica do motor nativo (mín. 1h; 0 desliga).
  final Duration checkInterval;

  final StreamController<SelfUpdateState> _controller =
      StreamController<SelfUpdateState>.broadcast();
  SelfUpdateState _state = const SelfUpdateState.idle();
  bool _initialized = false;

  @override
  bool get isSupported => true;

  @override
  SelfUpdateState get state => _state;

  @override
  Stream<SelfUpdateState> get changes => _controller.stream;

  void _emit(SelfUpdateState next) {
    _state = next;
    if (!_controller.isClosed) _controller.add(next);
  }

  @override
  Future<void> initialize() async {
    if (_initialized) return;
    _initialized = true;
    autoUpdater.addListener(this);
    // ORDEM IMPORTA no Windows: `setFeedURL` chama `win_sparkle_init()` por
    // baixo, e o header da WinSparkle é explícito que as funções de config "can
    // only be called *before* the first call to win_sparkle_init()". Por isso o
    // intervalo vem primeiro. No macOS a ordem é indiferente.
    await autoUpdater.setScheduledCheckInterval(checkInterval.inSeconds);
    await autoUpdater.setFeedURL(feedUrl);
  }

  @override
  Future<void> checkForUpdates({bool inBackground = true}) async {
    if (!_initialized) await initialize();
    await autoUpdater.checkForUpdates(inBackground: inBackground);
  }

  @override
  Future<void> applyUpdate() async {
    // `isActionable` (não `phase == downloaded`): no Windows a fase para em
    // `available` e o guard antigo fazia este método retornar sempre — era esse
    // o motivo de o clique no card não fazer nada.
    if (!_state.isActionable) return;
    // Foreground → macOS: o Sparkle instala o já baixado e relança. Windows:
    // `win_sparkle_check_update_with_ui()`, que conduz download+install e,
    // segundo o header, "ignores 'Skip this version' even if the user checked it
    // previously" — então isto também destrava quem já clicou Skip no diálogo.
    await autoUpdater.checkForUpdates(inBackground: false);
  }

  // ---- UpdaterListener: eventos do motor nativo → SelfUpdateState ----

  @override
  void onUpdaterCheckingForUpdate(Appcast? appcast) {
    _emit(const SelfUpdateState(SelfUpdatePhase.checking));
  }

  @override
  void onUpdaterUpdateAvailable(AppcastItem? item) {
    // macOS: o Sparkle já começou a baixar em background → `downloading`.
    // Windows: o WinSparkle não baixa nada sozinho e nunca avisa que baixou →
    // `available` é o estado terminal, e o clique no card (`applyUpdate`) é que
    // conduz o download+install.
    _emit(
      SelfUpdateState(
        autoDownloads ? SelfUpdatePhase.downloading : SelfUpdatePhase.available,
        version: _versionOf(item),
      ),
    );
  }

  @override
  void onUpdaterUpdateNotAvailable(UpdaterError? error) {
    _emit(const SelfUpdateState.idle());
  }

  @override
  void onUpdaterUpdateDownloaded(AppcastItem? item) {
    _emit(
      SelfUpdateState(SelfUpdatePhase.downloaded, version: _versionOf(item)),
    );
  }

  @override
  void onUpdaterBeforeQuitForUpdate(AppcastItem? item) {
    // macOS: o Sparkle encerra e relança o app sozinho — nada a fazer aqui.
    // Windows: o instalador já foi lançado e espera o app sair. O workspace
    // (panes/abas) reabre pelo estado persistido no próximo boot.
    if (autoDownloads) {
      debugPrint('[self-update] before quit for update');
      return;
    }
    final quit = quitForUpdate;
    if (quit == null) return;
    unawaited(
      quit().catchError((Object e) {
        debugPrint('[self-update] quit for update failed: $e');
      }),
    );
  }

  @override
  void onUpdaterError(UpdaterError? error) {
    _emit(SelfUpdateState(SelfUpdatePhase.error, message: error?.message));
  }

  String? _versionOf(AppcastItem? item) =>
      item?.displayVersionString ?? item?.versionString;

  @override
  void dispose() {
    autoUpdater.removeListener(this);
    if (!_controller.isClosed) _controller.close();
  }
}
