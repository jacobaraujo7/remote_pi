import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:cockpit/app/cockpit/domain/contracts/process_tree_provider.dart';
import 'package:cockpit/app/cockpit/data/process/windows_native_process_snapshot.dart';
import 'package:cockpit/app/core/data/diagnostics/diagnostics_log.dart';
import 'package:cockpit/app/cockpit/domain/entities/process_snapshot.dart';
import 'package:cockpit/app/core/domain/entities/harness.dart';

typedef ProcessRunner =
    Future<ProcessResult> Function(String executable, List<String> arguments);
typedef ProcessSnapshotter = List<ProcessSnapshot> Function();

class WindowsProcessTreeProvider implements ProcessTreeProvider {
  final ProcessRunner _runner;
  final ProcessSnapshotter? snapshotter;
  final DateTime Function() _clock;
  final Map<int, ({ProcessSnapshot? snapshot, DateTime expiresAt})> _details =
      {};
  DateTime? _lastDetailQueryAt;

  // Restoring several agent tabs launches their children in a short burst.
  // Batch newly seen PIDs instead of starting one costly CIM query per tab.
  static const _detailQueryCooldown = Duration(seconds: 3);

  static final Set<String> _candidateNames = {
    for (final spec in HarnessCatalog.specs.values)
      ...spec.allEntryPoints.map((name) => name.toLowerCase()),
    'node',
    'bun',
    'deno',
    'python',
    'python3',
    'npx',
    'uvx',
  };

  WindowsProcessTreeProvider({
    ProcessRunner? runner,
    this.snapshotter,
    DateTime Function()? clock,
  }) : _runner = runner ?? Process.run,
       _clock = clock ?? DateTime.now;

  @override
  Future<List<ProcessSnapshot>> getProcessSnapshots({
    required List<int> rootPids,
  }) async {
    if (rootPids.isEmpty) return const [];

    try {
      // Toolhelp is quick but synchronous. Enumerate off the UI isolate so a
      // busy Windows process table cannot consume a Flutter frame.
      final native = snapshotter != null
          ? snapshotter!()
          : await Isolate.run(windowsNativeProcessSnapshot);
      if (native.isEmpty) return const [];
      final rooted = _rootedSnapshots(native, rootPids);
      if (rooted.isEmpty) return const [];

      final candidates = rooted.where((snapshot) {
        final name = snapshot.executable.toLowerCase().replaceFirst(
          RegExp(r'\.(exe|cmd|bat)$'),
          '',
        );
        return _candidateNames.contains(name);
      }).toList();
      final liveIds = candidates.map((candidate) => candidate.pid).toSet();
      _details.removeWhere((pid, _) => !liveIds.contains(pid));

      final now = _clock();
      final unknown = candidates.where((candidate) {
        final cached = _details[candidate.pid];
        return cached == null || !cached.expiresAt.isAfter(now);
      }).toList();
      if (unknown.isNotEmpty &&
          (_lastDetailQueryAt == null ||
              now.difference(_lastDetailQueryAt!) >= _detailQueryCooldown)) {
        await _loadDetails(unknown);
        _lastDetailQueryAt = _clock();
      }

      return [
        for (final snapshot in rooted)
          if (_details[snapshot.pid]?.snapshot case final detail?)
            ProcessSnapshot(
              pid: snapshot.pid,
              ppid: snapshot.ppid,
              executable: detail.executable,
              argv: detail.argv,
            )
          else if (liveIds.contains(snapshot.pid))
            ProcessSnapshot(
              pid: snapshot.pid,
              ppid: snapshot.ppid,
              executable: '',
              argv: const [],
            )
          else
            snapshot,
      ];
    } on Object catch (e) {
      DiagnosticsLog.instance.warn(
        'process-tree',
        'native scan failed',
        error: e,
      );
      return const [];
    }
  }

  Future<void> _loadDetails(List<ProcessSnapshot> candidates) async {
    final filter = candidates
        .map((candidate) => 'ProcessId=${candidate.pid}')
        .join(' OR ');
    final found = <int, ProcessSnapshot>{};
    try {
      final result = await _runner('powershell.exe', [
        '-NoProfile',
        '-Command',
        'Get-CimInstance Win32_Process -Filter "$filter" | '
            'Select-Object ProcessId, ParentProcessId, ExecutablePath, CommandLine | '
            'ConvertTo-Json -Compress',
      ]);
      if (result.exitCode == 0) {
        for (final detail in parsePowerShellJson(result.stdout.toString())) {
          found[detail.pid] = detail;
        }
      }
    } on Object catch (e) {
      DiagnosticsLog.instance.warn(
        'process-tree',
        'detail scan failed',
        error: e,
      );
    }
    final now = _clock();
    for (final candidate in candidates) {
      final detail = found[candidate.pid];
      _details[candidate.pid] = (
        snapshot: detail,
        expiresAt: now.add(
          detail == null
              ? const Duration(seconds: 30)
              : const Duration(minutes: 5),
        ),
      );
    }
  }

  static List<ProcessSnapshot> _rootedSnapshots(
    List<ProcessSnapshot> snapshots,
    List<int> rootPids,
  ) {
    final byPid = {for (final snapshot in snapshots) snapshot.pid: snapshot};
    final children = <int, List<int>>{};
    for (final snapshot in snapshots) {
      children.putIfAbsent(snapshot.ppid, () => []).add(snapshot.pid);
    }
    final found = <ProcessSnapshot>[];
    final seen = <int>{};
    final pending = [...rootPids];
    while (pending.isNotEmpty) {
      final current = pending.removeLast();
      if (!seen.add(current)) continue;
      final snapshot = byPid[current];
      if (snapshot == null) continue;
      found.add(snapshot);
      pending.addAll(children[current] ?? const []);
    }
    return found;
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
