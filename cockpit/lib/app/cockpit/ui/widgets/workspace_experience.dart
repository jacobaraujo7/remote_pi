import 'package:flutter/rendering.dart' show RenderCustomMultiChildLayoutBox;
import 'dart:async';
import 'dart:math' as math;
import 'package:shadcn_flutter/shadcn_flutter.dart';
import '../../domain/contracts/process_metrics_provider.dart';
import '../../domain/entities/workspace_graph.dart';
import '../../domain/entities/workspace_presentation.dart';
import '../viewmodels/cockpit_viewmodel.dart';
import '../session/terminal_session.dart';
import '../services/graph_telemetry_service.dart';
import '../../../core/ui/themes/themes.dart';
import '../../../../i18n/strings.g.dart';
import 'workspace_box_list.dart';
import 'workspace_box_inspector.dart';
import 'workspace_graph_view.dart';

class WorkspaceExperience extends StatefulWidget {
  const WorkspaceExperience({
    super.key,
    required this.vm,
    required this.processMetrics,
    required this.terminals,
  });
  final CockpitViewModel vm;
  final ProcessMetricsProvider processMetrics;
  final Widget terminals;
  @override
  State<WorkspaceExperience> createState() => _WorkspaceExperienceState();
}

class _WorkspaceExperienceState extends State<WorkspaceExperience> {
  final Map<String, GraphTelemetrySnapshot> _metrics = {};
  final Set<String> _reading = {};
  Timer? _timer;
  String? _lastProject;
  WorkspaceViewMode? _lastMode;
  bool _lastInspector = false;
  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(
      const Duration(seconds: 10),
      (_) => _refreshMetrics(),
    );
    WidgetsBinding.instance.addPostFrameCallback((_) => _refreshMetrics());
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _refreshMetrics() async {
    if (widget.vm.presentation.mode == WorkspaceViewMode.terminals &&
        !widget.vm.presentation.inspectorOpen) {
      return;
    }
    for (final box in widget.vm.graphBoxes) {
      final tab = widget.vm.session(box.tabId ?? '');
      if (tab is! TerminalSession || tab.hasExited || !_reading.add(tab.id)) {
        continue;
      }
      try {
        final metric = await const GraphTelemetryService().snapshot(tab);
        if (!mounted) return;
        setState(() => _metrics[tab.id] = metric);
      } on Object {
        if (mounted) setState(() => _metrics.remove(tab.id));
      } finally {
        _reading.remove(tab.id);
      }
    }
    final liveIds = widget.vm.allSessions.map((s) => s.id).toSet();
    _metrics.removeWhere((id, _) => !liveIds.contains(id));
  }

  WorkspaceBoxEntry _entry(GraphBox box) {
    final vm = widget.vm;
    final tab = vm.session(box.tabId ?? '');
    final terminal = tab is TerminalSession ? tab : null;
    final status = vm.selectedRemoteDisconnected
        ? WorkspaceBoxStatus.disconnected
        : terminal == null || terminal.hasExited
        ? WorkspaceBoxStatus.closed
        : terminal.activeHarness == null
        ? WorkspaceBoxStatus.shell
        : switch (terminal.status) {
            TerminalStatus.working => WorkspaceBoxStatus.working,
            TerminalStatus.waiting => WorkspaceBoxStatus.waiting,
            TerminalStatus.idle => WorkspaceBoxStatus.idle,
          };
    return WorkspaceBoxEntry(
      box: box,
      status: status,
      tool: terminal?.activeHarness?.name == 'claudeCode'
          ? 'claude'
          : terminal?.activeHarness?.name ?? box.harness,
      contextPercent: terminal == null || terminal.hasExited
          ? null
          : _metrics[terminal.id]?.contextPercent,
    );
  }

  @override
  Widget build(BuildContext context) {
    final vm = widget.vm;
    return ListenableBuilder(
      listenable: Listenable.merge([
        vm,
        ...vm.allSessions.whereType<TerminalSession>(),
      ]),
      builder: (context, _) {
        final state = vm.presentation;
        final projectId = vm.selectedProjectId;
        if (_lastProject != projectId ||
            _lastMode != state.mode ||
            _lastInspector != state.inspectorOpen) {
          _lastProject = projectId;
          _lastMode = state.mode;
          _lastInspector = state.inspectorOpen;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) _refreshMetrics();
          });
        }
        final selected = vm.selectedWorkspaceBox;
        final preview =
            state.mode != WorkspaceViewMode.terminals && projectId != null;
        final hasTerminal =
            projectId != null && vm.previewTabFor(projectId) != null;
        final inspector = state.inspectorOpen && selected != null;
        final t = context.t.workspaceView;
        return CustomMultiChildLayout(
          delegate: _WorkspaceLayout(
            preview: preview,
            inspector: inspector,
            inspectorWidth: state.inspectorWidth,
            previewFraction: state.previewFraction,
          ),
          children: [
            LayoutId(
              id: 'overview',
              child: Offstage(
                offstage: !preview,
                child:
                    state.mode == WorkspaceViewMode.graph && projectId != null
                    ? WorkspaceGraphView(
                        key: ValueKey('workspace-graph-$projectId'),
                        vm: vm,
                        processMetrics: widget.processMetrics,
                        embedded: true,
                        selectedBoxId: selected?.id,
                        onSelectBox: (id) {
                          FocusManager.instance.primaryFocus?.unfocus();
                          vm.selectWorkspaceBox(id);
                        },
                        onExit: () =>
                            vm.setWorkspaceView(WorkspaceViewMode.terminals),
                        onOpenTab: (tabId) {
                          final box = vm.graphBoxForTab(tabId);
                          if (box != null) vm.openBoxInTerminals(box.id);
                        },
                      )
                    : WorkspaceBoxList(
                        key: ValueKey('workspace-boxes-$projectId'),
                        boxOrder: state.boxOrder,
                        onReorder: (order) => vm.updatePresentation(
                          vm.presentation.copyWith(boxOrder: order),
                        ),
                        entries: [for (final box in vm.graphBoxes) _entry(box)],
                        selectedBoxId: selected?.id,
                        onSelect: (id) {
                          FocusManager.instance.primaryFocus?.unfocus();
                          vm.selectWorkspaceBox(id);
                          _refreshMetrics();
                        },
                        onOpen: vm.openBoxInTerminals,
                        onConfigure: (id) =>
                            vm.selectWorkspaceBox(id, configure: true),
                      ),
              ),
            ),
            // This child and its parent remain identical in every mode.
            LayoutId(id: 'terminals', child: widget.terminals),
            LayoutId(
              id: 'empty',
              child: Offstage(
                offstage: !preview || hasTerminal,
                child: ColoredBox(
                  color: context.colors.bg,
                  child: Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          selected == null ? t.selectBox : t.noSession,
                          style: context.typo.body.copyWith(
                            color: context.colors.text3,
                          ),
                        ),
                        if (selected != null) ...[
                          const SizedBox(height: 12),
                          OutlineButton(
                            onPressed: vm.selectedRemoteDisconnected
                                ? null
                                : () {
                                    vm.openBoxShell(selected.id);
                                    vm.selectWorkspaceBox(selected.id);
                                  },
                            child: Text(t.startShell),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
            ),
            LayoutId(
              id: 'preview-divider',
              child: Offstage(
                offstage: !preview,
                child: _WorkspaceDivider(
                  vertical: false,
                  onDelta: (delta, size) => vm.updatePresentation(
                    state.copyWith(
                      previewFraction:
                          (state.previewFraction -
                                  delta / math.max(1, size.height))
                              .clamp(.20, .80),
                    ),
                  ),
                ),
              ),
            ),
            LayoutId(
              id: 'inspector-barrier',
              child: LayoutBuilder(
                builder: (context, c) => Offstage(
                  offstage: !inspector || c.maxWidth >= 1100,
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () => vm.updatePresentation(
                      state.copyWith(inspectorOpen: false),
                    ),
                    child: ColoredBox(color: context.colors.scrim),
                  ),
                ),
              ),
            ),
            LayoutId(
              id: 'inspector',
              child: Offstage(
                offstage: !inspector,
                child: selected == null
                    ? const SizedBox.shrink()
                    : WorkspaceBoxInspector(
                        key: ValueKey('inspector-${selected.id}'),
                        vm: vm,
                        box: selected,
                        entry: _entry(selected),
                        onClose: () => vm.updatePresentation(
                          state.copyWith(inspectorOpen: false),
                        ),
                      ),
              ),
            ),
            LayoutId(
              id: 'inspector-divider',
              child: Offstage(
                offstage: !inspector,
                child: _WorkspaceDivider(
                  vertical: true,
                  onDelta: (delta, size) => vm.updatePresentation(
                    state.copyWith(
                      inspectorWidth: (state.inspectorWidth - delta).clamp(
                        280,
                        460,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _WorkspaceLayout extends MultiChildLayoutDelegate {
  _WorkspaceLayout({
    required this.preview,
    required this.inspector,
    required this.inspectorWidth,
    required this.previewFraction,
  });
  final bool preview;
  final bool inspector;
  final double inspectorWidth;
  final double previewFraction;
  @override
  void performLayout(Size size) {
    final wide = size.width >= 1100;
    final panelWidth = math.min(inspectorWidth, size.width);
    final width = math.max(
      1.0,
      size.width - (wide && inspector ? panelWidth : 0),
    );
    final height = math.max(1.0, size.height);
    final top = preview ? height * (1 - previewFraction) : 0.0;
    void place(String id, Rect rect) {
      layoutChild(id, BoxConstraints.tight(rect.size));
      positionChild(id, rect.topLeft);
    }

    place('overview', Rect.fromLTWH(0, 0, width, preview ? top : height));
    place('terminals', Rect.fromLTWH(0, top, width, height - top));
    place('empty', Rect.fromLTWH(0, top, width, height - top));
    place('preview-divider', Rect.fromLTWH(0, math.max(0, top - 4), width, 8));
    place('inspector-barrier', Offset.zero & Size(size.width, height));
    place(
      'inspector',
      Rect.fromLTWH(size.width - panelWidth, 0, panelWidth, height),
    );
    place(
      'inspector-divider',
      Rect.fromLTWH(math.max(0, size.width - panelWidth - 4), 0, 8, height),
    );
  }

  @override
  bool shouldRelayout(_WorkspaceLayout old) =>
      old.preview != preview ||
      old.inspector != inspector ||
      old.inspectorWidth != inspectorWidth ||
      old.previewFraction != previewFraction;
}

class _WorkspaceDivider extends StatelessWidget {
  const _WorkspaceDivider({required this.vertical, required this.onDelta});
  final bool vertical;
  final void Function(double delta, Size parent) onDelta;
  @override
  Widget build(BuildContext context) => MouseRegion(
    cursor: vertical
        ? SystemMouseCursors.resizeLeftRight
        : SystemMouseCursors.resizeUpDown,
    child: GestureDetector(
      behavior: HitTestBehavior.opaque,
      onPanUpdate: (event) {
        final parent = context
            .findAncestorRenderObjectOfType<RenderCustomMultiChildLayoutBox>();
        if (parent != null && parent.hasSize) {
          onDelta(vertical ? event.delta.dx : event.delta.dy, parent.size);
        }
      },
      child: Center(
        child: Container(
          width: vertical ? 1 : null,
          height: vertical ? null : 1,
          color: context.colors.border2,
        ),
      ),
    ),
  );
}
