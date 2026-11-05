import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:cockpit/app/cockpit/data/tasks/project_paths.dart';
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
  late Directory workspace;
  late Directory mobile;
  late Directory desktop;
  late Directory empty;
  late List<Map<String, Object?>> mobileDevices;
  late _RecordingRunner runner;
  late TasksViewModel vm;

  setUp(() async {
    workspace = await Directory.systemTemp.createTemp('task_device_ws');
    mobile = await Directory.systemTemp.createTemp('task_device_mobile');
    desktop = await Directory.systemTemp.createTemp('task_device_desktop');
    empty = await Directory.systemTemp.createTemp('task_device_empty');
    await Directory(joinPath(mobile.path, 'android')).create();
    await Directory(joinPath(mobile.path, 'ios')).create();
    await Directory(joinPath(desktop.path, 'linux')).create();
    mobileDevices = [
      _device('Pixel', 'emulator-5554', 'android-arm64'),
      _device('iPhone', 'iphone', 'ios'),
      _device('Linux', 'linux', 'linux-x64', supported: false),
    ];
    runner = _RecordingRunner();
    vm = TasksViewModel(
      _FixedDiscovery([
        _run('json:a', mobile.path, const [
          'run',
          '--release',
          '--dart-define',
          'FOO=bar',
        ]),
        _run('json:b', desktop.path, const ['run']),
        _run('json:empty', empty.path, const ['run']),
        TaskDefinition(
          id: 'json:test',
          label: 'test',
          cwd: mobile.path,
          command: 'flutter',
          args: const ['test'],
        ),
        TaskDefinition(
          id: 'json:analyze',
          label: 'analyze',
          cwd: mobile.path,
          command: 'flutter',
          args: const ['analyze'],
        ),
        TaskDefinition(
          id: 'json:pub',
          label: 'pub',
          cwd: mobile.path,
          command: 'flutter',
          args: const ['pub', 'get'],
        ),
        TaskDefinition(
          id: 'json:build',
          label: 'build',
          cwd: mobile.path,
          command: 'flutter',
          args: const ['build', 'apk'],
        ),
        TaskDefinition(
          id: 'json:npm',
          label: 'npm',
          cwd: mobile.path,
          command: 'npm',
          args: const ['run', 'dev'],
        ),
      ]),
      runner,
      TaskDeviceCoordinator(
        DevToolRegistry([
          FlutterTool(
            runProcess: (exe, args, {workingDirectory}) async {
              final listed = workingDirectory == desktop.path
                  ? [
                      _device('Linux', 'linux', 'linux-x64'),
                      _device('Chrome', 'chrome', 'web-javascript'),
                    ]
                  : mobileDevices;
              return ProcessResult(0, 0, jsonEncode(listed), '');
            },
          ),
        ]),
        _MemoryDevices(),
        HostOs.macos,
      ),
    );
  });

  tearDown(() async {
    vm.dispose();
    for (final dir in [workspace, mobile, desktop, empty]) {
      if (await dir.exists()) await dir.delete(recursive: true);
    }
  });

  TaskDefinition task(String id) => vm.tasks.firstWhere((t) => t.id == id);

  test(
    'each flutter run keeps its own device and other tasks stay plain',
    () async {
      await vm.loadFor(workspace.path);

      final a = vm.deviceState(task('json:a'));
      final b = vm.deviceState(task('json:b'));
      expect(a.offered, isTrue);
      expect(a.selectedId, 'iphone');
      expect(a.selectedName, 'iPhone');
      expect(a.devices.map((d) => d.id), ['emulator-5554', 'iphone']);
      expect(b.offered, isTrue);
      expect(b.selectedId, 'linux');
      expect(b.devices.map((d) => d.id), ['linux']);
      for (final id in [
        'json:test',
        'json:analyze',
        'json:pub',
        'json:build',
        'json:npm',
      ]) {
        expect(vm.deviceState(task(id)).offered, isFalse, reason: id);
      }
      expect(vm.commandPreview(task('json:a')), contains('-d iphone'));

      await vm.selectDevice(task('json:a'), 'emulator-5554');
      expect(vm.deviceState(task('json:a')).selectedId, 'emulator-5554');
      expect(vm.deviceState(task('json:b')).selectedId, 'linux');

      mobileDevices = [
        _device('iPhone', 'iphone', 'ios'),
        _device('macOS', 'macos', 'darwin'),
      ];
      await vm.refreshDevices(task('json:a'));
      expect(vm.deviceState(task('json:a')).selectedId, 'emulator-5554');
      expect(vm.deviceState(task('json:a')).unavailable, isTrue);
      expect(vm.deviceState(task('json:a')).canStart, isFalse);
      expect(await vm.start(task('json:a')), isFalse);
      expect(runner.starts, isEmpty);

      mobileDevices = [
        _device('Pixel', 'emulator-5554', 'android-arm64'),
        _device('iPhone', 'iphone', 'ios'),
      ];
      await vm.refreshDevices(task('json:a'));
      final restored = vm.deviceState(task('json:a'));
      expect(restored.selectedId, 'emulator-5554');
      expect(restored.selectedName, 'Pixel');
      expect(restored.unavailable, isFalse);
      expect(restored.canStart, isTrue);
      expect(vm.deviceState(task('json:b')).selectedId, 'linux');

      expect(await vm.start(task('json:a')), isTrue);
      final args = runner.starts.single.args;
      expect(args, isNotNull);
      expect(
        args,
        containsAll(['run', '--release', '--dart-define', 'FOO=bar']),
      );
      expect(args!.where((arg) => arg == '-d'), ['-d']);
      expect(args[args.indexOf('-d') + 1], 'emulator-5554');

      runner.emit(
        TaskRun(taskId: 'json:a', status: TaskRunStatus.failed, exitCode: 1),
      );
      final failed = vm.stateOf('json:a');
      expect(failed.isActive, isFalse);
      expect(failed.isTransitioning, isFalse);
      expect(vm.deviceState(task('json:a')).selectedId, 'emulator-5554');
      expect(vm.deviceState(task('json:a')).offered, isTrue);

      runner.emit(TaskRun(taskId: 'json:a', status: TaskRunStatus.stopped));
      expect(vm.stateOf('json:a').isActive, isFalse);
      expect(vm.deviceState(task('json:a')).selectedId, 'emulator-5554');

      expect(await vm.start(task('json:npm')), isTrue);
      expect(runner.starts.last.args, isNull);
      expect(await vm.start(task('json:empty')), isFalse);
    },
  );

  test('automatic choice follows the list until the user picks', () async {
    mobileDevices = [_device('Pixel', 'emulator-5554', 'android-arm64')];
    await vm.loadFor(workspace.path);
    expect(vm.deviceState(task('json:a')).selectedId, 'emulator-5554');

    mobileDevices = [
      _device('Pixel', 'emulator-5554', 'android-arm64'),
      _device('iPhone', 'iphone', 'ios'),
    ];
    await vm.refreshDevices(task('json:a'));
    expect(vm.deviceState(task('json:a')).selectedId, 'iphone');

    await vm.selectDevice(task('json:a'), 'emulator-5554');
    await vm.refreshDevices(task('json:a'));
    expect(vm.deviceState(task('json:a')).selectedId, 'emulator-5554');
  });

  test('a remote workspace does not inject a local device', () async {
    final remoteRunner = _RecordingRunner();
    vm.remoteContextFor = (_) => (
      discovery: _FixedDiscovery([
        _run('json:remote', mobile.path, const ['run']),
      ]),
      runner: remoteRunner,
    );
    await vm.loadFor('/remote/project');
    expect(vm.deviceState(task('json:remote')).offered, isFalse);
    expect(await vm.start(task('json:remote')), isTrue);
    expect(remoteRunner.starts.single.args, isNull);
    expect(runner.starts, isEmpty);
  });
}

Map<String, Object?> _device(
  String name,
  String id,
  String target, {
  bool supported = true,
}) => {
  'name': name,
  'id': id,
  'isSupported': supported,
  'targetPlatform': target,
};

TaskDefinition _run(String id, String cwd, List<String> args) =>
    TaskDefinition(id: id, label: id, cwd: cwd, command: 'flutter', args: args);

class _FixedDiscovery implements TaskDiscovery {
  _FixedDiscovery(this.tasks);

  final List<TaskDefinition> tasks;

  @override
  Future<List<TaskDefinition>> discover(String cwd) async => tasks;
}

class _MemoryDevices implements DeviceSelectionStore {
  final _values = <String, String>{};

  @override
  DevicePreference? read(String cwd, String taskId) {
    final id = _values['$cwd\u0000$taskId'];
    if (id == null) return null;
    return DevicePreference(deviceId: id);
  }

  @override
  Future<void> write(String cwd, String taskId, String deviceId) async {
    _values['$cwd\u0000$taskId'] = deviceId;
  }
}

class _Start {
  _Start(this.args);
  final List<String>? args;
}

class _RecordingRunner implements TaskRunnerGateway {
  final starts = <_Start>[];
  final _runs = StreamController<TaskRun>.broadcast(sync: true);
  final _states = <String, TaskRun>{};

  void emit(TaskRun run) {
    _states[run.taskId] = run;
    _runs.add(run);
  }

  @override
  Stream<TaskRun> runs() => _runs.stream;

  @override
  Stream<TaskPreviewUrl> previewUrls() => const Stream<TaskPreviewUrl>.empty();

  @override
  Stream<TaskSessionUrl> sessionUrls() => const Stream<TaskSessionUrl>.empty();

  @override
  String? sessionUrlOf(String taskId) => null;

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
  }) async {
    starts.add(_Start(argsOverride));
    emit(
      TaskRun(
        taskId: def.id,
        status: TaskRunStatus.running,
        profileName: profileName,
      ),
    );
  }

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
