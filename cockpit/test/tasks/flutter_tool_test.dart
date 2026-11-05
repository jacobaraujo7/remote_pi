import 'dart:convert';
import 'dart:io';

import 'package:cockpit/app/cockpit/data/tasks/project_paths.dart';
import 'package:cockpit/app/cockpit/data/tasks/tools/dev_tool_registry.dart';
import 'package:cockpit/app/cockpit/data/tasks/tools/flutter_tool.dart';
import 'package:cockpit/app/cockpit/data/tasks/tools/json_device_selection_store.dart';
import 'package:cockpit/app/cockpit/data/tasks/tools/task_device_coordinator.dart';
import 'package:cockpit/app/cockpit/domain/contracts/dev_tool.dart';
import 'package:cockpit/app/cockpit/domain/contracts/device_selection_store.dart';
import 'package:cockpit/app/cockpit/domain/entities/task_definition.dart';
import 'package:cockpit/app/core/data/setup/json_state_store.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const tool = FlutterTool();

  group('match', () {
    test('flutter run and fvm wrappers select a device', () {
      expectRun('flutter', ['run']);
      expectRun('Flutter', ['run']);
      expectRun(r'C:\sdk\bin\flutter.bat', [
        'run',
      ], invocationEndsWith: 'flutter.bat');
      expectRun(
        '/opt/flutter/bin/flutter',
        ['run'],
        invocation: ['/opt/flutter/bin/flutter'],
      );
      expectRun('fvm', ['flutter', 'run'], invocation: ['fvm', 'flutter']);
      expectRun(
        'fvm',
        ['--verbose', 'flutter', 'run'],
        invocation: ['fvm', 'flutter'],
      );
      expectRun(
        'fvm',
        ['spawn', '3.24.0', 'flutter', 'run'],
        invocation: ['fvm', 'spawn', '3.24.0', 'flutter'],
      );
      expectRun('flutter', ['run', '-d', 'chrome'], device: 'chrome');
      expectRun('flutter', ['-d', 'chrome', 'run'], device: 'chrome');
      expectRun('flutter', ['run', '--device-id', 'chrome'], device: 'chrome');
      expectRun('flutter', ['run', '--device-id=chrome'], device: 'chrome');
      expectRun('flutter', ['--verbose', 'run']);
      expectRun('flutter', [
        'run',
        '-d',
        'ios',
        '--device-id',
        'chrome',
      ], device: 'chrome');
    });

    test('build names the platform and does not ask for a device', () {
      expectBuild('flutter', ['build', 'apk'], DevPlatform.android);
      expectBuild('flutter', ['build', 'appbundle'], DevPlatform.android);
      expectBuild('flutter', ['build', 'aar'], DevPlatform.android);
      expectBuild('flutter', [
        'build',
        '--release',
        'apk',
      ], DevPlatform.android);
      expectBuild('flutter', ['build', 'ios'], DevPlatform.ios);
      expectBuild('flutter', ['build', 'ipa'], DevPlatform.ios);
      expectBuild('flutter', ['build', 'macos'], DevPlatform.macos);
      expectBuild('flutter', ['build', 'linux'], DevPlatform.linux);
      expectBuild('flutter', ['build', 'windows'], DevPlatform.windows);
      expectBuild('flutter', ['build', 'web'], DevPlatform.web);
      expectBuild('fvm', ['flutter', 'build', 'apk'], DevPlatform.android);

      final bare = tool.match('flutter', ['build']);
      expect(bare?.operation, DevOperation.buildForPlatform);
      expect(bare?.buildPlatform, isNull);
    });

    test('auxiliary and foreign commands do not select a device', () {
      for (final args in [
        ['analyze'],
        ['test'],
        ['pub', 'get'],
        ['pub', 'run', 'something'],
        ['doctor'],
        ['clean'],
        ['attach'],
        ['drive'],
        ['install'],
      ]) {
        final parsed = tool.match('flutter', args);
        expect(parsed, isNotNull, reason: args.join(' '));
        expect(parsed!.operation, DevOperation.other, reason: args.join(' '));
      }
      expect(tool.match('npm', ['test']), isNull);
      expect(tool.match('npm', ['run', 'flutter']), isNull);
      expect(tool.match('echo', ['flutter', 'run']), isNull);
      expect(tool.match('dart', ['run']), isNull);
      expect(tool.match('fvm', ['use', 'stable']), isNull);
      expect(tool.match('fvm', ['dart', 'run']), isNull);
      expect(tool.match('fvm', ['spawn', '3.24.0', 'dart', 'run']), isNull);
    });
  });

  group('withDevice', () {
    test('appends a single -d and keeps the other arguments', () {
      expect(
        tool.withDevice([
          'run',
          '--release',
          '--dart-define',
          'FOO=bar',
        ], 'macos'),
        ['run', '--release', '--dart-define', 'FOO=bar', '-d', 'macos'],
      );
    });

    test('leaves the argv untouched when it already targets that device', () {
      final short = ['run', '-d', 'chrome', '--release'];
      expect(tool.withDevice(short, 'chrome'), same(short));
      final long = ['run', '--device-id=chrome'];
      expect(tool.withDevice(long, 'chrome'), same(long));
      final spaced = ['run', '--device-id', 'chrome', '--release'];
      expect(tool.withDevice(spaced, 'chrome'), same(spaced));
    });

    test('replaces a different device and drops duplicates', () {
      expect(
        tool.withDevice(['run', '--device-id', 'chrome', '--release'], 'macos'),
        ['run', '--release', '-d', 'macos'],
      );
      expect(tool.withDevice(['run', '-d', 'ios', '-d', 'chrome'], 'chrome'), [
        'run',
        '-d',
        'chrome',
      ]);
    });
  });

  group('prefer', () {
    const macos = DevDevice(
      id: 'macos',
      name: 'macOS',
      platform: DevPlatform.macos,
    );
    const windows = DevDevice(
      id: 'windows',
      name: 'Windows',
      platform: DevPlatform.windows,
    );
    const linux = DevDevice(
      id: 'linux',
      name: 'Linux',
      platform: DevPlatform.linux,
    );
    const iphone = DevDevice(
      id: 'iphone',
      name: 'iPhone',
      platform: DevPlatform.ios,
    );
    const pixel = DevDevice(
      id: 'emulator-5554',
      name: 'Pixel',
      platform: DevPlatform.android,
    );
    const chrome = DevDevice(
      id: 'chrome',
      name: 'Chrome',
      platform: DevPlatform.web,
    );

    test('picks the host desktop when the project enables it', () {
      expect(
        tool
            .prefer(
              HostOs.macos,
              {DevPlatform.macos, DevPlatform.ios},
              [iphone, macos],
            )
            ?.id,
        'macos',
      );
      expect(
        tool
            .prefer(
              HostOs.windows,
              {DevPlatform.windows, DevPlatform.android},
              [pixel, windows],
            )
            ?.id,
        'windows',
      );
      expect(
        tool
            .prefer(
              HostOs.linux,
              {DevPlatform.linux, DevPlatform.android},
              [pixel, linux],
            )
            ?.id,
        'linux',
      );
    });

    test('on macOS a mobile-only project prefers an iOS device', () {
      expect(
        tool
            .prefer(
              HostOs.macos,
              {DevPlatform.android, DevPlatform.ios},
              [pixel, iphone],
            )
            ?.id,
        'iphone',
      );
      expect(
        tool.prefer(HostOs.macos, {DevPlatform.android}, [pixel])?.id,
        'emulator-5554',
      );
    });

    test('without the native platform, picks another compatible device', () {
      expect(
        tool
            .prefer(
              HostOs.linux,
              {DevPlatform.android, DevPlatform.ios},
              [iphone, pixel],
            )
            ?.id,
        'iphone',
      );
      expect(
        tool
            .prefer(
              HostOs.macos,
              {DevPlatform.ios, DevPlatform.web},
              [chrome, iphone],
            )
            ?.id,
        'chrome',
      );
    });

    test('never picks a platform the project does not enable', () {
      expect(
        tool.prefer(HostOs.linux, {DevPlatform.android}, [linux, pixel])?.id,
        'emulator-5554',
      );
      expect(
        tool.prefer(HostOs.macos, {DevPlatform.android}, [macos, linux]),
        isNull,
      );
      expect(tool.prefer(HostOs.macos, {DevPlatform.ios}, const []), isNull);
    });
  });

  group('platforms and devices', () {
    late Directory root;

    setUp(() async {
      root = await Directory.systemTemp.createTemp('flutter_tool_test');
    });

    tearDown(() async {
      if (await root.exists()) await root.delete(recursive: true);
    });

    test('platforms are the folders present in that project', () async {
      await Directory(joinPath(root.path, 'android')).create();
      await Directory(joinPath(root.path, 'ios')).create();
      expect(await tool.platforms(root.path), {
        DevPlatform.android,
        DevPlatform.ios,
      });

      final other = await Directory.systemTemp.createTemp('flutter_tool_other');
      addTearDown(() async {
        if (await other.exists()) await other.delete(recursive: true);
      });
      await Directory(joinPath(other.path, 'linux')).create();
      expect(await tool.platforms(other.path), {DevPlatform.linux});
    });

    test(
      'devices keeps supported project platforms and the tool prefix',
      () async {
        await Directory(joinPath(root.path, 'android')).create();
        await Directory(joinPath(root.path, 'ios')).create();
        String? executable;
        List<String>? arguments;
        final probing = FlutterTool(
          runProcess: (exe, args, {workingDirectory}) async {
            executable = exe;
            arguments = args;
            expect(workingDirectory, root.path);
            return ProcessResult(
              0,
              0,
              jsonEncode([
                {
                  'name': 'Pixel',
                  'id': 'emulator-5554',
                  'isSupported': true,
                  'targetPlatform': 'android-arm64',
                },
                {
                  'name': 'Broken',
                  'id': 'offline-android',
                  'isSupported': false,
                  'targetPlatform': 'android-arm64',
                },
                {
                  'name': 'iPhone',
                  'id': 'iphone',
                  'isSupported': true,
                  'targetPlatform': 'ios',
                },
                {
                  'name': 'Linux',
                  'id': 'linux',
                  'isSupported': true,
                  'targetPlatform': 'linux-x64',
                },
                {
                  'name': 'Chrome',
                  'id': 'chrome',
                  'isSupported': true,
                  'targetPlatform': 'web-javascript',
                },
                {
                  'name': 'Mac',
                  'id': 'macos',
                  'isSupported': true,
                  'targetPlatform': 'darwin',
                },
              ]),
              '',
            );
          },
        );
        final parsed = probing.match('fvm', ['flutter', 'run'])!;
        final devices = await probing.devices(root.path, parsed);
        expect(executable, 'fvm');
        expect(arguments, ['flutter', 'devices', '--machine']);
        expect(devices.map((d) => d.id), ['emulator-5554', 'iphone']);
      },
    );
  });

  test('a later tool does not take Flutter commands', () {
    final registry = DevToolRegistry([const FlutterTool(), _EchoTool()]);
    expect(registry.match('flutter', ['run'])!.toolId, 'flutter');
    expect(registry.match('flutter', ['test'])!.operation, DevOperation.other);
    expect(registry.match('echo-tool', const [])!.toolId, 'echo');
    expect(registry.match('npm', ['test']), isNull);

    final reversed = DevToolRegistry([_EchoTool(), const FlutterTool()]);
    expect(reversed.match('flutter', ['run'])!.toolId, 'flutter');
    expect(reversed.match('echo-tool', const [])!.toolId, 'echo');
  });

  test('manual preference is stored per task and read back', () async {
    final dir = await Directory.systemTemp.createTemp('task_devices_store');
    final store = await JsonStateStore.open(
      dir.path,
      JsonDeviceSelectionStore.storeName,
    );
    addTearDown(() async {
      JsonStateStore.resetCacheForTesting();
      if (await dir.exists()) await dir.delete(recursive: true);
    });
    final selection = JsonDeviceSelectionStore(store);
    await selection.write('/app', 'json:a', 'iphone');
    await selection.write('/app', 'json:b', 'emulator-5554');
    await selection.write('/other', 'json:a', 'linux');
    expect(selection.read('/app', 'json:a')?.deviceId, 'iphone');
    expect(selection.read('/app', 'json:b')?.deviceId, 'emulator-5554');
    expect(selection.read('/other', 'json:a')?.deviceId, 'linux');

    await store.flush();
    JsonStateStore.resetCacheForTesting();
    final reopened = await JsonStateStore.open(
      dir.path,
      JsonDeviceSelectionStore.storeName,
    );
    expect(
      JsonDeviceSelectionStore(reopened).read('/app', 'json:a')?.deviceId,
      'iphone',
    );
  });

  test('explicit -d is kept and a missing one is not replaced', () async {
    final root = await Directory.systemTemp.createTemp('flutter_explicit');
    addTearDown(() async {
      if (await root.exists()) await root.delete(recursive: true);
    });
    await Directory(joinPath(root.path, 'android')).create();
    await Directory(joinPath(root.path, 'ios')).create();
    final probing = FlutterTool(
      runProcess: (exe, args, {workingDirectory}) async => ProcessResult(
        0,
        0,
        jsonEncode([
          {
            'name': 'Pixel',
            'id': 'emulator-5554',
            'isSupported': true,
            'targetPlatform': 'android-arm64',
          },
          {
            'name': 'iPhone',
            'id': 'iphone',
            'isSupported': true,
            'targetPlatform': 'ios',
          },
        ]),
        '',
      ),
    );
    final coordinator = TaskDeviceCoordinator(
      DevToolRegistry([probing]),
      _MemoryDevices(),
      HostOs.macos,
    );
    final pinned = TaskDefinition(
      id: 'json:pinned',
      label: 'pinned',
      cwd: root.path,
      command: 'flutter',
      args: const ['run', '-d', 'iphone', '--release'],
    );
    final plan = await coordinator.plan(
      pinned,
      profileName: null,
      remote: false,
    );
    expect(plan.blocked, isFalse);
    expect(plan.argsOverride, pinned.args);

    final missing = TaskDefinition(
      id: 'json:missing',
      label: 'missing',
      cwd: root.path,
      command: 'flutter',
      args: const ['run', '-d', 'chrome'],
    );
    final blocked = await coordinator.plan(
      missing,
      profileName: null,
      remote: false,
    );
    expect(blocked.blocked, isTrue);
    expect(
      coordinator
          .snapshot(missing, profileName: null, remote: false)
          .selectedId,
      'chrome',
    );

    final remote = await coordinator.plan(
      pinned,
      profileName: null,
      remote: true,
    );
    expect(remote.blocked, isFalse);
    expect(remote.argsOverride, isNull);
    expect(
      coordinator.offers(pinned, profileName: null, remote: true),
      isFalse,
    );
  });

  group('devtools session', () {
    const vm = 'http://127.0.0.1:54321/AbCdEf=/';
    const devtools = 'http://127.0.0.1:9100?uri=$vm';

    ParsedDevCommand run() => tool.match('flutter', ['run'])!;

    test('prefers the DevTools URL and consumes both', () {
      final hint = tool.inspectOutput(run(), '''
A Dart VM Service on macOS is available at: $vm
The Flutter DevTools debugger and profiler on macOS is available at: $devtools
''');
      expect(hint, isNotNull);
      expect(hint!.sessionUrl, devtools);
      expect(hint.consumedUrls, [devtools, vm]);
    });

    test('falls back to the VM Service URI', () {
      final hint = tool.inspectOutput(
        run(),
        'A Dart VM Service on iPhone is available at: $vm\n',
      );
      expect(hint!.sessionUrl, vm);
      expect(hint.consumedUrls, [vm]);
    });

    test('ignores other flutter commands and invalid urls', () {
      const line = 'A Dart VM Service on macOS is available at: $vm\n';
      expect(
        tool.inspectOutput(tool.match('flutter', ['test'])!, line),
        isNull,
      );
      expect(
        tool.inspectOutput(tool.match('flutter', ['build', 'apk'])!, line),
        isNull,
      );
      expect(
        tool.inspectOutput(
          run(),
          'The Flutter DevTools debugger is available at: ftp://127.0.0.1/x\n',
        ),
        isNull,
      );
      expect(tool.action(run(), sessionUrl: 'not a url'), isNull);
      expect(
        tool.action(tool.match('flutter', ['test'])!, sessionUrl: vm),
        isNull,
      );
    });

    test('action is only the devtools opener', () {
      final action = tool.action(run(), sessionUrl: devtools);
      expect(action, isNotNull);
      expect(action!.id, 'devtools');
      expect(action.icon, 'devtools');
      expect(_serviceTarget(action.url), vm);
      expect(action.url, contains('%3D'));
      expect(action.label, 'Open DevTools');
    });

    test('a service uri cut before the auth padding is not opened', () {
      const cut = 'http://127.0.0.1:9100?uri=ws://127.0.0.1:46075/vNzGJsPDZ';
      expect(tool.action(run(), sessionUrl: cut), isNull);
      final hint = tool.inspectOutput(
        run(),
        'The Flutter DevTools debugger and profiler on Linux is available at: $cut\n',
      );
      expect(hint!.sessionUrl, isNull);
      expect(hint.consumedUrls, [cut]);
    });

    test('registry does not claim npm output', () {
      final registry = DevToolRegistry(const [FlutterTool()]);
      expect(
        registry.inspectOutput('npm', ['run', 'dev'], 'available at: $vm'),
        isNull,
      );
      expect(registry.action('npm', ['run', 'dev'], sessionUrl: vm), isNull);
    });
  });
}

String _serviceTarget(String page) {
  final at = page.indexOf('uri=');
  final raw = at < 0 ? page : page.substring(at + 4).split('&').first;
  return Uri.decodeFull(raw);
}

void expectRun(
  String command,
  List<String> args, {
  String? device,
  List<String>? invocation,
  String? invocationEndsWith,
}) {
  final parsed = const FlutterTool().match(command, args);
  expect(parsed, isNotNull, reason: '$command ${args.join(' ')}');
  expect(parsed!.operation, DevOperation.runOnDevice);
  expect(parsed.explicitDeviceId, device);
  if (invocation != null) expect(parsed.invocation, invocation);
  if (invocationEndsWith != null) {
    expect(
      parsed.invocation.single.toLowerCase(),
      endsWith(invocationEndsWith),
    );
  }
}

void expectBuild(String command, List<String> args, DevPlatform platform) {
  final parsed = const FlutterTool().match(command, args);
  expect(parsed, isNotNull, reason: args.join(' '));
  expect(parsed!.operation, DevOperation.buildForPlatform);
  expect(parsed.buildPlatform, platform);
}

class _EchoTool implements DevTool {
  @override
  String get id => 'echo';

  @override
  ParsedDevCommand? match(String command, List<String> args) {
    if (command != 'echo-tool') return null;
    return ParsedDevCommand(
      toolId: id,
      operation: DevOperation.other,
      invocation: [command],
    );
  }
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
