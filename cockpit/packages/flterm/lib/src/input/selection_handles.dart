import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:libghostty/libghostty.dart' show Mods;
import 'package:meta/meta.dart';

import '../foundation/cell_metrics.dart';
import '../foundation/terminal_gesture_settings.dart';
import 'input_modifiers.dart';
import 'selection_handle_geometry.dart';
import 'selection_handle_layer.dart';
import 'selection_magnifier.dart';
import 'selection_modifier.dart';
import 'selection_session.dart';

@internal
final class TerminalSelectionHandles extends StatefulWidget {
  final bool visible;
  final CellMetrics metrics;
  final Color terminalBackground;
  final SelectionInteraction selection;
  final ValueGetter<Mods> readVirtualMods;
  final ValueChanged<int> onViewportRowChanged;
  final ValueChanged<bool>? onDragStateChanged;
  final GestureModifier? blockSelectionModifier;
  final TextMagnifierConfiguration? magnifierConfiguration;

  const TerminalSelectionHandles({
    super.key,
    required this.visible,
    required this.metrics,
    required this.selection,
    this.onDragStateChanged,
    this.magnifierConfiguration,
    required this.readVirtualMods,
    required this.terminalBackground,
    required this.onViewportRowChanged,
    this.blockSelectionModifier = .alt,
  });

  @override
  State<TerminalSelectionHandles> createState() => _SelectionHandlesState();
}

final class _SelectionHandlesState extends State<TerminalSelectionHandles> {
  final _magnifierContext = GlobalKey();
  late final _magnifierHost = OverlayEntry(
    builder: (_) => SizedBox.expand(key: _magnifierContext),
  );
  Offset? _dragAnchor;
  Offset? _gesturePosition;
  Offset _dragOffset = .zero;
  Offset _magnifierOverlayOrigin = .zero;
  SelectionEndpoint? _draggedEndpoint;
  SelectionMagnifier? _magnifier;

  Mods get _currentMods => readPointerModifiers(widget.readVirtualMods());

  MagnifierInfo get _magnifierInfo => SelectionMagnifier.geometry(
    context: context,
    gesture: _gesturePosition!,
    anchor: _dragAnchor!,
    metrics: widget.metrics,
    rows: widget.selection.rows,
  );

  @override
  Widget build(BuildContext context) {
    final scrollPosition = Scrollable.maybeOf(context)?.position;
    final changes = scrollPosition == null
        ? widget.selection
        : Listenable.merge([widget.selection, scrollPosition]);
    return LookupBoundary(
      child: Stack(
        clipBehavior: .none,
        children: [
          Positioned.fill(
            child: ListenableBuilder(
              listenable: changes,
              builder: (context, _) {
                final selection = widget.selection.selection;
                if (!widget.visible || selection == null) {
                  return const SizedBox.expand();
                }
                return SelectionHandleLayer(
                  selection: selection,
                  metrics: widget.metrics,
                  onDragStart: _startDrag,
                  onDragUpdate: _updateDrag,
                  onDragEnd: (endpoint, _) => _endDrag(endpoint: endpoint),
                  onDragCancel: (endpoint) => _endDrag(endpoint: endpoint),
                );
              },
            ),
          ),
          Positioned.fill(
            child: IgnorePointer(
              child: Transform.translate(
                offset: -_magnifierOverlayOrigin,
                child: Overlay(
                  clipBehavior: .none,
                  initialEntries: [_magnifierHost],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  void didUpdateWidget(TerminalSelectionHandles oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.selection != oldWidget.selection ||
        widget.magnifierConfiguration != oldWidget.magnifierConfiguration ||
        widget.metrics != oldWidget.metrics ||
        widget.terminalBackground != oldWidget.terminalBackground ||
        !widget.visible) {
      _endDrag(owner: oldWidget.selection);
    }
  }

  @override
  void dispose() {
    _endDrag();
    _magnifierHost
      ..remove()
      ..dispose();
    super.dispose();
  }

  void _applyDrag() {
    final endpoint = _draggedEndpoint;
    final anchor = _dragAnchor;
    final gesture = _gesturePosition;
    final selection = widget.selection.selection;
    if (endpoint == null ||
        anchor == null ||
        gesture == null ||
        selection == null) {
      return;
    }
    final handles = SelectionHandleGeometry.layout(selection, widget.metrics);
    final moving = switch (endpoint) {
      .start => handles.start,
      .end => handles.end,
    };
    if (moving == null) return;
    final position = SelectionHandleGeometry.positionForDrag(
      anchor: anchor,
      leading: moving.leading,
      metrics: widget.metrics,
      columns: widget.selection.columns,
      rows: widget.selection.rows,
    );
    _magnifier?.update(_magnifierInfo);
    widget.selection.updateEndpoint(
      endpoint,
      position,
      rectangle: isSelectionModifierPressed(
        widget.blockSelectionModifier,
        _currentMods,
      ),
    );
  }

  int _autoScrollDirection() {
    final anchor = _dragAnchor;
    if (anchor == null) return 0;
    final row = widget.metrics.cellAt(anchor).row;
    final rows = widget.selection.rows;
    if (row < 0) return -1;
    if (row >= rows) return 1;
    return 0;
  }

  void _autoScrollTick() {
    final direction = _autoScrollDirection();
    if (direction == 0) {
      _stopAutoScroll();
      return;
    }
    final scrollbar = widget.selection.scrollbar;
    final maxOffset = scrollbar.total > scrollbar.visible
        ? scrollbar.total - scrollbar.visible
        : 0;
    final nextOffset = (scrollbar.offset + direction).clamp(0, maxOffset);
    if (nextOffset == scrollbar.offset) {
      _stopAutoScroll();
      return;
    }
    widget.onViewportRowChanged(nextOffset);
    _applyDrag();
  }

  void _endDrag({SelectionEndpoint? endpoint, SelectionInteraction? owner}) {
    if (endpoint != null && endpoint != _draggedEndpoint) return;
    final wasDragging = _draggedEndpoint != null;
    (owner ?? widget.selection).stopAutoscroll(.handle);
    if (wasDragging) {
      HardwareKeyboard.instance.removeHandler(_handleModifierKey);
    }
    _dragAnchor = null;
    _draggedEndpoint = null;
    _gesturePosition = null;
    _magnifier?.dispose();
    _magnifier = null;
    if (wasDragging) widget.onDragStateChanged?.call(false);
  }

  bool _handleModifierKey(KeyEvent _) {
    _applyDrag();
    return false;
  }

  void _startDrag(SelectionHandleLayout layout, DragStartDetails details) {
    if (_draggedEndpoint != null) return;
    final box = context.findRenderObject()! as RenderBox;
    final overlayOrigin = box.localToGlobal(Offset.zero);
    if (overlayOrigin != _magnifierOverlayOrigin) {
      setState(() => _magnifierOverlayOrigin = overlayOrigin);
    }
    HardwareKeyboard.instance.addHandler(_handleModifierKey);
    _draggedEndpoint = layout.endpoint;
    widget.onDragStateChanged?.call(true);
    _dragAnchor = layout.anchor;
    _dragOffset = layout.anchor - box.globalToLocal(details.globalPosition);
    _gesturePosition = details.globalPosition;
    Focus.maybeOf(context)?.requestFocus();
    final magnifierContext = _magnifierContext.currentContext;
    if (magnifierContext == null) return;
    _magnifier = SelectionMagnifier(
      widget.magnifierConfiguration ??
          SelectionMagnifier.adaptive(context, widget.terminalBackground),
    )..show(magnifierContext, _magnifierInfo);
  }

  void _stopAutoScroll() => widget.selection.stopAutoscroll(.handle);

  void _updateAutoScroll() {
    if (_autoScrollDirection() == 0) {
      _stopAutoScroll();
      return;
    }
    widget.selection.startAutoscroll(.handle, _autoScrollTick);
  }

  void _updateDrag(SelectionEndpoint endpoint, DragUpdateDetails details) {
    if (_draggedEndpoint != endpoint) return;
    final box = context.findRenderObject()! as RenderBox;
    _dragAnchor = box.globalToLocal(details.globalPosition) + _dragOffset;
    _gesturePosition = details.globalPosition;
    _applyDrag();
    _updateAutoScroll();
  }
}
