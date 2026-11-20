import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:cockpit/app/cockpit/domain/contracts/agent_fork_gateway.dart';
import 'package:cockpit/app/cockpit/domain/entities/agent_fork.dart';
import 'package:cockpit/app/core/domain/entities/harness.dart';
import 'package:cockpit/app/core/domain/entities/terminal_profile.dart';
import 'package:cockpit/app/core/domain/result.dart';
import 'package:cockpit/app/core/utils/executable_resolver.dart';

typedef ForkHelpProbe =
    Future<String?> Function(String executable, List<String> args);

/// Only native external fork operations are enabled. Cursor/Agy's interactive
/// /fork cannot safely be automated by resuming an already-running source.
/// OpenCode/Copilot require an exact server-to-terminal binding before their
/// APIs can be used; process detection is deliberately not such a binding.
class LocalAgentForkGateway implements AgentForkGateway {
  LocalAgentForkGateway()
    : _probe = _help,
      _resolve = resolveExecutable,
      _exists = ((path) => File(path).exists());

  LocalAgentForkGateway.forTesting({
    required this._probe,
    Future<bool> Function(String)? exists,
  }) : _resolve = _testExecutable,
       _exists = exists ?? _testExists;

  static Future<String> _testExecutable(String name) async => '/agents/$name';
  static Future<bool> _testExists(String path) async => true;
  final ForkHelpProbe _probe;
  final Future<String> Function(String) _resolve;
  final Future<bool> Function(String) _exists;

  @override
  bool supports(HarnessKind harness) => switch (harness) {
    HarnessKind.claudeCode || HarnessKind.codex || HarnessKind.pi => true,
    HarnessKind.openCode ||
    HarnessKind.gitHubCopilot ||
    HarnessKind.cursor ||
    HarnessKind.antigravity => false,
  };

  @override
  Future<Result<AgentForkLaunch, AgentForkFailure>> prepare({
    required AgentConversationIdentity identity,
    required TerminalProfile profile,
  }) async {
    if (!supports(identity.harness)) {
      return const Failure(AgentForkFailure(AgentForkProblem.unavailable));
    }
    // WSL/custom shells may resolve a different installation. Do not probe a
    // local CLI and then claim that a different host or shell supports it.
    final shell = profile.executable.replaceAll('\\', '/').split('/').last;
    final powershell =
        shell == 'pwsh' || shell == 'pwsh.exe' || shell == 'powershell.exe';
    if (profile.wslDistro != null ||
        !(powershell || const {'sh', 'bash', 'zsh', 'fish'}.contains(shell))) {
      return const Failure(AgentForkFailure(AgentForkProblem.unsupportedHost));
    }
    final id = identity.sessionId;
    // Native session IDs are opaque identifiers, never shell fragments.
    if (!RegExp(r'^[a-zA-Z0-9][a-zA-Z0-9._-]{0,199}$').hasMatch(id) ||
        id == 'latest') {
      return const Failure(AgentForkFailure(AgentForkProblem.identifying));
    }
    var target = id;
    if (identity.harness == HarnessKind.pi) {
      final path = identity.transcriptPath;
      if (path == null ||
          !path.startsWith('/') ||
          RegExp(r'[\x00\r\n]').hasMatch(path) ||
          !await _exists(path)) {
        return const Failure(AgentForkFailure(AgentForkProblem.notSaved));
      }
      // An exact path also works for sessions stored in a custom directory.
      target = path;
    }
    final executable = await _resolve(switch (identity.harness) {
      HarnessKind.claudeCode => 'claude',
      HarnessKind.codex => 'codex',
      _ => 'pi',
    });
    final args = identity.harness == HarnessKind.codex
        ? const ['fork', '--help']
        : const ['--help'];
    final help = await _probe(executable, args);
    final compatible =
        help != null &&
        switch (identity.harness) {
          HarnessKind.claudeCode => help.contains('--fork-session'),
          HarnessKind.codex =>
            help.contains('SESSION_ID') &&
                help.contains('fork') &&
                help.contains('--no-daemon'),
          HarnessKind.pi => help.contains('--fork'),
          _ => false,
        };
    if (!compatible) {
      return const Failure(AgentForkFailure(AgentForkProblem.incompatible));
    }
    final words = <String>[
      executable,
      ...switch (identity.harness) {
        HarnessKind.claudeCode => ['--resume', id, '--fork-session'],
        HarnessKind.codex => ['fork', id, '--no-daemon'],
        _ => ['--fork', target],
      },
    ];
    // Single quotes suppress expansion in POSIX/fish and PowerShell. A
    // PowerShell command whose executable is quoted needs the call operator.
    String quote(String s) => powershell
        ? "'${s.replaceAll("'", "''")}'"
        : "'${s.replaceAll("'", "'\\''")}'";
    return Success(
      AgentForkLaunch('${powershell ? '& ' : ''}${words.map(quote).join(' ')}'),
    );
  }

  static Future<String?> _help(String executable, List<String> args) async {
    Process? process;
    try {
      process = await Process.start(
        executable,
        args,
        runInShell: Platform.isWindows && executable.endsWith('.cmd'),
      );
      final output = await Future.wait<Object>([
        process.exitCode,
        process.stdout
            .transform(const Utf8Decoder(allowMalformed: true))
            .join(),
        process.stderr
            .transform(const Utf8Decoder(allowMalformed: true))
            .join(),
      ]).timeout(const Duration(seconds: 8));
      return output[0] == 0 ? output[1] as String : null;
    } on ProcessException {
      return null;
    } on TimeoutException {
      process?.kill();
      return null;
    } on FileSystemException {
      return null;
    }
  }
}
