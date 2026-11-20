import 'package:cockpit/app/cockpit/domain/contracts/process_tree_provider.dart';
import 'package:cockpit/app/cockpit/domain/entities/agent_fork.dart';
import 'package:cockpit/app/cockpit/domain/entities/process_snapshot.dart';
import 'package:cockpit/app/cockpit/domain/services/terminal_harness_monitor.dart';
import 'package:cockpit/app/cockpit/ui/session/terminal_session.dart';
import 'package:cockpit/app/core/domain/entities/harness.dart';
import 'package:cockpit/app/core/domain/entities/terminal_profile.dart';
import 'package:flutter_test/flutter_test.dart';
import '../support/attachment_terminal_gateway.dart';

class _Processes implements ProcessTreeProvider {
  int? agentPid;
  String executable = 'claude';
  List<String> args = [];
  int? serverPid;
  @override
  Future<List<ProcessSnapshot>> getProcessSnapshots({
    required List<int> rootPids,
  }) async => [
    const ProcessSnapshot(
      pid: 100,
      ppid: 1,
      executable: 'bash',
      argv: ['bash'],
    ),
    if (agentPid != null)
      ProcessSnapshot(
        pid: agentPid!,
        ppid: 100,
        executable: executable,
        argv: [executable, ...args],
      ),
    if (serverPid != null && agentPid != null)
      ProcessSnapshot(
        pid: serverPid!,
        ppid: agentPid!,
        executable: 'codex',
        argv: const ['codex', 'app-server', '--listen', 'stdio://'],
      ),
  ];
}

class _Gateway extends AttachmentTerminalGateway {
  @override
  int? get rootProcessId => 100;
}

AgentConversationIdentity identity(
  String id,
  int pid, [
  HarnessKind kind = HarnessKind.claudeCode,
]) => AgentConversationIdentity(
  harness: kind,
  sessionId: id,
  processIds: [pid, 100],
);

void main() {
  test(
    'shared Codex reports an actionable state; private Codex binds through its app-server child',
    () async {
      final processes = _Processes()
        ..executable = 'codex'
        ..agentPid = 101;
      final monitor = TerminalHarnessMonitor(provider: processes);
      final session = TerminalSession(
        id: 'codex-tab',
        projectId: 'p',
        workingDirectory: '/tmp',
        gateway: _Gateway(),
        profile: const TerminalProfile(
          id: 'bash',
          label: 'bash',
          executable: '/bin/bash',
        ),
        monitor: monitor,
      );
      addTearDown(() async {
        await session.dispose();
        monitor.dispose();
      });
      await monitor.refreshSession('codex-tab');
      session.observeConversationIdentity(
        identity('wrong-shared-thread', 900, HarnessKind.codex),
        event: 'SessionStart',
      );
      expect(session.conversationIdentity, isNull);
      expect(session.codexNeedsPrivateServer, isTrue);

      processes
        ..agentPid = 102
        ..args = ['--no-daemon']
        ..serverPid = 103;
      await monitor.refreshSession('codex-tab');
      expect(session.agentProcessId, 102);
      expect(session.codexNeedsPrivateServer, isFalse);
      session.observeConversationIdentity(
        const AgentConversationIdentity(
          harness: HarnessKind.codex,
          sessionId: 'correct-thread',
          processIds: [104, 103, 102],
        ),
        event: 'SessionStart',
      );
      expect(session.conversationIdentity?.sessionId, 'correct-thread');
      session.observeConversationIdentity(
        identity('wrong-shared-thread', 900, HarnessKind.codex),
        event: 'SessionStart',
      );
      expect(session.conversationIdentity?.sessionId, 'correct-thread');
    },
  );

  test(
    'startup before process poll binds identity; old hooks cannot bind a replacement agent',
    () async {
      final processes = _Processes();
      final monitor = TerminalHarnessMonitor(provider: processes);
      final gateway = _Gateway();
      final session = TerminalSession(
        id: 't1',
        projectId: 'p',
        workingDirectory: '/tmp',
        gateway: gateway,
        profile: const TerminalProfile(
          id: 'bash',
          label: 'bash',
          executable: '/bin/bash',
        ),
        monitor: monitor,
      );
      addTearDown(() async {
        await session.dispose();
        monitor.dispose();
      });
      // Persisted resume hints are never sufficient to fork a conversation.
      session.claudeSessionId = 'persisted';
      expect(session.conversationIdentity, isNull);
      session.observeConversationIdentity(
        identity('parent', 101),
        event: 'SessionStart',
      );
      processes.agentPid = 101;
      await monitor.refreshSession('t1');
      expect(session.activeHarness, HarnessKind.claudeCode);
      expect(session.conversationIdentity?.sessionId, 'parent');
      expect(gateway.text, isEmpty);

      processes.agentPid = 102;
      await monitor.refreshSession('t1');
      expect(session.conversationIdentity, isNull);
      session.observeConversationIdentity(
        identity('parent', 101),
        event: 'Stop',
      );
      expect(session.conversationIdentity, isNull);
      session.observeConversationIdentity(
        identity('child', 102),
        event: 'SessionStart',
      );
      expect(session.conversationIdentity?.sessionId, 'child');
      // An end event belonging to the previous process must not clear the child.
      session.observeConversationIdentity(
        identity('parent', 101),
        event: 'SessionEnd',
      );
      expect(session.conversationIdentity?.sessionId, 'child');

      session.observeConversationIdentity(
        identity('child', 102),
        event: 'SessionEnd',
      );
      session.observeConversationIdentity(
        identity('child', 102),
        event: 'Stop',
      );
      expect(session.conversationIdentity, isNull);
      // Resuming the same conversation in a new process is legitimate.
      processes.agentPid = 103;
      await monitor.refreshSession('t1');
      session.observeConversationIdentity(
        identity('child', 103),
        event: 'SessionStart',
      );
      expect(session.conversationIdentity?.sessionId, 'child');
      processes.agentPid = null;
      await monitor.refreshSession('t1');
      expect(session.activeHarness, isNull);
      expect(session.conversationIdentity, isNull);
    },
  );
}
