import 'dart:io';

import 'package:cockpit/app/core/data/diagnostics/performance_diagnostics.dart';
import 'package:cockpit/app/core/data/diagnostics/diagnostics_log.dart';
import 'package:cockpit/app/core/domain/entities/terminal_profile.dart';
import 'package:cockpit/app/core/utils/shell_command.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final diagnostics = PerformanceDiagnostics.instance;
  final samples = <Map<String, Object>>[];
  late bool wasEnabled;
  late PerfSink previousSink;
  final profile = TerminalProfile(
    id: Platform.isWindows
        ? TerminalProfile.cmdId
        : TerminalProfile.loginShellId,
    label: 'test shell',
    executable: Platform.isWindows ? 'cmd.exe' : '/bin/sh',
  );

  setUp(() {
    wasEnabled = diagnostics.enabled;
    previousSink = diagnostics.sink;
    diagnostics.enabled = true;
    diagnostics.flush();
    samples.clear();
    diagnostics.sink = (metric, fields) =>
        samples.add({'metric': metric, ...fields});
  });

  tearDown(() {
    diagnostics.flush();
    diagnostics.sink = previousSink;
    diagnostics.enabled = wasEnabled;
  });

  test(
    'correlates spawn, first output and completion without command data',
    () async {
      final result = await runShellCommand(
        'echo private-command-marker',
        profile: profile,
        operation: ShellCommandOperation.cliExec,
        environment: {'PRIVATE_VALUE': 'private-environment-marker'},
      );
      diagnostics.flush();
      expect(result.code, 0);
      expect(result.stdout.trim(), 'private-command-marker');
      expect(result.toJson().keys, ['code', 'stdout', 'stderr', 'timedOut']);
      expect(samples.map((e) => e['metric']), [
        'spawn',
        'shellFirstOutput',
        'shellComplete',
      ]);
      expect(samples.map((e) => e['invocation']).toSet(), hasLength(1));
      expect(
        samples.map((e) => e['operation']),
        everyElement(ShellCommandOperation.cliExec.id),
      );
      final durations = samples.map((e) => e['durationUs'] as int).toList();
      expect(durations[1], greaterThanOrEqualTo(durations[0]));
      expect(durations[2], greaterThanOrEqualTo(durations[1]));
      expect(samples.toString(), isNot(contains('private-command-marker')));
      expect(samples.toString(), isNot(contains('private-environment-marker')));
      for (final sample in samples) {
        expect(
          sample.entries.where((e) => e.key != 'metric').map((e) => e.value),
          everyElement(isA<num>()),
        );
      }
    },
  );

  test('stderr counts as first output only once across both streams', () async {
    final result = await runShellCommand(
      Platform.isWindows
          ? 'echo error 1>&2 & echo output'
          : 'echo error >&2; echo output',
      profile: profile,
    );
    diagnostics.flush();
    expect(result.stderr, contains('error'));
    expect(result.stdout, contains('output'));
    expect(
      samples.where((e) => e['metric'] == 'shellFirstOutput'),
      hasLength(1),
    );
  });

  test('silent completion does not invent a first-output sample', () async {
    final result = await runShellCommand(
      Platform.isWindows ? 'exit /b 0' : 'exit 0',
      profile: profile,
    );
    diagnostics.flush();
    expect(result.code, 0);
    expect(samples.map((e) => e['metric']), ['spawn', 'shellComplete']);
  });

  test(
    'concurrent invocations retain distinct operation correlations',
    () async {
      await Future.wait([
        runShellCommand(
          'echo panel',
          profile: profile,
          operation: ShellCommandOperation.panelCommand,
        ),
        runShellCommand(
          'echo cli',
          profile: profile,
          operation: ShellCommandOperation.cliExec,
        ),
      ]);
      diagnostics.flush();
      final ids = samples.map((e) => e['invocation']).toSet();
      expect(ids, hasLength(2));
      for (final id in ids) {
        final invocation = samples.where((e) => e['invocation'] == id).toList();
        expect(invocation.map((e) => e['metric']), [
          'spawn',
          'shellFirstOutput',
          'shellComplete',
        ]);
        expect(invocation.map((e) => e['operation']).toSet(), hasLength(1));
      }
    },
  );

  test(
    'spawn failure records failed completion without exporting arguments',
    () async {
      final records = <DiagnosticsRecord>[];
      final log = DiagnosticsLog.instance;
      final previousLogSink = log.telemetrySink;
      log.telemetrySink = records.add;
      addTearDown(() => log.telemetrySink = previousLogSink);
      final result = await runShellCommand(
        'private-command-marker',
        profile: const TerminalProfile(
          id: TerminalProfile.cmdId,
          label: 'missing',
          executable: 'cockpit-definitely-absent-shell-783b',
        ),
      );
      diagnostics.flush();
      expect(result.code, 127);
      expect(samples.map((e) => e['metric']), ['spawn', 'shellComplete']);
      expect(samples.map((e) => e['failed']), everyElement(1));
      expect(samples.toString(), isNot(contains('private-command-marker')));
      expect(records, hasLength(1));
      expect(records.single.message, contains('operation unspecified'));
      expect(records.single.message, isNot(contains('private-command-marker')));
      expect(records.single.error, isNull);
    },
  );

  test(
    'late inherited-pipe output cannot follow the completion metric',
    () async {
      final buildDirectory = await Directory('build').create(recursive: true);
      final directory = await buildDirectory.createTemp('late-output-');
      final script = File('${directory.path}/late.cmd');
      final marker = File('${directory.path}/finished');
      addTearDown(() async {
        if (await script.exists()) await script.delete();
        if (await marker.exists()) await marker.delete();
        await directory.delete();
      });
      await script.writeAsString(
        '@echo off\r\n'
        'ping -n 5 127.0.0.1 >nul\r\n'
        'echo late-output\r\n'
        'echo finished> "%~dp0finished"\r\n',
      );
      final result = await runShellCommand(
        'start /b cmd.exe /d /c call ${script.path.replaceAll('/', r'\')}',
        profile: profile,
      );
      diagnostics.flush();
      expect(result.code, 0);
      expect(samples.map((e) => e['metric']), ['spawn', 'shellComplete']);
      // The parent has exited but the child still owns both inherited pipes.
      // This proves the bounded drain expired before the child produced output.
      expect(samples.last['durationUs'] as int, greaterThanOrEqualTo(1800000));
      expect(await marker.exists(), isFalse);
      final deadline = DateTime.now().add(const Duration(seconds: 10));
      while (!await marker.exists() && DateTime.now().isBefore(deadline)) {
        await Future<void>.delayed(const Duration(milliseconds: 100));
      }
      expect(await marker.exists(), isTrue);
      // Yield once after the child writes, then flush any late stream callback.
      await Future<void>.delayed(const Duration(milliseconds: 100));
      diagnostics.flush();
      expect(samples.map((e) => e['metric']), ['spawn', 'shellComplete']);
    },
    skip: !Platform.isWindows,
  );

  test(
    'timeout is marked on completion without changing result contract',
    () async {
      final result = await runShellCommand(
        Platform.isWindows ? 'ping -n 6 127.0.0.1 >nul' : 'sleep 5',
        profile: profile,
        timeout: const Duration(milliseconds: 100),
      );
      diagnostics.flush();
      expect(result.code, 124);
      expect(result.timedOut, isTrue);
      final completed = samples.singleWhere(
        (e) => e['metric'] == 'shellComplete',
      );
      expect(completed['timedOut'], 1);
      expect(completed['failed'], 1);
    },
  );
}
