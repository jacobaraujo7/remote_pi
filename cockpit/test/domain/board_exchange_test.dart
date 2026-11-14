import 'dart:convert';
import 'package:cockpit/app/cockpit/domain/entities/board_document.dart';
import 'package:cockpit/app/cockpit/domain/services/board_interchange.dart';
import 'package:cockpit/app/cockpit/domain/services/board_svg.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xml/xml.dart';

void main() {
  test('a single pencil mark is visible in SVG and HTML exports', () {
    final doc = BoardDocument([
      const BoardItem(
        'dot',
        BoardKind.stroke,
        30,
        45,
        width: 1,
        height: 1,
        color: '#123456',
        points: [(x: 0.0, y: 0.0)],
      ),
    ]);
    final dot = XmlDocument.parse(
      boardSvg(doc),
    ).findAllElements('circle').single;
    expect(dot.getAttribute('cx'), '30.0');
    expect(dot.getAttribute('fill'), '#123456');
  });
  final board = BoardDocument([
    const BoardItem(
      '1',
      BoardKind.process,
      0,
      20,
      color: '#64CBA7',
      label: '<start>',
    ),
    const BoardItem('2', BoardKind.decision, 220, 20, label: 'Accept?'),
    const BoardItem(
      '3',
      BoardKind.arrow,
      0,
      0,
      from: '1',
      to: '2',
      color: '#FA8983',
      label: 'Review',
    ),
  ]);
  test('Mermaid retains node and link colors in exported edge order', () {
    final drawing = BoardDocument([
      ...board.items.values.where((item) => item.kind != BoardKind.arrow),
      const BoardItem('first', BoardKind.arrow, 0, 0, from: '2', to: '1'),
      board.items['3']!,
      const BoardItem('caption', BoardKind.text, 50, 60, color: '#102030'),
    ]);
    final output = BoardInterchange.mermaid(drawing);
    expect(output, contains('style N0 fill:#64CBA7,color:#000000'));
    expect(output, contains('style N2 color:#102030'));
    expect(output, contains('linkStyle 1 stroke:#FA8983,color:#FA8983'));
    expect(output, isNot(contains('linkStyle 0')));
  });
  test('Excalidraw exports a right-to-left elbow with reciprocal bindings', () {
    final doc = BoardDocument([
      const BoardItem('right', BoardKind.process, 320, 0, width: 100),
      const BoardItem('left', BoardKind.process, 0, 100, width: 100),
      const BoardItem(
        'return',
        BoardKind.arrow,
        0,
        0,
        from: 'right',
        to: 'left',
      ),
    ]);
    final scene = jsonDecode(BoardInterchange.excalidraw(doc));
    final elements = {for (final item in scene['elements']) item['id']: item};
    final edge = elements['return'];
    expect([edge['x'], edge['y']], [320, 32]);
    expect(edge['points'], [
      [0, 0],
      [-110, 0],
      [-110, 100],
      [-220, 100],
    ]);
    for (final id in ['left', 'right']) {
      expect(elements[id]['boundElements'], [
        {'type': 'arrow', 'id': 'return'},
      ]);
    }
    expect(edge['startBinding']['elementId'], 'right');
    expect(edge['endBinding']['elementId'], 'left');
  });
  for (final codec in [
    (BoardInterchange.drawio, BoardInterchange.readDrawio),
    (BoardInterchange.excalidraw, BoardInterchange.readExcalidraw),
  ]) {
    test(
      'editable conversion preserves IDs, labels, decision, and bound endpoints ${codec.$1}',
      () {
        final result = codec.$2(codec.$1(board));
        expect(result.items['1']!.color, '#64CBA7');
        expect(result.items['3']!.color, '#FA8983');
        expect(result.items['1']!.label, '<start>');
        expect(result.items['2']!.kind, BoardKind.decision);
        expect(result.items['3']!.from, '1');
        expect(result.items['3']!.to, '2');
        expect(result.items['3']!.label, 'Review');
      },
    );
  }
  test('selection SVG crops to the selected shape and escapes its label', () {
    final svg = XmlDocument.parse(boardSvg(board, selected: {'1'}));
    expect(svg.findAllElements('rect').single.getAttribute('fill'), '#64CBA7');
    expect(
      XmlDocument.parse(
        boardSvg(board),
      ).findAllElements('path').single.getAttribute('stroke'),
      '#FA8983',
    );
    expect(svg.findAllElements('text').single.innerText, '<start>');
    expect(svg.findAllElements('polygon'), isEmpty);
  });
}
