part of 'frame_builder.dart';

const _italicOverhangFontSizeFactor = 0.15;

// Conservative context lets boundary-crossing ligatures shape correctly.
const _operatorLigatureContextCells = 16;

// Above common wide terminal columns; caps pathological operator animations.
const _operatorRunChunkCells = 256;

bool _isGraphicsElement(int codepoint) => switch (codepoint) {
  >= 0x2500 && <= 0x259F ||
  >= 0xE0B0 && <= 0xE0D7 ||
  >= 0x1CC00 && <= 0x1CEBF ||
  >= 0x1FB00 && <= 0x1FBFF => true,
  _ => false,
};

/// ASCII punctuation/operator: not digit, not uppercase, not lowercase.
bool _isOperator(int cp) {
  return cp < 0x30 ||
      (cp > 0x39 && cp < 0x41) ||
      (cp > 0x5A && cp < 0x61) ||
      cp > 0x7A;
}

bool _isSymbolCodepoint(int codepoint) {
  // Matches the symbol blocks Ghostty considers for glyph constraints.
  if (codepoint < 0x2190) return false;
  return switch (codepoint) {
    >= 0xE000 && <= 0xF8FF ||
    >= 0xF0000 && <= 0xFFFFD ||
    >= 0x100000 && <= 0x10FFFD ||
    >= 0x2190 && <= 0x21FF ||
    >= 0x2460 && <= 0x24FF ||
    >= 0x2600 && <= 0x26FF ||
    >= 0x2700 && <= 0x27BF ||
    >= 0x1F100 && <= 0x1F1FF ||
    >= 0x1F300 && <= 0x1F6FF => true,
    _ => false,
  };
}

enum _CellHighlight { none, searchMatch, selection, selectedSearchMatch }

/// Rebuilds rows, owning cell traversal, style transitions, and channel runs.
final class _RowBuilder {
  final Atlas _atlas;
  final PaintState _state;
  final SpriteBuffer _sprites;
  final CellContentResolver _content;
  final _StyleCache _styles;
  final _searchHighlights = _SearchHighlights();
  final _operatorCodepoints = <int>[];
  var _operatorX = 0.0;
  late CellMetrics _metrics;
  var _inverseDpr = 1.0;
  int? _backgroundAlpha;
  late ParagraphStyle _paragraphStyle;
  TerminalTheme? _paragraphStyleTheme;
  TerminalTheme? _lastTextStyleTheme;
  TextStyle? _lastTextStyle;
  var _lastTextStyleForeground = 0;
  var _lastTextStyleBold = false;
  var _lastTextStyleItalic = false;
  var _preedit = const _PreeditText.empty();
  _PreeditRange? _preeditRange;
  LinkSnapshot _links = .empty;
  var _hasLinks = false;

  var _rowIndex = 0;
  var _column = 0;
  var _x = 0.0;
  var _y = 0.0;
  var _prevStyleId = -1;
  int? _prevBackgroundArgb;
  var _prevHighlight = _CellHighlight.none;
  HyperlinkStyle? _prevLinkStyle;
  var _foregroundArgb = 0xFFFFFFFF;
  // Null means no explicit background, not a transparent color.
  int? _backgroundArgb;
  var _style = const Style();
  var _hidden = false;
  var _hasDecoration = false;
  var _hasBlink = false;
  var _backgroundStart = 0;
  int? _backgroundRunArgb;
  var _preeditEmitted = false;
  var _previousSymbol = false;

  _RowBuilder({
    required this._atlas,
    required this._sprites,
    required this._state,
    required this._content,
  }) : _styles = _StyleCache(_state);

  void beginFrame(LinkSnapshot links) {
    _metrics = _state.metrics;
    _inverseDpr = 1.0 / _atlas.devicePixelRatio;
    _links = links;
    _hasLinks = !links.isEmpty;
    final theme = _state.theme;
    _backgroundAlpha =
        theme.backgroundOpacityCells && theme.backgroundOpacity < 1.0
        ? theme.backgroundOpacityAlpha
        : null;
    if (!identical(theme, _paragraphStyleTheme)) {
      _paragraphStyle = ParagraphStyle(
        fontSize: theme.fontSize,
        fontFamily: theme.fontFamily,
        textAlign: .start,
        textDirection: TextDirection.ltr,
      );
      _paragraphStyleTheme = theme;
    }
    _styles.beginFrame();
  }

  bool rebuildRow(int rowIndex, RowIterator rows, CellIterator cells) {
    _sprites.beginRow(rowIndex);
    _rowIndex = rowIndex;
    _y = rowIndex * _metrics.cellHeight;
    _column = 0;
    _x = 0;
    // Native style IDs are unsigned; resolve before reusing cached style.
    _prevStyleId = -1;
    _hasBlink = false;
    _backgroundStart = 0;
    _backgroundRunArgb = null;
    _preeditEmitted = false;
    _previousSymbol = false;
    cells.reset(rows);

    while (cells.next() && _column < _state.cols) {
      _writeCell(cells);
    }

    _flushForeground();
    _flushBackgroundRun(_state.cols);
    _sprites.endRow();
    return _hasBlink;
  }

  ({int? previous, int? current, bool active}) updatePreedit(
    String text, {
    required RenderStateCursor cursor,
  }) {
    final previous = _preeditRange;
    final textChanged = text != _preedit.text;
    if (textChanged) _preedit = _PreeditText.parse(text);
    final next = _PreeditRange.resolve(
      preedit: _preedit,
      cursor: cursor,
      rows: _state.rows,
      cols: _state.cols,
    );

    _preeditRange = next;

    if (!textChanged && (next?.sameGeometry(previous) ?? previous == null)) {
      return (previous: null, current: null, active: next != null);
    }

    return (previous: previous?.row, current: next?.row, active: next != null);
  }

  void updateSearch(
    List<Selection> matches,
    Selection? selected, {
    required int viewportOffset,
    required RowDirtyTracker dirtyRows,
  }) {
    _searchHighlights.update(
      matches,
      selected,
      rows: _state.rows,
      cols: _state.cols,
      viewportOffset: viewportOffset,
      dirtyRows: dirtyRows,
    );
  }

  int _cellBackgroundArgb(int argb, {required bool inverse}) {
    final alpha = _backgroundAlpha;
    if (inverse || alpha == null) return argb;
    final adjustedAlpha = (((argb >>> 24) & 0xFF) * alpha + 127) ~/ 255;
    return (adjustedAlpha << 24) | (argb & 0x00FFFFFF);
  }

  void _closeBackgroundSpan(int span) {
    final endCol = _column + span > _state.cols ? _state.cols : _column + span;
    _flushBackgroundRun(endCol);
    _backgroundStart = endCol;
    _backgroundRunArgb = null;
  }

  void _emitCodepoint(int codepoint, {required double x}) {
    final entry = _content.resolveCodepoint(codepoint, style: _style);
    _emitEntry(entry, x: x, wideText: false);
  }

  void _emitDecorations(int span) {
    final x = _x;
    final style = _style;
    final right = x + _metrics.cellWidth * span;

    final underlineColor = style.underlineColor;
    final color = underlineColor != null
        ? _resolveColorArgb(
            underlineColor,
            _state.terminalPaletteArgb,
            _state.terminalForegroundArgb,
          )
        : _foregroundArgb;

    if (style.underline != UnderlineStyle.none) {
      final entry = _atlas.addDecoration(style.underline);
      for (var i = 0; i < span; i++) {
        _sprites.underline.add(
          x + _metrics.cellWidth * i,
          _y,
          entry,
          _inverseDpr,
          color,
        );
      }
    }

    if (style.strikethrough) {
      final strikeY = _y + _metrics.strikethroughPosition;
      _sprites.decoration.add(
        x,
        strikeY,
        right,
        strikeY + _metrics.strikethroughThickness,
        _foregroundArgb,
      );
    }

    if (style.overline) {
      final overY = _y + _metrics.overlinePosition;
      _sprites.decoration.add(
        x,
        overY,
        right,
        overY + _metrics.underlineThickness,
        _foregroundArgb,
      );
    }
  }

  void _emitEntry(
    AtlasEntry entry, {
    required double x,
    required bool wideText,
    int? foreground,
  }) {
    final color = foreground ?? _foregroundArgb;
    switch (entry.lane) {
      case .emoji:
        _sprites.emoji.add(x, _y, entry, _inverseDpr);
      case .sprite:
        _sprites.sprite.add(
          x + entry.bearingX * _inverseDpr,
          _y + entry.bearingY * _inverseDpr,
          entry,
          _inverseDpr,
          color,
        );
      case .text:
        final sprites = wideText ? _sprites.wide : _sprites.regular;
        sprites.add(
          x + entry.bearingX * _inverseDpr,
          _y + entry.bearingY * _inverseDpr,
          entry,
          _inverseDpr,
          color,
        );
      case .decoration:
        throw StateError('Decoration atlas entries cannot paint cell content.');
    }
  }

  void _emitForeground(
    CellIterator cell, {
    required int span,
    required int glyphSpan,
  }) {
    if (!cell.hasText) {
      _flushForeground();
      return;
    }

    final codepoint = cell.codepoint;
    final style = _style;

    if (span == 1 && codepoint > 0x20 && codepoint < 0x7F) {
      if (_isOperator(codepoint)) {
        if (_operatorCodepoints.isEmpty) _operatorX = _x;
        _operatorCodepoints.add(codepoint);
        return;
      }

      _flushForeground();
      _emitCodepoint(codepoint, x: _x);
      return;
    }

    _flushForeground();
    final entry = _content.resolveCell(
      cell,
      style: style,
      span: glyphSpan,
      borrowedCell: glyphSpan != span,
    );
    if (entry == null) return;
    _emitEntry(entry, x: _x, wideText: glyphSpan == 2);
  }

  void _emitPreedit(_PreeditRange range) {
    final underlineY = _y + _metrics.underlinePosition;
    _sprites.decoration.add(
      range.startCol * _metrics.cellWidth,
      underlineY,
      range.endCol * _metrics.cellWidth,
      underlineY + _metrics.underlineThickness,
      _state.terminalForegroundArgb,
    );

    var col = range.startCol;
    for (var i = range.clusterOffset; i < range.clusters.length; i++) {
      final cluster = range.clusters[i];
      final nextCol = col + cluster.span;
      if (nextCol > range.endCol) break;
      final x = col * _metrics.cellWidth;
      _emitPreeditCluster(cluster, x: x);
      col = nextCol;
    }
  }

  void _emitPreeditCluster(_PreeditCluster cluster, {required double x}) {
    final entry = _content.resolve(
      content: cluster.text,
      codepoint: cluster.firstCodepoint,
      graphemeLength: cluster.graphemeLength,
      style: const Style(),
      span: cluster.span,
    );
    if (entry == null) return;
    _emitEntry(
      entry,
      x: x,
      wideText: cluster.span == 2,
      foreground: _state.terminalForegroundArgb,
    );
  }

  void _emitShapedChunk(int coreStart, int coreEnd) {
    final textStart = math.max(0, coreStart - _operatorLigatureContextCells);
    final textEnd = math.min(
      _operatorCodepoints.length,
      coreEnd + _operatorLigatureContextCells,
    );
    final text = String.fromCharCodes(_operatorCodepoints, textStart, textEnd);
    final theme = _state.theme;
    final textX = _operatorX + _metrics.cellWidth * textStart;
    final coreX = _operatorX + _metrics.cellWidth * coreStart;
    final coreWidth = _metrics.cellWidth * (coreEnd - coreStart);
    final overhang = _style.italic
        ? math.max(
            1.0,
            (theme.fontSize * _italicOverhangFontSizeFactor).ceilToDouble(),
          )
        : 0.0;
    final paragraph =
        (ParagraphBuilder(_paragraphStyle)
              ..pushStyle(_textStyle())
              ..addText(text)
              ..pop())
            .build()
          ..layout(const ParagraphConstraints(width: .infinity));
    _sprites.shaped.add(
      ShapedRun(
        paragraph: paragraph,
        offset: Offset(
          textX,
          _y + _metrics.baseline - paragraph.alphabeticBaseline,
        ),
        clip: Rect.fromLTWH(
          coreX,
          _y,
          coreWidth + overhang,
          _metrics.cellHeight,
        ),
      ),
    );
  }

  void _flushBackgroundRun(int endCol) {
    if (_backgroundRunArgb == null || _backgroundStart >= endCol) return;
    _sprites.background.add(
      _backgroundStart * _metrics.cellWidth,
      _y,
      endCol * _metrics.cellWidth,
      _y + _metrics.cellHeight,
      _backgroundRunArgb!,
    );
  }

  void _flushForeground() {
    if (_operatorCodepoints.isEmpty) return;

    if (_operatorCodepoints.length == 1) {
      _emitCodepoint(_operatorCodepoints.first, x: _operatorX);
    } else {
      for (
        var start = 0;
        start < _operatorCodepoints.length;
        start += _operatorRunChunkCells
      ) {
        _emitShapedChunk(
          start,
          math.min(start + _operatorRunChunkCells, _operatorCodepoints.length),
        );
      }
    }
    _operatorCodepoints.clear();
  }

  int _glyphSpan(CellIterator cell, int span) {
    if (span > 1) {
      _previousSymbol = false;
      return span;
    }

    final codepoint = cell.codepoint;
    final symbol = _isSymbolCodepoint(codepoint);
    final graphicsElement = _isGraphicsElement(codepoint);
    final previousSymbol = _previousSymbol;
    _previousSymbol = symbol && !graphicsElement;
    if (!symbol ||
        graphicsElement ||
        previousSymbol ||
        _column + 1 >= _state.cols) {
      return 1;
    }

    // Symbol glyphs may borrow a following blank cell without changing the
    // terminal's logical cursor or decoration span.
    final currentCol = cell.col;
    cell.select(currentCol + 1);
    final nextCodepoint = cell.codepoint;
    cell.select(currentCol);
    return nextCodepoint == 0 ||
            nextCodepoint == 0x20 ||
            nextCodepoint == 0x2002
        ? 2
        : 1;
  }

  HyperlinkStyle? _linkStyle() {
    if (!_hasLinks) return null;
    final position = Position(row: _rowIndex, col: _column);
    if (_links.isHighlighted(position)) {
      return _state.theme.hyperlink.highlighted;
    }
    return _links.contains(position) ? _state.theme.hyperlink.idle : null;
  }

  void _resolveStyle(
    CellIterator cell, {
    required int? backgroundArgb,
    required _CellHighlight highlight,
    required HyperlinkStyle? linkStyle,
  }) {
    var (fg, bg, style, explicitBg) = _styles.resolve(
      cell,
      backgroundArgb: backgroundArgb,
    );
    final selection = switch (highlight) {
      .searchMatch => _state.theme.search.match,
      .selection => _state.theme.selection,
      .selectedSearchMatch => _state.theme.search.selectedMatch,
      .none => null,
    };
    if (selection != null) {
      final searchHighlight = highlight != .selection;
      final foreground =
          selection.foreground
              ?.resolve(cellForeground: Color(fg), cellBackground: Color(bg))
              .toARGB32() ??
          (searchHighlight ? fg : _state.terminalBackgroundArgb);
      final background =
          selection.background
              ?.resolve(cellForeground: Color(fg), cellBackground: Color(bg))
              .toARGB32() ??
          (searchHighlight ? bg : _state.terminalForegroundArgb);
      fg = foreground;
      bg = background;
      explicitBg = true;
    }

    fg = linkStyle?.textColor?.toARGB32() ?? fg;
    if (linkStyle != null && linkStyle.underline != .none) {
      style = Style(
        bold: style.bold,
        italic: style.italic,
        faint: style.faint,
        blink: style.blink,
        inverse: style.inverse,
        invisible: style.invisible,
        overline: style.overline,
        strikethrough: style.strikethrough,
        foreground: style.foreground,
        background: style.background,
        underline: style.underline == .none ? linkStyle.underline : .double,
        underlineColor: _rgbColor(linkStyle.underlineColor),
      );
    }

    _prevStyleId = cell.styleId;
    _prevBackgroundArgb = backgroundArgb;
    _style = style;
    _hidden = style.invisible || (!_state.blinkVisible && style.blink);
    _hasBlink = _hasBlink || style.blink;
    _hasDecoration =
        style.underline != .none || style.strikethrough || style.overline;
    _foregroundArgb = fg;
    _backgroundArgb = explicitBg
        ? _cellBackgroundArgb(bg, inverse: style.inverse)
        : null;
    _prevHighlight = highlight;
    _prevLinkStyle = linkStyle;
  }

  void _skipPreeditCell(CellIterator cell, _PreeditRange range, int span) {
    if (!_preeditEmitted) {
      // Emit the overlay once at the first covered terminal cell, after
      // closing real background/text runs up to the overlay boundary.
      _flushForeground();
      _flushBackgroundRun(range.startCol);
      _backgroundStart = range.endCol;
      _backgroundRunArgb = null;
      _emitPreedit(range);
      _preeditEmitted = true;
    }

    if (span == 2) cell.next();
    _column += span;
    _x += _metrics.cellWidth * span;
  }

  void _syncBackgroundRun() {
    if (_backgroundArgb == _backgroundRunArgb) return;

    _flushBackgroundRun(_column);

    _backgroundRunArgb = _backgroundArgb;
    _backgroundStart = _column;
  }

  TextStyle _textStyle() {
    final foreground = _foregroundArgb;
    final style = _style;
    final theme = _state.theme;
    final bold = style.bold;
    final italic = style.italic;
    final cached = _lastTextStyle;
    if (cached != null &&
        identical(theme, _lastTextStyleTheme) &&
        foreground == _lastTextStyleForeground &&
        bold == _lastTextStyleBold &&
        italic == _lastTextStyleItalic) {
      return cached;
    }

    final textStyle = TextStyle(
      color: Color(foreground),
      fontSize: theme.fontSize,
      fontFamily: theme.fontFamily,
      decoration: TextDecoration.none,
      fontWeight: bold ? .bold : theme.fontWeight,
      fontStyle: italic ? .italic : .normal,
      fontFamilyFallback: theme.fontFamilyFallback,
      fontFeatures: const [FontFeature.enable('liga')],
    );
    _lastTextStyleTheme = theme;
    _lastTextStyleForeground = foreground;
    _lastTextStyleBold = bold;
    _lastTextStyleItalic = italic;
    return _lastTextStyle = textStyle;
  }

  void _writeCell(CellIterator cell) {
    final span = cell.wide == .wide ? 2 : 1;
    final glyphSpan = _glyphSpan(cell, span);
    final preedit = _preeditRange;
    if (preedit != null && preedit.overlaps(_rowIndex, _column, span)) {
      _previousSymbol = false;
      _skipPreeditCell(cell, preedit, span);
      return;
    }

    final highlight = _searchHighlights.at(
      _rowIndex,
      _column,
      selected: cell.isSelected,
    );
    final linkStyle = _linkStyle();
    final backgroundArgb = cell.hasText ? null : cell.backgroundArgb;
    if (cell.styleId != _prevStyleId ||
        backgroundArgb != _prevBackgroundArgb ||
        highlight != _prevHighlight ||
        linkStyle != _prevLinkStyle) {
      _flushForeground();
      _resolveStyle(
        cell,
        backgroundArgb: backgroundArgb,
        highlight: highlight,
        linkStyle: linkStyle,
      );
    }
    _syncBackgroundRun();

    if (!_hidden) {
      _emitForeground(cell, span: span, glyphSpan: glyphSpan);
      if (_hasDecoration) {
        _emitDecorations(span);
      }
    } else {
      _flushForeground();
      _previousSymbol = false;
    }

    if (span == 2) {
      _closeBackgroundSpan(span);
      cell.next();
    }
    _column += span;
    _x += _metrics.cellWidth * span;
  }
}

/// Cell coverage precomputed when a search snapshot changes.
final class _SearchHighlights {
  var _cells = Uint8List(0);
  var _active = false;
  var _cols = 0;
  var _rows = 0;
  var _viewportOffset = 0;

  _CellHighlight at(int row, int col, {required bool selected}) {
    if (!_active) return selected ? .selection : .none;
    if (row < 0 || row >= _rows || col < 0 || col >= _cols) {
      return selected ? .selection : .none;
    }
    return switch (_cells[row * _cols + col]) {
      2 => .selectedSearchMatch,
      1 when !selected => .searchMatch,
      _ when selected => .selection,
      _ => .none,
    };
  }

  void update(
    List<Selection> matches,
    Selection? selected, {
    required int rows,
    required int cols,
    required int viewportOffset,
    required RowDirtyTracker dirtyRows,
  }) {
    for (var index = 0; index < _cells.length; index++) {
      if (_cells[index] != 0 && _cols > 0) {
        dirtyRows.markRow(index ~/ _cols);
      }
    }
    _rows = rows;
    _cols = cols;
    _viewportOffset = viewportOffset;
    _active = matches.isNotEmpty || selected != null;

    final length = rows * cols;
    if (_cells.length != length) {
      _cells = Uint8List(length);
    } else {
      _cells.fillRange(0, length, 0);
    }
    if (!_active) return;

    for (final match in matches) {
      _mark(match, 1, dirtyRows);
    }
    // The selected match overwrites ordinary matches at overlapping cells.
    if (selected != null) _mark(selected, 2, dirtyRows);
  }

  void _mark(Selection selection, int value, RowDirtyTracker dirtyRows) {
    final range = ViewportSelection.resolve(
      selection,
      rows: _rows,
      cols: _cols,
      viewportOffset: _viewportOffset,
    );
    if (range == null) return;
    for (var row = range.firstRow; row <= range.lastRow; row++) {
      final offset = row * _cols;
      _cells.fillRange(
        offset + range.startColumn(row),
        offset + range.endColumn(row),
        value,
      );
      dirtyRows.markRow(row);
    }
  }
}
