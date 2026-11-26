// Run explicitly: flutter test --no-pub tool/benchmark_shell_spawn_test.dart --reporter expanded
// Uses the same PowerShell invocation policy/profile for every sample, including
// the user's profile. Does not alter profile, terminal settings or app sessions.
import 'dart:convert';
import 'dart:io';

import 'package:cockpit/app/core/data/diagnostics/performance_diagnostics.dart';
import 'package:cockpit/app/core/domain/entities/terminal_profile.dart';
import 'package:cockpit/app/core/utils/shell_command.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    '20 sequential and 20 shell commands at concurrency four',
    () async {
      const profile = TerminalProfile(
        id: TerminalProfile.powershellId,
        label: 'PowerShell',
        executable: 'powershell.exe',
      );
      final diagnostics = PerformanceDiagnostics.instance;
      final previousEnabled = diagnostics.enabled;
      final previousSink = diagnostics.sink;
      final events = <Map<String, Object>>[];
      final rows = <Map<String, Object>>[];
      diagnostics.enabled = true;
      diagnostics.flush();
      diagnostics.sink = (metric, fields) =>
          events.add({'metric': metric, ...fields});
      try {
        Future<void> probe() async {
          final result = await runShellCommand(
            "[Console]::WriteLine('cockpit-spawn-probe')",
            profile: profile,
            operation: ShellCommandOperation.benchmark,
          );
          expect(result.code, 0);
          expect(result.stdout, contains('cockpit-spawn-probe'));
          // Every invocation has exactly one completion; its ID links all phases.
          // Flush after each batch below, then group using that ID.
        }

        for (var i = 0; i < 20; i++) {
          await probe();
        }
        diagnostics.flush();
        rows.addAll(events.map((e) => {'phase': 'sequential', ...e}));
        events.clear();
        for (var start = 0; start < 20; start += 4) {
          await Future.wait([for (var i = start; i < start + 4; i++) probe()]);
        }
        diagnostics.flush();
        rows.addAll(events.map((e) => {'phase': 'concurrent4', ...e}));
        for (final phase in ['sequential', 'concurrent4']) {
          for (final metric in ['spawn', 'shellFirstOutput', 'shellComplete']) {
            expect(
              rows.where((e) => e['phase'] == phase && e['metric'] == metric),
              hasLength(20),
            );
          }
        }
        final summaries = <String, Object>{};
        for (final phase in ['sequential', 'concurrent4']) {
          summaries[phase] = {
            for (final metric in ['spawn', 'shellFirstOutput', 'shellComplete'])
              metric: _summary(
                rows
                    .where((e) => e['phase'] == phase && e['metric'] == metric)
                    .map((e) => e['durationUs'] as int)
                    .toList(),
              ),
          };
        }
        final output = File('build/benchmarks/shell-spawn.json');
        await output.parent.create(recursive: true);
        await output.writeAsString(
          const JsonEncoder.withIndent('  ').convert({
            'profile': 'powershell',
            'measurementContext': 'flutter test (debug)',
            'platform': Platform.operatingSystem,
            'dartVersion': Platform.version,
            'samplesPerPhase': 20,
            'concurrency': {'sequential': 1, 'concurrent4': 4},
            'summaries': summaries,
            'samples': rows,
          }),
        );
        // ignore: avoid_print
        print(jsonEncode({'output': output.path, 'summaries': summaries}));
      } finally {
        diagnostics.flush();
        diagnostics.sink = previousSink;
        diagnostics.enabled = previousEnabled;
      }
    },
    skip: !Platform.isWindows,
    timeout: const Timeout(Duration(minutes: 10)),
  );
}

Map<String, int> _summary(List<int> values) {
  values.sort();
  return {
    'minUs': values.first,
    'p50Us': values[((values.length - 1) * .5).round()],
    'p95Us': values[((values.length - 1) * .95).round()],
    'maxUs': values.last,
    'over2s': values.where((v) => v > 2000000).length,
  };
}
