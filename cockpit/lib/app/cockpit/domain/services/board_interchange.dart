import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:xml/xml.dart';
import '../entities/board_document.dart';

abstract final class BoardInterchange {
  static String mermaid(BoardDocument doc) {
    final ids = {
      for (final (n, i)
          in doc.items.values.where((e) => e.kind != BoardKind.arrow).indexed)
        i.id: 'N$n',
    };
    String label(String raw) => raw
        .replaceAll('&', '&amp;')
        .replaceAll('"', '&quot;')
        .replaceAll('<', '&lt;')
        .replaceAll('>', '&gt;')
        .replaceAll('|', '&#124;')
        .replaceAll('\n', ' ');
    if (doc.items.length == 1 &&
        doc.items.values.single.kind == BoardKind.mermaid) {
      return doc.items.values.single.label;
    }
    final out = StringBuffer('flowchart LR\n');
    for (final i in doc.items.values.where((e) => e.kind != BoardKind.arrow)) {
      final text = label(i.label.isEmpty ? i.kind.name : i.label);
      out.writeln(
        i.kind == BoardKind.decision
            ? '  ${ids[i.id]}{"$text"}'
            : '  ${ids[i.id]}["$text"]',
      );
    }
    for (final i in doc.items.values.where((e) => e.kind == BoardKind.arrow)) {
      final title = i.label.isEmpty ? '' : '|"${label(i.label)}"|';
      out.writeln('  ${ids[i.from]} -->$title ${ids[i.to]}');
    }
    return out.toString();
  }

  static BoardDocument readDrawio(String source) {
    var xml = XmlDocument.parse(source);
    if (xml.rootElement.name.local == 'mxfile') {
      final pages = xml.findAllElements('diagram').toList();
      if (pages.length != 1) {
        throw const FormatException('Import one draw.io page at a time');
      }
      if (pages.single.childElements.isEmpty) {
        final compressed = base64Decode(pages.single.innerText.trim());
        xml = XmlDocument.parse(
          Uri.decodeComponent(
            utf8.decode(ZLibDecoder(raw: true).convert(compressed)),
          ),
        );
      }
    }
    if (xml.findAllElements('mxGraphModel').isEmpty) {
      throw const FormatException('Missing mxGraphModel');
    }
    final items = <BoardItem>[];
    final cells = {
      for (final c in xml.findAllElements('mxCell')) c.getAttribute('id'): c,
    };
    for (final cell in cells.values) {
      final id = cell.getAttribute('id')!, g = cell.getElement('mxGeometry');
      final label = cell.getAttribute('value') ?? '';
      String? styleColor(String key) => BoardItem.rgb(
        RegExp(
          '(?:^|;)$key=(#[a-fA-F0-9]{6})(?:;|\$)',
        ).firstMatch(cell.getAttribute('style') ?? '')?.group(1),
      );
      if (cell.getAttribute('edge') == '1') {
        items.add(
          BoardItem(
            id,
            BoardKind.arrow,
            0,
            0,
            color: styleColor('strokeColor'),
            from: cell.getAttribute('source'),
            to: cell.getAttribute('target'),
            label: label,
          ),
        );
      } else if (cell.getAttribute('vertex') == '1') {
        final style = cell.getAttribute('style') ?? '';
        double n(String key, double def) =>
            double.tryParse(g?.getAttribute(key) ?? '') ?? def;
        if (style.split(';').contains('group')) continue;
        final parent = cells[cell.getAttribute('parent')];
        final group =
            parent?.getAttribute('style')?.split(';').contains('group') == true
            ? parent
            : null;
        final origin = group?.getElement('mxGeometry');
        final ox = double.tryParse(origin?.getAttribute('x') ?? '') ?? 0,
            oy = double.tryParse(origin?.getAttribute('y') ?? '') ?? 0;
        final kind = style.contains('rhombus')
            ? BoardKind.decision
            : style.contains('swimlane')
            ? BoardKind.lane
            : style.startsWith('text')
            ? BoardKind.text
            : style.contains('shape=note')
            ? BoardKind.note
            : BoardKind.process;
        items.add(
          BoardItem(
            id,
            kind,
            ox + n('x', 0),
            oy + n('y', 0),
            color: styleColor(
              kind == BoardKind.text ? 'fontColor' : 'fillColor',
            ),
            group: group?.getAttribute('id'),
            width: max(1, n('width', 136)),
            height: max(1, n('height', 64)),
            label: label,
          ),
        );
      }
    }
    return BoardDocument(items);
  }

  static String drawio(BoardDocument doc) {
    final b = XmlBuilder();
    b.element(
      'mxfile',
      nest: () => b.element(
        'diagram',
        attributes: {'name': 'Board'},
        nest: () => b.element(
          'mxGraphModel',
          nest: () => b.element(
            'root',
            nest: () {
              var root = 'root', layer = 'layer';
              while (doc.items.containsKey(root)) {
                root += '0';
              }
              while (doc.items.containsKey(layer)) {
                layer += '0';
              }
              b.element('mxCell', attributes: {'id': root});
              b.element('mxCell', attributes: {'id': layer, 'parent': root});
              final groups = {
                for (final e in doc.items.values)
                  if (e.group != null) e.group!: BoardDocument.newId(),
              };
              for (final g in groups.values) {
                b.element(
                  'mxCell',
                  attributes: {
                    'id': g,
                    'parent': layer,
                    'vertex': '1',
                    'style': 'group;',
                  },
                  nest: () =>
                      b.element('mxGeometry', attributes: {'as': 'geometry'}),
                );
              }
              for (final e in doc.items.values) {
                final arrow = e.kind == BoardKind.arrow;
                final style = switch (e.kind) {
                  BoardKind.arrow =>
                    'edgeStyle=orthogonalEdgeStyle;endArrow=classic;',
                  BoardKind.decision => 'rhombus;',
                  BoardKind.lane => 'swimlane;',
                  BoardKind.note => 'shape=note;',
                  BoardKind.text => 'text;',
                  _ => 'rounded=1;',
                };
                b.element(
                  'mxCell',
                  attributes: {
                    'id': e.id,
                    'parent': groups[e.group] ?? layer,
                    'value': e.label,
                    'style': e.color == null
                        ? style
                        : e.kind == BoardKind.text
                        ? '${style}fontColor=${e.color};'
                        : arrow
                        ? '${style}strokeColor=${e.color};'
                        : '${style}fillColor=${e.color};fontColor=${e.contrastInk};',
                    if (arrow) ...{
                      'edge': '1',
                      'source': e.from!,
                      'target': e.to!,
                    } else
                      'vertex': '1',
                  },
                  nest: () => b.element(
                    'mxGeometry',
                    attributes: {
                      'as': 'geometry',
                      if (arrow)
                        'relative': '1'
                      else ...{
                        'x': '${e.x}',
                        'y': '${e.y}',
                        'width': '${e.width}',
                        'height': '${e.height}',
                      },
                    },
                  ),
                );
              }
            },
          ),
        ),
      ),
    );
    return b.buildDocument().toXmlString(pretty: true);
  }

  static BoardDocument readExcalidraw(String source) {
    final scene = jsonDecode(source);
    if (scene['type'] != 'excalidraw') {
      throw const FormatException('Invalid Excalidraw scene');
    }
    final elements = (scene['elements'] as List)
        .where((e) => e['isDeleted'] != true)
        .toList();
    final labels = {
      for (final e in elements)
        if (e['type'] == 'text' && e['containerId'] != null)
          e['containerId']: e['text'] as String,
    };
    final items = <BoardItem>[];
    for (final e in elements) {
      final type = e['type'];
      if (type == 'text' && e['containerId'] != null) continue;
      final kind = switch (type) {
        'arrow' => BoardKind.arrow,
        'diamond' => BoardKind.decision,
        'text' => BoardKind.text,
        'freedraw' || 'line' => BoardKind.stroke,
        'rectangle' || 'ellipse' => BoardKind.process,
        _ => throw FormatException('Unsupported Excalidraw element: $type'),
      };
      items.add(
        BoardItem(
          e['id'] as String,
          kind,
          (e['x'] as num).toDouble(),
          (e['y'] as num).toDouble(),
          width: max(1, (e['width'] as num).toDouble()),
          height: max(1, (e['height'] as num).toDouble()),
          color: BoardItem.rgb(
            e[kind == BoardKind.text ||
                    kind == BoardKind.stroke ||
                    kind == BoardKind.arrow
                ? 'strokeColor'
                : 'backgroundColor'],
          ),
          group: (e['groupIds'] as List?)?.lastOrNull as String?,
          label: labels[e['id']] ?? e['text'] as String? ?? '',
          from: e['startBinding']?['elementId'] as String?,
          to: e['endBinding']?['elementId'] as String?,
          points: kind == BoardKind.stroke
              ? [
                  for (final p in e['points'] as List)
                    (x: (p[0] as num).toDouble(), y: (p[1] as num).toDouble()),
                ]
              : [],
        ),
      );
    }
    return BoardDocument(items);
  }

  static String excalidraw(BoardDocument doc) {
    final elements = <Map<String, dynamic>>[];
    final labelIds = {
      for (final i in doc.items.values)
        if (i.label.isNotEmpty && i.kind != BoardKind.text)
          i.id: BoardDocument.newId(),
    };
    for (final i in doc.items.values) {
      final type = switch (i.kind) {
        BoardKind.arrow => 'arrow',
        BoardKind.stroke => 'freedraw',
        BoardKind.text => 'text',
        BoardKind.decision => 'diamond',
        _ => 'rectangle',
      };
      final base = {
        'id': i.id,
        'type': type,
        'x': i.x,
        'y': i.y,
        'width': i.width,
        'height': i.height,
        'angle': 0,
        'strokeColor': i.usesInkColor ? i.color ?? '#1e1e1e' : '#1e1e1e',
        'backgroundColor': i.usesInkColor
            ? 'transparent'
            : i.color ?? 'transparent',
        'fillStyle': 'solid',
        'strokeWidth': 1,
        'strokeStyle': 'solid',
        'roughness': 0,
        'opacity': 100,
        'seed': 1,
        'version': 1,
        'versionNonce': 1,
        'isDeleted': false,
        'groupIds': [if (i.group != null) i.group!],
        'boundElements': [
          for (final e in doc.items.values)
            if (e.from == i.id || e.to == i.id) {'type': 'arrow', 'id': e.id},
          if (labelIds.containsKey(i.id))
            {'type': 'text', 'id': labelIds[i.id]},
        ],
      };
      final text = {
        'text': i.label,
        'originalText': i.label,
        'fontSize': 16,
        'fontFamily': 1,
        'textAlign': 'center',
        'verticalAlign': 'middle',
        'lineHeight': 1.25,
      };
      final element = <String, dynamic>{...base};
      if (type == 'arrow') {
        final a = doc.items[i.from]!, b = doc.items[i.to]!;
        final x = a.x + a.width,
            y = a.y + a.height / 2,
            dx = b.x - x,
            dy = b.y + b.height / 2 - y;
        element.addAll({
          'x': x,
          'y': y,
          'width': dx.abs(),
          'height': dy.abs(),
          'points': [
            [0, 0],
            [dx, dy],
          ],
          'startBinding': {'elementId': a.id, 'focus': 0, 'gap': 0},
          'endBinding': {'elementId': b.id, 'focus': 0, 'gap': 0},
          'startArrowhead': null,
          'endArrowhead': 'arrow',
        });
      }
      if (type == 'freedraw') {
        element.addAll({
          'points': [
            for (final p in i.points) [p.x, p.y],
          ],
          'pressures': [],
          'simulatePressure': true,
        });
      }
      if (type == 'text') element.addAll(text);
      elements.add(element);
      if (labelIds.containsKey(i.id)) {
        elements.add({
          ...base,
          ...text,
          'id': labelIds[i.id],
          'type': 'text',
          'containerId': i.id,
          'strokeColor': i.usesInkColor ? i.color ?? '#202020' : i.contrastInk,
          'backgroundColor': 'transparent',
          'boundElements': [],
        });
      }
    }
    return jsonEncode({
      'type': 'excalidraw',
      'version': 2,
      'source': 'Cockpit',
      'elements': elements,
      'appState': {},
      'files': {},
    });
  }
}
