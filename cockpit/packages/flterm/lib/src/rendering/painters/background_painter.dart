import 'dart:ui';

import 'package:flutter/painting.dart';

import '../atlas/sprite_buffer.dart';
import '../paint_state.dart';

/// Paints the terminal background layer.
///
/// At full opacity, fills the grid with the opaque terminal background
/// color and then draws per-cell explicit background rects on top via a
/// batched [Canvas.drawVertices] call.
///
/// When [PaintState.backgroundOpacity] is less than 1.0, skips
/// the grid fill so the backdrop behind the repaint boundary layer
/// shows through on default background cells; filling here would
/// composite twice against that backdrop. Per-cell explicit background
/// rects still render on top, with alpha scaled by the frame builder when
/// [PaintState.backgroundOpacityCells] is true.
class BackgroundPainter {
  final Paint _fillPaint;
  final Paint _vertexPaint;
  final SpriteBuffer _sprites;
  final PaintState _state;

  BackgroundPainter(this._state, this._sprites)
    : _fillPaint = Paint(),
      _vertexPaint = Paint();

  void paint(Canvas canvas) {
    if (_state.theme.backgroundOpacity >= 1.0) {
      _fillPaint.color = Color(_state.terminalBackgroundArgb);
      canvas.drawRect(
        .fromLTWH(
          0,
          0,
          _state.cols * _state.metrics.cellWidth,
          _state.rows * _state.metrics.cellHeight,
        ),
        _fillPaint,
      );
    }

    for (final vertices in _sprites.backgroundVertices) {
      canvas.drawVertices(vertices, BlendMode.srcOver, _vertexPaint);
    }
  }
}
