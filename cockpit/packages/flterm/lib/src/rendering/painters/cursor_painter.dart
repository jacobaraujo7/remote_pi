import 'dart:ui';

import 'package:flutter/painting.dart';
import 'package:libghostty/libghostty.dart';

import '../atlas/atlas.dart';
import '../paint_state.dart';

/// Renders the terminal cursor in block, hollow, underline, and bar shapes.
///
/// Shape rules:
/// - Focused: uses the shape reported by the terminal (block, underline, bar).
/// - Unfocused: block becomes hollow outline; other shapes draw as-is.
/// - Password input + focused: forces filled block with a centered black dot
///   (no character glyph is drawn). When unfocused, normal rules apply.
///
/// For focused block cursors (non-password), draws the character under
/// the cursor using an atlas glyph tinted with the terminal background
/// color, so the text contrasts against the cursor fill. The glyph and
/// paint are pre-resolved during state sync.
///
/// Cursor opacity from [CursorTheme.opacity] is applied when focused.
/// Unfocused cursors draw at full opacity.
class CursorPainter {
  final Paint _paint;
  final Atlas _atlas;
  final PaintState _state;

  CursorPainter(this._state, this._atlas) : _paint = Paint();

  void paint(Canvas canvas) {
    final cursor = _state.cursor;
    if (_state.preeditActive) return;
    if (!cursor.viewportHasValue ||
        !cursor.visible ||
        cursor.viewportY < 0 ||
        cursor.viewportY >= _state.rows ||
        cursor.viewportX < 0 ||
        cursor.viewportX >= _state.cols ||
        !_state.blinkVisible) {
      return;
    }

    final metrics = _state.metrics;
    final focused = _state.cursorFocused;
    final opacity = focused ? (_state.theme.cursor.opacity * 255).ceil() : 255;
    _paint.color = Color(
      (opacity << 24) | (_state.cursorColorArgb & 0x00FFFFFF),
    );

    final endCol = (cursor.viewportX + (_state.cursorWide ? 2 : 1)).clamp(
      0,
      _state.cols,
    );
    final rect = metrics.cellRangeRect(
      cursor.viewportY,
      cursor.viewportX,
      endCol,
      .zero,
    );
    final CursorShape shape = switch ((
      focused,
      cursor.passwordInput,
      cursor.visualStyle,
    )) {
      (true, true, _) => .block,
      (false, _, .block) => .blockHollow,
      _ => cursor.visualStyle,
    };

    _paint.style = PaintingStyle.fill;
    switch (shape) {
      case .block when cursor.passwordInput:
        canvas.drawRect(rect, _paint);
        _paint.color = const Color(0xFF000000);
        canvas.drawCircle(
          rect.center,
          (metrics.cellHeight * 0.15).clamp(1.5, 4.0),
          _paint,
        );
      case .block:
        canvas.drawRect(rect, _paint);
        final entry = _state.cursorAtlasEntry;
        if (entry == null) return;
        final atlasImage = _atlas.imageFor(entry);
        if (atlasImage == null) return;

        final inverseDpr = 1.0 / _atlas.devicePixelRatio;
        final (sourceBearingX, sourceBearingY) = switch (entry.lane) {
          .sprite ||
          .text => (entry.bearingX * inverseDpr, entry.bearingY * inverseDpr),
          _ => (0.0, 0.0),
        };

        canvas.drawImageRect(
          atlasImage,
          Rect.fromLTRB(
            entry.srcLeft,
            entry.srcTop,
            entry.srcRight,
            entry.srcBottom,
          ),
          Rect.fromLTWH(
            cursor.viewportX * metrics.cellWidth + sourceBearingX,
            cursor.viewportY * metrics.cellHeight + sourceBearingY,
            (entry.srcRight - entry.srcLeft) * inverseDpr,
            (entry.srcBottom - entry.srcTop) * inverseDpr,
          ),
          _state.cursorGlyphPaint,
        );

      case .blockHollow:
        _paint
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5;
        canvas.drawRect(rect, _paint);

      case .underline:
        final thickness = metrics.underlineThickness;
        final underlineY = rect.top + metrics.underlinePosition;
        canvas.drawRect(
          .fromLTWH(rect.left, underlineY, rect.width, thickness),
          _paint,
        );

      case .bar:
        final barWidth = (metrics.cellWidth / 6).clamp(1.0, 3.0);
        canvas.drawRect(
          .fromLTWH(rect.left, rect.top, barWidth, rect.height),
          _paint,
        );
    }
  }
}
