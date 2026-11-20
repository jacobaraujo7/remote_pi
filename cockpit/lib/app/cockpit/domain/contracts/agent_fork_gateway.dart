import 'package:cockpit/app/cockpit/domain/entities/agent_fork.dart';
import 'package:cockpit/app/core/domain/entities/harness.dart';
import 'package:cockpit/app/core/domain/entities/terminal_profile.dart';
import 'package:cockpit/app/core/domain/result.dart';

abstract class AgentForkGateway {
  /// A detected process alone is insufficient: the adapter also needs an
  /// exact conversation identity and a compatible external fork operation.
  bool supports(HarnessKind harness);

  Future<Result<AgentForkLaunch, AgentForkFailure>> prepare({
    required AgentConversationIdentity identity,
    required TerminalProfile profile,
  });
}
