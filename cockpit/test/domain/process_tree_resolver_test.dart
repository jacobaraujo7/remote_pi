import 'package:cockpit/app/cockpit/domain/entities/process_snapshot.dart';
import 'package:cockpit/app/core/domain/entities/harness.dart';
import 'package:cockpit/app/cockpit/domain/services/process_tree_resolver.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('ProcessTreeResolver', () {
    test('pure shell returns null', () {
      final snapshots = [
        const ProcessSnapshot(
          pid: 100,
          ppid: 1,
          executable: '/bin/bash',
          argv: ['bash'],
        ),
      ];

      final result = ProcessTreeResolver.resolve(
        rootPid: 100,
        snapshots: snapshots,
      );

      expect(result, isNull);
    });

    test('unrecognized child tool under shell returns null', () {
      final snapshots = [
        const ProcessSnapshot(
          pid: 100,
          ppid: 1,
          executable: '/bin/bash',
          argv: ['bash'],
        ),
        const ProcessSnapshot(
          pid: 101,
          ppid: 100,
          executable: '/usr/bin/git',
          argv: ['git', 'status'],
        ),
      ];

      final result = ProcessTreeResolver.resolve(
        rootPid: 100,
        snapshots: snapshots,
      );

      expect(result, isNull);
    });

    test('descendant tool under interactive harness preserves ancestral harness', () {
      final snapshots = [
        const ProcessSnapshot(
          pid: 100,
          ppid: 1,
          executable: '/bin/bash',
          argv: ['bash'],
        ),
        const ProcessSnapshot(
          pid: 101,
          ppid: 100,
          executable: '/usr/local/bin/pi',
          argv: ['pi'],
        ),
        const ProcessSnapshot(
          pid: 102,
          ppid: 101,
          executable: '/usr/bin/flutter',
          argv: ['flutter', 'test'],
        ),
      ];

      final result = ProcessTreeResolver.resolve(
        rootPid: 100,
        snapshots: snapshots,
      );

      expect(result, equals(HarnessKind.pi));
    });

    test('nested interactive harnesses selects innermost active harness', () {
      final snapshots = [
        const ProcessSnapshot(
          pid: 100,
          ppid: 1,
          executable: '/bin/bash',
          argv: ['bash'],
        ),
        const ProcessSnapshot(
          pid: 101,
          ppid: 100,
          executable: '/usr/bin/claude',
          argv: ['claude'],
        ),
        const ProcessSnapshot(
          pid: 102,
          ppid: 101,
          executable: '/usr/local/bin/pi',
          argv: ['pi'],
        ),
      ];

      final result = ProcessTreeResolver.resolve(
        rootPid: 100,
        snapshots: snapshots,
      );

      expect(result, equals(HarnessKind.pi));
    });

    test('when nested harness exits, restores enclosing harness', () {
      // Simulating pi exited, only claude remains
      final snapshots = [
        const ProcessSnapshot(
          pid: 100,
          ppid: 1,
          executable: '/bin/bash',
          argv: ['bash'],
        ),
        const ProcessSnapshot(
          pid: 101,
          ppid: 100,
          executable: '/usr/bin/claude',
          argv: ['claude'],
        ),
      ];

      final result = ProcessTreeResolver.resolve(
        rootPid: 100,
        snapshots: snapshots,
      );

      expect(result, equals(HarnessKind.claudeCode));
    });

    test('suspended or background process is ignored', () {
      final snapshots = [
        const ProcessSnapshot(
          pid: 100,
          ppid: 1,
          executable: '/bin/bash',
          argv: ['bash'],
        ),
        const ProcessSnapshot(
          pid: 101,
          ppid: 100,
          executable: '/usr/local/bin/pi',
          argv: ['pi'],
          state: 'T', // Stopped
        ),
      ];

      final result = ProcessTreeResolver.resolve(
        rootPid: 100,
        snapshots: snapshots,
      );

      expect(result, isNull);
    });

    test('process not in foreground is ignored', () {
      final snapshots = [
        const ProcessSnapshot(
          pid: 100,
          ppid: 1,
          executable: '/bin/bash',
          argv: ['bash'],
        ),
        const ProcessSnapshot(
          pid: 101,
          ppid: 100,
          executable: '/usr/local/bin/pi',
          argv: ['pi'],
          isForeground: false,
        ),
      ];

      final result = ProcessTreeResolver.resolve(
        rootPid: 100,
        snapshots: snapshots,
      );

      expect(result, isNull);
    });

    test('missing root PID or empty snapshots returns null', () {
      expect(
        ProcessTreeResolver.resolve(rootPid: 999, snapshots: []),
        isNull,
      );
      expect(
        ProcessTreeResolver.resolve(
          rootPid: 999,
          snapshots: [
            const ProcessSnapshot(
              pid: 100,
              ppid: 1,
              executable: 'bash',
              argv: ['bash'],
            ),
          ],
        ),
        isNull,
      );
    });
  });
}
