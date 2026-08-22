import 'package:cockpit/app/cockpit/domain/entities/process_snapshot.dart';
import 'package:cockpit/app/core/domain/entities/harness.dart';
import 'package:cockpit/app/cockpit/domain/services/terminal_harness_classifier.dart';

abstract class ProcessTreeResolver {
  /// Resolves the effective interactive harness from a process tree snapshot
  /// rooted at [rootPid].
  ///
  /// Returns the innermost active interactive harness in the foreground
  /// ancestry path, or null if no interactive harness is active.
  static HarnessKind? resolve({
    required int rootPid,
    required List<ProcessSnapshot> snapshots,
  }) {
    if (snapshots.isEmpty) return null;

    final procMap = <int, ProcessSnapshot>{};
    for (final s in snapshots) {
      procMap[s.pid] = s;
    }

    if (!procMap.containsKey(rootPid)) return null;

    // Collect all descendants of rootPid
    final descendantPids = <int>{rootPid};
    bool added;
    do {
      added = false;
      for (final s in snapshots) {
        if (!descendantPids.contains(s.pid) && descendantPids.contains(s.ppid)) {
          descendantPids.add(s.pid);
          added = true;
        }
      }
    } while (added);

    // Build paths from rootPid down to leaf nodes
    final paths = _buildAncestryPaths(rootPid, descendantPids, procMap);

    HarnessKind? deepestHarness;
    int maxDepth = -1;

    for (final path in paths) {
      int currentDepth = 0;
      for (final pid in path) {
        final proc = procMap[pid];
        if (proc == null) continue;

        // Skip non-foreground or suspended processes
        if (!proc.isForeground) continue;
        if (proc.state != null && proc.state!.toUpperCase().contains('T')) continue;

        final kind = TerminalHarnessClassifier.classify(
          executable: proc.executable,
          argv: proc.argv,
        );

        if (kind != null) {
          if (currentDepth >= maxDepth) {
            maxDepth = currentDepth;
            deepestHarness = kind;
          }
        }
        currentDepth++;
      }
    }

    return deepestHarness;
  }

  static List<List<int>> _buildAncestryPaths(
    int rootPid,
    Set<int> descendantPids,
    Map<int, ProcessSnapshot> procMap,
  ) {
    final childrenMap = <int, List<int>>{};
    for (final pid in descendantPids) {
      final proc = procMap[pid];
      if (proc != null && proc.ppid != pid && descendantPids.contains(proc.ppid)) {
        childrenMap.putIfAbsent(proc.ppid, () => []).add(pid);
      }
    }

    final result = <List<int>>[];
    void dfs(int currentPid, List<int> currentPath) {
      final path = [...currentPath, currentPid];
      final children = childrenMap[currentPid];
      if (children == null || children.isEmpty) {
        result.add(path);
      } else {
        for (final child in children) {
          dfs(child, path);
        }
      }
    }

    dfs(rootPid, []);
    return result;
  }
}
