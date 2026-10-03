import 'dart:ui';

import 'package:flutter/widgets.dart' show TextSelectionHandleType;
import 'package:libghostty/libghostty.dart'
    show Position, Selection, SelectionOrder;
import 'package:meta/meta.dart';

import '../foundation/cell_metrics.dart';
import 'selection_session.dart';

final class SelectionHandleGeometry {
  const SelectionHandleGeometry._();

  static ({SelectionHandleLayout? start, SelectionHandleLayout? end}) layout(
    Selection selection,
    CellMetrics metrics,
  ) {
    final start = selection.start.positionIn(.viewport);
    final end = selection.end.positionIn(.viewport);
    final startLeading = switch (selection.order) {
      SelectionOrder.forward || SelectionOrder.mirroredReverse => true,
      SelectionOrder.reverse || SelectionOrder.mirroredForward => false,
    };
    return (
      start: start == null
          ? null
          : _endpoint(.start, start, leading: startLeading, metrics: metrics),
      end: end == null
          ? null
          : _endpoint(.end, end, leading: !startLeading, metrics: metrics),
    );
  }

  static Position positionForDrag({
    required Offset anchor,
    required bool leading,
    required CellMetrics metrics,
    required int columns,
    required int rows,
  }) {
    if (columns <= 0 || rows <= 0) return const Position(row: 0, col: 0);
    final row = metrics.cellHeight <= 0
        ? 0
        : ((anchor.dy / metrics.cellHeight).ceil() - 1).clamp(0, rows - 1);
    final rawColumn = metrics.cellWidth <= 0
        ? 0
        : leading
        ? (anchor.dx / metrics.cellWidth).floor()
        : (anchor.dx / metrics.cellWidth).ceil() - 1;
    return Position(row: row, col: rawColumn.clamp(0, columns - 1));
  }

  static SelectionHandleLayout _endpoint(
    SelectionEndpoint endpoint,
    Position position, {
    required bool leading,
    required CellMetrics metrics,
  }) {
    return SelectionHandleLayout(
      endpoint: endpoint,
      leading: leading,
      position: position,
      type: leading ? .left : .right,
      anchor: Offset(
        (position.col + (leading ? 0 : 1)) * metrics.cellWidth,
        (position.row + 1) * metrics.cellHeight,
      ),
    );
  }
}

@immutable
final class SelectionHandleLayout {
  final bool leading;
  final Offset anchor;
  final Position position;
  final SelectionEndpoint endpoint;
  final TextSelectionHandleType type;

  const SelectionHandleLayout({
    required this.anchor,
    required this.leading,
    required this.endpoint,
    required this.position,
    required this.type,
  });
}
