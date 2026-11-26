import 'dart:convert';

import 'package:cockpit/app/cockpit/domain/contracts/terminal_status_server.dart';
import 'package:cockpit/app/cockpit/domain/entities/orchestration_document.dart';
import 'package:cockpit/app/cockpit/domain/entities/workspace_graph.dart';
import 'package:cockpit/app/cockpit/ui/services/orchestration_controller.dart';
import 'package:cockpit/app/cockpit/ui/session/orchestration_session.dart';
import 'package:cockpit/app/cockpit/ui/session/pane_item.dart';
import 'package:cockpit/app/cockpit/ui/session/terminal_session.dart';
import 'package:cockpit/app/cockpit/ui/states/pane_node.dart';
import 'package:cockpit/app/cockpit/ui/viewmodels/orchestration_cli_handler.dart';
import 'package:cockpit/app/cockpit/ui/viewmodels/cockpit_viewmodel.dart';
import 'package:cockpit/app/core/domain/entities/terminal_profile.dart';
import 'package:cockpit/app/core/domain/result.dart';
import 'package:flutter_test/flutter_test.dart';
import '../support/attachment_terminal_gateway.dart';

class _Panel extends PaneItem {
  @override
  String get id => 'panel';
  @override
  String get projectId => 'worktree';
  @override
  String get workingDirectory => '/worktree';
  @override
  String get title => 'Panel';
}

class _MenuVm extends Fake implements CockpitViewModel {
  (String, String, PaneItem)? focused;
  int normalCreations = 0;
  @override
  (String, String, PaneItem)? focusedTab() => focused;
  @override
  dynamic noSuchMethod(Invocation invocation) {
    if (invocation.memberName == #newTabIn) {
      normalCreations++;
      return null;
    }
    return super.noSuchMethod(invocation);
  }
}

class _App {
  _App(String id) {
    controller = OrchestrationController(
      read: () async => disk,
      write: (value) async {
        disk = value;
      },
      newBoxId: () => 'unused',
      terminals: () => [
        for (final s in app.terminals.sessions.values)
          OrchestrationTerminal(s.id, s.displayTitle, '.'),
      ],
      createShell: (definition) async {
        final gateway = AttachmentTerminalGateway();
        final s = TerminalSession(
          id: '$id-${++spawned}',
          projectId: 'worktree',
          owner: app.terminals.owner,
          workingDirectory: '/worktree/${definition.directory}',
          gateway: gateway,
          profile: const TerminalProfile(
            id: 'sh',
            label: 'Shell',
            executable: 'sh',
          ),
        );
        gateways[s.id] = gateway;
        s.setManualLabel(definition.box.title);
        app.terminals.attach(s, focus: false);
        return s.id;
      },
      closeTerminal: (id) async {
        await app.terminals.detach(id)?.dispose();
      },
    );
    app = OrchestrationSession(
      id: id,
      projectId: 'worktree',
      path: '/worktree/$id.orc',
      controller: controller,
      onOpenFile: (terminal, path, {line}) async {
        opened.add((terminal.id, path));
        return const Failure('fixture document unavailable');
      },
      onCloseTerminal: (id) async {
        if (failClose) return const Failure('disconnected');
        await controller.forgetTerminal(id);
        await app.terminals.detach(id)?.dispose();
        return Success(id);
      },
    );
  }
  late final OrchestrationSession app;
  late final OrchestrationController controller;
  final gateways = <String, AttachmentTerminalGateway>{};
  int spawned = 0;
  bool failClose = false;
  final opened = <(String, String)>[];
  String disk = OrchestrationDocument(
    boxes: [
      for (final id in ['one', 'two'])
        OrchestrationBox(
          box: GraphBox(
            id: id,
            title: id,
            role: '',
            harness: '',
            model: '',
            position: Offset.zero,
          ),
        ),
    ],
  ).encode();
  String get first => controller.bindings['one']!;
  String get second => controller.bindings['two']!;
}

void main() {
  late _App a;
  late _App b;
  late TerminalSession normal;
  late _Panel panel;
  late OrchestrationCliRouter router;
  late List<String> lookups;
  late List<CockpitCommand> delegated;
  String? focused;

  setUp(() async {
    a = _App('a');
    b = _App('b');
    await a.controller.load();
    await b.controller.load();
    normal = TerminalSession(
      id: 'normal',
      projectId: 'worktree',
      workingDirectory: '/worktree',
      gateway: AttachmentTerminalGateway(),
      profile: const TerminalProfile(
        id: 'sh',
        label: 'Shell',
        executable: 'sh',
      ),
    );
    panel = _Panel();
    lookups = [];
    delegated = [];
    focused = normal.id;
    router = OrchestrationCliRouter(
      findSession: (id) {
        lookups.add(id);
        return <String, PaneItem>{
          normal.id: normal,
          panel.id: panel,
          a.app.id: a.app,
          b.app.id: b.app,
          ...a.app.terminals.sessions,
          ...b.app.terminals.sessions,
        }[id];
      },
      findOwner: (id) => {'a': a.app, 'b': b.app}[id],
      focusedTabId: () => focused,
      workspace: (id) => (root: '/worktree', name: 'Worktree', remote: true),
      projectCommand: (c) async {
        delegated.add(c);
        return const CockpitCommandResult.ok();
      },
    );
  });
  tearDown(() async {
    await a.app.dispose();
    await b.app.dispose();
    await normal.dispose();
    panel.dispose();
  });

  Future<CockpitCommandResult> call(
    String cmd, {
    String? target,
    Map<String, dynamic> args = const {},
  }) async => (await router.handle(
    CockpitCommand(
      cmd: cmd,
      callerTabId: a.first,
      tabId: target ?? a.first,
      args: args,
    ),
  ))!;

  test(
    'native new/split menu stays bound to the original app across an async focus switch',
    () async {
      final vm = _MenuVm()..focused = ('outer', a.app.id, a.app);
      vm.newTerminalForFocusedTab();
      vm.focused = ('other', b.app.id, b.app);
      await a.controller.settle();
      await Future<void>.delayed(Duration.zero);
      expect(a.spawned, 3);
      expect(b.spawned, 2);
      expect(vm.normalCreations, 0);
      expect(vm.splitFocusedOrchestration(SplitDir.vertical), isTrue);
      await b.controller.settle();
      await Future<void>.delayed(Duration.zero);
      expect(a.spawned, 3);
      expect(b.spawned, 3);
      expect(leaves(b.app.terminals.tree!).length, 2);
      expect(vm.normalCreations, 0);
    },
  );

  test(
    'menu retains normal terminal creation, while a closing app cannot fall back to outer docks',
    () async {
      final vm = _MenuVm()..focused = ('outer', normal.id, normal);
      vm.newTerminalForFocusedTab();
      expect(vm.normalCreations, 1);
      expect(vm.splitFocusedOrchestration(SplitDir.vertical), isFalse);
      vm.focused = ('outer', a.app.id, a.app);
      a.app.closing = true;
      vm.newTerminalForFocusedTab();
      expect(vm.splitFocusedOrchestration(SplitDir.vertical), isTrue);
      await Future<void>.delayed(Duration.zero);
      expect(vm.normalCreations, 1);
      expect(a.spawned, 2);
    },
  );

  test('open routes only to the caller-owned document presentation', () async {
    final result = await call(
      'open',
      target: a.second,
      args: {'path': 'note.txt'},
    );
    expect(result.ok, isFalse);
    expect(a.opened, [(a.second, 'note.txt')]);
    expect(b.opened, isEmpty);
    expect(delegated, isEmpty);
    expect(
      (await call('open', target: b.first, args: {'path': 'foreign.txt'})).ok,
      isFalse,
    );
    expect(
      (await call('open', target: normal.id, args: {'path': 'global.txt'})).ok,
      isFalse,
    );
    expect((await call('open', args: {'path': ''})).ok, isFalse);
    expect(a.opened, hasLength(1));
    expect(b.opened, isEmpty);
    expect(delegated, isEmpty);
  });

  test(
    'list only enumerates its own registry, even with another global focus',
    () async {
      final result = await call('list-panes');
      expect((result.data as List).map((e) => (e as Map)['id']), [
        a.first,
        a.second,
      ]);
      expect(lookups, [a.first]);
      expect(delegated, isEmpty);
      final workspaces = await call('list-workspaces');
      expect((workspaces.data as List).single, {
        'id': 'worktree',
        'name': 'Worktree',
        'path': '/worktree',
        'tabs': 2,
      });
    },
  );

  test(
    'send is confined to its app, ignores a forged traffic source and does not move focus',
    () async {
      a.app.context.revealBox('one', focus: true);
      final data = base64.encode(utf8.encode('hello'));
      expect(
        (await call(
          'write',
          target: a.second,
          args: {'data': data, 'sourceTabId': b.first},
        )).ok,
        isTrue,
      );
      expect(a.gateways[a.second]!.text, 'hello');
      expect(a.app.terminals.keyboardTabId, a.first);
      for (final target in [b.first, normal.id]) {
        expect(
          (await call('write', target: target, args: {'data': data})).ok,
          isFalse,
        );
      }
      expect(b.gateways[b.first]!.text, isEmpty);
      expect(focused, normal.id);
    },
  );

  test(
    'read names resolve only within the same app and ambiguity never guesses',
    () async {
      a.app.terminals.session(a.second)!.terminal.write('own output');
      var result = await call('read-pane', args: {'target': 'two'});
      expect(result.ok, isTrue);
      expect(
        utf8.decode(base64.decode((result.data as Map)['text'] as String)),
        contains('own output'),
      );
      expect((await call('read-pane', args: {'target': b.first})).ok, isFalse);
      a.app.terminals.session(a.first)!.setManualLabel('two');
      result = await call('read-pane', args: {'target': 'two'});
      expect(result.ok, isFalse);
    },
  );

  test(
    'new terminal uses its own pane and persists a portable directory without changing the other tree',
    () async {
      final otherTree = b.app.terminals.tree;
      final result = await call(
        'new-tab',
        args: {
          'cwd': '/worktree/packages',
          'title': 'worker',
          'split': 'right',
        },
      );
      expect(result.ok, isTrue);
      expect(a.spawned, 3);
      expect(b.spawned, 2);
      expect(b.app.terminals.tree, same(otherTree));
      expect(leaves(a.app.terminals.tree!).length, 2);
      expect((a.app.terminals.tree as SplitPane).dir, SplitDir.vertical);
      final definition = OrchestrationDocument.parse(a.disk).boxes.last;
      expect(definition.directory, 'packages');
      expect(definition.box.title, 'worker');
      expect(definition.box.harness, isEmpty);
      expect(definition.box.role, isEmpty);
      expect(focused, normal.id);
      expect((await call('new-tab', args: {'cwd': '/outside'})).ok, isFalse);
      expect((await call('new-tab', args: {'split': 'bad'})).ok, isFalse);
      expect(a.spawned, 3);
    },
  );

  test(
    'close only removes the owned definition after response flush',
    () async {
      expect((await call('close-tab', target: b.first)).ok, isFalse);
      final id = a.first;
      final response = await call('close-tab');
      expect(response.ok, isTrue);
      expect(a.app.terminals.contains(id), isTrue);
      response.afterResponse!();
      await a.controller.settle();
      await Future<void>.delayed(Duration.zero);
      expect(a.app.terminals.contains(id), isFalse);
      expect(OrchestrationDocument.parse(a.disk).boxes.map((d) => d.box.id), [
        'two',
      ]);
      expect(b.app.terminals.sessions.length, 2);
    },
  );

  test(
    'deferred native close failure stays visible in its app without removing the definition',
    () async {
      a.failClose = true;
      final response = await call('close-tab');
      response.afterResponse!();
      await Future<void>.delayed(Duration.zero);
      expect(a.app.terminals.sessions.length, 2);
      expect(a.controller.document!.boxes.length, 2);
      expect(a.controller.error, contains('disconnected'));
      expect(b.controller.error, isNull);
    },
  );

  test(
    'stale caller fails before target lookup or any selected-workspace fallback',
    () async {
      final result = await router.handle(
        CockpitCommand(
          cmd: 'list-panes',
          callerTabId: 'closed',
          tabId: normal.id,
        ),
      );
      expect(result!.ok, isFalse);
      expect(lookups, ['closed']);
      final internal = a.app.terminals.detach(a.first)!;
      try {
        expect(
          (await router.handle(
            CockpitCommand(
              cmd: 'new-tab',
              callerTabId: internal.id,
              tabId: normal.id,
            ),
          ))!.ok,
          isFalse,
        );
      } finally {
        await internal.dispose();
      }
      expect(a.spawned, 2);
    },
  );

  test(
    'stale explicit destinations cannot create a fallback terminal in the selected dock',
    () async {
      final result = await router.handle(
        CockpitCommand(cmd: 'new-tab', callerTabId: normal.id, tabId: 'closed'),
      );
      expect(result!.ok, isFalse);
      expect(a.spawned, 2);
      expect(b.spawned, 2);
      expect(delegated, isEmpty);
    },
  );

  test(
    'normal callers cannot address owned terminals; ordinary commands stay on the existing handler',
    () async {
      final rejected = await router.handle(
        CockpitCommand(cmd: 'write', callerTabId: normal.id, tabId: a.first),
      );
      expect(rejected!.ok, isFalse);
      expect(
        await router.handle(
          CockpitCommand(cmd: 'list-panes', callerTabId: normal.id),
        ),
        isNull,
      );
    },
  );

  test(
    'ordinary Gallery callers stay compatible, app containers never gain a global fallback',
    () async {
      expect(
        await router.handle(
          CockpitCommand(
            cmd: 'db-list',
            callerTabId: panel.id,
            tabId: panel.id,
          ),
        ),
        isNull,
      );
      expect(
        (await router.handle(
          CockpitCommand(cmd: 'list-panes', callerTabId: a.app.id),
        ))!.ok,
        isFalse,
      );
      expect(delegated, isEmpty);
    },
  );

  test(
    'external focused automation uses the selected internal terminal, never the global parent',
    () async {
      focused = a.app.id;
      expect(
        (await router.handle(
          const CockpitCommand(
            cmd: 'write',
            tabId: '@focused',
            args: {'data': 'YQ=='},
          ),
        ))!.ok,
        isFalse,
      );
      a.app.context.revealBox('two', focus: true);
      expect(
        (await router.handle(
          const CockpitCommand(
            cmd: 'write',
            tabId: '@focused',
            args: {'data': 'YQ=='},
          ),
        ))!.ok,
        isTrue,
      );
      expect(a.gateways[a.second]!.text, 'a');
      expect(b.gateways[b.second]!.text, isEmpty);
    },
  );

  test(
    'telemetry wrapper keeps the true caller and cannot use app storage',
    () async {
      for (final verb in [
        'telemetry-open',
        'telemetry-ingest',
        'telemetry-close',
      ]) {
        expect((await call(verb, args: {'run': 'r_1'})).ok, isTrue);
        expect(delegated.last.tabId, a.first);
        expect(delegated.last.callerTabId, a.first);
        expect(delegated.last.args['workspace'], 'worktree');
        expect((await call(verb, args: {'app': true})).ok, isFalse);
        expect((await call(verb, args: {'workspace': 'other'})).ok, isFalse);
      }
      expect(delegated, hasLength(3));
    },
  );

  test(
    'data tools are pinned to the sender worktree and global UI commands are refused',
    () async {
      expect((await call('db-list')).ok, isTrue);
      expect(delegated.single.tabId, a.first);
      expect(delegated.single.callerTabId, a.first);
      expect(delegated.single.args['workspace'], 'worktree');
      expect((await call('db-list', args: {'workspace': 'other'})).ok, isFalse);
      expect((await call('telemetry-errors', args: {'app': true})).ok, isFalse);
      for (final cmd in [
        'apply-layout',
        'open-workspace',
        'close-workspace',
        'browse',
        'orchestrate',
      ]) {
        expect((await call(cmd)).ok, isFalse, reason: cmd);
      }
      expect(delegated.length, 1);
      expect((await call('exec', args: {'command': 'pwd'})).ok, isTrue);
      expect(delegated.last.args['cwd'], '/worktree/.');
    },
  );
}
