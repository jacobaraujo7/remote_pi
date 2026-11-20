import 'package:cockpit/app/cockpit/domain/entities/content_search.dart';
import 'package:cockpit/app/cockpit/ui/states/sidebar_panel.dart';
import 'package:cockpit/app/cockpit/ui/viewmodels/content_search_controller.dart';
import 'package:cockpit/app/cockpit/ui/widgets/content_search_panel.dart';
import 'package:cockpit/app/cockpit/ui/widgets/file_tree_panel.dart';
import 'package:cockpit/app/core/domain/result.dart';
import 'package:cockpit/app/core/ui/themes/themes.dart';
import 'package:cockpit/i18n/strings.g.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';

void main() {
  testWidgets(
    'scroll, selection and controller replacement survive remount without scanning',
    (tester) async {
      var calls = 0;
      ContentSearchController create(String root) => ContentSearchController(
        root: root,
        search:
            (term, {caseSensitive = false, wholeWord = false, regex = false}) {
              calls++;
              return Stream.fromIterable(
                List.generate(
                  40,
                  (index) => FileMatches(
                    relativePath: 'file-$index.dart',
                    matches: [
                      LineMatch(
                        lineNumber: 1,
                        text: 'match $index',
                        ranges: const [MatchRange(0, 5)],
                      ),
                    ],
                  ),
                ),
              );
            },
      );
      final a = create('/workspace');
      final b = create('/worktree');
      final focus = ValueNotifier<int>(0);
      var active = a;
      var visible = true;
      late StateSetter update;
      await tester.pumpWidget(
        TranslationProvider(
          child: ShadcnApp(
            theme: buildTheme(brightness: Brightness.dark),
            home: Scaffold(
              child: SizedBox(
                width: 400,
                height: 350,
                child: StatefulBuilder(
                  builder: (_, setState) {
                    update = setState;
                    return visible
                        ? ContentSearchPanel(
                            controller: active,
                            fill: true,
                            onOpenResult: (_, _) {},
                            focusSignal: focus,
                          )
                        : const SizedBox();
                  },
                ),
              ),
            ),
          ),
        ),
      );
      await tester.enterText(find.byType(EditableText), 'needle');
      await tester.pump(const Duration(milliseconds: 201));
      await tester.pumpAndSettle();
      await tester.drag(find.byType(ListView), const Offset(0, -600));
      await tester.pumpAndSettle();
      final offset = a.scrollOffset;
      expect(offset, greaterThan(0));
      a.query.selection = const TextSelection(baseOffset: 1, extentOffset: 4);
      update(() => visible = false);
      await tester.pumpAndSettle();
      update(() => visible = true);
      await tester.pumpAndSettle();
      expect(
        tester.widget<ListView>(find.byType(ListView)).controller!.offset,
        closeTo(offset, 0.1),
      );
      expect(
        a.query.selection,
        const TextSelection(baseOffset: 1, extentOffset: 4),
      );
      expect(calls, 1);
      // Also exercise didUpdateWidget: no parent key/recreation.
      update(() => active = b);
      await tester.pumpAndSettle();
      expect(
        tester.widget<EditableText>(find.byType(EditableText)).controller.text,
        isEmpty,
      );
      update(() => active = a);
      await tester.pumpAndSettle();
      expect(
        tester.widget<ListView>(find.byType(ListView)).controller!.offset,
        closeTo(offset, 0.1),
      );
      expect(calls, 1);
      await tester.enterText(find.byType(EditableText), 'new query');
      await tester.pump(const Duration(milliseconds: 201));
      await tester.pumpAndSettle();
      expect(
        tester.widget<ListView>(find.byType(ListView)).controller!.offset,
        0,
      );
      expect(calls, 2);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      a.dispose();
      b.dispose();
      focus.dispose();
    },
  );

  testWidgets(
    'Search survives sidebar/workspace/worktree navigation without new scans',
    (tester) async {
      final states = <String, ContentSearchController>{};
      final panels = <String, SidebarPanel>{};
      final calls = <String, int>{};
      final opened = <(String, String, int)>[];
      var id = 'workspace-a';
      final focus = ValueNotifier<int>(0);
      late StateSetter update;
      await tester.pumpWidget(
        TranslationProvider(
          child: ShadcnApp(
            theme: buildTheme(brightness: Brightness.dark),
            home: Scaffold(
              child: Align(
                alignment: Alignment.topLeft,
                child: SizedBox(
                  width: 400,
                  child: StatefulBuilder(
                    builder: (_, setState) {
                      update = setState;
                      final origin = id;
                      final controller = states.putIfAbsent(
                        id,
                        () => ContentSearchController(
                          root: '/$origin',
                          search:
                              (
                                term, {
                                caseSensitive = false,
                                wholeWord = false,
                                regex = false,
                              }) {
                                calls.update(
                                  origin,
                                  (n) => n + 1,
                                  ifAbsent: () => 1,
                                );
                                return Stream.value(
                                  FileMatches(
                                    relativePath: '$origin.dart',
                                    matches: [
                                      LineMatch(
                                        lineNumber: 7,
                                        text: 'match in $origin',
                                        ranges: const [MatchRange(0, 5)],
                                      ),
                                    ],
                                  ),
                                );
                              },
                        ),
                      );
                      return FileTreePanel(
                        key: ValueKey(id),
                        rootPath: '/$id',
                        revision: 0,
                        activePanel: panels[id] ?? SidebarPanel.files,
                        onPanelChanged: (value) =>
                            update(() => panels[origin] = value),
                        searchPanel: ContentSearchPanel(
                          controller: controller,
                          fill: true,
                          focusSignal: focus,
                          onOpenResult: (path, line) =>
                              opened.add((origin, path, line)),
                        ),
                        searchFocusSignal: focus,
                        listChildren: (_) async => [],
                        gitStatusOf: (_) => null,
                        onOpenFile: (_) {},
                        onOpenDiff: (_) {},
                        isGitRepo: true,
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
          ),
        ),
      );
      await tester.pumpAndSettle();
      for (final context in ['workspace-a', 'workspace-b', 'worktree-a']) {
        update(() => id = context);
        await tester.pumpAndSettle();
        await tester.tap(find.byIcon(Icons.search));
        await tester.pumpAndSettle();
        await tester.enterText(find.byType(EditableText), 'query $context');
        await tester.pump(const Duration(milliseconds: 201));
        await tester.pumpAndSettle();
        expect(find.text('1 in 1'), findsOneWidget);
        expect(find.text('$context.dart'), findsOneWidget);
        await tester.tap(find.text('Aa'));
        await tester.pumpAndSettle();
        expect(calls[context], 2);
        await tester.tap(find.text('$context.dart')); // collapse the group
        await tester.pumpAndSettle();
        expect(
          find.text('match in $context', findRichText: true),
          findsNothing,
        );
        await tester.tap(find.byKey(const ValueKey('source-control-tab')));
        await tester.pumpAndSettle();
        await tester.tap(find.byIcon(Icons.search));
        await tester.pumpAndSettle();
        expect(find.text('query $context'), findsOneWidget);
        expect(calls[context], 2);
      }
      for (var round = 0; round < 3; round++) {
        for (final context in ['workspace-a', 'workspace-b', 'worktree-a']) {
          update(() => id = context);
          await tester.pumpAndSettle();
          expect(find.text('query $context'), findsOneWidget);
          expect(find.text('$context.dart'), findsOneWidget);
          expect(states[context]!.caseSensitive, isTrue);
          expect(states[context]!.isCollapsed('$context.dart'), isTrue);
          expect(calls[context], 2);
        }
      }
      await tester.tap(find.text('worktree-a.dart'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('match in worktree-a', findRichText: true));
      expect(opened, [('worktree-a', 'worktree-a.dart', 7)]);
      update(() => id = 'new-worktree');
      await tester.pumpAndSettle();
      await tester.tap(find.byIcon(Icons.search));
      await tester.pumpAndSettle();
      expect(states[id]!.query.text, isEmpty);
      expect(calls.containsKey(id), isFalse);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      for (final state in states.values) {
        state.dispose();
      }
      focus.dispose();
    },
  );
}
