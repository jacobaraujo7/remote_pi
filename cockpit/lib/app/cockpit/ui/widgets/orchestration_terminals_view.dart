import 'dart:async';
import 'dart:math' as math;

import 'package:shadcn_flutter/shadcn_flutter.dart';
import 'package:flutter/services.dart';
import '../../../core/ui/themes/themes.dart';
import '../../../../i18n/strings.g.dart';
import '../session/orchestration_session.dart';
import '../states/pane_node.dart';
import 'pane_divider.dart';
import 'pane_tab_leading.dart';
import 'stable_pane_host.dart';
import 'terminal_session_view.dart';

/// Distinct from outer TabDragData: neither outer docks nor other instances
/// may accept these children. Only the parent app tab crosses outer docks.
class OrchestrationTabDragData {
  const OrchestrationTabDragData(this.instanceId, this.tabId);
  final String instanceId, tabId;
}

class OrchestrationTerminalsView extends StatelessWidget {
  const OrchestrationTerminalsView({
    super.key,
    required this.session,
    required this.active,
    required this.focused,
  });
  final OrchestrationSession session;
  final bool active, focused;

  void _focus(String tabId) {
    session.onFocus?.call();
    session.context.focusTerminalTab(tabId);
  }

  Widget _dropZone(String paneId, Widget child) => Builder(
    builder: (context) {
      return DragTarget<OrchestrationTabDragData>(
        onWillAcceptWithDetails: (d) =>
            d.data.instanceId == session.id &&
            session.terminals.contains(d.data.tabId),
        onAcceptWithDetails: (d) {
          if (d.data.instanceId != session.id) return;
          final box = context.findRenderObject()! as RenderBox;
          final point = box.globalToLocal(d.offset);
          final x = math.min(48.0, box.size.width * .2);
          final y = math.min(48.0, box.size.height * .2);
          SplitDir? direction;
          var before = false;
          if (point.dx < x || point.dx > box.size.width - x) {
            direction = SplitDir.vertical;
            before = point.dx < x;
          } else if (point.dy < y || point.dy > box.size.height - y) {
            direction = SplitDir.horizontal;
            before = point.dy < y;
          }
          session.onFocus?.call();
          if (direction != null) {
            session.terminals.splitTab(
              d.data.tabId,
              direction,
              anchorPaneId: paneId,
              before: before,
            );
          } else {
            session.terminals.move(d.data.tabId, paneId);
          }
        },
        builder: (context, candidates, _) => DecoratedBox(
          decoration: BoxDecoration(
            border: candidates.isEmpty
                ? null
                : Border.all(color: context.colors.accent),
          ),
          child: child,
        ),
      );
    },
  );

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: session.terminals,
    builder: (context, _) {
      final mux = session.terminals;
      final tree = mux.tree;
      if (tree == null) {
        return Center(
          child: OutlineButton(
            onPressed: session.closing
                ? null
                : () => session.context.newTerminal(),
            child: Text(context.t.orchestration.newTerminal),
          ),
        );
      }
      return ClipRect(
        child: StablePaneHost(
          tree: tree,
          active: active,
          onResize: mux.resize,
          dividerBuilder: (dir, delta) => PaneDivider(dir: dir, onDelta: delta),
          paneBuilder: (pane, _) => _dropZone(
            pane.id,
            LayoutBuilder(
              builder: (context, limits) => ClipRect(
                child: Column(
                  children: [
                    SizedBox(
                      height: math.min(40, limits.maxHeight),
                      child: Row(
                        children: [
                          Expanded(
                            child: SingleChildScrollView(
                              scrollDirection: Axis.horizontal,
                              child: Row(
                                children: [
                                  for (final tabId in pane.tabs)
                                    _tab(context, pane, tabId),
                                ],
                              ),
                            ),
                          ),
                          SizedBox(
                            width: math.min(32, limits.maxWidth),
                            child: IconButton.ghost(
                              icon: const Icon(Icons.add, size: 16),
                              onPressed: session.closing
                                  ? null
                                  : () => session.context.newTerminal(
                                      inPane: pane.id,
                                    ),
                            ),
                          ),
                          if (limits.maxWidth >= 180)
                            IconButton.ghost(
                              icon: const Icon(
                                Icons.vertical_split_outlined,
                                size: 16,
                              ),
                              onPressed: session.closing
                                  ? null
                                  : () => session.context.newTerminal(
                                      inPane: pane.id,
                                      split: SplitDir.vertical,
                                    ),
                            ),
                          if (limits.maxWidth >= 180)
                            IconButton.ghost(
                              icon: const Icon(
                                Icons.horizontal_split_outlined,
                                size: 16,
                              ),
                              onPressed: session.closing
                                  ? null
                                  : () => session.context.newTerminal(
                                      inPane: pane.id,
                                      split: SplitDir.horizontal,
                                    ),
                            ),
                        ],
                      ),
                    ),
                    const Expanded(child: SizedBox()),
                  ],
                ),
              ),
            ),
          ),
          tabBodyBuilder: (pane, tabId, visible) {
            final terminal = mux.session(tabId)!;
            return _dropZone(
              pane.id,
              TerminalSessionView(
                key: ValueKey((session.id, tabId)),
                session: terminal,
                active: visible,
                focused: visible && focused && mux.keyboardTabId == tabId,
                focusRevision: mux.focusRevision,
                onFocus: () => _focus(tabId),
                onOpenFile: (path, {line}) =>
                    unawaited(session.openFile(terminal.id, path, line: line)),
                ownerShortcuts: {
                  const SingleActivator(
                    LogicalKeyboardKey.tab,
                    control: true,
                  ): () =>
                      session.context.cycleTerminalTab(1),
                  const SingleActivator(
                    LogicalKeyboardKey.tab,
                    control: true,
                    shift: true,
                  ): () =>
                      session.context.cycleTerminalTab(-1),
                },
              ),
            );
          },
        ),
      );
    },
  );

  Widget _tab(BuildContext context, LeafPane pane, String tabId) {
    final terminal = session.terminals.session(tabId)!;
    final selected = pane.active == tabId;
    void configure() {
      session.terminals.releaseKeyboard();
      final box = session.context.graphBoxForTab(tabId);
      if (box != null) {
        session.context.selectWorkspaceBox(box.id, configure: true);
      }
    }

    final tab = SizedBox(
      width: 188,
      height: 40,
      child: Listener(
        behavior: HitTestBehavior.translucent,
        onPointerDown: (event) {
          if (event.localPosition.dx < 162) _focus(tabId);
        },
        child: GestureDetector(
          onDoubleTap: configure,
          child: Container(
            padding: const EdgeInsets.only(left: 8),
            color: selected ? context.colors.accentSoft : context.colors.panel,
            child: Row(
              children: [
                PaneTabLeading(
                  item: terminal,
                  defaultIcon: Icons.terminal_outlined,
                  iconColor: context.colors.text2,
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    terminal.displayTitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: context.typo.tab,
                  ),
                ),
                if (terminal.unseenFinish)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 3),
                    child: Icon(
                      Icons.circle,
                      size: 7,
                      color: context.colors.accent,
                    ),
                  ),
                IconButton.ghost(
                  icon: const Icon(Icons.settings_outlined, size: 13),
                  onPressed: configure,
                ),
                IconButton.ghost(
                  icon: const Icon(Icons.close, size: 13),
                  onPressed: session.closing
                      ? null
                      : () async {
                          await session.closeTerminal(tabId);
                        },
                ),
              ],
            ),
          ),
        ),
      ),
    );
    final draggable = Draggable<OrchestrationTabDragData>(
      data: OrchestrationTabDragData(session.id, tabId),
      dragAnchorStrategy: pointerDragAnchorStrategy,
      feedback: Container(
        width: 188,
        height: 40,
        color: context.colors.panel,
        padding: const EdgeInsets.all(8),
        child: Text(terminal.displayTitle, style: context.typo.tab),
      ),
      child: tab,
    );
    return DragTarget<OrchestrationTabDragData>(
      onWillAcceptWithDetails: (d) =>
          d.data.instanceId == session.id &&
          session.terminals.contains(d.data.tabId),
      onAcceptWithDetails: (d) {
        if (d.data.instanceId != session.id || session.disposed) return;
        session.terminals.move(
          d.data.tabId,
          pane.id,
          index: pane.tabs.indexOf(tabId),
        );
      },
      builder: (_, _, _) => draggable,
    );
  }
}
