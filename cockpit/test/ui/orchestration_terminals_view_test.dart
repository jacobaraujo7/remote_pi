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
import 'package:cockpit/app/cockpit/domain/entities/orchestration_presentation.dart';
import 'package:cockpit/app/cockpit/domain/entities/workspace_graph.dart';
import 'package:cockpit/app/cockpit/ui/services/orchestration_controller.dart';
import 'package:cockpit/app/cockpit/ui/session/orchestration_session.dart';
import 'package:cockpit/app/cockpit/ui/session/terminal_session.dart';
import 'package:cockpit/app/cockpit/ui/states/pane_node.dart';
import 'package:cockpit/app/cockpit/ui/widgets/orchestration_terminals_view.dart';
import 'package:cockpit/app/cockpit/ui/widgets/orchestration_view.dart';
import 'package:cockpit/app/cockpit/ui/widgets/workspace_box_inspector.dart';
import 'package:cockpit/app/cockpit/domain/contracts/process_metrics_provider.dart';
import 'package:cockpit/app/core/ui/widgets/app_tooltip.dart';
import 'package:cockpit/app/core/ui/overlay/app_popover_handler.dart';
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
      onStartCli: (boxId) async {
        startedBoxes.add(
          app.context.graphBoxes.singleWhere((box) => box.id == boxId),
        );
        return Success(boxId);
      },
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
  final startedBoxes = <GraphBox>[];
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
      popoverHandler: const AppPopoverOverlayHandler(),
      menuHandler: const AppPopoverOverlayHandler(),
      tooltipHandler: const AppPopoverOverlayHandler(),
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

class _UnusedMetrics implements ProcessMetricsProvider {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  testWidgets('ordinary shell does not show Start CLI', (tester) async {
    final fixture = _Fixture('ordinary-shell', TerminalEngine.xterm);
    addTearDown(fixture.app.dispose);
    await fixture.app.controller.load();
    final session = fixture.app.terminals.session('ordinary-shell-one')!;
    expect(session.isPlainShell, isTrue);
    await tester.pumpWidget(
      _keyboardHost(
        TerminalSessionView(
          session: session,
          active: true,
          focused: true,
          focusRevision: 0,
          onFocus: () {},
          onOpenFile: (_, {line}) {},
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text(t.workspaceView.tool), findsNothing);
    expect(find.text(t.workspaceView.startCli), findsNothing);
    await tester.pumpWidget(const SizedBox());
    unawaited(fixture.app.dispose());
  });

  testWidgets('plain shell launches the selected CLI with default options', (
    tester,
  ) async {
    final fixture = _Fixture('shell-cli', TerminalEngine.xterm);
    addTearDown(fixture.app.dispose);
    await fixture.app.controller.load();
    final id = '${fixture.app.id}-one';
    fixture.app.context.focusTerminalTab(id);
    await tester.pumpWidget(
      _keyboardHost(
        OrchestrationTerminalsView(
          session: fixture.app,
          active: true,
          focused: true,
        ),
      ),
    );
    await tester.pumpAndSettle();
    final start = find.ancestor(
      of: find.text(t.workspaceView.startCli),
      matching: find.byType(OutlineButton),
    );
    expect(tester.widget<OutlineButton>(start).onPressed, isNull);
    await tester.tap(find.text(t.workspaceView.tool));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Claude Code'));
    await tester.pumpAndSettle();
    expect(fixture.gateways[id]!.text, isEmpty);
    await tester.tap(start);
    await tester.pump();
    expect(fixture.gateways[id]!.text, 'claude\r');
    expect(tester.widget<OutlineButton>(start).onPressed, isNull);
    expect(fixture.gateways['${fixture.app.id}-two']!.text, isEmpty);
    expect(fixture.app.context.graphBoxForTab(id)!.harness, isEmpty);
    fixture.app.terminals
        .session(id)!
        .applyClaudeStatus(status: TerminalStatus.working, isTurnStart: true);
    await tester.pump();
    expect(start, findsNothing);
    await tester.pumpWidget(const SizedBox());
    unawaited(fixture.app.dispose());
  });

  for (final mode in OrchestrationViewMode.values) {
    testWidgets('new terminal exposes Start CLI in ${mode.name}', (
      tester,
    ) async {
      final fixture = _Fixture('start-cli', TerminalEngine.xterm);
      addTearDown(fixture.app.dispose);
      await fixture.app.controller.load();
      fixture.app.context.setWorkspaceView(mode);
      await tester.pumpWidget(
        _keyboardHost(
          OrchestrationView(
            session: fixture.app,
            active: true,
            processMetrics: _UnusedMetrics(),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(
        find
            .byWidgetPredicate(
              (widget) =>
                  widget is AppTooltip &&
                  widget.message == t.workspaceView.newTerminal,
            )
            .hitTestable(),
      );
      await tester.pumpAndSettle();

      final inspector = find.byType(WorkspaceBoxInspector);
      expect(inspector, findsOneWidget);
      final form = tester.widget<WorkspaceBoxInspector>(inspector);
      expect(form.box.title, 'Terminal 3');
      expect(fixture.startedBoxes, isEmpty);
      expect(fixture.app.terminals.sessions, hasLength(3));

      final start = find.descendant(
        of: inspector,
        matching: find.ancestor(
          of: find.text(t.workspaceView.startCli),
          matching: find.byType(OutlineButton),
        ),
      );
      expect(tester.widget<OutlineButton>(start).onPressed, isNull);
      final tool = find.descendant(of: inspector, matching: find.text('codex'));
      await tester.ensureVisible(tool);
      await tester.tap(tool);
      await tester.pumpAndSettle();
      await tester.tap(start);
      await tester.pumpAndSettle();

      expect(fixture.startedBoxes, hasLength(1));
      expect(fixture.startedBoxes.single.id, form.box.id);
      expect(fixture.startedBoxes.single.harness, 'codex');
      expect(fixture.app.terminals.sessions, hasLength(3));
      expect(inspector, findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      unawaited(fixture.app.dispose());
    });
  }

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
