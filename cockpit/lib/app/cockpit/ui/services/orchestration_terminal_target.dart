import '../states/pane_node.dart';

/// Resolve a terminal destination without moving the orchestration document
/// or changing the saved split tree. A split is needed only as a last resort.
({String paneId, SplitDir? split}) orchestrationTerminalTarget({
  required PaneNode tree,
  required String orchestrationTabId,
  required Set<String> terminalIds,
  String? lastTerminalPaneId,
}) {
  final panes = leaves(tree);
  final app = panes
      .where((p) => p.tabs.contains(orchestrationTabId))
      .firstOrNull;
  final candidates = panes
      .where((p) => p.id != app?.id && p.tabs.any(terminalIds.contains))
      .toList();
  final existing =
      candidates.where((p) => p.id == lastTerminalPaneId).firstOrNull ??
      candidates.firstOrNull;
  if (existing != null) return (paneId: existing.id, split: null);
  return (
    paneId: app?.id ?? panes.first.id,
    split: app == null ? null : SplitDir.vertical,
  );
}
