import 'package:cockpit/app/core/ui/overlay/app_popover_handler.dart';
import 'package:cockpit/app/cockpit/domain/entities/workspace_graph.dart';
import 'package:cockpit/app/cockpit/ui/widgets/workspace_box_list.dart';
import 'package:cockpit/app/core/ui/themes/themes.dart';
import 'package:cockpit/i18n/strings.g.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const entries = [
    WorkspaceBoxEntry(
      box: GraphBox(
        id: 'b',
        title: 'Backend',
        role: 'Implement API',
        harness: 'codex',
        model: '',
        position: Offset.zero,
      ),
      status: WorkspaceBoxStatus.working,
      tool: 'codex',
    ),
    WorkspaceBoxEntry(
      box: GraphBox(
        id: 'a',
        title: 'Alpha',
        role: 'Review accessibility',
        harness: '',
        model: '',
        position: Offset.zero,
      ),
      status: WorkspaceBoxStatus.shell,
      tool: '',
    ),
  ];
  testWidgets('narrow boxes show live CLI and attention without refresh', (
    tester,
  ) async {
    var tool = 'Codex';
    var status = WorkspaceBoxStatus.waiting;
    var unseen = true;
    late StateSetter update;
    await tester.pumpWidget(
      TranslationProvider(
        child: ShadcnApp(
          theme: buildTheme(brightness: Brightness.dark),
          home: Scaffold(
            child: Align(
              alignment: Alignment.topLeft,
              child: SizedBox(
                width: 360,
                height: 500,
                child: StatefulBuilder(
                  builder: (_, setState) {
                    update = setState;
                    return WorkspaceBoxList(
                      entries: [
                        WorkspaceBoxEntry(
                          box: entries.first.box,
                          status: status,
                          tool: tool,
                          unseen: unseen,
                        ),
                      ],
                      onSelect: (_) {},
                      onOpen: (_) {},
                      onConfigure: (_) {},
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
    expect(find.text('Codex'), findsOneWidget);
    expect(find.byIcon(Icons.notification_important_outlined), findsOneWidget);
    update(() {
      tool = 'Claude Code';
      status = WorkspaceBoxStatus.idle;
    });
    await tester.pumpAndSettle();
    expect(find.text('Claude Code'), findsOneWidget);
    expect(find.byIcon(Icons.notifications_active_outlined), findsOneWidget);
    update(() => unseen = false);
    await tester.pumpAndSettle();
    expect(find.byIcon(Icons.notifications_active_outlined), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
  test('search matches function and sorting is case independent', () {
    expect(filterWorkspaceBoxes(entries).map((e) => e.box.id), ['a', 'b']);
    expect(
      filterWorkspaceBoxes(entries, search: 'ACCESSIBILITY').single.box.id,
      'a',
    );
    expect(
      filterWorkspaceBoxes(
        entries,
        status: WorkspaceBoxStatus.working,
      ).single.box.id,
      'b',
    );
    expect(filterWorkspaceBoxes(entries, search: 'missing'), isEmpty);
  });
  test('custom ordering survives rename and ignores stale IDs', () {
    expect(
      filterWorkspaceBoxes(
        entries,
        order: ['deleted', 'b', 'a'],
      ).map((e) => e.box.id),
      ['b', 'a'],
    );
    expect(filterWorkspaceBoxes(entries, order: ['b']).map((e) => e.box.id), [
      'b',
      'a',
    ]);
    expect(
      reorderWorkspaceBoxIds(['a', 'hidden', 'b', 'c'], ['a', 'b', 'c'], 0, 2),
      ['b', 'hidden', 'c', 'a'],
    );
    expect(
      reorderWorkspaceBoxIds(['a', 'hidden', 'b', 'c'], ['a', 'b', 'c'], 2, 0),
      ['c', 'hidden', 'a', 'b'],
    );
  });
  testWidgets(
    'dragging the handle reorders without selecting or opening a terminal',
    (tester) async {
      var order = <String>[];
      var selections = 0;
      var opens = 0;
      var configurations = 0;
      late StateSetter rebuild;
      await tester.pumpWidget(
        TranslationProvider(
          child: ShadcnApp(
            theme: buildTheme(brightness: Brightness.dark),
            home: Scaffold(
              child: StatefulBuilder(
                builder: (context, setState) {
                  rebuild = setState;
                  return WorkspaceBoxList(
                    entries: entries,
                    boxOrder: order,
                    onReorder: (value) => rebuild(() => order = value),
                    onSelect: (_) => selections++,
                    onOpen: (_) => opens++,
                    onConfigure: (_) => configurations++,
                  );
                },
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      Future<void> dragHandle(Finder handle, double dy) async {
        final gesture = await tester.startGesture(tester.getCenter(handle));
        await gesture.moveBy(Offset(0, dy.sign * 20));
        await tester.pump();
        for (var step = 0; step < 10; step++) {
          await gesture.moveBy(Offset(0, dy / 10));
          await tester.pump(const Duration(milliseconds: 16));
        }
        await tester.pump(const Duration(milliseconds: 350));
        await gesture.up();
      }

      final handles = find.byType(ReorderableDragStartListener);
      await dragHandle(handles.first, 100);
      await tester.pumpAndSettle();
      expect(order, ['b', 'a']);
      expect(
        tester.getTopLeft(find.byKey(const ValueKey('box-row-b'))).dy,
        lessThan(tester.getTopLeft(find.byKey(const ValueKey('box-row-a'))).dy),
      );
      await dragHandle(find.byType(ReorderableDragStartListener).last, -100);
      await tester.pumpAndSettle();
      expect(order, ['a', 'b']);
      expect(selections, 0);
      expect(opens, 0);
      expect(configurations, 0);
      expect(tester.takeException(), isNull);
    },
  );
  for (final brightness in Brightness.values) {
    for (final width in [540.0, 1440.0]) {
      testWidgets('list actions and layout at $width / $brightness', (
        tester,
      ) async {
        tester.view.resetPhysicalSize();
        tester.view.physicalSize = Size(width, 650);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        String? selected;
        String? configured;
        var opened = 0;
        await tester.pumpWidget(
          TranslationProvider(
            child: ShadcnApp(
              theme: buildTheme(brightness: brightness),
              popoverHandler: const AppPopoverOverlayHandler(),
              menuHandler: const AppPopoverOverlayHandler(),
              home: Scaffold(
                child: WorkspaceBoxList(
                  entries: entries,
                  onSelect: (id) => selected = id,
                  onOpen: (_) => opened++,
                  onConfigure: (id) => configured = id,
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.text('Backend'));
        await tester.pump(const Duration(milliseconds: 350));
        expect(selected, 'b');
        expect(opened, 0);
        expect(configured, isNull);
        await tester.tap(find.text('Backend'));
        await tester.pump(const Duration(milliseconds: 70));
        await tester.tap(find.text('Backend'));
        await tester.pumpAndSettle();
        expect(opened, 1);
        await tester.tap(find.byIcon(Icons.filter_list));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Working').last);
        await tester.pumpAndSettle();
        expect(find.text('Alpha'), findsNothing);
        expect(find.text('Backend'), findsOneWidget);
        expect(opened, 1);
        expect(configured, isNull);
        expect(tester.takeException(), isNull);
      });
    }
  }
}
