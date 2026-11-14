import 'package:cockpit/app/cockpit/domain/entities/board_document.dart';
import 'package:cockpit/app/cockpit/domain/services/board_interchange.dart';
import 'package:cockpit/app/cockpit/domain/services/board_svg.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xml/xml.dart';

void main() {
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
