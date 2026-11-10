import 'dart:async';
import '../../../core/domain/entities/harness.dart';
import '../../../core/domain/result.dart';
import '../../../core/ui/widgets/app_menu.dart';
import '../../../core/ui/widgets/app_tooltip.dart';
import '../../../core/ui/widgets/hover_tap.dart';
import '../services/orchestration_live_sessions.dart';
import 'package:flutter_modular/flutter_modular.dart';
import 'package:flutter/services.dart' show LogicalKeyboardKey;
import 'package:shadcn_flutter/shadcn_flutter.dart';
import 'package:path/path.dart' as path;
import '../../domain/entities/workspace_graph.dart';
import '../../domain/entities/orchestration_presentation.dart';
import '../../domain/contracts/process_metrics_provider.dart';
import '../services/graph_telemetry_service.dart';
import '../session/orchestration_session.dart';
import '../session/terminal_session.dart';
import '../states/pane_node.dart';
import 'orchestration_document_area.dart';
import 'pane_divider.dart';
import '../../../core/ui/themes/themes.dart';
import '../../../../i18n/strings.g.dart';
import 'workspace_box_list.dart';
import 'workspace_box_inspector.dart';
import 'workspace_graph_view.dart';

import 'package:cockpit/app/core/utils/text_clipboard.dart';

/// A document owns its overview (list or graph) and a terminal that appears
/// only while a definition is selected. No toolbar: the file path, the legend,
/// reload and the List|Graph switch live in the footer.
class OrchestrationView extends StatefulWidget {
  const OrchestrationView({
    super.key,
    required this.session,
    required this.active,
    this.focused = false,
    this.processMetrics,
    this.displayPath,
  });
  final OrchestrationSession session;
  final bool active;
  final bool focused;
  final ProcessMetricsProvider? processMetrics;

  /// Path shown in the footer (relative to the workspace when inside it).
  final String? displayPath;
  @override
  State<OrchestrationView> createState() => _OrchestrationViewState();
}

class _OrchestrationViewState extends State<OrchestrationView> {
  final Map<GraphTelemetryKey, GraphTelemetrySnapshot> _metrics = {};
  Timer? _timer;
  bool _refreshing = false;
  bool _dialogOpen = false;
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
      sources: widget.active
          ? [widget.session.context, widget.session.terminals, widget.session]
          : const [],
      sessionState: () => widget.active
          ? [
              for (final t in widget.session.terminals.sessions.values)
                (
                  t.id,
                  t.status,
                  t.activeHarness,
                  GraphTelemetryService.keyFor(t),
                  t.hasExited,
                  t.unseenFinish,
                  t.displayTitle,
                ),
            ]
          : const [],
      schedule: (callback) =>
          WidgetsBinding.instance.scheduleFrameCallback((_) => callback()),
      sessions: () =>
          widget.active ? widget.session.terminals.sessions.values : const [],
    );
  }

  @override
  void didUpdateWidget(covariant OrchestrationView oldWidget) {
    super.didUpdateWidget(oldWidget);
    widget.session.setPresentationActive(
      widget.active && widget.focused,
      visible: widget.active,
    );
    if (oldWidget.session != widget.session ||
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
    widget.session.setPresentationActive(
      widget.active && widget.focused,
      visible: widget.active,
    );
    _timer = Timer.periodic(const Duration(seconds: 10), (_) => _refresh());
    WidgetsBinding.instance.addPostFrameCallback((_) => _refresh());
  }

  Future<void> _refresh() async {
    if (_refreshing || !mounted || !widget.active) return;
    _refreshing = true;
    final documentSession = widget.session;
    final documentPath = documentSession.path;
    try {
      final next = <GraphTelemetryKey, GraphTelemetrySnapshot>{};
      for (final box in documentSession.controller.graphBoxes) {
        final session = documentSession.context.session(box.tabId ?? '');
        if (session == null) continue;
        final key = GraphTelemetryService.keyFor(session);
        final value = await const GraphTelemetryService().snapshot(session);
        if (identical(documentSession.context.session(session.id), session) &&
            key == GraphTelemetryService.keyFor(session)) {
          next[key] = value;
        }
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
    final s = widget.session.context.session(box.tabId ?? '');
    final t = s is TerminalSession ? s : null;
    return WorkspaceBoxEntry(
      box: box,
      status: widget.session.context.selectedRemoteDisconnected
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
      contextPercent: t == null || t.hasExited || t.activeHarness == null
          ? null
          : _metrics[GraphTelemetryService.keyFor(t)]?.contextPercent,
    );
  }

  /// The configuration is a centered dialog; `inspectorOpen` in the
  /// presentation is the request, consumed here exactly once.
  void _maybeOpenDialog(GraphBox selected) {
    if (_dialogOpen) return;
    _dialogOpen = true;
    final vm = widget.session.context;
    final session = widget.session;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) {
        _dialogOpen = false;
        return;
      }
      await showDialog<void>(
        context: context,
        builder: (dialogContext) => ListenableBuilder(
          listenable: vm,
          builder: (dialogContext, _) {
            final box =
                vm.graphBoxes.where((b) => b.id == selected.id).firstOrNull ??
                selected;
            return Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(
                  maxWidth: 560,
                  maxHeight: 720,
                ),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(10),
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        border: Border.all(color: dialogContext.colors.border),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: WorkspaceBoxInspector(
                        key: ValueKey('inspector-${session.path}-${box.id}'),
                        vm: vm,
                        box: box,
                        entry: _entry(box),
                        projectId: session.projectId,
                        directory:
                            session.controller.document?.boxes
                                .where((b) => b.box.id == box.id)
                                .firstOrNull
                                ?.directory ??
                            '.',
                        onSuggestRole: () => vm.suggestRole(box.id),
                        onSave: (name, role, tool, model, directory) =>
                            vm.configureBox(
                              box.id,
                              title: name,
                              role: role,
                              harness: tool,
                              model: model,
                              directory: directory,
                            ),
                        onClose: () => Navigator.of(dialogContext).pop(),
                      ),
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      );
      _dialogOpen = false;
      if (!vm.disposed) vm.closeInspector();
    });
  }

  @override
  Widget build(BuildContext context) {
    final vm = widget.session.context;
    return ListenableBuilder(
      listenable: _liveSessions,
      builder: (context, _) {
        final controller = widget.session.controller;
        controller.startPolling();
        final tr = context.t.orchestration;
        final state = vm.presentation;
        final selected = vm.selectedWorkspaceBox;
        if (state.inspectorOpen && selected != null) _maybeOpenDialog(selected);
        void select(String id, {bool configure = false}) =>
            vm.selectWorkspaceBox(id, configure: configure);
        final entries = [for (final b in vm.graphBoxes) _entry(b)];
        final open = selected != null;
        return Column(
          children: [
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
                        onDeselect: vm.clearSelection,
                        onNewTerminal:
                            controller.busy || vm.selectedRemoteDisconnected
                            ? null
                            : () => vm.newTerminal(),
                      ),
                      WorkspaceGraphView(
                        active:
                            widget.active &&
                            state.mode == OrchestrationViewMode.graph,
                        vm: vm,
                        processMetrics:
                            widget.processMetrics ??
                            context.read<ProcessMetricsProvider>(),
                        embedded: true,
                        selectedBoxId: selected?.id,
                        onSelectBox: (id) {
                          select(id);
                          vm.revealBox(id, focus: false);
                        },
                        onDeselect: vm.clearSelection,
                        onNewTerminal:
                            controller.busy || vm.selectedRemoteDisconnected
                            ? null
                            : () => vm.newTerminal(),
                        onExit: () =>
                            vm.setWorkspaceView(OrchestrationViewMode.boxes),
                        onOpenTab: (id) {
                          final box = vm.graphBoxForTab(id);
                          if (box != null) vm.openBoxInTerminals(box.id);
                        },
                      ),
                    ],
                  );
                  final terminalHeight = open
                      ? (constraints.maxHeight - 6).clamp(
                              0.0,
                              double.infinity,
                            ) *
                            state.terminalFraction
                      : 0.0;
                  return IgnorePointer(
                    ignoring: controller.busy,
                    child: Column(
                      children: [
                        Expanded(
                          // Esc here (focus outside the terminal) deselects;
                          // inside the terminal Esc belongs to the PTY.
                          child: CallbackShortcuts(
                            bindings: {
                              const SingleActivator(LogicalKeyboardKey.escape):
                                  vm.clearSelection,
                            },
                            child: Focus(
                              child: Listener(
                                behavior: HitTestBehavior.translucent,
                                onPointerDown: (_) =>
                                    widget.session.terminals.releaseKeyboard(),
                                child: overview,
                              ),
                            ),
                          ),
                        ),
                        if (open) ...[
                          SizedBox(
                            height: 6,
                            child: PaneDivider(
                              dir: SplitDir.horizontal,
                              onDelta: (delta) {
                                final fraction =
                                    (vm.presentation.terminalFraction -
                                            delta / constraints.maxHeight)
                                        .clamp(.15, .85);
                                vm.updatePresentation(
                                  state.mode == OrchestrationViewMode.boxes
                                      ? vm.presentation.copyWith(
                                          boxesTerminalFraction: fraction,
                                        )
                                      : vm.presentation.copyWith(
                                          graphTerminalFraction: fraction,
                                        ),
                                );
                              },
                            ),
                          ),
                          SizedBox(
                            height: terminalHeight,
                            child: ColoredBox(
                              color: context.colors.panel,
                              child: Center(
                                // On wide screens the terminal does not run
                                // edge to edge; below the cap it fills 100%.
                                child: ConstrainedBox(
                                  constraints: const BoxConstraints(
                                    maxWidth: 1100,
                                  ),
                                  child: _TerminalBox(
                                    session: widget.session,
                                    box: selected,
                                    entry: _entry(selected),
                                    active: widget.active,
                                    focused: widget.focused,
                                    onConfigure: () =>
                                        select(selected.id, configure: true),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  );
                },
              ),
            ),
            _Footer(
              path: widget.displayPath ?? path.basename(widget.session.path),
              selectedTitle: selected?.title,
              mode: state.mode,
              onMode: vm.setWorkspaceView,
              onReload: () async {
                await controller.load();
                await _refresh();
              },
            ),
          ],
        );
      },
    );
  }
}

/// Header strip (status, name, actions, close) above the owned terminal.
class _TerminalBox extends StatelessWidget {
  const _TerminalBox({
    required this.session,
    required this.box,
    required this.entry,
    required this.active,
    required this.focused,
    required this.onConfigure,
  });
  final OrchestrationSession session;
  final GraphBox box;
  final WorkspaceBoxEntry entry;
  final bool active, focused;
  final VoidCallback onConfigure;

  Future<void> _actions(BuildContext anchor) async {
    final vm = session.context;
    final t = anchor.t.workspaceView;
    final tr = anchor.t.orchestration;
    final terminal = vm.session(box.tabId ?? '');
    final alive = terminal != null && !terminal.hasExited;
    final agent = alive && terminal.activeHarness != null;
    final canControl =
        alive && !terminal.isWorking && !vm.selectedRemoteDisconnected;
    final value = await showAppMenu<String>(
      anchor,
      items: [
        AppMenuItem(
          value: 'configure',
          label: t.configure,
          icon: Icons.settings_outlined,
        ),
        if (box.role.isNotEmpty)
          AppMenuItem(value: 'copyRole', label: t.copyRole, icon: Icons.copy),
        const AppMenuItem.divider(),
        if (!alive)
          AppMenuItem(
            value: 'shell',
            label: t.startShell,
            icon: Icons.terminal,
            enabled: !vm.selectedRemoteDisconnected,
          ),
        if (!agent)
          AppMenuItem(
            value: 'cli',
            label: t.startCli,
            icon: Icons.play_arrow_outlined,
            enabled: !vm.selectedRemoteDisconnected && box.harness.isNotEmpty,
          )
        else ...[
          AppMenuItem(
            value: 'compact',
            label: t.compact,
            icon: Icons.compress,
            enabled: canControl,
          ),
          AppMenuItem(
            value: 'handoff',
            label: t.handoff,
            icon: Icons.swap_horiz,
            enabled: canControl,
          ),
        ],
        if (alive) ...[
          const AppMenuItem.divider(),
          AppMenuItem(
            value: 'close',
            label: tr.closeTerminal,
            icon: Icons.close,
            danger: true,
            enabled: !session.closing,
          ),
        ],
      ],
    );
    if (!anchor.mounted || value == null) return;
    Future<void> report(Future<Result<String, String>> action) async {
      final result = await action;
      if (result case Failure(:final error) when !session.disposed) {
        session.controller.reportError(error);
      }
    }

    switch (value) {
      case 'configure':
        onConfigure();
      case 'copyRole':
        await TextClipboardService.instance.write(
          box.role,
          operation: 'orchestration_view',
        );
      case 'shell':
        await report(vm.openBoxShell(box.id));
      case 'cli':
        await report(vm.relaunchGraphBox(box.id));
      case 'compact':
        (terminal as TerminalSession).insertText('/compact\r');
      case 'handoff':
        await _handoff(anchor);
      case 'close':
        if (box.tabId case final id?) await session.closeTerminal(id);
    }
  }

  Future<void> _handoff(BuildContext context) async {
    final vm = session.context;
    final t = context.t.workspaceView;
    final controller = TextEditingController(text: '${box.role}\n\n');
    String? summary;
    try {
      summary = await showDialog<String>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: Text(t.handoffTitle),
          content: SizedBox(
            width: 440,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(t.handoffHelp),
                const SizedBox(height: 12),
                TextField(controller: controller, maxLines: 7),
              ],
            ),
          ),
          actions: [
            OutlineButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: Text(t.cancel),
            ),
            PrimaryButton(
              onPressed: () =>
                  Navigator.of(dialogContext).pop(controller.text.trim()),
              child: Text(t.handoff),
            ),
          ],
        ),
      );
    } finally {
      controller.dispose();
    }
    if (summary == null || summary.isEmpty || session.disposed) return;
    final result = await vm.startGraphHandoff(box.id);
    switch (result) {
      case Success():
        await TextClipboardService.instance.write(
          summary,
          operation: 'orchestration_view',
        );
      case Failure(:final error):
        if (!session.disposed) session.controller.reportError(error);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final t = context.t.workspaceView;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.bg,
        border: Border.symmetric(vertical: BorderSide(color: colors.border)),
      ),
      child: Column(
        children: [
          Container(
            height: 28,
            padding: const EdgeInsets.only(left: 12, right: 4),
            decoration: BoxDecoration(
              border: Border(bottom: BorderSide(color: colors.border)),
            ),
            child: Row(
              children: [
                Icon(
                  Icons.circle,
                  size: 7,
                  color: workspaceStatusColor(context, entry.status),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    box.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: context.typo.label.copyWith(color: colors.text3),
                  ),
                ),
                if (entry.tool.isNotEmpty)
                  Text(
                    box.model.isEmpty
                        ? entry.tool
                        : '${entry.tool} · ${box.model}',
                    style: context.typo.label.copyWith(color: colors.text3),
                  ),
                const SizedBox(width: 4),
                Builder(
                  builder: (anchor) => AppTooltip(
                    message: t.actions,
                    child: IconButton.ghost(
                      icon: const Icon(Icons.more_horiz, size: 15),
                      onPressed: () => _actions(anchor),
                    ),
                  ),
                ),
                AppTooltip(
                  message: '${t.closeTerminal} (Esc)',
                  child: IconButton.ghost(
                    key: ValueKey('terminal-close-${session.id}'),
                    icon: const Icon(Icons.close, size: 15),
                    onPressed: session.context.clearSelection,
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: OrchestrationDocumentArea(
              session: session,
              active: active,
              focused: focused,
            ),
          ),
        ],
      ),
    );
  }
}

class _Footer extends StatelessWidget {
  const _Footer({
    required this.path,
    required this.selectedTitle,
    required this.mode,
    required this.onMode,
    required this.onReload,
  });
  final String path;
  final String? selectedTitle;
  final OrchestrationViewMode mode;
  final ValueChanged<OrchestrationViewMode> onMode;
  final VoidCallback onReload;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final typo = context.typo;
    final t = context.t.workspaceView;
    final g = context.t.graphView;
    final legend = [
      '┄→ ${g.planned}',
      '━→ ${g.observed}',
      '┈→ ${g.temporary}',
      '',
      '● ${g.working}   ◐ ${g.waiting}   ○ ${g.idle}   × ${g.ended}',
    ].join('\n');
    final muted = typo.label.copyWith(fontSize: 10.5, color: colors.text3);
    return Container(
      height: 26,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: colors.border)),
      ),
      child: Row(
        children: [
          // Flexible + Spacer dividiriam a largura em partes iguais e o
          // segmentado ficaria no meio; o lado esquerdo precisa ser Expanded.
          Expanded(
            child: Row(
              children: [
                Flexible(
                  child: Text(
                    path,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: muted,
                  ),
                ),
                if (selectedTitle case final title?) ...[
                  const SizedBox(width: 8),
                  Flexible(
                    child: Text(
                      '· $title',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: muted,
                    ),
                  ),
                ],
              ],
            ),
          ),
          if (mode == OrchestrationViewMode.graph)
            AppTooltip(
              message: legend,
              child: HoverTap(
                onTap: () {},
                borderRadius: const BorderRadius.all(Radius.circular(4)),
                padding: const EdgeInsets.symmetric(horizontal: 6),
                child: Text(
                  '?',
                  semanticsLabel: t.legend,
                  style: typo.label.copyWith(color: colors.text2),
                ),
              ),
            ),
          AppTooltip(
            message: context.t.orchestration.reload,
            child: HoverTap(
              onTap: onReload,
              borderRadius: const BorderRadius.all(Radius.circular(4)),
              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
              child: Icon(Icons.refresh, size: 13, color: colors.text2),
            ),
          ),
          const SizedBox(width: 6),
          _Toggle(
            label: t.boxes,
            active: mode == OrchestrationViewMode.boxes,
            onTap: () => onMode(OrchestrationViewMode.boxes),
          ),
          _Toggle(
            label: t.graph,
            active: mode == OrchestrationViewMode.graph,
            onTap: () => onMode(OrchestrationViewMode.graph),
          ),
        ],
      ),
    );
  }
}

class _Toggle extends StatelessWidget {
  const _Toggle({
    required this.label,
    required this.active,
    required this.onTap,
  });
  final String label;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return HoverTap(
      onTap: onTap,
      color: active ? colors.panel3 : null,
      borderRadius: const BorderRadius.all(Radius.circular(4)),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      child: Text(
        label,
        style: context.typo.label.copyWith(
          fontSize: 10.5,
          color: active ? colors.text : colors.text4,
        ),
      ),
    );
  }
}
