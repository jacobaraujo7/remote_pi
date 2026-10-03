part of 'frame_builder.dart';

typedef _CursorCell = ({String content, Style style, bool wide});

/// Resolves cursor paint state from copied frame data.
final class _CursorFrameBuilder {
  final PaintState _state;
  final CellContentResolver _content;
  _CursorCell? _lastCell;

  _CursorFrameBuilder(this._state, this._content);

  void refreshGlyph() {
    final cell = _lastCell;
    final entry = _resolveGlyph();
    _state.cursorAtlasEntry = entry;
    if (entry == null || cell == null) return;

    // The character under a block cursor paints in CursorTheme.text (or the
    // terminal background when unset) so it contrasts with the cursor fill.
    final (cellFg, cellBg) = _resolveCellColors(cell);
    final glyphColor =
        _state.theme.cursor.text?.resolve(
          cellForeground: cellFg,
          cellBackground: cellBg,
        ) ??
        Color(_state.terminalBackgroundArgb);
    _state.cursorGlyphPaint.colorFilter = ColorFilter.mode(
      glyphColor,
      BlendMode.modulate,
    );
  }

  void sync(
    RenderStateCursor cursor, {
    required _CursorCell? cell,
    RgbColor? color,
  }) {
    _lastCell = cell;
    _state.cursor = cell == null ? cursor.copyWith(visible: false) : cursor;
    _state.cursorWide = cell?.wide ?? false;
    if (cell == null) {
      _state.cursorAtlasEntry = null;
      return;
    }
    _resolveFillColor(color, cell);
    refreshGlyph();
  }

  (Color, Color) _resolveCellColors(_CursorCell cell) {
    final (fg, bg) = _resolveStyleColors(_state, cell.style);
    return (Color(fg), Color(bg));
  }

  // An OSC 12 color reported by libghostty overrides the theme cursor color.
  void _resolveFillColor(RgbColor? osc, _CursorCell cell) {
    if (osc != null) {
      _state.cursorColorArgb = osc.toArgb32;
      return;
    }
    final themeCursor = _state.theme.cursor.color;
    if (themeCursor == null) {
      _state.cursorColorArgb = _state.terminalForegroundArgb;
      return;
    }
    final (cellFg, cellBg) = _resolveCellColors(cell);
    _state.cursorColorArgb = themeCursor
        .resolve(cellForeground: cellFg, cellBackground: cellBg)
        .toARGB32();
  }

  AtlasEntry? _resolveGlyph() {
    final cell = _lastCell;
    if (cell == null ||
        !_state.cursorFocused ||
        _state.cursor.visualStyle != CursorShape.block) {
      return null;
    }
    final style = cell.style;
    if (cell.content.isEmpty ||
        style.invisible ||
        (style.blink && !_state.blinkVisible)) {
      return null;
    }

    final runes = cell.content.runes;
    return _content.resolve(
      content: cell.content,
      codepoint: runes.first,
      graphemeLength: runes.length,
      style: style,
      span: cell.wide ? 2 : 1,
    );
  }
}
