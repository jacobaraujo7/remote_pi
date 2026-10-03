import 'package:flutter/gestures.dart';
import 'package:flutter/widgets.dart';
import 'package:meta/meta.dart';

/// Recognizes the primitive gestures used by terminal interaction.
///
/// Pan is restricted to mouse, stylus, and inverted stylus; long press is
/// restricted to touch. The tap recognizer retains the primary pointer's
/// source timestamp because Flutter's resolved tap details do not expose it.
/// This widget reports gestures only and owns no selection or terminal state.
@internal
final class PrimitiveGestureDetector extends StatelessWidget {
  final Widget child;

  /// Fires when a tap begins with its source pointer timestamp.
  final void Function(TapDownDetails details, Duration timeStamp)? onTapDown;

  /// Fires when a tap ends.
  final GestureTapUpCallback? onTapUp;

  /// Fires when a mouse drag begins.
  final GestureDragStartCallback? onDragStart;

  /// Fires as the mouse drag continues.
  final GestureDragUpdateCallback? onDragUpdate;

  /// Fires when a mouse drag ends or is cancelled.
  final VoidCallback? onDragEnd;

  /// Fires when a touch long press begins.
  final GestureLongPressStartCallback? onLongPressStart;

  /// Fires as a touch long press moves.
  final GestureLongPressMoveUpdateCallback? onLongPressMoveUpdate;

  /// Fires when a touch long press ends.
  final VoidCallback? onLongPressUp;

  const PrimitiveGestureDetector({
    super.key,
    required this.child,
    this.onTapDown,
    this.onTapUp,
    this.onDragStart,
    this.onDragUpdate,
    this.onDragEnd,
    this.onLongPressStart,
    this.onLongPressMoveUpdate,
    this.onLongPressUp,
  });

  @override
  Widget build(BuildContext context) {
    return RawGestureDetector(
      behavior: .opaque,
      gestures: <Type, GestureRecognizerFactory>{
        _TimestampedTapGestureRecognizer:
            GestureRecognizerFactoryWithHandlers<
              _TimestampedTapGestureRecognizer
            >(() => _TimestampedTapGestureRecognizer(debugOwner: this), (
              recognizer,
            ) {
              recognizer.onTapDown = onTapDown == null
                  ? null
                  : (details) => onTapDown!(details, recognizer.timeStamp);
              recognizer.onTapUp = onTapUp;
            }),
        LongPressGestureRecognizer:
            GestureRecognizerFactoryWithHandlers<LongPressGestureRecognizer>(
              () => LongPressGestureRecognizer(
                debugOwner: this,
                supportedDevices: const {.touch},
              ),
              (instance) => instance
                ..onLongPressStart = onLongPressStart
                ..onLongPressMoveUpdate = onLongPressMoveUpdate
                ..onLongPressUp = onLongPressUp,
            ),
        PanGestureRecognizer:
            GestureRecognizerFactoryWithHandlers<PanGestureRecognizer>(
              () => PanGestureRecognizer(
                debugOwner: this,
                supportedDevices: const {.mouse, .stylus, .invertedStylus},
              ),
              (instance) {
                instance
                  ..dragStartBehavior = .down
                  ..onStart = onDragStart
                  ..onUpdate = onDragUpdate
                  ..onEnd = (_) => onDragEnd?.call();
                instance.onCancel = () => onDragEnd?.call();
              },
            ),
      },
      child: child,
    );
  }
}

/// Retains the primary pointer timestamp until Flutter resolves the tap arena.
final class _TimestampedTapGestureRecognizer extends TapGestureRecognizer {
  Duration timeStamp = .zero;

  _TimestampedTapGestureRecognizer({super.debugOwner});

  @override
  void addAllowedPointer(PointerDownEvent event) {
    super.addAllowedPointer(event);
    if (primaryPointer == event.pointer) timeStamp = event.timeStamp;
  }
}
