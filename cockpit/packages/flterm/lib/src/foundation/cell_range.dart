import 'package:flutter/foundation.dart' show immutable;
import 'package:libghostty/libghostty.dart' show PointTag, Position;

/// Inclusive range of terminal cells in one coordinate space.
///
/// ```dart
/// final range = CellRange(
///   start: const Position(row: 2, col: 4),
///   end: const Position(row: 2, col: 12),
/// );
///
/// final inside = range.contains(const Position(row: 2, col: 8));
/// ```
@immutable
final class CellRange {
  /// First cell in the range.
  final Position start;

  /// Last cell in the range.
  final Position end;

  /// Coordinate space used by [start] and [end].
  final PointTag pointTag;

  const CellRange({
    required this.start,
    required this.end,
    this.pointTag = .viewport,
  });

  @override
  int get hashCode => Object.hash(start, end, pointTag);

  /// Whether [start] and [end] are on the same terminal row.
  bool get isSingleRow => start.row == end.row;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is CellRange &&
          start == other.start &&
          end == other.end &&
          pointTag == other.pointTag;

  /// Whether [position] is inside this inclusive range.
  bool contains(Position position) {
    return start.compareTo(position) <= 0 && position.compareTo(end) <= 0;
  }

  /// Whether this range intersects [other].
  bool overlaps(CellRange other) {
    if (pointTag != other.pointTag) return false;
    if (start.compareTo(end) > 0 || other.start.compareTo(other.end) > 0) {
      return false;
    }
    return start.compareTo(other.end) <= 0 && other.start.compareTo(end) <= 0;
  }
}

extension on Position {
  int compareTo(Position other) {
    final byRow = row.compareTo(other.row);
    return byRow != 0 ? byRow : col.compareTo(other.col);
  }
}
