import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:cockpit/app/cockpit/domain/entities/file_view.dart';
import 'package:cockpit/app/cockpit/ui/session/file_viewer_session.dart';
import 'package:cockpit/app/cockpit/ui/viewmodels/cockpit_viewmodel.dart';
import 'package:cockpit/app/cockpit/ui/widgets/agent_markdown.dart';
import 'package:cockpit/app/cockpit/ui/widgets/code_editor.dart';
import 'package:cockpit/app/core/data/lsp/lsp_command.dart';
import 'package:cockpit/app/core/data/lsp/lsp_launchers.dart';
import 'package:cockpit/app/core/data/lsp/lsp_text_edit.dart';
import 'package:cockpit/app/core/domain/entities/lsp_diagnostic.dart';
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

  CodeEditingController? _ctrl;
  final _focus = FocusNode();

  /// LSP: VM (captado uma vez), assinatura de diagnostics e debounce do
  /// didChange. `_diagnostics` espelha o último batch deste documento — vale pro
  /// editor (via `_ctrl`) **e** pro viewer read-only.
  CockpitViewModel? _vm;
  StreamSubscription<LspDiagnosticsBatch>? _diagSub;
  Timer? _lspDebounce;
  List<LspDiagnostic> _diagnostics = const <LspDiagnostic>[];

  /// Texto editável da view atual, ou `null` se o tipo não é editável.
  String? get _editableText => switch (widget.session.view) {
    FileViewText(:final text) => text,
    FileViewMarkdown(:final text) => text,
    FileViewSvg(:final text) => text,
    _ => null,
  };

  /// Linguagem pro highlight: extensão (texto), `markdown` ou `xml` (svg).
  String? get _language => switch (widget.session.view) {
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

      // Troca o documento do LSP: fecha o antigo, abre o novo.
      if (oldPath != null) unawaited(_vm?.lspCloseDocument(oldPath));
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
          unawaited(_vm?.lspChangeDocument(widget.session.path, text));
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

  @override
  void dispose() {
    if (widget.session.saveDraft == _save) widget.session.saveDraft = null;
    _lspDebounce?.cancel();
    _diagSub?.cancel();
    if (_vm != null) unawaited(_vm!.lspCloseDocument(widget.session.path));
    _ctrl?.removeListener(_onCtrlChanged);
    _ctrl?.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _onCtrlChanged() {
    _updateDirty(_ctrl != null && _ctrl!.text != _baseline);
    // Edição do usuário → notifica o LSP (debounced p/ juntar rajada de teclas).
    final ctrl = _ctrl;
    if (ctrl == null) return;
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
      unawaited(_vm?.lspChangeDocument(widget.session.path, fresh));
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

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final editable = _editableText != null;
    // Texto/código sem preview edita direto; markdown/svg só editam quando o
    // switch está em "Source".
    final editingNow = editable && (!_hasPreview || _editing);

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
          if (editable)
            _Toolbar(
              hasPreview: _hasPreview,
              editing: editingNow,
              previewing: _hasPreview && !_editing,
              dirty: _dirty,
              saving: _saving,
              onToggle: _toggleEditing,
              onSave: () => _save().whenComplete(_refocusEditor),
              onDiscard: () {
                _discard();
                _refocusEditor();
              },
              onFormat: () => _format().whenComplete(_refocusEditor),
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
      },
      child: content,
    );
  }

  Widget _editor() {
    final ctrl = _ctrl;
    if (ctrl == null) return const SizedBox.shrink();
    return CodeEditor(controller: ctrl, focusNode: _focus);
  }
}

/// Footer fino do viewer editável. Markdown/svg ([hasPreview]) ganham o switch
/// Preview↔Source; texto/código não têm switch e editam direto. Save/Discard
/// aparecem sempre que se está editando ([editing]); o ponto sujo sinaliza
/// alterações não gravadas.
class _Toolbar extends StatelessWidget {
  const _Toolbar({
    required this.hasPreview,
    required this.editing,
    required this.previewing,
    required this.dirty,
    required this.saving,
    required this.onToggle,
    required this.onSave,
    required this.onDiscard,
    required this.onFormat,
  });

  /// Tem modo renderizado (markdown/svg) → mostra o switch Preview/Source.
  final bool hasPreview;

  /// Está no editor (fonte para markdown/svg; sempre para texto/código).
  final bool editing;

  /// Está mostrando o render (só faz sentido com [hasPreview]).
  final bool previewing;
  final bool dirty;
  final bool saving;
  final VoidCallback onToggle;
  final VoidCallback onSave;
  final VoidCallback onDiscard;
  final VoidCallback onFormat;

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
          const Spacer(),
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
          if (editing) ...[
            _BarButton(
              icon: Icons.auto_fix_high,
              label: 'Format',
              tooltip: 'Format (⇧⌘F)',
              enabled: !saving,
              onTap: onFormat,
            ),
            const SizedBox(width: 2),
            _BarButton(
              icon: Icons.undo,
              label: 'Discard',
              tooltip: 'Discard changes',
              enabled: dirty && !saving,
              onTap: onDiscard,
            ),
            const SizedBox(width: 2),
            _BarButton(
              icon: saving ? Icons.hourglass_empty : Icons.save_outlined,
              label: 'Save',
              tooltip: 'Save (⌘S)',
              enabled: dirty && !saving,
              onTap: onSave,
            ),
          ],
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

class _BarButton extends StatelessWidget {
  const _BarButton({
    required this.icon,
    required this.label,
    required this.tooltip,
    required this.enabled,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final String tooltip;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final color = enabled ? colors.text : colors.text4;
    return Tooltip(
      tooltip: (context) => TooltipContainer(child: Text(tooltip)),
      child: HoverTap(
        borderRadius: BorderRadius.circular(5),
        onTap: enabled ? onTap : () {},
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 14, color: color),
              const SizedBox(width: 5),
              Text(
                label,
                style: context.typo.tab.copyWith(color: color, fontSize: 12),
              ),
            ],
          ),
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
