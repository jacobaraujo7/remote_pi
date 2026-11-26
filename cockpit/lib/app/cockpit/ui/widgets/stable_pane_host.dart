import 'package:flutter/rendering.dart' show RenderCustomMultiChildLayoutBox;
import 'dart:math' as math;
import 'package:flutter/widgets.dart';
import '../states/pane_node.dart';

/// Projects a split tree without making pane widgets descendants of splits.
/// Each leaf has exactly one stable parent, including in single-pane previews.
class StablePaneHost extends StatelessWidget {
  const StablePaneHost({
    super.key,
    required this.tree,
    required this.paneBuilder,
    required this.onResize,
    this.active = true,
    this.preview = false,
    this.previewPaneId,
    this.dividerBuilder,
    this.tabBodyBuilder,
    this.tabStripHeight = 40,
  });
  final Widget Function(SplitDir dir, ValueChanged<double> onDelta)?
  dividerBuilder;

  /// Bodies are siblings of pane chrome, keyed by tab rather than dock. Moving
  /// a tab changes only geometry; native terminal views never deactivate.
  final Widget Function(LeafPane pane, String tabId, bool visible)?
  tabBodyBuilder;
  final double tabStripHeight;
  final PaneNode tree;
  final bool active;
  final bool preview;
  final String? previewPaneId;
  final Widget Function(LeafPane pane, bool visible) paneBuilder;
  final void Function(String splitId, double fractionDelta) onResize;

  @override
  Widget build(BuildContext context) {
    return CustomMultiChildLayout(
      delegate: _PaneLayout(
        tree,
        preview,
        previewPaneId,
        tabBodyBuilder != null,
        tabStripHeight,
        active,
      ),
      children: [
        for (final pane in leaves(tree))
          LayoutId(
            key: ValueKey('host-${pane.id}'),
            id: pane.id,
            child: ExcludeFocus(
              excluding: preview && pane.id != previewPaneId,
              child: IgnorePointer(
                ignoring: preview && pane.id != previewPaneId,
                child: Offstage(
                  offstage: preview && pane.id != previewPaneId,
                  child: paneBuilder(
                    pane,
                    !preview || pane.id == previewPaneId,
                  ),
                ),
              ),
            ),
          ),
        if (tabBodyBuilder != null)
          for (final pane in leaves(tree))
            for (final tabId in pane.tabs) _tabHost(pane, tabId),
        if (!preview)
          for (final split in paneSplits(tree))
            LayoutId(
              key: ValueKey('divider-${split.id}'),
              id: 'divider-${split.id}',
              child: _SplitHandle(
                split: split,
                onResize: onResize,
                builder: dividerBuilder,
              ),
            ),
      ],
    );
  }

  Widget _tabHost(LeafPane pane, String tabId) {
    final selected = pane.tabs.contains(pane.active)
        ? pane.active
        : pane.tabs.firstOrNull;
    final visible =
        active && tabId == selected && (!preview || pane.id == previewPaneId);
    return LayoutId(
      key: ValueKey(('tab-body', tabId)),
      id: ('tab-body', tabId),
      child: ExcludeFocus(
        excluding: !visible,
        child: IgnorePointer(
          ignoring: !visible,
          child: Offstage(
            offstage: !visible,
            child: TickerMode(
              enabled: visible,
              child: tabBodyBuilder!(pane, tabId, visible),
            ),
          ),
        ),
      ),
    );
  }
}

Iterable<SplitPane> paneSplits(PaneNode node) sync* {
  if (node is SplitPane) {
    yield node;
    yield* paneSplits(node.a);
    yield* paneSplits(node.b);
  }
}

Map<String, Rect> paneRectangles(PaneNode tree, Size size) {
  final result = <String, Rect>{};
  void walk(PaneNode node, Rect rect) {
    result[node.id] = rect;
    if (node is SplitPane) {
      final fraction = (node.frac * 100000).round().clamp(1, 99999) / 100000;
      if (node.dir == SplitDir.vertical) {
        final width = rect.width * fraction;
        walk(node.a, Rect.fromLTWH(rect.left, rect.top, width, rect.height));
        walk(
          node.b,
          Rect.fromLTWH(
            rect.left + width,
            rect.top,
            rect.width - width,
            rect.height,
          ),
        );
      } else {
        final height = rect.height * fraction;
        walk(node.a, Rect.fromLTWH(rect.left, rect.top, rect.width, height));
        walk(
          node.b,
          Rect.fromLTWH(
            rect.left,
            rect.top + height,
            rect.width,
            rect.height - height,
          ),
        );
      }
    }
  }

  walk(tree, Offset.zero & size);
  return result;
}

class _PaneLayout extends MultiChildLayoutDelegate {
  final bool? active;
  Map<String, Size>? _bodySizes;
  final bool detachedBodies;
  final double tabStripHeight;
  _PaneLayout(
    this.tree,
    this.preview,
    this.previewPaneId,
    this.detachedBodies,
    this.tabStripHeight,
    this.active,
  );
  final PaneNode tree;
  final bool preview;
  final String? previewPaneId;
  @override
  void performLayout(Size size) {
    // Hidden panes still receive bounded, nonzero constraints: their native
    // terminal controller must never be resized to an invalid zero grid.
    final safeSize = Size(math.max(1, size.width), math.max(1, size.height));
    final rects = paneRectangles(tree, safeSize);
    final bodySizes = _bodySizes ??= {};
    for (final pane in leaves(tree)) {
      final rect = preview && pane.id == previewPaneId
          ? Offset.zero & safeSize
          : rects[pane.id]!;
      layoutChild(pane.id, BoxConstraints.tight(rect.size));
      positionChild(pane.id, rect.topLeft);
      if (detachedBodies) {
        final top = math.min(tabStripHeight, rect.height);
        final bodySize = Size(
          math.max(1, rect.width),
          math.max(1, rect.height - top),
        );
        for (final tabId in pane.tabs) {
          final selected = pane.tabs.contains(pane.active)
              ? pane.active
              : pane.tabs.firstOrNull;
          final visible =
              active == true &&
              tabId == selected &&
              (!preview || pane.id == previewPaneId);
          // Offstage still lays out its child. Freezing a hidden body's last
          // valid constraints avoids reflowing every PTY/history on each drag.
          final measured = visible ? bodySize : (bodySizes[tabId] ?? bodySize);
          bodySizes[tabId] = measured;
          layoutChild(('tab-body', tabId), BoxConstraints.tight(measured));
          positionChild(('tab-body', tabId), rect.topLeft + Offset(0, top));
        }
      }
    }
    final liveTabs = {for (final pane in leaves(tree)) ...pane.tabs};
    bodySizes.removeWhere((id, _) => !liveTabs.contains(id));
    if (!preview) {
      for (final split in paneSplits(tree)) {
        final bounds = rects[split.id]!;
        final row = split.dir == SplitDir.vertical;
        final handle = row
            ? Rect.fromLTWH(
                bounds.left + bounds.width * split.frac - 6,
                bounds.top,
                12,
                bounds.height,
              )
            : Rect.fromLTWH(
                bounds.left,
                bounds.top + bounds.height * split.frac - 6,
                bounds.width,
                12,
              );
        layoutChild('divider-${split.id}', BoxConstraints.tight(handle.size));
        positionChild('divider-${split.id}', handle.topLeft);
      }
    }
  }

  @override
  bool shouldRelayout(_PaneLayout old) {
    _bodySizes = old._bodySizes;
    return old.active != active ||
        old.detachedBodies != detachedBodies ||
        old.tabStripHeight != tabStripHeight ||
        old.tree != tree ||
        old.preview != preview ||
        old.previewPaneId != previewPaneId;
  }
}

class _SplitHandle extends StatelessWidget {
  const _SplitHandle({
    required this.split,
    required this.onResize,
    this.builder,
  });
  final SplitPane split;
  final Widget Function(SplitDir, ValueChanged<double>)? builder;
  final void Function(String, double) onResize;
  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final row = split.dir == SplitDir.vertical;
      // The delegate gives the handle its cross-axis extent. Resolve the split
      // extent from this render object's parent data rather than the pane tree.
      void drag(double delta) {
        final parent = context
            .findAncestorRenderObjectOfType<RenderCustomMultiChildLayoutBox>();
        if (parent == null || !parent.hasSize) return;
        final rect = paneRectangles(_root(context), parent.size)[split.id];
        if (rect == null) return;
        final extent = row ? rect.width : rect.height;
        if (extent > 0) {
          onResize(split.id, delta / extent);
        }
      }

      if (builder != null) return builder!(split.dir, drag);
      return MouseRegion(
        cursor: row
            ? SystemMouseCursors.resizeLeftRight
            : SystemMouseCursors.resizeUpDown,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onPanUpdate: (event) => drag(row ? event.delta.dx : event.delta.dy),
          child: Center(
            child: Container(
              width: row ? 1 : null,
              height: row ? null : 1,
              color: const Color(0x333F4554),
            ),
          ),
        ),
      );
    },
  );
  PaneNode _root(BuildContext context) =>
      context.findAncestorWidgetOfExactType<StablePaneHost>()!.tree;
}
