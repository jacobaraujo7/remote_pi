import 'package:shadcn_flutter/shadcn_flutter.dart';
import 'package:flutter/gestures.dart' show PointerDeviceKind;
import 'package:cockpit/app/cockpit/ui/widgets/workspace_graph_view.dart';
import 'package:cockpit/app/cockpit/domain/contracts/process_metrics_provider.dart';
import 'package:cockpit/app/cockpit/domain/entities/process_metrics_snapshot.dart';
import 'package:cockpit/app/core/ui/themes/themes.dart';
import 'package:cockpit/i18n/strings.g.dart';
import 'dart:async';
import 'package:cockpit/app/cockpit/ui/states/pane_node.dart';
import 'package:cockpit/app/core/domain/entities/harness.dart';
import 'package:cockpit/app/cockpit/domain/contracts/terminal_status_server.dart';
import 'package:cockpit/app/cockpit/domain/entities/orchestration_document.dart';
import 'package:cockpit/app/cockpit/domain/entities/orchestration_presentation.dart';
import 'package:cockpit/app/cockpit/domain/entities/workspace_graph.dart';
import 'package:cockpit/app/cockpit/ui/services/orchestration_controller.dart';
import 'package:cockpit/app/cockpit/ui/session/terminal_session.dart';
import 'package:cockpit/app/cockpit/ui/viewmodels/orchestration_context.dart';
import 'package:cockpit/app/cockpit/ui/viewmodels/orchestration_multiplexer.dart';
import 'package:cockpit/app/core/domain/entities/terminal_profile.dart';
import 'package:cockpit/app/core/domain/result.dart';
import 'package:flutter_test/flutter_test.dart';
import '../support/attachment_terminal_gateway.dart';

OrchestrationBox _box(String id) => OrchestrationBox(
  box: GraphBox(
    id: id,
    title: id,
    role: '',
    harness: '',
    model: '',
    position: Offset.zero,
  ),
);

class _Document {
  _Document(
    this.id, {
    Future<Set<String>> Function(TerminalSession)? readAliases,
    bool remote = false,
    bool attachTerminals = true,
  }) {
    mux = OrchestrationMultiplexer(instanceId: id, projectId: 'same-worktree');
    controller = OrchestrationController(
      read: () async => disk,
      write: (text) async {
        disk = text;
      },
      newBoxId: () => 'unused',
      terminals: () => [
        for (final t in mux.sessions.values)
          OrchestrationTerminal(t.id, t.displayTitle, '.'),
      ],
      createShell: (box) async {
        if (!attachTerminals) return '$id-session-${++created}';
        final t = TerminalSession(
          id: '$id-session-${++created}',
          owner: mux.owner,
          projectId: 'same-worktree',
          workingDirectory: '/worktree',
          attachmentsRemote: remote,
          gateway: AttachmentTerminalGateway(),
          profile: const TerminalProfile(
            id: 'shell',
            label: 'Shell',
            executable: 'sh',
          ),
        );
        t.onTurnFinished = () => mux.turnFinished(t);
        mux.attach(t, focus: false);
        return t.id;
      },
      closeTerminal: (tabId) async {
        await mux.detach(tabId)?.dispose();
      },
    );
    context = OrchestrationContext(
      instanceId: id,
      projectId: 'same-worktree',
      controller: controller,
      terminals: mux,
      title: () => '$id.orchestration',
      onPersist: () => saves++,
      readAliases: readAliases,
      onOpenShell: (box) async {
        shells++;
        return Success(box);
      },
      onStartCli: (box) async {
        starts++;
        return Success(box);
      },
      onHandoff: (box) async {
        handoffs++;
        return Success(box);
      },
    );
  }
  final String id;
  int created = 0, saves = 0, shells = 0, starts = 0, handoffs = 0;
  String disk = OrchestrationDocument(
    boxes: [_box('shared'), _box('second')],
  ).encode();
  late final OrchestrationController controller;
  late final OrchestrationMultiplexer<TerminalSession> mux;
  late final OrchestrationContext context;
  Future<void> dispose() async {
    await controller.settle();
    context.dispose();
    controller.dispose();
    final sessions = mux.sessions.values.toList();
    mux.dispose();
    for (final t in sessions) {
      await t.dispose();
    }
  }
}

class _NoProcessMetrics implements ProcessMetricsProvider {
  @override
  Future<ProcessMetricsSnapshot> read(int pid) async => ProcessMetricsSnapshot(
    pid: pid,
    cpuPercent: null,
    rssBytes: null,
    collectedAt: DateTime.fromMillisecondsSinceEpoch(0),
    source: 'test',
  );
}

void main() {
  testWidgets(
    'graph clicks persist a planned connection only in its document',
    (tester) async {
      final a = _Document('graph-a', attachTerminals: false),
          b = _Document('graph-b', attachTerminals: false);
      addTearDown(() async {
        await tester.pumpWidget(const SizedBox());
        // This UI fixture has no native sessions; dispose its pure state here.
        for (final doc in [a, b]) {
          doc.context.dispose();
          doc.controller.dispose();
          doc.mux.dispose();
        }
        await tester.pump();
      });
      a.disk = OrchestrationDocument(
        boxes: [
          for (final (i, id) in ['shared', 'second'].indexed)
            OrchestrationBox(
              box: _box(id).box.copyWith(position: Offset(80 + i * 300, 190)),
            ),
        ],
      ).encode();
      await a.controller.load();
      await b.controller.load();
      final otherDisk = b.disk;
      final opened = <String>[];
      tester.view.physicalSize = const Size(1100, 700);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        TranslationProvider(
          child: ShadcnApp(
            theme: buildTheme(brightness: Brightness.dark),
            home: Scaffold(
              child: ListenableBuilder(
                listenable: a.context,
                builder: (context, _) => WorkspaceGraphView(
                  vm: a.context,
                  processMetrics: _NoProcessMetrics(),
                  embedded: true,
                  selectedBoxId: a.context.selectedWorkspaceBox?.id,
                  onSelectBox: (id) {
                    a.context.selectWorkspaceBox(id);
                    a.context.revealBox(id, focus: false);
                  },
                  onExit: () {},
                  onOpenTab: opened.add,
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(
        find.text(t.workspaceView.linkBoxes),
        kind: PointerDeviceKind.mouse,
      );
      await tester.pump();
      await tester.tap(find.text('shared'), kind: PointerDeviceKind.mouse);
      await tester.pump(const Duration(milliseconds: 16));
      // Repeating the source must neither cancel linking nor open its terminal.
      await tester.tap(find.text('shared'), kind: PointerDeviceKind.mouse);
      // Pausing on the source must not open a tooltip over the target click.
      await tester.pump(const Duration(milliseconds: 600));
      await tester.tap(find.text('second'), kind: PointerDeviceKind.mouse);
      await tester.pumpAndSettle();
      await a.controller.settle();
      expect(a.context.graphLinks.map((l) => (l.from, l.to)), [
        ('shared', 'second'),
      ]);
      expect(OrchestrationDocument.parse(a.disk).links.length, 1);
      expect(b.disk, otherDisk);
      expect(a.created, 2);
      expect(a.starts + b.starts, 0);
      expect(opened, isEmpty);
      await tester.tap(find.text('second'), kind: PointerDeviceKind.mouse);
      await tester.pump(const Duration(milliseconds: 80));
      await tester.tap(find.text('second'), kind: PointerDeviceKind.mouse);
      await tester.pumpAndSettle();
      expect(opened, [a.controller.bindings['second']]);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );

  test(
    'internal navigation updates only its own selection, and splitting preserves the selected source tab',
    () async {
      final a = _Document('navigation-a'), b = _Document('navigation-b');
      addTearDown(a.dispose);
      addTearDown(b.dispose);
      await Future.wait([a.controller.load(), b.controller.load()]);
      final first = a.controller.bindings['shared']!;
      final second = a.controller.bindings['second']!;
      final beforeB = b.mux.tree;
      a.context.selectTerminalTabByIndex(1);
      expect(a.mux.keyboardTabId, second);
      expect(a.context.selectedWorkspaceBox?.id, 'second');
      a.context.cycleTerminalTab(1);
      expect(a.mux.keyboardTabId, first);
      a.context.selectLastTerminalTab();
      expect(a.mux.keyboardTabId, second);
      a.context.focusTerminalTab(first);
      final sourcePane = a.mux.paneOf(first)!.id;
      final result = await a.context.newTerminal(split: SplitDir.vertical);
      expect(result, isA<Success<String, String>>());
      expect(findLeaf(a.mux.tree!, sourcePane)!.active, first);
      final newId = (result as Success<String, String>).value;
      expect(a.mux.keyboardTabId, newId);
      a.context.focusTerminalPaneToward(PaneMove.left);
      expect(a.mux.keyboardTabId, first);
      expect(a.context.selectedWorkspaceBox?.id, 'shared');
      a.context.selectTerminalTabByIndex(99);
      expect(a.mux.keyboardTabId, first);
      expect(b.mux.tree, same(beforeB));
      expect(b.created, 2);
      expect(a.starts + b.starts, 0);
    },
  );

  test(
    'external new definitions create a blank shell without selecting it or moving keyboard input',
    () async {
      final a = _Document('external-definition');
      addTearDown(a.dispose);
      await a.controller.load();
      a.context.selectTerminalTabByIndex(0);
      final selected = a.mux.keyboardTabId;
      final pane = a.mux.focusedPaneId!;
      a.disk = OrchestrationDocument(
        boxes: [_box('shared'), _box('second'), _box('external')],
      ).encode();
      await a.controller.load();
      expect(a.created, 3);
      expect(a.mux.keyboardTabId, selected);
      expect(findLeaf(a.mux.tree!, pane)!.active, selected);
      expect(a.context.selectedWorkspaceBox?.id, 'shared');
      expect(a.starts, 0);
    },
  );

  test(
    'remote CLI comes from its own main hooks and clears on end, not configuration or child hooks',
    () async {
      final remote = _Document('remote', remote: true);
      final local = _Document('local');
      addTearDown(remote.dispose);
      addTearDown(local.dispose);
      await Future.wait([remote.controller.load(), local.controller.load()]);
      final t = remote.mux.sessions.values.first;
      expect(t.activeHarness, isNull);
      remote.context.applyHook(
        ClaudeStatusUpdate(
          paneId: t.id,
          status: 'working',
          event: 'UserPromptSubmit',
          sessionId: 'codex-session',
          harness: 'codex',
        ),
      );
      expect(t.activeHarness, HarnessKind.codex);
      remote.context.applyHook(
        ClaudeStatusUpdate(
          paneId: t.id,
          status: 'subagent_start',
          subagentId: 'claude-child',
          harness: 'claude',
        ),
      );
      expect(t.activeHarness, HarnessKind.codex);
      remote.context.applyHook(
        ClaudeStatusUpdate(
          paneId: t.id,
          status: 'idle',
          event: 'SessionEnd',
          harness: 'codex',
        ),
      );
      expect(t.activeHarness, isNull);
      final localTerminal = local.mux.sessions.values.first;
      local.context.applyHook(
        ClaudeStatusUpdate(
          paneId: localTerminal.id,
          status: 'working',
          sessionId: 'local',
          harness: 'claude',
        ),
      );
      expect(
        localTerminal.activeHarness,
        isNull,
      ); // local process monitor remains authoritative
    },
  );

  test(
    'hooks update only their owned terminal and unread state, never another document',
    () async {
      final a = _Document('a'), b = _Document('b');
      addTearDown(a.dispose);
      addTearDown(b.dispose);
      await Future.wait([a.controller.load(), b.controller.load()]);
      final t = a.mux.sessions.values.first;
      final bSaved = b.saves, disk = a.disk;
      final working = ClaudeStatusUpdate(
        paneId: t.id,
        status: 'working',
        event: 'UserPromptSubmit',
        sessionId: 'sid-a',
        harness: 'claude',
      );
      expect(b.context.applyHook(working), isFalse);
      expect(a.context.applyHook(working), isTrue);
      expect(t.isWorking, isTrue);
      a.context.applyHook(
        ClaudeStatusUpdate(
          paneId: t.id,
          status: 'metric',
          sessionId: 'sid-a',
          contextTokens: 100,
          contextWindow: 200,
        ),
      );
      expect(t.reportedContextTokens, 100);
      a.context.applyHook(ClaudeStatusUpdate(paneId: t.id, status: 'waiting'));
      expect(t.status, TerminalStatus.waiting);
      a.context.applyHook(
        ClaudeStatusUpdate(paneId: t.id, status: 'idle', event: 'Stop'),
      );
      await Future<void>.delayed(const Duration(milliseconds: 80));
      expect(t.unseenFinish, isTrue);
      expect(
        b.mux.sessions.values.every((s) => !s.unseenFinish && !s.isWorking),
        isTrue,
      );
      expect(b.saves, bSaved);
      expect(a.disk, disk);
      expect(
        a.context.applyHook(
          const ClaudeStatusUpdate(paneId: 'outside', status: 'working'),
        ),
        isFalse,
      );
      expect(
        a.context.applyHook(
          ClaudeStatusUpdate(paneId: t.id, status: 'future-event'),
        ),
        isFalse,
      );
    },
  );

  test(
    'identical peer names in different apps cannot resolve each other',
    () async {
      final a = _Document('a'), b = _Document('b');
      addTearDown(a.dispose);
      addTearDown(b.dispose);
      await Future.wait([a.controller.load(), b.controller.load()]);
      final from = a.mux.sessions.values.first,
          target = a.mux.sessions.values.last;
      b.context.registerIdentity(b.mux.sessions.values.first.id, 'API');
      a.context.recordMessage(from.id, 'API');
      expect(a.context.graphTraffic, isEmpty);
      expect(a.context.graphUnresolvedPeers.length, 1);
      a.context.registerIdentity(target.id, 'api');
      expect(a.context.graphTraffic.single.toTabId, target.id);
      expect(a.context.graphUnresolvedPeers, isEmpty);
      expect(b.context.graphTraffic, isEmpty);
      a.context.registerIdentity(from.id, 'same');
      a.context.registerIdentity(target.id, 'same');
      a.context.recordMessage(from.id, 'same');
      expect(a.context.graphUnresolvedPeers.single.address, 'same');
      expect(a.context.graphTraffic.length, 1);
    },
  );

  test(
    'temporary children and conversation metrics reset only for the owning terminal',
    () async {
      final a = _Document('a');
      addTearDown(a.dispose);
      await a.controller.load();
      final t = a.mux.sessions.values.first, other = a.mux.sessions.values.last;
      a.context.applyHook(
        ClaudeStatusUpdate(paneId: t.id, status: 'idle', sessionId: 'parent'),
      );
      a.context.applyHook(
        ClaudeStatusUpdate(
          paneId: t.id,
          status: 'metric',
          sessionId: 'parent',
          contextTokens: 10,
          contextWindow: 100,
        ),
      );
      for (final terminal in [t, other]) {
        a.context.applyHook(
          ClaudeStatusUpdate(
            paneId: terminal.id,
            status: 'subagent_start',
            sessionId: 'child-conversation',
            subagentId: 'child',
            subagentType: 'reviewer',
            eventAt: DateTime(2026),
          ),
        );
      }
      expect(t.claudeSessionId, 'parent');
      expect(t.reportedContextTokens, 10);
      expect(a.context.graphSubagents.length, 2);
      a.context.applyHook(
        ClaudeStatusUpdate(paneId: t.id, status: 'idle', event: 'SessionEnd'),
      );
      expect(a.context.graphSubagents.single.ownerTabId, other.id);
      expect(
        a.context.applyHook(
          ClaudeStatusUpdate(
            paneId: t.id,
            status: 'subagent_start',
            subagentId: 'late',
          ),
        ),
        isFalse,
      );
      a.context.applyHook(
        ClaudeStatusUpdate(
          paneId: t.id,
          status: 'working',
          event: 'UserPromptSubmit',
          sessionId: 'new-conversation',
        ),
      );
      expect(t.reportedContextTokens, isNull);
      expect(
        a.context.applyHook(
          ClaudeStatusUpdate(
            paneId: t.id,
            status: 'metric',
            sessionId: 'parent',
            contextTokens: 999,
            contextWindow: 1000,
          ),
        ),
        isFalse,
      );
      expect(t.reportedContextTokens, isNull);
    },
  );

  test(
    'late transcript reply after SessionEnd cannot recreate an alias or edge',
    () async {
      final reply = Completer<Set<String>>();
      var reads = 0;
      final a = _Document(
        'a',
        readAliases: (_) {
          reads++;
          return reply.future;
        },
      );
      addTearDown(a.dispose);
      await a.controller.load();
      final t = a.mux.sessions.values.first,
          source = a.mux.sessions.values.last;
      t.applyClaudeStatus(
        status: TerminalStatus.idle,
        sessionId: 'sid',
        transcriptPath: '/only-owned.jsonl',
        harness: AgentHarness.claude,
      );
      final pending = a.context.reconcileIdentities();
      expect(reads, 1);
      a.context.applyHook(
        ClaudeStatusUpdate(paneId: t.id, status: 'idle', event: 'SessionEnd'),
      );
      reply.complete({'gone'});
      await pending;
      a.context.recordMessage(source.id, 'gone');
      await Future<void>.delayed(Duration.zero);
      expect(reads, 1);
      expect(a.context.graphTraffic, isEmpty);
      expect(a.context.graphUnresolvedPeers.single.address, 'gone');
    },
  );

  test(
    'detaching a terminal removes its aliases, traffic and temporary children',
    () async {
      final a = _Document('a');
      addTearDown(a.dispose);
      await a.controller.load();
      final t = a.mux.sessions.values.first,
          target = a.mux.sessions.values.last;
      a.context.registerIdentity(t.id, 'self');
      a.context.recordMessage(target.id, 'self');
      a.context.applyHook(
        ClaudeStatusUpdate(
          paneId: t.id,
          status: 'subagent_start',
          subagentId: 'child',
        ),
      );
      a.mux.detach(t.id);
      await t.dispose();
      expect(a.context.graphSubagents, isEmpty);
      expect(a.context.graphTraffic, isEmpty);
      a.context.recordMessage(target.id, 'self');
      expect(a.context.graphUnresolvedPeers.single.address, 'self');
    },
  );

  test(
    'same IDs in two documents never share selection, terminal bindings or edits',
    () async {
      final a = _Document('a'), b = _Document('b');
      await Future.wait([a.controller.load(), b.controller.load()]);
      expect(a.context.graphBoxes.first.id, b.context.graphBoxes.first.id);
      expect(
        a.context.graphBoxes.first.tabId,
        isNot(b.context.graphBoxes.first.tabId),
      );
      final diskB = b.disk, savedB = b.saves;
      a.mux.setActive(true);
      a.context.openBoxInTerminals('second');
      await a.context.configureBox(
        'shared',
        title: 'Renamed',
        role: 'API',
        harness: 'codex',
        model: 'model',
      );
      a.context.addGraphLink('shared', 'second');
      a.context.moveGraphBox('shared', const Offset(80, 150));
      await a.controller.settle();
      expect(a.context.selectedWorkspaceBox!.id, 'second');
      expect(b.context.selectedWorkspaceBox!.id, 'shared');
      expect(b.disk, diskB);
      expect(b.saves, savedB);
      expect(a.context.graphBoxes.first.title, 'Renamed');
      expect(
        a.mux.session(a.controller.bindings['shared']!)!.displayTitle,
        'Renamed',
      );
      expect(a.context.graphLinks.length, 1);
      expect(a.starts + b.starts + a.handoffs + b.handoffs, 0);
      await a.dispose();
      await b.dispose();
    },
  );

  test(
    'scoped lookup and session actions reject outside terminals/workspaces',
    () async {
      final a = _Document('a'), b = _Document('b');
      await Future.wait([a.controller.load(), b.controller.load()]);
      final foreign = b.mux.sessions.values.first;
      expect(a.context.session(foreign.id), isNull);
      expect(a.context.graphBoxForTab(foreign.id), isNull);
      expect(
        () => a.context.ensureGraphBoxForTab(foreign, Offset.zero),
        throwsArgumentError,
      );
      expect(await a.context.relaunchGraphBox('missing'), isA<Failure>());
      expect(
        await a.context.relaunchGraphBox('shared', workspaceId: 'other'),
        isA<Failure>(),
      );
      expect(a.starts + b.starts, 0);
      await a.context.relaunchGraphBox('shared');
      expect(a.starts, 1);
      expect(b.starts, 0);
      await a.dispose();
      await b.dispose();
    },
  );

  test(
    'planned links, observed traffic, peers and children stay within owner',
    () async {
      final a = _Document('a'), b = _Document('b');
      await Future.wait([a.controller.load(), b.controller.load()]);
      final first = a.controller.bindings['shared']!,
          second = a.controller.bindings['second']!;
      final foreign = b.controller.bindings['shared']!;
      a.context.recordTraffic(first, foreign);
      a.context.recordTraffic(foreign, first);
      expect(a.context.graphTraffic, isEmpty);
      a.context.recordTraffic(first, second);
      expect(a.context.graphTraffic.length, 1);
      for (final parent in [foreign, first]) {
        a.context.startSubagent(
          GraphSubagent(
            projectId: 'same-worktree',
            ownerTabId: parent,
            agentId: 'child',
            agentType: 'worker',
            harness: 'codex',
            startedAt: DateTime(2026),
          ),
        );
        a.context.recordPeer(
          GraphUnresolvedPeer(
            projectId: 'same-worktree',
            ownerTabId: parent,
            address: 'peer',
            observedAt: DateTime(2026),
          ),
        );
      }
      expect(a.context.graphSubagents.map((c) => c.ownerTabId), [first]);
      expect(a.context.graphUnresolvedPeers.map((c) => c.ownerTabId), [first]);
      expect(b.context.graphTraffic, isEmpty);
      expect(b.context.graphSubagents, isEmpty);
      expect(b.context.graphUnresolvedPeers, isEmpty);
      await a.mux.detach(first)!.dispose();
      expect(a.context.graphTraffic, isEmpty);
      expect(a.context.graphSubagents, isEmpty);
      expect(a.context.graphUnresolvedPeers, isEmpty);
      await a.dispose();
      await b.dispose();
    },
  );

  test(
    'queued reorder, move and inspector save preserve all three edits',
    () async {
      final a = _Document('a');
      await a.controller.load();
      a.context.updatePresentation(
        a.context.presentation.copyWith(boxOrder: ['second', 'shared']),
      );
      a.context.moveGraphBox('shared', const Offset(125, 200));
      final configured = a.context.configureBox(
        'shared',
        title: 'API',
        role: 'new role',
        harness: '',
        model: '',
        directory: 'src',
      );
      await configured;
      await a.controller.settle();
      final doc = OrchestrationDocument.parse(a.disk);
      expect(doc.boxes.map((b) => b.box.id), ['second', 'shared']);
      expect(doc.boxes.last.box.position, const Offset(125, 200));
      expect(doc.boxes.last.box.title, 'API');
      expect(doc.boxes.last.directory, 'src');
      expect(a.created, 2);
      expect(a.starts, 0);
      await a.dispose();
    },
  );

  test(
    'new terminal creates only an owned blank shell and leaves other document unchanged',
    () async {
      final a = _Document('a'), b = _Document('b');
      await Future.wait([a.controller.load(), b.controller.load()]);
      final before = b.disk;
      expect(await a.context.newTerminal(), isA<Success>());
      expect(a.created, 3);
      expect(b.created, 2);
      expect(b.disk, before);
      expect(a.context.selectedWorkspaceBox!.title, 'Terminal 3');
      expect(a.starts + a.handoffs + a.shells, 0);
      expect(
        a.mux.sessions.values.every((t) => t.owner == a.mux.owner),
        isTrue,
      );
      expect(a.disk, isNot(contains('session-')));
      await a.dispose();
      await b.dispose();
    },
  );

  test(
    'invalid directory/configuration/position cannot spawn or overwrite the file',
    () async {
      final a = _Document('a');
      await a.controller.load();
      final disk = a.disk;
      expect(
        await a.context.configureBox(
          'shared',
          role: '',
          harness: '',
          model: '',
          directory: '../outside',
        ),
        isA<Failure>(),
      );
      expect(a.disk, disk);
      expect(a.created, 2);
      expect(
        await a.context.createGraphBox(
          title: 'bad',
          role: '',
          harness: '',
          model: '',
          position: Offset(double.nan, 0),
        ),
        isA<Failure>(),
      );
      expect(a.created, 2);
      expect(a.disk, disk);
      await a.dispose();
    },
  );

  test(
    'mode and panel dimensions belong to local presentation, not the portable file',
    () async {
      final a = _Document('a'), b = _Document('b');
      await Future.wait([a.controller.load(), b.controller.load()]);
      final disk = a.disk;
      a.context.updatePresentation(
        a.context.presentation.copyWith(
          mode: OrchestrationViewMode.graph,
          inspectorOpen: true,
          inspectorWidth: 420,
          graphTerminalFraction: .45,
        ),
      );
      expect(a.context.presentation.terminalFraction, .45);
      expect(b.context.presentation.terminalFraction, .6);
      expect(b.context.presentation.inspectorOpen, isFalse);
      expect(
        OrchestrationPresentation.fromJson(
          a.context.presentation.toJson(),
        ).terminalFraction,
        .45,
      );
      expect(a.disk, disk);
      await a.dispose();
      await b.dispose();
    },
  );

  test(
    'disposed context rejects new actions and no longer forwards session changes',
    () async {
      final a = _Document('a');
      await a.controller.load();
      a.context.dispose();
      final saves = a.saves;
      a.mux.sessions.values.first.markUnseen();
      expect(a.saves, saves);
      expect(await a.context.newTerminal(), isA<Failure>());
      expect(await a.context.relaunchGraphBox('shared'), isA<Failure>());
      expect(a.created, 2);
      expect(a.starts, 0);
      await a.dispose();
    },
  );
}
