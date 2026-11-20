import 'dart:io';

import 'package:cockpit/app/cockpit/data/repositories/json_workspace_layout_store.dart';
import 'package:cockpit/app/cockpit/ui/states/sidebar_panel.dart';
import 'package:cockpit/app/cockpit/ui/widgets/file_tree_panel.dart';
import 'package:cockpit/app/core/data/setup/json_state_store.dart';
import 'package:cockpit/app/core/domain/result.dart';
import 'package:cockpit/app/core/ui/themes/themes.dart';
import 'package:cockpit/i18n/strings.g.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';

void main() {
  test('old, unknown and invalid selections default to Files', () {
    for (final doc in <Map<String, dynamic>?>[
      null,
      {},
      {kSidebarPanelKey: 'removedPanel'},
      {kSidebarPanelKey: 3},
    ]) {
      expect(sidebarPanelOf(doc), SidebarPanel.files);
    }
    for (final panel in SidebarPanel.values) {
      expect(sidebarPanelOf({kSidebarPanelKey: panel.name}), panel);
    }
  });

  test(
    'independent workspace and worktree layouts survive a disk reopen',
    () async {
      final dir = await Directory.systemTemp.createTemp('sidebar-layouts-');
      try {
        var state = await JsonStateStore.open(dir.path, 'layouts');
        var layouts = JsonWorkspaceLayoutStore(state);
        const choices = {
          'workspace-a': SidebarPanel.sourceControl,
          'workspace-b': SidebarPanel.database,
          'workspace-a/worktree-one': SidebarPanel.search,
          'workspace-a/worktree-two': SidebarPanel.gallery,
        };
        for (final entry in choices.entries) {
          await layouts.save(entry.key, {
            'v': 1,
            'tree': {'k': 'leaf', 'id': 'pane', 'tabs': [], 'active': ''},
            'sessions': <String, dynamic>{},
            kSidebarPanelKey: entry.value.name,
          });
        }
        await state.flush();
        JsonStateStore.resetCacheForTesting();
        state = await JsonStateStore.open(dir.path, 'layouts');
        layouts = JsonWorkspaceLayoutStore(state);
        for (var round = 0; round < 3; round++) {
          for (final entry in choices.entries) {
            final doc = await layouts.load(entry.key);
            expect(sidebarPanelOf(doc), entry.value);
            expect(doc!['tree'], isA<Map>());
            expect(doc['sessions'], isEmpty);
          }
        }
        expect(
          sidebarPanelOf(await layouts.load('new-worktree')),
          SidebarPanel.files,
        );
        await layouts.remove('workspace-b');
        expect(
          sidebarPanelOf(await layouts.load('workspace-b')),
          SidebarPanel.files,
        );
      } finally {
        JsonStateStore.resetCacheForTesting();
        await dir.delete(recursive: true);
      }
    },
  );

  testWidgets(
    'workspace and worktree switches restore their panels after remount',
    (tester) async {
      final selections = <String, SidebarPanel>{};
      var contextId = 'workspace-a';
      var isGitRepo = true;
      var searchAvailable = true;
      var revealGen = 0;
      final searchFocus = ValueNotifier<int>(0);
      late StateSetter update;
      await tester.pumpWidget(
        TranslationProvider(
          child: ShadcnApp(
            theme: buildTheme(brightness: Brightness.dark),
            home: Scaffold(
              child: StatefulBuilder(
                builder: (_, setState) {
                  update = setState;
                  return FileTreePanel(
                    key: ValueKey(contextId),
                    // Deliberately shared path: project IDs, rather than paths, own selection.
                    rootPath: '/workspace',
                    activePanel: selections[contextId] ?? SidebarPanel.files,
                    onPanelChanged: (panel) =>
                        update(() => selections[contextId] = panel),
                    revision: 0,
                    revealGen: revealGen,
                    revealPath: '/workspace/file.dart',
                    searchFocusSignal: searchFocus,
                    searchPanel: searchAvailable
                        ? const Text('SEARCH CONTENT')
                        : null,
                    databasePanel: const Text('DATABASE CONTENT'),
                    galleryPanel: const Text('GALLERY CONTENT'),
                    telemetryPanel: const Text('TELEMETRY CONTENT'),
                    listChildren: (_) async => [],
                    gitStatusOf: (_) => null,
                    onOpenFile: (_) {},
                    onOpenDiff: (_) {},
                    isGitRepo: isGitRepo,
                    changedPaths: const [],
                    onOpenWith: (_) {},
                    onCreateInFolder: (_, {command}) {},
                    onCreate: (_, _, _) async => const Success(null),
                    onRename: (_, _) async => const Success(null),
                    onDelete: (_) async => const Success(null),
                    onMove: (_, _) async => const Success(null),
                    onCopy: (_) {},
                    onCut: (_) {},
                    onPaste: (_) async => const Success(null),
                    canPaste: false,
                  );
                },
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(selections, isEmpty);
      await tester.tap(find.byKey(const ValueKey('source-control-tab')));
      await tester.pumpAndSettle();
      expect(selections[contextId], SidebarPanel.sourceControl);

      update(() => contextId = 'workspace-a/worktree-one');
      await tester.pumpAndSettle();
      expect(find.text('SEARCH CONTENT'), findsNothing);
      searchFocus.value++;
      await tester.pumpAndSettle();
      expect(selections[contextId], SidebarPanel.search);

      update(() => contextId = 'workspace-b');
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('database-tab')));
      await tester.pumpAndSettle();
      expect(find.text('DATABASE CONTENT'), findsOneWidget);

      for (var round = 0; round < 3; round++) {
        update(() => contextId = 'workspace-a');
        await tester.pumpAndSettle();
        expect(
          find.byKey(const ValueKey('source-control-changes-tab')),
          findsOneWidget,
        );
        update(() => contextId = 'workspace-a/worktree-one');
        await tester.pumpAndSettle();
        expect(find.text('SEARCH CONTENT'), findsOneWidget);
        update(() => contextId = 'workspace-b');
        await tester.pumpAndSettle();
        expect(find.text('DATABASE CONTENT'), findsOneWidget);
      }

      // Capability disappearance falls back visually, retaining the preference.
      update(() {
        contextId = 'workspace-a';
        isGitRepo = false;
      });
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('source-control-changes-tab')),
        findsNothing,
      );
      expect(selections[contextId], SidebarPanel.sourceControl);
      update(() => isGitRepo = true);
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('source-control-changes-tab')),
        findsOneWidget,
      );
      update(() {
        contextId = 'workspace-a/worktree-one';
        searchAvailable = false;
      });
      await tester.pumpAndSettle();
      expect(find.text('SEARCH CONTENT'), findsNothing);
      expect(selections[contextId], SidebarPanel.search);
      update(() => searchAvailable = true);
      await tester.pumpAndSettle();
      expect(find.text('SEARCH CONTENT'), findsOneWidget);

      // A controlled selection must survive unrelated reveal generations from
      // another context. Explicit reveals are selected by the VM.
      update(() => revealGen++);
      await tester.pumpAndSettle();
      expect(find.text('SEARCH CONTENT'), findsOneWidget);
      update(() => selections[contextId] = SidebarPanel.files);
      await tester.pumpAndSettle();
      expect(find.text('SEARCH CONTENT'), findsNothing);
      update(() => contextId = 'new-worktree');
      await tester.pumpAndSettle();
      expect(find.text('SEARCH CONTENT'), findsNothing);
      expect(find.text('DATABASE CONTENT'), findsNothing);
      expect(selections.containsKey(contextId), isFalse);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      searchFocus.dispose();
    },
  );
}
