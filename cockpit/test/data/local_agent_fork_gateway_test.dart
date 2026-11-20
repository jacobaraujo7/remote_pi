import 'package:cockpit/app/cockpit/data/terminal/local_agent_fork_gateway.dart';
import 'package:cockpit/app/cockpit/domain/entities/agent_fork.dart';
import 'package:cockpit/app/core/domain/entities/harness.dart';
import 'package:cockpit/app/core/domain/entities/terminal_profile.dart';
import 'package:cockpit/app/core/domain/result.dart';
import 'package:flutter_test/flutter_test.dart';

const profile = TerminalProfile(
  id: 'login-shell',
  label: 'bash',
  executable: '/bin/bash',
);
const id = '019ff255-62c9-7ba1-8481-63c8803ef51e';
AgentConversationIdentity identity(HarnessKind kind, [String sessionId = id]) =>
    AgentConversationIdentity(
      harness: kind,
      sessionId: sessionId,
      processIds: const [42],
      transcriptPath: kind == HarnessKind.pi
          ? '/sessions/pi conversation.jsonl'
          : null,
    );

void main() {
  test(
    'Pi requires a saved transcript and preserves custom session paths',
    () async {
      final gateway = LocalAgentForkGateway.forTesting(
        probe: (_, _) async => '--fork',
        exists: (path) async => path == "/custom storage/pi's chat.jsonl",
      );
      for (final path in [
        null,
        '/missing/session.jsonl',
        '/sessions/bad\npath',
      ]) {
        final result = await gateway.prepare(
          identity: AgentConversationIdentity(
            harness: HarnessKind.pi,
            sessionId: id,
            processIds: const [42],
            transcriptPath: path,
          ),
          profile: profile,
        );
        expect((result as Failure).error.problem, AgentForkProblem.notSaved);
      }
      final result = await gateway.prepare(
        identity: AgentConversationIdentity(
          harness: HarnessKind.pi,
          sessionId: id,
          processIds: const [42],
          transcriptPath: "/custom storage/pi's chat.jsonl",
        ),
        profile: profile,
      );
      expect(
        (result as Success).value.command,
        contains("'/custom storage/pi'\\''s chat.jsonl'"),
      );
    },
  );

  for (final (kind, help, suffix) in [
    (
      HarnessKind.claudeCode,
      '--resume --fork-session',
      "'--resume' '$id' '--fork-session'",
    ),
    (
      HarnessKind.codex,
      'Usage: codex fork [SESSION_ID] --no-daemon',
      "'fork' '$id' '--no-daemon'",
    ),
    (
      HarnessKind.pi,
      '--session --fork',
      "'--fork' '/sessions/pi conversation.jsonl'",
    ),
  ]) {
    test(
      '${kind.name}: checks support and builds an independent fork',
      () async {
        final probes = <List<String>>[];
        final gateway = LocalAgentForkGateway.forTesting(
          probe: (exe, args) async {
            probes.add(args);
            return help;
          },
        );
        final result = await gateway.prepare(
          identity: identity(kind),
          profile: profile,
        );
        expect(result, isA<Success<AgentForkLaunch, AgentForkFailure>>());
        expect(
          (result as Success<AgentForkLaunch, AgentForkFailure>).value.command,
          endsWith(suffix),
        );
        expect(
          probes.single,
          kind == HarnessKind.codex ? ['fork', '--help'] : ['--help'],
        );
      },
    );
  }

  test('does not claim API/interactive-only agents are integrated', () async {
    final gateway = LocalAgentForkGateway.forTesting(
      probe: (_, _) async => fail('must not probe'),
    );
    for (final kind in [
      HarnessKind.openCode,
      HarnessKind.gitHubCopilot,
      HarnessKind.cursor,
      HarnessKind.antigravity,
    ]) {
      expect(gateway.supports(kind), isFalse);
      final result = await gateway.prepare(
        identity: identity(kind),
        profile: profile,
      );
      expect((result as Failure).error.problem, AgentForkProblem.unavailable);
    }
  });

  test('old or missing CLI cannot enable fork', () async {
    for (final help in [null, 'Usage: pi --session ID']) {
      final gateway = LocalAgentForkGateway.forTesting(
        probe: (_, _) async => help,
      );
      final result = await gateway.prepare(
        identity: identity(HarnessKind.pi),
        profile: profile,
      );
      expect((result as Failure).error.problem, AgentForkProblem.incompatible);
    }
  });

  test(
    'never substitutes latest or executes shell text in a session ID',
    () async {
      final gateway = LocalAgentForkGateway.forTesting(
        probe: (_, _) async => fail('must not probe'),
      );
      for (final value in [
        '',
        'latest',
        'id;touch /tmp/injected',
        r'$(whoami)',
        "id'",
        'a\nb',
      ]) {
        final result = await gateway.prepare(
          identity: identity(HarnessKind.pi, value),
          profile: profile,
        );
        expect((result as Failure).error.problem, AgentForkProblem.identifying);
      }
    },
  );

  test(
    'does not probe a local CLI on behalf of WSL or an unknown shell',
    () async {
      final gateway = LocalAgentForkGateway.forTesting(
        probe: (_, _) async => fail('must not probe'),
      );
      for (final unsupported in [
        const TerminalProfile(
          id: 'wsl:Ubuntu',
          label: 'WSL',
          executable: 'wsl.exe',
        ),
        const TerminalProfile(
          id: 'custom',
          label: 'wrapper',
          executable: '/bin/wrapper',
        ),
        TerminalProfile.hostLoginShell,
      ]) {
        final result = await gateway.prepare(
          identity: identity(HarnessKind.pi),
          profile: unsupported,
        );
        expect(
          (result as Failure).error.problem,
          AgentForkProblem.unsupportedHost,
        );
      }
    },
  );
}
