import 'dart:io';

import 'package:cockpit/app/cockpit/domain/entities/file_view.dart';
import 'package:cockpit/app/cockpit/ui/session/file_viewer_session.dart';
import 'package:cockpit/app/cockpit/ui/widgets/agent_markdown.dart';
import 'package:cockpit/app/cockpit/ui/widgets/code_editor.dart';
import 'package:cockpit/app/core/ui/widgets/code_editing_controller.dart';
import 'package:cockpit/app/core/ui/widgets/code_highlight.dart';
import 'package:cockpit/app/cockpit/ui/widgets/media_view.dart';
import 'package:cockpit/app/core/ui/themes/themes.dart';
import 'package:cockpit/app/core/ui/widgets/hover_tap.dart';
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

  CodeEditingController? _ctrl;
  final _focus = FocusNode();

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
    final text = _editableText;
    if (text != null) {
      _baseline = text;
      _ctrl = CodeEditingController(text: text, language: _language)
        ..addListener(_onCtrlChanged);
      // Expõe o save do buffer à sessão pro "Salvar e fechar" (limpo no dispose).
      widget.session.saveDraft = _save;
    }
    // Aba já nasce focada (ex.: arquivo recém-aberto) → foca o editor.
    _focusEditorIfActive();
  }

  @override
  void didUpdateWidget(FileViewer old) {
    super.didUpdateWidget(old);
    final text = _editableText;
    // Tipo deixou de ser editável (raro) → sai do modo edição.
    if (text == null) {
      if (_editing) setState(() => _editing = false);
      return;
    }
    // Recarga externa (watcher) sobre conteúdo **não** sujo → sincroniza o campo.
    // Com edições pendentes, mantém o buffer do usuário (last-write-wins no save).
    if (!_dirty && _ctrl != null && _ctrl!.text != text) {
      _ctrl!.text = text;
      _baseline = text;
    }
    // Virou a aba focada (seleção da tab) → joga o foco no editor.
    if (widget.focused && !old.focused) _focusEditorIfActive();
  }

  /// `true` quando há editor visível (texto/código sempre; markdown/svg só em
  /// Source). Markdown/svg em preview não têm campo pra focar.
  bool get _editingNow => _editableText != null && (!_hasPreview || _editing);

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
    _ctrl?.removeListener(_onCtrlChanged);
    _ctrl?.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _onCtrlChanged() {
    _updateDirty(_ctrl != null && _ctrl!.text != _baseline);
  }

  /// Atualiza o estado sujo local **e** o da sessão (indicador da aba + dialog).
  void _updateDirty(bool value) {
    if (value != _dirty) setState(() => _dirty = value);
    widget.session.setDirty(value);
  }

  void _toggleEditing() {
    setState(() => _editing = !_editing);
    if (_editing) {
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

  /// Grava o buffer em disco. Retorna `true` no sucesso (ou se nada a salvar).
  Future<bool> _save() async {
    final ctrl = _ctrl;
    if (ctrl == null) return false;
    if (!_dirty || _saving) return true;
    final content = ctrl.text;
    setState(() => _saving = true);
    final ok = await widget.onSave(content);
    if (!mounted) return ok;
    setState(() => _saving = false);
    if (ok) {
      _baseline = content;
      _updateDirty(false);
    }
    return ok;
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
        editingNow ? _editor() : _TextView(text: text, language: language),
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
              onSave: () => _save(),
              onDiscard: _discard,
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
  const _TextView({required this.text, this.language});

  final String text;

  /// Linguagem (extensão do arquivo) pro syntax highlight; `null` = sem dica.
  final String? language;

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
