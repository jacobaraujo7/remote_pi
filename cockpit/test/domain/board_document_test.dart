import 'dart:convert';
import 'dart:io';

import 'package:cockpit/app/cockpit/data/filesystem/disk_file_change_watcher.dart';
import 'package:cockpit/app/cockpit/data/filesystem/file_reader_impl.dart';
import 'package:cockpit/app/cockpit/domain/entities/board_document.dart';
import 'package:cockpit/app/cockpit/domain/entities/file_view.dart';
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
  test('escaped identities remain connected after a Markdown round trip', () {
    const id = 'first:\\n\r\nstep';
    final board = BoardDocument([
      const BoardItem(id, BoardKind.process, 0, 0),
      end,
      const BoardItem('link', BoardKind.arrow, 0, 0, from: id, to: 'b'),
    ], id: 'board\\name');
    final restored = BoardDocument.parse(board.encode());
    expect(restored.id, board.id);
    expect(restored.items[id]?.id, id);
    expect(restored.items['link']?.from, id);
    expect(restored.encode(), board.encode());
  });
  test(
    'editing a workspace file as text reloads its diagram after atomic rename',
    () async {
      final dir = await Directory.systemTemp.createTemp('cockpit-canvas-');
      addTearDown(() => dir.delete(recursive: true));
      final file = File('${dir.path}/process.board');
      await File(
        'cli/skills/cockpit-canvas/templates/approval.board',
      ).copy(file.path);
      const watcher = DiskFileChangeWatcher(
        pollInterval: Duration(milliseconds: 100),
      );
      final reloaded = watcher.watchFile(file.path).first.then((_) async {
        final view =
            await const FileReaderImpl().read(file.path) as FileViewText;
        expect(view.language, 'markdown');
        return BoardDocument.parse(view.text);
      });
      final staged = File('${file.path}.tmp');
      await staged.writeAsString(
        (await file.readAsString()).replaceFirst(
          '> Receber pedido',
          '> Validar pedido',
        ),
      );
      await staged.rename(file.path);
      final observed = await reloaded.timeout(const Duration(seconds: 5));
      expect(observed.items['request']!.label, 'Validar pedido');
      expect(observed.items['link']!.from, 'request');
      final moved = BoardEdit.replace(
        observed,
        observed.items['request']!.edited(x: 75),
      ).apply(observed);
      expect(
        await const FileReaderImpl().write(file.path, moved.encode()),
        isTrue,
      );
      final saved = await file.readAsString();
      expect(saved, contains('> Validar pedido'));
      expect(saved, contains('- x: 75.0'));
    },
  );
  test(
    'legacy Markdown v2 writes plain properties and body labels on save',
    () {
      const source =
          '# Canvas Board\n- version: 2\n- id: "billing"\n\n'
          '## process\n- id: "first"\n- x: 3\n- y: 4\n'
          '- width: 20\n- height: 30\n- label: "Hello\\nworld"\n';
      final doc = BoardDocument.parse(source);
      final current = doc.encode();
      expect(current, contains('- id: first\n'));
      expect(current, contains('> Hello\n> world\n'));
      expect(
        BoardDocument.parse(current).items['first']!.label,
        'Hello\nworld',
      );
    },
  );
  test('stroke offsets and multiline labels are ordinary Markdown', () {
    const stroke = BoardItem(
      'ink',
      BoardKind.stroke,
      12,
      4,
      points: [(x: 0, y: 0), (x: 22.4, y: -9)],
      label: '> literal\r\n## does not start an object\n',
    );
    final text = BoardDocument([stroke]).encode();
    expect(text, contains('- points:\n  - 0.0, 0.0\n  - 22.4, -9.0\n'));
    expect(BoardDocument.parse(text).items['ink']!.toJson(), stroke.toJson());
    expect(
      () => BoardDocument.parse(
        text.replaceFirst('- id: ink', '- id: ink\n- id: repeated'),
      ),
      throwsFormatException,
    );
    expect(
      () => BoardDocument.parse(text.replaceFirst('version: 3', 'version: 4')),
      throwsFormatException,
    );
  });
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
      expect(markdown, startsWith('---\nversion: 3\n'));
      final reopened = BoardDocument.parse(markdown.replaceAll('\n', '\r\n'));
      expect(reopened.id, 'billing');
      expect(reopened.encode(), markdown.replaceAll('\n', '\r\n'));
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
        '- version: 33',
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
