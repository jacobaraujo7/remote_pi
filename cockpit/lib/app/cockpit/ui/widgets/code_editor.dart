import 'package:cockpit/app/core/domain/entities/lsp_diagnostic.dart';
import 'package:cockpit/app/core/ui/themes/themes.dart';
import 'package:cockpit/app/core/ui/widgets/code_editing_controller.dart';
import 'package:flutter/material.dart'
    show
        Icon,
        Icons,
        Scrollbar,
        ScrollbarOrientation,
        TextField,
        InputDecoration,
        InputBorder,
        TextInputType,
        Tooltip;
import 'package:flutter/gestures.dart' show PointerHoverEvent;
import 'package:flutter/widgets.dart';

/// Área **editável** de código com gutter de número de linha — a contraparte
/// edit do `_TextView` (read-only) do file_viewer. Mesmo layout: um scroll
/// vertical externo embrulha `Row[gutter fixo, divisor, scroll horizontal(campo)]`.
/// O campo é um [EditableText] com `maxLines: null` (cresce até a altura total,
/// sem scroll interno) dentro de `IntrinsicWidth` + scroll horizontal, então a
/// linha longa **não quebra** e o gutter alinha 1:1 — igual ao viewer.
///
/// Não cuida de dirty/save: só edição + pintura. O dono ([FileViewer]) escuta o
/// [controller] para o estado sujo e dispara o save.
class CodeEditor extends StatefulWidget {
  const CodeEditor({
    super.key,
    required this.controller,
    required this.focusNode,
  });

  final CodeEditingController controller;
  final FocusNode focusNode;

  @override
  State<CodeEditor> createState() => _CodeEditorState();
}

class _CodeEditorState extends State<CodeEditor> {
  final _vertical = ScrollController();
  final _horizontal = ScrollController();

  @override
  void initState() {
    super.initState();
    // Recontar linhas (gutter) a cada digitação que muda o nº de '\n'.
    widget.controller.addListener(_onChanged);
  }

  int _lineCount = 1;
  List<LspDiagnostic> _lastDiag = const <LspDiagnostic>[];

  // Hover de diagnostic ao nível de **linha** (não de coluna): mostra a(s)
  // mensagem(ns) da linha sob o mouse. Suficiente pro "suporte secundário".
  double _lineHeight = 18; // px por linha; recalculado no build via TextPainter
  static const double _padTop = 14; // padding vertical do SingleChildScrollView
  int? _hoverLine;
  List<String> _hoverMsgs = const <String>[];
  double _hoverDx = 0;

  void _onHover(PointerHoverEvent event) {
    final scroll = _vertical.hasClients ? _vertical.offset : 0.0;
    final contentY = event.localPosition.dy - _padTop + scroll;
    if (contentY < 0 || _lineHeight <= 0) return _clearHover();
    final line = (contentY ~/ _lineHeight); // base 0
    if (line == _hoverLine) return; // mesma linha → nada a fazer
    final msgs = widget.controller.messagesForLine(line);
    setState(() {
      _hoverLine = line;
      _hoverMsgs = msgs;
      _hoverDx = event.localPosition.dx;
    });
  }

  void _clearHover() {
    if (_hoverLine == null && _hoverMsgs.isEmpty) return;
    setState(() {
      _hoverLine = null;
      _hoverMsgs = const <String>[];
    });
  }

  void _onChanged() {
    final n = '\n'.allMatches(widget.controller.text).length + 1;
    final diag = widget.controller.diagnostics;
    // Rebuild do gutter quando o nº de linhas OU os diagnostics mudam (o campo
    // de texto repinta sozinho via buildTextSpan; o gutter depende de setState).
    if ((n != _lineCount || !identical(diag, _lastDiag)) && mounted) {
      setState(() {
        _lineCount = n;
        _lastDiag = diag;
      });
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onChanged);
    _vertical.dispose();
    _horizontal.dispose();
    super.dispose();
  }

  /// Largura fixa reservada pro slot do ícone de severity — **sempre** presente
  /// (mesmo sem diagnostic) pra que a coluna do gutter não mude de largura e
  /// empurre o código quando um erro aparece/some.
  static const double _iconSlot = 16;

  /// Uma linha do gutter: um slot fixo (ícone de severity quando há diagnostic,
  /// senão vazio) + o número. O ícone (12px) cabe na altura da linha de texto,
  /// mantendo o alinhamento 1:1 com o código.
  Widget _gutterLine(int oneBased, TextStyle numStyle) {
    final severity = widget.controller.severityForLine(oneBased - 1);
    final Widget slot;
    if (severity == null) {
      slot = const SizedBox(width: _iconSlot);
    } else {
      final messages = widget.controller.messagesForLine(oneBased - 1);
      slot = SizedBox(
        width: _iconSlot,
        child: Tooltip(
          message: messages.join('\n'),
          child: Icon(
            _severityIcon(severity),
            size: 12,
            color: SyntaxColors.diagnosticColor(severity),
          ),
        ),
      );
    }
    return Row(
      mainAxisSize: MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        slot,
        Text('$oneBased', style: numStyle),
      ],
    );
  }

  IconData _severityIcon(LspSeverity severity) => switch (severity) {
    LspSeverity.error => Icons.error,
    LspSeverity.warning => Icons.warning_amber_rounded,
    LspSeverity.info => Icons.info_outline,
    LspSeverity.hint => Icons.lightbulb_outline,
  };

  @override
  Widget build(BuildContext context) {
    final typo = context.typo;
    final syntax = context.syntax;
    final codeStyle = typo.mono.copyWith(color: syntax.base);
    _lineCount = '\n'.allMatches(widget.controller.text).length + 1;

    // Altura de uma linha (px) pra mapear posição do mouse → índice de linha.
    final lineProbe = TextPainter(
      text: TextSpan(text: 'X', style: codeStyle),
      textDirection: TextDirection.ltr,
    )..layout();
    _lineHeight = lineProbe.preferredLineHeight;

    // Clicar em qualquer ponto do editor (gutter, padding, espaço abaixo da
    // última linha) foca o campo — como num editor de verdade. Cliques sobre o
    // próprio TextField ganham a arena de gestos e posicionam o cursor; os
    // demais caem aqui. `translucent` pra não roubar o tap do campo.
    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onTap: () {
        if (!widget.focusNode.hasFocus) widget.focusNode.requestFocus();
      },
      child: ColoredBox(
        color: syntax.background,
        child: MouseRegion(
          onHover: _onHover,
          onExit: (_) => _clearHover(),
          child: LayoutBuilder(
            builder: (context, viewport) => Stack(
              children: [
                _editorScroll(),
                if (_hoverMsgs.isNotEmpty && _hoverLine != null)
                  _hoverOverlay(context, viewport.maxWidth),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// Overlay com a(s) mensagem(ns) de diagnostic da linha sob o mouse, ancorado
  /// abaixo da linha. Coordenadas relativas ao viewport (origem do Stack).
  Widget _hoverOverlay(BuildContext context, double maxWidth) {
    final colors = context.colors;
    final scroll = _vertical.hasClients ? _vertical.offset : 0.0;
    final lineTop = _padTop + (_hoverLine! * _lineHeight) - scroll;
    const tipWidth = 360.0;
    final left = _hoverDx.clamp(
      8.0,
      (maxWidth - tipWidth - 8).clamp(8.0, maxWidth),
    );
    return Positioned(
      left: left,
      top: lineTop + _lineHeight + 2,
      child: IgnorePointer(
        child: Container(
          constraints: const BoxConstraints(maxWidth: tipWidth),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
          decoration: BoxDecoration(
            color: colors.panel2,
            borderRadius: BorderRadius.circular(7),
            border: Border.all(color: colors.border),
          ),
          child: Text(
            _hoverMsgs.join('\n'),
            style: context.typo.label.copyWith(color: colors.text),
          ),
        ),
      ),
    );
  }

  Widget _editorScroll() {
    final syntax = context.syntax;
    final typo = context.typo;
    final codeStyle = typo.mono.copyWith(color: syntax.base);
    final numStyle = typo.mono.copyWith(
      color: syntax.base.withValues(alpha: 0.4),
    );
    final lineCount = _lineCount;
    return Scrollbar(
      controller: _horizontal,
      thumbVisibility: true,
      scrollbarOrientation: ScrollbarOrientation.bottom,
      notificationPredicate: (n) => n.depth == 1,
      child: Scrollbar(
        controller: _vertical,
        child: SingleChildScrollView(
          controller: _vertical,
          padding: const EdgeInsets.symmetric(vertical: 14),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.only(left: 14, right: 14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    for (var i = 1; i <= lineCount; i++)
                      _gutterLine(i, numStyle),
                  ],
                ),
              ),
              Container(width: 1, color: syntax.base.withValues(alpha: 0.15)),
              Expanded(
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    // Largura mínima = viewport (menos o padding H). Sem isso, o
                    // IntrinsicWidth colapsa o campo a ~0 quando o arquivo está
                    // vazio (recém-criado) → sem área pra clicar/digitar.
                    final minWidth = (constraints.maxWidth - 30).clamp(
                      0.0,
                      double.infinity,
                    );
                    return SingleChildScrollView(
                      controller: _horizontal,
                      scrollDirection: Axis.horizontal,
                      padding: const EdgeInsets.only(left: 14, right: 16),
                      // `TextField` (e não `EditableText` cru) pra ganhar os
                      // gestos de seleção do desktop: arrastar com o mouse,
                      // duplo-clique, Cmd+A. O highlight vem do `buildTextSpan`
                      // do controller; a decoração é zerada (sem borda/fundo).
                      child: ConstrainedBox(
                        constraints: BoxConstraints(minWidth: minWidth),
                        child: IntrinsicWidth(
                          child: TextField(
                            controller: widget.controller,
                            focusNode: widget.focusNode,
                            style: codeStyle,
                            cursorColor: syntax.base,
                            maxLines: null,
                            minLines: null,
                            // Scroll vertical é do contêiner externo; o campo
                            // cresce até a altura total (sem scroll interno) pra
                            // o gutter alinhar 1:1.
                            expands: false,
                            keyboardType: TextInputType.multiline,
                            decoration: const InputDecoration(
                              isCollapsed: true,
                              border: InputBorder.none,
                              contentPadding: EdgeInsets.zero,
                            ),
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
