import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

/// Identificador de coluna no overview à direita do editor.
///
/// Ordem visual: da **esquerda → direita** na strip; a coluna mais à direita
/// fica sob a [Scrollbar] vertical. Hoje só [git]; [diagnostics] entra depois.
enum OverviewRulerLane { git, diagnostics }

/// Marca proporcional ao documento (linhas base 1, ou fronteira `0..lineCount`).
@immutable
class OverviewRulerMark {
  const OverviewRulerMark.range({
    required this.startLine,
    required this.endLine,
    required this.color,
  }) : isBoundary = false;

  const OverviewRulerMark.boundary({required int boundary, required this.color})
    : startLine = boundary,
      endLine = boundary,
      isBoundary = true;

  /// Linha base 1 (range) ou índice de fronteira `0..lineCount` (boundary).
  final int startLine;
  final int endLine;
  final Color color;
  final bool isBoundary;
}

/// Uma coluna do overview (git, diagnostics, …).
@immutable
class OverviewRulerColumn {
  const OverviewRulerColumn({
    required this.lane,
    required this.width,
    required this.marks,
  });

  final OverviewRulerLane lane;
  final double width;
  final List<OverviewRulerMark> marks;

  bool get isEmpty => marks.isEmpty;
}

/// Strip multi-coluna sob a scrollbar vertical.
///
/// A [Scrollbar] do editor envolve este widget e pinta o thumb **por cima**.
class EditorOverviewRuler extends StatelessWidget {
  const EditorOverviewRuler({
    super.key,
    required this.columns,
    required this.lineCount,
    this.onJumpToLine,
  });

  /// Colunas da esquerda → direita (direita = sob a scrollbar).
  final List<OverviewRulerColumn> columns;
  final int lineCount;
  final ValueChanged<int>? onJumpToLine;

  double get totalWidth => columns.fold<double>(0, (sum, c) => sum + c.width);

  @override
  Widget build(BuildContext context) {
    final visible = [
      for (final c in columns)
        if (!c.isEmpty) c,
    ];
    if (lineCount <= 0 || visible.isEmpty) return const SizedBox.shrink();

    final width = visible.fold<double>(0, (sum, c) => sum + c.width);
    return LayoutBuilder(
      builder: (context, constraints) {
        final height = constraints.maxHeight;
        if (height <= 0) return const SizedBox.shrink();
        final child = CustomPaint(
          size: Size(width, height),
          painter: _OverviewRulerPainter(
            columns: visible,
            lineCount: lineCount,
          ),
        );
        final jump = onJumpToLine;
        if (jump == null) return child;
        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapDown: (details) {
            jump(
              overviewRulerLineForDy(
                dy: details.localPosition.dy,
                height: height,
                lineCount: lineCount,
              ),
            );
          },
          child: child,
        );
      },
    );
  }
}

/// Mapeia Y na faixa do overview → linha base 1.
@visibleForTesting
int overviewRulerLineForDy({
  required double dy,
  required double height,
  required int lineCount,
}) {
  if (height <= 0 || lineCount <= 0) return 1;
  final ratio = (dy / height).clamp(0.0, 1.0);
  return ((ratio * lineCount).floor() + 1).clamp(1, lineCount);
}

/// @nodoc — alias mantido pros testes existentes.
@visibleForTesting
int scmOverviewLineForDy({
  required double dy,
  required double height,
  required int lineCount,
}) => overviewRulerLineForDy(dy: dy, height: height, lineCount: lineCount);

class _OverviewRulerPainter extends CustomPainter {
  _OverviewRulerPainter({required this.columns, required this.lineCount});

  final List<OverviewRulerColumn> columns;
  final int lineCount;

  static const double _minTick = 1.5;

  @override
  void paint(Canvas canvas, Size size) {
    if (lineCount <= 0 || size.height <= 0) return;
    final paint = Paint()..style = PaintingStyle.fill;
    var x = 0.0;
    for (final column in columns) {
      final w = column.width;
      for (final mark in column.marks) {
        paint.color = mark.color;
        if (mark.isBoundary) {
          final y = (mark.startLine / lineCount) * size.height;
          final top = (y - _minTick / 2).clamp(0.0, size.height - _minTick);
          canvas.drawRect(Rect.fromLTWH(x, top, w, _minTick), paint);
        } else {
          final top = ((mark.startLine - 1) / lineCount) * size.height;
          final bottom = (mark.endLine / lineCount) * size.height;
          final h = (bottom - top).clamp(_minTick, size.height);
          canvas.drawRect(Rect.fromLTWH(x, top, w, h), paint);
        }
      }
      x += w;
    }
  }

  @override
  bool shouldRepaint(covariant _OverviewRulerPainter old) =>
      old.lineCount != lineCount || !_sameColumns(old.columns, columns);

  static bool _sameColumns(
    List<OverviewRulerColumn> a,
    List<OverviewRulerColumn> b,
  ) {
    if (identical(a, b)) return true;
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i].lane != b[i].lane ||
          a[i].width != b[i].width ||
          a[i].marks.length != b[i].marks.length) {
        return false;
      }
      for (var j = 0; j < a[i].marks.length; j++) {
        final m = a[i].marks[j];
        final n = b[i].marks[j];
        if (m.startLine != n.startLine ||
            m.endLine != n.endLine ||
            m.color != n.color ||
            m.isBoundary != n.isBoundary) {
          return false;
        }
      }
    }
    return true;
  }
}

/// Une linhas consecutivas (base 1) em intervalos inclusivos `(start, end)`.
@visibleForTesting
Iterable<(int, int)> overviewMergedLineRanges(Set<int> lines) sync* {
  if (lines.isEmpty) return;
  final sorted = lines.toList()..sort();
  var start = sorted.first;
  var prev = sorted.first;
  for (var i = 1; i < sorted.length; i++) {
    final line = sorted[i];
    if (line == prev + 1) {
      prev = line;
      continue;
    }
    yield (start, prev);
    start = line;
    prev = line;
  }
  yield (start, prev);
}

/// Largura da coluna Git (fina; a scrollbar cobre visualmente).
const double kOverviewGitColumnWidth = 2;
