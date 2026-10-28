import 'package:cockpit/i18n/strings.g.dart';
import 'dart:async';
import 'dart:convert';
import 'package:cockpit_core/cockpit_core.dart';
import 'package:cockpit/app/cockpit/domain/contracts/file_change_watcher.dart';
import 'package:cockpit/app/cockpit/ui/document/worktree_document_host.dart';
import 'package:cockpit/app/cockpit/ui/session/orchestration_file_presentation.dart';
import 'package:cockpit/app/cockpit/ui/widgets/orchestration_document_area.dart';
import 'package:cockpit/app/cockpit/ui/widgets/terminal_session_view.dart';
import 'package:cockpit/app/core/ui/menu/editor_menu_bridge.dart';
import 'package:cockpit/app/core/domain/result.dart';
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
import 'package:flutter/services.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';
import '../support/attachment_terminal_gateway.dart';

class _Settings extends SettingsStore {
  @override
  Future<AppSettings> load() async => const AppSettings();
  @override
  Future<void> save(AppSettings settings) async {}
}

class _Fixture {
  _Fixture(
    String id,
    TerminalEngine engine, {
    Future<Result<OrchestrationFilePresentation, String>> Function(
      TerminalSession,
      String, {
      int? line,
    })?
    openFile,
  }) {
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
        final gateway = AttachmentTerminalGateway();
        final t = TerminalSession(
          id: '$id-${box.box.id}',
          owner: app.terminals.owner,
          projectId: 'same-worktree',
          workingDirectory: '/worktree',
          gateway: gateway,
          profile: const TerminalProfile(
            id: 'shell',
            label: 'Shell',
            executable: 'sh',
          ),
          engine: engine,
        );
        gateways[t.id] = gateway;
        app.terminals.attach(t, focus: false);
        return t.id;
      },
    );
    app = OrchestrationSession(
      id: id,
      projectId: 'same-worktree',
      path: '/worktree/$id.orchestration',
      controller: controller,
      onOpenFile: openFile,
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
  final gateways = <String, AttachmentTerminalGateway>{};
  String disk = '';
  late final OrchestrationSession app;
}

Widget _keyboardHost(Widget child) => ModularApp(
  module: createModule(register: (_) {}),
  provide: (scope) => scope
    ..addChangeNotifier<SettingsController>(
      () => SettingsController(_Settings()),
    )
    ..addChangeNotifier<EditorMenuBridge>(() => EditorMenuBridge()),
  child: TranslationProvider(
    child: ShadcnApp(
      theme: buildTheme(brightness: Brightness.dark),
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
      home: child,
    ),
  ),
);

void main() {
  for (final engine in TerminalEngine.values) {
    testWidgets(
      'owned file presentation preserves $engine terminal identity and keyboard',
      (tester) async {
        final host = WorktreeDocumentHost(
          workspaceRoot: '/worktree',
          changes: _FileChanges(),
          files: _DocumentFiles(),
          remote: true,
          available: () => true,
        );
        final fixture = _Fixture(
          'file-${engine.name}',
          engine,
          openFile: (terminal, file, {line}) async => Success(
            OrchestrationFilePresentation(
              id: 'private-file',
              path: file,
              terminalId: terminal.id,
              host: host,
              line: line,
            ),
          ),
        );
        await fixture.app.controller.load();
        fixture.app.setPresentationActive(true);
        fixture.app.context.focusTerminalTab('${fixture.app.id}-one');
        await tester.pumpWidget(
          _keyboardHost(
            OrchestrationDocumentArea(
              session: fixture.app,
              active: true,
              focused: true,
            ),
          ),
        );
        await tester.pump();
        fixture.app.terminals.splitTab(
          '${fixture.app.id}-two',
          SplitDir.vertical,
          anchorPaneId: fixture.app.terminals
              .paneOf('${fixture.app.id}-one')!
              .id,
        );
        fixture.app.context.focusTerminalTab('${fixture.app.id}-one');
        await tester.pump();
        final originalTree = fixture.app.terminals.tree;
        final originalModels = fixture.app.terminals.sessions.values.toList();
        final states = {
          for (final terminal in originalModels)
            terminal.id: tester.state(
              find.byKey(
                ValueKey((fixture.app.id, terminal.id)),
                skipOffstage: false,
              ),
            ),
        };
        final source = originalModels.first.id;
        expect(
          await fixture.app.openFile(source, '/worktree/note.txt'),
          isA<Success<String, String>>(),
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 50));
        expect(fixture.app.terminals.active, isFalse);
        expect(
          find.byType(TerminalSessionView, skipOffstage: false),
          findsNWidgets(2),
        );
        for (final terminal in originalModels) {
          expect(
            tester.state(
              find.byKey(
                ValueKey((fixture.app.id, terminal.id)),
                skipOffstage: false,
              ),
            ),
            same(states[terminal.id]),
          );
        }
        fixture.app.context.revealBox('two', focus: false);
        await tester.pump();
        expect(fixture.app.fileVisible, isFalse);
        expect(fixture.app.filePresentation, isNotNull);
        expect(fixture.app.terminals.keyboardTabId, isNull);
        fixture.app.showFile();
        await tester.pump();
        await tester.tap(
          find.byKey(ValueKey('owned-file-close-${fixture.app.id}')),
        );
        await tester.pump();
        await tester.pump();
        expect(fixture.app.filePresentation, isNull);
        expect(fixture.app.terminals.active, isTrue);
        expect(fixture.app.terminals.sessions.values.toList(), originalModels);
        expect(fixture.app.terminals.tree!.id, originalTree!.id);
        for (final terminal in originalModels) {
          expect(
            tester.state(
              find.byKey(
                ValueKey((fixture.app.id, terminal.id)),
                skipOffstage: false,
              ),
            ),
            same(states[terminal.id]),
          );
        }
        await tester.sendKeyEvent(LogicalKeyboardKey.enter);
        await tester.pump();
        expect(fixture.gateways[source]!.text, '\r');
        expect(fixture.gateways['${fixture.app.id}-two']!.text, isEmpty);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
        addTearDown(() => fixture.app.dispose());
      },
    );
  }

  for (final engine in TerminalEngine.values) {
    testWidgets(
      '${engine.name}: Ctrl-Tab stays internal and input reaches the selected terminal',
      (tester) async {
        tester.view.physicalSize = const Size(1200, 600);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final a = _Fixture('keyboard-a', engine),
            b = _Fixture('keyboard-b', engine);
        addTearDown(() async {
          await Future.wait([a.app.dispose(), b.app.dispose()]);
        });
        await Future.wait([a.app.controller.load(), b.app.controller.load()]);
        a.app.context.openBoxInTerminals('one');
        b.app.context.openBoxInTerminals('one');
        await tester.pumpWidget(
          _keyboardHost(
            Row(
              children: [
                Expanded(
                  child: OrchestrationTerminalsView(
                    session: a.app,
                    active: true,
                    focused: true,
                  ),
                ),
                Expanded(
                  child: OrchestrationTerminalsView(
                    session: b.app,
                    active: true,
                    focused: false,
                  ),
                ),
              ],
            ),
          ),
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 50));
        final otherTree = b.app.terminals.tree;
        await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
        await tester.sendKeyEvent(LogicalKeyboardKey.tab);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 50));
        expect(a.app.terminals.keyboardTabId, 'keyboard-a-two');
        expect(a.app.context.selectedWorkspaceBox?.id, 'two');
        await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
        await tester.sendKeyEvent(LogicalKeyboardKey.enter);
        expect(a.gateways['keyboard-a-two']!.text, '\r');
        expect(a.gateways['keyboard-a-one']!.text, isEmpty);
        await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
        await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
        await tester.sendKeyEvent(LogicalKeyboardKey.tab);
        await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
        await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 50));
        expect(a.app.terminals.keyboardTabId, 'keyboard-a-one');
        expect(b.app.terminals.tree, same(otherTree));
        expect(b.app.terminals.keyboardTabId, 'keyboard-b-one');
        await tester.sendKeyEvent(LogicalKeyboardKey.enter);
        expect(a.gateways['keyboard-a-one']!.text, '\r');
        expect(a.gateways['keyboard-a-two']!.text, '\r');
        for (final gateway in b.gateways.values) {
          expect(gateway.text, isEmpty);
        }
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();
      },
    );

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

class _DocumentFiles implements FileService {
  @override
  Future<Uint8List> read(String path, {int maxBytes = 8 * 1024 * 1024}) async =>
      Uint8List.fromList(utf8.encode('owned file'));
  @override
  Future<void> write(String path, Uint8List bytes) async {}
  @override
  Future<List<FileEntry>> list(String path) async => [];
  @override
  Future<String> home() async => '/worktree';
}

class _FileChanges implements FileChangeWatcher {
  @override
  Stream<void> watchFile(String path) => const Stream.empty();
  @override
  Stream<void> watchFolder(String path) => const Stream.empty();
}
