import 'package:cockpit/app/cockpit/domain/entities/gallery_template.dart';
import 'package:cockpit/app/cockpit/domain/entities/orchestration_document.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'Gallery creates agents.orc with three unassigned terminal definitions',
    () {
      final template = GalleryTemplate.orchestration;
      expect(template.relativePath, 'agents.orc');
      expect(template.uniqueFileName(['agents.orc']), 'agents-2.orc');
      final doc = OrchestrationDocument.parse(template.content);
      expect(doc.boxes.map((b) => b.box.title), [
        'Terminal 1',
        'Terminal 2',
        'Terminal 3',
      ]);
      expect(doc.boxes.map((b) => b.box.id).toSet().length, 3);
      for (final entry in doc.boxes) {
        expect(entry.box.role, isEmpty);
        expect(entry.box.harness, isEmpty);
        expect(entry.box.model, isEmpty);
        expect(entry.box.tabId, isNull);
        expect(entry.directory, '.');
      }
      expect(doc.links, isEmpty);
    },
  );

  group('GalleryTemplate.uniqueFileName', () {
    test('returns the base name when free', () {
      expect(GalleryTemplate.layout.uniqueFileName(['a.txt']), 'dev.ckp');
    });

    test('suffixes -2, -3… when taken (case-insensitive)', () {
      expect(GalleryTemplate.layout.uniqueFileName(['DEV.CKP']), 'dev-2.ckp');
      expect(
        GalleryTemplate.kanban.uniqueFileName([
          'board.kanban',
          'board-2.kanban',
        ]),
        'board-3.kanban',
      );
    });
  });

  test('tasks lives under .cockpit with a fixed name', () {
    expect(GalleryTemplate.tasks.relativePath, '.cockpit/tasks.json');
    expect(GalleryTemplate.tasks.fixedName, isTrue);
    expect(GalleryTemplate.html.relativePath, 'view.html');
  });

  test('every template has content and a colored asset', () {
    for (final t in GalleryTemplate.values) {
      expect(t.content, isNotEmpty);
      expect(t.iconAsset, startsWith('assets/'));
      expect(t.fileName, endsWith('.${t.extension}'));
    }
  });
}
