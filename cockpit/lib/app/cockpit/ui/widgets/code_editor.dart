import 'dart:async';

import 'package:cockpit/app/core/utils/text_clipboard.dart';
import 'package:cockpit/app/cockpit/domain/entities/scm_line_decorations.dart';
import 'package:cockpit/app/cockpit/ui/widgets/editor_comment.dart';
import 'package:cockpit/app/cockpit/ui/widgets/editor_indent.dart';
import 'package:cockpit/app/cockpit/ui/widgets/editor_line_cut.dart';
import 'package:cockpit/app/cockpit/ui/widgets/editor_overview_ruler.dart';
import 'package:cockpit/app/cockpit/ui/widgets/http_variable_completion.dart';
import 'package:cockpit/app/cockpit/ui/widgets/http_script_editing.dart';
import 'package:cockpit/app/core/domain/entities/lsp_diagnostic.dart';
import 'package:cockpit/app/core/ui/clamping_scroll_behavior.dart';
import 'package:cockpit/app/core/ui/themes/themes.dart';
import 'package:cockpit/app/core/ui/widgets/app_tooltip.dart';
import 'package:cockpit/app/core/ui/widgets/code_editing_controller.dart';
import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform, listEquals;
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
import 'package:flutter/rendering.dart' show RenderEditable;
import 'package:flutter/services.dart'
    show
        Clipboard,
        HardwareKeyboard,
        KeyDownEvent,
        LogicalKeyboardKey,
        SelectionChangedCause;
import 'package:flutter/widgets.dart';

import 'editor_wrap_layout.dart';

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
/// Com [wordWrap], o scroll horizontal e o `IntrinsicWidth` saem: o campo
/// ocupa a largura da pane e quebra as linhas longas. Aí uma linha lógica deixa
/// de ser uma linha visual, e gutter, reveal, hover e overview passam a ler a
/// altura de cada linha de um [EditorWrapLayout] em vez de `idx * _lineHeight`.
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
    this.scrollAnchor,
    this.scmDecorations = ScmLineDecorations.empty,
    this.revealMatchStart,
    this.revealMatchTick = 0,
    this.onGoToDefinition,
    this.linkRangeAt,
    this.onLinkTap,
    this.filePath,
    this.wordWrap = false,
    this.lineActions = const {},
    this.lineActionTooltip,
    this.foldActions = const {},
    this.foldedLines = const {},
    this.lineNumbers,
    this.readOnly = false,
    this.onCodeTap,
    this.compactGutter = false,
    this.autoCloseHttpVariables = false,
    this.autoEditHttpScripts = false,
    this.completionVisible = false,
    this.completionItems = const [],
    this.completionDetails = const {},
    this.completionMethods = const {},
    this.completionIndex = 0,
    this.completionEmptyLabel = '',
    this.onCompletionSelected,
    this.onCompletionKey,
    this.variableNameAt,
    this.variablePopoverBuilder,
  });

  final CodeEditingController controller;
  final FocusNode focusNode;

  /// Callback quando Cmd/Ctrl+clique (go-to-definition). Passa {line, character}.
  final void Function(({int line, int character}))? onGoToDefinition;

  /// Alvos próprios do editor (por exemplo, referências de arquivos HTTP).
  final ({int start, int end})? Function(int offset)? linkRangeAt;
  final void Function(int offset)? onLinkTap;

  /// Caminho do arquivo (só a extensão é usada: fallback da largura de
  /// indentação quando o conteúdo não dá pista). `null` = 4 espaços.
  final String? filePath;

  /// Linha (base 1) a revelar (rolar + selecionar) — vem de um resultado de
  /// busca. `null` = nenhum pedido.
  final int? revealLine;

  /// Seleciona a linha revelada (busca) ou so posiciona o cursor (Git).
  final bool revealSelect;

  /// Sobe a cada novo pedido de reveal → re-dispara mesmo pra mesma linha.
  final int revealTick;

  /// Preserva a posição visual de uma linha quando o texto projetado muda
  /// (por exemplo, ao recolher uma seção HTTP). Índices base 0.
  final ({int oldLine, int newLine, int tick})? scrollAnchor;

  /// Decorações SCM no gutter (linhas base 1 + fronteiras de remoção).
  final ScmLineDecorations scmDecorations;

  /// Offset (UTF-16) do início do match atual da busca **no arquivo** (Cmd+F) a
  /// revelar — rola vertical **e** horizontalmente até ele, sem tocar na seleção
  /// (o highlight é pintado pelo controller). `null` = nenhum pedido.
  final int? revealMatchStart;

  /// Sobe a cada navegação de match → re-dispara mesmo pro mesmo offset.
  final int revealMatchTick;

  /// Quebra linhas longas na largura da pane (soft wrap), sem scroll
  /// horizontal. `false` = layout de código (uma linha visual por linha).
  final bool wordWrap;

  /// Ações no slot esquerdo do gutter, indexadas por linha base 0.
  final Map<int, VoidCallback> lineActions;
  final String? lineActionTooltip;
  final Map<int, VoidCallback> foldActions;
  final Set<int> foldedLines;
  final List<int>? lineNumbers;
  final bool readOnly;
  final VoidCallback? onCodeTap;

  /// Reserva as colunas de ação mesmo enquanto elas estão temporariamente vazias.
  final bool compactGutter;
  final bool autoCloseHttpVariables;
  final bool autoEditHttpScripts;
  final bool completionVisible;
  final List<String> completionItems;
  final Map<String, String> completionDetails;
  final Set<String> completionMethods;
  final int completionIndex;
  final String completionEmptyLabel;
  final ValueChanged<String>? onCompletionSelected;
  final bool Function(KeyEvent)? onCompletionKey;

  /// Hover interativo de placeholders no editor HTTP.
  final String? Function(int offset)? variableNameAt;
  final Widget Function(String name, int startOffset)? variablePopoverBuilder;

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
  final _completionScroll = ScrollController();

  /// Alturas por linha lógica no modo [CodeEditor.wordWrap]. Medida sob
  /// demanda ([_ensureWrap]) no layout do gutter — o primeiro a precisar dela
  /// —, quando o `EditableText` já foi montado e o estilo efetivo dele existe.
  final _wrap = EditorWrapLayout();
  double _wrapWidth = 0;
  bool _wrapDirty = true;

  /// Estilo efetivo do campo (o `TextField` mescla o tema por baixo do
  /// `style`, ex. `letterSpacing`): medir com o `codeStyle` puro quebraria em
  /// outro ponto. `null` antes de o campo existir.
  TextStyle? _fieldStyle;
  StrutStyle? _fieldStrut;
  TextScaler _fieldScaler = TextScaler.noScaling;

  /// Escala de texto do `MediaQuery`, lida no build (o [_ensureWrap] roda no
  /// layout, onde não se lê InheritedWidget).
  TextScaler _buildScaler = TextScaler.noScaling;

  /// Envolve o `TextField`: dá acesso ao `RenderEditable` (hit-test exato do
  /// go-to-definition quando a linha quebra).
  final _fieldKey = GlobalKey();

  /// Y (conteúdo) do topo da linha lógica [line] (base 0).
  double _lineTop(int line) =>
      widget.wordWrap ? _wrap.top(line) : line * _lineHeight;

  /// Altura da linha lógica [line] (base 0): N linhas visuais com quebra.
  double _lineExtent(int line) =>
      widget.wordWrap ? _wrap.height(line) : _lineHeight;

  /// Linha lógica (base 0) sob o y [contentY] do conteúdo. Abaixo do
  /// documento devolve o nº de linhas (fora), nos dois modos.
  int _lineAtY(double contentY) =>
      widget.wordWrap ? _wrap.lineAtY(contentY) : contentY ~/ _lineHeight;

  /// Mede a tabela de quebra se o texto, a largura ou o estilo mudaram desde a
  /// última medição. Lê o estilo efetivo do `EditableText` (já montado quando
  /// o gutter faz layout: o LayoutBuilder infla a subárvore inteira antes de
  /// fazer layout dos filhos).
  void _ensureWrap() {
    if (!widget.wordWrap || !_wrapDirty) return;
    _wrapDirty = false;
    EditableText? field;
    void visit(Element e) {
      if (field != null) return;
      final w = e.widget;
      if (w is EditableText) {
        field = w;
        return;
      }
      e.visitChildElements(visit);
    }

    final root = _fieldKey.currentContext;
    if (root is Element) visit(root);
    final f = field;
    if (f != null) {
      _fieldStyle = f.style;
      _fieldStrut = f.strutStyle;
      _fieldScaler = f.textScaler ?? _buildScaler;
    }
    final style = _fieldStyle ?? _codeStyle;
    if (style == null) return;
    _wrap.update(
      widget.controller.text,
      _wrapWidth,
      style,
      strut: _fieldStrut,
      textScaler: _fieldScaler,
    );
  }

  RenderEditable? _renderEditable() {
    RenderEditable? found;
    void visit(RenderObject node) {
      if (found != null) return;
      if (node is RenderEditable) {
        found = node;
        return;
      }
      node.visitChildren(visit);
    }

    final root = _fieldKey.currentContext?.findRenderObject();
    if (root != null) visit(root);
    return found;
  }

  @override
  void initState() {
    super.initState();
    _rebuildLineStarts();
    // Recontar linhas (gutter) a cada digitação que muda o nº de '\n'.
    widget.controller.addListener(_onChanged);
    widget.controller.addListener(_keepHorizontalOnSelection);
    _horizontal.addListener(_onHorizontalScroll);
    _vertical.addListener(_syncGutter);
    _vertical.addListener(_onVariableScroll);
    _horizontal.addListener(_onVariableScroll);
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
    final anchor = widget.scrollAnchor;
    final anchorChanged =
        anchor != null && anchor.tick != old.scrollAnchor?.tick;
    final oldScroll = _vertical.hasClients ? _vertical.offset : 0.0;
    final oldAnchorY = anchorChanged
        ? _lineTop(anchor.oldLine) - oldScroll
        : 0.0;
    if (widget.controller != old.controller) {
      _closeVariablePopover();
      old.controller.removeListener(_onChanged);
      old.controller.removeListener(_keepHorizontalOnSelection);
      widget.controller.addListener(_onChanged);
      widget.controller.addListener(_keepHorizontalOnSelection);
      _rebuildLineStarts();
      _lineCount = _lineStarts.length;
      _lastText = widget.controller.text;
      _lastDiag = widget.controller.diagnostics;
      _wrapDirty = true;
      _overviewContentExtent = null;
      _overviewViewportExtent = null;
    }
    if (anchorChanged) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || !_vertical.hasClients) return;
        final target = (_lineTop(anchor.newLine) - oldAnchorY).clamp(
          0.0,
          _vertical.position.maxScrollExtent,
        );
        if ((_vertical.offset - target).abs() > 0.5) _vertical.jumpTo(target);
      });
    }
    if (widget.completionVisible &&
        (!old.completionVisible ||
            widget.completionIndex != old.completionIndex ||
            !listEquals(widget.completionItems, old.completionItems))) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || !_completionScroll.hasClients) return;
        final itemHeight = widget.completionDetails.isEmpty ? 31.0 : 43.0;
        final top = widget.completionIndex * itemHeight;
        final bottom = top + itemHeight;
        final current = _completionScroll.offset;
        final viewport = _completionScroll.position.viewportDimension;
        if (top < current) {
          _completionScroll.jumpTo(top);
        } else if (bottom > current + viewport) {
          _completionScroll.jumpTo(
            (bottom - viewport).clamp(
              0.0,
              _completionScroll.position.maxScrollExtent,
            ),
          );
        }
      });
    }
    if (widget.wordWrap != old.wordWrap) _keepTopLineOnWrapToggle(old.wordWrap);
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

  /// Ligar/desligar a quebra muda a altura de tudo acima do viewport: sem
  /// ajuste, o mesmo offset cairia em outra linha. Guarda a primeira linha
  /// visível (na métrica do modo antigo) e volta a ela no pós-frame, quando o
  /// novo layout já mediu as linhas.
  void _keepTopLineOnWrapToggle(bool wasWrapped) {
    _pinned = false;
    if (!_vertical.hasClients || _lineHeight <= 0) return;
    final offset = _vertical.offset;
    final topLine = wasWrapped ? _wrap.lineAtY(offset) : offset ~/ _lineHeight;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_vertical.hasClients) return;
      _vertical.jumpTo(
        _lineTop(topLine).clamp(0.0, _vertical.position.maxScrollExtent),
      );
    });
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
      final target = (_lineTop(idx) - 80).clamp(
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
      _ensureWrap();
      var matchY = _lineTop(line);
      final style = _fieldStyle ?? _codeStyle;
      if (widget.wordWrap && style != null && _wrapWidth > 0) {
        // Com quebra, o match pode estar numa linha visual abaixo do início
        // da linha lógica: soma o y do caret do match dentro da linha.
        final lineEnd = text.indexOf('\n', offset);
        final painter = TextPainter(
          text: TextSpan(
            text: text.substring(
              lineStart,
              lineEnd < 0 ? text.length : lineEnd,
            ),
            style: style,
          ),
          strutStyle: _fieldStrut,
          textScaler: _fieldScaler,
          textDirection: TextDirection.ltr,
        )..layout(maxWidth: _wrapWidth);
        matchY += painter
            .getOffsetForCaret(
              TextPosition(offset: offset - lineStart),
              Rect.zero,
            )
            .dy;
        painter.dispose();
      }
      final target = (matchY - 80).clamp(
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
  final OverlayPortalController _variablePortal = OverlayPortalController();
  late final Listenable _variablePosition = Listenable.merge([
    _vertical,
    _horizontal,
  ]);
  String? _hoverVariable;
  int? _hoverVariableStart;
  bool _pointerOnVariable = false;
  bool _pointerOnPopover = false;
  bool _focusInPopover = false;
  Timer? _variableHideTimer;

  // Go-to-definition: detecta modificador (Cmd/Ctrl) + hover + tap.
  bool _definitionModeActive = false;
  bool _definitionModeHovered = false;
  int? _definitionHoverOffset;
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

    if (widget.variableNameAt != null && !_pointerOnPopover) {
      final offset = _offsetAtHover(event);
      final name = offset == null ? null : widget.variableNameAt!(offset);
      _pointerOnVariable = name != null;
      if (name != null && !_focusInPopover) {
        final start = widget.controller.text.lastIndexOf('{{', offset!);
        if (start >= 0 &&
            (name != _hoverVariable || start != _hoverVariableStart)) {
          _hoverVariable = name;
          _hoverVariableStart = start;
          _variablePortal.show();
          setState(() {});
        }
      }
      _reconcileVariablePopover();
    }

    final scroll = _vertical.hasClients ? _vertical.offset : 0.0;
    final contentY = event.localPosition.dy - _padTop + scroll;
    if (contentY < 0 || _lineHeight <= 0) return _clearHover();
    final line = _lineAtY(contentY); // base 0
    final unresolved = widget.controller.unresolvedVariableMessageAt(
      _offsetAtHover(event) ?? -1,
    );
    final msgs = _hoverVariable != null
        ? const <String>[]
        : unresolved == null
        ? widget.controller.messagesForLine(line)
        : [unresolved];
    if (line == _hoverLine && listEquals(msgs, _hoverMsgs)) return;
    setState(() {
      _hoverLine = line;
      _hoverMsgs = msgs;
      _hoverDx = event.localPosition.dx;
    });
  }

  void _reconcileVariablePopover() {
    if (_hoverVariable == null) return;
    if (_pointerOnVariable || _pointerOnPopover || _focusInPopover) {
      _variableHideTimer?.cancel();
      return;
    }
    if (_variableHideTimer?.isActive == true) return;
    _variableHideTimer?.cancel();
    _variableHideTimer = Timer(const Duration(milliseconds: 260), () {
      if (!mounted ||
          _pointerOnVariable ||
          _pointerOnPopover ||
          _focusInPopover) {
        return;
      }
      _closeVariablePopover();
    });
  }

  void _closeVariablePopover() {
    _variableHideTimer?.cancel();
    if (_hoverVariable == null) return;
    _variablePortal.hide();
    _hoverVariable = null;
    _hoverVariableStart = null;
    _pointerOnVariable = false;
    _pointerOnPopover = false;
    _focusInPopover = false;
    if (mounted) setState(() {});
  }

  void _onPopoverFocusChange(bool focused) {
    _focusInPopover = focused;
    _reconcileVariablePopover();
  }

  void _onVariableScroll() {
    if (_hoverVariable == null || _focusInPopover || _pointerOnPopover) return;
    _pointerOnVariable = false;
    _reconcileVariablePopover();
  }

  void _updateDefinitionMode() {
    final isCmd = _definitionModifierPressed;
    if (isCmd != _definitionModeActive) {
      setState(() => _definitionModeActive = isCmd);
    }
  }

  bool get _definitionModifierPressed {
    final keys = HardwareKeyboard.instance;
    return (defaultTargetPlatform == TargetPlatform.macOS &&
            keys.isMetaPressed) ||
        keys.isControlPressed;
  }

  /// Converte a posição do mouse em offset do buffer, descontando gutter,
  /// scroll horizontal e quebra de linha. Compartilhado pelo hover de variável
  /// HTTP e pelo go-to-definition.
  int? _offsetAtHover(PointerHoverEvent event) {
    final codeStyle = _codeStyle;
    if (codeStyle == null) return null;

    final scrollV = _vertical.hasClients ? _vertical.offset : 0.0;
    final contentY = event.localPosition.dy - _padTop + scrollV;
    if (_lineHeight <= 0) return null;
    final line = _lineAtY(contentY);
    if (contentY < 0 || line < 0 || line >= _lineStarts.length) {
      return null;
    }

    final scrollH = _horizontal.hasClients ? _horizontal.offset : 0.0;
    final codeLocalX =
        event.localPosition.dx - _gutterWidth - _codeLeftPadding + scrollH;
    if (codeLocalX < 0) return null;

    final text = widget.controller.text;
    if (widget.wordWrap) {
      // Com quebra, x/y viram (linha visual, coluna) dentro de uma linha
      // lógica — o `RenderEditable` resolve o ponto global já descontando o
      // scroll interno do campo.
      final editable = _renderEditable();
      if (editable == null) return null;
      return editable
          .getPositionForPoint(event.position)
          .offset
          .clamp(0, text.length);
    }
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
    painter.dispose();
    return (lineStart + pos.offset).clamp(0, text.length);
  }

  /// Atualiza o range de go-to-definition só com Cmd/Ctrl pressionado.
  void _updateDefinitionHoverRange(PointerHoverEvent event) {
    if (!_definitionModeActive) return _clearDefinitionHover();
    final offset = _offsetAtHover(event);
    if (offset == null) return _clearDefinitionHover();
    final range = widget.linkRangeAt != null
        ? widget.linkRangeAt!(offset)
        : widget.onGoToDefinition != null
        ? widget.controller.wordRangeAt(offset)
        : null;

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
    _definitionHoverOffset = range == null ? null : offset;
  }

  void _clearDefinitionHover() {
    if (_definitionModeHovered) {
      setState(() {
        _definitionModeHovered = false;
        _defCursor = SystemMouseCursors.text;
      });
    }
    widget.controller.definitionHoverRange = null;
    _definitionHoverOffset = null;
  }

  void _onDefinitionTap() {
    if (widget.onLinkTap != null) {
      final offset = _linkOffsetAtTap();
      if (offset != null) widget.onLinkTap!(offset);
      return;
    }
    final offset = widget.controller.selection.baseOffset;
    if (offset < 0) return;
    final pos = widget.controller.offsetToLineChar(offset);
    widget.onGoToDefinition?.call(pos);
  }

  int? _linkOffsetAtTap() {
    final selection = widget.controller.selection.baseOffset;
    for (final offset in [selection, selection - 1, _definitionHoverOffset]) {
      if (offset != null &&
          offset >= 0 &&
          widget.linkRangeAt?.call(offset) != null) {
        return offset;
      }
    }
    return null;
  }

  void _clearHover() {
    _clearDefinitionHover();
    _pointerOnVariable = false;
    _reconcileVariablePopover();
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

  /// Tab/Shift+Tab indentam em vez de mover o foco (comportamento VS Code).
  /// Sobrescreve os intents de travessia de foco só dentro do campo; aplicar
  /// via `controller.value` mantém o undo do TextField funcionando.
  late final Map<Type, Action<Intent>> _indentActions = {
    NextFocusIntent: CallbackAction<NextFocusIntent>(
      onInvoke: (_) => _applyIndent(outdent: false),
    ),
    PreviousFocusIntent: CallbackAction<PreviousFocusIntent>(
      onInvoke: (_) => _applyIndent(outdent: true),
    ),
  };

  // ---- Comentários (VS Code): Cmd+/ toggle · Cmd+K Cmd+C add · Cmd+K Cmd+U
  // remove. O chord `Cmd+K` arma [_chordPending] por 2 s; a tecla seguinte
  // (com ou sem o modificador, como no VS Code) resolve. Vive num `Focus`
  // acima do TextField: a tecla sobe pela cadeia de foco depois que o campo
  // não a consome, então nada do TextField muda. Sem sintaxe conhecida pra
  // linguagem o atalho é engolido sem efeito (melhor que colar `//` em YAML).
  bool _chordPending = false;
  Timer? _chordTimer;

  void _armChord() {
    _chordTimer?.cancel();
    _chordPending = true;
    _chordTimer = Timer(const Duration(seconds: 2), _cancelChord);
  }

  void _cancelChord() {
    _chordTimer?.cancel();
    _chordTimer = null;
    _chordPending = false;
  }

  KeyEventResult _onEditorKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    if (event.logicalKey == LogicalKeyboardKey.escape &&
        _hoverVariable != null) {
      _closeVariablePopover();
      return KeyEventResult.handled;
    }
    if (widget.readOnly) return KeyEventResult.ignored;
    if (widget.onCompletionKey?.call(event) == true) {
      return KeyEventResult.handled;
    }
    final keys = HardwareKeyboard.instance;
    final cmd =
        (defaultTargetPlatform == TargetPlatform.macOS && keys.isMetaPressed) ||
        keys.isControlPressed;
    final key = event.logicalKey;
    if (_chordPending) {
      _cancelChord();
      if (key == LogicalKeyboardKey.keyC) {
        _applyComment(_CommentOp.add);
        return KeyEventResult.handled;
      }
      if (key == LogicalKeyboardKey.keyU) {
        _applyComment(_CommentOp.remove);
        return KeyEventResult.handled;
      }
      // Modificador solto entre as duas teclas não cancela o chord.
      if (key == LogicalKeyboardKey.metaLeft ||
          key == LogicalKeyboardKey.metaRight ||
          key == LogicalKeyboardKey.controlLeft ||
          key == LogicalKeyboardKey.controlRight) {
        _armChord();
        return KeyEventResult.handled;
      }
      return KeyEventResult.ignored;
    }
    if (!cmd) return KeyEventResult.ignored;
    if (key == LogicalKeyboardKey.keyK && !keys.isShiftPressed) {
      _armChord();
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.slash) {
      _applyComment(_CommentOp.toggle);
      return KeyEventResult.handled;
    }
    // Shift/Alt (AltGr no Windows é Ctrl+Alt) e composição de IME em curso
    // ficam com o campo.
    if (keys.isShiftPressed ||
        keys.isAltPressed ||
        widget.controller.value.composing.isValid) {
      return KeyEventResult.ignored;
    }
    if (key == LogicalKeyboardKey.keyX) return _cutLine();
    if (key == LogicalKeyboardKey.keyV) return _pasteLine();
    return KeyEventResult.ignored;
  }

  // ---- Recorte de linha (VS Code): Cmd/Ctrl+X sem seleção recorta a linha
  // inteira; Cmd/Ctrl+V sem seleção, com aquela mesma linha ainda na área de
  // transferência, cola acima da linha do cursor. Com seleção, os dois seguem
  // o caminho normal do campo. [_lineClipboard] é estático para valer entre
  // editores, como no VS Code (recorta num arquivo, cola em outro).
  static String? _lineClipboard;

  KeyEventResult _cutLine() {
    final ctrl = widget.controller;
    final cut = cutLine(ctrl.value);
    if (cut == null) {
      // Arquivo vazio: nada a recortar, mas o atalho não cai no recorte normal.
      return ctrl.selection.isCollapsed
          ? KeyEventResult.handled
          : KeyEventResult.ignored;
    }
    // Editing is synchronous, like a normal cut. The clipboard result is
    // advisory: window feedback reports a failure without dropping later typing.
    _lineClipboard = cut.clipboard;
    ctrl.value = cut.value;
    unawaited(
      TextClipboardService.instance.write(
        cut.clipboard,
        operation: 'code_editor',
      ),
    );
    return KeyEventResult.handled;
  }

  KeyEventResult _pasteLine() {
    final line = _lineClipboard;
    if (line == null || !widget.controller.selection.isCollapsed) {
      return KeyEventResult.ignored;
    }
    // A leitura da área de transferência é assíncrona e o atalho precisa ser
    // decidido agora: o editor assume a tecla e, se o conteúdo mudou desde o
    // recorte (copiado de outro lugar), devolve ao colar normal do campo.
    unawaited(_pasteLineAsync(line));
    return KeyEventResult.handled;
  }

  Future<void> _pasteLineAsync(String line) async {
    final before = widget.controller.value;
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    if (!mounted) return;
    final ctrl = widget.controller;
    if (data?.text != line) {
      _lineClipboard = null;
      final fieldContext = widget.focusNode.context;
      if (fieldContext != null && fieldContext.mounted) {
        Actions.maybeInvoke(
          fieldContext,
          const PasteTextIntent(SelectionChangedCause.keyboard),
        );
      }
      return;
    }
    // O usuário mexeu no texto durante a leitura: não cola em lugar velho.
    if (ctrl.value != before) return;
    ctrl.value = pasteLineAbove(ctrl.value, line);
  }

  void _applyComment(_CommentOp op) {
    final syntax = commentSyntaxFor(widget.controller.language);
    if (syntax == null) return;
    final value = widget.controller.value;
    final next = switch (op) {
      _CommentOp.add => addLineComment(value, syntax),
      _CommentOp.remove => removeLineComment(value, syntax),
      _CommentOp.toggle => toggleLineComment(value, syntax),
    };
    if (next != value) widget.controller.value = next;
  }

  /// Unidade detectada, invalidada quando o texto muda (arquivo trocado ou
  /// editado): recomputa sob demanda no próximo Tab.
  IndentUnit? _indentUnit;
  String? _indentUnitText;

  IndentUnit _resolveIndentUnit() {
    final text = widget.controller.text;
    if (_indentUnit != null && identical(_indentUnitText, text)) {
      return _indentUnit!;
    }
    final unit = detectIndentUnit(text, path: widget.filePath);
    _indentUnit = unit;
    _indentUnitText = text;
    return unit;
  }

  Object? _applyIndent({required bool outdent}) {
    if (widget.readOnly) return null;
    final ctrl = widget.controller;
    final unit = _resolveIndentUnit();
    final next = outdent
        ? applyOutdent(ctrl.value, unit)
        : applyIndent(ctrl.value, unit);
    if (next != ctrl.value) ctrl.value = next;
    return null;
  }

  String? _lastText;

  void _onChanged() {
    _rebuildLineStarts();
    final text = widget.controller.text;
    final n = '\n'.allMatches(text).length + 1;
    final diag = widget.controller.diagnostics;
    // Com quebra, editar uma linha muda quantas linhas visuais ela ocupa sem
    // mudar o nº de linhas: o gutter (alturas da tabela) também precisa de
    // rebuild a cada mudança de **texto** (seleção sozinha não conta).
    final wrapTextChanged = widget.wordWrap && !identical(text, _lastText);
    final variableTextChanged =
        !identical(text, _lastText) && _hoverVariable != null;
    if (variableTextChanged) _closeVariablePopover();
    _lastText = text;
    if (wrapTextChanged) _wrapDirty = true;
    // Rebuild do gutter quando o nº de linhas OU os diagnostics mudam (o campo
    // de texto repinta sozinho via buildTextSpan; o gutter depende de setState).
    if ((n != _lineCount ||
            !identical(diag, _lastDiag) ||
            wrapTextChanged ||
            variableTextChanged) &&
        mounted) {
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
    _chordTimer?.cancel();
    _variableHideTimer?.cancel();
    widget.controller.removeListener(_onChanged);
    widget.controller.removeListener(_keepHorizontalOnSelection);
    _horizontal.removeListener(_onHorizontalScroll);
    _vertical.removeListener(_syncGutter);
    _vertical.removeListener(_onVariableScroll);
    _horizontal.removeListener(_onVariableScroll);
    widget.controller.definitionHoverRange = null;
    _vertical.dispose();
    _horizontal.dispose();
    _completionScroll.dispose();
    _gutter.dispose();
    _wrap.dispose();
    super.dispose();
  }

  /// Largura fixa reservada pro slot do ícone de severity — **sempre** presente
  /// (mesmo sem diagnostic) pra que a coluna do gutter não mude de largura e
  /// empurre o código quando um erro aparece/some.
  static const double _iconSlot = 16;
  bool get _hasLineControls =>
      widget.compactGutter ||
      widget.lineActions.isNotEmpty ||
      widget.foldActions.isNotEmpty;
  double get _gutterRightPadding => _hasLineControls ? 4 : 14;
  double get _codeLeftPadding => _hasLineControls ? 6 : 14;
  bool _hoveringGutter = false;

  /// Uma linha do gutter: um slot fixo (ícone de severity quando há diagnostic,
  /// senão vazio) + o número. O ícone (12px) cabe na altura da linha de texto,
  /// mantendo o alinhamento 1:1 com o código.
  Widget _gutterLine(int oneBased, TextStyle numStyle) {
    final severity = widget.controller.severityForLine(oneBased - 1);
    final action = widget.lineActions[oneBased - 1];
    final foldAction = widget.foldActions[oneBased - 1];
    final hasControls = _hasLineControls;
    final Widget slot;
    if (action != null) {
      final button = Semantics(
        button: true,
        label: widget.lineActionTooltip,
        child: MouseRegion(
          cursor: SystemMouseCursors.click,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: action,
            child: SizedBox(
              width: _iconSlot,
              height: _lineHeight,
              child: Icon(Icons.play_arrow, size: 17, color: context.colors.ok),
            ),
          ),
        ),
      );
      slot = widget.lineActionTooltip == null
          ? button
          : AppTooltip(message: widget.lineActionTooltip!, child: button);
    } else if (severity == null) {
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
    final row = Stack(
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
        Transform.translate(
          // Os glifos de Text no gutter têm mais leading que os do EditableText.
          offset: Offset(0, _hasLineControls ? -_lineHeight * 0.25 : 0),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              if (!hasControls) slot,
              SizedBox(
                width: _digitsWidth,
                child: Align(
                  alignment: Alignment.topRight,
                  child: Text(
                    '${widget.lineNumbers?[oneBased - 1] ?? oneBased}',
                    style: numStyle,
                  ),
                ),
              ),
              if (hasControls) ...[
                slot,
                SizedBox(
                  width: _iconSlot,
                  height: _lineHeight,
                  child:
                      foldAction != null &&
                          (_hoveringGutter ||
                              widget.foldedLines.contains(oneBased - 1))
                      ? MouseRegion(
                          cursor: SystemMouseCursors.click,
                          child: GestureDetector(
                            behavior: HitTestBehavior.opaque,
                            onTap: foldAction,
                            child: Icon(
                              widget.foldedLines.contains(oneBased - 1)
                                  ? Icons.chevron_right
                                  : Icons.keyboard_arrow_down,
                              size: 14,
                              color: context.colors.text3,
                            ),
                          ),
                        )
                      : null,
                ),
              ],
            ],
          ),
        ),
      ],
    );
    return row;
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
    _buildScaler = MediaQuery.textScalerOf(context);
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
      text: TextSpan(
        text: '${widget.lineNumbers?.last ?? _lineCount}',
        style: codeStyle,
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    _digitsWidth = digitsProbe.width;
    final controlsWidth = _hasLineControls ? _iconSlot * 2 : _iconSlot;
    _gutterWidth = 14 + controlsWidth + _digitsWidth + _gutterRightPadding + 1;

    // Clicar em qualquer ponto do editor (gutter, padding, espaço abaixo da
    // última linha) foca o campo — como num editor de verdade. Cliques sobre o
    // próprio TextField ganham a arena de gestos e posicionam o cursor; os
    // demais caem aqui. `translucent` pra não roubar o tap do campo.
    final editor = GestureDetector(
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
                if (widget.onCompletionSelected != null)
                  _completionOverlay(
                    context,
                    viewport.maxWidth,
                    viewport.maxHeight,
                  ),
                if (_hoverMsgs.isNotEmpty && _hoverLine != null)
                  _hoverOverlay(context, viewport.maxWidth),
              ],
            ),
          ),
        ),
      ),
    );
    if (widget.variableNameAt == null) return editor;
    return OverlayPortal(
      controller: _variablePortal,
      overlayChildBuilder: _variablePopoverOverlay,
      child: editor,
    );
  }

  Widget _variablePopoverOverlay(BuildContext overlayContext) {
    final name = _hoverVariable;
    if (name == null || widget.variablePopoverBuilder == null) {
      return const SizedBox.shrink();
    }
    return AnimatedBuilder(
      animation: _variablePosition,
      builder: (context, _) => LayoutBuilder(
        builder: (context, constraints) {
          final anchor = _variableAnchor(overlayContext);
          if (anchor == null) return const SizedBox.shrink();
          final width = (constraints.maxWidth - 16).clamp(0.0, 340.0);
          return CustomSingleChildLayout(
            delegate: _VariablePopoverPosition(anchor),
            child: SizedBox(
              width: width,
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  maxHeight: (constraints.maxHeight - 16).clamp(
                    0.0,
                    double.infinity,
                  ),
                ),
                child: MouseRegion(
                  onEnter: (_) {
                    _pointerOnPopover = true;
                    _reconcileVariablePopover();
                  },
                  onExit: (_) {
                    _pointerOnPopover = false;
                    _reconcileVariablePopover();
                  },
                  child: Focus(
                    onFocusChange: _onPopoverFocusChange,
                    onKeyEvent: (_, event) {
                      if (event is KeyDownEvent &&
                          event.logicalKey == LogicalKeyboardKey.escape) {
                        _closeVariablePopover();
                        return KeyEventResult.handled;
                      }
                      return KeyEventResult.ignored;
                    },
                    child: TapRegion(
                      onTapOutside: (_) => _closeVariablePopover(),
                      child: widget.variablePopoverBuilder!(
                        name,
                        _hoverVariableStart!,
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

  Rect? _variableAnchor(BuildContext overlayContext) {
    final start = _hoverVariableStart;
    final editable = _renderEditable();
    final overlay = Overlay.maybeOf(overlayContext)?.context.findRenderObject();
    if (start == null ||
        editable == null ||
        !editable.hasSize ||
        overlay is! RenderBox ||
        !overlay.hasSize) {
      return null;
    }
    final caret = editable.getLocalRectForCaret(TextPosition(offset: start));
    return editable.localToGlobal(caret.topLeft, ancestor: overlay) &
        caret.size;
  }

  Widget _completionOverlay(
    BuildContext context,
    double viewportWidth,
    double viewportHeight,
  ) {
    final popupWidth = widget.completionDetails.isEmpty ? 286.0 : 350.0;
    final width = (viewportWidth - 12).clamp(0.0, popupWidth);
    final caret = widget.controller.selection.baseOffset.clamp(
      0,
      widget.controller.text.length,
    );
    final pos = widget.controller.offsetToLineChar(caret);
    final lineStart = caret - pos.character;
    final prefix = widget.controller.text.substring(lineStart, caret);
    final painter = TextPainter(
      text: TextSpan(text: prefix, style: _codeStyle),
      textDirection: TextDirection.ltr,
    )..layout();
    final scrollH = _horizontal.hasClients ? _horizontal.offset : 0.0;
    final scrollV = _vertical.hasClients ? _vertical.offset : 0.0;
    final x = _gutterWidth + _codeLeftPadding + painter.width - scrollH;
    painter.dispose();
    final left = x.clamp(
      0.0,
      (viewportWidth - width).clamp(0.0, viewportWidth),
    );
    final below = _padTop + (pos.line + 1) * _lineHeight - scrollV + 3;
    final itemHeight = widget.completionDetails.isEmpty ? 31.0 : 43.0;
    final popupHeight = (widget.completionItems.length * itemHeight + 14).clamp(
      46.0,
      236.0,
    );
    final top = below + popupHeight > viewportHeight
        ? (_padTop + pos.line * _lineHeight - scrollV - popupHeight - 3).clamp(
            4.0,
            viewportHeight,
          )
        : below;
    final colors = context.colors;
    return Positioned(
      left: left,
      top: top,
      width: width,
      child: IgnorePointer(
        ignoring: !widget.completionVisible,
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 150),
          reverseDuration: const Duration(milliseconds: 120),
          transitionBuilder: (child, animation) => FadeTransition(
            opacity: animation,
            child: SlideTransition(
              position: Tween<Offset>(
                begin: const Offset(0, -0.06),
                end: Offset.zero,
              ).animate(animation),
              child: child,
            ),
          ),
          child: widget.completionVisible
              ? Container(
                  key: const ValueKey('http-variable-completion'),
                  constraints: BoxConstraints(maxHeight: viewportHeight * 0.55),
                  decoration: BoxDecoration(
                    color: colors.panel2,
                    border: Border.all(color: colors.border),
                    borderRadius: BorderRadius.circular(7),
                    boxShadow: [
                      BoxShadow(
                        color: colors.shadow,
                        blurRadius: 14,
                        offset: const Offset(0, 5),
                      ),
                    ],
                  ),
                  child: widget.completionItems.isEmpty
                      ? Padding(
                          padding: const EdgeInsets.all(10),
                          child: Text(
                            widget.completionEmptyLabel,
                            style: context.typo.label.copyWith(
                              fontSize: 11,
                              color: colors.text3,
                            ),
                          ),
                        )
                      : ListView.builder(
                          controller: _completionScroll,
                          shrinkWrap: true,
                          padding: const EdgeInsets.symmetric(vertical: 4),
                          itemCount: widget.completionItems.length,
                          itemExtent: itemHeight,
                          itemBuilder: (context, index) {
                            final name = widget.completionItems[index];
                            final detail = widget.completionDetails[name];
                            final selected = index == widget.completionIndex;
                            return MouseRegion(
                              cursor: SystemMouseCursors.click,
                              child: GestureDetector(
                                behavior: HitTestBehavior.opaque,
                                onTap: () =>
                                    widget.onCompletionSelected?.call(name),
                                child: Container(
                                  alignment: Alignment.centerLeft,
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 10,
                                  ),
                                  color: selected
                                      ? colors.accent.withValues(alpha: 0.16)
                                      : null,
                                  child: Row(
                                    children: [
                                      Icon(
                                        widget.completionMethods.contains(name)
                                            ? Icons.functions
                                            : Icons.data_object,
                                        size: 14,
                                        color: colors.accent,
                                      ),
                                      const SizedBox(width: 8),
                                      Expanded(
                                        child: detail != null
                                            ? Column(
                                                mainAxisAlignment:
                                                    MainAxisAlignment.center,
                                                crossAxisAlignment:
                                                    CrossAxisAlignment.start,
                                                children: [
                                                  Text(
                                                    name,
                                                    overflow:
                                                        TextOverflow.ellipsis,
                                                    style: context.typo.mono
                                                        .copyWith(
                                                          fontSize: 11.5,
                                                          color: colors.text,
                                                        ),
                                                  ),
                                                  Text(
                                                    detail,
                                                    overflow:
                                                        TextOverflow.ellipsis,
                                                    style: context.typo.label
                                                        .copyWith(
                                                          fontSize: 10,
                                                          color: colors.text3,
                                                        ),
                                                  ),
                                                ],
                                              )
                                            : Text(
                                                name,
                                                overflow: TextOverflow.ellipsis,
                                                style: context.typo.mono
                                                    .copyWith(
                                                      fontSize: 11.5,
                                                      color: colors.text,
                                                    ),
                                              ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            );
                          },
                        ),
                )
              : const SizedBox.shrink(
                  key: ValueKey('http-variable-completion-empty'),
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
    final lineTop = _padTop + _lineTop(_hoverLine!) - scroll;
    const tipWidth = 360.0;
    final left = _hoverDx.clamp(
      8.0,
      (maxWidth - tipWidth - 8).clamp(8.0, maxWidth),
    );
    return Positioned(
      left: left,
      top: lineTop + _lineExtent(_hoverLine!) + 2,
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
    final wrap = widget.wordWrap;

    final field = NotificationListener<ScrollMetricsNotification>(
      onNotification: _updateOverviewMetrics,
      child: Focus(
        key: _fieldKey,
        skipTraversal: true,
        canRequestFocus: false,
        onKeyEvent: _onEditorKey,
        child: Actions(
          actions: _indentActions,
          child: TextField(
            controller: widget.controller,
            inputFormatters:
                widget.autoCloseHttpVariables || widget.autoEditHttpScripts
                ? [
                    if (widget.autoCloseHttpVariables)
                      const HttpVariableBraceFormatter(),
                    if (widget.autoEditHttpScripts)
                      const HttpScriptEditingFormatter(),
                  ]
                : null,
            readOnly: widget.readOnly,
            focusNode: widget.focusNode,
            scrollController: _vertical,
            style: codeStyle,
            cursorColor: syntax.base,
            maxLines: null,
            minLines: null,
            expands: true,
            keyboardType: TextInputType.multiline,
            onTap: () {
              if (_definitionModifierPressed &&
                  (_definitionModeHovered || _linkOffsetAtTap() != null)) {
                _onDefinitionTap();
              } else {
                widget.onCodeTap?.call();
              }
            },
            mouseCursor: _defCursor,
            decoration: const InputDecoration(
              isCollapsed: true,
              border: InputBorder.none,
              contentPadding: EdgeInsets.only(bottom: _padBottom),
            ),
          ),
        ),
      ),
    );

    // Gutter — scroll próprio (travado ao input) espelhando `_vertical`.
    //
    // `ListView.builder` (e não `Column`): com uma Column, um arquivo de 5k
    // linhas materializava 5000 Rows+Texts A CADA rebuild — e rebuild acontece
    // até quando o mouse cruza uma linha (o tooltip de diagnostic faz
    // setState). Virtualizado, só as ~40 linhas visíveis são construídas, e
    // `severityForLine` (que varre os diagnostics) roda só pra elas.
    //
    // `itemExtent: _lineHeight` é o que mantém o alinhamento 1:1 com o texto —
    // mesma métrica que o campo usa por linha — e ainda dá scroll O(1) (o
    // `jumpTo` do `_syncGutter` não precisa medir os itens anteriores). Com
    // quebra, cada linha lógica tem a altura medida pelo [_wrap]
    // (`itemExtentBuilder`): o número fica no topo da primeira linha visual e
    // a soma das alturas continua igual à altura do conteúdo do campo.
    // Largura fixa porque a ListView, ao contrário da Column dentro do
    // SingleChildScrollView, não é intrínseca: sem isso o gutter esticaria e
    // comeria o campo.
    final gutter = MouseRegion(
      onEnter: (_) => setState(() => _hoveringGutter = true),
      onExit: (_) => setState(() => _hoveringGutter = false),
      child: Padding(
        padding: EdgeInsets.only(left: 14, right: _gutterRightPadding),
        child: SizedBox(
          width: (_hasLineControls ? _iconSlot * 2 : _iconSlot) + _digitsWidth,
          child: ListView.builder(
            controller: _gutter,
            physics: const NeverScrollableScrollPhysics(),
            padding: const EdgeInsets.only(bottom: _padBottom),
            itemExtent: wrap ? null : _lineHeight,
            itemExtentBuilder: wrap
                ? (i, _) {
                    _ensureWrap();
                    return _wrap.height(i);
                  }
                : null,
            itemCount: lineCount,
            itemBuilder: (context, i) => _gutterLine(i + 1, numStyle),
          ),
        ),
      ),
    );

    final divider = Container(
      width: 1,
      color: syntax.base.withValues(alpha: 0.15),
    );

    // Folga inferior DENTRO dos scrolls (`_padBottom`) — a última linha
    // assenta acima da scrollbar horizontal.
    final Widget body;
    if (wrap) {
      // Sem scroll horizontal: o campo ocupa a largura da pane e quebra. A
      // largura de quebra sai AQUI, no layout do Row; a tabela é medida no
      // layout do gutter (primeiro filho, antes do campo) via [_ensureWrap].
      body = LayoutBuilder(
        builder: (context, constraints) {
          final fieldWidth =
              (constraints.maxWidth - _gutterWidth - _codeLeftPadding - 16)
                  .clamp(0.0, double.infinity);
          _wrapWidth = (fieldWidth - kEditorWrapCaretMargin).clamp(
            1.0,
            double.infinity,
          );
          _wrapDirty = true;
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              gutter,
              divider,
              Expanded(
                child: Padding(
                  padding: EdgeInsets.only(left: _codeLeftPadding, right: 16),
                  child: field,
                ),
              ),
            ],
          );
        },
      );
    } else {
      body = Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          gutter,
          divider,
          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) {
                // Largura mínima = viewport (menos o padding H). Sem isso, o
                // IntrinsicWidth colapsa o campo a ~0 quando o arquivo está
                // vazio → sem área pra clicar/digitar.
                final minWidth = (constraints.maxWidth - _codeLeftPadding - 16)
                    .clamp(0.0, double.infinity);
                return SingleChildScrollView(
                  controller: _horizontal,
                  scrollDirection: Axis.horizontal,
                  padding: EdgeInsets.only(left: _codeLeftPadding, right: 16),
                  child: ConstrainedBox(
                    constraints: BoxConstraints(minWidth: minWidth),
                    child: IntrinsicWidth(child: field),
                  ),
                );
              },
            ),
          ),
        ],
      );
    }

    // `_padTop` fica FORA do Scrollbar vertical: trilha do thumb, overview e
    // viewport do TextField compartilham a mesma altura (senão os ticks
    // desalinhavam do scroll por 14px no topo).
    final column = Column(
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
                    child: body,
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
                      wrap: wrap ? _wrap : null,
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
    );
    // Sem quebra não há scroll horizontal — nem a barra dele.
    if (wrap) return column;
    return Scrollbar(
      controller: _horizontal,
      thumbVisibility: true,
      scrollbarOrientation: ScrollbarOrientation.bottom,
      notificationPredicate: (n) => n.metrics.axis == Axis.horizontal,
      child: column,
    );
  }
}

/// Posiciona pelo caret inicial da variável; usa o tamanho real do conteúdo
/// para inverter acima/abaixo e manter o popover dentro do overlay da janela.
class _VariablePopoverPosition extends SingleChildLayoutDelegate {
  const _VariablePopoverPosition(this.anchor);

  final Rect anchor;

  @override
  BoxConstraints getConstraintsForChild(BoxConstraints constraints) =>
      BoxConstraints.loose(constraints.biggest);

  @override
  Offset getPositionForChild(Size size, Size childSize) {
    final maxX = (size.width - childSize.width - 8).clamp(8.0, size.width);
    final maxY = (size.height - childSize.height - 8).clamp(8.0, size.height);
    final x = anchor.left.clamp(8.0, maxX);
    final below = anchor.bottom + 4;
    final y = below + childSize.height <= size.height - 8
        ? below
        : anchor.top - childSize.height - 4;
    return Offset(x, y.clamp(8.0, maxY));
  }

  @override
  bool shouldRelayout(_VariablePopoverPosition oldDelegate) =>
      anchor != oldDelegate.anchor;
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

enum _CommentOp { add, remove, toggle }
