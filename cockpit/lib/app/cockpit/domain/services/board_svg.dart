import 'dart:math';
import 'package:xml/xml.dart';
import '../entities/board_document.dart';

({Point<double> start, Point<double> end}) boardEdgeEndpoints(
  BoardDocument doc,
  BoardItem edge,
) {
  final a = doc.items[edge.from]!, b = doc.items[edge.to]!;
  final right = a.x + a.width / 2 <= b.x + b.width / 2;
  return (
    start: Point(right ? a.x + a.width : a.x, a.y + a.height / 2),
    end: Point(right ? b.x : b.x + b.width, b.y + b.height / 2),
  );
}

Rectangle<double> boardExportBounds(
  BoardDocument doc,
  Iterable<BoardItem> items,
) {
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

String boardSvg(BoardDocument doc, {Set<String>? selected}) {
  final shapes = doc.items.values
      .where(
        (e) =>
            e.kind != BoardKind.arrow &&
            (selected == null || selected.contains(e.id)),
      )
      .toList();
  final edges = doc.items.values.where(
    (e) =>
        e.kind == BoardKind.arrow &&
        (selected == null || selected.contains(e.id)),
  );
  final bounds = boardExportBounds(doc, [...shapes, ...edges]);
  final x = bounds.left, y = bounds.top, w = bounds.width, h = bounds.height;
  final b = XmlBuilder();
  void text(
    double x,
    double y,
    String label, [
    String color = '#202020',
    bool edge = false,
  ]) {
    if (label.isNotEmpty) {
      b.element(
        'text',
        attributes: {
          'x': '$x',
          'y': '$y',
          'text-anchor': 'middle',
          'font-family': 'sans-serif',
          'font-size': '14',
          'fill': color,
          if (edge) ...{
            'stroke': 'white',
            'stroke-width': '6',
            'paint-order': 'stroke',
          },
        },
        nest: () => b.text(label),
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
      for (final e in edges) {
        final endpoints = boardEdgeEndpoints(doc, e);
        final ax = endpoints.start.x,
            ay = endpoints.start.y,
            bx = endpoints.end.x,
            by = endpoints.end.y,
            mid = (ax + bx) / 2;
        final wing = ax <= bx ? -8 : 8;
        b.element(
          'path',
          attributes: {
            'd': 'M $ax $ay H $mid V $by H $bx m $wing -4 L $bx $by l $wing 4',
            'fill': 'none',
            'stroke': e.color ?? '#303030',
          },
        );
        text(mid, (ay + by) / 2 + 5, e.label, e.color ?? '#202020', true);
      }
      for (final i in shapes) {
        final cx = i.x + i.width / 2, cy = i.y + i.height / 2;
        final attrs = {
          'stroke': '#303030',
          'fill': i.color ?? (i.kind == BoardKind.note ? '#fff3ac' : 'white'),
        };
        if (i.kind == BoardKind.stroke) {
          if (i.width <= 1 && i.height <= 1) {
            b.element(
              'circle',
              attributes: {
                'cx': '${i.x}',
                'cy': '${i.y}',
                'r': '1',
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
