import 'dart:convert';
import 'dart:io';

import 'package:cockpit/app/cockpit/domain/contracts/process_tree_provider.dart';
import 'package:cockpit/app/core/data/diagnostics/diagnostics_log.dart';
import 'package:cockpit/app/cockpit/domain/entities/process_snapshot.dart';

typedef ProcessRunner =
    Future<ProcessResult> Function(String executable, List<String> arguments);

class WindowsProcessTreeProvider implements ProcessTreeProvider {
  final ProcessRunner _runner;

  WindowsProcessTreeProvider({ProcessRunner? runner})
    : _runner = runner ?? Process.run;

  @override
  Future<List<ProcessSnapshot>> getProcessSnapshots({
    required List<int> rootPids,
  }) async {
    if (rootPids.isEmpty) return const [];

    try {
      final result = await _runner('powershell.exe', [
        '-NoProfile',
        '-Command',
        'Get-CimInstance Win32_Process | Select-Object ProcessId, ParentProcessId, ExecutablePath, CommandLine | ConvertTo-Json',
      ]);

      if (result.exitCode != 0) return const [];

      return parsePowerShellJson(result.stdout.toString());
    } catch (_) {
      return const [];
    }
  }

  static List<ProcessSnapshot> parsePowerShellJson(String jsonStr) {
    final snapshots = <ProcessSnapshot>[];
    if (jsonStr.trim().isEmpty) return snapshots;

    try {
      final decoded = jsonDecode(jsonStr);
      final list = decoded is List ? decoded : [decoded];

      for (final item in list) {
        if (item is! Map) continue;
        final pid = item['ProcessId'] as int?;
        final ppid = item['ParentProcessId'] as int?;
        if (pid == null || ppid == null) continue;

        final exec = (item['ExecutablePath'] as String?) ?? '';
        final cmdLine = item['CommandLine'] as String?;

        List<String> argv = [];
        if (cmdLine != null && cmdLine.isNotEmpty) {
          argv = cmdLine.split(RegExp(r'\s+'));
        } else if (exec.isNotEmpty) {
          argv = [exec];
        }

        snapshots.add(
          ProcessSnapshot(
            pid: pid,
            ppid: ppid,
            executable: exec.isNotEmpty
                ? exec
                : (argv.isNotEmpty ? argv.first : ''),
            argv: argv,
            isForeground: true,
          ),
        );
      }
    } on Object catch (e) {
      DiagnosticsLog.instance.warn('process-tree', 'scan failed', error: e);
    }

    return snapshots;
  }
}
