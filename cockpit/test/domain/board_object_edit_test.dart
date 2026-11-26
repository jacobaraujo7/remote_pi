import 'package:cockpit/app/cockpit/domain/entities/board_document.dart';
import 'package:cockpit/app/cockpit/domain/services/board_editor.dart';
import 'package:cockpit/app/cockpit/domain/services/board_svg.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final doc = BoardDocument([
    const BoardItem('a', BoardKind.process, 0, 0, label: 'First'),
    const BoardItem('b', BoardKind.process, 200, 0, label: 'Second'),
    const BoardItem('edge', BoardKind.arrow, 0, 0, from: 'a', to: 'b'),
    const BoardItem('lane', BoardKind.lane, 0, 0, label: 'Lane'),
  ]);
  List<String> ids(BoardDocument doc) =>
      doc.paintOrder.map((i) => i.id).toList();
  test('absolute order crosses layers, survives reopening and undo', () {
    final edit = BoardEdit.reorder(doc, {'lane', 'edge'}, front: true);
    final changed = BoardDocument.parse(edit.apply(doc).encode());
    expect(ids(changed), ['a', 'b', 'lane', 'edge']);
    final svg = boardSvg(changed);
    expect(svg.indexOf('Second'), lessThan(svg.indexOf('Lane')));
    expect(svg.indexOf('Lane'), lessThan(svg.indexOf('<path')));
    expect(
      ids(
        BoardEdit.reorder(changed, {'edge'}, front: false).apply(changed),
      ).first,
      'edge',
    );
    final independent = BoardEdit.replace(
      changed,
      changed.items['a']!.edited(label: 'New'),
    ).apply(changed);
    final undone = edit.inverse.apply(independent);
    expect(ids(undone), ids(doc));
    expect(undone.items['a']!.label, 'New');
    expect(undone.encode(), contains('version: 3'));
  });
  test('multi-delete restores insertion order, shapes and both endpoints', () {
    final remove = BoardEdit.removeMany(doc, {'a', 'edge'});
    final removed = remove.apply(doc);
    expect(removed.items.keys, ['b', 'lane']);
    expect(remove.inverse.apply(removed).encode(), doc.encode());
    expect(BoardEdit.removeMany(doc, {'edge'}).apply(doc).items.keys, [
      'a',
      'b',
      'lane',
    ]);
  });
  test('v4 width is finite, positive and exported to SVG', () {
    final item = doc.items['edge']!.edited(strokeWidth: 8);
    final source = BoardEdit.replace(doc, item).apply(doc).encode();
    final reopened = BoardDocument.parse(source);
    expect(source, contains('version: 4'));
    expect(reopened.items['edge']!.strokeWidth, 8);
    expect(boardSvg(reopened), contains('stroke-width="8.0"'));
    for (final invalid in ['-1', '0', 'Infinity', 'NaN']) {
      expect(
        () => BoardDocument.parse(
          source.replaceFirst('stroke: 8.0', 'stroke: $invalid'),
        ),
        throwsFormatException,
      );
    }
  });
}
