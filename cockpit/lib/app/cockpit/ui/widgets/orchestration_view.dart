import 'dart:async';
import '../../../core/domain/entities/harness.dart';
import '../services/orchestration_live_sessions.dart';
import 'package:flutter_modular/flutter_modular.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';
import 'package:path/path.dart' as path;
import '../../domain/entities/workspace_graph.dart';
import '../../domain/entities/orchestration_presentation.dart';
import '../../domain/contracts/process_metrics_provider.dart';
import '../services/graph_telemetry_service.dart';
import '../session/orchestration_session.dart';
import '../session/terminal_session.dart';
import '../viewmodels/cockpit_viewmodel.dart';
import '../../../core/ui/themes/themes.dart';
import '../../../../i18n/strings.g.dart';
import 'workspace_box_list.dart';
import 'workspace_box_inspector.dart';
import 'workspace_graph_view.dart';

/// A normal dockable document. This widget never owns a TerminalView.
class OrchestrationView extends StatefulWidget {
  const OrchestrationView({
    super.key,
    required this.session,
    required this.vm,
    required this.active,
    this.processMetrics,
  });
  final OrchestrationSession session;
  final CockpitViewModel vm;
  final bool active;
  final ProcessMetricsProvider? processMetrics;
  @override
  State<OrchestrationView> createState() => _OrchestrationViewState();
}

class _OrchestrationViewState extends State<OrchestrationView> {
  final Map<String, GraphTelemetrySnapshot> _metrics = {};
  Timer? _timer;
  bool _refreshing = false;
  OrchestrationLiveSessions? _live;
  OrchestrationLiveSessions get _liveSessions {
    // Also replace listeners created before this performance update on hot reload.
    if (_live != null &&
        (_live!.schedule == null ||
            _live!.sources.isNotEmpty != widget.active)) {
      _live!.dispose();
      _live = null;
    }
    return _live ??= OrchestrationLiveSessions(
      sources: widget.active ? [widget.vm, widget.session] : const [],
      sessionState: () => widget.active
          ? [
              for (final t
                  in widget.vm.allSessions.whereType<TerminalSession>().where(
                    (t) => t.projectId == widget.session.projectId,
                  ))
                (
                  t.id,
                  t.status,
                  t.activeHarness,
                  t.hasExited,
                  t.unseenFinish,
                  t.displayTitle,
                ),
            ]
          : const [],
      schedule: (callback) =>
          WidgetsBinding.instance.scheduleFrameCallback((_) => callback()),
      sessions: () => widget.active
          ? widget.vm.allSessions.whereType<TerminalSession>().where(
              (t) => t.projectId == widget.session.projectId,
            )
          : const [],
    );
  }

  @override
  void didUpdateWidget(covariant OrchestrationView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.vm != widget.vm ||
        oldWidget.session != widget.session ||
        oldWidget.active != widget.active) {
      _live?.dispose();
      _live = null;
      _metrics.clear();
    }
    if ((!oldWidget.active && widget.active) ||
        oldWidget.session != widget.session) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _refresh());
    }
  }

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 10), (_) => _refresh());
    WidgetsBinding.instance.addPostFrameCallback((_) => _refresh());
  }

  Future<void> _refresh() async {
    if (_refreshing ||
        !mounted ||
        !widget.active ||
        widget.vm.selectedProjectId != widget.session.projectId) {
      return;
    }
    _refreshing = true;
    final documentSession = widget.session;
    final documentPath = documentSession.path;
    try {
      final next = <String, GraphTelemetrySnapshot>{};
      for (final box in documentSession.controller.graphBoxes) {
        final session = widget.vm.session(box.tabId ?? '');
        if (session == null) continue;
        next[session.id] = await const GraphTelemetryService().snapshot(
          session,
        );
      }
      if (!mounted ||
          widget.session != documentSession ||
          documentSession.path != documentPath) {
        return;
      }
      setState(() {
        _metrics
          ..clear()
          ..addAll(next);
      });
    } finally {
      _refreshing = false;
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    _live?.dispose();
    super.dispose();
  }

  WorkspaceBoxEntry _entry(GraphBox box) {
    final s = widget.vm.session(box.tabId ?? '');
    final t = s is TerminalSession ? s : null;
    return WorkspaceBoxEntry(
      box: box,
      status: widget.vm.selectedRemoteDisconnected
          ? WorkspaceBoxStatus.disconnected
          : t == null
          ? WorkspaceBoxStatus.disconnected
          : t.hasExited
          ? WorkspaceBoxStatus.closed
          : switch (t.status) {
              TerminalStatus.working => WorkspaceBoxStatus.working,
              TerminalStatus.waiting => WorkspaceBoxStatus.waiting,
              TerminalStatus.idle =>
                t.activeHarness == null
                    ? WorkspaceBoxStatus.shell
                    : WorkspaceBoxStatus.idle,
            },
      tool: t?.activeHarness == null
          ? ''
          : HarnessCatalog.specs[t!.activeHarness]!.label,
      unseen: t?.unseenFinish ?? false,
      contextPercent: t == null || t.hasExited
          ? null
          : _metrics[t.id]?.contextPercent,
    );
  }

  @override
  Widget build(BuildContext context) {
    final vm = widget.vm;
    return ListenableBuilder(
      listenable: _liveSessions,
      builder: (context, _) {
        // An offstage document must never project another worktree's selection.
        if (vm.selectedProjectId != widget.session.projectId) {
          return const SizedBox.shrink();
        }
        final controller = widget.session.controller;
        controller.startPolling();
        final t = context.t.workspaceView;
        final tr = context.t.orchestration;
        final state = vm.presentation;
        final selected = vm.selectedWorkspaceBox;
        void select(String id, {bool configure = false}) =>
            vm.selectWorkspaceBox(id, configure: configure);
        final entries = [for (final b in vm.graphBoxes) _entry(b)];
        Widget inspector() => WorkspaceBoxInspector(
          key: ValueKey('inspector-${widget.session.path}-${selected!.id}'),
          vm: vm,
          box: selected,
          entry: _entry(selected),
          projectId: widget.session.projectId,
          directory:
              controller.document?.boxes
                  .where((b) => b.box.id == selected.id)
                  .firstOrNull
                  ?.directory ??
              '.',
          onSuggestRole: () => vm.suggestOrchestrationRole(
            widget.session.projectId,
            selected.id,
          ),
          onSave: (name, role, tool, model, directory) =>
              vm.configureOrchestrationBox(
                widget.session.projectId,
                selected.id,
                title: name,
                role: role,
                harness: tool,
                model: model,
                directory: directory,
              ),
          onClose: () =>
              vm.updatePresentation(state.copyWith(inspectorOpen: false)),
        );
        return Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(8),
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  SizedBox(
                    width: 160,
                    child: Text(
                      path.basename(widget.session.path),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: context.typo.body.copyWith(
                        fontSize: 13,
                        fontWeight: FontWeight.w400,
                      ),
                    ),
                  ),
                  OutlineButton(
                    onPressed: () =>
                        vm.setWorkspaceView(OrchestrationViewMode.boxes),
                    child: Text(
                      t.boxes,
                      style: TextStyle(
                        color: state.mode == OrchestrationViewMode.boxes
                            ? context.colors.accent
                            : null,
                      ),
                    ),
                  ),
                  OutlineButton(
                    onPressed: () =>
                        vm.setWorkspaceView(OrchestrationViewMode.graph),
                    child: Text(
                      t.graph,
                      style: TextStyle(
                        color: state.mode == OrchestrationViewMode.graph
                            ? context.colors.accent
                            : null,
                      ),
                    ),
                  ),
                  PrimaryButton(
                    onPressed: controller.busy || vm.selectedRemoteDisconnected
                        ? null
                        : () => vm.newTerminalTab(
                            cwd: vm.projectRootOf(widget.session.projectId)!,
                            workspaceId: widget.session.projectId,
                          ),
                    child: Text(tr.newTerminal),
                  ),
                  IconButton.ghost(
                    icon: const Icon(Icons.refresh, size: 17),
                    onPressed: () async {
                      await controller.load();
                      await _refresh();
                    },
                  ),
                  IconButton.ghost(
                    icon: const Icon(Icons.settings_outlined, size: 17),
                    onPressed: selected == null
                        ? null
                        : () => select(selected.id, configure: true),
                  ),
                ],
              ),
            ),
            if (selected != null && selected.role.trim().isEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(tr.roleMissing, style: context.typo.label),
                    ),
                    const SizedBox(width: 8),
                    OutlineButton(
                      onPressed: () => select(selected.id, configure: true),
                      child: Text(t.configure),
                    ),
                  ],
                ),
              ),
            if (controller.busy) const LinearProgressIndicator(),
            if (controller.error != null || controller.dirty)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(10),
                color: context.colors.panel,
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        controller.error ?? tr.savePending,
                        style: context.typo.label.copyWith(
                          color: context.colors.warn,
                        ),
                      ),
                    ),
                    OutlineButton(
                      onPressed: () => controller.load(),
                      child: Text(tr.reload),
                    ),
                  ],
                ),
              ),
            for (final removed in controller.pendingRemovals.values)
              Padding(
                padding: const EdgeInsets.all(8),
                child: Wrap(
                  spacing: 8,
                  runSpacing: 6,
                  children: [
                    Text(
                      '${removed.box.title}: ${tr.removed}',
                      style: context.typo.label,
                    ),
                    OutlineButton(
                      onPressed: () => controller.resolveRemoval(
                        removed.box.id,
                        close: true,
                      ),
                      child: Text(tr.closeTerminal),
                    ),
                    OutlineButton(
                      onPressed: () => controller.resolveRemoval(
                        removed.box.id,
                        close: false,
                      ),
                      child: Text(tr.restoreDefinition),
                    ),
                  ],
                ),
              ),
            Expanded(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final showInspector = state.inspectorOpen && selected != null;
                  final wide = constraints.maxWidth >= 800;
                  final width = state.inspectorWidth.clamp(
                    280.0,
                    (constraints.maxWidth * .48).clamp(280.0, 520.0),
                  );
                  final overview = IndexedStack(
                    index: state.mode == OrchestrationViewMode.graph ? 1 : 0,
                    children: [
                      WorkspaceBoxList(
                        key: ValueKey('boxes-${widget.session.id}'),
                        entries: entries,
                        boxOrder: state.boxOrder,
                        selectedBoxId: selected?.id,
                        onReorder: (order) => vm.updatePresentation(
                          vm.presentation.copyWith(boxOrder: order),
                        ),
                        onSelect: (id) {
                          select(id);
                          vm.openBoxInTerminals(id);
                        },
                        onOpen: vm.openBoxInTerminals,
                        onConfigure: (id) => select(id, configure: true),
                      ),
                      if (state.mode == OrchestrationViewMode.graph)
                        WorkspaceGraphView(
                          active: widget.active,
                          vm: vm,
                          processMetrics:
                              widget.processMetrics ??
                              context.read<ProcessMetricsProvider>(),
                          embedded: true,
                          selectedBoxId: selected?.id,
                          onSelectBox: select,
                          onExit: () =>
                              vm.setWorkspaceView(OrchestrationViewMode.boxes),
                          onOpenTab: (id) {
                            final box = vm.graphBoxForTab(id);
                            if (box != null) vm.openBoxInTerminals(box.id);
                          },
                        )
                      else
                        const SizedBox.shrink(),
                    ],
                  );
                  return IgnorePointer(
                    ignoring: controller.busy,
                    child: Stack(
                      children: [
                        Row(
                          children: [
                            Expanded(child: overview),
                            if (showInspector && wide) ...[
                              GestureDetector(
                                behavior: HitTestBehavior.opaque,
                                onHorizontalDragUpdate: (d) =>
                                    vm.updatePresentation(
                                      vm.presentation.copyWith(
                                        inspectorWidth:
                                            (vm.presentation.inspectorWidth -
                                                    d.delta.dx)
                                                .clamp(280.0, 520.0),
                                      ),
                                    ),
                                child: SizedBox(
                                  width: 5,
                                  child: ColoredBox(
                                    color: context.colors.border,
                                  ),
                                ),
                              ),
                              SizedBox(width: width, child: inspector()),
                            ],
                          ],
                        ),
                        if (showInspector && !wide)
                          Positioned.fill(
                            child: Stack(
                              children: [
                                Positioned.fill(
                                  child: GestureDetector(
                                    onTap: () => vm.updatePresentation(
                                      state.copyWith(inspectorOpen: false),
                                    ),
                                    child: ColoredBox(
                                      color: context.colors.scrim,
                                    ),
                                  ),
                                ),
                                Align(
                                  alignment: Alignment.centerRight,
                                  child: SizedBox(
                                    width: constraints.maxWidth
                                        .clamp(0, 360)
                                        .toDouble(),
                                    child: inspector(),
                                  ),
                                ),
                              ],
                            ),
                          ),
                      ],
                    ),
                  );
                },
              ),
            ),
          ],
        );
      },
    );
  }
}
