import 'dart:async';
import 'dart:io';
import 'package:cockpit/app/core/data/setup/json_state_store.dart';
import 'package:cockpit/app/cockpit/data/repositories/json_workspace_layout_store.dart';
import 'package:cockpit/app/cockpit/domain/entities/workspace_presentation.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'queued order survives immediate close flush and fresh store in every view',
    () async {
      final root = await Directory.systemTemp.createTemp(
        'workspace_order_store_',
      );
      try {
        var presentation = const WorkspacePresentation(
          boxOrder: ['review', 'backend', 'design'],
          selectedBoxId: 'backend',
        );
        for (final mode in WorkspaceViewMode.values) {
          presentation = presentation.copyWith(mode: mode);
          final store = await JsonStateStore.open(root.path, 'layouts');
          final layouts = JsonWorkspaceLayoutStore(store);
          // Window close flushes immediately, before the store debounce expires.
          final pending = layouts.save('workspace-a', {
            'v': 1,
            'presentation': presentation.toJson(),
          });
          unawaited(
            layouts.save('workspace-b', {
              'v': 1,
              'presentation': const WorkspacePresentation(
                boxOrder: ['another'],
              ).toJson(),
            }),
          );
          await JsonStateStore.flushAll();
          await pending;
          JsonStateStore.resetCacheForTesting();
          final reopened = JsonWorkspaceLayoutStore(
            await JsonStateStore.open(root.path, 'layouts'),
          );
          final restored = WorkspacePresentation.fromJson(
            (await reopened.load('workspace-a'))!['presentation'],
          );
          expect(restored.mode, mode);
          expect(restored.boxOrder, ['review', 'backend', 'design']);
          expect(restored.selectedBoxId, 'backend');
          expect(
            WorkspacePresentation.fromJson(
              (await reopened.load('workspace-b'))!['presentation'],
            ).boxOrder,
            ['another'],
          );
        }
      } finally {
        JsonStateStore.resetCacheForTesting();
        await root.delete(recursive: true);
      }
    },
  );
}
