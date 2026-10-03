import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:libghostty/libghostty.dart'
    show Mods, MouseAction, MouseButton, Position, Selection;
import 'package:meta/meta.dart';

import '../foundation.dart';
import '../links/link_interaction.dart';
import '../links/link_settings.dart';
import 'input_message.dart';
import 'input_modifiers.dart';
import 'primitive_gesture_detector.dart';
import 'scroll_gesture_region.dart';
import 'selection_handles.dart';
import 'selection_modifier.dart';
import 'selection_session.dart';

_MouseTarget _mouseTarget(InteractionRegion value) =>
    (send: value.onMouseInput, readVirtualMods: value.readVirtualMods);

typedef _MouseTarget = ({
  ValueChanged<MouseInput> send,
  ValueGetter<Mods> readVirtualMods,
});

typedef _SelectionSnapshot = ({Position? start, Position? end, bool rectangle});

/// Owns pointer-sequence arbitration for one terminal view.
///
/// It keeps mouse reporting, selection, link activation, and cancellation on
/// the same pointer identity. Terminal-directed wheel, touch, and trackpad
/// motion is delegated to [ScrollGestureRegion]. All resulting terminal
/// actions cross focused input and selection modules as normalized values.
///
/// Pointer ownership is decided once per sequence. Modifier changes may alter
/// the shape of an active selection, but they do not transfer the sequence to
/// link activation or terminal mouse reporting. Cancellation releases every
/// owned interaction before another pointer can claim it.
@internal
final class InteractionRegion extends StatefulWidget {
  final Widget child;
  final CellMetrics metrics;
  final LinkInteraction links;
  final Color terminalBackground;
  final ScrollPhysics scrollPhysics;
  final SelectionInteraction selection;
  final TerminalGestureSettings settings;
  final ValueGetter<Mods> readVirtualMods;
  final ValueChanged<MouseInput> onMouseInput;
  final ValueChanged<int> onViewportRowChanged;
  final ValueChanged<ScrollInput> onScrollInput;
  final ValueChanged<ActivatedLink>? onLinkActivate;
  final ValueListenable<TerminalInteractionState> interaction;

  const InteractionRegion({
    super.key,
    this.onLinkActivate,
    required this.child,
    required this.links,
    required this.metrics,
    required this.selection,
    required this.interaction,
    required this.onMouseInput,
    required this.onScrollInput,
    required this.readVirtualMods,
    required this.terminalBackground,
    required this.onViewportRowChanged,
    this.settings = const TerminalGestureSettings(),
    this.scrollPhysics = const ClampingScrollPhysics(),
  });

  @override
  State<InteractionRegion> createState() => _InteractionRegionState();
}

final class _InteractionRegionState extends State<InteractionRegion> {
  static const _mouseButtons = <int, MouseButton>{
    kPrimaryMouseButton: .left,
    kMiddleMouseButton: .middle,
    kSecondaryMouseButton: .right,
    kBackMouseButton: .eight,
    kForwardMouseButton: .nine,
  };
  static const _supportedMouseButtons =
      kPrimaryMouseButton |
      kMiddleMouseButton |
      kSecondaryMouseButton |
      kBackMouseButton |
      kForwardMouseButton;

  final _activePointers = <int, _TrackedPointer>{};
  _DragState? _drag;
  int? _interactionPointer;
  Duration? _interactionTimeStamp;
  var _linkPressActive = false;
  Position? _pressCell;
  var _selectionGestureUpdate = false;
  var _selectionHandleDragActive = false;
  _SelectionSnapshot? _visibleHandleSelectionSnapshot;
  var _selectionHandlesVisible = false;
  var _terminalDragActive = false;
  var _terminalOwnsInteraction = false;

  Mods get _currentMods => readPointerModifiers(widget.readVirtualMods());

  @override
  Widget build(BuildContext context) {
    final interaction = Listener(
      behavior: HitTestBehavior.opaque,
      onPointerDown: _handleTrackedDown,
      onPointerMove: _handleTrackedMove,
      onPointerHover: _handleTrackedHover,
      onPointerUp: _handleTrackedUp,
      onPointerCancel: _handleTrackedCancel,
      child: ScrollGestureRegion(
        metrics: widget.metrics,
        readVirtualMods: widget.readVirtualMods,
        onScrollInput: widget.onScrollInput,
        physics: widget.scrollPhysics,
        interaction: widget.interaction,
        onScrollStart: _handleScrollStart,
        child: PrimitiveGestureDetector(
          onTapDown: _handleTapDown,
          onTapUp: _handleTapUp,
          onDragStart: _handleDragStart,
          onDragUpdate: _handleDragUpdate,
          onDragEnd: _endDrag,
          onLongPressStart: _handleLongPressStart,
          onLongPressMoveUpdate: _handleLongPressMoveUpdate,
          onLongPressUp: _endDrag,
          child: widget.child,
        ),
      ),
    );
    return Stack(
      clipBehavior: .none,
      children: [
        interaction,
        Positioned.fill(
          child: TerminalSelectionHandles(
            selection: widget.selection,
            readVirtualMods: widget.readVirtualMods,
            onViewportRowChanged: widget.onViewportRowChanged,
            metrics: widget.metrics,
            visible:
                _selectionHandlesVisible &&
                widget.settings.touchSelectionHandles,
            magnifierConfiguration: widget.settings.magnifierConfiguration,
            onDragStateChanged: (active) => _selectionHandleDragActive = active,
            terminalBackground: widget.terminalBackground,
            blockSelectionModifier: widget.settings.blockSelectionModifier,
          ),
        ),
      ],
    );
  }

  @override
  void didUpdateWidget(InteractionRegion oldWidget) {
    super.didUpdateWidget(oldWidget);
    final selectionChanged = widget.selection != oldWidget.selection;
    final inputChanged =
        widget.readVirtualMods != oldWidget.readVirtualMods ||
        widget.onMouseInput != oldWidget.onMouseInput ||
        widget.onScrollInput != oldWidget.onScrollInput;
    if (selectionChanged) {
      oldWidget.selection.removeListener(_handleSelectionChanged);
      widget.selection.addListener(_handleSelectionChanged);
      _interactionPointer = null;
      _interactionTimeStamp = null;
      _terminalDragActive = false;
      _terminalOwnsInteraction = false;
    }
    if (widget.links != oldWidget.links && _linkPressActive) {
      _linkPressActive = false;
      oldWidget.links.cancel();
    }
    if (widget.metrics != oldWidget.metrics ||
        selectionChanged ||
        inputChanged) {
      _selectionHandleDragActive = false;
      _visibleHandleSelectionSnapshot = null;
      _selectionHandlesVisible = false;
      final selection = selectionChanged
          ? oldWidget.selection
          : widget.selection;
      _cancelSelectionInteraction(selection);
      if (!selectionChanged && !inputChanged) widget.selection.invalidate();
    }
    if (inputChanged) {
      _releaseTrackedPointers();
    }
    if (!widget.settings.touchSelectionHandles) {
      _visibleHandleSelectionSnapshot = null;
      _selectionHandlesVisible = false;
    }
  }

  @override
  void dispose() {
    widget.selection.removeListener(_handleSelectionChanged);
    _cancelSelectionInteraction(widget.selection);
    _releaseTrackedPointers();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    widget.selection.addListener(_handleSelectionChanged);
  }

  void _autoScrollTick() {
    if (Scrollable.maybeOf(context) == null) {
      _stopAutoScroll();
      return;
    }

    final drag = _drag;
    if (drag == null) {
      _stopAutoScroll();
      return;
    }

    _updateSelection(
      () => widget.selection.handleAutoscroll(
        SelectionPointerInput(
          pixelX: drag.localPosition.dx,
          pixelY: drag.localPosition.dy,
          rectangle: drag.lastRectangle,
        ),
      ),
    );
  }

  MouseButton? _buttonForDownEvent(PointerDownEvent event) {
    return switch (event.kind) {
      .touch => .left,
      .mouse => _mouseButtonForBit(
        smallestButton(event.buttons & _supportedMouseButtons),
      ),
      .stylus || .invertedStylus => _stylusButtonForMask(event.buttons),
      _ => null,
    };
  }

  void _cancelLinkPress() {
    if (!_linkPressActive) return;
    _linkPressActive = false;
    widget.links.cancel();
  }

  void _cancelSelectionInteraction(
    SelectionInteraction selection, {
    bool clearSelection = false,
  }) {
    if (clearSelection || _drag != null || _pressCell != null) {
      selection.cancelGesture();
    }
    _cancelLinkPress();
    _clearDrag();
    _pressCell = null;
  }

  void _cancelSelectionPress() {
    if (_pressCell == null) return;
    widget.selection.cancelGesture();
    _pressCell = null;
  }

  void _clearDrag() {
    if (_drag == null) return;
    HardwareKeyboard.instance.removeHandler(_handleModifierKey);
    _stopAutoScroll();
    _drag = null;
  }

  void _endDrag() {
    if (_terminalDragActive) {
      _terminalDragActive = false;
      _terminalOwnsInteraction = false;
      return;
    }
    final drag = _drag;
    if (drag == null) return;
    _releaseSelectionPress(drag.cell);
    _clearDrag();
    _cancelLinkPress();
    _terminalOwnsInteraction = false;
  }

  void _handleDragStart(DragStartDetails details) {
    Focus.maybeOf(context)?.requestFocus();
    _cancelLinkPress();
    if (_terminalOwnsInteraction) {
      _terminalDragActive = true;
      return;
    }
    if (!widget.settings.dragSelection) {
      _cancelSelectionPress();
      return;
    }

    _startDrag(
      details.localPosition,
      beginPress: _pressCell == null,
      timeStamp: details.sourceTimeStamp ?? _interactionTimeStamp,
    );
  }

  void _handleDragUpdate(DragUpdateDetails details) {
    if (_drag != null) _updateDrag(details.localPosition);
  }

  void _handleLongPressMoveUpdate(LongPressMoveUpdateDetails details) {
    if (_drag != null) _updateDrag(details.localPosition);
  }

  void _handleLongPressStart(LongPressStartDetails details) {
    Focus.maybeOf(context)?.requestFocus();
    if (_terminalOwnsInteraction) return;
    if (!widget.settings.longPressSelection) {
      _cancelSelectionPress();
      return;
    }
    _startDrag(
      details.localPosition,
      rectangle: widget.settings.longPressSelectionShape == .rectangle,
      beginPress: _pressCell == null,
      timeStamp: _interactionTimeStamp,
    );
    if (widget.settings.touchSelectionHandles && !_selectionHandlesVisible) {
      _visibleHandleSelectionSnapshot = _selectionSnapshotOf(
        widget.selection.selection,
      );
      setState(() => _selectionHandlesVisible = true);
    }
  }

  bool _handleModifierKey(KeyEvent _) {
    final drag = _drag;
    if (drag != null) _updateDrag(drag.localPosition);
    return false;
  }

  void _handleScrollStart(PointerDeviceKind kind) {
    _hideSelectionHandles();
    _cancelSelectionInteraction(widget.selection, clearSelection: true);
    if (kind == .touch) {
      Focus.maybeOf(context)?.requestFocus();
      _activePointers.removeWhere((_, pointer) => pointer.kind == .touch);
    }
  }

  void _handleSelectionChanged() {
    if (!_selectionHandlesVisible) return;
    final selectionSnapshot = _selectionSnapshotOf(widget.selection.selection);
    if (_selectionGestureUpdate || _selectionHandleDragActive) {
      _visibleHandleSelectionSnapshot = selectionSnapshot;
      return;
    }
    if (selectionSnapshot != _visibleHandleSelectionSnapshot) {
      _hideSelectionHandles();
    }
  }

  void _handleSelectionPress(Offset position, Duration? timeStamp) {
    final settings = widget.settings;
    final cell = widget.metrics.cellAt(position);
    _updateSelection(
      () => widget.selection.handlePress(
        SelectionPressInput(
          pixelX: position.dx,
          pixelY: position.dy,
          behaviors: settings.selectionBehaviors,
          wordBoundaries: settings.wordBoundaries,
          repeatDistance: kDoubleTapSlop,
          repeatInterval: kDoubleTapTimeout,
          timeStamp: timeStamp ?? Duration.zero,
          fullWidthLine: settings.lineSelectMode == .full,
        ),
      ),
    );
    _pressCell = cell;
  }

  void _handleTapDown(TapDownDetails details, Duration timeStamp) {
    _hideSelectionHandles();
    Focus.maybeOf(context)?.requestFocus();
    if (_terminalOwnsInteraction) return;
    if (widget.links.handlePress(
      localPosition: details.localPosition,
      metrics: widget.metrics,
      pointerKind: details.kind ?? .mouse,
      virtualMods: widget.readVirtualMods(),
    )) {
      _linkPressActive = true;
      _cancelSelectionPress();
      return;
    }
    _handleSelectionPress(details.localPosition, timeStamp);
  }

  void _handleTapUp(TapUpDetails details) {
    if (_linkPressActive) {
      _linkPressActive = false;
      final link = widget.links.handleRelease(
        localPosition: details.localPosition,
        metrics: widget.metrics,
      );
      if (link != null) widget.onLinkActivate?.call(link);
      _terminalOwnsInteraction = false;
      return;
    }
    if (_terminalOwnsInteraction) {
      _terminalOwnsInteraction = false;
      return;
    }
    if (_pressCell == null && _isMouseTracked()) {
      return;
    }
    _releaseSelectionPress(widget.metrics.cellAt(details.localPosition));
  }

  void _handleTrackedCancel(PointerCancelEvent event) {
    final pointer = _activePointers[event.pointer];
    if (pointer != null && pointer.kind != .touch) {
      _releaseTrackedPointer(event.pointer, event.localPosition);
    } else {
      _activePointers.remove(event.pointer);
    }
    if (_interactionPointer != event.pointer) return;
    _interactionPointer = null;
    _interactionTimeStamp = null;
    _terminalDragActive = false;
    _terminalOwnsInteraction = false;
    _cancelSelectionPress();
    _cancelLinkPress();
    _clearDrag();
  }

  void _handleTrackedDown(PointerDownEvent event) {
    if (_activePointers.containsKey(event.pointer)) return;
    // A modified click on a link opens the link even when the application
    // tracks the mouse; the tap handler then claims it as a link press.
    final tracked = _isMouseTracked() && !_linkClaimsPress(event);
    final button = tracked ? _buttonForDownEvent(event) : null;
    if (_interactionPointer == null) {
      _interactionPointer = event.pointer;
      _interactionTimeStamp = event.timeStamp;
      _terminalOwnsInteraction = button != null;
    }
    if (!tracked) return;
    if (button == null) return;
    if (event.kind == .touch && _interactionPointer != event.pointer) return;

    final pointer = _TrackedPointer(
      button: button,
      buttons: 0,
      kind: event.kind,
      position: event.localPosition,
      tapCandidate: event.kind == .touch,
      target: _mouseTarget(widget),
    );
    _activePointers[event.pointer] = pointer;
    if (event.kind == .mouse) {
      _updateMouseButtons(pointer, event.buttons, event.localPosition);
      return;
    }
    if (event.kind == .stylus || event.kind == .invertedStylus) {
      _updateStylusButton(pointer, event.buttons, event.localPosition);
    }
  }

  void _handleTrackedHover(PointerHoverEvent event) {
    if (!_isMouseTracked()) return;
    if (!_isHoverKind(event.kind)) return;
    _sendMouseEvent(.motion, event.localPosition, target: _mouseTarget(widget));
  }

  void _handleTrackedMove(PointerMoveEvent event) {
    final pointer = _activePointers[event.pointer];
    if (pointer == null) return;
    if (pointer.tapCandidate &&
        (event.localPosition - pointer.downPosition).distance > kTouchSlop) {
      pointer.tapCandidate = false;
    }
    final moved = pointer.position != event.localPosition;
    if (pointer.kind == .mouse) {
      _updateMouseButtons(pointer, event.buttons, event.localPosition);
      if (!moved) return;
    } else if (pointer.kind == .stylus || pointer.kind == .invertedStylus) {
      _updateStylusButton(pointer, event.buttons, event.localPosition);
      if (!moved) return;
    } else {
      pointer.position = event.localPosition;
    }
    if (pointer.kind == .touch) return;
    _sendMouseEvent(
      .motion,
      event.localPosition,
      button: pointer.buttons == 0 ? null : pointer.button,
      target: pointer.target,
    );
  }

  void _handleTrackedUp(PointerUpEvent event) {
    _releaseTrackedPointer(event.pointer, event.localPosition);
    if (_interactionPointer == event.pointer) {
      _interactionPointer = null;
      _interactionTimeStamp = null;
    }
  }

  void _hideSelectionHandles() {
    if (!_selectionHandlesVisible) return;
    _visibleHandleSelectionSnapshot = null;
    setState(() => _selectionHandlesVisible = false);
  }

  bool _isBlockModifierPressed() {
    return isSelectionModifierPressed(
      widget.settings.blockSelectionModifier,
      _currentMods,
    );
  }

  bool _isHoverKind(PointerDeviceKind kind) => switch (kind) {
    .mouse || .stylus || .invertedStylus => true,
    _ => false,
  };

  bool _isMouseTracked() {
    return widget.interaction.value.mouseTracking != .none &&
        !HardwareKeyboard.instance.isShiftPressed &&
        !widget.readVirtualMods().hasShift;
  }

  bool _linkClaimsPress(PointerDownEvent event) {
    if (event.kind != .mouse) return false;
    return widget.links.claimsModifiedPress(
      localPosition: event.localPosition,
      metrics: widget.metrics,
      virtualMods: widget.readVirtualMods(),
    );
  }

  MouseButton? _mouseButtonForBit(int button) => _mouseButtons[button];

  void _releaseSelectionPress([Position? cell]) {
    final releaseCell = cell ?? _pressCell;
    if (releaseCell == null) return;
    _updateSelection(() => widget.selection.handleRelease(releaseCell));
    _pressCell = null;
  }

  void _releaseTrackedPointer(int pointerId, Offset position) {
    final pointer = _activePointers[pointerId];
    if (pointer == null) return;
    pointer.position = position;
    if (pointer.kind == .mouse) {
      _updateMouseButtons(pointer, 0, position);
    } else if (pointer.kind == .stylus || pointer.kind == .invertedStylus) {
      _updateStylusButton(pointer, 0, position);
    } else if (pointer.kind == .touch && pointer.tapCandidate) {
      pointer.buttons = kPrimaryButton;
      _sendMouseEvent(
        .press,
        position,
        button: pointer.button,
        target: pointer.target,
      );
      pointer.buttons = 0;
      _sendMouseEvent(
        .release,
        position,
        button: pointer.button,
        target: pointer.target,
      );
    }
    _activePointers.remove(pointerId);
  }

  void _releaseTrackedPointers() {
    _activePointers.removeWhere((_, pointer) => pointer.kind == .touch);
    while (_activePointers.isNotEmpty) {
      final entry = _activePointers.entries.first;
      _releaseTrackedPointer(entry.key, entry.value.position);
    }
  }

  _SelectionSnapshot? _selectionSnapshotOf(Selection? selection) {
    if (selection == null) return null;
    return (
      start: selection.start.positionIn(.viewport),
      end: selection.end.positionIn(.viewport),
      rectangle: selection.rectangle,
    );
  }

  void _sendMouseEvent(
    MouseAction action,
    Offset position, {
    MouseButton? button,
    required _MouseTarget target,
  }) {
    target.send(
      MouseInput(
        action: action,
        anyButtonPressed: _activePointers.values.any(
          (pointer) => pointer.buttons != 0,
        ),
        button: button,
        mods: readPointerModifiers(target.readVirtualMods()),
        pixelX: position.dx,
        pixelY: position.dy,
      ),
    );
  }

  void _startAutoScroll() {
    if (Scrollable.maybeOf(context) == null) return;
    widget.selection.startAutoscroll(.pointer, _autoScrollTick);
  }

  void _startDrag(
    Offset position, {
    bool rectangle = false,
    bool beginPress = false,
    required Duration? timeStamp,
  }) {
    final cell = widget.metrics.cellAt(position);
    final block = rectangle || _isBlockModifierPressed();
    if (_drag == null) HardwareKeyboard.instance.addHandler(_handleModifierKey);
    _drag = _DragState(
      cell,
      position,
      fixedRectangle: rectangle,
      lastRectangle: block,
    );
    if (beginPress) _handleSelectionPress(position, timeStamp);
  }

  void _stopAutoScroll() {
    widget.selection.stopAutoscroll(.pointer);
  }

  MouseButton? _stylusButtonForMask(int buttons) {
    const supported =
        kStylusContact | kPrimaryStylusButton | kSecondaryStylusButton;
    if (buttons & ~supported != 0) return null;
    final barrel = buttons & (kPrimaryStylusButton | kSecondaryStylusButton);
    return switch (barrel) {
      0 when buttons == kStylusContact => .left,
      kPrimaryStylusButton => .right,
      kSecondaryStylusButton => .middle,
      _ => null,
    };
  }

  void _updateDrag(Offset position) {
    final drag = _drag;
    if (drag == null) return;
    final cell = widget.metrics.cellAt(position);
    drag.cell = cell;
    drag.localPosition = position;

    final visibleRows = widget.selection.rows;
    if (visibleRows > 0) {
      if (cell.row < 0 || cell.row >= visibleRows) {
        _startAutoScroll();
      } else {
        _stopAutoScroll();
      }
    }

    final clampedRow = visibleRows > 0
        ? cell.row.clamp(0, visibleRows - 1)
        : cell.row;
    final clampedCell = Position(row: clampedRow, col: cell.col);
    final rectangle = drag.fixedRectangle || _isBlockModifierPressed();
    if (clampedCell == drag.lastCell && rectangle == drag.lastRectangle) {
      return;
    }
    drag.lastCell = clampedCell;
    drag.lastRectangle = rectangle;

    _updateSelection(
      () => widget.selection.handleDrag(
        SelectionPointerInput(
          pixelX: position.dx,
          pixelY: position.dy,
          rectangle: rectangle,
        ),
      ),
    );
  }

  void _updateMouseButtons(
    _TrackedPointer pointer,
    int buttons,
    Offset position,
  ) {
    final nextButtons = buttons & _supportedMouseButtons;
    final previousButtons = pointer.buttons;
    final removed = previousButtons & ~nextButtons;
    final added = nextButtons & ~previousButtons;
    pointer.buttons = nextButtons;

    for (final entry in _mouseButtons.entries) {
      if (removed & entry.key == 0) continue;
      _sendMouseEvent(
        .release,
        position,
        button: entry.value,
        target: pointer.target,
      );
    }

    for (final entry in _mouseButtons.entries) {
      if (added & entry.key == 0) continue;
      pointer.button = entry.value;
      _sendMouseEvent(
        .press,
        position,
        button: entry.value,
        target: pointer.target,
      );
    }

    if (pointer.buttons != 0 &&
        !_mouseButtons.entries.any(
          (entry) =>
              entry.value == pointer.button && pointer.buttons & entry.key != 0,
        )) {
      pointer.button = _mouseButtonForBit(smallestButton(pointer.buttons))!;
    }
    pointer.position = position;
  }

  void _updateSelection(VoidCallback update) {
    _selectionGestureUpdate = true;
    try {
      update();
    } finally {
      _selectionGestureUpdate = false;
    }
  }

  void _updateStylusButton(
    _TrackedPointer pointer,
    int buttons,
    Offset position,
  ) {
    final previousButton = pointer.buttons == 0 ? null : pointer.button;
    final nextButton = _stylusButtonForMask(buttons);
    pointer.buttons = nextButton == null ? 0 : kPrimaryButton;

    if (previousButton != nextButton) {
      if (previousButton != null) {
        _sendMouseEvent(
          .release,
          position,
          button: previousButton,
          target: pointer.target,
        );
      }
      if (nextButton != null) {
        pointer.button = nextButton;
        _sendMouseEvent(
          .press,
          position,
          button: nextButton,
          target: pointer.target,
        );
      }
    }
    pointer.position = position;
  }
}

final class _DragState {
  final bool fixedRectangle;
  Position cell;
  Position? lastCell;
  bool lastRectangle;
  Offset localPosition;

  _DragState(
    this.cell,
    this.localPosition, {
    required this.fixedRectangle,
    required this.lastRectangle,
  });
}

final class _TrackedPointer {
  final Offset downPosition;
  final PointerDeviceKind kind;
  final _MouseTarget target;
  MouseButton button;
  int buttons;
  Offset position;
  bool tapCandidate;

  _TrackedPointer({
    required this.button,
    required this.buttons,
    required this.kind,
    required this.position,
    required this.tapCandidate,
    required this.target,
  }) : downPosition = position;
}
