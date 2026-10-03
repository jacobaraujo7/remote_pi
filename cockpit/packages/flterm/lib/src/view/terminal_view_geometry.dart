part of 'terminal_view.dart';

/// Builds content layered over the complete [TerminalView] surface.
///
/// The builder is laid out over [TerminalViewGeometry.surfaceBounds] and
/// receives geometry in that local coordinate system. The application owns
/// the returned widget's layout, hit testing, semantics, and visual design.
typedef TerminalOverlayBuilder =
    Widget Function(BuildContext context, TerminalViewGeometry geometry);

/// Converts terminal cells and selections to [TerminalView] coordinates.
///
/// All rectangles use logical pixels with the top-left of the complete view
/// as their origin, including terminal padding. Geometry is a build-time
/// snapshot; use the latest value supplied to [TerminalOverlayBuilder] after
/// the view changes size, padding, font metrics, or viewport position.
///
/// ```dart
/// final match = controller.search.selectedMatch;
/// final rects = match == null
///     ? const <Rect>[]
///     : geometry.selectionRects(match);
/// ```
@immutable
final class TerminalViewGeometry {
  /// Bounds of the complete terminal view in overlay coordinates.
  final Rect surfaceBounds;

  /// Bounds occupied by whole terminal cells in overlay coordinates.
  ///
  /// This excludes terminal padding and any remaining space smaller than a
  /// complete cell.
  final Rect gridBounds;

  final CellMetrics _metrics;
  final int _cols;
  final int _rows;
  final int _viewportOffset;

  TerminalViewGeometry._({
    required Size surfaceSize,
    required EdgeInsets padding,
    required this._metrics,
    required this._cols,
    required this._rows,
    required this._viewportOffset,
  }) : surfaceBounds = Offset.zero & surfaceSize,
       gridBounds =
           padding.topLeft &
           Size(_cols * _metrics.cellWidth, _rows * _metrics.cellHeight);

  factory TerminalViewGeometry._fromConstraints({
    required EdgeInsets padding,
    required int viewportOffset,
    required CellMetrics metrics,
    required BoxConstraints constraints,
    required SurfaceGeometry? committed,
  }) {
    final width = constraints.hasBoundedWidth ? constraints.maxWidth : 0.0;
    final height = constraints.hasBoundedHeight ? constraints.maxHeight : 0.0;
    final gridWidth = (width - padding.horizontal).clamp(0.0, width);
    final gridHeight = (height - padding.vertical).clamp(0.0, height);
    final (cols, rows) = committed == null
        ? metrics.gridSize(gridWidth, gridHeight)
        : (committed.cols, committed.rows);
    return TerminalViewGeometry._(
      surfaceSize: Size(width, height),
      padding: padding,
      metrics: metrics,
      cols: cols,
      rows: rows,
      viewportOffset: viewportOffset,
    );
  }

  /// Returns the visible cell containing [offset], or null outside the grid.
  ///
  /// [offset] uses the overlay coordinate system, including terminal padding.
  ///
  /// ```dart
  /// final position = geometry.cellAt(pointerEvent.localPosition);
  /// if (position != null) {
  ///   showCellMenu(position);
  /// }
  /// ```
  Position? cellAt(Offset offset) {
    if (!gridBounds.contains(offset)) return null;
    final position = _metrics.cellAt(offset - gridBounds.topLeft);
    return _contains(position) ? position : null;
  }

  /// Returns the rectangle of a visible viewport [position], or null.
  ///
  /// ```dart
  /// final rect = geometry.cellRect(const Position(row: 2, col: 4));
  /// if (rect != null) {
  ///   showMarker(rect.center);
  /// }
  /// ```
  Rect? cellRect(Position position) {
    if (!_contains(position)) return null;
    return _metrics.cellRect(position, gridBounds.topLeft);
  }

  /// Returns the visible rectangle for [ref], or null when it is off-screen.
  ///
  /// Grid references are short-lived libghostty snapshots and must be
  /// converted before the terminal mutates.
  ///
  /// ```dart
  /// final match = controller.search.selectedMatch;
  /// final rect = match == null ? null : geometry.gridRefRect(match.start);
  /// if (rect != null) avoidOverlayRect(rect);
  /// ```
  Rect? gridRefRect(GridRef ref) {
    final position = ViewportSelection.positionOf(ref, _viewportOffset);
    return position == null ? null : cellRect(position);
  }

  /// Returns visible rectangles covering [selection].
  ///
  /// Multi-row contiguous selections produce one rectangle per visible row.
  /// Rectangular and reversed selections are normalized. A selection outside
  /// the visible rows returns an empty list. As with other [Selection]
  /// operations, the snapshot must not have been invalidated by a terminal
  /// mutation.
  ///
  /// ```dart
  /// return Stack(
  ///   children: [
  ///     for (final rect in geometry.selectionRects(match))
  ///       Positioned.fromRect(rect: rect, child: const SearchMarker()),
  ///   ],
  /// );
  /// ```
  List<Rect> selectionRects(Selection selection) {
    final range = ViewportSelection.resolve(
      selection,
      rows: _rows,
      cols: _cols,
      viewportOffset: _viewportOffset,
    );
    if (range == null) return const [];
    return [
      for (var row = range.firstRow; row <= range.lastRow; row++)
        ?_rowRect(row, range.startColumn(row), range.endColumn(row)),
    ];
  }

  bool _contains(Position position) {
    return position.row >= 0 &&
        position.row < _rows &&
        position.col >= 0 &&
        position.col < _cols;
  }

  Rect? _rowRect(int row, int startCol, int endCol) {
    if (startCol >= endCol) return null;
    return _metrics.cellRangeRect(row, startCol, endCol, gridBounds.topLeft);
  }
}
