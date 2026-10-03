import 'package:flutter/foundation.dart'
    show
        TargetPlatform,
        ValueGetter,
        ValueListenable,
        defaultTargetPlatform,
        kIsWeb;
import 'package:flutter/gestures.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';
import 'package:libghostty/libghostty.dart' show Mods;
import 'package:meta/meta.dart';

import '../foundation.dart';
import 'input_message.dart';
import 'input_modifiers.dart';

typedef _ScrollTarget = ({Offset position, Mods mods, bool reportMouse});

/// Carries one accepted drag into its optional ballistic continuation.
///
/// Keeping both phases in one object preserves the captured terminal target
/// and per-axis momentum without parallel gesture and fling state in the
/// widget. Motion is converted to supported axes before it reaches the router.
final class _ScrollActivity {
  final _ScrollAxis _horizontal;
  final _ScrollAxis _vertical;
  final PointerDeviceKind kind;
  final _ScrollTarget target;
  Duration _elapsed = .zero;
  Offset _position = .zero;
  bool _dragging;
  bool _moved;

  _ScrollActivity({
    required this.kind,
    required this.target,
    required ScrollPhysics physics,
    required Offset carriedVelocity,
    required Duration? timeStamp,
  }) : _horizontal = _ScrollAxis(
         carriedVelocity: physics.carriedMomentum(carriedVelocity.dx),
         motionStartDistanceThreshold: physics.dragStartDistanceMotionThreshold,
         timeStamp: timeStamp,
       ),
       _vertical = _ScrollAxis(
         carriedVelocity: physics.carriedMomentum(carriedVelocity.dy),
         motionStartDistanceThreshold: physics.dragStartDistanceMotionThreshold,
         timeStamp: timeStamp,
       ),
       _dragging = true,
       _moved = false;

  bool get done => _horizontal.done && _vertical.done;

  bool get isDragging => _dragging;

  Offset get velocity {
    final seconds = _seconds(_elapsed);
    return Offset(
      _horizontal.velocityAt(seconds),
      _vertical.velocityAt(seconds),
    );
  }

  Offset advance(Duration elapsed) {
    _elapsed = elapsed;
    final seconds = _seconds(elapsed);
    final position = Offset(
      _horizontal.positionAt(seconds, _position.dx),
      _vertical.positionAt(seconds, _position.dy),
    );
    final delta = position - _position;
    _position = position;
    return delta;
  }

  void dropMomentum() {
    _horizontal.dropMomentum();
    _vertical.dropMomentum();
  }

  bool markMoved(Offset delta) {
    if (_supported(delta) == Offset.zero || _moved) return false;
    _moved = true;
    return true;
  }

  bool startBallistic({
    required ScrollPhysics physics,
    required Offset velocity,
    required Size viewportSize,
    required double devicePixelRatio,
  }) {
    _dragging = false;
    final supported = _supported(velocity);
    _horizontal.startBallistic(
      physics: physics,
      velocity: _horizontal.applyMomentumTo(supported.dx),
      axis: .horizontal,
      viewportDimension: viewportSize.width,
      devicePixelRatio: devicePixelRatio,
    );
    _vertical.startBallistic(
      physics: physics,
      velocity: _vertical.applyMomentumTo(supported.dy),
      axis: .vertical,
      viewportDimension: viewportSize.height,
      devicePixelRatio: devicePixelRatio,
    );
    return !done;
  }

  Offset update(Offset delta, Duration? timeStamp) {
    final supported = _supported(delta);
    return Offset(
      _horizontal.update(supported.dx, timeStamp),
      _vertical.update(supported.dy, timeStamp),
    );
  }

  Offset _supported(Offset delta) {
    return target.reportMouse ? delta : Offset(0, delta.dy);
  }

  static double _seconds(Duration elapsed) {
    return elapsed.inMicroseconds / Duration.microsecondsPerSecond;
  }
}

/// Per-axis motion state matching Flutter's scroll-drag momentum behavior.
final class _ScrollAxis {
  static const _largeThresholdBreakDistance = 24.0;
  static const _motionStoppedThreshold = Duration(milliseconds: 50);

  final double carriedVelocity;
  final double? motionStartDistanceThreshold;
  double? _distanceSinceStop;
  Duration? _lastMovement;
  bool _retainsMomentum;
  Simulation? _simulation;

  _ScrollAxis({
    required this.carriedVelocity,
    required this.motionStartDistanceThreshold,
    required Duration? timeStamp,
  }) : _lastMovement = timeStamp,
       _distanceSinceStop = motionStartDistanceThreshold == null ? null : 0,
       _retainsMomentum = carriedVelocity != 0;

  bool get done => _simulation == null;

  double applyMomentumTo(double replacement) {
    if (!_retainsMomentum ||
        replacement.sign != carriedVelocity.sign ||
        replacement.abs() <=
            carriedVelocity.abs() *
                ScrollDragController.momentumRetainVelocityThresholdFactor) {
      return replacement;
    }
    return replacement + carriedVelocity;
  }

  void dropMomentum() => _retainsMomentum = false;

  double positionAt(double time, double fallback) {
    final simulation = _simulation;
    if (simulation == null) return fallback;
    final position = simulation.x(time);
    if (simulation.isDone(time)) _simulation = null;
    return position;
  }

  void startBallistic({
    required ScrollPhysics physics,
    required double velocity,
    required Axis axis,
    required double viewportDimension,
    required double devicePixelRatio,
  }) {
    _simulation = velocity == 0
        ? null
        : physics.createBallisticSimulation(
            // The terminal consumes deltas instead of using a ScrollPosition.
            // Finite extents and non-zero fallbacks keep Flutter's synthetic
            // scroll metrics valid for detached or zero-sized surfaces.
            FixedScrollMetrics(
              minScrollExtent: -1e9,
              maxScrollExtent: 1e9,
              pixels: 0,
              viewportDimension: viewportDimension > 0 ? viewportDimension : 1,
              axisDirection: axis == .horizontal ? .right : .down,
              devicePixelRatio: devicePixelRatio > 0 ? devicePixelRatio : 1,
            ),
            velocity,
          );
  }

  double update(double delta, Duration? timeStamp) {
    if (delta != 0) _lastMovement = timeStamp;
    _updateMomentum(delta, timeStamp);
    return _applyMotionStartThreshold(delta, timeStamp);
  }

  double velocityAt(double time) {
    final simulation = _simulation;
    if (simulation == null || simulation.isDone(time)) return 0;
    return simulation.dx(time);
  }

  double _applyMotionStartThreshold(double delta, Duration? timeStamp) {
    final threshold = motionStartDistanceThreshold;
    if (timeStamp == null || threshold == null) return delta;
    if (delta == 0) {
      final lastMovement = _lastMovement;
      if (_distanceSinceStop == null &&
          (lastMovement == null ||
              timeStamp - lastMovement > _motionStoppedThreshold)) {
        _distanceSinceStop = 0;
      }
      return 0;
    }
    final distance = _distanceSinceStop;
    if (distance == null) return delta;
    _distanceSinceStop = distance + delta;
    if (_distanceSinceStop!.abs() <= threshold) return 0;
    _distanceSinceStop = null;
    if (delta.abs() > _largeThresholdBreakDistance) return delta;
    final easedDistance = threshold / 3;
    return (delta.abs() < easedDistance ? delta.abs() : easedDistance) *
        delta.sign;
  }

  void _updateMomentum(double delta, Duration? timeStamp) {
    if (!_retainsMomentum || delta != 0) return;
    final lastMovement = _lastMovement;
    if (timeStamp == null ||
        lastMovement == null ||
        timeStamp - lastMovement >
            ScrollDragController.momentumRetainStationaryDurationThreshold) {
      _retainsMomentum = false;
    }
  }
}

enum _ScrollGestureMode { pan, vertical }

/// Owns terminal-directed wheel, touch, and trackpad scrolling.
///
/// This component captures one target for each gesture sequence, quantizes
/// pixel motion into terminal cell steps, and continues flings through
/// Flutter's [ScrollPhysics]. Mouse reporting uses a two-dimensional pan
/// recognizer; alternate-screen key scrolling uses a vertical recognizer so
/// horizontal gestures remain available to ancestor widgets.
@internal
final class ScrollGestureRegion extends StatefulWidget {
  final Widget child;
  final CellMetrics metrics;
  final ScrollPhysics physics;
  final ValueGetter<Mods> readVirtualMods;
  final ValueChanged<ScrollInput> onScrollInput;
  final ValueListenable<TerminalInteractionState> interaction;
  final ValueChanged<PointerDeviceKind> onScrollStart;

  const ScrollGestureRegion({
    super.key,
    required this.metrics,
    required this.physics,
    required this.readVirtualMods,
    required this.onScrollInput,
    required this.interaction,
    required this.onScrollStart,
    required this.child,
  });

  @override
  State<ScrollGestureRegion> createState() => _ScrollGestureRegionState();
}

final class _ScrollGestureRegionState extends State<ScrollGestureRegion>
    with SingleTickerProviderStateMixin {
  static const _macOsDiscreteScrollPixels = 40.0;
  static const _macOsDiscreteVerticalMultiplier = 3.0;

  late final Ticker _ticker;
  _ScrollActivity? _activity;
  _ScrollRemainder? _remainder;

  @override
  Widget build(BuildContext context) {
    return Listener(
      behavior: .opaque,
      onPointerSignal: _handlePointerSignal,
      child: RawGestureDetector(
        behavior: .opaque,
        gestures: <Type, GestureRecognizerFactory>{
          _TwoAxisScrollRecognizer:
              GestureRecognizerFactoryWithHandlers<_TwoAxisScrollRecognizer>(
                () => _TwoAxisScrollRecognizer(debugOwner: this),
                (recognizer) => _configure(recognizer, .pan),
              ),
          _VerticalScrollRecognizer:
              GestureRecognizerFactoryWithHandlers<_VerticalScrollRecognizer>(
                () => _VerticalScrollRecognizer(debugOwner: this),
                (recognizer) => _configure(recognizer, .vertical),
              ),
        },
        child: widget.child,
      ),
    );
  }

  @override
  void didUpdateWidget(ScrollGestureRegion oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.interaction != oldWidget.interaction) {
      oldWidget.interaction.removeListener(_handleInteractionChanged);
      widget.interaction.addListener(_handleInteractionChanged);
    }
    if (widget.onScrollInput != oldWidget.onScrollInput ||
        widget.metrics != oldWidget.metrics ||
        widget.interaction != oldWidget.interaction ||
        widget.physics != oldWidget.physics) {
      _reset();
    }
  }

  @override
  void dispose() {
    widget.interaction.removeListener(_handleInteractionChanged);
    _cancelGesture();
    _ticker.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    _ticker = createTicker(_tick);
    widget.interaction.addListener(_handleInteractionChanged);
  }

  void _beginGesture(PointerEvent event) {
    final carriedVelocity = _activity?.velocity ?? Offset.zero;
    _stopBallistic();
    _activity = _ScrollActivity(
      target: _targetAt(event.localPosition),
      kind: event.kind,
      physics: widget.physics,
      carriedVelocity: carriedVelocity,
      timeStamp: event.timeStamp,
    );
  }

  void _cancelGesture() {
    _activity = null;
    _ticker.stop();
  }

  void _configure(DragGestureRecognizer recognizer, _ScrollGestureMode mode) {
    (recognizer as _ScrollSequence).configureSequence(
      canStart: () => _gestureMode() == mode,
      onPointerStart: _beginGesture,
    );
    final configuration = ScrollConfiguration.of(context);
    recognizer
      ..dragStartBehavior = .down
      ..multitouchDragStrategy = configuration.getMultitouchDragStrategy(
        context,
      )
      ..onUpdate = _updateGesture
      ..onEnd = _endGesture
      ..onCancel = _cancelGesture
      ..minFlingDistance = widget.physics.minFlingDistance
      ..minFlingVelocity = widget.physics.minFlingVelocity
      ..maxFlingVelocity = widget.physics.maxFlingVelocity
      ..velocityTrackerBuilder = configuration.velocityTrackerBuilder(context)
      ..gestureSettings = MediaQuery.maybeGestureSettingsOf(context);
  }

  int _discreteHorizontalTicks(double delta) {
    if (delta == 0) return 0;
    final magnitude = (delta.abs() / _macOsDiscreteScrollPixels).round();
    final ticks = magnitude < 1 ? 1 : magnitude;
    return delta < 0 ? -ticks : ticks;
  }

  double _discreteVerticalTicks(double delta) {
    if (delta == 0) return 0;
    final ticks = delta / _macOsDiscreteScrollPixels;
    return ticks.abs() < 1 ? ticks.sign : ticks;
  }

  void _endGesture(DragEndDetails details) {
    final activity = _activity;
    if (activity == null || !activity.isDragging) return;
    final velocity = -details.velocity.pixelsPerSecond;
    if (activity.markMoved(velocity)) widget.onScrollStart(activity.kind);
    if (!activity.startBallistic(
      physics: widget.physics,
      velocity: velocity,
      viewportSize: context.size ?? Size.zero,
      devicePixelRatio: View.of(context).devicePixelRatio,
    )) {
      _activity = null;
      return;
    }
    _ticker.start();
  }

  _ScrollGestureMode? _gestureMode() {
    final metrics = widget.metrics;
    if ((_activity?.isDragging ?? false) ||
        !widget.physics.allowUserScrolling ||
        !metrics.cellWidth.isFinite ||
        metrics.cellWidth <= 0 ||
        !metrics.cellHeight.isFinite ||
        metrics.cellHeight <= 0) {
      return null;
    }
    if (widget.interaction.value.mouseTracking != .none) {
      return readPointerModifiers(widget.readVirtualMods()).hasShift
          ? null
          : .pan;
    }
    final interaction = widget.interaction.value;
    return interaction.activeScreen == .alternate && interaction.alternateScroll
        ? .vertical
        : null;
  }

  void _handleInteractionChanged() => _reset();

  void _handlePointerSignal(PointerSignalEvent event) {
    if (event is PointerScrollInertiaCancelEvent) {
      _stopBallistic();
      return;
    }
    if (event is! PointerScrollEvent ||
        event.scrollDelta == .zero ||
        _gestureMode() == null) {
      return;
    }
    final target = _targetAt(event.localPosition);
    final delta = _supportedDelta(_normalizePointerScroll(event), target);
    if (delta == Offset.zero) return;
    GestureBinding.instance.pointerSignalResolver.register(
      event,
      (resolvedEvent) => _handleResolvedPointerSignal(
        resolvedEvent,
        delta: delta,
        target: target,
      ),
    );
  }

  void _handleResolvedPointerSignal(
    PointerSignalEvent event, {
    required Offset delta,
    required _ScrollTarget target,
  }) {
    if (event is! PointerScrollEvent) return;
    _stopBallistic();
    widget.onScrollStart(event.kind);
    _route(delta, target);
    event.respond(allowPlatformDefault: false);
  }

  Offset _normalizePointerScroll(PointerScrollEvent event) {
    if (kIsWeb ||
        defaultTargetPlatform != TargetPlatform.macOS ||
        event.kind != PointerDeviceKind.mouse) {
      return event.scrollDelta;
    }

    final delta = event.scrollDelta;
    final metrics = widget.metrics;
    return Offset(
      _discreteHorizontalTicks(delta.dx) * metrics.cellWidth,
      _discreteVerticalTicks(delta.dy) *
          metrics.cellHeight *
          _macOsDiscreteVerticalMultiplier,
    );
  }

  void _reset() {
    _cancelGesture();
    _remainder = null;
  }

  void _route(Offset delta, _ScrollTarget target) {
    final metrics = widget.metrics;
    var remainder = _remainder;
    if (remainder == null || !remainder.shares(target, metrics)) {
      remainder = _ScrollRemainder(target, metrics);
      _remainder = remainder;
    }

    remainder.horizontal += delta.dx;
    remainder.vertical += delta.dy;
    final horizontal = (remainder.horizontal / metrics.cellWidth).truncate();
    final vertical = (remainder.vertical / metrics.cellHeight).truncate();
    if (horizontal != 0) remainder.horizontal -= horizontal * metrics.cellWidth;
    if (vertical != 0) remainder.vertical -= vertical * metrics.cellHeight;
    if (horizontal == 0 && vertical == 0) return;

    widget.onScrollInput(
      ScrollInput(
        horizontal: horizontal,
        mods: target.mods,
        pixelX: target.position.dx,
        pixelY: target.position.dy,
        reportMouse: target.reportMouse,
        vertical: vertical,
      ),
    );
  }

  void _stopBallistic() {
    _ticker.stop();
    final activity = _activity;
    if (activity == null) return;
    if (activity.isDragging) {
      activity.dropMomentum();
    } else {
      _activity = null;
    }
  }

  _ScrollTarget _targetAt(Offset position) {
    final mods = readPointerModifiers(widget.readVirtualMods());
    return (
      position: position,
      mods: mods,
      reportMouse:
          widget.interaction.value.mouseTracking != .none && !mods.hasShift,
    );
  }

  void _tick(Duration elapsed) {
    final activity = _activity;
    if (activity == null || activity.isDragging) return;
    final delta = activity.advance(elapsed);
    if (delta != Offset.zero) _route(delta, activity.target);
    if (activity.done) _stopBallistic();
  }

  void _updateGesture(DragUpdateDetails details) {
    final activity = _activity;
    if (activity == null || !activity.isDragging) return;
    final delta = -details.delta;
    if (activity.markMoved(delta)) widget.onScrollStart(activity.kind);
    final adjusted = activity.update(delta, details.sourceTimeStamp);
    if (adjusted != Offset.zero) _route(adjusted, activity.target);
  }

  static Offset _supportedDelta(Offset delta, _ScrollTarget target) {
    return target.reportMouse ? delta : Offset(0, delta.dy);
  }
}

/// Accumulates sub-cell motion for one compatible terminal scroll target.
///
/// Mouse-reporting remainders are tied to their cell and modifier snapshot;
/// alternate-scroll remainders can continue across positions because only
/// vertical key steps are emitted.
final class _ScrollRemainder {
  final CellMetrics metrics;
  final _ScrollTarget target;
  double horizontal;
  double vertical;

  _ScrollRemainder(this.target, this.metrics) : horizontal = 0, vertical = 0;

  bool shares(_ScrollTarget other, CellMetrics otherMetrics) {
    if (metrics != otherMetrics || target.reportMouse != other.reportMouse) {
      return false;
    }
    if (!other.reportMouse) return true;
    return target.mods == other.mods &&
        metrics.cellAt(target.position) == metrics.cellAt(other.position);
  }
}

/// Keeps one recognizer eligible for the full pointer sequence it accepted.
///
/// Eligibility is sampled only at sequence start. This prevents modifier or
/// terminal-mode changes from transferring an in-flight sequence between the
/// pan and vertical recognizers.
mixin _ScrollSequence on OneSequenceGestureRecognizer {
  late ValueGetter<bool> _canStart;
  late ValueChanged<PointerEvent> _onPointerStart;
  PointerDeviceKind? _activeKind;

  bool allowsSequence(PointerEvent event) {
    final activeKind = _activeKind;
    return activeKind == null ? _canStart() : activeKind == event.kind;
  }

  void configureSequence({
    required ValueGetter<bool> canStart,
    required ValueChanged<PointerEvent> onPointerStart,
  }) {
    _canStart = canStart;
    _onPointerStart = onPointerStart;
  }

  void startSequence(PointerEvent event) {
    if (_activeKind != null) return;
    _activeKind = event.kind;
    _onPointerStart(event);
  }

  void stopSequence() => _activeKind = null;

  @override
  void addAllowedPointer(PointerDownEvent event) {
    startSequence(event);
    super.addAllowedPointer(event);
  }

  @override
  void addAllowedPointerPanZoom(PointerPanZoomStartEvent event) {
    startSequence(event);
    super.addAllowedPointerPanZoom(event);
  }

  @override
  void didStopTrackingLastPointer(int pointer) {
    super.didStopTrackingLastPointer(pointer);
    stopSequence();
  }

  @override
  bool isPointerPanZoomAllowed(PointerPanZoomStartEvent event) {
    return allowsSequence(event) && super.isPointerPanZoomAllowed(event);
  }
}

final class _TwoAxisScrollRecognizer extends PanGestureRecognizer
    with _ScrollSequence {
  _TwoAxisScrollRecognizer({super.debugOwner})
    : super(supportedDevices: const {.touch, .trackpad});

  @override
  bool isPointerAllowed(PointerEvent event) {
    return allowsSequence(event) && super.isPointerAllowed(event);
  }
}

final class _VerticalScrollRecognizer extends VerticalDragGestureRecognizer
    with _ScrollSequence {
  _VerticalScrollRecognizer({super.debugOwner})
    : super(supportedDevices: const {.touch, .trackpad});

  @override
  bool isPointerAllowed(PointerEvent event) {
    return allowsSequence(event) && super.isPointerAllowed(event);
  }
}
