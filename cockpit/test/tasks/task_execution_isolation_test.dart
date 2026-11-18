import 'dart:typed_data';
import 'package:cockpit/app/cockpit/data/remote/remote_task_gateway.dart';
import 'package:cockpit_remote/cockpit_remote.dart';
import 'package:cockpit/app/cockpit/data/tasks/tools/flutter_tool.dart';
import 'package:cockpit/app/cockpit/domain/contracts/device_selection_store.dart';
import 'package:cockpit/app/cockpit/data/tasks/compose_tasks.dart';
import 'package:cockpit/app/cockpit/data/terminal/file_terminal_scrollback_store.dart';
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:cockpit/app/cockpit/data/tasks/pty_task_runner.dart';
import 'package:cockpit/app/cockpit/data/tasks/task_discovery_impl.dart';
import 'package:cockpit/app/cockpit/data/tasks/tasks_json_loader.dart';
import 'package:cockpit/app/cockpit/data/tasks/tools/dev_tool_registry.dart';
import 'package:cockpit/app/cockpit/data/tasks/tools/task_device_coordinator.dart';
import 'package:cockpit/app/cockpit/domain/contracts/task_adapter.dart';
import 'package:cockpit/app/cockpit/domain/entities/task_definition.dart';
import 'package:cockpit/app/cockpit/domain/entities/task_run.dart';
import 'package:cockpit/app/cockpit/domain/contracts/dev_tool.dart';
import 'package:cockpit/app/cockpit/ui/viewmodels/tasks_viewmodel.dart';
import 'package:flutter_test/flutter_test.dart';

import 'tasks_workspace_import_test.dart' show IdleTaskRunner, NoDevices;
import '../session/task_terminal_store_run_ordering_test.dart'
    show SequencedRunner, NullScrollbackStore;
import 'package:cockpit/app/cockpit/ui/session/task_terminal_store.dart';
import 'package:cockpit/app/core/domain/entities/app_settings.dart';
import 'package:cockpit/app/core/terminal/terminal_controller.dart';
import 'package:cockpit/app/cockpit/domain/contracts/telemetry_ingest.dart';

const config = '''{
  "tasks": [
    {"label":"Server", "command":"dotnet", "args":["run"], "kind":"watch",
     "profiles":[{"name":"dev"},{"name":"prod"}]},
    {"label":"Worker", "command":"dotnet", "args":["run"], "kind":"watch",
     "profiles":[{"name":"dev"},{"name":"prod"}]}
  ]
}''';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory temp;
  late List<String> roots;
  final discovery = TaskDiscoveryImpl(const []);

  setUp(() async {
    temp = await Directory.systemTemp.createTemp('cockpit-task-isolation-');
    roots = [
      '${temp.path}/payments.service/.cockpit/worktrees/shared',
      '${temp.path}/order.service/.cockpit/worktrees/shared',
      '${temp.path}/payments.service/.cockpit/worktrees/other',
    ];
    for (final root in roots) {
      final file = File('$root/.cockpit/tasks.json');
      await file.parent.create(recursive: true);
      await file.writeAsString(config);
    }
  });

  tearDown(() async => temp.delete(recursive: true));

  test(
    'same task/worktree/profile names have distinct stable runtime IDs',
    () async {
      final all = [for (final root in roots) ...await discovery.discover(root)];
      expect(all.map((d) => d.id).toSet(), hasLength(6));
      expect(all.map((d) => d.localId).toSet(), {'json:Server', 'json:Worker'});
      expect(all.map((d) => d.profiles.first.name).toSet(), {'dev'});
      expect((await discovery.discover(roots.first)).first.id, all.first.id);
      expect(all.first.id.length, lessThan(100)); // safe scrollback filenames
    },
  );

  test('workspace UUID isolates even the same physical folder', () async {
    final vm = TasksViewModel(
      discovery,
      IdleTaskRunner(),
      TaskDeviceCoordinatorImpl(
        DevToolRegistry(const []),
        NoDevices(),
        HostOs.linux,
      ),
    );
    addTearDown(vm.dispose);
    await vm.loadFor(roots.first, workspaceId: 'workspace-a');
    final a = vm.tasks.first;
    vm.cycleProfile(a);
    await vm.loadFor(roots.first, workspaceId: 'workspace-b');
    expect(vm.tasks.first.id, isNot(a.id));
    expect(vm.selectedProfile(vm.tasks.first), 'dev');
    await vm.loadFor(roots.first, workspaceId: 'workspace-a');
    expect(vm.tasks.first.id, a.id);
    expect(vm.selectedProfile(vm.tasks.first), 'prod');
  });

  test(
    'remote discovery includes host, workspace and full worktree root',
    () async {
      final a = RemoteTaskDiscovery(
        () async => _RemoteFiles(),
        hostId: 'host-a',
      );
      final b = RemoteTaskDiscovery(
        () async => _RemoteFiles(),
        hostId: 'host-b',
      );
      final first = (await a.discover(
        '/srv/project/shared',
        workspaceId: 'ws',
      )).first;
      final otherHost = (await b.discover(
        '/srv/project/shared',
        workspaceId: 'ws',
      )).first;
      final otherWorkspace = (await a.discover(
        '/srv/project/shared',
        workspaceId: 'ws-other',
      )).first;
      final otherRoot = (await a.discover(
        '/srv/other/shared',
        workspaceId: 'ws',
      )).first;
      expect({
        first.id,
        otherHost.id,
        otherWorkspace.id,
        otherRoot.id,
      }, hasLength(4));
      expect(first.localId, 'json:Server');
    },
  );

  test(
    'legacy device preferences remain readable; new choices are scoped',
    () async {
      final memory = _Devices();
      final def = TaskDefinition(
        id: 'json:run',
        label: 'run',
        cwd: roots.first,
        command: 'flutter',
        args: const ['run'],
      ).scopedTo(roots.first, workspaceId: 'a');
      final other = def.scopedTo(roots.first, workspaceId: 'b');
      await memory.write(def.cwd, def.localId, 'legacy-device');
      final devices = TaskDeviceCoordinatorImpl(
        DevToolRegistry(const [FlutterTool()]),
        memory,
        HostOs.linux,
      );
      expect(
        devices.snapshot(def, profileName: null, remote: false).selectedId,
        'legacy-device',
      );
      await devices.select(def, 'new-device');
      expect(
        devices.snapshot(def, profileName: null, remote: false).selectedId,
        'new-device',
      );
      expect(
        devices.snapshot(other, profileName: null, remote: false).selectedId,
        'legacy-device',
      );
    },
  );

  test('scope uses config root even when tasks share an absolute cwd', () {
    final loader = TasksJsonLoader();
    final content = jsonEncode({
      'cwd': '/shared/build',
      'tasks': [
        {'label': 'Server', 'command': 'dotnet'},
      ],
    });
    final a = loader.parseContent(content, roots[0]).single.scopedTo(roots[0]);
    final b = loader.parseContent(content, roots[1]).single.scopedTo(roots[1]);
    expect(a.cwd, b.cwd);
    expect(a.id, isNot(b.id));
    expect(a.scopedTo(roots[0]).id, a.id); // qualification is idempotent
    expect(
      a.scopedTo(roots[0], hostId: 'host-a').id,
      isNot(a.scopedTo(roots[0], hostId: 'host-b').id),
    );
    expect(a.scopedTo(roots[0], hostId: 'host-a').id, isNot(a.id));
  });

  test(
    'detected definitions are scoped after local override merging',
    () async {
      final detected = TaskDiscoveryImpl([_Adapter()]);
      final a = await detected.discover(roots[0]);
      final b = await detected.discover(roots[1]);
      expect(a, hasLength(3)); // manual Server replaces detected Server
      expect(
        a.singleWhere((t) => t.localId == 'json:Server').command,
        'dotnet',
      );
      final first = a.singleWhere((t) => t.localId == 'detected:run');
      expect(
        first.id,
        isNot(b.singleWhere((t) => t.localId == 'detected:run').id),
      );
      expect(first.interactiveKeys.single.key, 'r');
      expect(first.watch!.onChange, 'reload');
      expect(first.previewOpen, TaskPreviewOpen.never);
      expect(first.telemetryEnabled, isFalse);
    },
  );

  test(
    'profile selection remains independent across tasks and root switches',
    () async {
      final vm = TasksViewModel(
        discovery,
        IdleTaskRunner(),
        TaskDeviceCoordinatorImpl(
          DevToolRegistry(const []),
          NoDevices(),
          HostOs.linux,
        ),
      );
      addTearDown(vm.dispose);
      await vm.loadFor(roots[0]);
      final server = vm.tasks.first;
      final worker = vm.tasks.last;
      vm.cycleProfile(server);
      expect(vm.selectedProfile(server), 'prod');
      expect(vm.selectedProfile(worker), 'dev');
      await vm.loadFor(roots[1]);
      expect(vm.selectedProfile(vm.tasks.first), 'dev');
      await vm.loadFor(roots[0]);
      expect(vm.selectedProfile(vm.tasks.first), 'prod');
    },
  );

  test('terminals remain distinct across roots, hosts and restart', () async {
    final defs = [
      for (final root in roots) (await discovery.discover(root)).first,
    ];
    final remote = defs.first.scopedTo(roots.first, hostId: 'remote');
    final runner = SequencedRunner();
    final store = TaskTerminalStore(runner, NullScrollbackStore())
      ..setDefaultEngine(TerminalEngine.xterm);
    addTearDown(store.dispose);
    final all = [...defs, remote];
    for (var i = 0; i < all.length; i++) {
      runner.spawn(all[i].id, pid: 100 + i);
      runner.write(all[i].id, 'server-$i\r\n');
    }
    String screen(String id) =>
        (store.existingTerminal(id)! as XtermTerminalController)
            .plainLines()
            .join('\n');
    runner.exit(all.first.id);
    runner.spawn(all.first.id, pid: 200);
    runner.write(all.first.id, 'restarted\r\n');
    expect(screen(all.first.id), contains('restarted'));
    for (var i = 1; i < all.length; i++) {
      expect(screen(all[i].id), contains('server-$i'));
      expect(screen(all[i].id), isNot(contains('restarted')));
    }
    for (final def in all) {
      runner.exit(def.id);
    }
  });

  test(
    'persisted task output restores separately for identical names',
    () async {
      final defs = [
        for (final root in roots) (await discovery.discover(root)).first,
      ];
      final disk = FileTerminalScrollbackStore(
        root: Directory('${temp.path}/scrollback'),
      );
      for (var i = 0; i < defs.length; i++) {
        await disk.save(
          projectId: '__tasks__',
          sessionId: defs[i].id,
          contents: 'history-$i\r\n',
        );
      }
      final store = TaskTerminalStore(IdleTaskRunner(), disk)
        ..setDefaultEngine(TerminalEngine.xterm);
      addTearDown(store.dispose);
      for (var i = 0; i < roots.length; i++) {
        final def = (await discovery.discover(roots[i])).first;
        final terminal = store.terminalFor(def.id) as XtermTerminalController;
        await _until(
          () => terminal.plainLines().join('\n').contains('history-$i'),
        );
        expect(
          terminal.plainLines().join('\n'),
          isNot(contains('history-${(i + 1) % 3}')),
        );
      }
    },
  );

  test(
    'Compose reconciliation preserves other roots and monitors each separately',
    () async {
      final resolver = _ComposeResolver();
      final runner = PtyTaskRunner(
        _NoTelemetry(),
        DevToolRegistry(const []),
        composeResolver: resolver,
      );
      addTearDown(runner.disposeAll);
      final defs = <TaskDefinition>[];
      for (final root in roots) {
        final file = '$root/compose.yaml';
        await File(
          file,
        ).writeAsString('services:\n  api:\n    image: example\n');
        resolver.active.add(file);
        final def = TaskDefinition(
          id: 'compose:api',
          label: 'api',
          cwd: root,
          command: 'docker',
          args: ['compose', '-f', file, 'up', '-d', 'api'],
          profiles: const [
            TaskProfile(name: 'up', args: ['up', '-d', 'api']),
          ],
        ).scopedTo(root);
        defs.add(def);
        await runner.reconcileDefinitions([def], projectRoot: root);
      }
      for (final def in defs) {
        expect(runner.runOf(def.id).status, TaskRunStatus.running);
      }
      resolver.active.remove('${roots.first}/compose.yaml');
      await runner.reconcileDefinitions([], projectRoot: roots.last);
      expect(runner.runOf(defs.first.id).status, TaskRunStatus.stopped);
      for (final def in defs.skip(1)) {
        expect(runner.runOf(def.id).status, TaskRunStatus.running);
      }
    },
  );

  test(
    'real PTY servers: simultaneous start, output, states, stop and restart are isolated',
    () async {
      Future<void> git(String cwd, List<String> args) async {
        final result = await Process.run('git', args, workingDirectory: cwd);
        expect(
          result.exitCode,
          0,
          reason: '${result.stdout}\n${result.stderr}',
        );
      }

      for (final workspace in ['payments.service', 'order.service']) {
        final repo = '${temp.path}/$workspace';
        await git(repo, ['init', '-q']);
        await git(repo, [
          '-c',
          'user.name=Cockpit Test',
          '-c',
          'user.email=test@localhost',
          '-c',
          'commit.gpgsign=false',
          'commit',
          '--allow-empty',
          '-qm',
          'fixture',
        ]);
      }
      for (final root in roots) {
        // Only generated fixture config exists here; Git needs an empty path.
        await Directory('$root/.cockpit').delete(recursive: true);
        final workspace = root.contains('/payments.service/')
            ? 'payments.service'
            : 'order.service';
        await git('${temp.path}/$workspace', [
          'worktree',
          'add',
          '-b',
          root.split('/').last,
          root,
        ]);
      }
      final dotnet = Platform.environment['COCKPIT_TASK_TEST_DOTNET'];
      if (dotnet != null) {
        final fixture = Directory('test/fixtures/task_isolation_server');
        for (final root in roots) {
          for (final name in ['Server.csproj', 'Program.cs']) {
            await File('${fixture.path}/$name').copy('$root/$name');
          }
          final build = await Process.run(
            dotnet,
            ['build', '--nologo', '-o', 'out'],
            workingDirectory: root,
            environment: {
              'DOTNET_CLI_HOME': temp.path,
              'DOTNET_SKIP_FIRST_TIME_EXPERIENCE': '1',
            },
          );
          expect(build.exitCode, 0, reason: '${build.stdout}\n${build.stderr}');
        }
      } else {
        for (final root in roots) {
          await File('$root/server.py').writeAsString(_pythonServer);
        }
      }
      // Same command/args in every worktree; distinct Server/Worker tasks also
      // share dev/prod profile names. Configuration remains ordinary tasks.json.
      for (final root in roots) {
        final decoded = jsonDecode(config) as Map<String, dynamic>;
        for (final task in decoded['tasks'] as List) {
          task['command'] = 'exec';
          task['args'] = dotnet == null
              ? ['python3', '-u', 'server.py']
              : [dotnet, 'out/Server.dll'];
          task['preview'] = false;
          task['progressPatterns'] = [
            {'begin': 'BUILDING', 'end': 'READY'},
          ];
        }
        final file = File('$root/.cockpit/tasks.json');
        await file.parent.create(recursive: true);
        await file.writeAsString(jsonEncode(decoded));
      }
      final runner = PtyTaskRunner(_NoTelemetry(), DevToolRegistry(const []));
      final vm = TasksViewModel(
        discovery,
        runner,
        TaskDeviceCoordinatorImpl(
          DevToolRegistry(const []),
          NoDevices(),
          HostOs.linux,
        ),
      );
      final events = <TaskRun>[];
      final output = <String, StringBuffer>{};
      final subs = <StreamSubscription<String>>[];
      final runSub = runner.runs().listen((event) {
        events.add(event);
        if (event.status == TaskRunStatus.running && event.pid != null) {
          final buffer = output.putIfAbsent(event.taskId, StringBuffer.new);
          subs.add(runner.output(event.taskId).listen(buffer.write));
        }
      });
      addTearDown(() async {
        vm.dispose();
        await runSub.cancel();
        for (final sub in subs) {
          await sub.cancel();
        }
        await runner.disposeAll();
      });
      final definitions = <TaskDefinition>[];
      for (final root in roots) {
        await vm.loadFor(root, workspaceId: 'workspace-${roots.indexOf(root)}');
        definitions.add(vm.tasks.first);
        if (root == roots.first) {
          definitions.add(vm.tasks.last);
        }
      }
      await Future.wait(
        definitions.map((def) => runner.start(def, profileName: 'dev')),
      );
      await _until(
        () => definitions.every(
          (d) => output[d.id]?.toString().contains('PORT:') ?? false,
        ),
      );
      expect(
        definitions.map((d) => runner.runOf(d.id).pid).toSet(),
        hasLength(4),
      );
      final originalPids = {
        for (final d in definitions) d.id: runner.runOf(d.id).pid,
      };
      Future<void> checkServer(TaskDefinition d) async {
        final matches = RegExp(
          r'PORT:(\d+)',
        ).allMatches(output[d.id].toString());
        final port = int.parse(matches.last.group(1)!);
        final client = _RealHttpOverrides().createHttpClient(null);
        try {
          final req = await client.getUrl(Uri.parse('http://127.0.0.1:$port/'));
          final res = await req.close();
          expect(await utf8.decoder.bind(res).join(), d.cwd);
        } finally {
          client.close(force: true);
        }
      }

      for (final d in definitions) {
        await checkServer(d);
      }
      // Selecting another project must recover its own still-running state.
      await vm.loadFor(roots[0], workspaceId: 'workspace-0');
      final first = definitions.first;
      expect(vm.stateOf(first.id).pid, originalPids[first.id]);
      runner.sendKey(first.id, 'build\n');
      await _until(() => vm.stateOf(first.id).status == TaskRunStatus.building);
      for (final d in definitions.skip(1)) {
        expect(vm.stateOf(d.id).status, TaskRunStatus.running);
        expect(output[d.id].toString(), isNot(contains('BUILDING')));
      }
      runner.sendKey(first.id, 'ready\n');
      await _until(() => vm.stateOf(first.id).status == TaskRunStatus.running);
      await runner.restart(first.id);
      await _until(
        () =>
            RegExp('PORT:').allMatches(output[first.id].toString()).length == 2,
      );
      expect(runner.runOf(first.id).pid, isNot(originalPids[first.id]));
      expect(runner.runOf(first.id).profileName, 'dev');
      for (final d in definitions) {
        await checkServer(d);
      }
      // Let the old stop escalation deadline pass: it must not kill a new run.
      await Future<void>.delayed(const Duration(milliseconds: 3200));
      await checkServer(first);
      await runner.stop(first.id);
      await _until(
        () => runner.runOf(first.id).status == TaskRunStatus.stopped,
      );
      for (final d in definitions.skip(1)) {
        expect(runner.runOf(d.id).pid, originalPids[d.id]);
        expect(vm.stateOf(d.id).status, TaskRunStatus.running);
        await checkServer(d);
      }
      expect(
        events.where((e) => e.taskId == first.id).map((e) => e.status),
        containsAll([
          TaskRunStatus.starting,
          TaskRunStatus.running,
          TaskRunStatus.building,
          TaskRunStatus.stopping,
          TaskRunStatus.stopped,
        ]),
      );
    },
    skip: Platform.environment['COCKPIT_TASK_PTY_TESTS'] != '1'
        ? 'Set COCKPIT_TASK_PTY_TESTS=1 and expose libcockpit_pty on the native library path.'
        : false,
    timeout: const Timeout(Duration(minutes: 3)),
  );
}

Future<void> _until(bool Function() condition) async {
  final deadline = DateTime.now().add(const Duration(seconds: 15));
  while (!condition()) {
    if (DateTime.now().isAfter(deadline)) {
      fail('Timed out waiting for task state/output');
    }
    await Future<void>.delayed(const Duration(milliseconds: 25));
  }
}

class _NoTelemetry implements TelemetryIngest {
  @override
  Future<TelemetryIngestSession?> openTaskRun(
    TaskDefinition def, {
    required String command,
    int? pid,
    String? paneId,
  }) async => null;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Adapter implements TaskAdapter {
  @override
  Future<bool> matches(String cwd) async => true;
  @override
  Future<List<TaskDefinition>> tasksFor(String cwd) async => [
    TaskDefinition(
      id: 'json:Server',
      label: 'detected',
      cwd: cwd,
      command: 'ignored',
    ),
    TaskDefinition(
      id: 'detected:run',
      label: 'run',
      cwd: cwd,
      command: 'dotnet',
      interactiveKeys: const [InteractiveKey(key: 'r', label: 'reload')],
      watch: const TaskWatch(paths: ['src'], onChange: 'reload'),
      previewOpen: TaskPreviewOpen.never,
      telemetryEnabled: false,
    ),
  ];
}

const _pythonServer = '''
import http.server, os, threading, sys
class Handler(http.server.BaseHTTPRequestHandler):
    def do_GET(self):
        body = os.getcwd().encode()
        self.send_response(200)
        self.send_header('Content-Length', str(len(body)))
        self.end_headers()
        self.wfile.write(body)
    def log_message(self, *args): pass
server = http.server.HTTPServer(('127.0.0.1', 0), Handler)
print('PORT:' + str(server.server_port), flush=True)
threading.Thread(target=server.serve_forever, daemon=True).start()
for line in sys.stdin:
    print('BUILDING' if line.strip() == 'build' else 'READY', flush=True)
server.shutdown()
''';

// Flutter's widget-test HTTP override returns fake 400 responses; this test
// deliberately talks to real loopback servers in child processes.
class _RealHttpOverrides extends HttpOverrides {}

class _ComposeResolver extends ComposeEngineResolver {
  final active = <String>{};
  @override
  Future<Set<String>> runningServices(
    ComposeEngine engine,
    String file,
  ) async => active.contains(file) ? {'api'} : {};
}

class _RemoteFiles extends Fake implements RemoteFileService {
  @override
  Future<Uint8List> read(String path, {int maxBytes = 8 * 1024 * 1024}) async =>
      Uint8List.fromList(utf8.encode(config));
}

class _Devices implements DeviceSelectionStore {
  final values = <(String, String), DevicePreference>{};
  @override
  DevicePreference? read(String cwd, String taskId) => values[(cwd, taskId)];
  @override
  Future<void> write(String cwd, String taskId, String deviceId) async {
    values[(cwd, taskId)] = DevicePreference(deviceId: deviceId);
  }
}
