import 'dart:async';

import 'graph_box_editor.dart';
import 'workspace_box_list.dart';
import '../../../core/domain/entities/harness.dart';

import 'package:cockpit/app/cockpit/domain/entities/workspace_graph.dart';
import 'package:cockpit/app/cockpit/domain/contracts/process_metrics_provider.dart';
import 'package:cockpit/app/cockpit/domain/entities/process_metrics_snapshot.dart';
import 'package:cockpit/app/cockpit/ui/session/pane_item.dart';
import 'package:cockpit/app/cockpit/ui/session/terminal_session.dart';
import 'package:cockpit/app/cockpit/ui/viewmodels/workspace_graph_context.dart';
import 'package:cockpit/app/cockpit/ui/services/graph_telemetry_service.dart';
import 'package:cockpit/app/cockpit/ui/services/graph_process_metrics_service.dart';
import 'package:cockpit/app/cockpit/ui/widgets/confirm_dialog.dart';
import 'package:cockpit/app/core/ui/widgets/app_tooltip.dart';
import 'package:cockpit/app/core/domain/result.dart';
import 'package:cockpit/app/core/ui/themes/themes.dart';
import 'package:cockpit/app/core/ui/widgets/window_controls.dart';
import 'package:cockpit/i18n/strings.g.dart';
import 'package:flutter/services.dart' show Clipboard, ClipboardData;
import 'package:shadcn_flutter/shadcn_flutter.dart';

/// Canvas for the boxes supplied by its context. Terminal presentation is
/// owned by the surrounding multiplexer, never created by this graph.
class WorkspaceGraphView extends StatefulWidget {
  const WorkspaceGraphView({
    super.key,
    required this.vm,
    required this.processMetrics,
    required this.onExit,
    required this.onOpenTab,
    this.active = true,
    this.embedded = false,
    this.selectedBoxId,
    this.onSelectBox,
  });

  final bool active;
  final bool embedded;
  final String? selectedBoxId;
  final ValueChanged<String>? onSelectBox;
  final WorkspaceGraphContext vm;
  final ProcessMetricsProvider processMetrics;
  final VoidCallback onExit;
  final void Function(String tabId) onOpenTab;

  @override
  State<WorkspaceGraphView> createState() => _WorkspaceGraphViewState();
}

class _WorkspaceGraphViewState extends State<WorkspaceGraphView> {
  final TransformationController _transform = TransformationController();
  final ValueNotifier<int> _graphRevision = ValueNotifier(0);
  bool _editingText = false;
  final Map<GraphTelemetryKey, Future<GraphTelemetrySnapshot>> _telemetry = {};
  final Map<String, Offset> _dragPositions = {};
  final Map<String, Offset> _subagentPositions = {};
  final Map<GraphTelemetryKey, GraphTelemetrySnapshot> _latestTelemetry = {};
  final Map<String, Future<ProcessMetricsSnapshot>> _processTelemetry = {};
  late GraphProcessMetricsService _processMetricsService;
  Timer? _telemetryTimer;
  String? _selected;
  String? _linkFrom;
  bool _linkMode = false;

  static const Size _canvasSize = Size(2400, 1600);
  static const Size _boxSize = Size(230, 142);

  @override
  void initState() {
    super.initState();
    if (!widget.embedded) widget.vm.addListener(_onVmChanged);
    _processMetricsService = GraphProcessMetricsService(
      hostProvider: widget.processMetrics,
    );
    _telemetryTimer = Timer.periodic(const Duration(seconds: 10), (_) {
      if (!mounted || !widget.active || _editingText) return;
      setState(() {
        _telemetry.clear();
        _latestTelemetry.clear();
        _processTelemetry.clear();
      });
    });
  }

  @override
  void didUpdateWidget(covariant WorkspaceGraphView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.vm != widget.vm || oldWidget.embedded != widget.embedded) {
      oldWidget.vm.removeListener(_onVmChanged);
      if (!widget.embedded) widget.vm.addListener(_onVmChanged);
      _graphRevision.value++;
      _telemetry.clear();
      _latestTelemetry.clear();
      _processTelemetry.clear();
    }
    if (!oldWidget.active && widget.active) {
      _telemetry.clear();
      _latestTelemetry.clear();
      _processTelemetry.clear();
    }
    if (oldWidget.processMetrics != widget.processMetrics) {
      _processMetricsService = GraphProcessMetricsService(
        hostProvider: widget.processMetrics,
      );
      _processTelemetry.clear();
    }
  }

  @override
  void dispose() {
    _telemetryTimer?.cancel();
    widget.vm.removeListener(_onVmChanged);
    _graphRevision.dispose();
    _transform.dispose();
    super.dispose();
  }

  Future<GraphTelemetrySnapshot>? _telemetryForBox(GraphBox box) {
    final context = widget.vm;
    final pane = context.session(box.tabId ?? '');
    if (pane == null) return null;
    final key = GraphTelemetryService.keyFor(pane);
    _telemetry.removeWhere((old, _) => old.pane.id == pane.id && old != key);
    _latestTelemetry.removeWhere(
      (old, _) => old.pane.id == pane.id && old != key,
    );
    return _telemetry.putIfAbsent(key, () async {
      final result = await const GraphTelemetryService().snapshot(pane);
      if (mounted &&
          widget.vm == context &&
          identical(context.session(pane.id), pane) &&
          key == GraphTelemetryService.keyFor(pane)) {
        _latestTelemetry[key] = result;
        if (!_editingText) setState(() {});
      }
      return result;
    });
  }

  GraphTelemetrySnapshot? _latestFor(String? tabId) {
    final pane = tabId == null ? null : widget.vm.session(tabId);
    return pane == null
        ? null
        : _latestTelemetry[GraphTelemetryService.keyFor(pane)];
  }

  void _onVmChanged() {
    if (widget.active && !widget.embedded && !_editingText) {
      _graphRevision.value++;
    }
  }

  List<GraphBox> _visibleBoxes(WorkspaceGraphContext vm) => vm.graphBoxes;

  void _dragBox(GraphBox box, Offset delta) {
    final current = _dragPositions[box.id] ?? box.position;
    final next = current + delta / _transform.value.getMaxScaleOnAxis();
    setState(() {
      _dragPositions[box.id] = Offset(
        next.dx.clamp(0.0, _canvasSize.width - _boxSize.width),
        next.dy.clamp(0.0, _canvasSize.height - _boxSize.height),
      );
    });
  }

  void _finishBoxDrag(GraphBox box) {
    final position = _dragPositions.remove(box.id);
    if (position == null) return;
    final session = widget.vm.session(box.tabId ?? '');
    if (session == null) {
      widget.vm.moveGraphBox(box.id, position);
      return;
    }
    final saved = widget.vm.graphBoxForTab(session.id);
    if (saved == null) {
      widget.vm.ensureGraphBoxForTab(session, position);
    } else {
      widget.vm.moveGraphBox(saved.id, position);
    }
  }

  void _select(GraphBox box) {
    if (_linkMode) {
      final from = _linkFrom;
      if (from == null) {
        setState(() => _linkFrom = box.id);
      } else if (from != box.id) {
        // Planned edges belong to document definitions, even without a shell.
        widget.vm.addGraphLink(from, box.id);
        setState(() {
          _linkFrom = null;
          _linkMode = false;
          _selected = box.id;
        });
        widget.onSelectBox?.call(box.id);
      }
      return;
    }
    setState(() => _selected = box.id);
    widget.onSelectBox?.call(box.id);
  }

  Future<void> _createBox() async {
    final request = await showDialog<_GraphBoxDraft>(
      context: context,
      barrierColor: context.colors.scrim,
      builder: (context) => const _CreateBoxDialog(),
    );
    if (!mounted || request == null) return;
    final count = widget.vm.graphBoxes.length;
    final created = await widget.vm.createGraphBox(
      title: request.title,
      role: request.role,
      harness: request.harness,
      model: request.model,
      position: Offset(140 + (count % 5) * 270.0, 160 + (count ~/ 5) * 190.0),
    );
    if (!mounted) return;
    if (created case Failure(:final error)) {
      await showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Não foi possível criar o box'),
          content: Text(error),
          actions: [
            PrimaryButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('OK'),
            ),
          ],
        ),
      );
    } else if (created case Success(:final value)) {
      final box = widget.vm.graphBoxForTab(value);
      if (box != null) setState(() => _selected = box.id);
    }
  }

  Future<String?> _editText(String title, String initial) async {
    final controller = TextEditingController(text: initial);
    _editingText = true;
    try {
      return await showDialog<String>(
        context: context,
        barrierColor: context.colors.scrim,
        builder: (context) => AlertDialog(
          title: Text(title),
          content: SizedBox(
            width: 440,
            child: TextField(controller: controller, maxLines: 6),
          ),
          actions: [
            OutlineButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Cancelar'),
            ),
            PrimaryButton(
              onPressed: () =>
                  Navigator.of(context).pop(controller.text.trim()),
              child: const Text('Confirmar'),
            ),
          ],
        ),
      );
    } finally {
      _editingText = false;
      if (mounted) _graphRevision.value++;
      controller.dispose();
    }
  }

  Future<GraphBoxEditDraft?> _editBox(
    GraphBox box, {
    required bool canStart,
  }) async {
    _editingText = true;
    try {
      return await showGraphBoxEditor(context, box, canStart: canStart);
    } finally {
      _editingText = false;
      if (mounted) _graphRevision.value++;
    }
  }

  Future<void> _showGraphError(String message) => showDialog<void>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Não foi possível configurar o box'),
      content: Text(message),
      actions: [
        PrimaryButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('OK'),
        ),
      ],
    ),
  );
  Future<void> _compact(GraphBox box) async {
    final session = widget.vm.session(box.tabId ?? '');
    if (session is TerminalSession &&
        session.activeHarness != null &&
        !session.isWorking) {
      session.insertText('/compact\r');
    }
    if (mounted) setState(_telemetry.clear);
  }

  Future<void> _handoff(GraphBox box) async {
    final session = widget.vm.session(box.tabId ?? '');
    if (session == null || session.isWorking) return;
    final brief = await _editText(
      'Resumo para a nova sessão',
      'Função: ${box.role}\n\nEstado atual e próximos passos:\n',
    );
    if (!mounted || brief == null || brief.isEmpty) return;
    if (session is TerminalSession) {
      final created = await widget.vm.startGraphHandoff(box.id);
      if (created case Success(:final value)) {
        await Clipboard.setData(ClipboardData(text: brief));
        if (!mounted) return;
        await showInfoDialog(
          context,
          title: 'Nova sessão preparada',
          message:
              'O resumo de handoff foi copiado. Cole no novo terminal quando a ferramenta estiver pronta.',
        );
        if (mounted) widget.onOpenTab(value);
      }
    }
    if (mounted) setState(_telemetry.clear);
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.active) return const SizedBox.shrink();
    final colors = context.colors;
    return ListenableBuilder(
      listenable: _graphRevision,
      builder: (context, _) {
        final selectedBoxId = widget.selectedBoxId ?? _selected;
        final boxes = [
          for (final box in _visibleBoxes(widget.vm))
            if (_dragPositions[box.id] case final Offset position)
              box.copyWith(position: position)
            else
              box,
        ];
        final children = widget.vm.graphSubagents;
        final unresolvedPeers = widget.vm.graphUnresolvedPeers;
        GraphBox? selectedBox;
        for (final box in boxes) {
          if (box.id == selectedBoxId) selectedBox = box;
        }
        final selectedSession = selectedBox == null
            ? null
            : widget.vm.session(selectedBox.tabId ?? '');
        final positions = {for (final box in boxes) box.id: box.position};
        final temporaryLinks = <GraphLink>[];
        for (final child in children) {
          final parent = boxes
              .where((b) => b.tabId == child.ownerTabId)
              .firstOrNull;
          if (parent == null) continue;
          final siblings = children
              .where((item) => item.ownerTabId == child.ownerTabId)
              .toList();
          final index = siblings.indexWhere((item) => item.id == child.id);
          positions[child.id] =
              _subagentPositions[child.id] ??
              Offset(
                (parent.position.dx + 250).clamp(0.0, _canvasSize.width - 190),
                (parent.position.dy + index * 104.0).clamp(
                  0.0,
                  _canvasSize.height - 88,
                ),
              );
          temporaryLinks.add(GraphLink(from: parent.id, to: child.id));
        }
        final unresolvedLinks = <GraphLink>[];
        for (final peer in unresolvedPeers) {
          final parent = boxes
              .where((b) => b.tabId == peer.ownerTabId)
              .firstOrNull;
          if (parent == null) continue;
          final siblingIndex = unresolvedPeers
              .where((item) => item.ownerTabId == peer.ownerTabId)
              .toList()
              .indexWhere((item) => item.id == peer.id);
          final childCount = children
              .where((item) => item.ownerTabId == peer.ownerTabId)
              .length;
          positions[peer.id] = Offset(
            (parent.position.dx + 250).clamp(0.0, _canvasSize.width - 190),
            (parent.position.dy + (childCount + siblingIndex) * 104.0).clamp(
              0.0,
              _canvasSize.height - 88,
            ),
          );
          unresolvedLinks.add(GraphLink(from: parent.id, to: peer.id));
        }
        _subagentPositions.removeWhere(
          (id, _) => !children.any((child) => child.id == id),
        );
        return ColoredBox(
          color: colors.bg,
          child: Stack(
            children: [
              Positioned.fill(
                child: InteractiveViewer(
                  transformationController: _transform,
                  constrained: false,
                  boundaryMargin: const EdgeInsets.all(900),
                  minScale: 0.35,
                  maxScale: 2.5,
                  child: SizedBox.fromSize(
                    size: _canvasSize,
                    child: Stack(
                      children: [
                        Positioned.fill(
                          child: RepaintBoundary(
                            child: CustomPaint(
                              painter: _GraphLinkPainter(
                                positions: positions,
                                links: widget.vm.graphLinks,
                                temporary: temporaryLinks,
                                observed: [
                                  ...unresolvedLinks,
                                  for (final event in widget.vm.graphTraffic)
                                    if (boxes.any(
                                          (b) => b.tabId == event.fromTabId,
                                        ) &&
                                        boxes.any(
                                          (b) => b.tabId == event.toTabId,
                                        ))
                                      GraphLink(
                                        from: boxes
                                            .firstWhere(
                                              (b) => b.tabId == event.fromTabId,
                                            )
                                            .id,
                                        to: boxes
                                            .firstWhere(
                                              (b) => b.tabId == event.toTabId,
                                            )
                                            .id,
                                      ),
                                ],
                                selected: selectedBoxId,
                                normal: colors.border2,
                                highlighted: colors.accent,
                                temporaryColor: colors.warn,
                              ),
                            ),
                          ),
                        ),
                        for (final box in boxes)
                          Positioned(
                            left: box.position.dx,
                            top: box.position.dy,
                            width: _boxSize.width,
                            height: _boxSize.height,
                            child: _GraphBoxCard(
                              box: box,
                              session: widget.vm.session(box.tabId ?? ''),
                              disconnected:
                                  widget.vm.selectedRemoteDisconnected,
                              telemetry: _telemetryForBox(box),
                              processTelemetry: switch (widget.vm.session(
                                box.tabId ?? '',
                              )) {
                                TerminalSession(
                                  :final profile,
                                  :final rootProcessId,
                                  :final wslProcessId,
                                  :final processMetricsAreRemote,
                                ) =>
                                  _processTelemetry.putIfAbsent(
                                    box.tabId ?? box.id,
                                    () => processMetricsAreRemote
                                        ? (widget.vm.session(box.tabId ?? '')
                                                  as TerminalSession)
                                              .readRemoteProcessMetrics()
                                        : _processMetricsService.read(
                                            profile: profile,
                                            hostPid: rootProcessId,
                                            wslPid: wslProcessId,
                                          ),
                                  ),
                                _ => null,
                              },
                              selected:
                                  _selected == box.id || _linkFrom == box.id,
                              connecting: _linkMode,
                              onTap: () => _select(box),
                              onOpen: () {
                                final tabId = box.tabId;
                                if (tabId != null && tabId.isNotEmpty) {
                                  widget.onOpenTab(tabId);
                                }
                              },
                              onDrag: (delta) => _dragBox(box, delta),
                              onDragEnd: () => _finishBoxDrag(box),
                            ),
                          ),
                        for (final child in children)
                          if (positions[child.id] case final Offset point)
                            Positioned(
                              left: point.dx,
                              top: point.dy,
                              width: 190,
                              height: 88,
                              child: _GraphSubagentCard(
                                child: child,
                                disconnected:
                                    widget.vm.selectedRemoteDisconnected,
                                selected: _selected == child.id,
                                onTap: () =>
                                    setState(() => _selected = child.id),
                                onOpenParent: () =>
                                    widget.onOpenTab(child.ownerTabId),
                                onDrag: (delta) {
                                  final next =
                                      point +
                                      delta /
                                          _transform.value.getMaxScaleOnAxis();
                                  setState(
                                    () => _subagentPositions[child.id] = Offset(
                                      next.dx.clamp(
                                        0.0,
                                        _canvasSize.width - 190,
                                      ),
                                      next.dy.clamp(
                                        0.0,
                                        _canvasSize.height - 88,
                                      ),
                                    ),
                                  );
                                },
                              ),
                            ),
                        for (final peer in unresolvedPeers)
                          if (positions[peer.id] case final Offset point)
                            Positioned(
                              left: point.dx,
                              top: point.dy,
                              width: 190,
                              height: 88,
                              child: _GraphUnresolvedPeerCard(peer: peer),
                            ),
                      ],
                    ),
                  ),
                ),
              ),
              if (!widget.embedded)
                Positioned(
                  left: 0,
                  right: 0,
                  top: 0,
                  child: WindowTitleBar(
                    children: [
                      const WindowControls(),
                      const SizedBox(width: 12),
                      Text(
                        widget.vm.selectedDisplayTitle ?? 'Cockpit',
                        style: context.typo.title.copyWith(
                          fontSize: 14,
                          color: colors.text,
                        ),
                      ),
                      const Spacer(),
                      PrimaryButton(
                        onPressed: _createBox,
                        child: const Text('+ Criar box'),
                      ),
                      const SizedBox(width: 8),
                      OutlineButton(
                        onPressed: () => setState(() {
                          _linkMode = !_linkMode;
                          _linkFrom = null;
                        }),
                        child: Text(
                          _linkMode
                              ? 'Selecione origem e destino'
                              : 'Ligar boxes',
                        ),
                      ),
                      const SizedBox(width: 8),
                      OutlineButton(
                        onPressed: widget.onExit,
                        child: const Text('Voltar aos terminais'),
                      ),
                      const WindowControlsTrailing(),
                    ],
                  ),
                ),
              if (widget.embedded)
                Positioned(
                  top: 10,
                  right: 12,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      OutlineButton(
                        onPressed: () => setState(() {
                          _linkMode = !_linkMode;
                          _linkFrom = null;
                        }),
                        child: Text(
                          _linkMode
                              ? context.t.workspaceView.selectEndpoints
                              : context.t.workspaceView.linkBoxes,
                        ),
                      ),
                      const SizedBox(width: 8),
                      OutlineButton(
                        onPressed: () => _transform.value = Matrix4.identity(),
                        child: Text(context.t.workspaceView.zoomFit),
                      ),
                    ],
                  ),
                ),
              if (widget.vm.selectedRemoteDisconnected)
                Positioned(
                  left: 20,
                  top: 130,
                  child: Text(
                    'Host desconectado · métricas podem estar desatualizadas',
                    style: context.typo.label.copyWith(color: colors.warn),
                  ),
                ),
              Positioned(
                left: 20,
                top: 60,
                child: _GraphLegend(
                  planned: colors.border2,
                  observed: colors.accent,
                  temporary: colors.warn,
                ),
              ),
              if (!widget.embedded && selectedBox != null)
                Positioned(
                  right: 20,
                  top: 66,
                  width: 290,
                  child: _GraphInspector(
                    box: selectedBox,
                    hasSession: selectedSession != null,
                    agentRunning:
                        selectedSession is TerminalSession &&
                        selectedSession.activeHarness != null,
                    links: widget.vm.graphLinks
                        .where(
                          (l) =>
                              l.from == selectedBox!.id ||
                              l.to == selectedBox.id,
                        )
                        .toList(),
                    boxNames: {for (final box in boxes) box.id: box.title},
                    telemetry: _latestFor(selectedBox.tabId),
                    onEditRole: () async {
                      final box = selectedBox!;
                      final draft = await _editBox(
                        box,
                        canStart:
                            selectedSession == null ||
                            selectedSession is TerminalSession &&
                                selectedSession.activeHarness == null,
                      );
                      if (!mounted || draft == null) return;
                      final session = widget.vm.session(box.tabId ?? '');
                      final id = session == null
                          ? box.id
                          : widget.vm.ensureGraphBoxForTab(
                              session,
                              box.position,
                            );
                      final configured = await widget.vm.configureGraphBox(
                        boxId: id,
                        role: draft.role,
                        harness: draft.harness,
                        model: draft.model,
                      );
                      if (!mounted) return;
                      if (configured case Failure(:final error)) {
                        await _showGraphError(error);
                        return;
                      }
                      setState(() => _selected = id);
                      if (draft.start) {
                        final started = await widget.vm.relaunchGraphBox(id);
                        if (started case Success(:final value)) {
                          widget.onOpenTab(value);
                        } else if (started case Failure(:final error)) {
                          await _showGraphError(error);
                        }
                      }
                    },
                    onCopyRole: () async {
                      await Clipboard.setData(
                        ClipboardData(text: selectedBox!.role),
                      );
                    },
                    onOpen: () {
                      final tabId = selectedBox?.tabId;
                      if (tabId != null && tabId.isNotEmpty) {
                        widget.onOpenTab(tabId);
                      }
                    },
                    onCompact: () => _compact(selectedBox!),
                    onHandoff: () => _handoff(selectedBox!),
                    onStart: () async {
                      final result = await widget.vm.relaunchGraphBox(
                        selectedBox!.id,
                      );
                      if (result case Success(:final value)) {
                        widget.onOpenTab(value);
                      } else if (result case Failure(:final error)) {
                        await _showGraphError(error);
                      }
                    },
                    onRemoveLink: (link) =>
                        widget.vm.removeGraphLink(link.from, link.to),
                  ),
                ),
              Positioned(
                left: 22,
                bottom: 16,
                child: Text(
                  'Arraste boxes para organizar · Arraste o fundo para navegar · Zoom com rolagem',
                  style: context.typo.label.copyWith(color: colors.text3),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _GraphLegend extends StatelessWidget {
  const _GraphLegend({
    required this.planned,
    required this.observed,
    required this.temporary,
  });

  final Color planned;
  final Color observed;
  final Color temporary;

  @override
  Widget build(BuildContext context) {
    final tr = context.t.graphView;
    final colors = context.colors;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.panel,
        border: Border.all(color: colors.border2),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  tr.legend,
                  style: context.typo.label.copyWith(color: colors.text3),
                ),
                const SizedBox(width: 12),
                Text('┄→', style: context.typo.mono.copyWith(color: planned)),
                const SizedBox(width: 4),
                Text(
                  tr.planned,
                  style: context.typo.label.copyWith(color: colors.text2),
                ),
                const SizedBox(width: 12),
                Text('━→', style: context.typo.mono.copyWith(color: observed)),
                const SizedBox(width: 4),
                Text(
                  tr.observed,
                  style: context.typo.label.copyWith(color: colors.text2),
                ),
                const SizedBox(width: 12),
                Text('┈→', style: context.typo.mono.copyWith(color: temporary)),
                const SizedBox(width: 4),
                Text(
                  tr.temporary,
                  style: context.typo.label.copyWith(color: colors.text2),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  '● ${tr.working}',
                  style: context.typo.label.copyWith(color: colors.online),
                ),
                const SizedBox(width: 12),
                Text(
                  '◐ ${tr.waiting}',
                  style: context.typo.label.copyWith(color: colors.warn),
                ),
                const SizedBox(width: 12),
                Text(
                  '○ ${tr.idle}',
                  style: context.typo.label.copyWith(color: colors.text2),
                ),
                const SizedBox(width: 12),
                Text(
                  '× ${tr.ended}',
                  style: context.typo.label.copyWith(color: colors.text3),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _GraphBoxCard extends StatelessWidget {
  const _GraphBoxCard({
    required this.box,
    required this.session,
    required this.disconnected,
    required this.telemetry,
    required this.processTelemetry,
    required this.selected,
    required this.connecting,
    required this.onTap,
    required this.onOpen,
    required this.onDrag,
    required this.onDragEnd,
  });

  final GraphBox box;
  final PaneItem? session;
  final bool disconnected;
  final Future<GraphTelemetrySnapshot>? telemetry;
  final Future<ProcessMetricsSnapshot>? processTelemetry;
  final bool selected;
  final bool connecting;
  final VoidCallback onTap;
  final VoidCallback onOpen;
  final ValueChanged<Offset> onDrag;
  final VoidCallback onDragEnd;

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: FutureBuilder<GraphTelemetrySnapshot>(
        key: ObjectKey(telemetry),
        future: telemetry,
        builder: (context, snapshot) => FutureBuilder<ProcessMetricsSnapshot>(
          future: processTelemetry,
          builder: (context, process) =>
              _buildCard(context, snapshot.data, process.data),
        ),
      ),
    );
  }

  Widget _buildCard(
    BuildContext context,
    GraphTelemetrySnapshot? metric,
    ProcessMetricsSnapshot? process,
  ) {
    final colors = context.colors;
    final tr = context.t.graphView;
    final rawStatus = disconnected
        ? 'disconnected'
        : switch (session) {
            TerminalSession(:final status, :final hasExited) =>
              hasExited ? 'stopped' : status.name,
            null => 'stopped',
            _ => metric?.activity.name ?? 'idle',
          };
    final terminal = session is TerminalSession
        ? session as TerminalSession
        : null;
    final cli = terminal?.activeHarness == null
        ? context.t.orchestration.noCli
        : HarnessCatalog.specs[terminal!.activeHarness]!.label;
    final status = switch (rawStatus) {
      'working' || 'streaming' => tr.working,
      'waiting' => tr.waiting,
      'idle' => tr.idle,
      'starting' || 'booting' => tr.starting,
      'stopped' || 'crashed' => tr.ended,
      'disconnected' => tr.disconnected,
      'unknown' => tr.unknown,
      _ => rawStatus,
    };
    final statusSymbol = switch (rawStatus) {
      'working' || 'streaming' => '●',
      'waiting' => '◐',
      'idle' => '○',
      'starting' || 'booting' => '◌',
      'stopped' || 'crashed' || 'disconnected' => '×',
      _ => '?',
    };
    final statusColor = switch (rawStatus) {
      'working' || 'streaming' => colors.online,
      'waiting' || 'starting' || 'booting' => colors.warn,
      'disconnected' => colors.warn,
      _ => colors.text3,
    };
    final contextUsed = metric?.contextTokens?.value;
    final contextWindow = metric?.contextWindow?.value;
    final contextPercent = metric?.contextPercent;
    final contextSource =
        metric?.contextTokens?.source ?? metric?.activitySource;
    final contextTime = metric?.contextTokens?.observedAt;
    final details = <String>[
      tr.tooltipSession,
      tr.tooltipIdentity(
        tool: cli,
        model: box.model.isEmpty ? tr.defaultModel : box.model,
        status: status,
      ),
      box.role.isEmpty ? tr.noRole : box.role,
      '',
      tr.tooltipContext,
      if (contextUsed != null && contextWindow != null)
        tr.tooltipUsage(
          used: contextUsed.toString(),
          window: contextWindow.toString(),
        )
      else
        tr.contextUnavailable,
      if (metric?.totalTokens?.value case final tokenCount?)
        tr.tokens(count: tokenCount.toString()),
      if (contextSource != null) tr.source(value: contextSource),
      if (contextTime != null)
        tr.updated(value: contextTime.toLocal().toString()),
      '',
      tr.tooltipMachine,
      if (process?.cpuPercent case final cpu?)
        tr.tooltipCpu(value: cpu.toStringAsFixed(1)),
      if (process?.rssBytes case final rss?)
        tr.tooltipRam(value: (rss / 1048576).toStringAsFixed(0)),
      if (process?.source case final processSource?)
        tr.source(value: processSource),
      if (process?.collectedAt case final processTime?)
        tr.updated(value: processTime.toLocal().toString()),
      if (process?.unavailableReason case final reason?)
        tr.tooltipReason(reason: reason),
    ].join('\n');
    Widget withTooltip({required Widget child}) => connecting
        ? child
        : AppTooltip(message: details, showOnFocus: true, child: child);
    return withTooltip(
      child: FocusableActionDetector(
        actions: {
          ActivateIntent: CallbackAction<ActivateIntent>(
            onInvoke: (_) {
              onTap();
              return null;
            },
          ),
        },
        child: GestureDetector(
          onTap: onTap,
          // Endpoint selection must not wait for or trigger terminal opening.
          onDoubleTap: connecting ? null : onOpen,
          onPanUpdate: connecting ? null : (event) => onDrag(event.delta),
          onPanEnd: connecting ? null : (_) => onDragEnd(),
          onPanCancel: connecting ? null : onDragEnd,
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: colors.panel2,
              border: Border.all(
                color: selected ? colors.accent : colors.border2,
                width: selected ? 2 : 1,
              ),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        statusSymbol,
                        style: context.typo.title.copyWith(color: statusColor),
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          box.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: context.typo.title.copyWith(
                            fontSize: 14,
                            color: colors.text,
                          ),
                        ),
                      ),
                      WorkspaceAttentionBadge(
                        unseen: session?.unseenFinish ?? false,
                        waiting: rawStatus == 'waiting',
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '$cli${box.model.isEmpty ? '' : ' · ${box.model}'}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: context.typo.label.copyWith(color: colors.text3),
                  ),
                  const SizedBox(height: 5),
                  Text(
                    box.role.isEmpty ? tr.noRole : box.role,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: context.typo.label.copyWith(color: colors.text2),
                  ),
                  const Spacer(),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          status,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: context.typo.label.copyWith(
                            color: statusColor,
                          ),
                        ),
                      ),
                      if (contextPercent != null)
                        Text(
                          '${contextPercent.toStringAsFixed(0)}%',
                          style: context.typo.label.copyWith(
                            color: contextPercent >= 70
                                ? colors.warn
                                : colors.text2,
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  if (contextPercent == null)
                    Text(
                      tr.contextUnavailable,
                      style: context.typo.label.copyWith(color: colors.text3),
                    )
                  else
                    ClipRRect(
                      borderRadius: BorderRadius.circular(3),
                      child: SizedBox(
                        height: 5,
                        child: Stack(
                          fit: StackFit.expand,
                          children: [
                            ColoredBox(color: colors.border2),
                            FractionallySizedBox(
                              alignment: Alignment.centerLeft,
                              widthFactor: (contextPercent / 100).clamp(
                                0.0,
                                1.0,
                              ),
                              child: ColoredBox(
                                color: contextPercent >= 70
                                    ? colors.warn
                                    : colors.accent,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _GraphUnresolvedPeerCard extends StatelessWidget {
  const _GraphUnresolvedPeerCard({required this.peer});

  final GraphUnresolvedPeer peer;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final tr = context.t.graphView;
    return RepaintBoundary(
      child: AppTooltip(
        message: tr.unresolvedPeerTooltip(address: peer.address),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: colors.accent.withValues(alpha: 0.08),
            border: Border.all(color: colors.accent),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Padding(
            padding: const EdgeInsets.all(10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  tr.unresolvedPeer,
                  style: context.typo.label.copyWith(color: colors.accent),
                ),
                const SizedBox(height: 4),
                Text(
                  peer.address,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: context.typo.title.copyWith(color: colors.text),
                ),
                const Spacer(),
                Text(
                  tr.unresolvedPeerHint,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: context.typo.label.copyWith(color: colors.text3),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _GraphSubagentCard extends StatelessWidget {
  const _GraphSubagentCard({
    required this.child,
    required this.disconnected,
    required this.selected,
    required this.onTap,
    required this.onOpenParent,
    required this.onDrag,
  });

  final GraphSubagent child;
  final bool disconnected;
  final bool selected;
  final VoidCallback onTap;
  final VoidCallback onOpenParent;
  final ValueChanged<Offset> onDrag;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final tr = context.t.graphSubagent;
    final name = child.agentType.isEmpty ? tr.nameFallback : child.agentType;
    return AppTooltip(
      showOnFocus: true,
      message: tr.tooltip(
        type: name,
        id: child.agentId,
        harness: child.harness,
        tab: child.ownerTabId,
        time: child.startedAt.toLocal().toString(),
      ),
      child: FocusableActionDetector(
        actions: {
          ActivateIntent: CallbackAction<ActivateIntent>(
            onInvoke: (_) {
              onTap();
              return null;
            },
          ),
        },
        child: GestureDetector(
          onTap: onTap,
          onDoubleTap: onOpenParent,
          onPanUpdate: (event) => onDrag(event.delta),
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: colors.warn.withValues(alpha: 0.10),
              border: Border.all(
                color: selected ? colors.accent : colors.warn,
                width: selected ? 2 : 1,
              ),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Padding(
              padding: const EdgeInsets.all(10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '◈ ${tr.badge}',
                    style: context.typo.label.copyWith(color: colors.warn),
                  ),
                  const SizedBox(height: 5),
                  Text(
                    name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: context.typo.title.copyWith(color: colors.text),
                  ),
                  const Spacer(),
                  Text(
                    context.t.graphView.controlledBy,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: context.typo.label.copyWith(color: colors.text3),
                  ),
                  Text(
                    disconnected ? tr.disconnected : tr.active,
                    style: context.typo.label.copyWith(
                      color: disconnected ? colors.warn : colors.online,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _GraphInspector extends StatelessWidget {
  const _GraphInspector({
    required this.box,
    required this.hasSession,
    required this.agentRunning,
    required this.links,
    required this.boxNames,
    required this.telemetry,
    required this.onEditRole,
    required this.onCopyRole,
    required this.onOpen,
    required this.onCompact,
    required this.onHandoff,
    required this.onStart,
    required this.onRemoveLink,
  });

  final GraphBox box;
  final bool hasSession;
  final bool agentRunning;
  final List<GraphLink> links;
  final Map<String, String> boxNames;
  final GraphTelemetrySnapshot? telemetry;
  final VoidCallback onEditRole;
  final VoidCallback onCopyRole;
  final VoidCallback onOpen;
  final VoidCallback onCompact;
  final VoidCallback onHandoff;
  final VoidCallback onStart;
  final ValueChanged<GraphLink> onRemoveLink;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final pct = telemetry?.contextPercent;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.panel,
        border: Border.all(color: colors.border2),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              box.title,
              style: context.typo.title.copyWith(color: colors.text),
            ),
            const SizedBox(height: 10),
            if (hasSession)
              PrimaryButton(
                onPressed: onOpen,
                child: Text(context.t.graphView.openTerminal),
              ),
            const SizedBox(height: 8),
            Text(
              box.role.isEmpty ? context.t.graphView.noRole : box.role,
              maxLines: 5,
              overflow: TextOverflow.ellipsis,
              style: context.typo.body.copyWith(color: colors.text2),
            ),
            const SizedBox(height: 10),
            OutlineButton(
              onPressed: onEditRole,
              child: const Text('Editar função e CLI'),
            ),
            if (box.role.isNotEmpty) ...[
              const SizedBox(height: 6),
              OutlineButton(
                onPressed: onCopyRole,
                child: const Text('Copiar função para iniciar demanda'),
              ),
            ],
            if (pct != null && pct >= 70) ...[
              const SizedBox(height: 10),
              Text(
                pct >= 85
                    ? 'Contexto alto (${pct.toStringAsFixed(0)}%). Prepare um handoff.'
                    : 'Contexto em ${pct.toStringAsFixed(0)}%. Considere compactar.',
                style: context.typo.label.copyWith(color: colors.warn),
              ),
            ],
            if (telemetry != null) ...[
              const SizedBox(height: 12),
              Text(
                context.t.graphView.metrics,
                style: context.typo.label.copyWith(color: colors.text3),
              ),
              const SizedBox(height: 4),
              Text(
                pct == null
                    ? context.t.graphView.contextUnavailable
                    : context.t.graphView.context(
                        percent: pct.toStringAsFixed(0),
                      ),
                style: context.typo.label.copyWith(color: colors.text2),
              ),
              if (telemetry?.totalTokens?.value case final count?)
                Text(
                  context.t.graphView.tokens(count: count.toString()),
                  style: context.typo.label.copyWith(color: colors.text2),
                ),
              Text(
                context.t.graphView.source(
                  value:
                      telemetry?.contextTokens?.source ??
                      telemetry?.activitySource ??
                      '-',
                ),
                style: context.typo.label.copyWith(color: colors.text3),
              ),
            ],
            const SizedBox(height: 10),
            if (!agentRunning)
              PrimaryButton(
                onPressed: box.harness.isEmpty ? onEditRole : onStart,
                child: Text(
                  box.harness.isEmpty
                      ? 'Configurar CLI'
                      : 'Iniciar ${box.harness == 'claudeCode' ? 'claude' : box.harness}',
                ),
              )
            else ...[
              OutlineButton(
                onPressed: onCompact,
                child: const Text('Compactar'),
              ),
              const SizedBox(height: 6),
              OutlineButton(
                onPressed: onHandoff,
                child: const Text('Nova sessão com handoff'),
              ),
            ],
            if (links.isNotEmpty) ...[
              const SizedBox(height: 14),
              Text(
                context.t.graphView.connections,
                style: context.typo.label.copyWith(color: colors.text2),
              ),
              for (final link in links)
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        '${boxNames[link.from] ?? link.from} → ${boxNames[link.to] ?? link.to}',
                        overflow: TextOverflow.ellipsis,
                        style: context.typo.mono.copyWith(
                          fontSize: 10,
                          color: colors.text3,
                        ),
                      ),
                    ),
                    OutlineButton(
                      onPressed: () => onRemoveLink(link),
                      child: const Text('×'),
                    ),
                  ],
                ),
            ] else ...[
              const SizedBox(height: 14),
              Text(
                context.t.graphView.noConnections,
                style: context.typo.label.copyWith(color: colors.text3),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _GraphLinkPainter extends CustomPainter {
  const _GraphLinkPainter({
    required this.positions,
    required this.links,
    required this.temporary,
    required this.observed,
    required this.selected,
    required this.normal,
    required this.highlighted,
    required this.temporaryColor,
  });
  final Map<String, Offset> positions;
  final List<GraphLink> links;
  final List<GraphLink> temporary;
  final List<GraphLink> observed;
  final String? selected;
  final Color normal;
  final Color highlighted;
  final Color temporaryColor;

  @override
  void paint(Canvas canvas, Size size) {
    final observedPairs = {
      for (final event in observed) (event.from, event.to),
    };
    for (final link in links) {
      if (observedPairs.contains((link.from, link.to))) {
        continue;
      }
      _paintLink(canvas, link, planned: true);
    }
    for (final link in temporary) {
      _paintLink(canvas, link, planned: true, temporary: true);
    }
    for (final link in observed) {
      _paintLink(canvas, link, planned: false);
    }
  }

  void _paintLink(
    Canvas canvas,
    GraphLink link, {
    required bool planned,
    bool temporary = false,
  }) {
    final a = positions[link.from];
    final b = positions[link.to];
    if (a == null || b == null) return;
    final start = a + const Offset(230, 71);
    final end = b + Offset(0, temporary ? 44 : 71);
    final active = selected == link.from || selected == link.to;
    final paint = Paint()
      ..color = temporary
          ? temporaryColor
          : !planned || active
          ? highlighted
          : normal
      ..strokeWidth = active || !planned ? 2.4 : 1.4
      ..style = PaintingStyle.stroke;
    final mid = (start.dx + end.dx) / 2;
    final path = Path()
      ..moveTo(start.dx, start.dy)
      ..cubicTo(mid, start.dy, mid, end.dy, end.dx, end.dy);
    if (planned) {
      for (final metric in path.computeMetrics()) {
        final step = temporary ? 7.0 : 12.0;
        final length = temporary ? 2.5 : 6.0;
        for (var distance = 0.0; distance < metric.length; distance += step) {
          canvas.drawPath(
            metric.extractPath(distance, distance + length),
            paint,
          );
        }
      }
    } else {
      canvas.drawPath(path, paint);
    }
    final arrow = Paint()..color = paint.color;
    canvas.drawPath(
      Path()
        ..moveTo(end.dx, end.dy)
        ..lineTo(end.dx - 7, end.dy - 4)
        ..lineTo(end.dx - 7, end.dy + 4)
        ..close(),
      arrow,
    );
  }

  @override
  bool shouldRepaint(covariant _GraphLinkPainter oldDelegate) =>
      oldDelegate.positions != positions ||
      oldDelegate.links != links ||
      oldDelegate.temporary != temporary ||
      oldDelegate.observed != observed ||
      oldDelegate.selected != selected;
}

typedef _GraphBoxDraft = ({
  String title,
  String role,
  String harness,
  String model,
});

class _CreateBoxDialog extends StatefulWidget {
  const _CreateBoxDialog();

  @override
  State<_CreateBoxDialog> createState() => _CreateBoxDialogState();
}

class _CreateBoxDialogState extends State<_CreateBoxDialog> {
  final _title = TextEditingController();
  final _role = TextEditingController();
  final _model = TextEditingController();
  String _harness = 'claude';

  @override
  void dispose() {
    _title.dispose();
    _role.dispose();
    _model.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Criar box'),
    content: SizedBox(
      width: 420,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Nome'),
          TextField(controller: _title, placeholder: const Text('Frontend')),
          const SizedBox(height: 12),
          const Text('Função / instrução inicial'),
          TextField(
            controller: _role,
            placeholder: const Text('Implementar interface'),
          ),
          const SizedBox(height: 12),
          const Text('Ferramenta'),
          Row(
            children: [
              for (final harness in const ['claude', 'codex', 'pi'])
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: OutlineButton(
                    onPressed: () => setState(() => _harness = harness),
                    child: Text(_harness == harness ? '● $harness' : harness),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 12),
          const Text('Modelo (vazio = padrão da ferramenta)'),
          TextField(controller: _model, placeholder: const Text('model-id')),
        ],
      ),
    ),
    actions: [
      OutlineButton(
        onPressed: () => Navigator.of(context).pop(),
        child: const Text('Cancelar'),
      ),
      PrimaryButton(
        onPressed: () {
          if (_title.text.trim().isEmpty) return;
          Navigator.of(context).pop((
            title: _title.text.trim(),
            role: _role.text.trim(),
            harness: _harness,
            model: _model.text.trim(),
          ));
        },
        child: const Text('Criar terminal'),
      ),
    ],
  );
}
