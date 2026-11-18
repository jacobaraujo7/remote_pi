import 'dart:io';

import 'package:cockpit/app/cockpit/data/tasks/pty_task_runner.dart';
import 'package:cockpit/app/cockpit/data/tasks/tools/dev_tool_registry.dart';
import 'package:cockpit/app/cockpit/domain/contracts/telemetry_ingest.dart';
import 'package:cockpit/app/cockpit/domain/entities/task_definition.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'Compose uses merged env for build, status, restart, logs and stop',
    () async {
      final tmp = await Directory.systemTemp.createTemp('compose_env');
      addTearDown(() => tmp.delete(recursive: true));
      final capture = File('${tmp.path}/capture');
      final engine = File('${tmp.path}/docker');
      await engine.writeAsString(r'''#!/bin/sh
printf '%s|%s|%s\n' "$*" "$API_URL" "$LOG_LEVEL" >> "$CAPTURE"
case "$*" in
  *'ps --services'*) echo api ;;
esac
''');
      expect((await Process.run('chmod', ['+x', engine.path])).exitCode, 0);
      final task = TaskDefinition(
        id: 'json:api',
        label: 'api',
        cwd: tmp.path,
        command: engine.path,
        args: const ['compose', '-f', 'compose.yml'],
        env: {
          'API_URL': 'https://api.example.com',
          'LOG_LEVEL': 'info',
          'CAPTURE': capture.path,
          'PATH': '${tmp.path}:${Platform.environment['PATH']}',
        },
        profiles: const [
          TaskProfile(
            name: 'build',
            args: ['build', 'api'],
            env: {'LOG_LEVEL': 'debug'},
          ),
        ],
      );
      final runner = PtyTaskRunner(_NoTelemetry(), DevToolRegistry([]));
      addTearDown(runner.disposeAll);
      await runner.start(task, profileName: 'build');
      await runner.reconcileDefinitions([task]);
      await runner.restart(task.id);
      // logs writes asynchronously after Process.start.
      for (
        var i = 0;
        i < 100 && !capture.readAsStringSync().contains('logs --tail');
        i++
      ) {
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
      await runner.stop(task.id);
      final lines = await capture.readAsLines();
      for (final command in [
        'build api',
        'ps --services',
        'restart api',
        'logs --tail',
        'stop api',
      ]) {
        final matching = lines.where((line) => line.contains(command));
        expect(matching, isNotEmpty, reason: command);
        expect(
          matching,
          everyElement(endsWith('|https://api.example.com|debug')),
        );
      }
    },
    skip: Platform.isWindows,
  );
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
