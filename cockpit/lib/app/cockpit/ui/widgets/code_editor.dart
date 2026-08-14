import 'dart:async';
import 'dart:io' show Platform;

import 'package:cockpit/app/cockpit/domain/entities/scm_line_decorations.dart';
import 'package:cockpit/app/cockpit/ui/widgets/editor_overview_ruler.dart';
import 'package:cockpit/app/core/domain/entities/lsp_diagnostic.dart';
import 'package:cockpit/app/core/ui/clamping_scroll_behavior.dart';
import 'package:cockpit/app/core/ui/themes/themes.dart';
import 'package:cockpit/app/core/ui/widgets/app_tooltip.dart';
import 'package:cockpit/app/core/ui/widgets/code_editing_controller.dart';
import 'package:flutter/gestures.dart' show PointerHoverEvent;
import 'package:flutter/material.dart'
    show
        Icon,
        Icons,
        InputBorder,
        InputDecoration,
        Scrollbar,
        ScrollbarOrientation,
        SystemMouseCursors,
        TextField,
        TextInputType;
import 'package:flutter/services.dart' show HardwareKeyboard;
import 'package:flutter/widgets.dart';

/// Área **editável** de código com gutter de número de linha.
///
/// Layout: `Row[gutter, divisor, scroll horizontal(campo)]` com frame de 14px
/// no topo (fora dos scrolls) e folga de 14px no fim do conteúdo (dentro dos
/// scrolls, acima da scrollbar horizontal). O campo é um [EditableText] com
/// `expands: true` que **é o dono do scroll vertical** (scroll interno via
/// [_vertical]); o gutter tem scroll próprio travado ao input, espelhando
/// [_vertical] via [_syncGutter], pra alinhar 1:1. `IntrinsicWidth` + scroll
/// horizontal externo fazem a linha longa **não quebrar**.
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
    this.revealSelect = true,
    this.revealTick = 0,
    this.scmDecorations = ScmLineDecorations.empty,
    this.revealMatchStart,
    this.revealMatchTick = 0,
    this.onGoToDefinition,
  });

  final CodeEditingController controller;
  final FocusNode focusNode;

  /// Callback quando Cmd/Ctrl+clique (go-to-definition). Passa {line, character}.
  final void Function(({int line, int character}))? onGoToDefinition;

  /// Linha (base 1) a revelar (rolar + selecionar) — vem de um resultado de
  /// busca. `null` = nenhum pedido.
  final int? revealLine;

  /// Seleciona a linha revelada (busca) ou so posiciona o cursor (Git).
  final bool revealSelect;

  /// Sobe a cada novo pedido de reveal → re-dispara mesmo pra mesma linha.
  final int revealTick;

  /// Decorações SCM no gutter (linhas base 1 + fronteiras de remoção).
  final ScmLineDecorations scmDecorations;

  /// Offset (UTF-16) do início do match atual da busca **no arquivo** (Cmd+F) a
  /// revelar — rola vertical **e** horizontalmente até ele, sem tocar na seleção
  /// (o highlight é pintado pelo controller). `null` = nenhum pedido.
  final int? revealMatchStart;

  /// Sobe a cada navegação de match → re-dispara mesmo pro mesmo offset.
  final int revealMatchTick;

  @override
  State<CodeEditor> createState() => _CodeEditorState();
}

/// Mantém a física global clamp, mas não desenha barras automáticas.
///
/// Um simples `copyWith(scrollbars: false)` não basta para o [TextField]:
/// internamente, o Flutter reativa scrollbars quando o campo é multilinha.
class _CodeEditorScrollBehavior extends ClampingScrollBehavior {
  const _CodeEditorScrollBehavior();

  @override
  Widget buildScrollbar(
    BuildContext context,
    Widget child,
    ScrollableDetails details,
  ) => child;
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
    _rebuildLineStarts();
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
      final c = _lastCollapsedH.clamp(
        0.0,
        _horizontal.position.maxScrollExtent,
      );
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

  /// Rola até a linha [oneBased] (base 1). Busca a seleciona; Source Control
  /// e overview SCM apenas posicionam o cursor.
  void _reveal(int oneBased, {bool? select}) {
    final text = widget.controller.text;
    final lines = text.split('\n');
    final idx = oneBased - 1;
    if (idx < 0 || idx >= lines.length) return;
    var start = 0;
    for (var i = 0; i < idx; i++) {
      start += lines[i].length + 1; // +1 do '\n'
    }
    final end = start + lines[idx].length;
    final doSelect = select ?? widget.revealSelect;
    // Extent no INÍCIO da linha (base no fim): a seleção cobre a linha inteira
    // igual, mas o `bringIntoView` do campo segue o extent → rola a horizontal
    // pra esquerda (início), em vez de empurrar pro fim da linha.
    widget.controller.selection = doSelect
        ? TextSelection(baseOffset: end, extentOffset: start)
        : TextSelection.collapsed(offset: start);
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
        text: TextSpan(
          text: text.substring(lineStart, offset),
          style: codeStyle,
        ),
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

  // Geometria publicada pelo ScrollPosition do TextField. A Scrollbar usa
  // estes mesmos valores para pintar sua trilha e o overview deve compartilhar
  // essa referência, em vez de inferi-la pela altura do Stack.
  double? _overviewContentExtent;
  double? _overviewViewportExtent;

  bool _updateOverviewMetrics(ScrollMetricsNotification notification) {
    if (notification.metrics.axis != Axis.vertical) return false;
    final metrics = notification.metrics;
    final contentExtent =
        metrics.maxScrollExtent -
        metrics.minScrollExtent +
        metrics.viewportDimension;
    final viewportExtent = metrics.viewportDimension;
    if (_overviewContentExtent == contentExtent &&
        _overviewViewportExtent == viewportExtent) {
      return false;
    }
    setState(() {
      _overviewContentExtent = contentExtent;
      _overviewViewportExtent = viewportExtent;
    });
    return false;
  }

  bool _isEditorVerticalScroll(ScrollNotification notification) {
    if (notification.metrics.axis != Axis.vertical || !_vertical.hasClients) {
      return false;
    }
    final notificationContext = notification.context;
    if (notificationContext == null) return false;
    return identical(
      Scrollable.maybeOf(notificationContext)?.position,
      _vertical.position,
    );
  }

  /// Frame de padding no topo, fora dos scrolls — gutter e campo começam em y=0.
  static const double _padTop = 14;

  /// Folga no fim do scroll vertical (gutter + campo) pra última linha assentar
  /// acima da scrollbar horizontal (overlay no rodapé do viewport).
  static const double _padBottom = 14;
  int? _hoverLine;
  List<String> _hoverMsgs = const <String>[];
  double _hoverDx = 0;

  // Go-to-definition: detecta modificador (Cmd/Ctrl) + hover + tap.
  bool _definitionModeActive = false;
  bool _definitionModeHovered = false;
  MouseCursor _defCursor = SystemMouseCursors.text;
  TextStyle? _codeStyle; // cache do build(), usado pro hit-test do hover
  double _gutterWidth = 0; // idem — largura medida do bloco do gutter
  double _digitsWidth = 0; // largura do maior nº de linha (dimensiona o gutter)
  List<int> _lineStarts = <int>[0]; // offset de início de cada linha

  void _onHover(PointerHoverEvent event) {
    // Atualiza estado do definition mode (Cmd/Ctrl segurado?) + range sob o
    // mouse (independente do cache por linha do tooltip de diagnostic abaixo).
    _updateDefinitionMode();
    _updateDefinitionHoverRange(event);

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

  void _updateDefinitionMode() {
    final keys = HardwareKeyboard.instance;
    final isCmd =
        (Platform.isMacOS && keys.isMetaPressed) || keys.isControlPressed;
    if (isCmd != _definitionModeActive) {
      setState(() => _definitionModeActive = isCmd);
    }
  }

  /// Converte a posição do mouse em offset de texto (via largura medida do
  /// gutter + scroll horizontal + `TextPainter.getPositionForOffset` na linha
  /// hovered) e atualiza o range sublinhado no controller — só quando o
  /// modificador está ativo. Fora dele, limpa (sem sublinhado/cursor de mão).
  void _updateDefinitionHoverRange(PointerHoverEvent event) {
    if (!_definitionModeActive) return _clearDefinitionHover();
    final codeStyle = _codeStyle;
    if (codeStyle == null) return _clearDefinitionHover();

    final scrollV = _vertical.hasClients ? _vertical.offset : 0.0;
    final contentY = event.localPosition.dy - _padTop + scrollV;
    final line = contentY ~/ _lineHeight;
    if (contentY < 0 ||
        _lineHeight <= 0 ||
        line < 0 ||
        line >= _lineStarts.length) {
      return _clearDefinitionHover();
    }

    final scrollH = _horizontal.hasClients ? _horizontal.offset : 0.0;
    final codeLocalX = event.localPosition.dx - _gutterWidth - 14 + scrollH;
    if (codeLocalX < 0) return _clearDefinitionHover();

    final text = widget.controller.text;
    final lineStart = _lineStarts[line];
    final lineEnd = line + 1 < _lineStarts.length
        ? _lineStarts[line + 1] - 1
        : text.length;
    final lineText = text.substring(
      lineStart,
      lineEnd.clamp(lineStart, text.length),
    );
    final painter = TextPainter(
      text: TextSpan(text: lineText, style: codeStyle),
      textDirection: TextDirection.ltr,
    )..layout();
    final pos = painter.getPositionForOffset(Offset(codeLocalX, 0));
    final offset = (lineStart + pos.offset).clamp(0, text.length);
    final range = widget.controller.wordRangeAt(offset);

    final hovered = range != null;
    if (hovered != _definitionModeHovered) {
      setState(() {
        _definitionModeHovered = hovered;
        _defCursor = hovered
            ? SystemMouseCursors.click
            : SystemMouseCursors.text;
      });
    }
    widget.controller.definitionHoverRange = range;
  }

  void _clearDefinitionHover() {
    if (_definitionModeHovered) {
      setState(() {
        _definitionModeHovered = false;
        _defCursor = SystemMouseCursors.text;
      });
    }
    widget.controller.definitionHoverRange = null;
  }

  void _onDefinitionTap() {
    final offset = widget.controller.selection.baseOffset;
    if (offset < 0) return;
    final pos = widget.controller.offsetToLineChar(offset);
    widget.onGoToDefinition?.call(pos);
  }

  void _clearHover() {
    _clearDefinitionHover();
    if (_hoverLine == null && _hoverMsgs.isEmpty) return;
    setState(() {
      _hoverLine = null;
      _hoverMsgs = const <String>[];
    });
  }

  void _rebuildLineStarts() {
    final t = widget.controller.text;
    final starts = <int>[0];
    for (var i = 0; i < t.length; i++) {
      if (t.codeUnitAt(i) == 0x0A) starts.add(i + 1);
    }
    _lineStarts = starts;
  }

  void _onChanged() {
    _rebuildLineStarts();
    final n = '\n'.allMatches(widget.controller.text).length + 1;
    final diag = widget.controller.diagnostics;
    // Rebuild do gutter quando o nº de linhas OU os diagnostics mudam (o campo
    // de texto repinta sozinho via buildTextSpan; o gutter depende de setState).
    if ((n != _lineCount || !identical(diag, _lastDiag)) && mounted) {
      setState(() {
        if (n != _lineCount) {
          // Não pinte um frame com a extensão do documento anterior. O novo
          // layout publicará as métricas corretas logo após esta reconstrução.
          _overviewContentExtent = null;
          _overviewViewportExtent = null;
        }
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
    widget.controller.definitionHoverRange = null;
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
    final scm = widget.scmDecorations;
    final marker = scm.addedLines.contains(oneBased)
        ? context.colors.online
        : scm.modifiedLines.contains(oneBased)
        ? context.colors.accent
        : null;
    final removalBefore = scm.removalBoundaries.contains(oneBased - 1);
    final removalAfter =
        oneBased == _lineCount && scm.removalBoundaries.contains(_lineCount);
    final hasScm = marker != null || removalBefore || removalAfter;
    final deleted = context.colors.gitDeleted;
    return Stack(
      key: hasScm ? ValueKey('git-change-line:$oneBased') : null,
      children: [
        if (marker != null)
          Positioned(
            top: 0,
            bottom: 0,
            left: 0,
            child: IgnorePointer(child: Container(width: 2, color: marker)),
          ),
        if (removalBefore)
          Positioned(
            top: 0,
            left: 0,
            child: IgnorePointer(
              child: Container(
                key: ValueKey('git-removal-boundary:${oneBased - 1}'),
                width: 6,
                height: 2,
                color: deleted,
              ),
            ),
          ),
        if (removalAfter)
          Positioned(
            bottom: 0,
            left: 0,
            child: IgnorePointer(
              child: Container(
                key: ValueKey('git-removal-boundary:$_lineCount'),
                width: 6,
                height: 2,
                color: deleted,
              ),
            ),
          ),
        Row(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            slot,
            Text('$oneBased', style: numStyle),
          ],
        ),
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
    _codeStyle = codeStyle;
    _lineCount = '\n'.allMatches(widget.controller.text).length + 1;

    // Altura de uma linha (px) pra mapear posição do mouse → índice de linha.
    final lineProbe = TextPainter(
      text: TextSpan(text: 'X', style: codeStyle),
      textDirection: TextDirection.ltr,
    )..layout();
    _lineHeight = lineProbe.preferredLineHeight;

    // Largura do bloco do gutter (pad esquerdo + slot do ícone + dígitos do
    // maior nº de linha + pad direito + divisor) — usada pra converter posição
    // X do mouse em offset de texto (hover do go-to-definition).
    final digitsProbe = TextPainter(
      text: TextSpan(text: '$_lineCount', style: codeStyle),
      textDirection: TextDirection.ltr,
    )..layout();
    _digitsWidth = digitsProbe.width;
    _gutterWidth = 14 + _iconSlot + _digitsWidth + 14 + 1;

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
          cursor: _defCursor,
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
    final colors = context.colors;
    final codeStyle = typo.mono.copyWith(color: syntax.base);
    final numStyle = typo.mono.copyWith(
      color: syntax.base.withValues(alpha: 0.4),
    );
    final lineCount = _lineCount;
    final scm = widget.scmDecorations;
    // `_padTop` fica FORA do Scrollbar vertical: trilha do thumb, overview e
    // viewport do TextField compartilham a mesma altura (senão os ticks
    // desalinhavam do scroll por 14px no topo).
    return Scrollbar(
      controller: _horizontal,
      thumbVisibility: true,
      scrollbarOrientation: ScrollbarOrientation.bottom,
      notificationPredicate: (n) => n.metrics.axis == Axis.horizontal,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: _padTop),
          Expanded(
            child: Scrollbar(
              controller: _vertical,
              // Há dois scrollables verticais sob esta barra (gutter e campo).
              // Aceitar o gutter faria o thumb trocar de geometria conforme a
              // ordem das notificações, enquanto o overview segue o campo.
              notificationPredicate: _isEditorVerticalScroll,
              // O shadcn adiciona uma scrollbar vertical automática a cada
              // Scrollable desktop. Gutter e TextField precisam de scrolls
              // próprios para ficarem sincronizados, mas suas barras
              // duplicariam a barra deste painel.
              child: Stack(
                fit: StackFit.expand,
                children: [
                  Positioned.fill(
                    child: ScrollConfiguration(
                      behavior: const _CodeEditorScrollBehavior(),
                      // Folga inferior DENTRO dos scrolls (`_padBottom`) — a
                      // última linha assenta acima da scrollbar horizontal.
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Gutter — scroll próprio (travado ao input) espelhando
                          // `_vertical`.
                          //
                          // `ListView.builder` (e não `Column`): com uma Column, um
                          // arquivo de 5k linhas materializava 5000 Rows+Texts A
                          // CADA rebuild — e rebuild acontece até quando o mouse
                          // cruza uma linha (o tooltip de diagnostic faz setState).
                          // Virtualizado, só as ~40 linhas visíveis são construídas,
                          // e `severityForLine` (que varre os diagnostics) roda só
                          // pra elas.
                          //
                          // `itemExtent: _lineHeight` é o que mantém o alinhamento
                          // 1:1 com o texto — mesma métrica que o campo usa por
                          // linha — e ainda dá scroll O(1) (o `jumpTo` do
                          // `_syncGutter` não precisa medir os itens anteriores).
                          // Largura fixa porque a ListView, ao contrário da Column
                          // dentro do SingleChildScrollView, não é intrínseca:
                          // sem isso o gutter esticaria e comeria o campo.
                          Padding(
                            padding: const EdgeInsets.only(left: 14, right: 14),
                            child: SizedBox(
                              width: _iconSlot + _digitsWidth,
                              child: ListView.builder(
                                controller: _gutter,
                                physics: const NeverScrollableScrollPhysics(),
                                padding: const EdgeInsets.only(
                                  bottom: _padBottom,
                                ),
                                itemExtent: _lineHeight,
                                itemCount: lineCount,
                                itemBuilder: (context, i) =>
                                    _gutterLine(i + 1, numStyle),
                              ),
                            ),
                          ),
                          Container(
                            width: 1,
                            color: syntax.base.withValues(alpha: 0.15),
                          ),
                          Expanded(
                            child: LayoutBuilder(
                              builder: (context, constraints) {
                                // Largura mínima = viewport (menos o padding H).
                                // Sem isso, o IntrinsicWidth colapsa o campo a ~0
                                // quando o arquivo está vazio → sem área pra
                                // clicar/digitar.
                                final minWidth = (constraints.maxWidth - 30)
                                    .clamp(0.0, double.infinity);
                                return SingleChildScrollView(
                                  controller: _horizontal,
                                  scrollDirection: Axis.horizontal,
                                  padding: const EdgeInsets.only(
                                    left: 14,
                                    right: 16,
                                  ),
                                  child: ConstrainedBox(
                                    constraints: BoxConstraints(
                                      minWidth: minWidth,
                                    ),
                                    child: IntrinsicWidth(
                                      child:
                                          NotificationListener<
                                            ScrollMetricsNotification
                                          >(
                                            onNotification:
                                                _updateOverviewMetrics,
                                            child: TextField(
                                              controller: widget.controller,
                                              focusNode: widget.focusNode,
                                              scrollController: _vertical,
                                              style: codeStyle,
                                              cursorColor: syntax.base,
                                              maxLines: null,
                                              minLines: null,
                                              expands: true,
                                              keyboardType:
                                                  TextInputType.multiline,
                                              onTap: _definitionModeActive
                                                  ? _onDefinitionTap
                                                  : null,
                                              mouseCursor: _defCursor,
                                              decoration: const InputDecoration(
                                                isCollapsed: true,
                                                border: InputBorder.none,
                                                contentPadding: EdgeInsets.only(
                                                  bottom: _padBottom,
                                                ),
                                              ),
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
                  // Overview na mesma caixa da Scrollbar vertical (top/bottom
                  // 0), usando as métricas efetivas do mesmo TextField.
                  if (!scm.isEmpty &&
                      _overviewContentExtent != null &&
                      _overviewViewportExtent != null)
                    Positioned(
                      key: const ValueKey('git-scm-overview'),
                      top: 0,
                      right: 0,
                      bottom: 0,
                      width: kOverviewGitColumnWidth,
                      child: EditorOverviewRuler(
                        lineCount: lineCount,
                        lineHeight: _lineHeight,
                        scrollContentExtent: _overviewContentExtent,
                        scrollViewportExtent: _overviewViewportExtent,
                        onJumpToLine: (line) => _reveal(line, select: false),
                        columns: [
                          OverviewRulerColumn(
                            lane: OverviewRulerLane.git,
                            width: kOverviewGitColumnWidth,
                            marks: _scmOverviewMarks(
                              scm,
                              added: colors.online,
                              modified: colors.accent,
                              deleted: colors.gitDeleted,
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Converte [ScmLineDecorations] em marcas da coluna Git do overview.
List<OverviewRulerMark> _scmOverviewMarks(
  ScmLineDecorations scm, {
  required Color added,
  required Color modified,
  required Color deleted,
}) {
  final marks = <OverviewRulerMark>[
    for (final range in overviewMergedLineRanges(scm.addedLines))
      OverviewRulerMark.range(
        startLine: range.$1,
        endLine: range.$2,
        color: added,
      ),
    for (final range in overviewMergedLineRanges(scm.modifiedLines))
      OverviewRulerMark.range(
        startLine: range.$1,
        endLine: range.$2,
        color: modified,
      ),
    for (final b in scm.removalBoundaries)
      OverviewRulerMark.boundary(boundary: b, color: deleted),
  ];
  return marks;
}
