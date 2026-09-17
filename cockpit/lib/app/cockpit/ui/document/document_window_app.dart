import 'dart:async';
import 'dart:io';

import 'package:cockpit/app/cockpit/data/filesystem/file_reader_impl.dart';
import 'package:cockpit/app/cockpit/domain/entities/file_view.dart';
import 'package:cockpit/app/cockpit/ui/document/document_windows.dart';
import 'package:cockpit/app/cockpit/ui/document/standalone_document_host.dart';
import 'package:cockpit/app/cockpit/ui/session/document_host.dart';
import 'package:cockpit/app/cockpit/ui/session/file_viewer_session.dart';
import 'package:cockpit/app/cockpit/ui/session/notebook_session.dart';
import 'package:cockpit/app/cockpit/ui/widgets/file_viewer.dart';
import 'package:cockpit/app/cockpit/ui/widgets/kanban_board_view.dart';
import 'package:cockpit/app/cockpit/ui/widgets/notebook_view.dart';
import 'package:cockpit/app/core/data/repositories/json_settings_store.dart';
import 'package:cockpit/app/core/data/setup/json_state_store.dart';
import 'package:cockpit/app/core/data/setup/storage_location.dart';
import 'package:cockpit/app/core/data/theme_store.dart';
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
        child: DocumentWindowRoot(path: path),
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
  const DocumentWindowRoot({super.key, required this.path});

  final String path;

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
                      child: DocumentScreen(path: path),
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
/// quadro; o resto → [FileViewer] (markdown com preview, código, imagem,
/// mídia). `.dbq`/`.http` abrem como texto aqui: query e request precisam
/// das conexões do workspace, que a janela solta não tem. Relê o arquivo
/// quando ele muda no disco (edição em outra janela ou por agente).
class DocumentScreen extends StatefulWidget {
  const DocumentScreen({super.key, required this.path});

  final String path;

  @override
  State<DocumentScreen> createState() => _DocumentScreenState();
}

class _DocumentScreenState extends State<DocumentScreen>
    with WidgetsBindingObserver {
  static const _reader = FileReaderImpl();

  late final StandaloneDocumentHost _host = StandaloneDocumentHost(
    workspaceRoot: StandaloneDocumentHost.findWorkspaceRoot(widget.path),
  );
  FileViewerSession? _session;
  NotebookSession? _notebook;
  bool _missing = false;
  StreamSubscription<FileSystemEvent>? _watch;
  Timer? _debounce;

  /// mtime do arquivo na última leitura. É o que permite conferir, ao voltar
  /// à vista, se perdemos alguma mudança enquanto a janela estava oculta.
  DateTime? _loadedAt;

  /// Enquanto a janela está numa outra mesa do macOS (ou totalmente coberta)
  /// o engine dela recebe `hidden` e o Flutter DESLIGA os frames: o watcher
  /// até dispara e o `setState` até roda, mas nada pinta até a janela voltar.
  /// Este poll confere o mtime a cada 2 s enquanto oculta e força a releitura
  /// ao voltar, pra janela nunca reaparecer com conteúdo velho.
  Timer? _hiddenPoll;

  bool get _isNotebook =>
      widget.path.toLowerCase().endsWith('.notebook') &&
      FileSystemEntity.isDirectorySync(widget.path);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    if (_isNotebook) {
      _notebook = NotebookSession(id: 'doc', projectId: '', path: widget.path);
    } else {
      unawaited(_load());
      _watchFile();
    }
  }

  Future<void> _load() async {
    if (!File(widget.path).existsSync()) {
      if (mounted) setState(() => _missing = true);
      return;
    }
    final view = await _reader.read(widget.path);
    _loadedAt = _mtime();
    if (!mounted) return;
    setState(() {
      _missing = false;
      final current = _session;
      if (current == null) {
        _session = FileViewerSession(
          id: 'doc',
          projectId: '',
          path: widget.path,
          view: view,
        );
      } else {
        current.view = view;
      }
    });
  }

  /// Observa a PASTA do arquivo (evento por nome): mais barato e robusto que
  /// observar o arquivo, que some/renasce em editores que gravam por rename.
  void _watchFile() {
    final dir = File(widget.path).parent;
    try {
      _watch = dir.watch().listen((event) {
        if (event.path != widget.path) return;
        _debounce?.cancel();
        _debounce = Timer(const Duration(milliseconds: 150), _load);
      });
    } on FileSystemException {
      // sem watcher (fs exótico): a janela mostra o que leu ao abrir
    }
  }

  DateTime? _mtime() {
    try {
      return File(widget.path).lastModifiedSync();
    } on FileSystemException {
      return null;
    }
  }

  /// Relê se o arquivo mudou desde a última leitura (mtime diferente).
  void _reloadIfChanged() {
    if (_isNotebook) return;
    final now = _mtime();
    if (now == null || now == _loadedAt) return;
    unawaited(_load());
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    switch (state) {
      case AppLifecycleState.hidden:
      case AppLifecycleState.paused:
        _hiddenPoll ??= Timer.periodic(
          const Duration(seconds: 2),
          (_) => _reloadIfChanged(),
        );
      case AppLifecycleState.resumed:
      case AppLifecycleState.inactive:
      case AppLifecycleState.detached:
        _hiddenPoll?.cancel();
        _hiddenPoll = null;
        _reloadIfChanged();
    }
  }

  Future<bool> _save(String content) async {
    final ok = await _host.writeTextAt(widget.path, content);
    if (ok) await _load();
    return ok;
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _hiddenPoll?.cancel();
    _debounce?.cancel();
    unawaited(_watch?.cancel());
    _session?.dispose();
    _notebook?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final tr = context.t.cockpit.documentWindow;
    final Widget body;
    if (_notebook case final notebook?) {
      body = NotebookView(
        session: notebook,
        active: true,
        focused: true,
        workspaceRoot: _host.workspaceRoot,
      );
    } else if (_missing) {
      body = Center(
        child: Text(
          tr.fileNotFound(path: widget.path),
          style: context.typo.body.copyWith(color: context.colors.text3),
        ),
      );
    } else if (_session case final session?) {
      if (session.view is FileViewAudio || session.view is FileViewVideo) {
        // media_kit não pode ser inicializado num segundo engine (ver
        // runDocumentWindow); mídia abre na janela principal.
        body = Center(
          child: Text(
            tr.mediaNotSupported,
            style: context.typo.body.copyWith(color: context.colors.text3),
          ),
        );
      } else if (widget.path.toLowerCase().endsWith('.kanban')) {
        body = KanbanBoardView(
          session: session,
          active: true,
          focused: true,
          workspaceRoot: _host.workspaceRoot,
          onSave: _save,
          onReload: _load,
          onViewModeChanged: (_) {},
        );
      } else {
        body = FileViewer(session: session, onSave: _save);
      }
    } else {
      body = const Center(child: CircularProgressIndicator());
    }
    return DocumentHostScope(host: _host, child: body);
  }
}
