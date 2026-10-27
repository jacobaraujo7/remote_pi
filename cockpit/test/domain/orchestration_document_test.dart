import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:cockpit/app/cockpit/domain/entities/orchestration_document.dart';
import 'package:cockpit/app/cockpit/domain/entities/workspace_graph.dart';

void main() {
  test(
    'recognizes .orc and legacy files without matching unrelated suffixes',
    () {
      for (final file in [
        'agents.orc',
        '/work/AGENTS.ORC',
        r'C:\work\agents.orc',
        'old.orchestration',
        'OLD.ORCHESTRATION',
      ]) {
        expect(OrchestrationDocument.isFilePath(file), isTrue, reason: file);
      }
      for (final file in [
        'agents.orc.bak',
        '/folder.orc/file.txt',
        'file.json',
        'orc',
      ]) {
        expect(OrchestrationDocument.isFilePath(file), isFalse, reason: file);
      }
    },
  );
  test(
    'fresh defaults use independent IDs but do not populate empty files',
    () {
      var id = 0;
      final a = OrchestrationDocument.defaultTerminals(
        newId: () => 'box-${++id}',
      );
      final b = OrchestrationDocument.defaultTerminals(
        newId: () => 'box-${++id}',
      );
      expect(a.boxes.length, 3);
      expect(b.boxes.length, 3);
      expect(
        {
          ...a.boxes.map((b) => b.box.id),
          ...b.boxes.map((b) => b.box.id),
        }.length,
        6,
      );
      expect(
        OrchestrationDocument.parse(
          const OrchestrationDocument().encode(),
        ).boxes,
        isEmpty,
      );
    },
  );

  const box = GraphBox(
    id: 'stable',
    title: 'API',
    role: 'Backend',
    harness: 'claude',
    model: 'sonnet',
    position: Offset(12, 20),
    tabId: 'local-process',
  );
  test(
    'portable JSON excludes live session identity and preserves configuration',
    () {
      final doc = OrchestrationDocument(
        boxes: [const OrchestrationBox(box: box, directory: 'packages/api')],
        extra: {'notes': 'shared'},
      );
      final text = doc.encode();
      expect(text, isNot(contains('tabId')));
      expect(text, isNot(contains('local-process')));
      final copy = OrchestrationDocument.parse(text);
      expect(copy.boxes.single.box.id, 'stable');
      expect(copy.boxes.single.directory, 'packages/api');
      expect(copy.boxes.single.box.tabId, isNull);
      expect(copy.extra['notes'], 'shared');
    },
  );
  test(
    'rejects absolute, parent and platform-specific paths before reconciliation',
    () {
      for (final dir in [
        '/home/me',
        'C:/work',
        'C:\\work',
        '../other',
        'a/../../b',
        '',
      ]) {
        final text = OrchestrationDocument(
          boxes: [OrchestrationBox(box: box, directory: dir)],
        ).encode();
        expect(
          () => OrchestrationDocument.parse(text),
          throwsFormatException,
          reason: dir,
        );
      }
    },
  );
  test('rejects duplicate boxes and dangling links', () {
    expect(
      () => OrchestrationDocument.parse(
        OrchestrationDocument(
          boxes: [
            const OrchestrationBox(box: box),
            const OrchestrationBox(box: box),
          ],
        ).encode(),
      ),
      throwsFormatException,
    );
    expect(
      () => OrchestrationDocument.parse(
        OrchestrationDocument(
          boxes: [const OrchestrationBox(box: box)],
          links: [const GraphLink(from: 'stable', to: 'missing')],
        ).encode(),
      ),
      throwsFormatException,
    );
  });
  test('rejects unsupported versions without coercion', () {
    expect(
      () => OrchestrationDocument.parse(
        jsonEncode({'version': 2, 'boxes': [], 'links': []}),
      ),
      throwsFormatException,
    );
  });
}
