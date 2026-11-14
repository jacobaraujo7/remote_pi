import 'dart:convert';
import 'dart:math';
import 'package:xml/xml.dart';
import '../entities/board_document.dart';

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
  final bounds = [
    ...shapes,
    for (final e in edges) ...[doc.items[e.from]!, doc.items[e.to]!],
  ];
  if (bounds.isEmpty) throw const FormatException('Empty selection');
  final x = bounds.map((e) => e.x).reduce(min) - 12,
      y = bounds.map((e) => e.y).reduce(min) - 12;
  final w = bounds.map((e) => e.x + e.width).reduce(max) - x + 12,
      h = bounds.map((e) => e.y + e.height).reduce(max) - y + 12;
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
        final a = doc.items[e.from]!, d = doc.items[e.to]!;
        final right = a.x + a.width / 2 <= d.x + d.width / 2;
        final ax = right ? a.x + a.width : a.x,
            ay = a.y + a.height / 2,
            bx = right ? d.x : d.x + d.width,
            by = d.y + d.height / 2,
            mid = (ax + bx) / 2;
        final wing = right ? -8 : 8;
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
          base64Decode(i.thumbnail!);
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
