import 'dart:math' as math;

import 'package:cupertino_ui/cupertino_ui.dart'
    show CupertinoTextSelectionControls, CupertinoTheme;
import 'package:flutter/widgets.dart';

final selectionCupertinoHandleControls = _SelectionCupertinoHandleControls();

final class _SelectionCupertinoHandleControls
    extends CupertinoTextSelectionControls {
  static const _ballRadius = 8.0;
  static const _caretWidth = 2.0;
  static const _overlap = 2.0;

  @override
  Widget buildHandle(
    BuildContext context,
    TextSelectionHandleType type,
    double textLineHeight, [
    VoidCallback? onTap,
  ]) {
    final handle = SizedBox.fromSize(
      size: getHandleSize(textLineHeight),
      child: CustomPaint(
        painter: _SelectionCupertinoHandlePainter(
          color: CupertinoTheme.of(context).selectionHandleColor,
          type: type,
        ),
      ),
    );
    return type == .right
        ? Transform.rotate(angle: math.pi, child: handle)
        : handle;
  }

  @override
  Offset getHandleAnchor(TextSelectionHandleType type, double textLineHeight) {
    final size = getHandleSize(textLineHeight);
    return switch (type) {
      .left => Offset(_ballRadius, size.height),
      .right => Offset(_ballRadius, size.height - 2 * _ballRadius + _overlap),
      .collapsed => Offset(_ballRadius, size.height / 2),
    };
  }

  @override
  Size getHandleSize(double textLineHeight) =>
      Size(2 * _ballRadius, textLineHeight + 2 * _ballRadius - _overlap);
}

final class _SelectionCupertinoHandlePainter extends CustomPainter {
  final Color color;
  final TextSelectionHandleType type;

  const _SelectionCupertinoHandlePainter({
    required this.color,
    required this.type,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = color;
    if (type == .collapsed) {
      canvas.drawRect(
        Rect.fromLTWH(
          (size.width - _SelectionCupertinoHandleControls._caretWidth) / 2,
          0,
          _SelectionCupertinoHandleControls._caretWidth,
          size.height,
        ),
        paint,
      );
      return;
    }
    canvas
      ..drawCircle(
        const Offset(
          _SelectionCupertinoHandleControls._ballRadius,
          _SelectionCupertinoHandleControls._ballRadius,
        ),
        _SelectionCupertinoHandleControls._ballRadius,
        paint,
      )
      ..drawRect(
        Rect.fromLTWH(
          _SelectionCupertinoHandleControls._ballRadius -
              _SelectionCupertinoHandleControls._caretWidth / 2,
          2 * _SelectionCupertinoHandleControls._ballRadius -
              _SelectionCupertinoHandleControls._overlap,
          _SelectionCupertinoHandleControls._caretWidth,
          size.height -
              2 * _SelectionCupertinoHandleControls._ballRadius +
              _SelectionCupertinoHandleControls._overlap,
        ),
        paint,
      );
  }

  @override
  bool shouldRepaint(_SelectionCupertinoHandlePainter oldDelegate) {
    return color != oldDelegate.color || type != oldDelegate.type;
  }
}
