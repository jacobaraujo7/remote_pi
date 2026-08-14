import 'dart:math' as math;

import 'package:flutter/material.dart'
    show ScrollbarTheme, TargetPlatform, Theme;
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
/// O eixo Y usa as extensões efetivas do mesmo scroll que alimenta a
/// [Scrollbar], evitando estimar a geometria a partir do tamanho do widget.
class EditorOverviewRuler extends StatelessWidget {
  const EditorOverviewRuler({
    super.key,
    required this.columns,
    required this.lineCount,
    required this.lineHeight,
    this.contentPaddingBottom = 0,
    this.scrollContentExtent,
    this.scrollViewportExtent,
    this.onJumpToLine,
  });

  /// Colunas da esquerda → direita (direita = sob a scrollbar).
  final List<OverviewRulerColumn> columns;
  final int lineCount;
  final double lineHeight;

  /// Folga no fim do conteúdo scrollável (ex.: acima da scrollbar horizontal).
  /// Usada apenas como fallback antes de o scroll publicar suas métricas.
  final double contentPaddingBottom;

  /// Extensões efetivas publicadas pelo [ScrollPosition] da barra vertical.
  ///
  /// A Scrollbar usa `viewportDimension` como comprimento físico da trilha e
  /// `maxScrollExtent - minScrollExtent + viewportDimension` como extensão
  /// total do conteúdo. O overview precisa usar exatamente os mesmos valores.
  final double? scrollContentExtent;
  final double? scrollViewportExtent;
  final ValueChanged<int>? onJumpToLine;

  double get totalWidth => columns.fold<double>(0, (sum, c) => sum + c.width);

  @override
  Widget build(BuildContext context) {
    final visible = [
      for (final c in columns)
        if (!c.isEmpty) c,
    ];
    if (lineCount <= 0 || lineHeight <= 0 || visible.isEmpty) {
      return const SizedBox.shrink();
    }

    final width = visible.fold<double>(0, (sum, c) => sum + c.width);
    return LayoutBuilder(
      builder: (context, constraints) {
        final widgetHeight = constraints.maxHeight;
        if (widgetHeight <= 0) return const SizedBox.shrink();
        final contentExtent =
            scrollContentExtent ??
            overviewContentHeight(
              lineCount: lineCount,
              lineHeight: lineHeight,
              contentPaddingBottom: contentPaddingBottom,
            );
        // Material Scrollbar aplica o padding do MediaQuery à trilha e usa o
        // viewport do ScrollPosition (não a altura do widget que a envolve).
        final trackPadding = MediaQuery.paddingOf(context);
        final viewportExtent = scrollViewportExtent ?? widgetHeight;
        final trackHeight = (viewportExtent - trackPadding.vertical).clamp(
          0.0,
          double.infinity,
        );
        if (contentExtent <= 0 || trackHeight <= 0) {
          return const SizedBox.shrink();
        }
        final platform = Theme.of(context).platform;
        final scrollbarTheme = ScrollbarTheme.of(context);
        final mainAxisMargin = platform == TargetPlatform.iOS
            ? 3.0
            : scrollbarTheme.mainAxisMargin ?? 0.0;
        final minThumbExtent = platform == TargetPlatform.iOS
            ? 36.0
            : scrollbarTheme.minThumbLength ?? 48.0;
        final traversableTrackExtent = (trackHeight - 2 * mainAxisMargin).clamp(
          0.0,
          double.infinity,
        );
        final geometry = OverviewRulerGeometry(
          contentExtent: contentExtent,
          viewportExtent: viewportExtent,
          trackStart: trackPadding.top + mainAxisMargin,
          trackExtent: traversableTrackExtent,
          thumbExtent: overviewScrollbarThumbExtent(
            contentExtent: contentExtent,
            viewportExtent: viewportExtent,
            trackPaddingExtent: trackPadding.vertical,
            traversableTrackExtent: traversableTrackExtent,
            minThumbExtent: minThumbExtent,
          ),
        );
        final child = CustomPaint(
          size: Size(width, widgetHeight),
          painter: _OverviewRulerPainter(
            columns: visible,
            lineCount: lineCount,
            lineHeight: lineHeight,
            geometry: geometry,
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
                trackHeight: geometry.trackExtent,
                lineCount: lineCount,
                lineHeight: lineHeight,
                contentExtent: contentExtent,
                geometry: geometry,
              ),
            );
          },
          child: child,
        );
      },
    );
  }
}

/// Altura total do conteúdo scrollável (linhas + folga inferior).
@visibleForTesting
double overviewContentHeight({
  required int lineCount,
  required double lineHeight,
  double contentPaddingBottom = 0,
}) => lineCount * lineHeight + contentPaddingBottom;

/// Offset Y no conteúdo no início da linha base 1 (ou fronteira `boundary`).
@visibleForTesting
double overviewContentOffsetForLine({
  required int line,
  required double lineHeight,
}) => (line - 1).clamp(0, 1 << 30) * lineHeight;

/// Offset Y no conteúdo para fronteira `0..lineCount`.
@visibleForTesting
double overviewContentOffsetForBoundary({
  required int boundary,
  required double lineHeight,
}) => boundary.clamp(0, 1 << 30) * lineHeight;

/// Mapeia offset de conteúdo → Y na trilha (mesma proporção da Scrollbar).
@visibleForTesting
double overviewTrackY({
  required double contentOffset,
  required double contentHeight,
  required double trackHeight,
}) {
  if (contentHeight <= 0 || trackHeight <= 0) return 0;
  return (contentOffset / contentHeight).clamp(0.0, 1.0) * trackHeight;
}

/// Extensão do thumb calculada com as mesmas regras do [ScrollbarPainter].
@visibleForTesting
double overviewScrollbarThumbExtent({
  required double contentExtent,
  required double viewportExtent,
  required double trackPaddingExtent,
  required double traversableTrackExtent,
  required double minThumbExtent,
}) {
  if (contentExtent <= 0 ||
      viewportExtent <= 0 ||
      traversableTrackExtent <= 0) {
    return 0;
  }
  final adjustedContentExtent = contentExtent - trackPaddingExtent;
  if (adjustedContentExtent <= 0) return traversableTrackExtent;
  final fractionVisible =
      ((viewportExtent - trackPaddingExtent) / adjustedContentExtent).clamp(
        0.0,
        1.0,
      );
  final naturalExtent = traversableTrackExtent * fractionVisible;
  return math
      .max(naturalExtent, math.min(minThumbExtent, traversableTrackExtent))
      .clamp(0.0, traversableTrackExtent);
}

/// Transformação entre offsets do documento e coordenadas da scrollbar.
///
/// Quando o Flutter limita o thumb a um tamanho mínimo, uma regra proporcional
/// simples deixa de coincidir com sua posição. Esta geometria preserva a
/// posição relativa dentro do thumb: uma linha centralizada no viewport fica
/// exatamente no centro do thumb, inclusive em arquivos muito longos.
@immutable
class OverviewRulerGeometry {
  const OverviewRulerGeometry({
    required this.contentExtent,
    required this.viewportExtent,
    required this.trackStart,
    required this.trackExtent,
    required this.thumbExtent,
  });

  final double contentExtent;
  final double viewportExtent;
  final double trackStart;
  final double trackExtent;
  final double thumbExtent;

  double get trackEnd => trackStart + trackExtent;

  double contentToTrack(double contentOffset) {
    if (contentExtent <= 0 || trackExtent <= 0) return trackStart;
    final offset = contentOffset.clamp(0.0, contentExtent);
    if (contentExtent <= viewportExtent ||
        thumbExtent <= 0 ||
        thumbExtent >= trackExtent ||
        viewportExtent <= 0) {
      return trackStart + (offset / contentExtent) * trackExtent;
    }

    final halfViewport = viewportExtent / 2;
    final halfThumb = thumbExtent / 2;
    if (offset <= halfViewport) {
      return trackStart + (offset / viewportExtent) * thumbExtent;
    }
    if (offset >= contentExtent - halfViewport) {
      return trackEnd -
          ((contentExtent - offset) / viewportExtent) * thumbExtent;
    }

    final scrollableExtent = contentExtent - viewportExtent;
    final thumbTravel = trackExtent - thumbExtent;
    return trackStart +
        halfThumb +
        ((offset - halfViewport) / scrollableExtent) * thumbTravel;
  }

  double trackToContent(double dy) {
    if (contentExtent <= 0 || trackExtent <= 0) return 0;
    final local = (dy - trackStart).clamp(0.0, trackExtent);
    if (contentExtent <= viewportExtent ||
        thumbExtent <= 0 ||
        thumbExtent >= trackExtent ||
        viewportExtent <= 0) {
      return (local / trackExtent) * contentExtent;
    }

    final halfViewport = viewportExtent / 2;
    final halfThumb = thumbExtent / 2;
    if (local <= halfThumb) {
      return (local / thumbExtent) * viewportExtent;
    }
    if (local >= trackExtent - halfThumb) {
      return contentExtent -
          ((trackExtent - local) / thumbExtent) * viewportExtent;
    }

    final scrollableExtent = contentExtent - viewportExtent;
    final thumbTravel = trackExtent - thumbExtent;
    return halfViewport +
        ((local - halfThumb) / thumbTravel) * scrollableExtent;
  }

  @override
  bool operator ==(Object other) =>
      other is OverviewRulerGeometry &&
      other.contentExtent == contentExtent &&
      other.viewportExtent == viewportExtent &&
      other.trackStart == trackStart &&
      other.trackExtent == trackExtent &&
      other.thumbExtent == thumbExtent;

  @override
  int get hashCode => Object.hash(
    contentExtent,
    viewportExtent,
    trackStart,
    trackExtent,
    thumbExtent,
  );
}

/// Mapeia Y na faixa do overview → linha base 1 (inverso do paint).
@visibleForTesting
int overviewRulerLineForDy({
  required double dy,
  double trackTop = 0,
  required double trackHeight,
  required int lineCount,
  required double lineHeight,
  double contentPaddingBottom = 0,
  double? contentExtent,
  OverviewRulerGeometry? geometry,
}) {
  if (trackHeight <= 0 || lineCount <= 0 || lineHeight <= 0) return 1;
  final contentHeight =
      contentExtent ??
      overviewContentHeight(
        lineCount: lineCount,
        lineHeight: lineHeight,
        contentPaddingBottom: contentPaddingBottom,
      );
  final contentY =
      geometry?.trackToContent(dy) ??
      ((dy - trackTop) / trackHeight).clamp(0.0, 1.0) * contentHeight;
  final line = (contentY / lineHeight).floor() + 1;
  return line.clamp(1, lineCount);
}

/// @nodoc — alias dos testes antigos (proporção simples sem padding).
@visibleForTesting
int scmOverviewLineForDy({
  required double dy,
  required double height,
  required int lineCount,
}) => overviewRulerLineForDy(
  dy: dy,
  trackHeight: height,
  lineCount: lineCount,
  lineHeight: 1,
  contentPaddingBottom: 0,
);

class _OverviewRulerPainter extends CustomPainter {
  _OverviewRulerPainter({
    required this.columns,
    required this.lineCount,
    required this.lineHeight,
    required this.geometry,
  });

  final List<OverviewRulerColumn> columns;
  final int lineCount;
  final double lineHeight;
  final OverviewRulerGeometry geometry;

  static const double _minTick = 1.5;

  @override
  void paint(Canvas canvas, Size size) {
    if (lineCount <= 0 ||
        lineHeight <= 0 ||
        geometry.contentExtent <= 0 ||
        geometry.trackExtent <= 0 ||
        size.height <= 0) {
      return;
    }
    final paint = Paint()..style = PaintingStyle.fill;
    var x = 0.0;
    for (final column in columns) {
      final w = column.width;
      for (final mark in column.marks) {
        paint.color = mark.color;
        if (mark.isBoundary) {
          final y = geometry.contentToTrack(
            overviewContentOffsetForBoundary(
              boundary: mark.startLine,
              lineHeight: lineHeight,
            ),
          );
          final top = (y - _minTick / 2).clamp(
            geometry.trackStart,
            geometry.trackEnd - _minTick,
          );
          canvas.drawRect(Rect.fromLTWH(x, top, w, _minTick), paint);
        } else {
          final top = geometry.contentToTrack(
            overviewContentOffsetForLine(
              line: mark.startLine,
              lineHeight: lineHeight,
            ),
          );
          final bottom = geometry.contentToTrack(
            overviewContentOffsetForLine(
              line: mark.endLine + 1,
              lineHeight: lineHeight,
            ),
          );
          final h = (bottom - top).clamp(_minTick, geometry.trackExtent);
          final paintTop = top.clamp(
            geometry.trackStart,
            geometry.trackEnd - h,
          );
          canvas.drawRect(Rect.fromLTWH(x, paintTop, w, h), paint);
        }
      }
      x += w;
    }
  }

  @override
  bool shouldRepaint(covariant _OverviewRulerPainter old) =>
      old.lineCount != lineCount ||
      old.lineHeight != lineHeight ||
      old.geometry != geometry ||
      !_sameColumns(old.columns, columns);

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
