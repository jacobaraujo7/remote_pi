import 'dart:async';

import 'package:cockpit/app/cockpit/domain/entities/file_view.dart';
import 'package:cockpit/app/cockpit/domain/entities/http_document.dart';
import 'package:cockpit/app/cockpit/domain/entities/http_response_result.dart';
import 'package:cockpit/app/cockpit/domain/services/http_environment_catalog.dart';
import 'package:cockpit/app/cockpit/domain/services/http_code_navigation.dart';
import 'package:cockpit/app/cockpit/ui/session/file_viewer_session.dart';
import 'package:cockpit/app/cockpit/ui/viewmodels/cockpit_viewmodel.dart';
import 'package:cockpit/app/cockpit/ui/viewmodels/http_viewmodel.dart';
import 'package:cockpit/app/cockpit/ui/widgets/code_editor.dart';
import 'package:cockpit/app/cockpit/ui/widgets/http_request_folds.dart';
import 'package:cockpit/app/cockpit/ui/widgets/http_variable_completion.dart';
import 'package:cockpit/app/core/ui/file_operation_error_message.dart';
import 'package:cockpit/app/core/ui/http_request_error_message.dart';
import 'package:cockpit/app/core/ui/menu/editor_menu_bridge.dart';
import 'package:cockpit/app/core/ui/themes/themes.dart';
import 'package:cockpit/app/core/ui/widgets/app_menu.dart';
import 'package:cockpit/app/core/ui/widgets/code_editing_controller.dart';
import 'package:cockpit/app/core/ui/widgets/code_highlight.dart';
import 'package:cockpit/app/core/ui/widgets/hover_tap.dart';
import 'package:cockpit/i18n/strings.g.dart';
import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform;
import 'package:flutter/services.dart'
    show HardwareKeyboard, KeyDownEvent, KeyEvent, LogicalKeyboardKey;
import 'package:flutter_modular/flutter_modular.dart';
import 'package:path/path.dart' as p;
import 'package:shadcn_flutter/shadcn_flutter.dart';

/// Tab de um arquivo `.http`: editor em cima, resposta embaixo, split
/// arrastável — a mesma anatomia da tab `.dbq`, e pelo mesmo motivo reusa a
/// [FileViewerSession] (preview/dirty/watch/persistência de graça); só o
/// render diverge.
///
/// O arquivo **é** a fonte de verdade: nada de estado escondido em
/// frontmatter, ao contrário do `.dbq`. Run executa todas as seções em ordem;
/// os botões do gutter executam uma seção específica.
class HttpRequestView extends StatefulWidget {
  const HttpRequestView({
    super.key,
    required this.session,
    required this.active,
    required this.focused,
    required this.onSave,
  });

  final FileViewerSession session;
  final bool active;
  final bool focused;

  /// Grava o conteúdo do editor no disco.
  final Future<bool> Function(String content) onSave;

  @override
  State<HttpRequestView> createState() => _HttpRequestViewState();
}

class _HttpRequestViewState extends State<HttpRequestView> {
  late final CodeEditingController _text;
  late String _lastSourceText;
  late final CodeEditingController _foldedText;
  final Set<int> _foldedStarts = {};
  late HttpRequestFolds _foldProjection;
  int? _revealFoldLine;
  int _foldTick = 0;
  final FocusNode _focus = FocusNode();
  EditorMenuBridge? _menuBridge;
  HttpEnvironmentCatalog _catalog = const HttpEnvironmentCatalog({});
  final List<StreamSubscription<void>> _environmentWatches = [];
  String? _environmentPath;
  String? _lastEnvironmentSelection;
  int _environmentReadSeq = 0;
  bool _completionVisible = false;
  int _completionIndex = 0;
  int? _plainCompletionOffset;

  /// Conteúdo do disco como o conhecemos (baseline de dirty/discard).
  late String _baseline;
  bool _starting = false;

  /// Estado de view (resposta, split, aba) — mora no [HttpViewModel] para
  /// sobreviver ao re-mount quando a tab muda de pane.
  late final HttpTabState _view;

  @override
  void initState() {
    super.initState();
    _view = context.read<HttpViewModel>().tabStateFor(widget.session.id);
    widget.session.httpEnvironment ??= context
        .read<CockpitViewModel>()
        .httpEnvironmentFor(widget.session.projectId, widget.session.path);
    _lastEnvironmentSelection = widget.session.httpEnvironment;
    _baseline = _diskText();
    _view.syncSource(_baseline, HttpDocument.parse(_baseline).requests.length);
    _view.addListener(_onViewState);
    _text = CodeEditingController(text: _baseline, language: 'http');
    _lastSourceText = _baseline;
    _foldedText = CodeEditingController(text: _baseline, language: 'http');
    _foldProjection = HttpRequestFolds.build(_baseline, _foldedStarts);
    _text.addListener(_onEdited);
    widget.session.addListener(_onSession);
    widget.session.saveDraft = _save;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) unawaited(_loadEnvironments(rewatch: true).then((_) {}));
    });
    if (widget.session.scratch) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) widget.session.setDirty(true);
      });
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _menuBridge = context.read<EditorMenuBridge>();
  }

  @override
  void dispose() {
    _menuBridge?.clear(this);
    for (final watch in _environmentWatches) {
      unawaited(watch.cancel());
    }
    widget.session.removeListener(_onSession);
    _view.removeListener(_onViewState);
    if (widget.session.saveDraft == _save) widget.session.saveDraft = null;
    _text.removeListener(_onEdited);
    _text.dispose();
    _foldedText.dispose();
    _focus.dispose();
    super.dispose();
  }

  String _diskText() => switch (widget.session.view) {
    FileViewText(:final text) => text,
    FileViewMarkdown(:final text) => text,
    _ => '',
  };

  void _onViewState() {
    if (mounted) setState(() {});
  }

  HttpDocument get _doc => HttpDocument.parse(_text.text);

  Future<HttpEnvironmentCatalog> _loadEnvironments({
    bool rewatch = false,
  }) async {
    if (!mounted || widget.session.scratch) return _catalog;
    final vm = context.read<CockpitViewModel>();
    final path = widget.session.path;
    final root =
        vm.rootContaining(widget.session.projectId, path) ??
        (path.startsWith('/') ? p.posix.dirname(path) : p.dirname(path));
    if (rewatch || _environmentPath != path) {
      _environmentPath = path;
      for (final watch in _environmentWatches) {
        unawaited(watch.cancel());
      }
      _environmentWatches.clear();
      for (final folder in HttpEnvironmentCatalog.directoriesFor(path, root)) {
        _environmentWatches.add(
          vm
              .watchFolder(folder)
              .listen((_) => unawaited(_loadEnvironments().then((_) {}))),
        );
      }
    }
    final seq = ++_environmentReadSeq;
    final catalog = await HttpEnvironmentCatalog.load(
      httpPath: path,
      rootPath: root,
      readText: vm.readTextAt,
    );
    if (!mounted || seq != _environmentReadSeq || path != widget.session.path) {
      return catalog;
    }
    setState(() {
      _catalog = catalog;
      if (_completionVisible) _completionIndex = 0;
    });
    _refreshUnresolvedVariables();
    return catalog;
  }

  bool get _dirty => widget.session.scratch || _text.text != _baseline;

  void _onEdited() {
    // Editar pode mover as linhas dos requests e seus botões no gutter.
    final textChanged = _text.text != _lastSourceText;
    if (textChanged) {
      if (_foldedStarts.isNotEmpty) _foldedStarts.clear();
      _rebuildFoldedText();
    }
    _lastSourceText = _text.text;
    _updateCompletion(textChanged: textChanged);
    if (textChanged) _view.syncSource(_text.text, _doc.requests.length);
    if (textChanged) _refreshUnresolvedVariables();
    if (mounted && (textChanged || _foldedStarts.isEmpty)) setState(() {});
    widget.session.setDirty(_dirty);
  }

  HttpVariableSlot? get _variableSlot {
    final selection = _text.selection;
    if (!selection.isValid || !selection.isCollapsed) return null;
    return HttpVariableCompletion.slotAt(_text.text, selection.baseOffset);
  }

  List<String> get _completionOptions {
    final slot = _variableSlot;
    if (slot == null && _plainCompletionOffset == null) return const [];
    final names = <String>{
      ..._catalog.valuesFor(widget.session.httpEnvironment).keys,
      ..._doc.variables.keys,
    }.toList()..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
    final query = slot?.prefix.trim().toLowerCase() ?? '';
    return names.where((name) => name.toLowerCase().startsWith(query)).toList();
  }

  void _updateCompletion({required bool textChanged}) {
    if (_plainCompletionOffset != null) {
      if (textChanged || _text.selection.baseOffset != _plainCompletionOffset) {
        _plainCompletionOffset = null;
        _completionVisible = false;
        _completionIndex = 0;
      }
      return;
    }
    final slot = _variableSlot;
    if (slot == null) {
      _completionVisible = false;
      _completionIndex = 0;
    } else if (textChanged) {
      _completionVisible = slot.prefix.isNotEmpty;
      _completionIndex = 0;
    } else if (_completionVisible) {
      final count = _completionOptions.length;
      if (count > 0 && _completionIndex >= count) _completionIndex = count - 1;
    }
  }

  bool _completionKey(KeyEvent event) {
    if (event is! KeyDownEvent) return false;
    if (_foldedStarts.isNotEmpty) return false;
    final key = event.logicalKey;
    final keys = HardwareKeyboard.instance;
    if (key == LogicalKeyboardKey.space &&
        (keys.isControlPressed ||
            (defaultTargetPlatform == TargetPlatform.macOS &&
                keys.isMetaPressed))) {
      final selection = _text.selection;
      if (!selection.isValid || !selection.isCollapsed) return false;
      setState(() {
        _plainCompletionOffset = _variableSlot == null
            ? selection.baseOffset
            : null;
        _completionVisible = true;
        _completionIndex = 0;
      });
      return true;
    }
    if (!_completionVisible) return false;
    if (key == LogicalKeyboardKey.escape) {
      setState(() {
        _completionVisible = false;
        _plainCompletionOffset = null;
      });
      return true;
    }
    if (keys.isControlPressed || keys.isMetaPressed || keys.isAltPressed) {
      return false;
    }
    final options = _completionOptions;
    if (key == LogicalKeyboardKey.arrowDown && options.isNotEmpty) {
      setState(
        () => _completionIndex = (_completionIndex + 1) % options.length,
      );
      return true;
    }
    if (key == LogicalKeyboardKey.arrowUp && options.isNotEmpty) {
      setState(
        () => _completionIndex =
            (_completionIndex - 1 + options.length) % options.length,
      );
      return true;
    }
    if (key == LogicalKeyboardKey.enter || key == LogicalKeyboardKey.tab) {
      if (options.isNotEmpty) {
        _completeVariable(
          options[_completionIndex.clamp(0, options.length - 1)],
        );
      } else {
        setState(() {
          _completionVisible = false;
          _plainCompletionOffset = null;
        });
      }
      return true;
    }
    return false;
  }

  void _completeVariable(String name) {
    final slot = _variableSlot;
    if (slot != null) {
      _text.value = HttpVariableCompletion.complete(_text.value, slot, name);
    } else if (_plainCompletionOffset case final offset?) {
      _text.value = HttpVariableCompletion.insertAt(_text.value, offset, name);
    } else {
      return;
    }
    setState(() {
      _completionVisible = false;
      _plainCompletionOffset = null;
    });
    _focus.requestFocus();
  }

  void _refreshUnresolvedVariables() {
    if (!mounted) return;
    final selected = widget.session.httpEnvironment;
    final environment = _catalog.valuesFor(selected);
    final tr = context.t.cockpit.httpView;
    for (final controller in [_text, _foldedText]) {
      final missing = HttpDocument.unresolvedPlaceholders(
        controller.text,
        environment: environment,
      );
      controller.setUnresolvedVariables([
        for (final item in missing)
          UnresolvedCodeVariable(
            item.start,
            item.end,
            selected == null
                ? tr.unresolvedVariableNoEnvironment(name: item.name)
                : tr.unresolvedVariableInEnvironment(
                    name: item.name,
                    environment: selected,
                  ),
          ),
      ]);
    }
  }

  void _rebuildFoldedText() {
    _foldProjection = HttpRequestFolds.build(_text.text, _foldedStarts);
    _foldedText.text = _foldProjection.text;
    _foldedText.selection = const TextSelection.collapsed(offset: 0);
  }

  void _toggleFold(int sourceLine) {
    _completionVisible = false;
    _plainCompletionOffset = null;
    if (!_foldedStarts.remove(sourceLine)) _foldedStarts.add(sourceLine);
    _rebuildFoldedText();
    _refreshUnresolvedVariables();
    _revealFoldLine =
        (_foldedStarts.isEmpty
            ? sourceLine
            : _foldProjection.visibleBySource[sourceLine] ?? 0) +
        1;
    _foldTick++;
    setState(() {});
  }

  void _expandForEdit() {
    if (_foldedStarts.isEmpty) return;
    _completionVisible = false;
    _plainCompletionOffset = null;
    _foldedStarts.clear();
    _rebuildFoldedText();
    _refreshUnresolvedVariables();
    setState(() {});
  }

  HttpCodeLink? _codeLinkAt(int offset) {
    final display = _foldedStarts.isEmpty ? _text.text : _foldedText.text;
    if (offset < 0 || offset >= display.length) return null;
    final displayLine = '\n'.allMatches(display.substring(0, offset)).length;
    final sourceLine = _foldedStarts.isEmpty
        ? displayLine
        : _foldProjection.lineNumbers[displayLine] - 1;
    return HttpCodeNavigation.linkAt(
      displayText: display,
      offset: offset,
      sourceText: _text.text,
      sourcePath: widget.session.path,
      sourceLine: sourceLine,
      environment: widget.session.httpEnvironment,
      catalog: _catalog,
    );
  }

  void _openCodeLink(int offset) {
    final link = _codeLinkAt(offset);
    if (link == null) return;
    final vm = context.read<CockpitViewModel>();
    if (link.path case final path?) {
      unawaited(vm.openFile(path, isPreview: false, revealLine: link.line));
    } else if (link.url case final url?) {
      if (defaultTargetPlatform == TargetPlatform.linux ||
          vm.openWebBrowser(url, projectId: widget.session.projectId) == null) {
        unawaited(vm.openUrlExternally(url));
      }
    }
  }

  /// Mudança vinda do disco (watcher / agente salvou): adota o conteúdo novo
  /// se o buffer local não está sujo. **Não** re-executa sozinho, ao contrário
  /// do `.dbq`: request tem efeito colateral no servidor: quem dispara é o
  /// humano.
  void _onSession() {
    if (_lastEnvironmentSelection != widget.session.httpEnvironment) {
      _lastEnvironmentSelection = widget.session.httpEnvironment;
      _completionIndex = 0;
      _refreshUnresolvedVariables();
      if (mounted) setState(() {});
    }
    if (_environmentPath != widget.session.path && !widget.session.scratch) {
      unawaited(_loadEnvironments(rewatch: true).then((_) {}));
    }
    if (widget.session.scratch) return;
    final text = _diskText();
    if (text == _baseline || widget.session.dirty) return;
    setState(() {
      _baseline = text;
      if (_text.text != text) _text.text = text;
    });
  }

  Future<bool> _save() async {
    if (!_dirty) return true;
    final content = _text.text;
    if (widget.session.scratch) {
      final name = await _promptName();
      if (name == null || !mounted) return false;
      final result = await context.read<CockpitViewModel>().saveScratchAs(
        widget.session.id,
        name,
        content,
      );
      if (!mounted) return false;
      final error = result.fold((_) => null, (f) => f);
      if (error != null) {
        _showError(
          context.t.cockpit.httpView.couldNotSave,
          fileOperationErrorMessage(context, error),
        );
        return false;
      }
      setState(() => _baseline = content);
      widget.session.setDirty(_dirty);
      return true;
    }
    final ok = await widget.onSave(content);
    if (!mounted) return ok;
    if (ok) {
      setState(() => _baseline = content);
      widget.session.setDirty(_dirty);
    }
    return ok;
  }

  Future<String?> _promptName() {
    final ctrl = TextEditingController(text: 'requests.http');
    return showDialog<String>(
      context: context,
      builder: (context) {
        final colors = context.colors;
        return AlertDialog(
          title: Text(
            context.t.cockpit.httpView.saveRequestAs,
            style: context.typo.title.copyWith(
              fontSize: 15,
              color: colors.text,
            ),
          ),
          content: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 360),
            child: TextField(
              controller: ctrl,
              autofocus: true,
              style: context.typo.mono.copyWith(
                fontSize: 12.5,
                color: colors.text,
              ),
              border: Border.all(color: colors.border),
              borderRadius: BorderRadius.circular(6),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
              onSubmitted: (v) => Navigator.of(context).pop(v),
            ),
          ),
          actions: [
            GhostButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text(context.t.common.cancel),
            ),
            PrimaryButton(
              onPressed: () => Navigator.of(context).pop(ctrl.text),
              child: Text(context.t.common.save),
            ),
          ],
        );
      },
    );
  }

  void _showError(String title, String message) {
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(
          title,
          style: context.typo.title.copyWith(
            fontSize: 15,
            color: context.colors.text,
          ),
        ),
        content: Text(
          message,
          style: context.typo.body.copyWith(
            fontSize: 13,
            color: context.colors.text2,
          ),
        ),
        actions: [
          PrimaryButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(context.t.common.ok),
          ),
        ],
      ),
    );
  }

  void _discard() {
    setState(() => _text.text = _baseline);
    widget.session.setDirty(_dirty);
  }

  int get _cursorLine {
    final display = _foldedStarts.isEmpty ? _text : _foldedText;
    final selection = display.selection;
    final offset = selection.isValid ? selection.baseOffset : 0;
    final line = '\n'
        .allMatches(
          display.text.substring(0, offset.clamp(0, display.text.length)),
        )
        .length;
    return _foldedStarts.isEmpty ? line : _foldProjection.lineNumbers[line] - 1;
  }

  int _currentRequestIndex(HttpDocument doc) {
    final index = doc.requestIndexAtLine(_cursorLine);
    return index < 0 ? 0 : index;
  }

  void _runCurrent() {
    final doc = _doc;
    if (doc.requests.isNotEmpty) unawaited(_run(_currentRequestIndex(doc)));
  }

  void _runAll() => unawaited(_run());

  Future<void> _run([int? requestIndex]) async {
    if (_view.isRunning || _starting) return;
    setState(() => _starting = true);
    try {
      await _runResolved(requestIndex);
    } finally {
      if (mounted) setState(() => _starting = false);
    }
  }

  Future<void> _runResolved(int? requestIndex) async {
    final catalog = await _loadEnvironments();
    if (!mounted) return;
    final doc = _doc;
    if (doc.requests.isEmpty) return;
    // Arquivo real: Run salva antes (o arquivo é o que o agente e a CLI leem).
    if (!widget.session.scratch && _dirty) {
      if (!await _save() || !mounted) return;
    }

    if (requestIndex != null && requestIndex >= doc.requests.length) return;
    final baseDir = widget.session.scratch
        ? ''
        : widget.session.workingDirectory;

    await _view.runRequests(
      context.read<HttpViewModel>().runner,
      doc.requests,
      baseDir: baseDir,
      onlyIndex: requestIndex,
      document: doc,
      environment: catalog.valuesFor(widget.session.httpEnvironment),
    );
  }

  Future<void> _pickEnvironment(BuildContext anchor) async {
    final catalog = await _loadEnvironments();
    if (!mounted || !anchor.mounted) return;
    final selected = widget.session.httpEnvironment;
    final picked = await showAppMenu<String>(
      anchor,
      items: [
        AppMenuItem(
          value: '',
          label: context.t.cockpit.httpView.noEnvironment,
          selected: selected == null,
        ),
        for (final name in catalog.names)
          AppMenuItem(value: name, label: name, selected: name == selected),
      ],
    );
    if (!mounted || picked == null) return;
    context.read<CockpitViewModel>().setHttpEnvironment(
      widget.session.id,
      picked.isEmpty ? null : picked,
    );
  }

  void _syncMenuBridge() {
    final bridge = _menuBridge;
    if (bridge == null) return;
    if (widget.focused) {
      bridge.publish(
        owner: this,
        canSave: _dirty,
        canDiscard: _dirty,
        canFormat: false,
        onSave: _save,
        onDiscard: _discard,
        onFormat: () {},
      );
    } else {
      bridge.clear(this);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final doc = _doc;
    final foldEnds = _foldProjection.foldEnds;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _syncMenuBridge();
    });
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.keyS, meta: true): _save,
        const SingleActivator(LogicalKeyboardKey.keyS, control: true): _save,
        const SingleActivator(LogicalKeyboardKey.enter, meta: true):
            _runCurrent,
        const SingleActivator(LogicalKeyboardKey.enter, control: true):
            _runCurrent,
        const SingleActivator(
          LogicalKeyboardKey.enter,
          meta: true,
          shift: true,
        ): _runAll,
        const SingleActivator(
          LogicalKeyboardKey.enter,
          control: true,
          shift: true,
        ): _runAll,
      },
      child: ColoredBox(
        color: colors.panel,
        child: Column(
          children: [
            _topBar(context),
            Expanded(
              child: LayoutBuilder(
                builder: (context, box) {
                  final editorH = (box.maxHeight * _view.split).clamp(
                    90.0,
                    box.maxHeight - 110,
                  );
                  return Column(
                    children: [
                      SizedBox(
                        height: editorH,
                        child: CodeEditor(
                          key: ValueKey(_foldedStarts.isNotEmpty),
                          controller: _foldedStarts.isEmpty
                              ? _text
                              : _foldedText,
                          compactGutter: true,
                          focusNode: _focus,
                          revealLine: _revealFoldLine,
                          revealSelect: false,
                          revealTick: _foldTick,
                          readOnly: _foldedStarts.isNotEmpty,
                          onCodeTap: _foldedStarts.isEmpty
                              ? null
                              : _expandForEdit,
                          linkRangeAt: (offset) {
                            final link = _codeLinkAt(offset);
                            return link == null
                                ? null
                                : (start: link.start, end: link.end);
                          },
                          onLinkTap: _openCodeLink,
                          autoCloseHttpVariables: _foldedStarts.isEmpty,
                          completionVisible:
                              _foldedStarts.isEmpty && _completionVisible,
                          completionItems: _completionOptions,
                          completionIndex: _completionIndex,
                          completionEmptyLabel:
                              context.t.cockpit.httpView.noMatchingVariables,
                          onCompletionSelected: _completeVariable,
                          onCompletionKey: _completionKey,
                          lineNumbers: _foldedStarts.isEmpty
                              ? null
                              : _foldProjection.lineNumbers,
                          lineActions: _view.isRunning || _starting
                              ? const {}
                              : {
                                  for (var i = 0; i < doc.requests.length; i++)
                                    if (_foldedStarts.isEmpty ||
                                        _foldProjection.visibleBySource
                                            .containsKey(
                                              doc.requests[i].requestLine,
                                            ))
                                      (_foldedStarts.isEmpty
                                          ? doc.requests[i].requestLine
                                          : _foldProjection.visibleBySource[doc
                                                .requests[i]
                                                .requestLine]!): () =>
                                          _run(i),
                                },
                          foldActions: {
                            for (final sourceLine in foldEnds.keys)
                              if (_foldedStarts.isEmpty ||
                                  _foldProjection.visibleBySource.containsKey(
                                    sourceLine,
                                  ))
                                (_foldedStarts.isEmpty
                                    ? sourceLine
                                    : _foldProjection
                                          .visibleBySource[sourceLine]!): () =>
                                    _toggleFold(sourceLine),
                          },
                          foldedLines: {
                            for (final sourceLine in _foldedStarts)
                              if (_foldProjection.visibleBySource.containsKey(
                                sourceLine,
                              ))
                                _foldProjection.visibleBySource[sourceLine]!,
                          },
                          lineActionTooltip: context.t.cockpit.httpView.run,
                        ),
                      ),
                      MouseRegion(
                        cursor: SystemMouseCursors.resizeUpDown,
                        child: GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onVerticalDragUpdate: (d) => setState(() {
                            _view.split =
                                ((editorH + d.delta.dy) / box.maxHeight).clamp(
                                  0.12,
                                  0.85,
                                );
                          }),
                          child: SizedBox(
                            height: 7,
                            child: Center(
                              child: Container(
                                height: 1,
                                color: colors.border2,
                              ),
                            ),
                          ),
                        ),
                      ),
                      Expanded(child: _responseArea(context)),
                    ],
                  );
                },
              ),
            ),
            _footer(context),
          ],
        ),
      ),
    );
  }

  Widget _topBar(BuildContext context) {
    final colors = context.colors;
    final typo = context.typo;
    final tr = context.t.cockpit.httpView;
    final doc = _doc;
    final empty = doc.requests.isEmpty;
    final runBg = empty ? colors.panel3 : colors.accent;
    final runFg = onColor(runBg);
    return Container(
      height: 36,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: colors.border)),
      ),
      child: Row(
        children: [
          Icon(Icons.language, size: 14, color: colors.accent),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              empty ? tr.noRequests : tr.requestCount(n: doc.requests.length),
              overflow: TextOverflow.ellipsis,
              style: typo.label.copyWith(
                fontSize: 11,
                color: empty ? colors.warn : colors.text2,
              ),
            ),
          ),
          Builder(
            builder: (anchor) => HoverTap(
              onTap: () => _pickEnvironment(anchor),
              color: colors.panel3,
              borderRadius: const BorderRadius.all(Radius.circular(4)),
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 150),
                    child: Text(
                      widget.session.httpEnvironment ?? tr.noEnvironment,
                      overflow: TextOverflow.ellipsis,
                      style: typo.label.copyWith(
                        fontSize: 11,
                        color: colors.text2,
                      ),
                    ),
                  ),
                  const SizedBox(width: 4),
                  Icon(
                    Icons.keyboard_arrow_down,
                    size: 13,
                    color: colors.text3,
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 8),
          HoverTap(
            onTap: _view.isRunning || _starting || empty ? null : _runAll,
            color: runBg,
            hoverColor: colors.accent.withValues(alpha: 0.85),
            borderRadius: const BorderRadius.all(Radius.circular(5)),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  _view.isRunning || _starting
                      ? Icons.hourglass_top
                      : Icons.play_arrow,
                  size: 13,
                  color: runFg,
                ),
                const SizedBox(width: 4),
                Text(
                  _view.isRunning || _starting ? tr.running : tr.runAll,
                  style: typo.label.copyWith(fontSize: 11.5, color: runFg),
                ),
                const SizedBox(width: 6),
                Text(
                  defaultTargetPlatform == TargetPlatform.macOS
                      ? '⌘⇧↵'
                      : 'Ctrl+Shift+↵',
                  style: typo.label.copyWith(
                    fontSize: 9.5,
                    color: runFg.withValues(alpha: 0.7),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _responseArea(BuildContext context) {
    final doc = _doc;
    return Column(
      children: [
        if (doc.requests.isNotEmpty) _resultSelector(context, doc),
        Expanded(child: _responseContent(context)),
      ],
    );
  }

  String _requestOptionLabel(HttpDocument doc, int index) {
    final name = doc.requests[index].name.trim();
    return name.isEmpty ? '#${index + 1}' : name;
  }

  Widget _requestStatusIcon(BuildContext context, HttpRequestRunStatus status) {
    final colors = context.colors;
    return Icon(
      switch (status) {
        HttpRequestRunStatus.idle => Icons.radio_button_unchecked,
        HttpRequestRunStatus.loading => Icons.hourglass_top,
        HttpRequestRunStatus.success => Icons.check_circle_outline,
        HttpRequestRunStatus.error => Icons.cancel_outlined,
      },
      size: 15,
      color: switch (status) {
        HttpRequestRunStatus.idle => colors.text3,
        HttpRequestRunStatus.loading => colors.accent,
        HttpRequestRunStatus.success => colors.ok,
        HttpRequestRunStatus.error => colors.warn,
      },
    );
  }

  Future<void> _pickResult(BuildContext anchor, HttpDocument doc) async {
    final picked = await showAppMenu<int>(
      anchor,
      minWidth: 250,
      items: [
        for (var i = 0; i < doc.requests.length; i++)
          AppMenuItem(
            value: i,
            label: _requestOptionLabel(doc, i),
            leading: _requestStatusIcon(context, _view.outcomes[i].status),
            selected: i == _view.selectedRequest,
          ),
      ],
    );
    if (!mounted || picked == null || picked >= _view.outcomes.length) return;
    setState(() => _view.selectedRequest = picked);
  }

  Widget _resultSelector(BuildContext context, HttpDocument doc) {
    final colors = context.colors;
    final selected = _view.selectedRequest.clamp(0, doc.requests.length - 1);
    final outcome = _view.outcomes[selected];
    return Container(
      height: 37,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      alignment: Alignment.centerLeft,
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: colors.border)),
      ),
      child: Builder(
        builder: (anchor) => HoverTap(
          onTap: () => _pickResult(anchor, doc),
          color: colors.panel3,
          borderRadius: const BorderRadius.all(Radius.circular(4)),
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _requestStatusIcon(context, outcome.status),
              const SizedBox(width: 7),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 320),
                child: Text(
                  _requestOptionLabel(doc, selected),
                  overflow: TextOverflow.ellipsis,
                  style: context.typo.label.copyWith(
                    fontSize: 11.5,
                    color: colors.text2,
                  ),
                ),
              ),
              const SizedBox(width: 6),
              Icon(Icons.keyboard_arrow_down, size: 14, color: colors.text3),
            ],
          ),
        ),
      ),
    );
  }

  Widget _responseContent(BuildContext context) {
    final colors = context.colors;
    final typo = context.typo;
    final tr = context.t.cockpit.httpView;

    final outcome = _view.selectedOutcome;
    if (_view.pane == HttpResponsePane.tests && outcome != null) {
      final lines = outcome.tests.isEmpty
          ? tr.noTests
          : outcome.tests
                .map(
                  (test) =>
                      '${test.passed ? '✓' : '✕'} ${test.name}${test.message == null ? '' : ' — ${test.message}'}',
                )
                .join('\n');
      return SingleChildScrollView(
        padding: const EdgeInsets.all(14),
        child: SelectableText(
          lines,
          style: typo.mono.copyWith(fontSize: 12, color: colors.text2),
        ),
      );
    }
    if (_view.pane == HttpResponsePane.script && outcome != null) {
      final text = [
        if (outcome.scriptError != null) outcome.scriptError!,
        ...outcome.logs,
      ].join('\n');
      return SingleChildScrollView(
        padding: const EdgeInsets.all(14),
        child: SelectableText(
          text.isEmpty ? tr.noScriptOutput : text,
          style: typo.mono.copyWith(fontSize: 12, color: colors.text2),
        ),
      );
    }
    if (outcome?.scriptError != null && outcome?.result == null) {
      return SingleChildScrollView(
        padding: const EdgeInsets.all(14),
        child: SelectableText(
          outcome!.scriptError!,
          style: typo.mono.copyWith(fontSize: 12, color: colors.error),
        ),
      );
    }
    final error = outcome?.error;
    if (error != null) {
      return Container(
        alignment: Alignment.topLeft,
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.error_outline, size: 14, color: colors.error),
                const SizedBox(width: 6),
                Text(
                  tr.error.title,
                  style: typo.label.copyWith(
                    fontSize: 11.5,
                    color: colors.error,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            SelectableText(
              httpRequestErrorMessage(context, error),
              style: typo.mono.copyWith(fontSize: 12, color: colors.text2),
            ),
          ],
        ),
      );
    }

    final result = outcome?.result;
    if (result == null) {
      return Center(
        child: Text(
          outcome?.status == HttpRequestRunStatus.loading
              ? tr.running
              : tr.runHint,
          style: typo.label.copyWith(fontSize: 12, color: colors.text3),
        ),
      );
    }

    final text = _paneText(result);
    if (text.isEmpty) {
      return Center(
        child: Text(
          tr.emptyBody,
          style: typo.label.copyWith(fontSize: 12, color: colors.text3),
        ),
      );
    }

    final baseStyle = typo.mono.copyWith(fontSize: 12, color: colors.text2);
    // Realce da resposta: JSON no Body (quando parseia), gramática do `.http`
    // nos Headers (`Nome: valor`). Raw fica cru de propósito — é o modo "me
    // mostra exatamente o que veio". `buildCodeSpan` devolve null quando não
    // há o que pintar; aí cai no texto simples.
    final language = switch (_view.pane) {
      HttpResponsePane.body => result.prettyJson != null ? 'json' : null,
      HttpResponsePane.headers => 'http',
      HttpResponsePane.raw => null,
      HttpResponsePane.tests => null,
      HttpResponsePane.script => null,
    };
    final span = language == null
        ? null
        : buildCodeSpan(
            context,
            source: text,
            language: language,
            baseStyle: baseStyle,
          );

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
      // O viewport dá ao filho a largura da pane, mas sem isto o texto de uma
      // linha só encolhe e o `SingleChildScrollView` o centraliza — era o que
      // deixava a resposta boiando no meio. Largura cheia + alinhamento
      // explícito prendem tudo à esquerda.
      child: SizedBox(
        width: double.infinity,
        child: span == null
            ? SelectableText(text, textAlign: TextAlign.start, style: baseStyle)
            : SelectableText.rich(span, textAlign: TextAlign.start),
      ),
    );
  }

  /// Texto da aba corrente (Body/Headers/Raw) — mesma fonte para o render e
  /// para o Copy, para nunca copiarem coisas diferentes.
  String _paneText(HttpResponseResult result) => switch (_view.pane) {
    HttpResponsePane.headers => [
      for (final h in result.headers) '${h.name}: ${h.value}',
    ].join('\n'),
    HttpResponsePane.raw => result.bodyText,
    HttpResponsePane.body => result.prettyJson ?? result.bodyText,
    HttpResponsePane.tests => '',
    HttpResponsePane.script => '',
  };

  Widget _footer(BuildContext context) {
    final colors = context.colors;
    final typo = context.typo;
    final tr = context.t.cockpit.httpView;
    final result = _view.selectedOutcome?.result;
    final info = StringBuffer();
    if (result != null) {
      info.write('${result.statusCode} ${result.reasonPhrase}'.trim());
      info.write(' · ${result.elapsed.inMilliseconds} ms');
      info.write(' · ${_humanBytes(result.sizeBytes)}');
      if (result.truncated) info.write(tr.truncatedSuffix);
    }
    return Container(
      height: 26,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: colors.border)),
      ),
      child: Row(
        children: [
          if (result != null) ...[
            Container(
              width: 7,
              height: 7,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: _statusColor(context, result.statusCode),
              ),
            ),
            const SizedBox(width: 6),
          ],
          Expanded(
            child: Text(
              info.toString(),
              overflow: TextOverflow.ellipsis,
              style: typo.label.copyWith(fontSize: 10.5, color: colors.text3),
            ),
          ),
          // Seletor da view da resposta — mesmo lugar e mesmo estilo do
          // toggle Table/JSON da tab `.dbq`.
          Flexible(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  if (result != null) ...[
                    _PaneToggle(
                      label: tr.body,
                      active: _view.pane == HttpResponsePane.body,
                      onTap: () =>
                          setState(() => _view.pane = HttpResponsePane.body),
                    ),
                    _PaneToggle(
                      label: tr.headers,
                      active: _view.pane == HttpResponsePane.headers,
                      onTap: () =>
                          setState(() => _view.pane = HttpResponsePane.headers),
                    ),
                    _PaneToggle(
                      label: tr.raw,
                      active: _view.pane == HttpResponsePane.raw,
                      onTap: () =>
                          setState(() => _view.pane = HttpResponsePane.raw),
                    ),
                  ],
                  if (_view.selectedOutcome?.status !=
                      HttpRequestRunStatus.idle) ...[
                    _PaneToggle(
                      label: tr.tests,
                      active: _view.pane == HttpResponsePane.tests,
                      onTap: () =>
                          setState(() => _view.pane = HttpResponsePane.tests),
                    ),
                    _PaneToggle(
                      label: tr.script,
                      active: _view.pane == HttpResponsePane.script,
                      onTap: () =>
                          setState(() => _view.pane = HttpResponsePane.script),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Color _statusColor(BuildContext context, int status) {
    final colors = context.colors;
    if (status >= 500) return colors.error;
    if (status >= 400) return colors.warn;
    if (status >= 200 && status < 300) return colors.ok;
    return colors.text3;
  }

  static String _humanBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) {
      return '${(bytes / 1024).toStringAsFixed(1)} kB';
    }
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
}

/// Botão compacto do seletor Body/Headers/Raw no rodapé.
class _PaneToggle extends StatelessWidget {
  const _PaneToggle({
    required this.label,
    required this.active,
    required this.onTap,
  });

  final String label;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return HoverTap(
      onTap: onTap,
      color: active ? colors.panel3 : null,
      borderRadius: const BorderRadius.all(Radius.circular(4)),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      child: Text(
        label,
        style: context.typo.label.copyWith(
          fontSize: 10.5,
          color: active ? colors.text : colors.text4,
        ),
      ),
    );
  }
}
