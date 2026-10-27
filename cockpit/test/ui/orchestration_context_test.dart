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
  _Document(this.id) {
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
        final t = TerminalSession(
          id: '$id-session-${++created}',
          owner: mux.owner,
          projectId: 'same-worktree',
          workingDirectory: '/worktree',
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

void main() {
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
