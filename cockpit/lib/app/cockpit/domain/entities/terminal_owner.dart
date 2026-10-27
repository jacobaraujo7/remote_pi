import 'package:flutter/foundation.dart';

/// Presentation and command boundary, independent of the selected worktree.
/// A document's portable box IDs are never session ownership credentials.
@immutable
class TerminalOwner {
  const TerminalOwner.workspace() : instanceId = null;
  const TerminalOwner.orchestration(String id)
    : assert(id != ''),
      instanceId = id;

  final String? instanceId;
  bool get isWorkspace => instanceId == null;

  @override
  bool operator ==(Object other) =>
      other is TerminalOwner && instanceId == other.instanceId;
  @override
  int get hashCode => instanceId.hashCode;
}
