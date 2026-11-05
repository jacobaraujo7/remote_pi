import 'dart:async';

import 'package:cockpit/app/cockpit/data/tasks/preview_url_scan.dart';
import 'package:cockpit/app/cockpit/data/tasks/tools/dev_tool_registry.dart';
import 'package:cockpit/app/cockpit/data/tasks/tools/flutter_tool.dart';
import 'package:cockpit/app/cockpit/data/tasks/tools/task_device_coordinator.dart';
import 'package:cockpit/app/cockpit/domain/contracts/dev_tool.dart';
import 'package:cockpit/app/cockpit/domain/contracts/device_selection_store.dart';
import 'package:cockpit/app/cockpit/domain/contracts/task_discovery.dart';
import 'package:cockpit/app/cockpit/domain/contracts/task_runner_gateway.dart';
import 'package:cockpit/app/cockpit/domain/entities/task_definition.dart';
import 'package:cockpit/app/cockpit/domain/entities/task_run.dart';
import 'package:cockpit/app/cockpit/ui/viewmodels/tasks_viewmodel.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const vmUrl = 'http://127.0.0.1:54321/AbCdEf=/';
  const devtools = 'http://127.0.0.1:9100?uri=$vmUrl';
  const appUrl = 'http://localhost:8080';

  group('preview scan', () {
    test('skips DevTools and VM Service and keeps the app url', () {
      final text =
          'A Dart VM Service on macOS is available at: $vmUrl\n'
          'The Flutter DevTools debugger and profiler on macOS is available at: $devtools\n'
          'lib/main.dart is being served at $appUrl\n';
      final hint = const FlutterTool().inspectOutput(
        const FlutterTool().match('flutter', ['run'])!,
        text,
      );
      expect(scanPreviewUrl(text, consumed: hint!.consumedUrls), appUrl);
    });

    test('a VM Service line alone is not a preview', () {
      final text = 'A Dart VM Service on macOS is available at: $vmUrl\n';
      final hint = const FlutterTool().inspectOutput(
        const FlutterTool().match('flutter', ['run'])!,
        text,
      );
      expect(scanPreviewUrl(text, consumed: hint!.consumedUrls), isNull);
    });

    test('without a tool, the first local url is still the preview', () {
      final text = 'serving $appUrl\n';
      expect(scanPreviewUrl(text), appUrl);
    });

    test('a wrap before the auth padding rejoins /ws and keeps the app url', () {
      const service = 'ws://127.0.0.1:46075/vNzGJsPDZ=/ws';
      const page = 'http://127.0.0.1:9100?uri=$service';
      final wrapped =
          'The Flutter DevTools debugger and profiler on Linux is available at: '
          'http://127.0.0.1:9100?uri=ws://127.0.0.1:46075/vNzGJsPDZ\n'
          '=/ws\n'
          'lib/main.dart is being served at $appUrl\n';
      final hint = const FlutterTool().inspectOutput(
        const FlutterTool().match('flutter', ['run'])!,
        wrapped,
      );
      expect(hint!.sessionUrl, page);
      final action = const FlutterTool().action(
        const FlutterTool().match('flutter', ['run'])!,
        sessionUrl: hint.sessionUrl!,
      );
      expect(_serviceTarget(action!.url), service);
      expect(action.url, contains('%3D'));
      expect(action.url.contains('=/ws'), isFalse);
      expect(
        scanPreviewUrl(
          joinWrappedPreviewLines(wrapped),
          consumed: hint.consumedUrls,
        ),
        appUrl,
      );
    });

    test('a cut service uri is consumed and is not a preview', () {
      final partial =
          'The Flutter DevTools debugger and profiler on Linux is available at: '
          'http://127.0.0.1:9100?uri=ws://127.0.0.1:46075/vNzGJsPDZ\n';
      final hint = const FlutterTool().inspectOutput(
        const FlutterTool().match('flutter', ['run'])!,
        partial,
      );
      expect(hint!.sessionUrl, isNull);
      expect(scanPreviewUrl(partial, consumed: hint.consumedUrls), isNull);
    });

    test('join stops once the service url is whole', () {
      const cut =
          'http://127.0.0.1:9100?uri=ws://127.0.0.1:46075/vNzGJsPDZ\n=/ws\n';
      expect(
        joinWrappedPreviewLines(cut),
        'http://127.0.0.1:9100?uri=ws://127.0.0.1:46075/vNzGJsPDZ=/ws\n',
      );
      const whole =
          'http://127.0.0.1:9100?uri=ws://127.0.0.1:46075/vNzGJsPDZ=/ws\n'
          'The Flutter DevTools\n';
      expect(joinWrappedPreviewLines(whole), whole);
      expect(
        joinWrappedPreviewLines('$devtools\n$appUrl\n'),
        '$devtools\n$appUrl\n',
      );
    });
  });

  group('task actions', () {
    late _SessionRunner runner;
    late TasksViewModel vm;
    late TaskDefinition appA;
    late TaskDefinition appB;
    late TaskDefinition tests;
    late TaskDefinition npm;

    setUp(() {
      appA = _task('json:a', 'flutter', const ['run']);
      appB = _task('json:b', 'flutter', const ['run', '-d', 'ios']);
      tests = _task('json:test', 'flutter', const ['test']);
      npm = _task('json:npm', 'npm', const ['run', 'dev']);
      runner = _SessionRunner();
      vm = TasksViewModel(
        _FixedDiscovery(const []),
        runner,
        TaskDeviceCoordinator(
          DevToolRegistry(const [FlutterTool()]),
          _MemoryDevices(),
          HostOs.linux,
        ),
      );
    });

    tearDown(() => vm.dispose());

    test('shows the action only while running with a url', () {
      runner.emit(_run(appA.id, TaskRunStatus.starting));
      runner.emitSession(appA.id, devtools);
      expect(vm.actionsFor(appA), isEmpty);

      runner.emit(_run(appA.id, TaskRunStatus.running));
      runner.emitSession(appA.id, vmUrl);
      expect(vm.actionsFor(appA).single.url, vmUrl);

      runner.emitSession(appA.id, devtools);
      final opened = vm.actionsFor(appA).single.url;
      expect(_serviceTarget(opened), vmUrl);
      expect(opened, startsWith('http://127.0.0.1:9100?'));
      expect(opened, contains('%3D'));
      expect(vm.actionsFor(appA).single.id, 'devtools');
    });

    test('two flutter apps keep independent sessions', () {
      runner.emit(_run(appA.id, TaskRunStatus.running));
      runner.emit(_run(appB.id, TaskRunStatus.building));
      runner.emitSession(appA.id, devtools);
      runner.emitSession(appB.id, 'http://127.0.0.1:9101?uri=$vmUrl');
      expect(_serviceTarget(vm.actionsFor(appA).single.url), vmUrl);
      expect(
        vm.actionsFor(appA).single.url,
        startsWith('http://127.0.0.1:9100?'),
      );
      expect(_serviceTarget(vm.actionsFor(appB).single.url), vmUrl);
      expect(
        vm.actionsFor(appB).single.url,
        startsWith('http://127.0.0.1:9101?'),
      );
    });

    test('stop clears and the next run uses the new url', () {
      runner.emit(_run(appA.id, TaskRunStatus.running));
      runner.emitSession(appA.id, devtools);
      runner.emit(_run(appA.id, TaskRunStatus.stopped));
      runner.emitSession(appA.id, '');
      expect(vm.actionsFor(appA), isEmpty);

      runner.emit(_run(appA.id, TaskRunStatus.running));
      expect(vm.actionsFor(appA), isEmpty);
      runner.emitSession(appA.id, 'http://127.0.0.1:9102?uri=$vmUrl');
      expect(_serviceTarget(vm.actionsFor(appA).single.url), vmUrl);
      expect(
        vm.actionsFor(appA).single.url,
        startsWith('http://127.0.0.1:9102?'),
      );
    });

    test('non-flutter tasks and invalid urls have no action', () {
      runner.emit(_run(tests.id, TaskRunStatus.running));
      runner.emit(_run(npm.id, TaskRunStatus.running));
      runner.emit(_run(appA.id, TaskRunStatus.running));
      runner.emitSession(tests.id, devtools);
      runner.emitSession(npm.id, devtools);
      runner.emitSession(appA.id, 'not-a-url');
      expect(vm.actionsFor(tests), isEmpty);
      expect(vm.actionsFor(npm), isEmpty);
      expect(vm.actionsFor(appA), isEmpty);
    });
  });
}

String _serviceTarget(String page) {
  final at = page.indexOf('uri=');
  final raw = at < 0 ? page : page.substring(at + 4).split('&').first;
  return Uri.decodeFull(raw);
}

TaskDefinition _task(String id, String command, List<String> args) {
  return TaskDefinition(
    id: id,
    label: id,
    cwd: '/app',
    command: command,
    args: args,
  );
}

TaskRun _run(String id, TaskRunStatus status) =>
    TaskRun(taskId: id, status: status);

class _FixedDiscovery implements TaskDiscovery {
  const _FixedDiscovery(this.tasks);
  final List<TaskDefinition> tasks;

  @override
  Future<List<TaskDefinition>> discover(String cwd) async => tasks;
}

class _MemoryDevices implements DeviceSelectionStore {
  @override
  DevicePreference? read(String cwd, String taskId) => null;

  @override
  Future<void> write(String cwd, String taskId, String deviceId) async {}
}

class _SessionRunner implements TaskRunnerGateway {
  final _runs = StreamController<TaskRun>.broadcast(sync: true);
  final _sessions = StreamController<TaskSessionUrl>.broadcast(sync: true);
  final _states = <String, TaskRun>{};
  final _urls = <String, String>{};

  void emit(TaskRun run) {
    _states[run.taskId] = run;
    _runs.add(run);
  }

  void emitSession(String taskId, String url) {
    if (url.isEmpty) {
      _urls.remove(taskId);
    } else {
      _urls[taskId] = url;
    }
    _sessions.add(TaskSessionUrl(taskId, url));
  }

  @override
  Stream<TaskRun> runs() => _runs.stream;

  @override
  Stream<TaskSessionUrl> sessionUrls() => _sessions.stream;

  @override
  String? sessionUrlOf(String taskId) => _urls[taskId];

  @override
  Stream<TaskPreviewUrl> previewUrls() => const Stream<TaskPreviewUrl>.empty();

  @override
  Stream<String> output(String taskId) => const Stream<String>.empty();

  @override
  TaskRun runOf(String taskId) => _states[taskId] ?? TaskRun.idleFor(taskId);

  @override
  Future<void> start(
    TaskDefinition def, {
    String? profileName,
    List<String> adHocArgs = const [],
    List<String>? argsOverride,
  }) async {}

  @override
  Future<void> stop(String taskId) async {}

  @override
  Future<void> restart(String taskId) async {}

  @override
  void sendKey(String taskId, String key) {}

  @override
  void startWatch(TaskDefinition def) {}

  @override
  void stopWatch(String taskId) {}

  @override
  void resize(String taskId, int rows, int columns) {}

  @override
  Future<void> disposeAll() async {}
}
