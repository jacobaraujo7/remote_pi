import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:cockpit/app/cockpit/data/filesystem/disk_file_change_watcher.dart';
import 'package:cockpit/app/cockpit/data/filesystem/file_reader_impl.dart';
import 'package:cockpit/app/cockpit/data/panel/panel_command.dart';
import 'package:cockpit/app/cockpit/domain/entities/file_view.dart';
import 'package:cockpit/app/cockpit/ui/document/document_windows.dart';
import 'package:cockpit/app/cockpit/ui/document/running_instance.dart';
import 'package:cockpit/app/cockpit/ui/document/standalone_document_host.dart';
import 'worktree_document_host.dart';
import 'dart:typed_data';
import 'package:cockpit/app/cockpit/ui/session/document_host.dart';
import 'package:cockpit/app/cockpit/ui/session/file_viewer_session.dart';
import 'package:cockpit/app/cockpit/ui/session/notebook_session.dart';
import 'package:cockpit/app/cockpit/ui/widgets/file_viewer.dart';
import 'package:cockpit/app/cockpit/ui/widgets/kanban_board_view.dart';
import 'package:cockpit/app/cockpit/ui/widgets/layout_preview_view.dart';
import 'package:cockpit/app/cockpit/ui/widgets/notebook_view.dart';
import 'package:cockpit/app/cockpit/ui/widgets/panel_view.dart';
import 'package:cockpit/app/core/data/repositories/json_settings_store.dart';
import 'package:cockpit/app/core/data/setup/json_state_store.dart';
import 'package:cockpit/app/core/data/setup/storage_location.dart';
import 'package:cockpit/app/core/data/terminal/terminal_profile_resolver_impl.dart';
import 'package:cockpit/app/core/data/theme_store.dart';
import 'package:cockpit/app/core/domain/contracts/terminal_profile_resolver.dart';
import 'package:cockpit/app/core/domain/entities/app_settings.dart';
import 'package:cockpit/app/core/ui/app_zoom.dart';
import 'package:cockpit/app/core/ui/clamping_scroll_behavior.dart';
import 'package:cockpit/app/core/ui/menu/editor_menu_bridge.dart';
import 'package:cockpit/app/core/ui/overlay/app_popover_handler.dart';
import 'package:cockpit/app/core/ui/settings_controller.dart';
import 'package:cockpit/app/core/ui/themes/themes.dart';
import 'package:cockpit/i18n/strings.g.dart';
import 'package:flutter_modular/flutter_modular.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';

/// Entrypoint da **janela de documento** (ver [DocumentWindows]): o `main`
/// chega aqui quando o engine foi criado pelo `desktop_multi_window` com um
/// argumento de documento. Sobe só o necessário — settings (tema/fontes) do
/// mesmo JSON do app, i18n e o viewer do caminho — sem módulo do Cockpit,
/// sem projetos, sem status hook, sem LSP.
Future<void> runDocumentWindow(List<String> args) async {
  final path = DocumentWindows.pathFromArguments(args)!;
  WidgetsFlutterBinding.ensureInitialized();
  // Qualquer falha ANTES do runApp deixaria a janela preta e muda. Erros da
  // árvore de widgets também: sem handler, o engine desta janela não tem o
  // runGuarded do app. Tudo vira uma tela de erro legível.
  FlutterError.onError = (details) {
    FlutterError.presentError(details);
    stderr.writeln('[document-window] ${details.exception}');
  };
  try {
    await _boot(path);
  } catch (e, st) {
    stderr.writeln('[document-window] boot failed: $e\n$st');
    runApp(_BootError(path: path, error: '$e'));
  }
}

Future<void> _boot(String path) async {
  // SEM MediaKit.ensureInitialized(): o holder nativo do media_kit é POR
  // PROCESSO; inicializar de novo no engine desta janela achava a referência
  // do engine principal e a DESCARTAVA (log "Found 1 reference(s). Disposing"),
  // quebrando o player da janela principal. Áudio/vídeo ficam fora da janela
  // de documento (ver [DocumentScreen]).

  await LocaleSettings.useDeviceLocale();
  final stateDir = await StorageLocation.stateDir();
  final store = await JsonStateStore.open(
    stateDir,
    JsonSettingsStore.storeName,
  );
  final settings = SettingsController(
    JsonSettingsStore(store),
    const ThemeStore(),
  );
  await settings.load();
  _followSettingsFile(store, settings);
  // Perfis de terminal: o `.panel` na janela solta roda `cockpit <line>` no
  // perfil padrão das configurações, como na aba. A descoberta (pwsh? WSL?)
  // aquece em paralelo; até lá o `effectiveDefault` cai no fallback da
  // plataforma, que já é um perfil válido.
  final terminalProfiles = TerminalProfileResolverImpl();
  unawaited(terminalProfiles.discover());
  stderr.writeln('[document-window] booted for $path');

  unawaited(
    DocumentWindowChannel.present(path.split(Platform.pathSeparator).last),
  );

  runApp(
    TranslationProvider(
      child: ModularApp(
        module: createModule(register: (_) {}),
        provide: (s) => s
          ..addChangeNotifier<SettingsController>(() => settings)
          ..addChangeNotifier<EditorMenuBridge>(EditorMenuBridge.new),
        child: DocumentWindowRoot(
          path: path,
          terminalProfiles: terminalProfiles,
        ),
      ),
    ),
  );
}

/// A janela HERDA tema, fontes e zoom do app principal e os acompanha ao
/// vivo: observa a pasta do JSON de settings e relê quando o app grava
/// (⌘= na janela principal escala esta também). No sentido inverso o app
/// principal não relê; um ⌘= aqui vale pra esta janela e fica gravado.
void _followSettingsFile(JsonStateStore store, SettingsController settings) {
  final file = File(store.path);
  Timer? debounce;
  try {
    file.parent.watch().listen((event) {
      if (event.path != file.path) return;
      debounce?.cancel();
      debounce = Timer(const Duration(milliseconds: 200), () async {
        await store.reload();
        await settings.load();
      });
    });
  } on FileSystemException {
    // sem watcher: fica com o que leu ao abrir
  }
}

/// Tela de erro da janela de documento (boot falhou): texto cru, sem tema,
/// porque o tema pode ser justamente o que falhou.
class _BootError extends StatelessWidget {
  const _BootError({required this.path, required this.error});

  final String path;
  final String error;

  @override
  Widget build(BuildContext context) => WidgetsApp(
    color: const Color(0xFF1E1E1E),
    debugShowCheckedModeBanner: false,
    builder: (context, _) => ColoredBox(
      color: const Color(0xFF1E1E1E),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Text(
          'Cockpit could not open this document.\n\n$path\n\n$error',
          style: const TextStyle(color: Color(0xFFDDDDDD), fontSize: 13),
        ),
      ),
    ),
  );
}

/// Raiz visual da janela de documento: mesmo tema/tokens do app (lê o
/// [SettingsController]) em volta de um [DocumentScreen].
class DocumentWindowRoot extends StatelessWidget {
  const DocumentWindowRoot({
    super.key,
    required this.path,
    this.terminalProfiles,
  });

  final String path;

  /// Perfis de terminal — o `.panel` roda `cockpit <line>` no padrão das
  /// configurações. `null` = shell da plataforma.
  final TerminalProfileResolver? terminalProfiles;

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<SettingsController>();
    final s = controller.settings;
    final theme = controller.activeTheme;
    return ShadcnApp(
      title: path.split(Platform.pathSeparator).last,
      debugShowCheckedModeBanner: false,
      popoverHandler: const AppPopoverOverlayHandler(),
      menuHandler: const AppPopoverOverlayHandler(),
      tooltipHandler: const AppPopoverOverlayHandler(),
      scrollBehavior: const ClampingScrollBehavior(),
      theme: buildTheme(
        brightness: Brightness.light,
        settings: s,
        theme: theme,
      ),
      darkTheme: buildTheme(
        brightness: Brightness.dark,
        settings: s,
        theme: theme,
      ),
      themeMode: switch (s.themeMode) {
        AppThemeMode.system => ThemeMode.system,
        AppThemeMode.light => ThemeMode.light,
        AppThemeMode.dark => ThemeMode.dark,
      },
      home: Builder(
        builder: (context) {
          final tokens = buildTokens(
            brightness: Theme.of(context).brightness,
            settings: s,
            theme: theme,
          );
          // Mesmo zoom do app (⌘=/⌘-/⌘0) e mesma escala herdada das settings.
          return CallbackShortcuts(
            bindings: zoomBindings(controller),
            child: Focus(
              autofocus: true,
              child: DefaultSelectionStyle(
                selectionColor: tokens.terminal.selection,
                cursorColor: tokens.colors.accent,
                child: AppZoom(
                  scale: s.interfaceSize / 14.0,
                  child: CockpitTheme(
                    colors: tokens.colors,
                    typo: tokens.typo,
                    syntax: tokens.syntax,
                    terminal: tokens.terminal,
                    child: ColoredBox(
                      color: tokens.colors.bg,
                      child: DocumentScreen(
                        path: path,
                        terminalProfiles: terminalProfiles,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

/// Lê [path] e escolhe o viewer: pasta `.notebook` → caderno; `.kanban` →
/// quadro; `.ckp` → preview do layout; `.panel` → página viva; o resto → [FileViewer] (markdown com preview, código, imagem,
/// mídia). `.dbq`/`.http` abrem como texto aqui: query e request precisam
/// das conexões do workspace, que a janela solta não tem. Relê o arquivo
/// quando ele muda no disco (edição em outra janela ou por agente).
class DocumentScreen extends StatelessWidget {
  const DocumentScreen({
    super.key,
    required this.path,
    this.terminalProfiles,
    this.host,
    this.projectId = '',
    this.sessionId = 'doc',
    this.revealLine,
    this.active = true,
    this.focused = true,
    this.onPanelCall,
    this.onSession,
  });
  final String path;
  final TerminalProfileResolver? terminalProfiles;
  final WorktreeDocumentHost? host;
  final String projectId, sessionId;
  final int? revealLine;
  final bool active, focused;
  final Future<Map<String, Object?>> Function(String, String)? onPanelCall;
  final ValueChanged<FileViewerSession?>? onSession;

  @override
  Widget build(BuildContext context) =>
      _DocumentScreenBody(key: ValueKey((host, path, sessionId)), config: this);
}

/// Rebinding a path/host unmounts the old viewer before disposing its session.
class _DocumentScreenBody extends StatefulWidget {
  const _DocumentScreenBody({super.key, required this.config});
  final DocumentScreen config;
  @override
  State<_DocumentScreenBody> createState() => _DocumentScreenState();
}

class _DocumentScreenState extends State<_DocumentScreenBody>
    with WidgetsBindingObserver {
  DocumentScreen get config => widget.config;
  static const _reader = FileReaderImpl();
  static const _changes = DiskFileChangeWatcher();

  late final StandaloneDocumentHost _host =
      config.host ??
      StandaloneDocumentHost(
        workspaceRoot: StandaloneDocumentHost.findWorkspaceRoot(config.path),
        changes: _changes,
      );
  FileViewerSession? _session;
  NotebookSession? _notebook;
  bool _missing = false;
  Object? _loadError;
  int _loadGeneration = 0;

  /// Live-reload do arquivo (o caderno vigia a própria pasta pelo host).
  /// Rename atômico, rajada de eventos e stream do SO que morre ficam com o
  /// [_changes]; o poll de `stat` dele também cobre a janela oculta, cujo
  /// engine para os frames (numa outra mesa do macOS ou toda coberta).
  StreamSubscription<void>? _watch;

  /// mtime do arquivo na última leitura: ao voltar à vista, confere se algo
  /// mudou enquanto a janela estava oculta.
  DateTime? _loadedAt;

  bool get _isNotebook =>
      config.path.toLowerCase().endsWith('.notebook') &&
      (config.host != null || FileSystemEntity.isDirectorySync(config.path));

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    if (_isNotebook) {
      _notebook = NotebookSession(
        id: config.sessionId,
        projectId: config.projectId,
        path: config.path,
      );
    } else {
      unawaited(_load());
      _watch = _host.changes.watchFile(config.path).listen((_) {
        if (config.active) unawaited(_load());
      });
    }
  }

  @override
  void didUpdateWidget(covariant _DocumentScreenBody oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!oldWidget.config.active && config.active) _reloadIfChanged();
    final line = config.revealLine;
    if (line != null && line != oldWidget.config.revealLine) {
      _session?.reveal(line, select: false);
    }
  }

  Future<void> _load() async {
    final generation = ++_loadGeneration;
    try {
      if (config.host == null && !File(config.path).existsSync()) {
        if (mounted) setState(() => _missing = true);
        return;
      }
      final view =
          await (config.host?.readView(config.path) ??
              _reader.read(config.path));
      if (!mounted || generation != _loadGeneration) return;
      _loadedAt = _mtime();
      final current = _session;
      if (current != null) {
        current.adoptDisk(view);
        if (_missing || _loadError != null) {
          setState(() {
            _missing = false;
            _loadError = null;
          });
        }
        return;
      }
      final session = FileViewerSession(
        id: config.sessionId,
        projectId: config.projectId,
        path: config.path,
        view: view,
      );
      if (config.revealLine case final line?) {
        session.reveal(line, select: false);
      }
      setState(() {
        _missing = false;
        _loadError = null;
        _session = session;
      });
      config.onSession?.call(session);
    } on Object catch (error) {
      if (mounted && generation == _loadGeneration) {
        setState(() => _loadError = error);
      }
    }
  }

  DateTime? _mtime() {
    if (config.host != null) return null;
    try {
      return File(config.path).lastModifiedSync();
    } on FileSystemException {
      return null;
    }
  }

  /// Relê se o arquivo mudou desde a última leitura (mtime diferente). O
  /// caderno não tem um mtime só: pede a recarga dele inteiro.
  void _reloadIfChanged() {
    if (!config.active) return;
    if (_notebook case final notebook?) {
      notebook.requestReload();
      return;
    }
    if (config.host != null) {
      unawaited(_load());
      return;
    }
    final now = _mtime();
    if (now == null || now == _loadedAt) return;
    unawaited(_load());
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Voltou à vista (com foco = resumed, sem foco = inactive): garante o
    // conteúdo atual antes do primeiro frame, sem esperar o poll do watcher.
    if (state == AppLifecycleState.resumed ||
        state == AppLifecycleState.inactive) {
      _reloadIfChanged();
    }
  }

  Future<bool> _save(String content) async {
    final view = _session?.view;
    final encoding = switch (view) {
      FileViewText(:final encoding) ||
      FileViewMarkdown(:final encoding) ||
      FileViewSvg(:final encoding) => encoding,
      _ => utf8,
    };
    List<int> bytes;
    try {
      bytes = encoding.encode(content);
    } on ArgumentError {
      // Match native FileReaderImpl: new characters may require UTF-8.
      bytes = utf8.encode(content);
    }
    final ok = config.host == null
        ? await _host.writeTextAt(config.path, content)
        : await _host.writeBytesAt(config.path, Uint8List.fromList(bytes));
    if (ok) await _load();
    return ok;
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    unawaited(_watch?.cancel());
    config.onSession?.call(null);
    _session?.dispose();
    _notebook?.dispose();
    super.dispose();
  }

  Future<Map<String, Object?>> _refuseUnboundPanelCall(
    String line,
    String cwd,
  ) async => const {
    'ok': false,
    'error': 'Originating terminal is unavailable',
  };

  @override
  Widget build(BuildContext context) {
    final tr = context.t.cockpit.documentWindow;
    final Widget body;
    if (_notebook case final notebook?) {
      body = NotebookView(
        session: notebook,
        active: config.active,
        focused: config.active && config.focused,
        workspaceRoot: _host.workspaceRoot,
      );
    } else if (_missing) {
      body = Center(
        child: Text(
          tr.fileNotFound(path: config.path),
          style: context.typo.body.copyWith(color: context.colors.text3),
        ),
      );
    } else if (_session case final session?) {
      if (config.host == null &&
          (session.view is FileViewAudio || session.view is FileViewVideo)) {
        // media_kit não pode ser inicializado num segundo engine (ver
        // runDocumentWindow); mídia abre na janela principal.
        body = Center(
          child: Text(
            tr.mediaNotSupported,
            style: context.typo.body.copyWith(color: context.colors.text3),
          ),
        );
      } else if (config.path.toLowerCase().endsWith('.kanban')) {
        body = KanbanBoardView(
          session: session,
          active: config.active,
          focused: config.active && config.focused,
          workspaceRoot: _host.workspaceRoot,
          onSave: _save,
          onReload: _load,
          onViewModeChanged: (_) {},
        );
      } else if (config.path.toLowerCase().endsWith('.ckp')) {
        // Layout: a janela solta MOSTRA o que o arquivo faria, mas não tem
        // workspace nenhum para aplicar. O botão despacha para o app, que
        // resolve o destino e pede a confirmação (ver `apply-layout` no
        // cockpit_cli_handler).
        final view = session.view;
        body = LayoutPreviewView(
          path: config.path,
          source: view is FileViewText ? view.text : '',
          hostOs: Platform.operatingSystem,
          primary: config.host != null
              ? null
              : LayoutApplyAction(
                  label: context.t.cockpit.layoutPreview.applyInCockpit,
                  onApply: () => unawaited(
                    RunningInstance.forwardApplyLayout(config.path),
                  ),
                ),
        );
      } else if (config.path.toLowerCase().endsWith('.panel') &&
          config.host?.remote != true) {
        // Painel vivo também na janela solta. A ponte spawna a CLI `cockpit`
        // como na aba; a CLI fala com o app principal pelo socket, então
        // `exec`, `db`, `send`... funcionam daqui. Sem workspace próprio, os
        // verbos que dependem de aba usam o que o humano tem selecionado.
        body = PanelView(
          session: session,
          onCall:
              config.onPanelCall ??
              (config.host != null
                  ? _refuseUnboundPanelCall
                  : (line, cwd) => runPanelCommandLine(
                      line,
                      cwd: cwd,
                      environment: RunningInstance.cliEnvironment,
                      // Lido na chamada (não no build): o padrão pode mudar nas
                      // configurações com a janela aberta.
                      profile: config.terminalProfiles?.effectiveDefault(
                        context
                            .read<SettingsController>()
                            .settings
                            .defaultTerminalProfileId,
                      ),
                    )),
        );
      } else {
        body = FileViewer(
          session: session,
          onSave: _save,
          active: config.active,
          focused: config.active && config.focused,
          allowLocalFileSystem: config.host?.remote != true,
        );
      }
    } else {
      body = _loadError == null
          ? const Center(child: CircularProgressIndicator())
          : const SizedBox.shrink();
    }
    return DocumentHostScope(
      host: _host,
      child: Column(
        children: [
          if (_loadError case final error?)
            Padding(
              padding: const EdgeInsets.all(8),
              child: Row(
                children: [
                  Expanded(child: Text(error.toString())),
                  OutlineButton(
                    onPressed: _load,
                    child: Text(context.t.core.bootstrapError.retry),
                  ),
                ],
              ),
            ),
          Expanded(child: body),
        ],
      ),
    );
  }
}
