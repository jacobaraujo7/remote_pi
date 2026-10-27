import 'package:cockpit/app/cockpit/domain/entities/orchestration_document.dart';
import 'package:cockpit/app/cockpit/domain/entities/workspace_graph.dart';
import 'package:cockpit/app/cockpit/ui/services/orchestration_controller.dart';
import 'package:cockpit/app/cockpit/ui/session/orchestration_session.dart';
import 'package:cockpit/app/cockpit/ui/session/terminal_session.dart';
import 'package:cockpit/app/cockpit/ui/states/pane_node.dart';
import 'package:cockpit/app/cockpit/ui/widgets/orchestration_terminals_view.dart';
import 'package:cockpit/app/cockpit/ui/widgets/pane_view.dart' show TabDragData;
import 'package:cockpit/app/core/domain/contracts/settings_store.dart';
import 'package:cockpit/app/core/domain/entities/app_settings.dart';
import 'package:cockpit/app/core/domain/entities/terminal_profile.dart';
import 'package:cockpit/app/core/ui/settings_controller.dart';
import 'package:cockpit/app/core/ui/themes/themes.dart';
import 'package:flutter_modular/flutter_modular.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';
import '../support/attachment_terminal_gateway.dart';

class _Settings extends SettingsStore {
  @override
  Future<AppSettings> load() async => const AppSettings();
  @override
  Future<void> save(AppSettings settings) async {}
}

class _Fixture {
  _Fixture(String id, TerminalEngine engine) {
    final controller = OrchestrationController(
      read: () async => disk,
      write: (text) async {
        disk = text;
      },
      newBoxId: () => 'new-box',
      terminals: () => [
        for (final t in app.terminals.sessions.values)
          OrchestrationTerminal(t.id, t.displayTitle, '.'),
      ],
      closeTerminal: (_) async {},
      createShell: (box) async {
        final t = TerminalSession(
          id: '$id-${box.box.id}',
          owner: app.terminals.owner,
          projectId: 'same-worktree',
          workingDirectory: '/worktree',
          gateway: AttachmentTerminalGateway(),
          profile: const TerminalProfile(
            id: 'shell',
            label: 'Shell',
            executable: 'sh',
          ),
          engine: engine,
        );
        app.terminals.attach(t, focus: false);
        return t.id;
      },
    );
    app = OrchestrationSession(
      id: id,
      projectId: 'same-worktree',
      path: '/worktree/$id.orchestration',
      controller: controller,
    );
    disk = OrchestrationDocument(
      boxes: [
        for (final name in ['one', 'two'])
          OrchestrationBox(
            box: GraphBox(
              id: name,
              title: '$id-$name',
              role: '',
              harness: '',
              model: '',
              position: Offset.zero,
            ),
          ),
      ],
    ).encode();
  }
  String disk = '';
  late final OrchestrationSession app;
}

void main() {
  for (final engine in TerminalEngine.values) {
    testWidgets(
      '${engine.name}: internal drag never crosses owners or outer dock targets',
      (tester) async {
        tester.view.physicalSize = const Size(1200, 600);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final a = _Fixture('a', engine), b = _Fixture('b', engine);
        await Future.wait([a.app.controller.load(), b.app.controller.load()]);
        a.app.context.openBoxInTerminals('one');
        b.app.context.openBoxInTerminals('one');
        var outerDrops = 0;
        await tester.pumpWidget(
          ModularApp(
            module: createModule(register: (_) {}),
            provide: (scope) => scope
              ..addChangeNotifier<SettingsController>(
                () => SettingsController(_Settings()),
              ),
            child: ShadcnApp(
              builder: (context, child) {
                final tokens = buildTokens(
                  brightness: Brightness.dark,
                  settings: const AppSettings(),
                );
                return CockpitTheme(
                  colors: tokens.colors,
                  typo: tokens.typo,
                  syntax: tokens.syntax,
                  terminal: tokens.terminal,
                  child: child!,
                );
              },
              home: Row(
                children: [
                  Expanded(
                    child: OrchestrationTerminalsView(
                      key: const ValueKey('owner-a'),
                      session: a.app,
                      active: true,
                      focused: true,
                    ),
                  ),
                  Expanded(
                    child: OrchestrationTerminalsView(
                      key: const ValueKey('owner-b'),
                      session: b.app,
                      active: true,
                      focused: false,
                    ),
                  ),
                  SizedBox(
                    width: 120,
                    child: DragTarget<TabDragData>(
                      onWillAcceptWithDetails: (_) => true,
                      onAcceptWithDetails: (_) => outerDrops++,
                      builder: (_, _, _) =>
                          const SizedBox.expand(key: ValueKey('outer-target')),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
        await tester.pump();
        Future<void> drag(String label, Offset target) async {
          final gesture = await tester.startGesture(
            tester.getCenter(find.text(label)),
          );
          await gesture.moveBy(const Offset(20, 40));
          await tester.pump();
          await gesture.moveTo(target);
          await tester.pump();
          await gesture.up();
          // Let the header's double-tap recognizer release its arena timer.
          await tester.pump(const Duration(milliseconds: 400));
        }

        final treeA = a.app.terminals.serialize(),
            treeB = b.app.terminals.serialize();
        final native = tester.state(
          find.byKey(const ValueKey(('a', 'a-one')), skipOffstage: false),
        );
        await drag(
          'a-one',
          tester.getCenter(find.byKey(const ValueKey('owner-b'))),
        );
        expect(a.app.terminals.serialize(), treeA);
        expect(b.app.terminals.serialize(), treeB);
        await drag(
          'a-one',
          tester.getCenter(find.byKey(const ValueKey('outer-target'))),
        );
        expect(outerDrops, 0);
        expect(a.app.terminals.serialize(), treeA);
        final rect = tester.getRect(find.byKey(const ValueKey('owner-a')));
        await drag('a-two', rect.centerRight - const Offset(8, 0));
        expect(a.app.terminals.tree, isA<SplitPane>());
        expect(
          a.app.terminals.paneOf('a-one')!.id,
          isNot(a.app.terminals.paneOf('a-two')!.id),
        );
        expect(
          tester.state(
            find.byKey(const ValueKey(('a', 'a-one')), skipOffstage: false),
          ),
          same(native),
        );
        expect(b.app.terminals.serialize(), treeB);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
        await tester.runAsync(() async {
          await a.app.dispose();
          await b.app.dispose();
        });
      },
    );
  }
}
