import 'dart:convert';
import 'dart:io';

import 'package:cockpit/app/cockpit/domain/entities/board_document.dart';
import 'package:cockpit/app/cockpit/domain/entities/gallery_template.dart';
import 'package:cockpit/app/cockpit/domain/services/board_editor.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const start = BoardItem('a', BoardKind.process, 12, 5, label: 'Start');
  const end = BoardItem('b', BoardKind.decision, 200, 10, label: 'Approve?');
  const edge = BoardItem(
    'c',
    BoardKind.arrow,
    0,
    0,
    from: 'a',
    to: 'b',
    label: 'Yes',
  );
  final doc = BoardDocument([start, end, edge]);
  test(
    'legacy JSON migrates to editable Markdown with stable IDs and order',
    () {
      final items = [start.edited(color: '#00FFAA', group: 'group'), end, edge];
      final legacy = jsonEncode({
        'version': 1,
        'id': 'billing',
        'items': items.map((i) => i.toJson()).toList(),
      });
      final markdown = BoardDocument.parse(legacy).encode();
      expect(markdown, startsWith('# Canvas Board\n\n- version: 2'));
      final reopened = BoardDocument.parse(markdown.replaceAll('\n', '\r\n'));
      expect(reopened.id, 'billing');
      expect(reopened.encode(), markdown);
      expect(
        reopened.items.values.map((i) => i.toJson()),
        items.map((i) => i.toJson()),
      );
    },
  );
  test('the core skill example opens as a connected diagram', () {
    final guide = File(
      'cli/skills/cockpit-canvas/references/board.md',
    ).readAsStringSync();
    final markdown = RegExp(
      r'```markdown\r?\n([\s\S]*?)\r?\n```',
    ).firstMatch(guide)![1]!;
    final board = BoardDocument.parse(markdown);
    expect(board.items['link']!.from, 'request');
    expect(board.items['link']!.to, 'approve');
  });
  test(
    'Markdown preserves fence tokens, CRLF, trailing lines and empty Mermaid',
    () {
      for (final label in [
        '',
        'graph TD\n%% ```\n\n',
        'sequenceDiagram\r\n A->>B: Olá\r\n',
      ]) {
        final item = BoardItem(
          'diagram',
          BoardKind.mermaid,
          0,
          0,
          label: label,
        );
        final encoded = BoardDocument([item]).encode();
        if (!label.contains('\r')) expect(encoded, contains('`mermaid\n'));
        expect(BoardDocument.parse(encoded).items['diagram']!.label, label);
      }
    },
  );
  test(
    'Markdown rejects unsupported versions, duplicate and unknown properties',
    () {
      for (final header in [
        '- version: 3',
        '- version: 2\n- version: 2',
        '- version: 2\n- typo: 1',
      ]) {
        expect(
          () => BoardDocument.parse('# Canvas Board\n$header'),
          throwsFormatException,
        );
      }
    },
  );
  test(
    'Gallery creates a valid editable board and suffixes colliding names',
    () {
      final template = GalleryTemplate.board;
      expect(BoardDocument.parse(template.content).items, isEmpty);
      expect(template.uniqueFileName(['diagram.board']), 'diagram-2.board');
    },
  );
  test('deleting and restoring a shape also restores its connector', () {
    final edit = BoardEdit.remove(doc, 'a');
    final removed = edit.apply(doc);
    expect(removed.items.keys, ['b']);
    expect(edit.inverse.apply(removed).items['c']!.toJson(), edge.toJson());
  });
  test('independent moves survive an inverse and conflicting moves fail', () {
    final edit = BoardEdit.replace(doc, start.edited(x: 55));
    final moved = edit.apply(doc);
    final independent = BoardEdit.replace(
      moved,
      end.edited(y: 109),
    ).apply(moved);
    final restored = edit.inverse.apply(independent);
    expect(restored.items['a']!.x, 12);
    expect(restored.items['b']!.y, 109);
    expect(() => edit.apply(moved), throwsStateError);
  });
  test('Mermaid source survives a workspace save and reopen exactly', () {
    const source =
        '---\ntitle: Entrega\n---\nsequenceDiagram\n  Ana->>José: Olá!\n';
    final item = BoardItem(
      BoardDocument.newId(),
      BoardKind.mermaid,
      80,
      20,
      label: source,
    );
    final saved = BoardEdit.replace(doc, item).apply(doc);
    expect(BoardDocument.parse(saved.encode()).items[item.id]!.label, source);
  });
  test(
    'corrupt, unknown and disconnected documents cannot replace the canvas',
    () {
      expect(
        () => BoardDocument.parse('{"version":2,"items":[]}'),
        throwsFormatException,
      );
      expect(() => BoardDocument([start, edge]), throwsFormatException);
      expect(() => BoardDocument([start, start]), throwsFormatException);
    },
  );
}
