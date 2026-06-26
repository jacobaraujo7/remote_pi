// Fork do `RenderTerminal` do xterm (src/ui/render.dart), trazido pra dentro do
// cockpit pra ganharmos controle do *renderer* sem manter um fork do pacote
// inteiro. O "cérebro" (parser ANSI + buffer) continua sendo o do xterm; aqui só
// trocamos o *pintor*.
//
// Única mudança funcional vs. o original: **cache de `ui.Picture` por linha**.
// O xterm re-grava cada célula visível (drawRect do fundo + drawParagraph do
// glifo) a cada frame — ~10k draw calls por frame quando um harness despeja
// saída, daí a lentidão. Aqui gravamos cada *linha* num `Picture` chaveado pelo
// hash do conteúdo: linhas estáveis viram um único `drawPicture` (barato na GPU)
// e só as linhas que mudaram são re-gravadas. Cursor, seleção e highlights
// continuam pintados por cima, ao vivo (não entram no cache da linha), então
// selecionar/piscar cursor não invalida nada.
//
// Reusamos o `CockpitTerminalPainter` do xterm (que já tem cache de parágrafo, glifos
// procedurais de bloco/borda do nosso fork e resolução correta de cor/flags) —
// não há por que reescrever a pintura de célula, que está correta.
//
// ignore_for_file: implementation_imports
import 'dart:math' show max;
import 'dart:ui';

import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:xterm/src/core/buffer/cell_offset.dart';
import 'package:xterm/src/core/buffer/line.dart';
import 'package:xterm/src/core/buffer/range.dart';
import 'package:xterm/src/core/buffer/segment.dart';
import 'package:xterm/src/core/mouse/button.dart';
import 'package:xterm/src/core/mouse/button_state.dart';
import 'package:xterm/src/terminal.dart';
import 'package:xterm/src/ui/controller.dart';
import 'package:xterm/src/ui/cursor_type.dart';
import 'package:xterm/src/ui/selection_mode.dart';
import 'package:xterm/src/ui/terminal_size.dart';
import 'package:xterm/src/ui/terminal_text_style.dart';
import 'package:xterm/src/ui/terminal_theme.dart';

import 'cockpit_terminal_painter.dart';

typedef EditableRectCallback = void Function(Rect rect, Rect caretRect);

class CockpitTerminalRender extends RenderBox
    with RelayoutWhenSystemFontsChangeMixin {
  CockpitTerminalRender({
    required Terminal terminal,
    required TerminalController controller,
    required ViewportOffset offset,
    required EdgeInsets padding,
    required bool autoResize,
    required TerminalStyle textStyle,
    required TextScaler textScaler,
    required TerminalTheme theme,
    required FocusNode focusNode,
    required TerminalCursorType cursorType,
    required bool alwaysShowCursor,
    required double devicePixelRatio,
    EditableRectCallback? onEditableRect,
    String? composingText,
  }) : _terminal = terminal,
       _controller = controller,
       _offset = offset,
       _padding = padding,
       _autoResize = autoResize,
       _focusNode = focusNode,
       _cursorType = cursorType,
       _alwaysShowCursor = alwaysShowCursor,
       _onEditableRect = onEditableRect,
       _composingText = composingText,
       _painter = CockpitTerminalPainter(
         theme: theme,
         textStyle: textStyle,
         textScaler: textScaler,
         devicePixelRatio: devicePixelRatio,
       );

  Terminal _terminal;
  set terminal(Terminal terminal) {
    if (_terminal == terminal) return;
    if (attached) _terminal.removeListener(_onTerminalChange);
    _terminal = terminal;
    if (attached) _terminal.addListener(_onTerminalChange);
    _lineCache.clear();
    _resizeTerminalIfNeeded();
    markNeedsLayout();
  }

  TerminalController _controller;
  set controller(TerminalController controller) {
    if (_controller == controller) return;
    if (attached) _controller.removeListener(_onControllerUpdate);
    _controller = controller;
    if (attached) _controller.addListener(_onControllerUpdate);
    markNeedsLayout();
  }

  ViewportOffset _offset;
  set offset(ViewportOffset value) {
    if (value == _offset) return;
    if (attached) _offset.removeListener(_onScroll);
    _offset = value;
    if (attached) _offset.addListener(_onScroll);
    markNeedsLayout();
  }

  EdgeInsets _padding;
  set padding(EdgeInsets value) {
    if (value == _padding) return;
    _padding = value;
    markNeedsLayout();
  }

  bool _autoResize;
  set autoResize(bool value) {
    if (value == _autoResize) return;
    _autoResize = value;
    markNeedsLayout();
  }

  set textStyle(TerminalStyle value) {
    if (value == _painter.textStyle) return;
    _painter.textStyle = value;
    _lineCache
        .clear(); // glifos mudam de tamanho/forma → pictures velhas inválidas
    markNeedsLayout();
  }

  set textScaler(TextScaler value) {
    if (value == _painter.textScaler) return;
    _painter.textScaler = value;
    _lineCache.clear();
    markNeedsLayout();
  }

  set theme(TerminalTheme value) {
    if (value == _painter.theme) return;
    _painter.theme = value;
    _lineCache.clear(); // cores mudam → re-gravar tudo
    markNeedsPaint();
  }

  set devicePixelRatio(double value) {
    if (value == _painter.devicePixelRatio) return;
    _painter.devicePixelRatio = value; // re-snap do cellSize → relayout
    _lineCache.clear();
    markNeedsLayout();
  }

  FocusNode _focusNode;
  set focusNode(FocusNode value) {
    if (value == _focusNode) return;
    if (attached) _focusNode.removeListener(_onFocusChange);
    _focusNode = value;
    if (attached) _focusNode.addListener(_onFocusChange);
    markNeedsPaint();
  }

  TerminalCursorType _cursorType;
  set cursorType(TerminalCursorType value) {
    if (value == _cursorType) return;
    _cursorType = value;
    markNeedsPaint();
  }

  bool _alwaysShowCursor;
  set alwaysShowCursor(bool value) {
    if (value == _alwaysShowCursor) return;
    _alwaysShowCursor = value;
    markNeedsPaint();
  }

  EditableRectCallback? _onEditableRect;
  set onEditableRect(EditableRectCallback? value) {
    if (value == _onEditableRect) return;
    _onEditableRect = value;
    markNeedsLayout();
  }

  String? _composingText;
  set composingText(String? value) {
    if (value == _composingText) return;
    _composingText = value;
    markNeedsPaint();
  }

  TerminalSize? _viewportSize;

  final CockpitTerminalPainter _painter;

  /// Cache de uma `Picture` por conteúdo de linha (ver nota no topo do arquivo).
  final _lineCache = _LinePictureCache(maxSize: 512);

  var _stickToBottom = true;

  void _onScroll() {
    _stickToBottom = _scrollOffset >= _maxScrollExtent;
    markNeedsLayout();
    _notifyEditableRect();
  }

  void _onFocusChange() {
    markNeedsPaint();
  }

  void _onTerminalChange() {
    markNeedsLayout();
    _notifyEditableRect();
  }

  void _onControllerUpdate() {
    markNeedsLayout();
  }

  @override
  final isRepaintBoundary = true;

  @override
  void attach(PipelineOwner owner) {
    super.attach(owner);
    _offset.addListener(_onScroll);
    _terminal.addListener(_onTerminalChange);
    _controller.addListener(_onControllerUpdate);
    _focusNode.addListener(_onFocusChange);
  }

  @override
  void detach() {
    super.detach();
    _offset.removeListener(_onScroll);
    _terminal.removeListener(_onTerminalChange);
    _controller.removeListener(_onControllerUpdate);
    _focusNode.removeListener(_onFocusChange);
  }

  @override
  void dispose() {
    _lineCache.clear(); // libera os Pictures nativos
    super.dispose();
  }

  @override
  bool hitTestSelf(Offset position) {
    return true;
  }

  @override
  void systemFontsDidChange() {
    _painter.clearFontCache();
    _lineCache.clear();
    super.systemFontsDidChange();
  }

  @override
  void performLayout() {
    size = constraints.biggest;

    _updateViewportSize();

    _updateScrollOffset();

    if (_stickToBottom) {
      _offset.correctBy(_maxScrollExtent - _scrollOffset);
    }
  }

  /// Total height of the terminal in pixels. Includes scrollback buffer.
  double get _terminalHeight =>
      _terminal.buffer.lines.length * _painter.cellSize.height;

  /// The distance from the top of the terminal to the top of the viewport.
  double get _scrollOffset {
    return _offset.pixels;
  }

  /// The height of a terminal line in pixels. This includes the line spacing.
  /// Height of the entire terminal is expected to be a multiple of this value.
  double get lineHeight => _painter.cellSize.height;

  /// Get the top-left corner of the cell at [cellOffset] in pixels.
  Offset getOffset(CellOffset cellOffset) {
    final row = cellOffset.y;
    final col = cellOffset.x;
    final x = col * _painter.cellSize.width;
    final y = row * _painter.cellSize.height;
    return Offset(x + _padding.left, y + _padding.top - _scrollOffset);
  }

  /// Get the [CellOffset] of the cell that [offset] is in.
  CellOffset getCellOffset(Offset offset) {
    final x = offset.dx - _padding.left;
    final y = offset.dy - _padding.top + _scrollOffset;
    final row = y ~/ _painter.cellSize.height;
    final col = x ~/ _painter.cellSize.width;
    return CellOffset(
      col.clamp(0, _terminal.viewWidth - 1),
      row.clamp(0, _terminal.buffer.lines.length - 1),
    );
  }

  /// Selects entire words in the terminal that contains [from] and [to].
  void selectWord(Offset from, [Offset? to]) {
    final fromOffset = getCellOffset(from);
    final fromBoundary = _terminal.buffer.getWordBoundary(fromOffset);
    if (fromBoundary == null) return;
    if (to == null) {
      _controller.setSelection(
        _terminal.buffer.createAnchorFromOffset(fromBoundary.begin),
        _terminal.buffer.createAnchorFromOffset(fromBoundary.end),
        mode: SelectionMode.line,
      );
    } else {
      final toOffset = getCellOffset(to);
      final toBoundary = _terminal.buffer.getWordBoundary(toOffset);
      if (toBoundary == null) return;
      final range = fromBoundary.merge(toBoundary);
      _controller.setSelection(
        _terminal.buffer.createAnchorFromOffset(range.begin),
        _terminal.buffer.createAnchorFromOffset(range.end),
        mode: SelectionMode.line,
      );
    }
  }

  /// Selects characters in the terminal that starts from [from] to [to]. At
  /// least one cell is selected even if [from] and [to] are same.
  void selectCharacters(Offset from, [Offset? to]) {
    final fromPosition = getCellOffset(from);
    if (to == null) {
      _controller.setSelection(
        _terminal.buffer.createAnchorFromOffset(fromPosition),
        _terminal.buffer.createAnchorFromOffset(fromPosition),
      );
    } else {
      var toPosition = getCellOffset(to);
      if (toPosition.x >= fromPosition.x) {
        toPosition = CellOffset(toPosition.x + 1, toPosition.y);
      }
      _controller.setSelection(
        _terminal.buffer.createAnchorFromOffset(fromPosition),
        _terminal.buffer.createAnchorFromOffset(toPosition),
      );
    }
  }

  /// Send a mouse event at [offset] with [button] being currently in [buttonState].
  bool mouseEvent(
    TerminalMouseButton button,
    TerminalMouseButtonState buttonState,
    Offset offset,
  ) {
    final position = getCellOffset(offset);
    return _terminal.mouseInput(button, buttonState, position);
  }

  void _notifyEditableRect() {
    final cursor = localToGlobal(cursorOffset);

    final rect = Rect.fromLTRB(
      cursor.dx,
      cursor.dy,
      size.width,
      cursor.dy + _painter.cellSize.height,
    );

    final caretRect = cursor & _painter.cellSize;

    _onEditableRect?.call(rect, caretRect);
  }

  /// Update the viewport size in cells based on the current widget size in
  /// pixels.
  void _updateViewportSize() {
    if (size <= _painter.cellSize) {
      return;
    }

    final viewportSize = TerminalSize(
      size.width ~/ _painter.cellSize.width,
      _viewportHeight ~/ _painter.cellSize.height,
    );

    if (_viewportSize != viewportSize) {
      _viewportSize = viewportSize;
      _resizeTerminalIfNeeded();
    }
  }

  /// Notify the underlying terminal that the viewport size has changed.
  void _resizeTerminalIfNeeded() {
    if (_autoResize && _viewportSize != null) {
      _terminal.resize(
        _viewportSize!.width,
        _viewportSize!.height,
        _painter.cellSize.width.round(),
        _painter.cellSize.height.round(),
      );
    }
  }

  /// Update the scroll offset based on the current terminal state. This should
  /// be called in [performLayout] after the viewport size has been updated.
  void _updateScrollOffset() {
    _offset.applyViewportDimension(_viewportHeight);
    _offset.applyContentDimensions(0, _maxScrollExtent);
  }

  bool get _isComposingText {
    return _composingText != null && _composingText!.isNotEmpty;
  }

  bool get _shouldShowCursor {
    return _terminal.cursorVisibleMode || _alwaysShowCursor || _isComposingText;
  }

  double get _viewportHeight {
    return size.height - _padding.vertical;
  }

  double get _maxScrollExtent {
    return max(_terminalHeight - _viewportHeight, 0.0);
  }

  double get _lineOffset {
    return -_scrollOffset + _padding.top;
  }

  /// The offset of the cursor from the top left corner of this render object.
  Offset get cursorOffset {
    return Offset(
      _terminal.buffer.cursorX * _painter.cellSize.width,
      _terminal.buffer.absoluteCursorY * _painter.cellSize.height + _lineOffset,
    );
  }

  Size get cellSize {
    return _painter.cellSize;
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    _paint(context, offset);
    context.setWillChangeHint();
  }

  void _paint(PaintingContext context, Offset offset) {
    final canvas = context.canvas;

    final lines = _terminal.buffer.lines;
    final charHeight = _painter.cellSize.height;

    final firstLineOffset = _scrollOffset - _padding.top;
    final lastLineOffset = _scrollOffset + size.height + _padding.bottom;

    final firstLine = firstLineOffset ~/ charHeight;
    final lastLine = lastLineOffset ~/ charHeight;

    final effectFirstLine = firstLine.clamp(0, lines.length - 1);
    final effectLastLine = lastLine.clamp(0, lines.length - 1);

    for (var i = effectFirstLine; i <= effectLastLine; i++) {
      final line = lines[i];
      final dy = (i * charHeight + _lineOffset).truncateToDouble();

      // Cache por conteúdo: a Picture é gravada em (0,0) e reposicionada no draw,
      // então linhas com o mesmo conteúdo (ex.: várias linhas em branco) e a
      // mesma linha em frames seguintes reaproveitam a mesma Picture.
      final key = _hashLine(line);
      var picture = _lineCache.get(key);
      if (picture == null) {
        picture = _recordLine(line);
        _lineCache.put(key, picture);
      }

      canvas.save();
      canvas.translate(offset.dx, offset.dy + dy);
      canvas.drawPicture(picture);
      canvas.restore();
    }

    if (_terminal.buffer.absoluteCursorY >= effectFirstLine &&
        _terminal.buffer.absoluteCursorY <= effectLastLine) {
      if (_isComposingText) {
        _paintComposingText(canvas, offset + cursorOffset);
      }

      if (_shouldShowCursor) {
        _painter.paintCursor(
          canvas,
          offset + cursorOffset,
          cursorType: _cursorType,
          hasFocus: _focusNode.hasFocus,
        );
      }
    }

    _paintHighlights(
      canvas,
      _controller.highlights,
      effectFirstLine,
      effectLastLine,
    );

    if (_controller.selection != null) {
      _paintSelection(
        canvas,
        _controller.selection!,
        effectFirstLine,
        effectLastLine,
      );
    }
  }

  /// Grava uma única linha (fundo + glifos) num `Picture`, em (0,0). Reusa o
  /// `CockpitTerminalPainter` do xterm, então herda cache de parágrafo e glifos
  /// procedurais sem reimplementar nada.
  Picture _recordLine(BufferLine line) {
    final recorder = PictureRecorder();
    final canvas = Canvas(recorder);
    _painter.paintLine(canvas, Offset.zero, line);
    return recorder.endRecording();
  }

  /// Hash FNV-1a sobre as células da linha (4 ints por célula no buffer do
  /// xterm). Barato comparado a re-gravar a linha; é o que decide se a Picture
  /// cacheada ainda vale.
  int _hashLine(BufferLine line) {
    final data = line.data;
    final count = line.length * 4;
    var hash = 0x811c9dc5;
    for (var i = 0; i < count; i++) {
      hash = (hash ^ data[i]) & 0xffffffff;
      hash = (hash * 0x01000193) & 0xffffffff;
    }
    return hash;
  }

  /// Paints the text that is currently being composed in IME to [canvas] at
  /// [offset]. [offset] is usually the cursor position.
  void _paintComposingText(Canvas canvas, Offset offset) {
    final composingText = _composingText;
    if (composingText == null) {
      return;
    }

    final style = _painter.textStyle.toTextStyle(
      color: _painter.resolveForegroundColor(_terminal.cursor.foreground),
      backgroundColor: _painter.theme.background,
      underline: true,
    );

    final builder = ParagraphBuilder(style.getParagraphStyle());
    builder.addPlaceholder(
      offset.dx,
      _painter.cellSize.height,
      PlaceholderAlignment.middle,
    );
    builder.pushStyle(style.getTextStyle(textScaler: _painter.textScaler));
    builder.addText(composingText);

    final paragraph = builder.build();
    paragraph.layout(ParagraphConstraints(width: size.width));

    canvas.drawParagraph(paragraph, Offset(0, offset.dy));
  }

  void _paintSelection(
    Canvas canvas,
    BufferRange selection,
    int firstLine,
    int lastLine,
  ) {
    for (final segment in selection.toSegments()) {
      if (segment.line >= _terminal.buffer.lines.length) {
        break;
      }

      if (segment.line < firstLine) {
        continue;
      }

      if (segment.line > lastLine) {
        break;
      }

      _paintSegment(canvas, segment, _painter.theme.selection);
    }
  }

  void _paintHighlights(
    Canvas canvas,
    List<TerminalHighlight> highlights,
    int firstLine,
    int lastLine,
  ) {
    for (var highlight in _controller.highlights) {
      final range = highlight.range?.normalized;

      if (range == null ||
          range.begin.y > lastLine ||
          range.end.y < firstLine) {
        continue;
      }

      for (var segment in range.toSegments()) {
        if (segment.line < firstLine) {
          continue;
        }

        if (segment.line > lastLine) {
          break;
        }

        _paintSegment(canvas, segment, highlight.color);
      }
    }
  }

  @pragma('vm:prefer-inline')
  void _paintSegment(Canvas canvas, BufferSegment segment, Color color) {
    final start = segment.start ?? 0;
    final end = segment.end ?? _terminal.viewWidth;

    final startOffset = Offset(
      start * _painter.cellSize.width,
      segment.line * _painter.cellSize.height + _lineOffset,
    );

    _painter.paintHighlight(canvas, startOffset, end - start, color);
  }
}

/// LRU mínimo de `Picture` por linha. Um `Map` em Dart preserva a ordem de
/// inserção, então a chave mais antiga é a primeira; ao acessar, reinserimos pra
/// promover a MRU. Pictures evictadas/limpas são `dispose()`-adas (recurso
/// nativo — não some sozinho).
class _LinePictureCache {
  _LinePictureCache({required this.maxSize});

  final int maxSize;
  final _map = <int, Picture>{};

  Picture? get(int key) {
    final picture = _map.remove(key);
    if (picture != null) _map[key] = picture; // promove a MRU
    return picture;
  }

  void put(int key, Picture picture) {
    _map[key] = picture;
    if (_map.length > maxSize) {
      final oldestKey = _map.keys.first;
      _map.remove(oldestKey)?.dispose();
    }
  }

  void clear() {
    for (final picture in _map.values) {
      picture.dispose();
    }
    _map.clear();
  }
}
