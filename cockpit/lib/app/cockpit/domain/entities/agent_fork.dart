import 'package:cockpit/app/core/domain/entities/harness.dart';

enum AgentForkProblem {
  identifying,
  privateServerRequired,
  notSaved,
  checking,
  unavailable,
  incompatible,
  unsupportedHost,
  staleSession,
  busy,
  launchFailed,
}

/// Conversation identity is separate from the tab ID and from restore hints.
/// Ancestors bind a hook to the actual foreground agent process, preventing
/// a previous agent's delayed hooks from enabling a fork of the wrong chat.
class AgentConversationIdentity {
  const AgentConversationIdentity({
    required this.harness,
    required this.sessionId,
    required this.processIds,
    this.transcriptPath,
  });

  final HarnessKind harness;
  final String sessionId;
  final String? transcriptPath;
  final List<int> processIds;
}

class AgentForkLaunch {
  const AgentForkLaunch(this.command);
  final String command;
}

class AgentForkFailure {
  const AgentForkFailure(this.problem, {this.detail});
  final AgentForkProblem problem;
  final String? detail;
}
