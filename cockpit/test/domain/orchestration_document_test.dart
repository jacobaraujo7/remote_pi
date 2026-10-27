import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/widgets.dart';
import 'package:cockpit/app/cockpit/domain/entities/orchestration_document.dart';
import 'package:cockpit/app/cockpit/domain/entities/workspace_graph.dart';

void main() {
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
