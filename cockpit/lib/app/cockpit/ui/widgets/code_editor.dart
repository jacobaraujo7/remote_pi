import 'dart:async';

import 'package:cockpit/app/core/domain/entities/lsp_diagnostic.dart';
import 'package:cockpit/app/core/ui/themes/themes.dart';
import 'package:cockpit/app/core/ui/widgets/app_tooltip.dart';
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
        TextInputType;
import 'package:flutter/gestures.dart' show PointerHoverEvent;
import 'package:flutter/widgets.dart';

/// Área **editável** de código com gutter de número de linha.
///
/// Layout: `Row[gutter, divisor, scroll horizontal(campo)]` num frame de padding
/// vertical de 14px. O campo é um [EditableText] com `expands: true` que **é o
/// dono do scroll vertical** (scroll interno via [_vertical]); o gutter tem
/// scroll próprio travado ao input, espelhando [_vertical] via [_syncGutter],
/// pra alinhar 1:1. `IntrinsicWidth` + scroll horizontal externo fazem a linha
/// longa **não quebrar**.
///
/// Por que o campo é o dono do scroll vertical (e não um container externo):
/// durante um drag de seleção, o `EditableText` recalcula a âncora convertendo a
/// posição **global** do ponteiro em local a cada update, compensando só o scroll
/// do Scrollable **mais próximo**. Com scroll vertical externo aninhado sob o
/// scroll horizontal, o Scrollable mais próximo do campo é o horizontal → o
/// vertical fica sem compensação e a âncora escorrega junto com o auto-scroll.
/// Com o scroll vertical interno ao campo, a compensação (`renderEditable.offset`)
/// cobre o eixo vertical → âncora estável.
///
/// Não cuida de dirty/save: só edição + pintura. O dono ([FileViewer]) escuta o
/// [controller] para o estado sujo e dispara o save.
class CodeEditor extends StatefulWidget {
  const CodeEditor({
    super.key,
    required this.controller,
    required this.focusNode,
    this.revealLine,
    this.revealTick = 0,
    this.revealMatchStart,
    this.revealMatchTick = 0,
  });

  final CodeEditingController controller;
  final FocusNode focusNode;

  /// Linha (base 1) a revelar (rolar + selecionar) — vem de um resultado de
  /// busca. `null` = nenhum pedido.
  final int? revealLine;

  /// Sobe a cada novo pedido de reveal → re-dispara mesmo pra mesma linha.
  final int revealTick;

  /// Offset (UTF-16) do início do match atual da busca **no arquivo** (Cmd+F) a
  /// revelar — rola vertical **e** horizontalmente até ele, sem tocar na seleção
  /// (o highlight é pintado pelo controller). `null` = nenhum pedido.
  final int? revealMatchStart;

  /// Sobe a cada navegação de match → re-dispara mesmo pro mesmo offset.
  final int revealMatchTick;

  @override
  State<CodeEditor> createState() => _CodeEditorState();
}

class _CodeEditorState extends State<CodeEditor> {
  // `_vertical` é o scrollController do PRÓPRIO campo (scroll interno). Isso é
  // essencial pra seleção: se o campo crescesse até a altura total e o scroll
  // fosse de um container externo, o campo se moveria no espaço global durante o
  // auto-scroll e a âncora da seleção (recalculada de global→local a cada drag)
  // escorregaria junto. Com o scroll interno, o campo fica parado e só o
  // conteúdo rola → âncora estável. O gutter espelha `_vertical` via `_gutter`.
  final _vertical = ScrollController();
  final _horizontal = ScrollController();
  final _gutter = ScrollController();

  @override
  void initState() {
    super.initState();
    // Recontar linhas (gutter) a cada digitação que muda o nº de '\n'.
    widget.controller.addListener(_onChanged);
    widget.controller.addListener(_keepHorizontalOnSelection);
    _horizontal.addListener(_onHorizontalScroll);
    _vertical.addListener(_syncGutter);
    if (widget.revealLine != null) _scheduleReveal(widget.revealLine!);
  }

  /// Espelha o scroll interno do campo (`_vertical`) no gutter, que tem scroll
  /// próprio travado ao input (`NeverScrollableScrollPhysics`). `jumpTo` é
  /// síncrono dentro da notificação → sem lag visível.
  void _syncGutter() {
    if (!_gutter.hasClients) return;
    final target = _vertical.hasClients
        ? _vertical.offset.clamp(0.0, _gutter.position.maxScrollExtent)
        : 0.0;
    if ((_gutter.offset - target).abs() > 0.5) _gutter.jumpTo(target);
  }

  /// Âncora: offset horizontal do último caret **colapsado**. Enquanto há
  /// **seleção de intervalo** ([_pinned]), o `EditableText` chama `showOnScreen`
  /// pro extent e empurra o `_horizontal` pro fim da linha — nós o travamos
  /// nesta âncora. Caret colapsado (digitar/mover) segue normal.
  double _lastCollapsedH = 0;
  bool _pinned = false;
  bool _restoringH = false;

  void _keepHorizontalOnSelection() {
    if (!_horizontal.hasClients) return;
    final sel = widget.controller.selection;
    if (!sel.isValid) return;
    if (sel.isCollapsed) {
      _pinned = false;
      _lastCollapsedH = _horizontal.offset; // âncora = posição do caret
    } else {
      _pinned = true; // o `_onHorizontalScroll` desfaz o auto-scroll do extent
      _enforcePin();
    }
  }

  /// Qualquer rolagem horizontal enquanto pinado (a do `showOnScreen` da
  /// seleção, independente de quando dispara) é desfeita de volta à âncora.
  void _onHorizontalScroll() {
    if (_pinned) _enforcePin();
  }

  void _enforcePin() {
    if (_restoringH || !_horizontal.hasClients) return;
    final clamped = _lastCollapsedH.clamp(
      0.0,
      _horizontal.position.maxScrollExtent,
    );
    if ((_horizontal.offset - clamped).abs() <= 0.5) return;
    // Microtask: jumpTo fora do dispatch da notificação de scroll.
    _restoringH = true;
    scheduleMicrotask(() {
      _restoringH = false;
      if (!_pinned || !_horizontal.hasClients) return;
      final c = _lastCollapsedH.clamp(0.0, _horizontal.position.maxScrollExtent);
      if ((_horizontal.offset - c).abs() > 0.5) _horizontal.jumpTo(c);
    });
  }

  @override
  void didUpdateWidget(CodeEditor old) {
    super.didUpdateWidget(old);
    if (widget.revealLine != null && widget.revealTick != old.revealTick) {
      _scheduleReveal(widget.revealLine!);
    }
    if (widget.revealMatchStart != null &&
        widget.revealMatchTick != old.revealMatchTick) {
      final start = widget.revealMatchStart!;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _revealMatch(start);
      });
    }
  }

  /// Agenda o reveal pro pós-frame (precisa do `_lineHeight` do build e do
  /// ScrollController já anexado).
  void _scheduleReveal(int oneBased) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _reveal(oneBased);
    });
  }

  /// Rola até a linha [oneBased] (base 1) e a **seleciona** (highlight visual),
  /// jogando o foco no campo. Posições fora do texto são ignoradas.
  void _reveal(int oneBased) {
    final text = widget.controller.text;
    final lines = text.split('\n');
    final idx = oneBased - 1;
    if (idx < 0 || idx >= lines.length) return;
    var start = 0;
    for (var i = 0; i < idx; i++) {
      start += lines[i].length + 1; // +1 do '\n'
    }
    final end = start + lines[idx].length;
    // Extent no INÍCIO da linha (base no fim): a seleção cobre a linha inteira
    // igual, mas o `bringIntoView` do campo segue o extent → rola a horizontal
    // pra esquerda (início), em vez de empurrar pro fim da linha.
    widget.controller.selection = TextSelection(
      baseOffset: end,
      extentOffset: start,
    );
    widget.focusNode.requestFocus();
    // Reveal sempre mostra o início da linha → âncora horizontal em 0 (mantém
    // coerência com o `_keepHorizontalOnSelection`, que segura essa seleção).
    _lastCollapsedH = 0;
    if (_horizontal.hasClients) _horizontal.jumpTo(0);
    if (_vertical.hasClients) {
      final target = (idx * _lineHeight - 80).clamp(
        0.0,
        _vertical.position.maxScrollExtent,
      );
      _vertical.animateTo(
        target,
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOutCubic,
      );
    }
  }

  /// Rola até o match da busca no [offset] (início) — vertical **e** horizontal
  /// — sem mexer na seleção do usuário (o realce do match é pintado pelo
  /// controller via `setSearchMatches`). Neutraliza o pin horizontal pra poder
  /// rolar a linha longa até a coluna do match.
  void _revealMatch(int offset) {
    final text = widget.controller.text;
    if (offset < 0 || offset > text.length) return;
    // Linha (base 0) e início da linha que contém o offset.
    var line = 0;
    var lineStart = 0;
    for (var i = 0; i < offset; i++) {
      if (text.codeUnitAt(i) == 0x0A) {
        line++;
        lineStart = i + 1;
      }
    }
    _pinned = false; // libera o pin: queremos rolar até a coluna do match

    if (_vertical.hasClients) {
      final target = (line * _lineHeight - 80).clamp(
        0.0,
        _vertical.position.maxScrollExtent,
      );
      _vertical.animateTo(
        target,
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOutCubic,
      );
    }

    if (_horizontal.hasClients) {
      final syntax = context.syntax;
      final codeStyle = context.typo.mono.copyWith(color: syntax.base);
      // Largura do prefixo da linha até o match → coluna em px.
      final prefix = TextPainter(
        text: TextSpan(text: text.substring(lineStart, offset), style: codeStyle),
        textDirection: TextDirection.ltr,
      )..layout();
      final x = prefix.width;
      final viewport = _horizontal.position.viewportDimension;
      final cur = _horizontal.offset;
      final maxH = _horizontal.position.maxScrollExtent;
      double target = cur;
      // Fora à esquerda → alinha com folga; fora à direita → traz pra dentro.
      if (x < cur + 40) {
        target = (x - 40).clamp(0.0, maxH);
      } else if (x > cur + viewport - 80) {
        target = (x - viewport + 120).clamp(0.0, maxH);
      }
      _lastCollapsedH = target;
      if ((target - cur).abs() > 0.5) {
        _horizontal.animateTo(
          target,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOutCubic,
        );
      }
    }
  }

  int _lineCount = 1;
  List<LspDiagnostic> _lastDiag = const <LspDiagnostic>[];

  // Hover de diagnostic ao nível de **linha** (não de coluna): mostra a(s)
  // mensagem(ns) da linha sob o mouse. Suficiente pro "suporte secundário".
  double _lineHeight = 18; // px por linha; recalculado no build via TextPainter
  static const double _padTop = 14; // frame de padding vertical fora dos scrolls
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
    widget.controller.removeListener(_keepHorizontalOnSelection);
    _horizontal.removeListener(_onHorizontalScroll);
    _vertical.removeListener(_syncGutter);
    _vertical.dispose();
    _horizontal.dispose();
    _gutter.dispose();
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
        child: AppTooltip(
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
      notificationPredicate: (n) => n.metrics.axis == Axis.horizontal,
      child: Scrollbar(
        controller: _vertical,
        notificationPredicate: (n) => n.metrics.axis == Axis.vertical,
        // O padding de 14px é um frame FIXO fora dos dois scrolls (gutter e
        // campo), pra ambos começarem o conteúdo em y=0 e rolarem em lockstep
        // sem que o inset de topo desalinhe ao rolar.
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 14),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Gutter — scroll próprio (travado ao input) espelhando `_vertical`.
              Padding(
                padding: const EdgeInsets.only(left: 14, right: 14),
                child: SingleChildScrollView(
                  controller: _gutter,
                  physics: const NeverScrollableScrollPhysics(),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      for (var i = 1; i <= lineCount; i++)
                        _gutterLine(i, numStyle),
                    ],
                  ),
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
                            // O campo é o DONO do scroll vertical (scroll interno)
                            // → fica parado no espaço global e a âncora da seleção
                            // não escorrega durante o auto-scroll do drag.
                            scrollController: _vertical,
                            style: codeStyle,
                            cursorColor: syntax.base,
                            maxLines: null,
                            minLines: null,
                            // Preenche a altura do viewport e rola o conteúdo
                            // internamente; o gutter espelha via `_syncGutter`.
                            expands: true,
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
