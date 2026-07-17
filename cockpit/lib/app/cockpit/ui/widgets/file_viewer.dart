import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:cockpit/app/cockpit/domain/entities/file_view.dart';
import 'package:cockpit/app/cockpit/ui/session/file_viewer_session.dart';
import 'package:cockpit/app/cockpit/ui/viewmodels/cockpit_viewmodel.dart';
import 'package:cockpit/app/cockpit/ui/widgets/agent_markdown.dart';
import 'package:cockpit/app/cockpit/ui/widgets/code_editor.dart';
import 'package:cockpit/app/cockpit/ui/widgets/file_find_bar.dart';
import 'package:cockpit/app/core/data/lsp/lsp_command.dart';
import 'package:cockpit/app/core/data/lsp/lsp_launchers.dart';
import 'package:cockpit/app/core/data/lsp/lsp_text_edit.dart';
import 'package:cockpit/app/core/domain/entities/lsp_diagnostic.dart';
import 'package:cockpit/app/core/ui/file_icons/file_icons.dart';
import 'package:cockpit/app/core/ui/menu/editor_menu_bridge.dart';
import 'package:cockpit/app/core/ui/settings_controller.dart';
import 'package:cockpit/app/core/ui/widgets/code_editing_controller.dart';
import 'package:cockpit/app/core/ui/widgets/code_highlight.dart';
import 'package:cockpit/app/cockpit/ui/widgets/media_view.dart';
import 'package:cockpit/app/core/ui/themes/themes.dart';
import 'package:cockpit/app/core/ui/widgets/hover_tap.dart';
import 'package:flutter_modular/flutter_modular.dart';
// SelectionArea (Material) envolve o scroll do markdown → seleção + auto-scroll.
import 'package:flutter/material.dart' show SelectionArea;
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';

/// Corpo do viewer de arquivo: markdown / texto / imagem / A/V.
///
/// Texto e markdown são **editáveis**: uma toolbar fina no topo alterna entre
/// visualizar (highlight read-only / markdown renderizado) e editar (código
/// editável com gutter). Salvar é `Cmd+S` (ou o botão); o ponto sujo (●) sinaliza
/// alterações não gravadas. [onSave] persiste em disco via a VM. Mídia/imagem e
/// não-suportado seguem read-only, sem toolbar.
class FileViewer extends StatefulWidget {
  const FileViewer({
    super.key,
    required this.session,
    required this.onSave,
    this.active = true,
    this.focused = true,
  });

  final FileViewerSession session;

  /// Grava o conteúdo editado em disco. Retorna `true` no sucesso.
  final Future<bool> Function(String content) onSave;

  /// `true` enquanto esta é a aba ativa (visível). Repassado ao player A/V, que
  /// pausa ao virar `false` (plano 46). Tipos não-mídia ignoram.
  final bool active;

  /// `true` quando esta aba está ativa **e** a pane focada — aí o editor recebe
  /// o foco do teclado automaticamente (digitar direto ao selecionar a aba).
  final bool focused;

  @override
  State<FileViewer> createState() => _FileViewerState();
}

class _FileViewerState extends State<FileViewer> {
  /// Modo de edição ligado (texto) / fonte exibida (markdown). Desligado = ver.
  bool _editing = false;
  bool _dirty = false;
  bool _saving = false;
  String _baseline = '';
  String? _lastObservedPath;

  /// Último [FileViewerSession.revealTick] visto — detecta novos pedidos de
  /// "revelar linha" (resultado de busca) vindos da VM.
  int _lastRevealTick = 0;

  CodeEditingController? _ctrl;
  final _focus = FocusNode();

  /// Busca **no arquivo** (Cmd+F). Estado local: barra aberta, query, opções e
  /// matches casados sobre o buffer atual. O highlight é pintado pelo controller
  /// (`setSearchMatches`); a navegação rola o editor via `_findRevealTick`.
  bool _findOpen = false;
  final _findCtrl = TextEditingController();
  final _findFocus = FocusNode();
  bool _findCase = false;
  bool _findWord = false;
  bool _findRegex = false;
  bool _findInvalid = false;
  List<MatchSpan> _findMatches = const <MatchSpan>[];
  int _findIndex = -1;
  int _findRevealTick = 0;

  /// `true` enquanto aplicamos matches no controller. `setSearchMatches` dispara
  /// `notifyListeners` → `_onCtrlChanged` (listener do controller); sem este
  /// guard, isso reentraria em `_recomputeFind` e recursaria infinitamente (o
  /// texto não mudou, só o realce).
  bool _settingMatches = false;

  /// LSP: VM (captado uma vez), assinatura de diagnostics e debounce do
  /// didChange. `_diagnostics` espelha o último batch deste documento — vale pro
  /// editor (via `_ctrl`) **e** pro viewer read-only.
  CockpitViewModel? _vm;
  StreamSubscription<LspDiagnosticsBatch>? _diagSub;
  Timer? _lspDebounce;
  List<LspDiagnostic> _diagnostics = const <LspDiagnostic>[];

  /// `true` quando o documento foi de fato aberto no LSP. Arquivos **fora do
  /// workspace** (abertos por drag&drop do SO) ficam sem language server →
  /// pulamos didOpen/didChange/didClose pra não spawnar servidor no lugar errado.
  bool _lspOn = false;

  /// Texto editável da view atual, ou `null` se o tipo não é editável.
  String? get _editableText => switch (widget.session.view) {
    FileViewText(:final text) => text,
    FileViewMarkdown(:final text) => text,
    FileViewSvg(:final text) => text,
    _ => null,
  };

  /// Linguagem pro highlight: nome de arquivo especial (`.env*`), extensão
  /// (texto), `markdown` ou `xml` (svg).
  String? get _language =>
      filenameLanguageOf(widget.session.path) ??
      switch (widget.session.view) {
        FileViewText(:final language) => language,
        FileViewMarkdown() => 'markdown',
        FileViewSvg() => 'xml',
        _ => null,
      };

  /// Tem modo renderizado além da fonte (markdown/svg) → mostra o switch
  /// Preview/Source. Demais textos/códigos entram direto em edição (sem toggle).
  bool get _hasPreview =>
      widget.session.view is FileViewMarkdown ||
      widget.session.view is FileViewSvg;

  @override
  void initState() {
    super.initState();
    _lastObservedPath = widget.session.path;
    _lastRevealTick = widget.session.revealTick;
    widget.session.addListener(_onSession);
    // Reveal pendente num arquivo markdown/svg → abre direto na fonte (o editor
    // é quem sabe rolar + selecionar a linha; o preview renderizado não).
    if (widget.session.revealLine != null && _hasPreview) _editing = true;
    final text = _editableText;
    if (text != null) {
      _baseline = text;
      _ctrl = CodeEditingController(text: text, language: _language)
        ..addListener(_onCtrlChanged);
      // Expõe o save do buffer à sessão pro "Salvar e fechar" (limpo no dispose).
      widget.session.saveDraft = _save;
      _startLsp(text);
    }
    // Aba já nasce focada (ex.: arquivo recém-aberto) → foca o editor.
    _focusEditorIfActive();
  }

  /// Abre o documento no LSP e passa a escutar os diagnostics deste arquivo.
  /// No-op para linguagens sem servidor (o pool degrada graciosamente).
  void _startLsp(String text) {
    final vm = context.read<CockpitViewModel>();
    _vm = vm;
    final path = widget.session.path;
    // Fora do workspace (drop externo) → sem LSP. Mantém o highlight léxico.
    if (!vm.isInsideProject(widget.session.projectId, path)) {
      _lspOn = false;
      return;
    }
    _lspOn = true;
    final uri = Uri.file(path).toString();
    unawaited(vm.lspOpenDocument(path, text, widget.session.projectId));
    _diagSub = vm.lspDiagnostics.listen((batch) {
      if (batch.uri != uri || !mounted) return;
      setState(() => _diagnostics = batch.diagnostics);
      _ctrl?.diagnostics = batch.diagnostics;
    });
  }

  @override
  void didUpdateWidget(FileViewer old) {
    super.didUpdateWidget(old);

    // Se o path mudou (preview reutilizado), força rebuild total.
    if (widget.session.path != _lastObservedPath) {
      final oldPath = _lastObservedPath;
      _lastObservedPath = widget.session.path;
      _editing = false;
      _dirty = false;
      _baseline = '';
      _ctrl?.removeListener(_onCtrlChanged);
      _ctrl?.dispose();
      _ctrl = null;

      // Busca é por-arquivo: fecha ao trocar de documento.
      _findOpen = false;
      _findMatches = const <MatchSpan>[];
      _findIndex = -1;
      _findInvalid = false;

      // Troca o documento do LSP: fecha o antigo, abre o novo.
      if (oldPath != null && _lspOn) unawaited(_vm?.lspCloseDocument(oldPath));
      _diagSub?.cancel();
      _diagSub = null;
      _diagnostics = const <LspDiagnostic>[];

      // Recria o controller com o novo conteúdo.
      final text = _editableText;
      if (text != null) {
        _baseline = text;
        _ctrl = CodeEditingController(text: text, language: _language)
          ..addListener(_onCtrlChanged);
        widget.session.saveDraft = _save;
        _startLsp(text);
      } else {
        widget.session.saveDraft = null;
      }
      // Força rebuild.
      setState(() {});
      return;
    }

    final text = _editableText;
    // Tipo deixou de ser editável (raro) → sai do modo edição.
    if (text == null) {
      if (_editing) setState(() => _editing = false);
      return;
    }
    // Recarga externa (watcher) sobre conteúdo **não** sujo → sincroniza o campo.
    // Com edições pendentes, mantém o buffer do usuário (last-write-wins no save).
    // Adia para pós-build: evitar setState durante build (setDirty -> notifyListeners).
    if (!_dirty && _ctrl != null && _ctrl!.text != text) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && !_dirty && _ctrl != null && _ctrl!.text != text) {
          _ctrl!.text = text;
          _baseline = text;
          // O disco mudou (agente editou) → mantém o LSP em sync.
          if (_lspOn) {
            unawaited(_vm?.lspChangeDocument(widget.session.path, text));
          }
        }
      });
    }
    // Virou a aba focada (seleção da tab) → joga o foco no editor.
    if (widget.focused && !old.focused) _focusEditorIfActive();
  }

  /// `true` quando há editor visível (texto/código sempre; markdown/svg só em
  /// Source). Markdown/svg em preview não têm campo pra focar.
  bool get _editingNow => _editableText != null && (!_hasPreview || _editing);

  /// Devolve o foco ao editor após uma ação da toolbar (Format/Save/Discard),
  /// pra continuar digitando sem reclicar no campo. Post-frame porque a ação
  /// pode disparar rebuild (ex.: saving) que rouba o foco recém-pedido.
  void _refocusEditor() {
    if (!mounted || _ctrl == null || !_editingNow) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _focus.requestFocus();
    });
  }

  /// Foca o campo do editor se esta aba está focada e em modo edição.
  void _focusEditorIfActive() {
    if (!widget.focused || !_editingNow || _ctrl == null) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && widget.focused) _focus.requestFocus();
    });
  }

  /// Reage a mudanças da sessão: novo pedido de reveal (linha de busca) →
  /// rebuild pra repassar o tick ao [CodeEditor] (e abrir a fonte se markdown).
  void _onSession() {
    if (widget.session.revealTick == _lastRevealTick) return;
    _lastRevealTick = widget.session.revealTick;
    if (!mounted) return;
    setState(() {
      if (_hasPreview) _editing = true;
    });
  }

  /// Bridge app-scoped do menu File (Save/Discard/Format). Capturado em
  /// [didChangeDependencies] pra ficar acessível no [dispose] (onde `context`
  /// já não pode ser lido).
  EditorMenuBridge? _menuBridge;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _menuBridge = context.read<EditorMenuBridge>();
  }

  /// Publica (ou limpa) o estado do menu File conforme esta aba. Só publica se
  /// for a aba **focada** e em edição; senão libera o menu (item cinza). As
  /// capacidades espelham exatamente os botões da toolbar (Save/Discard exigem
  /// `dirty && !saving`; Format exige só `!saving`). `owner: this` garante que a
  /// aba antiga não apague o estado da nova ao perder o foco.
  void _syncMenuBridge() {
    final bridge = _menuBridge;
    if (bridge == null) return;
    if (widget.focused && _editingNow) {
      final canWrite = _dirty && !_saving;
      bridge.publish(
        owner: this,
        canSave: canWrite,
        canDiscard: canWrite,
        canFormat: !_saving,
        onSave: () => _save().whenComplete(_refocusEditor),
        onDiscard: () {
          _discard();
          _refocusEditor();
        },
        onFormat: () => _format().whenComplete(_refocusEditor),
      );
    } else {
      bridge.clear(this);
    }
  }

  @override
  void dispose() {
    _menuBridge?.clear(this);
    widget.session.removeListener(_onSession);
    if (widget.session.saveDraft == _save) widget.session.saveDraft = null;
    _lspDebounce?.cancel();
    _diagSub?.cancel();
    if (_vm != null && _lspOn) {
      unawaited(_vm!.lspCloseDocument(widget.session.path));
    }
    _ctrl?.removeListener(_onCtrlChanged);
    _ctrl?.dispose();
    _focus.dispose();
    _findCtrl.dispose();
    _findFocus.dispose();
    super.dispose();
  }

  void _onCtrlChanged() {
    // Nosso próprio setSearchMatches (só repinta, não muda texto) → ignora pra
    // não recursar e pra não churnar o LSP à toa.
    if (_settingMatches) return;
    _updateDirty(_ctrl != null && _ctrl!.text != _baseline);
    // Buffer mudou com a busca aberta → os offsets deslocaram; recasa.
    if (_findOpen && _findCtrl.text.isNotEmpty) _recomputeFind(reveal: false);
    // Edição do usuário → notifica o LSP (debounced p/ juntar rajada de teclas).
    final ctrl = _ctrl;
    if (ctrl == null) return;
    if (!_lspOn) return;
    _lspDebounce?.cancel();
    _lspDebounce = Timer(const Duration(milliseconds: 400), () {
      _vm?.lspChangeDocument(widget.session.path, ctrl.text);
    });
  }

  /// Atualiza o estado sujo local **e** o da sessão (indicador da aba + dialog).
  void _updateDirty(bool value) {
    if (value != _dirty) setState(() => _dirty = value);
    widget.session.setDirty(value);
  }

  void _toggleEditing() {
    setState(() => _editing = !_editing);
    // Ao iniciar a edição, transforma preview em aba normal.
    if (_editing) {
      widget.session.pin();
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _focus.requestFocus();
      });
    }
  }

  /// Duplica as linhas tocadas pela seleção (linha inteira, à la VSCode
  /// "Copy Line Down/Up"). Sem seleção → duplica a linha do cursor. A cópia
  /// entra abaixo ([down] = true) ou acima; o cursor/seleção acompanha a cópia.
  void _cloneLines({required bool down}) {
    final ctrl = _ctrl;
    if (ctrl == null) return;
    final text = ctrl.text;
    final sel = ctrl.selection;
    if (!sel.isValid) return;

    // Expande pra abranger linhas inteiras: início da linha do menor offset até
    // o fim da linha do maior offset.
    final selStart = sel.start;
    final selEnd = sel.end;
    final lineStart = text.lastIndexOf('\n', selStart - 1) + 1;
    var lineEnd = text.indexOf('\n', selEnd);
    if (lineEnd == -1) lineEnd = text.length;
    final block = text.substring(lineStart, lineEnd);

    final String newText;
    final int delta;
    if (down) {
      // Insere \n + bloco logo após a linha final; empurra o cursor pra cópia.
      newText =
          '${text.substring(0, lineEnd)}\n$block${text.substring(lineEnd)}';
      delta = block.length + 1;
    } else {
      // Insere bloco + \n antes da linha inicial; cursor fica na cópia de cima
      // (offsets originais já apontam pra ela).
      newText =
          '${text.substring(0, lineStart)}$block\n${text.substring(lineStart)}';
      delta = 0;
    }

    ctrl.value = TextEditingValue(
      text: newText,
      selection: TextSelection(
        baseOffset: sel.baseOffset + delta,
        extentOffset: sel.extentOffset + delta,
      ),
    );
  }

  void _discard() {
    final ctrl = _ctrl;
    if (ctrl == null || !_dirty || _saving) return;
    // Volta o buffer ao último conteúdo salvo (baseline) e zera o estado sujo.
    ctrl.text = _baseline;
    _updateDirty(false);
  }

  /// Comando de formatador externo (`%FILE%`) configurado pra linguagem deste
  /// arquivo, ou `null`. Lido das Configurações (app-scoped).
  String? _externalFormatter() {
    final lang = languageForPath(widget.session.path)?.id;
    if (lang == null) return null;
    return context.read<SettingsController>().settings.lspFormatters[lang];
  }

  bool get _formatOnSave =>
      context.read<SettingsController>().settings.formatOnSave;

  /// Grava o buffer em disco. Retorna `true` no sucesso (ou se nada a salvar).
  /// Com **format-on-save** ligado: formatadores de buffer (JSON/LSP) rodam
  /// **antes** de gravar; formatador externo roda **depois** (file-based) e relê.
  Future<bool> _save() async {
    final ctrl = _ctrl;
    if (ctrl == null) return false;
    if (!_dirty || _saving) return true;

    final external = _externalFormatter();
    final formatOnSave = _formatOnSave;

    // Buffer-format antes de gravar (só quando não há formatador externo).
    if (formatOnSave && external == null) {
      final formatted = await _formatBuffer();
      if (!mounted) return false;
      if (formatted != null && formatted != ctrl.text) {
        _applyToBuffer(formatted);
      }
    }

    final content = ctrl.text;
    setState(() => _saving = true);
    final ok = await widget.onSave(content);
    if (!mounted) return ok;
    setState(() => _saving = false);
    if (ok) {
      _baseline = content;
      _updateDirty(false);
    }

    // Formatador externo: roda no arquivo já gravado e relê.
    if (ok && formatOnSave && external != null) {
      await _runExternalFormatter(external);
    }
    return ok;
  }

  /// Formata sob demanda (⇧⌘F). Externo (file-based) tem precedência; senão
  /// JSON via stdlib / LSP no buffer.
  Future<void> _format() async {
    final ctrl = _ctrl;
    if (ctrl == null || _saving) return;
    final external = _externalFormatter();
    if (external != null) {
      // File-based: grava o buffer atual, roda o formatador, relê.
      final ok = await _save();
      if (!ok || !mounted) return;
      await _runExternalFormatter(external);
      return;
    }
    final formatted = await _formatBuffer();
    if (!mounted || formatted == null || formatted == ctrl.text) return;
    _applyToBuffer(formatted);
  }

  /// Formata o conteúdo atual **no buffer** e devolve o texto (sem gravar):
  /// JSON via stdlib, demais via LSP. `null` se não há o que formatar.
  Future<String?> _formatBuffer() async {
    final ctrl = _ctrl;
    if (ctrl == null) return null;
    final path = widget.session.path;
    final ext = path.contains('.') ? path.split('.').last.toLowerCase() : '';
    if (ext == 'json') {
      try {
        return '${const JsonEncoder.withIndent('  ').convert(jsonDecode(ctrl.text))}\n';
      } catch (_) {
        return null; // JSON inválido
      }
    }
    final vm = _vm;
    if (vm == null) return null;
    final edits = await vm.lspFormat(path, ctrl.text);
    if (edits.isEmpty) return null;
    return applyTextEdits(ctrl.text, edits);
  }

  /// Roda o formatador externo no arquivo em disco e relê o buffer.
  Future<void> _runExternalFormatter(String command) async {
    final result = await runFormatterCommand(command, widget.session.path);
    if (!mounted) return;
    await result.fold((_) => _reloadFromDisk(), (_) async {});
  }

  /// Relê o conteúdo do disco para o buffer (após o formatador externo).
  Future<void> _reloadFromDisk() async {
    try {
      final fresh = await File(widget.session.path).readAsString();
      if (!mounted) return;
      final ctrl = _ctrl;
      if (ctrl == null || ctrl.text == fresh) return;
      _applyToBuffer(fresh);
      _baseline = fresh;
      _updateDirty(false);
      if (_lspOn) unawaited(_vm?.lspChangeDocument(widget.session.path, fresh));
    } catch (_) {}
  }

  /// Aplica [text] no buffer preservando o cursor (best-effort).
  void _applyToBuffer(String text) {
    final ctrl = _ctrl;
    if (ctrl == null) return;
    final caret = ctrl.selection.baseOffset;
    ctrl.value = TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(
        offset: caret < 0 ? 0 : caret.clamp(0, text.length),
      ),
    );
  }

  // ── Busca no arquivo (Cmd+F) ──────────────────────────────────────────────

  /// Abre a barra de busca. Se há texto selecionado numa única linha, usa-o como
  /// termo inicial (igual VSCode). Já aberta → só refoca e seleciona tudo.
  void _openFind() {
    final ctrl = _ctrl;
    if (ctrl == null || !_editingNow) return;
    final sel = ctrl.selection;
    // Seed do termo a partir da seleção (colapsa depois pra soltar o pin
    // horizontal do editor, que só reage a seleção de intervalo).
    if (sel.isValid && !sel.isCollapsed) {
      final picked = sel.textInside(ctrl.text);
      if (picked.isNotEmpty && !picked.contains('\n')) {
        _findCtrl.text = picked;
      }
      ctrl.selection = TextSelection.collapsed(offset: sel.baseOffset);
    }
    setState(() => _findOpen = true);
    _recomputeFind(reveal: true);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _findFocus.requestFocus();
      _findCtrl.selection = TextSelection(
        baseOffset: 0,
        extentOffset: _findCtrl.text.length,
      );
    });
  }

  /// Fecha a barra, limpa os realces e devolve o foco ao editor.
  void _closeFind() {
    if (!_findOpen) return;
    setState(() {
      _findOpen = false;
      _findMatches = const <MatchSpan>[];
      _findIndex = -1;
      _findInvalid = false;
    });
    _applyMatches(const <MatchSpan>[], -1);
    _refocusEditor();
  }

  /// Recasa a query no buffer atual e atualiza realces. Com [reveal], salta pro
  /// primeiro match a partir do cursor (abertura / mudança de query/opções).
  void _recomputeFind({required bool reveal}) {
    final ctrl = _ctrl;
    if (ctrl == null) return;
    final result = computeFileMatches(
      ctrl.text,
      _findCtrl.text,
      caseSensitive: _findCase,
      wholeWord: _findWord,
      regex: _findRegex,
    );
    final matches = result.matches;
    var index = -1;
    if (matches.isNotEmpty) {
      if (reveal) {
        // Primeiro match no cursor ou depois dele; senão, o primeiro (wrap).
        final caret = ctrl.selection.baseOffset;
        final from = caret < 0 ? 0 : caret;
        index = matches.indexWhere((m) => m.start >= from);
        if (index < 0) index = 0;
      } else {
        // Preserva o match atual se ainda couber; senão clampa.
        index = _findIndex.clamp(0, matches.length - 1);
      }
    }
    setState(() {
      _findMatches = matches;
      _findIndex = index;
      _findInvalid = result.invalidRegex;
    });
    _applyMatches(matches, index);
    if (reveal && index >= 0) _revealFindMatch();
  }

  /// Aplica os matches no controller sob o guard [_settingMatches] (ver campo).
  void _applyMatches(List<MatchSpan> matches, int index) {
    _settingMatches = true;
    _ctrl?.setSearchMatches(matches, index);
    _settingMatches = false;
  }

  void _findNext() => _stepFind(1);
  void _findPrev() => _stepFind(-1);

  void _stepFind(int delta) {
    if (_findMatches.isEmpty) return;
    final n = _findMatches.length;
    final next = (_findIndex + delta + n) % n;
    setState(() => _findIndex = next);
    _applyMatches(_findMatches, next);
    _revealFindMatch();
  }

  /// Pede ao [CodeEditor] pra rolar até o match atual (bump do tick).
  void _revealFindMatch() {
    if (!mounted) return;
    setState(() => _findRevealTick++);
  }

  void _onFindChanged(String _) => _recomputeFind(reveal: true);

  void _toggleFind(void Function() mutate) {
    setState(mutate);
    _recomputeFind(reveal: true);
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final editable = _editableText != null;
    // Texto/código sem preview edita direto; markdown/svg só editam quando o
    // switch está em "Source".
    final editingNow = editable && (!_hasPreview || _editing);

    // Reflete o estado atual no menu File (Save/Discard/Format). Post-frame
    // porque `publish/clear` pode `notifyListeners` (não pode rodar durante build).
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _syncMenuBridge();
    });

    final Widget body = switch (widget.session.view) {
      FileViewMarkdown(:final text) =>
        editingNow
            ? _editor()
            : SelectionArea(child: _Scroll(child: AgentMarkdown(text))),
      FileViewSvg(:final text) =>
        editingNow ? _editor() : _SvgPreview(source: text),
      FileViewText(:final text, :final language) =>
        editingNow
            ? _editor()
            : _TextView(
                text: text,
                language: language,
                diagnostics: _diagnostics,
              ),
      FileViewImage(:final path) => _ImageView(path: path),
      FileViewAudio(:final path) => MediaView(
        key: ValueKey('media:$path'),
        path: path,
        kind: MediaKind.audio,
        active: widget.active,
      ),
      FileViewVideo(:final path) => MediaView(
        key: ValueKey('media:$path'),
        path: path,
        kind: MediaKind.video,
        active: widget.active,
      ),
      FileViewUnsupported() => Center(
        child: Text(
          'Can\'t open this file.',
          style: context.typo.body.copyWith(color: colors.text3),
        ),
      ),
    };

    final Widget content = ColoredBox(
      color: colors.panel,
      child: Column(
        children: [
          Expanded(child: body),
          // Barra inferior: breadcrumb do caminho à esquerda + o switch
          // Preview/Source à direita (só com render). As ações Save/Discard/
          // Format vivem no menu File — não são repetidas aqui.
          _Toolbar(
            leading: _Breadcrumb(
              path: context.read<CockpitViewModel>().displayPath(
                widget.session.projectId,
                widget.session.path,
              ),
              fileName: widget.session.title,
            ),
            hasPreview: _hasPreview,
            editing: editingNow,
            previewing: _hasPreview && !_editing,
            dirty: _dirty,
            saving: _saving,
            onToggle: _toggleEditing,
          ),
        ],
      ),
    );

    // Cmd+S / Ctrl+S envolve o viewer **inteiro** (editor + footer): o markdown/
    // svg entra em Source pelo botão do footer, então o foco fica fora do campo;
    // wrapping só o editor deixaria o atalho sem alcance (era o bug do markdown).
    if (!editable) return content;
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.keyS, meta: true): () =>
            _save(),
        const SingleActivator(LogicalKeyboardKey.keyS, control: true): () =>
            _save(),
        const SingleActivator(LogicalKeyboardKey.keyF, meta: true): _openFind,
        const SingleActivator(LogicalKeyboardKey.keyF, control: true):
            _openFind,
        const SingleActivator(
          LogicalKeyboardKey.keyF,
          meta: true,
          shift: true,
        ): () =>
            _format(),
        const SingleActivator(
          LogicalKeyboardKey.keyF,
          control: true,
          shift: true,
        ): () =>
            _format(),
        // Clonar linha(s): Option+Shift+↓/↑ (macOS) = Alt+Shift+↓/↑ (Win/Linux).
        // `alt` é a mesma tecla lógica (Option) → um binding serve as 3 plataformas.
        const SingleActivator(
          LogicalKeyboardKey.arrowDown,
          alt: true,
          shift: true,
        ): () =>
            _cloneLines(down: true),
        const SingleActivator(
          LogicalKeyboardKey.arrowUp,
          alt: true,
          shift: true,
        ): () =>
            _cloneLines(down: false),
      },
      child: content,
    );
  }

  Widget _editor() {
    final ctrl = _ctrl;
    if (ctrl == null) return const SizedBox.shrink();
    return Stack(
      children: [
        Positioned.fill(
          child: CodeEditor(
            controller: ctrl,
            focusNode: _focus,
            revealLine: widget.session.revealLine,
            revealTick: widget.session.revealTick,
            revealMatchStart:
                _findIndex >= 0 && _findIndex < _findMatches.length
                ? _findMatches[_findIndex].start
                : null,
            revealMatchTick: _findRevealTick,
          ),
        ),
        if (_findOpen)
          Positioned(
            top: 8,
            right: 16,
            child: FileFindBar(
              controller: _findCtrl,
              focusNode: _findFocus,
              matchCount: _findMatches.length,
              currentIndex: _findIndex,
              caseSensitive: _findCase,
              wholeWord: _findWord,
              regex: _findRegex,
              invalidRegex: _findInvalid,
              onChanged: _onFindChanged,
              onNext: _findNext,
              onPrev: _findPrev,
              onClose: _closeFind,
              onToggleCase: () => _toggleFind(() => _findCase = !_findCase),
              onToggleWord: () => _toggleFind(() => _findWord = !_findWord),
              onToggleRegex: () => _toggleFind(() => _findRegex = !_findRegex),
            ),
          ),
      ],
    );
  }
}

/// Footer fino do viewer editável. Markdown/svg ([hasPreview]) ganham o switch
/// Preview↔Source; texto/código não têm switch e editam direto. Save/Discard
/// aparecem sempre que se está editando ([editing]); o ponto sujo sinaliza
/// alterações não gravadas.
class _Toolbar extends StatelessWidget {
  const _Toolbar({
    required this.leading,
    required this.hasPreview,
    required this.editing,
    required this.previewing,
    required this.dirty,
    required this.saving,
    required this.onToggle,
  });

  /// Conteúdo à esquerda da barra (o breadcrumb do caminho).
  final Widget leading;

  /// Tem modo renderizado (markdown/svg) → mostra o switch Preview/Source.
  final bool hasPreview;

  /// Está no editor (fonte para markdown/svg; sempre para texto/código).
  final bool editing;

  /// Está mostrando o render (só faz sentido com [hasPreview]).
  final bool previewing;
  final bool dirty;
  final bool saving;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Container(
      height: 34,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      decoration: BoxDecoration(
        color: colors.bg,
        border: Border(top: BorderSide(color: colors.border)),
      ),
      child: Row(
        children: [
          Expanded(child: leading),
          const SizedBox(width: 8),
          if (dirty && !saving)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: Container(
                width: 7,
                height: 7,
                decoration: BoxDecoration(
                  color: colors.accent,
                  shape: BoxShape.circle,
                ),
              ),
            ),
          if (hasPreview) ...[
            const SizedBox(width: 4),
            _Segmented(
              leftLabel: 'Preview',
              rightLabel: 'Source',
              leftActive: previewing,
              onTap: onToggle,
            ),
          ],
        ],
      ),
    );
  }
}

/// Switch de dois estados (ver | editar). Clicar em qualquer lado alterna.
class _Segmented extends StatelessWidget {
  const _Segmented({
    required this.leftLabel,
    required this.rightLabel,
    required this.leftActive,
    required this.onTap,
  });

  final String leftLabel;
  final String rightLabel;
  final bool leftActive;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final typo = context.typo;

    Widget seg(String label, bool active) => Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: active ? colors.panel : Colors.transparent,
        borderRadius: BorderRadius.circular(5),
      ),
      child: Text(
        label,
        style: typo.tab.copyWith(
          color: active ? colors.text : colors.text3,
          fontSize: 12,
        ),
      ),
    );

    return HoverTap(
      borderRadius: BorderRadius.circular(7),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(2),
        decoration: BoxDecoration(
          color: colors.panel2,
          borderRadius: BorderRadius.circular(7),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [seg(leftLabel, leftActive), seg(rightLabel, !leftActive)],
        ),
      ),
    );
  }
}

class _Scroll extends StatelessWidget {
  const _Scroll({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
      child: child,
    );
  }
}

/// Visualizador read-only de texto/código com **gutter de número de linha** à
/// esquerda (fixo na horizontal) e **scroll horizontal** pro conteúdo quando a
/// linha é longa. O texto segue selecionável; os números, não.
class _TextView extends StatefulWidget {
  const _TextView({
    required this.text,
    this.language,
    this.diagnostics = const <LspDiagnostic>[],
  });

  final String text;

  /// Linguagem (extensão do arquivo) pro syntax highlight; `null` = sem dica.
  final String? language;

  /// Diagnostics do LSP a sublinhar (mesmo do editor).
  final List<LspDiagnostic> diagnostics;

  @override
  State<_TextView> createState() => _TextViewState();
}

class _TextViewState extends State<_TextView> {
  final _vertical = ScrollController();
  final _horizontal = ScrollController();

  @override
  void dispose() {
    _vertical.dispose();
    _horizontal.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final typo = context.typo;
    // O viewer de código segue o tema de **syntax** (fundo próprio), não o tema
    // do app — assim One Dark/Dracula ficam escuros mesmo no app em light. O
    // tamanho vem do `typo.mono` (configurável em Configurações → Código).
    final syntax = context.syntax;
    final codeStyle = typo.mono.copyWith(color: syntax.base);
    // Spans coloridos (highlight.js → tema). `null` quando não vale destacar
    // (sem linguagem / arquivo grande) → renderiza texto puro.
    final codeSpan = buildCodeSpan(
      context,
      source: widget.text,
      language: widget.language,
      baseStyle: codeStyle,
      diagnostics: diagnosticRangesFor(widget.text, widget.diagnostics),
    );
    final numStyle = typo.mono.copyWith(
      color: syntax.base.withValues(alpha: 0.4),
    );

    // Conta linhas pelos '\n' (arquivo sem newline final = última linha conta;
    // arquivo vazio = 1 linha). Mesma métrica do código → gutter alinha 1:1.
    final lineCount = '\n'.allMatches(widget.text).length + 1;

    // Dois scrollbars aninhados: a barra **horizontal** envolve tudo, então fica
    // **pinada no rodapé do viewport** (não some ao fim do conteúdo). O scroll
    // horizontal é aninhado dentro do vertical (`depth == 1`), por isso o
    // `notificationPredicate` filtra por profundidade. A vertical fica na borda.
    return ColoredBox(
      color: syntax.background,
      child: Scrollbar(
        controller: _horizontal,
        thumbVisibility: true,
        scrollbarOrientation: ScrollbarOrientation.bottom,
        notificationPredicate: (notification) => notification.depth == 1,
        child: Scrollbar(
          controller: _vertical,
          child: SingleChildScrollView(
            controller: _vertical,
            padding: const EdgeInsets.symmetric(vertical: 14),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Gutter — números à direita, fixo (não rola na horizontal).
                Padding(
                  padding: const EdgeInsets.only(left: 14, right: 14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      for (var i = 1; i <= lineCount; i++)
                        Text('$i', style: numStyle),
                    ],
                  ),
                ),
                Container(width: 1, color: syntax.base.withValues(alpha: 0.15)),
                // Código — rola na horizontal quando a linha estoura; selecionável.
                Expanded(
                  child: SingleChildScrollView(
                    controller: _horizontal,
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.only(left: 14, right: 16),
                    child: codeSpan == null
                        ? SelectableText(widget.text, style: codeStyle)
                        : SelectableText.rich(codeSpan),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Render do SVG a partir da **fonte** (texto), não do caminho — assim o preview
/// reflete o conteúdo salvo e atualiza após cada save (sem cache de arquivo).
class _SvgPreview extends StatelessWidget {
  const _SvgPreview({required this.source});
  final String source;

  @override
  Widget build(BuildContext context) {
    return InteractiveViewer(
      maxScale: 8,
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: SvgPicture.string(source, fit: BoxFit.contain),
        ),
      ),
    );
  }
}

/// Breadcrumb do caminho do arquivo, na barra inferior do viewer (estilo
/// VSCode). Mostra o caminho **relativo** ao workspace (ou **absoluto** se
/// externo); o último segmento ganha o ícone do tipo de arquivo. Rola na
/// horizontal se estourar.
class _Breadcrumb extends StatelessWidget {
  const _Breadcrumb({required this.path, required this.fileName});

  /// Caminho já resolvido (relativo ou absoluto), sem barra inicial.
  final String path;
  final String fileName;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final typo = context.typo;
    final segs = path.split('/').where((s) => s.isNotEmpty).toList();
    if (segs.isEmpty) segs.add(fileName);

    final crumbs = <Widget>[];
    for (var i = 0; i < segs.length; i++) {
      final isLast = i == segs.length - 1;
      if (i > 0) {
        crumbs.add(
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 3),
            child: Icon(Icons.chevron_right, size: 14, color: colors.text4),
          ),
        );
      }
      if (isLast) {
        crumbs
          ..add(FileTypeIcon.file(fileName, size: 13))
          ..add(const SizedBox(width: 5));
      }
      crumbs.add(
        Text(
          segs[i],
          style: typo.label.copyWith(
            fontSize: 12,
            color: isLast ? colors.text2 : colors.text4,
          ),
        ),
      );
    }

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(children: crumbs),
    );
  }
}

class _ImageView extends StatelessWidget {
  const _ImageView({required this.path});
  final String path;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final file = File(path);
    final isSvg = path.toLowerCase().endsWith('.svg');
    return InteractiveViewer(
      maxScale: 8,
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: isSvg
              ? SvgPicture.file(file, fit: BoxFit.contain)
              : Image.file(
                  file,
                  fit: BoxFit.contain,
                  errorBuilder: (context, error, stack) => Text(
                    'Could not load the image.',
                    style: context.typo.body.copyWith(color: colors.text3),
                  ),
                ),
        ),
      ),
    );
  }
}
