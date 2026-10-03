part of 'frame_builder.dart';

final class _PreeditCluster {
  final String text;
  final int firstCodepoint;
  final int graphemeLength;
  final int span;

  const _PreeditCluster({
    required this.text,
    required this.firstCodepoint,
    required this.graphemeLength,
    required this.span,
  });
}

/// Cell-based terminal range temporarily replaced by visible preedit text.
///
/// [startCol] and [endCol] are terminal columns. [clusterOffset] points at
/// the first visible grapheme cluster when overflow clips the preedit from
/// the left.
final class _PreeditRange {
  final int row;
  final int startCol;
  final int endCol;
  final int clusterOffset;
  final List<_PreeditCluster> clusters;

  const _PreeditRange({
    required this.row,
    required this.startCol,
    required this.endCol,
    required this.clusterOffset,
    required this.clusters,
  });

  bool overlaps(int row, int col, int span) {
    final cellEndCol = col + span;
    return row == this.row && col < endCol && cellEndCol > startCol;
  }

  bool sameGeometry(_PreeditRange? other) {
    return other != null &&
        row == other.row &&
        startCol == other.startCol &&
        endCol == other.endCol &&
        clusterOffset == other.clusterOffset;
  }

  static _PreeditRange? resolve({
    required _PreeditText preedit,
    required RenderStateCursor cursor,
    required int rows,
    required int cols,
  }) {
    if (!cursor.viewportHasValue ||
        !cursor.visible ||
        cursor.viewportY < 0 ||
        cursor.viewportY >= rows ||
        cursor.viewportX < 0 ||
        cursor.viewportX >= cols ||
        rows <= 0 ||
        cols <= 0) {
      return null;
    }

    if (preedit.isEmpty) return null;

    final startCol = preedit.startCol(cursor.viewportX, cols);
    final visible = preedit.visibleSuffix(cols - startCol);
    final visibleWidth = visible.width;
    final endCol = startCol + visibleWidth;
    if (startCol >= endCol) return null;

    return _PreeditRange(
      row: cursor.viewportY,
      startCol: startCol,
      endCol: endCol,
      clusterOffset: visible.clusterOffset,
      clusters: preedit.clusters,
    );
  }
}

/// Preedit text split into terminal-cell spans.
///
/// Rendering uses libghostty's grapheme-cluster spans instead of paragraph
/// widths so preedit text replaces exactly the terminal cells it occupies.
final class _PreeditText {
  final String text;
  final List<_PreeditCluster> clusters;
  final int cellWidth;

  const _PreeditText(this.text, this.clusters, this.cellWidth);

  const _PreeditText.empty() : text = '', clusters = const [], cellWidth = 0;

  factory _PreeditText.parse(String text) {
    if (text.isEmpty) return const _PreeditText.empty();

    final codepoints = text.runes.toList(growable: false);
    final clusters = <_PreeditCluster>[];
    var cellWidth = 0;
    var index = 0;
    while (index < codepoints.length) {
      final result = unicodeGraphemeWidth(codepoints.sublist(index));
      final end = math.min(index + result.consumed, codepoints.length);
      if (end <= index) break;

      final span = result.width;
      if (span > 0) {
        cellWidth += span;
        clusters.add(
          _PreeditCluster(
            text: String.fromCharCodes(codepoints, index, end),
            firstCodepoint: codepoints[index],
            graphemeLength: end - index,
            span: span,
          ),
        );
      }
      index = end;
    }

    return _PreeditText(text, clusters, cellWidth);
  }

  bool get isEmpty => clusters.isEmpty;

  int startCol(int cursorCol, int cols) {
    final rightWidth = cols - cursorCol;
    return cellWidth <= rightWidth
        ? cursorCol
        : math.max(0, cursorCol - (cellWidth - rightWidth));
  }

  ({int clusterOffset, int width}) visibleSuffix(int maxWidth) {
    var clusterOffset = clusters.length;
    var width = 0;
    for (var i = clusters.length - 1; i >= 0; i--) {
      final nextWidth = width + clusters[i].span;
      if (nextWidth > maxWidth) break;
      width = nextWidth;
      clusterOffset = i;
    }
    return (clusterOffset: clusterOffset, width: width);
  }
}
