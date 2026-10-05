import 'dart:io';
import 'package:cockpit/app/cockpit/data/process/linux_process_tree_provider.dart';
import 'package:cockpit/app/cockpit/data/process/macos_process_tree_provider.dart';
import 'package:cockpit/app/cockpit/data/process/windows_process_tree_provider.dart';
import 'package:cockpit/app/cockpit/data/process/windows_native_process_snapshot.dart';
import 'package:cockpit/app/cockpit/data/process/wsl_process_tree_provider.dart';
import 'package:cockpit/app/cockpit/domain/entities/process_snapshot.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('ProcessTreeProvider platform adapters', () {
    test('MacosProcessTreeProvider parses ps output correctly', () {
      const psOutput = '''
  PID  PPID STAT TPGID  PGID COMMAND
  100     1 S+    100   100 bash
  101   100 S+    101   101 /usr/local/bin/pi -c
  102   101 S     101   102 flutter test
''';

      final snapshots = MacosProcessTreeProvider.parsePsOutput(psOutput);

      expect(snapshots.length, equals(3));
      expect(snapshots[0].pid, equals(100));
      expect(snapshots[0].isForeground, isTrue);
      expect(snapshots[1].executable, equals('/usr/local/bin/pi'));
      expect(snapshots[1].argv, equals(['/usr/local/bin/pi', '-c']));
    });

    test(
      'WindowsProcessTreeProvider parses PowerShell JSON output correctly',
      () {
        const jsonStr = '''
[
  {
    "ProcessId": 1000,
    "ParentProcessId": 100,
    "ExecutablePath": "C:\\\\Program Files\\\\powershell.exe",
    "CommandLine": "powershell.exe -NoProfile"
  },
  {
    "ProcessId": 1001,
    "ParentProcessId": 1000,
    "ExecutablePath": "C:\\\\bin\\\\claude.exe",
    "CommandLine": "claude.exe -c"
  }
]
''';

        final snapshots = WindowsProcessTreeProvider.parsePowerShellJson(
          jsonStr,
        );

        expect(snapshots.length, equals(2));
        expect(snapshots[0].pid, equals(1000));
        expect(snapshots[1].pid, equals(1001));
        expect(snapshots[1].executable, equals('C:\\bin\\claude.exe'));
      },
    );

    test('Windows native snapshot contains the current process', () {
      if (!Platform.isWindows) return;
      final snapshots = windowsNativeProcessSnapshot();
      final current = snapshots.where((snapshot) => snapshot.pid == pid);
      expect(current, hasLength(1));
      expect(current.single.executable, isNotEmpty);
    });

    test('Windows provider enumerates off the UI isolate', () async {
      if (!Platform.isWindows) return;
      final snapshots = await WindowsProcessTreeProvider().getProcessSnapshots(
        rootPids: [pid],
      );
      expect(snapshots.map((snapshot) => snapshot.pid), contains(pid));
    });

    test(
      'Windows provider keeps only rooted processes without invoking CIM for shells',
      () async {
        var calls = 0;
        final provider = WindowsProcessTreeProvider(
          snapshotter: () => const [
            ProcessSnapshot(
              pid: 100,
              ppid: 1,
              executable: 'pwsh.exe',
              argv: ['pwsh.exe'],
            ),
            ProcessSnapshot(
              pid: 101,
              ppid: 100,
              executable: 'git.exe',
              argv: ['git.exe'],
            ),
            ProcessSnapshot(
              pid: 999,
              ppid: 1,
              executable: 'codex.exe',
              argv: ['codex.exe'],
            ),
          ],
          runner: (executable, arguments) async {
            calls++;
            return ProcessResult(0, 0, '[]', '');
          },
        );
        final snapshots = await provider.getProcessSnapshots(rootPids: [100]);
        expect(
          snapshots.map((snapshot) => snapshot.pid),
          containsAll([100, 101]),
        );
        expect(snapshots, hasLength(2));
        expect(calls, 0);
      },
    );

    test(
      'Windows provider fetches a new harness command line only once',
      () async {
        var calls = 0;
        final provider = WindowsProcessTreeProvider(
          snapshotter: () => const [
            ProcessSnapshot(
              pid: 100,
              ppid: 1,
              executable: 'pwsh.exe',
              argv: ['pwsh.exe'],
            ),
            ProcessSnapshot(
              pid: 101,
              ppid: 100,
              executable: 'codex.exe',
              argv: ['codex.exe'],
            ),
          ],
          runner: (executable, arguments) async {
            calls++;
            expect(executable, 'powershell.exe');
            expect(arguments.last, contains('ProcessId=101'));
            return ProcessResult(0, 0, '''
{"ProcessId":101,"ParentProcessId":100,"ExecutablePath":"codex.exe","CommandLine":"codex.exe"}
''', '');
          },
        );
        final first = await provider.getProcessSnapshots(rootPids: [100]);
        final second = await provider.getProcessSnapshots(rootPids: [100]);
        expect(first.last.executable, 'codex.exe');
        expect(second.last.executable, 'codex.exe');
        expect(calls, 1);
      },
    );

    test(
      'Windows provider batches harnesses that appear during restore',
      () async {
        var now = DateTime.utc(2026);
        var includeSecond = false;
        final filters = <String>[];
        final provider = WindowsProcessTreeProvider(
          clock: () => now,
          snapshotter: () => [
            const ProcessSnapshot(
              pid: 100,
              ppid: 1,
              executable: 'pwsh.exe',
              argv: ['pwsh.exe'],
            ),
            const ProcessSnapshot(
              pid: 101,
              ppid: 100,
              executable: 'claude.exe',
              argv: ['claude.exe'],
            ),
            if (includeSecond)
              const ProcessSnapshot(
                pid: 102,
                ppid: 100,
                executable: 'claude.exe',
                argv: ['claude.exe'],
              ),
          ],
          runner: (executable, arguments) async {
            filters.add(arguments.last);
            return ProcessResult(0, 0, '''
[
  {"ProcessId":101,"ParentProcessId":100,"ExecutablePath":"claude.exe","CommandLine":"claude.exe"},
  {"ProcessId":102,"ParentProcessId":100,"ExecutablePath":"claude.exe","CommandLine":"claude.exe"}
]
''', '');
          },
        );

        await provider.getProcessSnapshots(rootPids: [100]);
        includeSecond = true;
        await provider.getProcessSnapshots(rootPids: [100]);
        expect(filters, hasLength(1));
        now = now.add(const Duration(seconds: 3));
        await provider.getProcessSnapshots(rootPids: [100]);
        expect(filters, hasLength(2));
        expect(filters.last, contains('ProcessId=102'));
      },
    );

    test('WslProcessTreeProvider parses WSL ps output grouped by distro', () {
      const psOutput = '''
  PID  PPID STAT TPGID  PGID COMMAND
  200     1 S+    200   200 zsh
  201   200 S+    201   201 opencode
''';

      final snapshots = WslProcessTreeProvider.parsePsOutput(psOutput);

      expect(snapshots.length, equals(2));
      expect(snapshots[1].pid, equals(201));
      expect(snapshots[1].executable, equals('opencode'));
    });

    test(
      'LinuxProcessTreeProvider tolerates empty or missing proc directory',
      () async {
        final provider = LinuxProcessTreeProvider(
          procDir: Directory('/non_existent_proc_path_for_testing'),
        );

        final snapshots = await provider.getProcessSnapshots(rootPids: [100]);
        expect(snapshots, isEmpty);
      },
    );

    test(
      'LinuxProcessTreeProvider walks only the rooted tree via children',
      () async {
        final tmp = await Directory.systemTemp.createTemp('proc_tree_');
        addTearDown(() => tmp.delete(recursive: true));

        Future<void> writeProc({
          required int pid,
          required int ppid,
          required String comm,
          required List<int> children,
          String state = 'S',
          int pgrp = 0,
          int tpgid = 0,
        }) async {
          final dir = Directory('${tmp.path}/$pid');
          final task = Directory('${dir.path}/task/$pid');
          await task.create(recursive: true);
          final effectivePgrp = pgrp == 0 ? pid : pgrp;
          final effectiveTpgid = tpgid == 0 ? pid : tpgid;
          // pid (comm) state ppid pgrp session tty_nr tpgid ...
          await File('${dir.path}/stat').writeAsString(
            '$pid ($comm) $state $ppid $effectivePgrp $pid 0 $effectiveTpgid 0',
          );
          await File(
            '${dir.path}/cmdline',
          ).writeAsBytes([...comm.codeUnits, 0]);
          await File(
            '${task.path}/children',
          ).writeAsString(children.isEmpty ? '' : '${children.join(' ')}\n');
        }

        await writeProc(pid: 10, ppid: 1, comm: 'fish', children: [11]);
        await writeProc(pid: 11, ppid: 10, comm: 'claude', children: const []);
        // Sibling tree that must NOT be included when rooted at 10.
        await writeProc(pid: 20, ppid: 1, comm: 'other', children: [21]);
        await writeProc(pid: 21, ppid: 20, comm: 'codex', children: const []);

        final provider = LinuxProcessTreeProvider(procDir: tmp);
        final snapshots = await provider.getProcessSnapshots(rootPids: [10]);

        expect(snapshots.map((s) => s.pid).toSet(), equals({10, 11}));
        expect(
          snapshots.firstWhere((s) => s.pid == 11).executable,
          equals('claude'),
        );
      },
    );
  });
}
