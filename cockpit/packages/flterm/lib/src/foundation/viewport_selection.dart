import 'package:flutter/foundation.dart' show immutable, internal;
import 'package:libghostty/libghostty.dart' show GridRef, Position, Selection;

/// Projects a selection into clipped viewport rows and exclusive column ends.
@internal
@immutable
final class ViewportSelection {
  final int firstRow;
  final int lastRow;
  final int _firstStart;
  final int _lastEnd;
  final int _middleStart;
  final int _middleEnd;

  const ViewportSelection._(
    this.firstRow,
    this.lastRow,
    this._firstStart,
    this._lastEnd,
    this._middleStart,
    this._middleEnd,
  );

  int endColumn(int row) => row == lastRow ? _lastEnd : _middleEnd;

  int startColumn(int row) => row == firstRow ? _firstStart : _middleStart;

  static Position? positionOf(GridRef ref, int viewportOffset) {
    final viewport = ref.positionIn(.viewport);
    if (viewport != null) return viewport;
    final screen = ref.positionIn(.screen);
    if (screen == null) return null;
    return Position(row: screen.row - viewportOffset, col: screen.col);
  }

  static ViewportSelection? resolve(
    Selection selection, {
    required int rows,
    required int cols,
    required int viewportOffset,
  }) {
    var start = positionOf(selection.start, viewportOffset);
    var end = positionOf(selection.end, viewportOffset);
    if (start == null || end == null || rows == 0 || cols == 0) return null;
    if (start.row > end.row || (start.row == end.row && start.col > end.col)) {
      (start, end) = (end, start);
    }

    if (end.row < 0 || start.row >= rows) return null;
    final firstRow = start.row.clamp(0, rows - 1);
    final lastRow = end.row.clamp(0, rows - 1);
    if (selection.rectangle) {
      final firstCol = (start.col < end.col ? start.col : end.col).clamp(
        0,
        cols,
      );
      final endCol = ((start.col > end.col ? start.col : end.col) + 1).clamp(
        0,
        cols,
      );
      return ViewportSelection._(
        firstRow,
        lastRow,
        firstCol,
        endCol,
        firstCol,
        endCol,
      );
    }
    return ViewportSelection._(
      firstRow,
      lastRow,
      firstRow == start.row ? start.col.clamp(0, cols) : 0,
      lastRow == end.row ? (end.col + 1).clamp(0, cols) : cols,
      0,
      cols,
    );
  }
}
