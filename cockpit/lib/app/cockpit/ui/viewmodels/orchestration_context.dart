import 'dart:async';
import 'dart:ui' show Offset;

import 'package:flutter/foundation.dart';
import '../../../core/domain/result.dart';
import '../../domain/entities/orchestration_document.dart';
import '../../domain/entities/orchestration_presentation.dart';
import '../../domain/entities/workspace_graph.dart';
import '../../domain/value_objects/uid.dart';
import '../services/orchestration_controller.dart';
import '../session/pane_item.dart';
import '../session/terminal_session.dart';
import '../states/pane_node.dart';
import 'orchestration_multiplexer.dart';
import 'workspace_graph_context.dart';

typedef OrchestrationBoxAction =
    Future<Result<String, String>> Function(String boxId);

/// One document's graph, inspector and terminal actions. No global VM or
/// workspace session inventory is available to this model or its renderers.
class OrchestrationContext extends ChangeNotifier
    implements WorkspaceGraphContext {
  OrchestrationContext({
    required this.instanceId,
    required this.projectId,
    required this.controller,
    required this.terminals,
    required this._title,
    this._remoteDisconnected,
    this._presentation = const OrchestrationPresentation(),
    this.onOpenShell,
    this.onStartCli,
    this.onHandoff,
    this.onSuggestRole,
    this.onPersist,
  }) {
    controller.addListener(_onDocument);
    terminals.addListener(_onTerminals);
  }
  final String instanceId;
  final String projectId;
  final OrchestrationController controller;
  final OrchestrationMultiplexer<TerminalSession> terminals;
  final String Function() _title;
  final bool Function()? _remoteDisconnected;
  final OrchestrationBoxAction? onOpenShell,
      onStartCli,
      onHandoff,
      onSuggestRole;
  final VoidCallback? onPersist;
  bool _disposed = false;
  bool get disposed => _disposed;
  OrchestrationPresentation _presentation;
  OrchestrationPresentation get presentation => _presentation;
  final List<GraphObservedLink> _traffic = [];
  final Map<String, GraphUnresolvedPeer> _peers = {};
  final GraphSubagentRegistry _children = GraphSubagentRegistry();
  String? _lastKeyboardTab;

  @override
  String get selectedProjectId => projectId;
  @override
  String get selectedDisplayTitle => _title();
  @override
  bool get selectedRemoteDisconnected => _remoteDisconnected?.call() ?? false;
  @override
  List<GraphBox> get graphBoxes => List.unmodifiable(controller.graphBoxes);
  @override
  List<GraphLink> get graphLinks =>
      List.unmodifiable(controller.document?.links ?? const []);
  @override
  List<GraphObservedLink> get graphTraffic => List.unmodifiable(
    _traffic.where(
      (e) => terminals.contains(e.fromTabId) && terminals.contains(e.toTabId),
    ),
  );
  @override
  List<GraphUnresolvedPeer> get graphUnresolvedPeers => List.unmodifiable(
    _peers.values.where((e) => terminals.contains(e.ownerTabId)),
  );
  @override
  List<GraphSubagent> get graphSubagents => List.unmodifiable(
    _children
        .forProject(projectId)
        .where((e) => terminals.contains(e.ownerTabId)),
  );
  @override
  TerminalSession? session(String id) => terminals.session(id);
  @override
  GraphBox? graphBoxForTab(String tabId) => !terminals.contains(tabId)
      ? null
      : graphBoxes.where((b) => b.tabId == tabId).firstOrNull;
  GraphBox? get selectedWorkspaceBox =>
      graphBoxes
          .where((b) => b.id == _presentation.selectedBoxId)
          .firstOrNull ??
      graphBoxes.firstOrNull;

  void _changed() {
    if (_disposed) return;
    onPersist?.call();
    notifyListeners();
  }

  void documentRenamed() => _changed();

  void _onDocument() {
    final doc = controller.document;
    if (doc != null) {
      _presentation = _presentation.copyWith(
        boxOrder: doc.boxes.map((b) => b.box.id).toList(),
      );
      for (final b in graphBoxes) {
        final terminal = session(b.tabId ?? '');
        if (terminal != null && terminal.manualLabel != b.title) {
          terminal.setManualLabel(b.title);
        }
      }
    }
    _changed();
  }

  void _onTerminals() {
    final keyboard = terminals.keyboardTabId;
    if (keyboard != _lastKeyboardTab) {
      _lastKeyboardTab = keyboard;
      final box = keyboard == null ? null : graphBoxForTab(keyboard);
      if (box != null) {
        _presentation = _presentation.copyWith(selectedBoxId: box.id);
      }
    }
    _changed();
  }

  /// Startup-only local state; never writes/reorders the portable document.
  void restorePresentation(OrchestrationPresentation value) {
    if (_disposed) return;
    _lastKeyboardTab = terminals.keyboardTabId;
    _presentation = value;
    notifyListeners();
  }

  void updatePresentation(OrchestrationPresentation value) {
    if (_disposed) return;
    final reorder = !listEquals(value.boxOrder, _presentation.boxOrder);
    _presentation = value.copyWith(boxOrder: value.boxOrder);
    _changed();
    if (reorder) {
      final rank = {for (final (i, id) in value.boxOrder.indexed) id: i};
      unawaited(
        controller.mutate((doc) {
          final boxes = [...doc.boxes];
          final original = {for (final (i, b) in boxes.indexed) b.box.id: i};
          boxes.sort(
            (a, b) => (rank[a.box.id] ?? rank.length + original[a.box.id]!)
                .compareTo(rank[b.box.id] ?? rank.length + original[b.box.id]!),
          );
          return OrchestrationDocument(
            boxes: boxes,
            links: doc.links,
            extra: doc.extra,
          );
        }),
      );
    }
  }

  void setWorkspaceView(OrchestrationViewMode mode) {
    terminals.releaseKeyboard();
    updatePresentation(_presentation.copyWith(mode: mode));
  }

  @override
  void selectWorkspaceBox(String boxId, {bool configure = false}) {
    if (_disposed || !graphBoxes.any((b) => b.id == boxId)) return;
    if (configure) terminals.releaseKeyboard();
    updatePresentation(
      _presentation.copyWith(
        selectedBoxId: boxId,
        inspectorOpen: configure ? true : null,
      ),
    );
  }

  void revealBox(String boxId, {bool focus = true}) {
    if (_disposed) return;
    final box = graphBoxes.where((b) => b.id == boxId).firstOrNull;
    if (box == null) return;
    selectWorkspaceBox(boxId);
    terminals.reveal(box.tabId ?? '', focus: focus);
  }

  @override
  void openBoxInTerminals(String boxId) => revealBox(boxId);
  @override
  String ensureGraphBoxForTab(PaneItem item, Offset position) {
    if (!identical(session(item.id), item)) {
      throw ArgumentError('Foreign terminal');
    }
    final box = graphBoxForTab(item.id);
    if (box == null) throw StateError('Terminal has no document definition');
    return box.id;
  }

  @override
  void moveGraphBox(String boxId, Offset position) {
    if (_disposed || !position.dx.isFinite || !position.dy.isFinite) return;
    unawaited(
      controller.mutate(
        (doc) => OrchestrationDocument(
          boxes: [
            for (final b in doc.boxes)
              b.box.id == boxId
                  ? OrchestrationBox(
                      box: b.box.copyWith(position: position),
                      directory: b.directory,
                    )
                  : b,
          ],
          links: doc.links,
          extra: doc.extra,
        ),
      ),
    );
  }

  @override
  void addGraphLink(String from, String to) {
    if (_disposed || from == to) return;
    unawaited(
      controller.mutate((doc) {
        final ids = doc.boxes.map((b) => b.box.id).toSet();
        if (!ids.contains(from) || !ids.contains(to)) return doc;
        return OrchestrationDocument(
          boxes: doc.boxes,
          links: [
            ...doc.links,
            if (!doc.links.any((l) => l.from == from && l.to == to))
              GraphLink(from: from, to: to),
          ],
          extra: doc.extra,
        );
      }),
    );
  }

  @override
  void removeGraphLink(String from, String to) {
    if (_disposed) return;
    unawaited(
      controller.mutate(
        (doc) => OrchestrationDocument(
          boxes: doc.boxes,
          links: doc.links.where((l) => l.from != from || l.to != to).toList(),
          extra: doc.extra,
        ),
      ),
    );
  }

  Result<String, String>? _validate(String title, String tool, String model) {
    if (title.trim().isEmpty) return const Failure('Title is required');
    if (tool.isNotEmpty && !const {'claude', 'codex', 'pi'}.contains(tool)) {
      return const Failure('Unsupported tool');
    }
    if (model.isNotEmpty && !RegExp(r'^[a-zA-Z0-9._:/-]+$').hasMatch(model)) {
      return const Failure('Invalid model');
    }
    return null;
  }

  Result<String, String> _result(String id) => _disposed
      ? const Failure('Document closed')
      : controller.error != null || controller.dirty
      ? Failure(controller.error ?? 'Document has unsaved changes')
      : Success(id);

  Future<Result<String, String>> configureBox(
    String boxId, {
    String? title,
    required String role,
    required String harness,
    required String model,
    String? directory,
  }) async {
    if (_disposed) return const Failure('Document closed');
    final box = graphBoxes.where((b) => b.id == boxId).firstOrNull;
    if (box == null) return const Failure('Box not found');
    final tool = harness == 'claudeCode' ? 'claude' : harness;
    final invalid = _validate(title ?? box.title, tool, model.trim());
    if (invalid != null) return invalid;
    await controller.mutate((doc) {
      if (!doc.boxes.any((b) => b.box.id == boxId)) {
        throw StateError('Box not found');
      }
      return OrchestrationDocument(
        boxes: [
          for (final b in doc.boxes)
            b.box.id == boxId
                ? OrchestrationBox(
                    box: b.box.copyWith(
                      title: title?.trim(),
                      role: role.trim(),
                      harness: tool,
                      model: model.trim(),
                    ),
                    directory: directory?.trim() ?? b.directory,
                  )
                : b,
        ],
        links: doc.links,
        extra: doc.extra,
      );
    });
    return _result(boxId);
  }

  @override
  Future<Result<String, String>> configureGraphBox({
    required String boxId,
    String? title,
    required String role,
    required String harness,
    required String model,
  }) => configureBox(
    boxId,
    title: title,
    role: role,
    harness: harness,
    model: model,
  );

  Future<Result<String, String>> newTerminal({
    String? title,
    String? inPane,
    SplitDir? split,
  }) async {
    final anchor = inPane ?? terminals.focusedPaneId;
    if (inPane != null &&
        (terminals.tree == null || findLeaf(terminals.tree!, inPane) == null)) {
      return const Failure('Foreign pane');
    }
    final result = await createGraphBox(
      title: title ?? 'Terminal ${graphBoxes.length + 1}',
      role: '',
      harness: '',
      model: '',
      position: OrchestrationController.autoPosition(graphBoxes.length),
    );
    if (result case Success(:final value) when !_disposed) {
      final target =
          terminals.tree == null ||
              anchor == null ||
              findLeaf(terminals.tree!, anchor) == null
          ? terminals.paneOf(value)?.id
          : anchor;
      if (target != null) {
        if (split != null) {
          terminals.splitTab(value, split, anchorPaneId: target);
        } else if (terminals.paneOf(value)?.id != target) {
          terminals.move(value, target);
        }
      }
    }
    return result;
  }

  @override
  Future<Result<String, String>> createGraphBox({
    required String title,
    required String role,
    required String harness,
    required String model,
    required Offset position,
  }) async {
    if (_disposed) return const Failure('Document closed');
    final invalid = _validate(title, harness, model);
    if (invalid != null) return invalid;
    if (!position.dx.isFinite || !position.dy.isFinite) {
      return const Failure('Invalid graph position');
    }
    final id = newUid();
    await controller.addBox(
      OrchestrationBox(
        box: GraphBox(
          id: id,
          title: title.trim(),
          role: role.trim(),
          harness: harness,
          model: model,
          position: position,
        ),
      ),
    );
    final tabId = controller.bindings[id];
    if (tabId != null && terminals.contains(tabId)) revealBox(id);
    return _result(tabId ?? id);
  }

  Future<Result<String, String>> _act(
    String boxId,
    OrchestrationBoxAction? action, {
    String? workspaceId,
  }) async {
    if (_disposed) return const Failure('Document closed');
    if (workspaceId != null && workspaceId != projectId) {
      return const Failure('Foreign workspace');
    }
    if (!graphBoxes.any((b) => b.id == boxId)) {
      return const Failure('Box not found');
    }
    if (selectedRemoteDisconnected) return const Failure('Host disconnected');
    if (action == null) return const Failure('Session action unavailable');
    final result = await action(boxId);
    return _disposed ? const Failure('Document closed') : result;
  }

  @override
  Future<Result<String, String>> openBoxShell(
    String boxId, {
    String? workspaceId,
  }) => _act(boxId, onOpenShell, workspaceId: workspaceId);
  @override
  Future<Result<String, String>> relaunchGraphBox(
    String boxId, {
    String? workspaceId,
  }) => _act(boxId, onStartCli, workspaceId: workspaceId);
  @override
  Future<Result<String, String>> startGraphHandoff(
    String boxId, {
    String? workspaceId,
  }) => _act(boxId, onHandoff, workspaceId: workspaceId);
  Future<Result<String, String>> suggestRole(String boxId) =>
      _act(boxId, onSuggestRole);

  void recordTraffic(String from, String to, {DateTime? at}) {
    if (_disposed ||
        from == to ||
        !terminals.contains(from) ||
        !terminals.contains(to)) {
      return;
    }
    _traffic.removeWhere((e) => e.fromTabId == from && e.toTabId == to);
    _traffic.add(
      GraphObservedLink(
        fromTabId: from,
        toTabId: to,
        observedAt: at ?? DateTime.now(),
      ),
    );
    if (_traffic.length > 256) _traffic.removeAt(0);
    _changed();
  }

  void recordPeer(GraphUnresolvedPeer peer) {
    if (_disposed ||
        peer.projectId != projectId ||
        !terminals.contains(peer.ownerTabId)) {
      return;
    }
    _peers[peer.id] = peer;
    _changed();
  }

  void startSubagent(GraphSubagent child) {
    if (_disposed ||
        child.projectId != projectId ||
        !terminals.contains(child.ownerTabId)) {
      return;
    }
    if (_children.start(child)) _changed();
  }

  void stopSubagent(String parentId, String agentId, DateTime at) {
    if (_disposed || !terminals.contains(parentId)) return;
    if (_children.stop(parentId, agentId, at)) _changed();
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    controller.removeListener(_onDocument);
    terminals.removeListener(_onTerminals);
    super.dispose();
  }
}
