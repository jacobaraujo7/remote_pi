import 'dart:async';

import 'package:cockpit/app/cockpit/domain/contracts/process_tree_provider.dart';
import 'package:cockpit/app/cockpit/domain/entities/process_snapshot.dart';
import 'package:cockpit/app/core/domain/entities/harness.dart';
import 'package:cockpit/app/cockpit/domain/services/terminal_harness_monitor.dart';
import 'package:flutter_test/flutter_test.dart';

class FakeProcessTreeProvider implements ProcessTreeProvider {
  List<ProcessSnapshot> snapshotsToReturn;
  int callCount = 0;
  bool shouldThrow = false;

  FakeProcessTreeProvider({this.snapshotsToReturn = const []});

  @override
  Future<List<ProcessSnapshot>> getProcessSnapshots({
    required List<int> rootPids,
  }) async {
    callCount++;
    if (shouldThrow) {
      throw Exception('Process inspection failed');
    }
    return snapshotsToReturn;
  }
}

void main() {
  group('TerminalHarnessMonitor', () {
    test('starts monitor on first registration and executes immediate poll', () async {
      final fakeProvider = FakeProcessTreeProvider(
        snapshotsToReturn: [
          const ProcessSnapshot(
            pid: 100,
            ppid: 1,
            executable: 'bash',
            argv: ['bash'],
          ),
          const ProcessSnapshot(
            pid: 101,
            ppid: 100,
            executable: '/bin/pi',
            argv: ['pi'],
          ),
        ],
      );

      final monitor = TerminalHarnessMonitor(
        provider: fakeProvider,
        pollInterval: const Duration(milliseconds: 500),
      );

      HarnessKind? notifiedHarness;

      monitor.registerSession(
        sessionId: 'session-1',
        rootPid: () => 100,
        onHarnessChanged: (harness) {
          notifiedHarness = harness;
        },
      );

      expect(monitor.isRunning, isTrue);
      expect(monitor.registeredCount, equals(1));

      // Wait microtask for immediate poll completion
      await pumpEventQueue();

      expect(fakeProvider.callCount, equals(1));
      expect(notifiedHarness, equals(HarnessKind.pi));

      monitor.dispose();
    });

    test('shares single snapshot query across multiple sessions', () async {
      final fakeProvider = FakeProcessTreeProvider(
        snapshotsToReturn: [
          const ProcessSnapshot(
            pid: 100,
            ppid: 1,
            executable: 'bash',
            argv: ['bash'],
          ),
          const ProcessSnapshot(
            pid: 101,
            ppid: 100,
            executable: '/bin/claude',
            argv: ['claude'],
          ),
          const ProcessSnapshot(
            pid: 200,
            ppid: 1,
            executable: 'bash',
            argv: ['bash'],
          ),
          const ProcessSnapshot(
            pid: 201,
            ppid: 200,
            executable: '/bin/codex',
            argv: ['codex'],
          ),
        ],
      );

      final monitor = TerminalHarnessMonitor(
        provider: fakeProvider,
        pollInterval: const Duration(milliseconds: 500),
      );

      HarnessKind? harness1;
      HarnessKind? harness2;

      monitor.registerSession(
        sessionId: 'session-1',
        rootPid: () => 100,
        onHarnessChanged: (h) => harness1 = h,
      );

      monitor.registerSession(
        sessionId: 'session-2',
        rootPid: () => 200,
        onHarnessChanged: (h) => harness2 = h,
      );

      await pumpEventQueue();
      await monitor.poll();

      expect(harness1, equals(HarnessKind.claudeCode));
      expect(harness2, equals(HarnessKind.codex));

      monitor.dispose();
    });

    test('stops polling when all sessions are unregistered', () async {
      final fakeProvider = FakeProcessTreeProvider();
      final monitor = TerminalHarnessMonitor(
        provider: fakeProvider,
        pollInterval: const Duration(milliseconds: 100),
      );

      monitor.registerSession(
        sessionId: 'session-1',
        rootPid: () => 100,
        onHarnessChanged: (_) {},
      );

      expect(monitor.isRunning, isTrue);

      monitor.unregisterSession('session-1');

      expect(monitor.isRunning, isFalse);
      expect(monitor.registeredCount, equals(0));

      monitor.dispose();
    });

    test('handles inspection error gracefully without throwing', () async {
      final fakeProvider = FakeProcessTreeProvider()..shouldThrow = true;
      final monitor = TerminalHarnessMonitor(
        provider: fakeProvider,
        pollInterval: const Duration(milliseconds: 100),
      );

      HarnessKind? harness;

      monitor.registerSession(
        sessionId: 'session-1',
        rootPid: () => 100,
        onHarnessChanged: (h) => harness = h,
      );

      await pumpEventQueue();

      expect(harness, isNull);

      monitor.dispose();
    });

    test('requestPoll coalesces while a poll is in flight', () async {
      final gate = Completer<void>();
      final fakeProvider = _GatedProcessTreeProvider(gate);
      final monitor = TerminalHarnessMonitor(
        provider: fakeProvider,
        pollInterval: const Duration(days: 1),
      );

      monitor.registerSession(
        sessionId: 'session-1',
        rootPid: () => 100,
        onHarnessChanged: (_) {},
      );

      await pumpEventQueue();
      expect(fakeProvider.callCount, equals(1));

      monitor.requestPoll();
      monitor.requestPoll();
      expect(fakeProvider.callCount, equals(1));

      gate.complete();
      await pumpEventQueue();
      expect(fakeProvider.callCount, greaterThanOrEqualTo(2));

      monitor.dispose();
    });
  });
}

class _GatedProcessTreeProvider implements ProcessTreeProvider {
  _GatedProcessTreeProvider(this.gate);

  final Completer<void> gate;
  int callCount = 0;

  @override
  Future<List<ProcessSnapshot>> getProcessSnapshots({
    required List<int> rootPids,
  }) async {
    callCount++;
    await gate.future;
    return const [
      ProcessSnapshot(
        pid: 100,
        ppid: 1,
        executable: 'bash',
        argv: ['bash'],
      ),
    ];
  }
}
