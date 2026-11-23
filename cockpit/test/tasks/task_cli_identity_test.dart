import 'dart:convert';
import 'dart:io';

import 'package:cockpit/app/cockpit/data/tasks/task_discovery_impl.dart';
import 'package:cockpit/app/cockpit/data/tasks/tools/dev_tool_registry.dart';
import 'package:cockpit/app/cockpit/data/tasks/tools/task_device_coordinator.dart';
import 'package:cockpit/app/cockpit/domain/contracts/dev_tool.dart';
import 'package:cockpit/app/cockpit/domain/contracts/http_request_runner.dart';
import 'package:cockpit/app/cockpit/domain/contracts/terminal_status_server.dart';
import 'package:cockpit/app/cockpit/domain/entities/project.dart';
import 'package:cockpit/app/cockpit/domain/entities/task_definition.dart';
import 'package:cockpit/app/cockpit/domain/entities/task_run.dart';
import 'package:cockpit/app/cockpit/domain/services/db_query_service.dart';
import 'package:cockpit/app/cockpit/ui/session/pane_item.dart';
import 'package:cockpit/app/cockpit/ui/session/task_terminal_store.dart';
import 'package:cockpit/app/cockpit/ui/viewmodels/cockpit_cli_handler.dart';
import 'package:cockpit/app/cockpit/ui/viewmodels/cockpit_viewmodel.dart';
import 'package:cockpit/app/cockpit/ui/viewmodels/telemetry_cli_handler.dart';
import 'package:cockpit/app/core/domain/entities/app_settings.dart';
import 'package:flutter_test/flutter_test.dart';

import '../session/task_terminal_store_run_ordering_test.dart'
    show SequencedRunner, NullScrollbackStore;
import 'tasks_workspace_import_test.dart' show NoDevices;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'CLI keeps short task IDs compatible and routes by workspace UUID',
    () async {
      final root = await Directory.systemTemp.createTemp('task-cli-identity-');
      addTearDown(() => root.delete(recursive: true));
      final file = File('${root.path}/.cockpit/tasks.json');
      await file.parent.create(recursive: true);
      await file.writeAsString(
        '{"tasks":[{"label":"Server","command":"dotnet"}]}',
      );
      Project project(String id) => Project(
        id: id,
        name: id,
        path: root.path,
        colorValue: 0,
        createdAt: DateTime(2026),
      );
      final vm = _Vm()..project = project('payments');
      final runner = _Runner();
      final store = TaskTerminalStore(runner, NullScrollbackStore())
        ..setDefaultEngine(TerminalEngine.xterm);
      addTearDown(store.dispose);
      final discovery = TaskDiscoveryImpl(const []);
      final cli = CockpitCliHandler(
        vm,
        _Db(),
        _Http(),
        discovery,
        runner,
        store,
        _Telemetry(),
        TaskDeviceCoordinatorImpl(
          DevToolRegistry(const []),
          NoDevices(),
          HostOs.linux,
        ),
      );
      Future<CockpitCommandResult> command(
        String verb, {
        String target = 'json:Server',
      }) => cli.handle(CockpitCommand(cmd: verb, args: {'target': target}));
      final payments = (await discovery.discover(
        root.path,
        workspaceId: 'payments',
      )).single;
      final orders = (await discovery.discover(
        root.path,
        workspaceId: 'orders',
      )).single;
      expect((await command('run-task')).ok, isTrue);
      expect(runner.started, [payments.id]);
      runner.write(payments.id, 'payments-output\r\n');
      vm.project = project('orders');
      expect((await command('run-task')).ok, isTrue);
      expect(runner.started, [payments.id, orders.id]);
      runner.write(orders.id, 'orders-output\r\n');
      final read = await command('read-task');
      expect(read.ok, isTrue);
      final text = utf8.decode(
        base64Decode((read.data as Map)['text'] as String),
      );
      expect(text, contains('orders-output'));
      expect(text, isNot(contains('payments-output')));
      expect((await command('restart-task')).ok, isTrue);
      expect(runner.restarted, [orders.id]);
      expect((await command('stop-task')).ok, isTrue);
      expect(runner.stopped, [orders.id]);
      expect(runner.runOf(payments.id).isActive, isTrue);
      vm.project = project('payments');
      // Opaque IDs from list-tasks are accepted alongside legacy short aliases.
      expect((await command('stop-task', target: payments.id)).ok, isTrue);
      expect(runner.stopped, [orders.id, payments.id]);
    },
  );
}

class _Vm extends Fake implements CockpitViewModel {
  late Project project;
  @override
  Project? get selectedProject => project;
  @override
  PaneItem? session(String id) => null;
}

class _Db extends Fake implements DbQueryService {}

class _Http extends Fake implements HttpRequestRunner {}

class _Telemetry extends Fake implements TelemetryCliHandler {}

class _Runner extends SequencedRunner {
  final started = <String>[];
  final restarted = <String>[];
  final stopped = <String>[];
  final states = <String, TaskRun>{};
  @override
  TaskRun runOf(String id) => states[id] ?? TaskRun.idleFor(id);
  @override
  Future<void> start(
    TaskDefinition def, {
    String? profileName,
    List<String> adHocArgs = const [],
    List<String>? argsOverride,
  }) async {
    started.add(def.id);
    states[def.id] = TaskRun(taskId: def.id, status: TaskRunStatus.running);
    spawn(def.id, pid: started.length);
  }

  @override
  Future<void> stop(String id) async {
    stopped.add(id);
    states.remove(id);
    super.exit(id);
  }

  @override
  Future<void> restart(String id) async => restarted.add(id);
}
