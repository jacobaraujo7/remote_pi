import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

import 'selection_handle_geometry.dart';
import 'selection_session.dart';

final class SelectionHandleTarget extends StatelessWidget {
  static const _minimumInteractiveDimension = 48.0;

  final Offset? peerAnchor;
  final double lineHeight;
  final SelectionHandleLayout layout;
  final TextSelectionControls controls;
  final GestureDragEndCallback onDragEnd;
  final GestureDragStartCallback onDragStart;
  final GestureDragCancelCallback onDragCancel;
  final GestureDragUpdateCallback onDragUpdate;

  const SelectionHandleTarget({
    super.key,
    required this.layout,
    required this.lineHeight,
    required this.controls,
    required this.onDragCancel,
    required this.onDragEnd,
    required this.onDragStart,
    required this.onDragUpdate,
    required this.peerAnchor,
  });

  @override
  Widget build(BuildContext context) {
    return Positioned.fill(
      child: LayoutBuilder(
        builder: (context, constraints) {
          final visualSize = controls.getHandleSize(lineHeight);
          final size = Size(
            math.max(_minimumInteractiveDimension, visualSize.width),
            math.max(_minimumInteractiveDimension, visualSize.height),
          );
          final viewport = constraints.biggest;
          final origin = _targetOrigin(layout.anchor, size, viewport);
          final peerOrigin = peerAnchor == null
              ? null
              : _targetOrigin(peerAnchor!, size, viewport);
          final targetAnchor = layout.anchor - origin;
          final visualAnchor = controls.getHandleAnchor(
            layout.type,
            lineHeight,
          );
          return Stack(
            clipBehavior: .none,
            children: [
              Positioned(
                left: origin.dx,
                top: origin.dy,
                child: _ClosestHandleHitRegion(
                  anchor: targetAnchor,
                  peerAnchor: peerAnchor == null
                      ? null
                      : targetAnchor + peerAnchor! - layout.anchor,
                  peerBounds: peerOrigin == null
                      ? null
                      : (peerOrigin - origin) & size,
                  child: RawGestureDetector(
                    key: ValueKey<SelectionEndpoint>(layout.endpoint),
                    behavior: .opaque,
                    gestures: {
                      _SelectionHandleDragRecognizer:
                          GestureRecognizerFactoryWithHandlers<
                            _SelectionHandleDragRecognizer
                          >(
                            _SelectionHandleDragRecognizer.new,
                            (recognizer) => recognizer
                              ..dragStartBehavior = .down
                              ..onCancel = onDragCancel
                              ..onEnd = onDragEnd
                              ..onStart = onDragStart
                              ..onUpdate = onDragUpdate,
                          ),
                    },
                    child: SizedBox.fromSize(
                      size: size,
                      child: Stack(
                        clipBehavior: .none,
                        children: [
                          Positioned(
                            left: targetAnchor.dx - visualAnchor.dx,
                            top: targetAnchor.dy - visualAnchor.dy,
                            child: controls.buildHandle(
                              context,
                              layout.type,
                              lineHeight,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Offset _targetOrigin(Offset anchor, Size target, Size viewport) => Offset(
    (anchor.dx - target.width / 2).clamp(
      0,
      math.max(0, viewport.width - target.width),
    ),
    (anchor.dy - target.height / 2).clamp(
      0,
      math.max(0, viewport.height - target.height),
    ),
  );
}

final class _ClosestHandleHitRegion extends SingleChildRenderObjectWidget {
  final Offset anchor;
  final Offset? peerAnchor;
  final Rect? peerBounds;

  const _ClosestHandleHitRegion({
    required this.anchor,
    required this.peerAnchor,
    required this.peerBounds,
    required super.child,
  });

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderClosestHandleHitRegion(anchor, peerAnchor, peerBounds);

  @override
  void updateRenderObject(
    BuildContext context,
    _RenderClosestHandleHitRegion renderObject,
  ) {
    renderObject
      ..anchor = anchor
      ..peerAnchor = peerAnchor
      ..peerBounds = peerBounds;
  }
}

final class _RenderClosestHandleHitRegion extends RenderProxyBox {
  Offset anchor;
  Offset? peerAnchor;
  Rect? peerBounds;

  _RenderClosestHandleHitRegion(this.anchor, this.peerAnchor, this.peerBounds);

  @override
  bool hitTest(BoxHitTestResult result, {required Offset position}) {
    final peerAnchor = this.peerAnchor;
    if (peerAnchor != null &&
        peerBounds!.contains(position) &&
        (position - anchor).distanceSquared >
            (position - peerAnchor).distanceSquared) {
      return false;
    }
    return super.hitTest(result, position: position);
  }
}

final class _SelectionHandleDragRecognizer extends PanGestureRecognizer {
  @override
  void addAllowedPointer(PointerDownEvent event) {
    super.addAllowedPointer(event);
    resolve(.accepted);
  }
}
