import 'dart:async';

import 'package:flutter/foundation.dart' hide Key;
import 'package:libghostty/libghostty.dart';

import '../foundation/surface_geometry.dart';

/// A normalized terminal selection pointer update.
@immutable
final class SelectionPointerInput {
  /// The horizontal logical pixel offset from the terminal grid origin.
  final double pixelX;

  /// The vertical logical pixel offset from the terminal grid origin.
  final double pixelY;

  /// Whether the selection is rectangular.
  final bool rectangle;

  const SelectionPointerInput({
    required this.pixelX,
    required this.pixelY,
    required this.rectangle,
  });
}

/// Identifies the owner policy for the shared selection autoscroll timer.
enum SelectionAutoscrollPolicy { pointer, handle }

/// Identifies the stored endpoint changed by a touch selection handle.
@internal
enum SelectionEndpoint { start, end }

/// Owns selection gesture continuation for one attached terminal view.
@internal
final class SelectionInteraction extends ChangeNotifier {
  final SelectionSession _selection;
  final SelectionGesture _gesture;
  final SelectionGestureEvent _drag = .drag();
  final SelectionGestureEvent _press = .press();
  final SelectionGestureEvent _release = .release();
  final SelectionGestureEvent _autoscroll = .autoscrollTick();
  List<int>? _wordBoundaryCodepoints;
  Timer? _autoscrollTimer;
  SelectionAutoscrollPolicy? _autoscrollPolicy;
  var _cellHeight = 0.0;
  var _cellWidth = 0.0;
  var _columns = 0;
  var _disposed = false;
  var _rows = 0;
  SurfaceGeometry? _geometry;

  SelectionInteraction._(this._selection)
    : _gesture = SelectionGesture(_selection._terminal);

  int get columns =>
      _columns > 0 ? _columns : _selection._terminal.geometry.cols;

  SurfaceGeometry? get geometry => _geometry;

  int get rows => _rows > 0 ? _rows : _selection._terminal.geometry.rows;

  Scrollbar get scrollbar => _selection._terminal.scrollbar;

  Selection? get selection => _selection._terminal.selection;

  void cancelGesture() {
    if (_disposed) return;
    stopAutoscroll();
    _gesture.reset();
    _selection._set(null, clearIfNull: true);
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    try {
      stopAutoscroll();
      _release.dispose();
      _autoscroll.dispose();
      _drag.dispose();
      _press.dispose();
      _gesture.dispose();
    } finally {
      _selection._interactionDisposed(this);
      super.dispose();
    }
  }

  void handleAutoscroll(SelectionPointerInput event) {
    _checkNotDisposed();
    if (_columns <= 0 || _rows <= 0) return;
    _selection._set(_applyAutoscroll(event));
  }

  void handleDrag(SelectionPointerInput event) {
    _checkNotDisposed();
    final ref = _viewportRef(_cellAt(event.pixelX, event.pixelY));
    if (ref == null) return;
    _selection._set(_applyDrag(event, ref));
  }

  void handlePress(SelectionPressInput event) {
    _checkNotDisposed();
    final ref = _viewportRef(_cellAt(event.pixelX, event.pixelY));
    if (ref == null) {
      _selection._set(null, clearIfNull: true);
      return;
    }

    var selection = _applyPress(event, ref);
    if (selection != null &&
        event.fullWidthLine &&
        _gesture.state.behavior == .line) {
      selection = _fullWidthLine(selection);
    }
    _selection._set(selection, clearIfNull: true);
  }

  void handleRelease(Position cell) {
    _checkNotDisposed();
    _release.setRef(_viewportRef(cell));
    _selection._set(_gesture.apply(_release));
  }

  void invalidate() {
    _checkNotDisposed();
    stopAutoscroll();
    resetGesture();
    _selection.invalidate();
  }

  void resetGesture() {
    if (_disposed) return;
    _wordBoundaryCodepoints = null;
    _gesture.reset();
  }

  /// Starts the shared selection autoscroll loop for [policy].
  ///
  /// Only one policy may own the loop at a time. Starting a different policy
  /// replaces the previous owner; starting the same policy is idempotent.
  void startAutoscroll(
    SelectionAutoscrollPolicy policy,
    VoidCallback callback,
  ) {
    _checkNotDisposed();
    if (_autoscrollPolicy == policy && _autoscrollTimer != null) return;
    stopAutoscroll();
    _autoscrollPolicy = policy;
    _autoscrollTimer = Timer.periodic(
      const Duration(milliseconds: 50),
      (_) => callback(),
    );
  }

  /// Stops autoscroll when [policy] currently owns the loop.
  void stopAutoscroll([SelectionAutoscrollPolicy? policy]) {
    if (policy != null && _autoscrollPolicy != policy) return;
    _autoscrollTimer?.cancel();
    _autoscrollTimer = null;
    _autoscrollPolicy = null;
  }

  void updateEndpoint(
    SelectionEndpoint endpoint,
    Position cell, {
    bool? rectangle,
  }) {
    _checkNotDisposed();
    final selection = _selection._terminal.selection;
    if (selection == null) return;
    final ref = _viewportRef(cell);
    if (ref == null) return;

    resetGesture();
    _selection._set(
      Selection.fromRefs(
        start: endpoint == .start ? ref : selection.start,
        end: endpoint == .end ? ref : selection.end,
        rectangle: rectangle ?? selection.rectangle,
      ),
    );
  }

  void updateGeometry(SurfaceGeometry geometry) {
    _checkNotDisposed();
    if (_geometry == geometry) return;
    stopAutoscroll();
    _geometry = geometry;
    _columns = geometry.cols;
    _rows = geometry.rows;
    _cellWidth = geometry.cellWidth;
    _cellHeight = geometry.cellHeight;
  }

  Selection? _applyAutoscroll(SelectionPointerInput input) {
    _autoscroll
      ..setViewport(_clampViewportPoint(_cellAt(input.pixelX, input.pixelY)))
      ..setPosition(input.pixelX, input.pixelY)
      ..setRectangle(value: input.rectangle)
      ..setGeometry(_gestureGeometry());
    _setWordBoundaryCodepoints(_autoscroll);
    return _gesture.apply(_autoscroll);
  }

  Selection? _applyDrag(SelectionPointerInput input, GridRef ref) {
    _drag
      ..setRef(ref)
      ..setPosition(input.pixelX, input.pixelY)
      ..setRectangle(value: input.rectangle)
      ..setGeometry(_gestureGeometry());
    _setWordBoundaryCodepoints(_drag);
    return _gesture.apply(_drag);
  }

  Selection? _applyPress(SelectionPressInput input, GridRef ref) {
    _wordBoundaryCodepoints = input.wordBoundaries?.runes.toList(
      growable: false,
    );
    _press
      ..setRef(ref)
      ..setPosition(input.pixelX, input.pixelY)
      ..setBehaviors(input.behaviors)
      ..setRepeatDistance(input.repeatDistance)
      ..setRepeatIntervalNs(input.repeatInterval.inMicroseconds * 1000)
      ..setTimeNs(input.timeStamp.inMicroseconds * 1000);
    _setWordBoundaryCodepoints(_press);
    return _gesture.apply(_press);
  }

  Position _cellAt(double pixelX, double pixelY) {
    return Position(
      row: _cellHeight > 0 ? (pixelY / _cellHeight).floor() : 0,
      col: _cellWidth > 0 ? (pixelX / _cellWidth).floor() : 0,
    );
  }

  void _checkNotDisposed() {
    if (_disposed) throw StateError('SelectionInteraction is disposed.');
  }

  Position _clampViewportPoint(Position position) {
    return Position(
      row: position.row.clamp(0, _rows - 1),
      col: position.col.clamp(0, _columns - 1),
    );
  }

  void _ensureGridSize() {
    if (_rows > 0 && _columns > 0) return;
    final geometry = _selection._terminal.geometry;
    _rows = geometry.rows;
    _columns = geometry.cols;
  }

  Selection _fullWidthLine(Selection selection) {
    final start = selection.start.positionIn(.viewport);
    final end = selection.end.positionIn(.viewport);
    if (start == null || end == null) return selection;
    _ensureGridSize();
    if (_columns <= 0) return selection;
    return Selection.fromRefs(
      start: .at(
        _selection._terminal,
        Position(row: start.row, col: 0),
        pointTag: .viewport,
      ),
      end: .at(
        _selection._terminal,
        Position(row: end.row, col: _columns - 1),
        pointTag: .viewport,
      ),
    );
  }

  SelectionGestureGeometry _gestureGeometry() {
    _ensureGridSize();
    return SelectionGestureGeometry(
      columns: _columns <= 0 ? 1 : _columns,
      cellWidth: _cellWidth <= 0 ? 1 : _cellWidth.round(),
      paddingLeft: 0,
      screenHeight: _cellHeight <= 0
          ? 1
          : (_cellHeight * (_rows <= 0 ? 1 : _rows)).round(),
    );
  }

  void _notifySelectionChanged() => notifyListeners();

  void _setWordBoundaryCodepoints(SelectionGestureEvent event) {
    event.setWordBoundaryCodepoints(_wordBoundaryCodepoints);
  }

  GridRef? _viewportRef(Position position) {
    _ensureGridSize();
    if (_rows <= 0 || _columns <= 0) return null;
    return .at(
      _selection._terminal,
      _clampViewportPoint(position),
      pointTag: .viewport,
    );
  }
}

/// A normalized terminal selection press.
@immutable
final class SelectionPressInput {
  /// The horizontal logical pixel offset from the terminal grid origin.
  final double pixelX;

  /// The vertical logical pixel offset from the terminal grid origin.
  final double pixelY;

  /// Selection behavior for single, double, and triple presses.
  final SelectionGestureBehaviors behaviors;

  /// Characters that split words during word selection.
  ///
  /// `null` uses the terminal defaults; an empty string supplies an explicit
  /// empty boundary set.
  final String? wordBoundaries;

  /// Maximum logical-pixel distance between repeated presses.
  final double repeatDistance;

  /// Maximum interval between repeated presses.
  final Duration repeatInterval;

  /// Monotonic source-event time used to classify repeated presses.
  final Duration timeStamp;

  /// Whether line selection extends across the complete terminal row.
  final bool fullWidthLine;

  const SelectionPressInput({
    required this.pixelX,
    required this.pixelY,
    required this.behaviors,
    required this.wordBoundaries,
    required this.repeatDistance,
    required this.repeatInterval,
    required this.timeStamp,
    required this.fullWidthLine,
  });

  @override
  int get hashCode => Object.hash(
    pixelX,
    pixelY,
    behaviors,
    wordBoundaries,
    repeatDistance,
    repeatInterval,
    timeStamp,
    fullWidthLine,
  );

  @override
  bool operator ==(Object other) {
    return other is SelectionPressInput &&
        other.pixelX == pixelX &&
        other.pixelY == pixelY &&
        other.behaviors == behaviors &&
        other.wordBoundaries == wordBoundaries &&
        other.repeatDistance == repeatDistance &&
        other.repeatInterval == repeatInterval &&
        other.timeStamp == timeStamp &&
        other.fullWidthLine == fullWidthLine;
  }
}

/// Owns the canonical selection state for one terminal session.
final class SelectionSession {
  final Terminal _terminal;
  final VoidCallback? _beginMutation;
  final VoidCallback? _endMutation;
  final VoidCallback _notifyChanged;
  SelectionInteraction? _interaction;

  SelectionSession(
    this._terminal,
    this._notifyChanged, [
    this._beginMutation,
    this._endMutation,
  ]);

  bool get hasSelection => _terminal.selection != null;

  void clear({required bool notify}) {
    if (_terminal.selection == null) return;
    _interaction?.resetGesture();
    _set(null, clearIfNull: true, notify: notify);
  }

  SelectionInteraction createInteraction() {
    if (_interaction != null) {
      throw StateError('SelectionSession already has selection input.');
    }
    final interaction = SelectionInteraction._(this);
    _interaction = interaction;
    return interaction;
  }

  void disposeInteraction() => _interaction?.dispose();

  bool extend(Key key) {
    final SelectionAdjust? adjustment = switch (key) {
      .arrowRight => .right,
      .arrowLeft => .left,
      .arrowUp => .up,
      .arrowDown => .down,
      _ => null,
    };
    if (adjustment == null) return false;
    final selection = _terminal.selection;
    if (selection == null) return false;
    _set(selection.adjust(adjustment));
    return true;
  }

  void invalidate() => clear(notify: false);

  @internal
  void notifyNativeSelectionChanged() =>
      _interaction?._notifySelectionChanged();

  void selectAll() => _set(_terminal.selectAll());

  String selectedText({FormatterFormat format = .plain}) {
    final selection = _terminal.selection;
    if (selection == null) return '';
    return _terminal.formatSelection(
          format: format,
          unwrap: !selection.rectangle,
          selection: selection,
        ) ??
        '';
  }

  void selectRange({
    required Position start,
    required Position end,
    required PointTag pointTag,
    required bool rectangle,
  }) {
    _set(
      .fromRefs(
        start: .at(_terminal, start, pointTag: pointTag),
        end: .at(_terminal, end, pointTag: pointTag),
        rectangle: rectangle,
      ),
    );
  }

  void updateGeometry(SurfaceGeometry geometry) {
    _interaction?.updateGeometry(geometry);
  }

  void _interactionDisposed(SelectionInteraction interaction) {
    if (identical(_interaction, interaction)) _interaction = null;
  }

  void _set(Selection? value, {bool clearIfNull = false, bool notify = true}) {
    if (value == null) {
      if (!clearIfNull || _terminal.selection == null) return;
    } else {
      final current = _terminal.selection;
      if (current != null && current.equal(value)) return;
    }

    _setTerminalSelection(value);
    if (notify) {
      _notifyChanged();
      _interaction?._notifySelectionChanged();
    }
  }

  void _setTerminalSelection(Selection? value) {
    _beginMutation?.call();
    try {
      _terminal.selection = value;
    } finally {
      _endMutation?.call();
    }
  }
}
