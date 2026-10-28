import 'dart:collection';

import 'package:flutter/foundation.dart';
import '../session/pane_item.dart';
import '../states/pane_node.dart';

/// Owns only one document's children; it never queries a workspace inventory.
/// Sessions must be constructed with this owner, not adopted from another dock.
/// Detach returns a session without disposing it: the presenter must unmount
/// its TerminalView before disposing the native controller.
class OrchestrationMultiplexer<T extends PaneItem> extends ChangeNotifier {
  OrchestrationMultiplexer({
    required this.instanceId,
    required this.projectId,
    this.windowActive,
  });

  final String instanceId;
  final String projectId;
  final bool Function()? windowActive;
  bool get _mayRead => _active && (windowActive?.call() ?? true);
  TerminalOwner get owner => TerminalOwner.orchestration(instanceId);
  final Map<String, T> _sessions = {};
  Map<String, T> get sessions => UnmodifiableMapView(_sessions);
  PaneNode? _tree;
  PaneNode? get tree => _tree;
  String? _focusedPaneId;
  String? get focusedPaneId => _focusedPaneId;
  String? _keyboardTabId;
  String? get keyboardTabId => _keyboardTabId;
  int _focusRevision = 0;
  int get focusRevision => _focusRevision;
  bool _active = false;
  bool get active => _active;
  bool _disposed = false;
  int _ids = 0;
  String _newId() => '$instanceId-pane-${++_ids}';

  bool contains(String tabId) => _sessions.containsKey(tabId);
  T? session(String tabId) => _sessions[tabId];
  LeafPane? paneOf(String tabId) => _tree == null
      ? null
      : leaves(_tree!).where((p) => p.tabs.contains(tabId)).firstOrNull;

  void attach(T session, {String? inPane, SplitDir? split, bool focus = true}) {
    _ensureAlive();
    if (session.owner != owner || session.projectId != projectId) {
      throw ArgumentError('Terminal does not belong to this orchestration');
    }
    if (_sessions.containsKey(session.id)) {
      if (!identical(_sessions[session.id], session)) {
        throw StateError('Duplicate terminal ID: ${session.id}');
      }
      return; // repeated reconciliation cannot duplicate tabs or listeners
    }
    final root = _tree;
    final target = root == null
        ? null
        : findLeaf(root, inPane ?? _focusedPaneId ?? '') ?? leaves(root).first;
    if (inPane != null && (root == null || findLeaf(root, inPane) == null)) {
      throw ArgumentError('Pane does not belong to this orchestration');
    }
    _sessions[session.id] = session;
    session.addListener(_onSessionChanged);
    if (target == null) {
      _tree = LeafPane(id: _newId(), tabs: [session.id], active: session.id);
    } else if (split == null) {
      _tree = updateLeaf(
        root!,
        target.id,
        (p) => p.copyWith(
          tabs: [...p.tabs, session.id],
          active: focus ? session.id : p.active,
        ),
      );
    } else {
      _tree = splitLeaf(
        root!,
        target.id,
        split,
        LeafPane(id: _newId(), tabs: [session.id], active: session.id),
        splitId: _newId(),
      );
    }
    final pane = paneOf(session.id)!;
    _focusedPaneId ??= pane.id;
    if (focus) {
      _focusedPaneId = pane.id;
      _keyboardTabId = session.id;
      _focusRevision++;
      if (_mayRead) session.clearUnseen();
    }
    notifyListeners();
  }

  /// Selection and keyboard focus are independent. Revealing a graph node
  /// must not send subsequent keystrokes to a hidden/previous terminal.
  bool reveal(String tabId, {bool focus = true}) {
    _ensureAlive();
    final pane = paneOf(tabId);
    if (pane == null) return false;
    _tree = updateLeaf(_tree!, pane.id, (p) => p.copyWith(active: tabId));
    if (focus) {
      _focusedPaneId = pane.id;
      _keyboardTabId = tabId;
      _focusRevision++;
      if (_mayRead) _sessions[tabId]!.clearUnseen();
    } else {
      _keyboardTabId = null;
    }
    notifyListeners();
    return true;
  }

  void releaseKeyboard() {
    _ensureAlive();
    if (_keyboardTabId == null) return;
    _keyboardTabId = null;
    notifyListeners();
  }

  /// Repositions an existing owned session without changing its controller.
  bool splitTab(
    String tabId,
    SplitDir direction, {
    String? anchorPaneId,
    bool before = false,
  }) {
    _ensureAlive();
    final source = paneOf(tabId);
    final root = _tree;
    final anchor = root == null
        ? null
        : findLeaf(root, anchorPaneId ?? _focusedPaneId ?? '');
    if (source == null || anchor == null) return false;
    if (source.id == anchor.id && source.tabs.length == 1) return false;
    final remaining = source.tabs.where((id) => id != tabId).toList();
    final removed = remaining.isEmpty
        ? removeLeaf(root!, source.id)
        : updateLeaf(
            root!,
            source.id,
            (p) => p.copyWith(
              tabs: remaining,
              active: source.active == tabId ? remaining.last : source.active,
            ),
          );
    final fresh = LeafPane(id: _newId(), tabs: [tabId], active: tabId);
    _tree = splitLeaf(
      removed,
      anchor.id,
      direction,
      fresh,
      splitId: _newId(),
      before: before,
    );
    _focusedPaneId = fresh.id;
    _keyboardTabId = tabId;
    _focusRevision++;
    if (_mayRead) _sessions[tabId]!.clearUnseen();
    notifyListeners();
    return true;
  }

  void setActive(bool value) {
    _ensureAlive();
    if (_active == value) return;
    _active = value;
    refreshReadEligibility();
    notifyListeners();
  }

  void refreshReadEligibility() {
    if (!_disposed && _mayRead && _keyboardTabId != null) {
      _sessions[_keyboardTabId]?.clearUnseen();
    }
  }

  /// Local unread state only. No system notifier or global controller is used.
  void turnFinished(T session) {
    if (_disposed || !identical(_sessions[session.id], session)) return;
    if (!_mayRead || _keyboardTabId != session.id) session.markUnseen();
  }

  bool move(String tabId, String destinationPaneId, {int? index}) {
    _ensureAlive();
    final source = paneOf(tabId);
    final root = _tree;
    final target = root == null ? null : findLeaf(root, destinationPaneId);
    if (source == null || target == null) return false;
    if (source.id == target.id) {
      _tree = updateLeaf(
        root!,
        source.id,
        (p) => p.copyWith(
          tabs: reorderTabs(p.tabs, tabId, index ?? p.tabs.length),
        ),
      );
    } else {
      final tabs = [...target.tabs];
      tabs.insert((index ?? tabs.length).clamp(0, tabs.length), tabId);
      var next = updateLeaf(
        root!,
        target.id,
        (p) => p.copyWith(tabs: tabs, active: tabId),
      );
      final remaining = source.tabs.where((id) => id != tabId).toList();
      next = remaining.isEmpty
          ? removeLeaf(next, source.id)
          : updateLeaf(
              next,
              source.id,
              (p) => p.copyWith(
                tabs: remaining,
                active: source.active == tabId ? remaining.last : source.active,
              ),
            );
      _tree = next;
    }
    _focusedPaneId = target.id;
    _keyboardTabId = tabId;
    _focusRevision++;
    if (_mayRead) _sessions[tabId]!.clearUnseen();
    notifyListeners();
    return true;
  }

  bool resize(String splitId, double fractionDelta) {
    _ensureAlive();
    final root = _tree;
    final split = root == null ? null : findSplit(root, splitId);
    if (split == null || !fractionDelta.isFinite) return false;
    _tree = setFrac(root!, splitId, (split.frac + fractionDelta).clamp(.1, .9));
    notifyListeners();
    return true;
  }

  T? detach(String tabId) {
    _ensureAlive();
    final pane = paneOf(tabId);
    final session = _sessions.remove(tabId);
    if (session == null) return null;
    session.removeListener(_onSessionChanged);
    if (pane != null) {
      final remaining = pane.tabs.where((id) => id != tabId).toList();
      if (_sessions.isEmpty) {
        _tree = null;
      } else if (remaining.isEmpty) {
        _tree = removeLeaf(_tree!, pane.id);
      } else {
        _tree = updateLeaf(
          _tree!,
          pane.id,
          (p) => p.copyWith(
            tabs: remaining,
            active: pane.active == tabId ? remaining.last : pane.active,
          ),
        );
      }
    }
    final root = _tree;
    final focus = root == null
        ? null
        : findLeaf(root, _focusedPaneId ?? '') ?? leaves(root).first;
    _focusedPaneId = focus?.id;
    if (_keyboardTabId == tabId) {
      _keyboardTabId = focus?.active;
      _focusRevision++;
    }
    notifyListeners();
    return session;
  }

  Map<String, dynamic> serialize() => {
    if (_tree != null) 'tree': paneNodeToJson(_tree!),
    'focusedPaneId': _focusedPaneId,
    'keyboardTabId': _keyboardTabId,
  };

  /// Only restore layout after all owned sessions have been registered. Reject
  /// foreign IDs and duplicate placements before changing any live state.
  void restoreLayout(Map<String, dynamic> state) {
    _ensureAlive();
    final raw = state['tree'];
    if (raw == null && _sessions.isEmpty) return;
    if (raw is! Map) throw const FormatException('Missing internal pane tree');
    final next = paneNodeFromJson(raw.cast<String, dynamic>());
    final nodes = <String>{};
    void checkNodes(PaneNode node) {
      if (!nodes.add(node.id)) throw const FormatException('Duplicate pane ID');
      if (node is SplitPane) {
        if (!node.frac.isFinite || node.frac <= 0 || node.frac >= 1) {
          throw const FormatException('Invalid pane fraction');
        }
        checkNodes(node.a);
        checkNodes(node.b);
      }
    }

    checkNodes(next);
    final placed = <String>{};
    for (final leaf in leaves(next)) {
      if (leaf.tabs.isEmpty || !leaf.tabs.contains(leaf.active)) {
        throw const FormatException('Invalid active terminal');
      }
      for (final id in leaf.tabs) {
        if (!_sessions.containsKey(id) || !placed.add(id)) {
          throw const FormatException('Foreign or duplicate terminal');
        }
      }
    }
    if (placed.length != _sessions.length) {
      throw const FormatException('Internal layout omits owned terminals');
    }
    final focusId = state['focusedPaneId'];
    final keyboardId = state['keyboardTabId'];
    final focus = focusId is String ? findLeaf(next, focusId) : null;
    if (focus == null || (keyboardId != null && keyboardId != focus.active)) {
      throw const FormatException('Invalid internal focus');
    }
    _tree = next;
    _focusedPaneId = focus.id;
    _keyboardTabId = keyboardId as String?;
    // Restored pane IDs may be sparse. Keep the generator above every suffix.
    for (final id in nodes) {
      final prefix = '$instanceId-pane-';
      if (!id.startsWith(prefix)) continue;
      final suffix = int.tryParse(id.substring(prefix.length));
      if (suffix != null && suffix > _ids) _ids = suffix;
    }
    _focusRevision++;
    notifyListeners();
  }

  void _onSessionChanged() {
    if (!_disposed) notifyListeners();
  }

  void _ensureAlive() {
    if (_disposed) throw StateError('Orchestration multiplexer is disposed');
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    for (final session in _sessions.values) {
      session.removeListener(_onSessionChanged);
    }
    // Session teardown belongs to the lifecycle coordinator, after UI detach.
    _sessions.clear();
    _tree = null;
    super.dispose();
  }
}
