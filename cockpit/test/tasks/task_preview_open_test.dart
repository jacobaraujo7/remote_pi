import 'package:cockpit/app/cockpit/domain/entities/task_definition.dart';
import 'package:flutter_test/flutter_test.dart';

TaskDefinition def({
  bool previewEnabled = true,
  TaskPreviewOpen previewOpen = TaskPreviewOpen.always,
}) => TaskDefinition(
  id: 'json:api',
  label: 'api',
  cwd: '/tmp',
  command: 'go',
  previewEnabled: previewEnabled,
  previewOpen: previewOpen,
);

void main() {
  test(
    'always (default) abre no start E no restart — comportamento histórico',
    () {
      final task = def();

      expect(task.shouldOpenPreview(isRestart: false), isTrue);
      expect(task.shouldOpenPreview(isRestart: true), isTrue);
    },
  );

  test('start abre no start e cala no restart', () {
    final task = def(previewOpen: TaskPreviewOpen.start);

    expect(task.shouldOpenPreview(isRestart: false), isTrue);
    expect(task.shouldOpenPreview(isRestart: true), isFalse);
  });

  test('never nunca abre', () {
    final task = def(previewOpen: TaskPreviewOpen.never);

    expect(task.shouldOpenPreview(isRestart: false), isFalse);
    expect(task.shouldOpenPreview(isRestart: true), isFalse);
  });

  test('preview: false vence qualquer previewOpen', () {
    for (final open in TaskPreviewOpen.values) {
      final task = def(previewEnabled: false, previewOpen: open);
      expect(
        task.shouldOpenPreview(isRestart: false),
        isFalse,
        reason: '$open',
      );
      expect(task.shouldOpenPreview(isRestart: true), isFalse, reason: '$open');
    }
  });
}
