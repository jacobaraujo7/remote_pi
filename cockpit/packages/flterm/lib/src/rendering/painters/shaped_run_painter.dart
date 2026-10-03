import 'dart:ui';

import '../atlas/sprite_buffer.dart';

/// Paints paragraph-shaped text runs that need ligature shaping.
final class ShapedRunPainter {
  final ShapedRunBuffer _runs;

  const ShapedRunPainter(this._runs);

  void paint(Canvas canvas) {
    if (_runs.count == 0) return;

    for (final row in _runs.rows) {
      for (final run in row) {
        canvas.save();
        canvas.clipRect(run.clip);
        canvas.drawParagraph(run.paragraph, run.offset);
        canvas.restore();
      }
    }
  }
}
