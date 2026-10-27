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
