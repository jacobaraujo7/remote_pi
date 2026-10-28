import 'dart:async';
import 'dart:ui' show Offset;

import 'package:flutter/foundation.dart';
import '../../../core/domain/result.dart';
import '../../domain/entities/orchestration_document.dart';
import '../../domain/contracts/terminal_status_server.dart';
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
    this.onRevealTerminals,
    this.readAliases,
  }) {
    _knownTerminals.addAll(terminals.sessions.keys);
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
  final VoidCallback? onRevealTerminals;
  final Future<Set<String>> Function(TerminalSession)? readAliases;
  bool _disposed = false;
  bool get disposed => _disposed;
  OrchestrationPresentation _presentation;
  OrchestrationPresentation get presentation => _presentation;
  final List<GraphObservedLink> _traffic = [];
  final Map<String, GraphUnresolvedPeer> _peers = {};
  final GraphSubagentRegistry _children = GraphSubagentRegistry();
  String? _lastKeyboardTab;
  final Map<String, Set<String>> _aliases = {};
  final Set<String> _endedSessions = {};
  final Set<String> _knownTerminals = {};
  final Map<String, int> _activityEpoch = {};
  final Set<(String, String?, String?)> _aliasReads = {};
  final Map<String, DateTime> _lastAliasRead = {};

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
    final current = terminals.sessions.keys.toSet();
    for (final removed in _knownTerminals.difference(current)) {
      _clearActivity(removed);
      _endedSessions.remove(removed);
      _activityEpoch.remove(removed);
    }
    for (final stopped in terminals.sessions.values.where((t) => t.hasExited)) {
      if (_endedSessions.add(stopped.id)) _clearActivity(stopped.id);
    }
    _knownTerminals
      ..clear()
      ..addAll(current);
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
    onRevealTerminals?.call();
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

  /// Native tab and keyboard commands share the graph/inspector selection.
  void focusTerminalTab(String tabId) {
    if (_disposed || !terminals.contains(tabId)) return;
    onRevealTerminals?.call();
    final box = graphBoxes.where((b) => b.tabId == tabId).firstOrNull;
    if (box != null) {
      revealBox(box.id);
    } else {
      terminals.reveal(tabId);
    }
  }

  LeafPane? _focusedTerminalPane() {
    final tree = terminals.tree;
    if (_disposed || tree == null) return null;
    return findLeaf(tree, terminals.focusedPaneId ?? '') ??
        leaves(tree).firstOrNull;
  }

  void selectTerminalTabByIndex(int index) {
    final pane = _focusedTerminalPane();
    if (pane == null || index < 0 || index >= pane.tabs.length) return;
    focusTerminalTab(pane.tabs[index]);
  }

  void selectLastTerminalTab() {
    final pane = _focusedTerminalPane();
    if (pane != null && pane.tabs.isNotEmpty) focusTerminalTab(pane.tabs.last);
  }

  void cycleTerminalTab(int delta) {
    final pane = _focusedTerminalPane();
    if (pane == null || pane.tabs.isEmpty) return;
    final index = pane.tabs.indexOf(pane.active);
    focusTerminalTab(
      pane.tabs[((index < 0 ? 0 : index) + delta) % pane.tabs.length],
    );
  }

  void focusTerminalPaneToward(PaneMove move) {
    final tree = terminals.tree;
    final pane = _focusedTerminalPane();
    if (tree == null || pane == null) return;
    final target = neighborLeaf(tree, pane.id, move);
    final next = target == null ? null : findLeaf(tree, target)?.active;
    if (next != null) focusTerminalTab(next);
  }

  Future<Result<String, String>> newTerminal({
    String? title,
    String? inPane,
    SplitDir? split,
    String directory = '.',
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
      directory: directory,
      reveal: false,
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
      focusTerminalTab(value);
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
    String directory = '.',
    bool reveal = true,
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
        directory: directory,
      ),
    );
    final tabId = controller.bindings[id];
    if (reveal && tabId != null && terminals.contains(tabId)) {
      revealBox(id);
    }
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

  /// Route only an event whose exact terminal belongs to this instance. This
  /// never touches a workspace inventory or the global notification controller.
  bool applyHook(ClaudeStatusUpdate update) {
    if (_disposed) return false;
    final terminal = session(update.paneId);
    if (terminal == null || terminal.hasExited) return false;
    if (!const {
      'working',
      'waiting',
      'idle',
      'metric',
      'subagent_start',
      'subagent_stop',
    }.contains(update.status)) {
      return false;
    }
    final previousSid = terminal.claudeSessionId;
    final incomingSid = update.sessionId;
    final harnessChanged =
        update.harness != null &&
        AgentHarness.fromWire(update.harness) != terminal.agentHarness &&
        !update.status.startsWith('subagent_') &&
        update.status != 'metric';
    final newSession =
        harnessChanged ||
        update.event == 'UserPromptSubmit' ||
        update.event == 'SessionStart' ||
        (incomingSid != null &&
            incomingSid.isNotEmpty &&
            incomingSid != previousSid &&
            !update.status.startsWith('subagent_') &&
            update.status != 'metric');
    if (_endedSessions.contains(terminal.id) && !newSession) return false;
    if (newSession) _endedSessions.remove(terminal.id);
    if (update.status == 'metric') {
      if (incomingSid != null &&
          incomingSid.isNotEmpty &&
          previousSid != null &&
          incomingSid != previousSid) {
        return false;
      }
      if (update.contextTokens != null && update.contextWindow != null) {
        terminal.applyGraphMetrics(
          update.contextTokens!,
          update.contextWindow!,
        );
      }
      return true;
    }
    if (update.status == 'subagent_start') {
      final id = update.subagentId;
      if (id != null && id.isNotEmpty) {
        startSubagent(
          GraphSubagent(
            projectId: projectId,
            ownerTabId: terminal.id,
            agentId: id,
            agentType: update.subagentType ?? '',
            harness: update.harness ?? terminal.agentHarness.wire,
            startedAt: update.eventAt ?? DateTime.now(),
          ),
        );
      }
      return true;
    }
    if (update.status == 'subagent_stop') {
      final id = update.subagentId;
      if (id != null) {
        stopSubagent(terminal.id, id, update.eventAt ?? DateTime.now());
      }
      return true;
    }
    if (harnessChanged ||
        (incomingSid != null &&
            incomingSid.isNotEmpty &&
            previousSid != null &&
            incomingSid != previousSid)) {
      _clearActivity(terminal.id);
      terminal.transcriptPath = null;
      terminal.clearGraphMetrics();
    }
    if (update.harness == 'claude') {
      if (update.graphSelfName case final String ownAddress) {
        registerIdentity(terminal.id, ownAddress);
      }
      if (update.graphRecipient case final String recipient) {
        recordMessage(terminal.id, recipient, at: update.eventAt);
      }
    }
    if (update.event == 'SessionEnd') {
      _endedSessions.add(terminal.id);
      if (_clearActivity(terminal.id)) _changed();
    }
    terminal.applyClaudeStatus(
      status: switch (update.status) {
        'working' => TerminalStatus.working,
        'waiting' => TerminalStatus.waiting,
        _ => TerminalStatus.idle,
      },
      isTurnStart: update.event == 'UserPromptSubmit',
      sessionId: update.sessionId,
      transcriptPath: update.transcriptPath,
      harness: AgentHarness.fromWire(update.harness),
    );
    if (update.event == 'SessionEnd') {
      terminal.observeRemoteHookHarness(null);
    } else if (terminal.claudeSessionId != null &&
        (update.harness == null ||
            AgentHarness.values.any((h) => h.wire == update.harness))) {
      terminal.observeRemoteHookHarness(terminal.agentHarness);
    }
    if (terminal.claudeSessionId != previousSid) onPersist?.call();
    if (update.event != 'SessionEnd' &&
        update.harness == 'claude' &&
        (update.transcriptPath != null ||
            terminal.claudeSessionId != previousSid)) {
      unawaited(reconcileIdentities());
    }
    return true;
  }

  void registerIdentity(String tabId, String address) {
    final alias = address.trim().toLowerCase();
    if (_disposed ||
        !terminals.contains(tabId) ||
        alias.isEmpty ||
        alias.length > 128) {
      return;
    }
    _aliases.putIfAbsent(alias, () => {}).add(tabId);
    if (_aliases.length > 256) _aliases.remove(_aliases.keys.first);
    _resolvePeers(alias);
  }

  void recordMessage(String tabId, String address, {DateTime? at}) {
    final recipient = address.trim();
    if (_disposed ||
        !terminals.contains(tabId) ||
        recipient.isEmpty ||
        recipient.length > 128) {
      return;
    }
    final targets = _aliases[recipient.toLowerCase()];
    if (targets?.length == 1 && terminals.contains(targets!.single)) {
      if (targets.single != tabId) recordTraffic(tabId, targets.single, at: at);
      return;
    }
    recordPeer(
      GraphUnresolvedPeer(
        projectId: projectId,
        ownerTabId: tabId,
        address: recipient,
        observedAt: at ?? DateTime.now(),
      ),
    );
    unawaited(reconcileIdentities());
  }

  void _resolvePeers(String alias) {
    final targets = _aliases[alias];
    if (targets == null || targets.length != 1) return;
    final target = targets.single;
    final matches = _peers.values
        .where((p) => p.address.toLowerCase() == alias)
        .toList();
    for (final peer in matches) {
      _peers.remove(peer.id);
      if (peer.ownerTabId != target) {
        recordTraffic(peer.ownerTabId, target, at: peer.observedAt);
      }
    }
    if (matches.isNotEmpty) _changed();
  }

  /// Only known own transcripts are eligible. No global transcript discovery or
  /// other app's aliases can resolve an address in this instance.
  Future<void> reconcileIdentities() async {
    final reader = readAliases;
    if (_disposed || reader == null) return;
    for (final terminal in terminals.sessions.values.toList()) {
      if (terminal.agentHarness != AgentHarness.claude ||
          terminal.hasExited ||
          _endedSessions.contains(terminal.id) ||
          terminal.transcriptPath == null ||
          terminal.claudeSessionId == null) {
        continue;
      }
      final key = (
        terminal.id,
        terminal.claudeSessionId,
        terminal.transcriptPath,
      );
      final now = DateTime.now();
      if (_aliasReads.contains(key) ||
          now.difference(_lastAliasRead[terminal.id] ?? DateTime(1970)) <
              const Duration(seconds: 5)) {
        continue;
      }
      _aliasReads.add(key);
      _lastAliasRead[terminal.id] = now;
      final epoch = _activityEpoch[terminal.id] ?? 0;
      try {
        final aliases = await reader(terminal);
        if (_disposed ||
            !identical(session(terminal.id), terminal) ||
            terminal.hasExited ||
            terminal.claudeSessionId != key.$2 ||
            terminal.transcriptPath != key.$3 ||
            (_activityEpoch[terminal.id] ?? 0) != epoch) {
          continue;
        }
        for (final alias in aliases) {
          registerIdentity(terminal.id, alias);
        }
      } catch (_) {
        // Identity remains unresolved; a later event can retry without changing
        // the native session or fabricating a connection.
      } finally {
        _aliasReads.remove(key);
      }
    }
  }

  bool _clearActivity(String tabId) {
    final before = _traffic.length + _peers.length;
    _traffic.removeWhere((e) => e.fromTabId == tabId || e.toTabId == tabId);
    _peers.removeWhere((_, peer) => peer.ownerTabId == tabId);
    _aliases.removeWhere((_, tabs) {
      tabs.remove(tabId);
      return tabs.isEmpty;
    });
    _activityEpoch[tabId] = (_activityEpoch[tabId] ?? 0) + 1;
    _lastAliasRead.remove(tabId);
    final children = _children.clearOwner(tabId);
    return children || before != _traffic.length + _peers.length;
  }

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
    if (_peers.length > 64) _peers.remove(_peers.keys.first);
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
