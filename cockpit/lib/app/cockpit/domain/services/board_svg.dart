import 'dart:convert';
import 'dart:math';
import 'package:xml/xml.dart';
import '../entities/board_document.dart';

typedef BoardRoute = ({Point<double> start, Point<double> end, bool vertical});

BoardRoute boardRoute(Rectangle<double> a, Rectangle<double> b) {
  final dx = b.left + b.width / 2 - a.left - a.width / 2;
  final dy = b.top + b.height / 2 - a.top - a.height / 2;
  final vertical =
      dy.abs() - (a.height + b.height) / 2 >
          dx.abs() - (a.width + b.width) / 2 &&
      dy != 0;
  return (
    vertical: vertical,
    start: Point(
      vertical
          ? a.left + a.width / 2
          : dx < 0
          ? a.left
          : a.right,
      vertical ? (dy < 0 ? a.top : a.bottom) : a.top + a.height / 2,
    ),
    end: Point(
      vertical
          ? b.left + b.width / 2
          : dx < 0
          ? b.right
          : b.left,
      vertical ? (dy < 0 ? b.bottom : b.top) : b.top + b.height / 2,
    ),
  );
}

BoardRoute boardEdgeEndpoints(BoardDocument doc, BoardItem edge) {
  final a = doc.items[edge.from]!, b = doc.items[edge.to]!;
  return boardRoute(
    Rectangle(a.x, a.y, a.width, a.height),
    Rectangle(b.x, b.y, b.width, b.height),
  );
}

Rectangle<double> boardExportBounds(
  BoardDocument doc,
  Iterable<BoardItem> items, {
  bool includeSvgLabels = false,
  double Function(String)? measureLabel,
}) {
  Rectangle<double>? bounds;
  for (final item in items) {
    var rect = Rectangle(item.x, item.y, item.width, item.height);
    if (item.kind == BoardKind.arrow) {
      final edge = boardEdgeEndpoints(doc, item);
      rect = Rectangle.fromPoints(edge.start, edge.end);
      if (item.label.isNotEmpty) {
        rect = rect.boundingBox(
          Rectangle(
            (edge.start.x + edge.end.x) / 2 - 60,
            (edge.start.y + edge.end.y) / 2 - 17,
            120,
            34,
          ),
        );
      }
    }
    final rendersLabel =
        includeSvgLabels &&
        item.kind != BoardKind.stroke &&
        !(item.kind == BoardKind.mermaid && item.thumbnail != null);
    if (rendersLabel && item.label.isNotEmpty) {
      final lines = const LineSplitter().convert(item.label);
      final height = lines.length * 16.0;
      final width = measureLabel == null
          ? rect.width
          : lines.map(measureLabel).reduce(max);
      rect = rect.boundingBox(
        Rectangle(
          rect.left + (rect.width - width) / 2,
          rect.top + (rect.height - height) / 2,
          width,
          height,
        ),
      );
    }
    if (item.strokeWidth case final width?) {
      rect = Rectangle(
        rect.left - width / 2,
        rect.top - width / 2,
        rect.width + width,
        rect.height + width,
      );
    }
    bounds = bounds?.boundingBox(rect) ?? rect;
  }
  if (bounds == null) throw const FormatException('Empty selection');
  return Rectangle(
    bounds.left - 12,
    bounds.top - 12,
    bounds.width + 24,
    bounds.height + 24,
  );
}

String boardSvg(
  BoardDocument doc, {
  Set<String>? selected,
  double Function(String)? measureLabel,
}) {
  final items = doc.paintOrder.where(
    (i) => selected == null || selected.contains(i.id),
  );
  final bounds = boardExportBounds(
    doc,
    items,
    includeSvgLabels: true,
    measureLabel: measureLabel,
  );
  final x = bounds.left, y = bounds.top, w = bounds.width, h = bounds.height;
  final b = XmlBuilder();
  void text(
    double x,
    double y,
    String label, [
    String color = '#202020',
    String? halo,
  ]) {
    if (label.isNotEmpty) {
      final lines = const LineSplitter().convert(label);
      b.element(
        'text',
        attributes: {
          'x': '$x',
          'y': '$y',
          'text-anchor': 'middle',
          'font-family': 'sans-serif',
          'font-size': '14',
          'fill': color,
          if (halo != null) ...{
            'stroke': halo,
            'stroke-width': '6',
            'paint-order': 'stroke',
          },
        },
        nest: () {
          if (lines.length == 1) {
            b.text(lines.first);
            return;
          }
          final firstBaseline = y - (lines.length - 1) * 8;
          for (final (index, line) in lines.indexed) {
            b.element(
              'tspan',
              attributes: {'x': '$x', 'y': '${firstBaseline + index * 16}'},
              nest: () => b.text(line),
            );
          }
        },
      );
    }
  }

  b.element(
    'svg',
    attributes: {
      'xmlns': 'http://www.w3.org/2000/svg',
      'width': '$w',
      'height': '$h',
      'viewBox': '$x $y $w $h',
    },
    nest: () {
      for (final i in items) {
        if (i.kind == BoardKind.arrow) {
          final endpoints = boardEdgeEndpoints(doc, i);
          final ax = endpoints.start.x,
              ay = endpoints.start.y,
              bx = endpoints.end.x,
              by = endpoints.end.y,
              mid = (ax + bx) / 2;
          final midY = (ay + by) / 2;
          final wing = endpoints.vertical
              ? (ay <= by ? -8 : 8)
              : (ax <= bx ? -8 : 8);
          b.element(
            'path',
            attributes: {
              'd': endpoints.vertical
                  ? 'M $ax $ay V $midY H $bx V $by m -4 $wing L $bx $by l 4 $wing'
                  : 'M $ax $ay H $mid V $by H $bx m $wing -4 L $bx $by l $wing 4',
              'fill': 'none',
              'stroke': i.color ?? '#303030',
              if (i.strokeWidth != null) 'stroke-width': '${i.strokeWidth}',
            },
          );
          text(
            mid,
            (ay + by) / 2 + 5,
            i.label,
            i.color ?? '#202020',
            i.color == null ? '#FFFFFF' : i.contrastInk,
          );
          continue;
        }
        final cx = i.x + i.width / 2, cy = i.y + i.height / 2;
        final attrs = {
          'stroke': '#303030',
          if (i.strokeWidth != null) 'stroke-width': '${i.strokeWidth}',
          'fill': i.color ?? (i.kind == BoardKind.note ? '#fff3ac' : 'white'),
        };
        if (i.kind == BoardKind.stroke) {
          if (i.width <= 1 && i.height <= 1) {
            b.element(
              'circle',
              attributes: {
                'cx': '${i.x}',
                'cy': '${i.y}',
                'r': i.strokeWidth == null ? '1' : '${i.strokeWidth! / 2}',
                'fill': i.color ?? '#303030',
              },
            );
            continue;
          }
          b.element(
            'polyline',
            attributes: {
              'points': i.points
                  .map((p) => '${i.x + p.x},${i.y + p.y}')
                  .join(' '),
              'stroke': i.color ?? '#303030',
              'fill': 'none',
              if (i.strokeWidth != null) 'stroke-width': '${i.strokeWidth}',
            },
          );
        } else if (i.kind == BoardKind.decision) {
          b.element(
            'polygon',
            attributes: {
              ...attrs,
              'points':
                  '$cx,${i.y} ${i.x + i.width},$cy $cx,${i.y + i.height} ${i.x},$cy',
            },
          );
        } else if (i.kind == BoardKind.mermaid && i.thumbnail != null) {
          i.thumbnailBytes;
          b.element(
            'image',
            attributes: {
              'x': '${i.x}',
              'y': '${i.y}',
              'width': '${i.width}',
              'height': '${i.height}',
              'href': 'data:image/png;base64,${i.thumbnail}',
            },
          );
          continue;
        } else if (i.kind != BoardKind.text) {
          b.element(
            'rect',
            attributes: {
              ...attrs,
              'x': '${i.x}',
              'y': '${i.y}',
              'width': '${i.width}',
              'height': '${i.height}',
              'rx': '4',
            },
          );
        }
        text(
          cx,
          cy + 5,
          i.label,
          i.kind == BoardKind.text
              ? i.color ?? '#202020'
              : i.color == null
              ? '#202020'
              : i.contrastInk,
        );
      }
    },
  );
  return b.buildDocument().toXmlString();
}
