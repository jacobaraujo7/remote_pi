import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:cockpit/app/core/utils/text_clipboard.dart';
import 'package:cockpit/app/cockpit/domain/entities/file_view.dart';
import 'package:cockpit/app/cockpit/domain/entities/http_document.dart';
import 'package:cockpit/app/cockpit/domain/entities/http_response_result.dart';
import 'package:cockpit/app/cockpit/domain/services/http_environment_catalog.dart';
import 'package:cockpit/app/cockpit/domain/services/http_script_session.dart';
import 'package:cockpit/app/cockpit/domain/services/http_code_navigation.dart';
import 'package:cockpit/app/cockpit/ui/session/file_viewer_session.dart';
import 'package:cockpit/app/cockpit/ui/viewmodels/cockpit_viewmodel.dart';
import 'package:cockpit/app/cockpit/ui/viewmodels/http_viewmodel.dart';
import 'package:cockpit/app/cockpit/ui/widgets/code_editor.dart';
import 'package:cockpit/app/cockpit/ui/widgets/http_request_folds.dart';
import 'package:cockpit/app/cockpit/ui/widgets/http_response_code_view.dart';
import 'package:cockpit/app/cockpit/ui/widgets/http_response_folds.dart';
import 'package:cockpit/app/cockpit/ui/widgets/http_script_completion.dart';
import 'package:cockpit/app/cockpit/ui/widgets/http_variable_completion.dart';
import 'package:cockpit/app/cockpit/ui/widgets/http_variable_override_popover.dart';
import 'package:cockpit/app/core/ui/file_operation_error_message.dart';
import 'package:cockpit/app/core/ui/http_request_error_message.dart';
import 'package:cockpit/app/core/ui/menu/editor_menu_bridge.dart';
import 'package:cockpit/app/core/ui/themes/themes.dart';
import 'package:cockpit/app/core/ui/widgets/app_menu.dart';
import 'package:cockpit/app/core/ui/widgets/app_tooltip.dart';
import 'package:cockpit/app/core/ui/widgets/code_editing_controller.dart';
import 'package:cockpit/app/core/ui/widgets/hover_tap.dart';
import 'package:cockpit/i18n/strings.g.dart';
import 'package:file_picker/file_picker.dart';
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
  late final Set<int> _foldedStarts;
  late HttpRequestFolds _foldProjection;
  ({int oldLine, int newLine, int tick})? _foldScrollAnchor;
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
  HttpResponseResult? _completionBodyResult;
  Object? _completionBodyJson;
  final Map<String, Object?> _responseBodiesForCompletion = {};

  /// Conteúdo do disco como o conhecemos (baseline de dirty/discard).
  late String _baseline;
  bool _starting = false;

  /// Estado de view (resposta, split, aba) — mora no [HttpViewModel] para
  /// sobreviver ao re-mount quando a tab muda de pane.
  late final HttpTabState _view;

  @override
  void initState() {
    super.initState();
    _view = context.read<HttpViewModel>().tabStateFor(
      widget.session.id,
      projectId: widget.session.scratch ? null : widget.session.projectId,
      path: widget.session.scratch ? null : widget.session.path,
    );
    _foldedStarts = _view.foldedStarts;
    widget.session.httpEnvironment ??= context
        .read<CockpitViewModel>()
        .httpEnvironmentFor(widget.session.projectId, widget.session.path);
    _lastEnvironmentSelection = widget.session.httpEnvironment;
    _baseline = _diskText();
    _view.syncSource(_baseline, HttpDocument.parse(_baseline).requests.length);
    _view.addListener(_onViewState);
    HttpScriptSession.shared.addListener(_onGlobalsChanged);
    _text = CodeEditingController(text: _baseline, language: 'http');
    _lastSourceText = _baseline;
    _foldProjection = HttpRequestFolds.build(_baseline, _foldedStarts);
    _foldedText = CodeEditingController(
      text: _foldProjection.text,
      language: 'http',
    );
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
    HttpScriptSession.shared.removeListener(_onGlobalsChanged);
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
    if (!mounted) return;
    _refreshUnresolvedVariables();
    setState(() {});
  }

  void _onGlobalsChanged() {
    if (!mounted) return;
    _refreshUnresolvedVariables();
    setState(() {});
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
      if (_view.outcomes.any((outcome) => outcome.result != null)) {
        final previous = HttpDocument.parse(_lastSourceText);
        for (
          var i = 0;
          i < previous.requests.length && i < _view.outcomes.length;
          i++
        ) {
          final result = _view.outcomes[i].result;
          if (result != null) {
            _responseBodiesForCompletion[_responseCompletionKey(
              i,
              previous.requests[i],
            )] = _decodeCompletionBody(
              result,
            );
          }
        }
        while (_responseBodiesForCompletion.length > 24) {
          _responseBodiesForCompletion.remove(
            _responseBodiesForCompletion.keys.first,
          );
        }
      }
      _view.syncSource(_text.text, _doc.requests.length);
      _rebuildFoldedText();
    }
    _lastSourceText = _text.text;
    _updateCompletion(textChanged: textChanged);
    if (textChanged) _refreshUnresolvedVariables();
    if (mounted && (textChanged || _foldedStarts.isEmpty)) setState(() {});
    widget.session.setDirty(_dirty);
  }

  HttpVariableSlot? get _variableSlot {
    final selection = _text.selection;
    if (!selection.isValid || !selection.isCollapsed) return null;
    if (HttpScriptCompletion.insideBlock(_text.text, selection.baseOffset)) {
      return null;
    }
    return HttpVariableCompletion.slotAt(_text.text, selection.baseOffset);
  }

  HttpScriptSlot? get _scriptSlot {
    final selection = _text.selection;
    if (!selection.isValid || !selection.isCollapsed) return null;
    return HttpScriptCompletion.slotAt(_text.text, selection.baseOffset);
  }

  Object? get _responseBodyForCompletion {
    final document = _doc;
    final index = document.requestIndexAtLine(_cursorLine);
    final result = index >= 0 && index < _view.outcomes.length
        ? _view.outcomes[index].result
        : null;
    if (result == null) {
      return index >= 0
          ? _responseBodiesForCompletion[_responseCompletionKey(
              index,
              document.requests[index],
            )]
          : null;
    }
    final body = _decodeCompletionBody(result);
    _responseBodiesForCompletion[_responseCompletionKey(
          index,
          document.requests[index],
        )] =
        body;
    return body;
  }

  String _responseCompletionKey(int index, HttpRequestSpec request) =>
      '$index|${request.method}|${request.url}';

  Object? _decodeCompletionBody(HttpResponseResult result) {
    if (identical(result, _completionBodyResult)) return _completionBodyJson;
    _completionBodyResult = result;
    try {
      _completionBodyJson = jsonDecode(result.bodyText);
    } on FormatException {
      _completionBodyJson = result.bodyText;
    }
    return _completionBodyJson;
  }

  List<HttpScriptSuggestion> get _scriptOptions {
    final slot = _scriptSlot;
    if (slot == null) return const [];
    return HttpScriptCompletion.options(
      slot,
      responseBody: slot.receiver?.startsWith('response.body') == true
          ? _responseBodyForCompletion
          : null,
    );
  }

  List<String> get _completionOptions {
    if (_scriptSlot != null) {
      return [for (final item in _scriptOptions) item.name];
    }
    final selection = _text.selection;
    if (selection.isValid &&
        HttpScriptCompletion.insideBlock(_text.text, selection.baseOffset)) {
      return const [];
    }
    final slot = _variableSlot;
    if (slot == null && _plainCompletionOffset == null) return const [];
    final requestIndex = _doc.requestIndexAtLine(_cursorLine);
    final names = <String>{
      ..._catalog.valuesFor(widget.session.httpEnvironment).keys,
      ...HttpScriptSession.shared.globals.keys,
      ..._doc.variables.keys,
      ..._view.runtimeVariablesFor(widget.session.httpEnvironment).keys,
      if (requestIndex >= 0 && requestIndex < _view.outcomes.length)
        ..._view.outcomes[requestIndex].requestVariables.keys,
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
    final scriptSlot = _scriptSlot;
    if (scriptSlot != null) {
      if (textChanged) {
        _completionVisible = scriptSlot.autoShow && _scriptOptions.isNotEmpty;
        _completionIndex = 0;
      } else if (_completionVisible) {
        final count = _scriptOptions.length;
        if (count > 0 && _completionIndex >= count) {
          _completionIndex = count - 1;
        }
      }
      return;
    }
    final selection = _text.selection;
    if (selection.isValid &&
        HttpScriptCompletion.insideBlock(_text.text, selection.baseOffset)) {
      _completionVisible = false;
      _completionIndex = 0;
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
      if (HttpScriptCompletion.insideBlock(_text.text, selection.baseOffset) &&
          _scriptSlot == null) {
        return true;
      }
      setState(() {
        _plainCompletionOffset = _scriptSlot == null && _variableSlot == null
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
        _completeCompletion(
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

  void _completeCompletion(String name) {
    final scriptSlot = _scriptSlot;
    if (scriptSlot != null) {
      final choices = _scriptOptions.where((item) => item.name == name);
      if (choices.isEmpty) return;
      _text.value = HttpScriptCompletion.complete(
        _text.value,
        scriptSlot,
        choices.first,
      );
      setState(() {
        _completionVisible = false;
        _plainCompletionOffset = null;
      });
      _focus.requestFocus();
      return;
    }
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
        globals: HttpScriptSession.shared.globals,
        overrides: _view.runtimeValuesFor(selected),
        requestVariablesByIndex: {
          for (var i = 0; i < _view.outcomes.length; i++)
            i: _view.outcomes[i].requestVariables,
        },
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
  }

  static int _lineStartOffset(String text, int line) {
    var offset = 0;
    for (var i = 0; i < line; i++) {
      final next = text.indexOf('\n', offset);
      if (next < 0) return text.length;
      offset = next + 1;
    }
    return offset;
  }

  void _toggleFold(int sourceLine) {
    _completionVisible = false;
    _plainCompletionOffset = null;
    final oldLine = _foldedStarts.isEmpty
        ? sourceLine
        : _foldProjection.visibleBySource[sourceLine] ?? 0;
    if (!_foldedStarts.remove(sourceLine)) _foldedStarts.add(sourceLine);
    _rebuildFoldedText();
    _refreshUnresolvedVariables();
    final newLine = _foldedStarts.isEmpty
        ? sourceLine
        : _foldProjection.visibleBySource[sourceLine] ?? 0;
    final target = _foldedStarts.isEmpty ? _text : _foldedText;
    target.selection = TextSelection.collapsed(
      offset: _lineStartOffset(target.text, newLine),
    );
    _foldScrollAnchor = (oldLine: oldLine, newLine: newLine, tick: ++_foldTick);
    setState(() {});
  }

  void _expandForEdit() {
    if (_foldedStarts.isEmpty) return;
    final selection = _foldedText.selection;
    final offset = selection.isValid ? selection.baseOffset : 0;
    final oldLine = '\n'
        .allMatches(_foldedText.text.substring(0, offset))
        .length;
    final sourceLine =
        _foldProjection.lineNumbers[oldLine.clamp(
          0,
          _foldProjection.lineNumbers.length - 1,
        )] -
        1;
    _completionVisible = false;
    _plainCompletionOffset = null;
    _foldedStarts.clear();
    _rebuildFoldedText();
    _refreshUnresolvedVariables();
    _text.selection = TextSelection.collapsed(
      offset: _lineStartOffset(_text.text, sourceLine),
    );
    _foldScrollAnchor = (
      oldLine: oldLine,
      newLine: sourceLine,
      tick: ++_foldTick,
    );
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
      globals: HttpScriptSession.shared.globals,
      overrides: _view.runtimeValuesFor(widget.session.httpEnvironment),
    );
  }

  String? _variableNameAt(int offset) {
    final display = _foldedStarts.isEmpty ? _text.text : _foldedText.text;
    if (offset < 0 || offset >= display.length) return null;
    final start = display.lastIndexOf('\n', offset - 1) + 1;
    final endBreak = display.indexOf('\n', offset);
    final end = endBreak < 0 ? display.length : endBreak;
    final line = display.substring(start, end);
    final trimmed = line.trimLeft();
    if (trimmed.startsWith('#') ||
        trimmed.startsWith('//') ||
        HttpScriptCompletion.insideBlock(display, offset)) {
      return null;
    }
    for (final match in HttpDocument.interpolation.allMatches(line)) {
      if (offset >= start + match.start && offset < start + match.end) {
        return match.group(1);
      }
    }
    return null;
  }

  Widget _variablePopover(String name, int displayOffset) {
    final tr = context.t.cockpit.httpView;
    final environmentName = widget.session.httpEnvironment;
    final overrides = _view.runtimeValuesFor(environmentName);
    final override = _view.runtimeVariablesFor(environmentName)[name];
    final display = _foldedStarts.isEmpty ? _text.text : _foldedText.text;
    final displayLine = '\n'
        .allMatches(display.substring(0, displayOffset))
        .length;
    final sourceLine = _foldedStarts.isEmpty
        ? displayLine
        : _foldProjection.lineNumbers[displayLine] - 1;
    final requestIndex = _doc.requestIndexAtLine(sourceLine);
    final requestVariables =
        requestIndex >= 0 && requestIndex < _view.outcomes.length
        ? _view.outcomes[requestIndex].requestVariables
        : const <String, String>{};
    final token = '{{$name}}';
    final resolved = _doc.interpolate(
      token,
      extra: {
        ..._catalog.valuesFor(environmentName),
        ...HttpScriptSession.shared.globals,
      },
      requestVariables: requestVariables,
      overrides: overrides,
    );
    final value = resolved == token ? null : resolved;
    final origin = requestVariables.containsKey(name)
        ? 'request.variables'
        : _doc.variables.containsKey(name)
        ? tr.overrideFile
        : _catalog.valuesFor(environmentName).containsKey(name)
        ? tr.overrideEnvironment
        : HttpScriptSession.shared.globals.containsKey(name)
        ? tr.overrideGlobal
        : 'undefined';
    return HttpVariableOverridePopover(
      key: ValueKey('$environmentName:$requestIndex:$name'),
      name: name,
      effectiveValue: value,
      origin: origin,
      runtimeOverride: override,
      onApply: (entry) {
        _view.setRuntimeVariable(environmentName, name, entry);
        _refreshUnresolvedVariables();
      },
      onClear: () {
        _view.clearRuntimeVariable(environmentName, name);
        _refreshUnresolvedVariables();
      },
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
    if (!widget.session.scratch) {
      context.read<HttpViewModel>().tabStateFor(
        widget.session.id,
        projectId: widget.session.projectId,
        path: widget.session.path,
      );
    }
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
      overrides: _view.runtimeValuesFor(widget.session.httpEnvironment),
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
                          controller: _foldedStarts.isEmpty
                              ? _text
                              : _foldedText,
                          compactGutter: true,
                          focusNode: _focus,
                          scrollAnchor: _foldScrollAnchor,
                          readOnly: _foldedStarts.isNotEmpty,
                          linkRangeAt: (offset) {
                            final link = _codeLinkAt(offset);
                            return link == null
                                ? null
                                : (start: link.start, end: link.end);
                          },
                          onLinkTap: _openCodeLink,
                          variableNameAt: _variableNameAt,
                          variablePopoverBuilder: _variablePopover,
                          autoCloseHttpVariables: _foldedStarts.isEmpty,
                          autoEditHttpScripts: _foldedStarts.isEmpty,
                          completionVisible:
                              _foldedStarts.isEmpty && _completionVisible,
                          completionItems: _completionOptions,
                          completionIndex: _completionIndex,
                          completionEmptyLabel: _scriptSlot == null
                              ? context.t.cockpit.httpView.noMatchingVariables
                              : context.t.cockpit.httpView.noScriptSuggestions,
                          completionDetails: {
                            for (final item in _scriptOptions)
                              item.name: item.detail,
                          },
                          completionMethods: {
                            for (final item in _scriptOptions)
                              if (item.method) item.name,
                          },
                          onCompletionSelected: _completeCompletion,
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
          if (_foldedStarts.isNotEmpty) ...[
            AppTooltip(
              message: tr.expandToEdit,
              child: HoverTap(
                onTap: _expandForEdit,
                color: colors.panel3,
                borderRadius: const BorderRadius.all(Radius.circular(4)),
                padding: const EdgeInsets.all(5),
                child: Icon(Icons.edit, size: 14, color: colors.text2),
              ),
            ),
            const SizedBox(width: 8),
          ],
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
        if (doc.requests.isNotEmpty) _responseToolbar(context, doc),
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

  Widget _responseToolbar(BuildContext context, HttpDocument doc) {
    final colors = context.colors;
    final selected = _view.selectedRequest.clamp(0, doc.requests.length - 1);
    final outcome = _view.outcomes[selected];
    final tr = context.t.cockpit.httpView;
    return Container(
      height: 38,
      padding: const EdgeInsets.only(left: 10, right: 6),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: colors.border)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Align(
              alignment: Alignment.centerLeft,
              child: Builder(
                builder: (anchor) => HoverTap(
                  onTap: () => _pickResult(anchor, doc),
                  color: colors.panel3,
                  borderRadius: const BorderRadius.all(Radius.circular(4)),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 5,
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _requestStatusIcon(context, outcome.status),
                      const SizedBox(width: 7),
                      Flexible(
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
                      Icon(
                        Icons.keyboard_arrow_down,
                        size: 14,
                        color: colors.text3,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                _PaneToggle(
                  label: tr.response,
                  active: _view.pane == HttpResponsePane.response,
                  onTap: () =>
                      setState(() => _view.pane = HttpResponsePane.response),
                ),
                _PaneToggle(
                  label: tr.headers,
                  count: outcome.result?.headers.length ?? 0,
                  active: _view.pane == HttpResponsePane.headers,
                  onTap: () =>
                      setState(() => _view.pane = HttpResponsePane.headers),
                ),
                _PaneToggle(
                  label: tr.tests,
                  count: outcome.tests.length,
                  active: _view.pane == HttpResponsePane.tests,
                  onTap: () =>
                      setState(() => _view.pane = HttpResponsePane.tests),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _responseContent(BuildContext context) {
    final colors = context.colors;
    final typo = context.typo;
    final tr = context.t.cockpit.httpView;

    final outcome = _view.selectedOutcome;
    if (_view.pane == HttpResponsePane.tests && outcome != null) {
      final lines = _testsText(outcome, tr.noTests);
      return SingleChildScrollView(
        padding: const EdgeInsets.all(14),
        child: SelectableText(
          lines,
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

    final text = _paneText(result, outcome!);
    if (text.isEmpty) {
      return Center(
        child: Text(
          tr.emptyBody,
          style: typo.label.copyWith(fontSize: 12, color: colors.text3),
        ),
      );
    }

    final format = _effectiveFormat(result);
    final language = switch (_view.pane) {
      HttpResponsePane.response => switch (format) {
        HttpResponseFormat.json => result.prettyJson != null ? 'json' : null,
        HttpResponseFormat.html => 'xml',
        HttpResponseFormat.xml => 'xml',
        HttpResponseFormat.javascript => 'javascript',
        _ => null,
      },
      HttpResponsePane.headers => 'http',
      HttpResponsePane.tests => null,
    };
    if (_view.pane == HttpResponsePane.headers ||
        format != HttpResponseFormat.hex &&
            format != HttpResponseFormat.base64) {
      final foldSyntax = _view.pane == HttpResponsePane.headers
          ? null
          : switch (format) {
              HttpResponseFormat.json when result.prettyJson != null =>
                HttpResponseFoldSyntax.json,
              HttpResponseFormat.xml => HttpResponseFoldSyntax.xml,
              HttpResponseFormat.html => HttpResponseFoldSyntax.html,
              _ => null,
            };
      return HttpResponseCodeView(
        key: ValueKey((outcome, result, _view.pane, format)),
        text: text,
        language: language,
        foldSyntax: foldSyntax,
        foldedStarts: foldSyntax == null
            ? <int>{}
            : outcome.responseFolds.putIfAbsent(format, () => <int>{}),
      );
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
      // O viewport dá ao filho a largura da pane, mas sem isto o texto de uma
      // linha só encolhe e o `SingleChildScrollView` o centraliza — era o que
      // deixava a resposta boiando no meio. Largura cheia + alinhamento
      // explícito prendem tudo à esquerda.
      child: SizedBox(
        width: double.infinity,
        child: SelectableText(
          text,
          textAlign: TextAlign.start,
          style: typo.mono.copyWith(fontSize: 12, color: colors.text2),
        ),
      ),
    );
  }

  String _testsText(HttpRequestOutcome outcome, String emptyLabel) {
    final tests = outcome.tests
        .map(
          (test) =>
              '${test.passed ? '✓' : '✕'} ${test.name}${test.message == null ? '' : ' — ${test.message}'}',
        )
        .toList();
    final script = [
      if (outcome.scriptError != null) outcome.scriptError!,
      ...outcome.logs,
    ];
    return [
      if (tests.isEmpty) emptyLabel else ...tests,
      if (script.isNotEmpty) ...['', 'Script', ...script],
    ].join('\n');
  }

  HttpResponseFormat _effectiveFormat(HttpResponseResult result) {
    if (_view.format case final selected?) return selected;
    final type = result.contentType.toLowerCase();
    if (type.contains('html')) return HttpResponseFormat.html;
    if (type.contains('xml')) return HttpResponseFormat.xml;
    if (type.contains('javascript')) return HttpResponseFormat.javascript;
    return result.prettyJson != null
        ? HttpResponseFormat.json
        : HttpResponseFormat.raw;
  }

  String _formatBody(HttpResponseResult result) =>
      switch (_effectiveFormat(result)) {
        HttpResponseFormat.json => result.prettyJson ?? result.bodyText,
        HttpResponseFormat.html ||
        HttpResponseFormat.xml ||
        HttpResponseFormat.javascript ||
        HttpResponseFormat.raw => result.bodyText,
        HttpResponseFormat.hex =>
          result.bodyBytes
              .map((b) => b.toRadixString(16).padLeft(2, '0'))
              .join(' '),
        HttpResponseFormat.base64 => base64Encode(result.bodyBytes),
      };

  String _paneText(HttpResponseResult result, HttpRequestOutcome outcome) =>
      switch (_view.pane) {
        HttpResponsePane.headers => [
          for (final h in result.headers) '${h.name}: ${h.value}',
        ].join('\n'),
        HttpResponsePane.response => _formatBody(result),
        HttpResponsePane.tests => _testsText(
          outcome,
          context.t.cockpit.httpView.noTests,
        ),
      };

  Widget _footer(BuildContext context) {
    final colors = context.colors;
    final typo = context.typo;
    final tr = context.t.cockpit.httpView;
    final outcome = _view.selectedOutcome;
    final result = outcome?.result;
    return Container(
      height: 32,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: colors.border)),
      ),
      child: Row(
        children: [
          if (result != null && _view.pane == HttpResponsePane.response)
            Builder(
              builder: (anchor) => HoverTap(
                onTap: () => _pickResponseFormat(anchor),
                color: colors.panel3,
                borderRadius: const BorderRadius.all(Radius.circular(4)),
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      _formatLabel(_effectiveFormat(result)),
                      style: typo.label.copyWith(
                        fontSize: 10.5,
                        color: colors.text2,
                      ),
                    ),
                    const SizedBox(width: 4),
                    Icon(Icons.arrow_drop_down, size: 14, color: colors.text3),
                  ],
                ),
              ),
            ),
          const Spacer(),
          if (result != null) ...[
            Text(
              '${result.statusCode} ${result.reasonPhrase}'.trim(),
              style: typo.label.copyWith(
                fontSize: 10.5,
                color: _statusColor(context, result.statusCode),
              ),
            ),
            const SizedBox(width: 9),
            Text(
              '${(result.elapsed.inMilliseconds / 1000).toStringAsFixed(2)}s',
              style: typo.label.copyWith(fontSize: 10.5, color: colors.text3),
            ),
            const SizedBox(width: 9),
            Text(
              _humanBytes(result.sizeBytes),
              style: typo.label.copyWith(fontSize: 10.5, color: colors.text3),
            ),
            if (result.truncated)
              Tooltip(
                tooltip: (_) => Text(tr.truncatedSuffix.trim()),
                child: Icon(Icons.info_outline, size: 13, color: colors.warn),
              ),
            const SizedBox(width: 7),
          ],
          _responseAction(
            context,
            Icons.copy_outlined,
            tr.copyResponse,
            result == null
                ? null
                : () => TextClipboardService.instance.write(
                    _paneText(result, outcome!),
                    operation: 'http_request_view',
                  ),
          ),
          _responseAction(
            context,
            Icons.save_alt,
            tr.saveResponse,
            result == null ? null : _saveResponse,
          ),
          _responseAction(
            context,
            Icons.close,
            tr.clearResponse,
            outcome == null ||
                    outcome.status == HttpRequestRunStatus.idle ||
                    _view.isRunning
                ? null
                : _view.clearSelectedResponse,
          ),
        ],
      ),
    );
  }

  Widget _responseAction(
    BuildContext context,
    IconData icon,
    String label,
    VoidCallback? action,
  ) {
    final colors = context.colors;
    return Tooltip(
      tooltip: (_) => Text(label),
      child: HoverTap(
        onTap: action,
        borderRadius: const BorderRadius.all(Radius.circular(4)),
        padding: const EdgeInsets.all(4),
        child: Icon(
          icon,
          size: 15,
          color: action == null ? colors.text4 : colors.text2,
        ),
      ),
    );
  }

  String _formatLabel(HttpResponseFormat format) => switch (format) {
    HttpResponseFormat.json => 'JSON',
    HttpResponseFormat.html => 'HTML',
    HttpResponseFormat.xml => 'XML',
    HttpResponseFormat.javascript => 'JavaScript',
    HttpResponseFormat.raw => 'Raw',
    HttpResponseFormat.hex => 'Hex',
    HttpResponseFormat.base64 => 'Base64',
  };

  Future<void> _pickResponseFormat(BuildContext anchor) async {
    final picked = await showAppMenu<HttpResponseFormat>(
      anchor,
      minWidth: 155,
      items: [
        for (final format in HttpResponseFormat.values)
          AppMenuItem(
            value: format,
            label: _formatLabel(format),
            selected:
                format == _effectiveFormat(_view.selectedOutcome!.result!),
          ),
      ],
    );
    if (mounted && picked != null) setState(() => _view.format = picked);
  }

  Future<void> _saveResponse() async {
    final outcome = _view.selectedOutcome;
    final result = outcome?.result;
    if (outcome == null || result == null) return;
    final pane = _view.pane;
    final format = _effectiveFormat(result);
    final content = _paneText(result, outcome);
    final rawBody =
        pane == HttpResponsePane.response && format == HttpResponseFormat.raw;
    final contentType = result.contentType.toLowerCase();
    final extension = switch (pane) {
      HttpResponsePane.headers || HttpResponsePane.tests => 'txt',
      HttpResponsePane.response => switch (format) {
        HttpResponseFormat.json => 'json',
        HttpResponseFormat.html => 'html',
        HttpResponseFormat.xml => 'xml',
        HttpResponseFormat.javascript => 'js',
        HttpResponseFormat.raw when contentType.contains('pdf') => 'pdf',
        HttpResponseFormat.raw when contentType.contains('png') => 'png',
        HttpResponseFormat.raw when contentType.contains('jpeg') => 'jpg',
        HttpResponseFormat.raw when contentType.contains('svg') => 'svg',
        HttpResponseFormat.raw when contentType.contains('text/plain') => 'txt',
        HttpResponseFormat.raw => 'bin',
        _ => 'txt',
      },
    };
    final path = await FilePicker.platform.saveFile(
      dialogTitle: context.t.cockpit.httpView.saveResponse,
      fileName: 'response.$extension',
      type: FileType.any,
    );
    if (path == null) return;
    try {
      if (rawBody) {
        await File(path).writeAsBytes(result.bodyBytes);
      } else {
        await File(path).writeAsString(content);
      }
    } catch (_) {
      if (!mounted) return;
      showToast(
        context: context,
        location: ToastLocation.bottomRight,
        builder: (context, _) => SurfaceCard(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Text(context.t.cockpit.httpView.couldNotSave),
          ),
        ),
      );
    }
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

/// Aba compacta da barra de resultados.
class _PaneToggle extends StatelessWidget {
  const _PaneToggle({
    required this.label,
    required this.active,
    required this.onTap,
    this.count,
  });

  final String label;
  final bool active;
  final VoidCallback onTap;
  final int? count;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: HoverTap(
        onTap: onTap,
        padding: const EdgeInsets.symmetric(horizontal: 9),
        child: SizedBox(
          height: 31,
          child: Column(
            children: [
              Expanded(
                child: Center(
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        label,
                        style: context.typo.label.copyWith(
                          fontSize: 11,
                          color: active ? colors.text : colors.text3,
                        ),
                      ),
                      if (count != null && count! > 0) ...[
                        const SizedBox(width: 3),
                        Text(
                          '$count',
                          style: context.typo.label.copyWith(
                            fontSize: 9,
                            color: colors.text4,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              Container(
                height: 2,
                color: active ? colors.accent : const Color(0x00000000),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
