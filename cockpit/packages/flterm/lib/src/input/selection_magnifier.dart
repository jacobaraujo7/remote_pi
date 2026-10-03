import 'dart:math' as math;

import 'package:cupertino_ui/cupertino_ui.dart' show CupertinoMagnifier;
import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/widgets.dart';
import 'package:material_ui/material_ui.dart' show TextMagnifier, Theme;

import '../foundation/cell_metrics.dart';

final class SelectionCupertinoMagnifier extends StatelessWidget {
  static const _horizontalScreenPadding = 10.0;
  static const _hideBelowThreshold = 48.0;
  static const _lensSize = Size(115, 85);
  static const _magnificationScale = 1.5;
  static const _decoration = MagnifierDecoration(
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.all(Radius.circular(42.5)),
    ),
    shadows: [
      BoxShadow(
        color: Color.fromARGB(25, 0, 0, 0),
        blurRadius: 11,
        spreadRadius: 0.2,
        blurStyle: BlurStyle.outer,
      ),
    ],
  );

  final ValueListenable<MagnifierInfo> magnifierInfo;
  final Color filmColor;

  const SelectionCupertinoMagnifier({
    super.key,
    required this.magnifierInfo,
    required this.filmColor,
  });

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder(
      valueListenable: magnifierInfo,
      builder: (context, info, _) {
        final caretCenterY = info.caretRect.center.dy;
        if (caretCenterY - info.globalGesturePosition.dy <
            -_hideBelowThreshold) {
          return const SizedBox.shrink();
        }
        final screen = MediaQuery.sizeOf(context);
        final verticalLensPosition = math.max(
          caretCenterY,
          caretCenterY - (caretCenterY - info.globalGesturePosition.dy) / 10,
        );
        final desiredLeft = info.globalGesturePosition.dx - _lensSize.width / 2;
        final left = desiredLeft
            .clamp(
              _horizontalScreenPadding,
              math.max(
                _horizontalScreenPadding,
                screen.width - _horizontalScreenPadding - _lensSize.width,
              ),
            )
            .toDouble();
        final top =
            verticalLensPosition -
            (_lensSize.height - CupertinoMagnifier.kMagnifierAboveFocalPoint);
        return Positioned(
          left: left,
          top: top,
          child: RawMagnifier(
            size: _lensSize,
            magnificationScale: _magnificationScale,
            focalPointOffset: Offset(
              info.globalGesturePosition.dx - (left + _lensSize.width / 2),
              _lensSize.height / 2 -
                  CupertinoMagnifier.kMagnifierAboveFocalPoint +
                  caretCenterY -
                  verticalLensPosition,
            ),
            decoration: _decoration,
            child: ColoredBox(color: filmColor),
          ),
        );
      },
    );
  }
}

final class SelectionMagnifier {
  final _controller = MagnifierController();
  final TextMagnifierConfiguration configuration;
  final _info = ValueNotifier<MagnifierInfo>(.empty);
  var _disposed = false;

  SelectionMagnifier(this.configuration);

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    if (_controller.overlayEntry != null) _controller.hide();
    _info.dispose();
  }

  void show(BuildContext context, MagnifierInfo info) {
    if (_disposed) return;
    if (Overlay.maybeOf(context, rootOverlay: true) == null) return;
    _info.value = info;
    final magnifier = configuration.magnifierBuilder(
      context,
      _controller,
      _info,
    );
    if (magnifier == null) return;
    _controller.show(context: context, builder: (_) => magnifier);
  }

  void update(MagnifierInfo info) {
    if (_controller.overlayEntry != null) _info.value = info;
  }

  static TextMagnifierConfiguration adaptive(
    BuildContext context,
    Color terminalBackground,
  ) {
    return switch (Theme.of(context).platform) {
      .android => TextMagnifierConfiguration(
        magnifierBuilder: (_, _, info) => TextMagnifier(magnifierInfo: info),
      ),
      .iOS => TextMagnifierConfiguration(
        magnifierBuilder: (_, _, info) => SelectionCupertinoMagnifier(
          magnifierInfo: info,
          filmColor: terminalBackground.withValues(alpha: 0.08),
        ),
      ),
      _ => .disabled,
    };
  }

  static MagnifierInfo geometry({
    required BuildContext context,
    required Offset gesture,
    required Offset anchor,
    required CellMetrics metrics,
    required int rows,
  }) {
    final box = context.findRenderObject()! as RenderBox;
    final origin = box.localToGlobal(Offset.zero);
    final row = metrics.cellHeight <= 0
        ? 0
        : ((anchor.dy / metrics.cellHeight).ceil() - 1).clamp(
            0,
            math.max(0, rows - 1),
          );
    final line = Rect.fromLTWH(
      origin.dx,
      origin.dy + row * metrics.cellHeight,
      box.size.width,
      metrics.cellHeight,
    );
    final globalAnchor = origin + anchor;
    return MagnifierInfo(
      globalGesturePosition: gesture,
      caretRect: Rect.fromLTWH(
        globalAnchor.dx,
        line.top,
        1,
        metrics.cellHeight,
      ),
      fieldBounds: origin & box.size,
      currentLineBoundaries: line,
    );
  }
}
