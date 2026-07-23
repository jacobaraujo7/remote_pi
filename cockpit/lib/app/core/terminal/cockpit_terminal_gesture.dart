// Fork do `TerminalGestureHandler` do xterm (src/ui/gesture/gesture_handler.dart).
// Forkado só porque o original tipa `terminalView` como o `TerminalViewState` do
// xterm — precisamos do nosso [CockpitTerminalState] pra alcançar o
// [CockpitTerminalRender]. A lógica (tap/drag/double-tap → seleção; encaminhar
// mouse pro terminal) é idêntica. O `TerminalGestureDetector` é view-agnóstico,
// então o reusamos direto do pacote.
//
// ignore_for_file: implementation_imports
import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart' show HardwareKeyboard;
import 'package:flutter/widgets.dart';
import 'package:cockpit/app/core/terminal/xterm/src/core/mouse/button.dart';
import 'package:cockpit/app/core/terminal/xterm/src/core/mouse/button_state.dart';
import 'package:cockpit/app/core/terminal/xterm/src/core/mouse/mode.dart';
import 'package:cockpit/app/core/terminal/xterm/src/ui/controller.dart';
import 'package:cockpit/app/core/terminal/xterm/src/ui/gesture/gesture_detector.dart';

import 'cockpit_terminal.dart';
import 'cockpit_terminal_render.dart';

class CockpitTerminalGestureHandler extends StatefulWidget {
  const CockpitTerminalGestureHandler({
    super.key,
    required this.terminalView,
    required this.terminalController,
    this.child,
    this.onTapUp,
    this.onSingleTapUp,
    this.onTapDown,
    this.onSecondaryTapDown,
    this.onSecondaryTapUp,
    this.onTertiaryTapDown,
    this.onTertiaryTapUp,
    this.readOnly = false,
  });

  final CockpitTerminalState terminalView;

  final TerminalController terminalController;

  final Widget? child;

  final GestureTapUpCallback? onTapUp;

  final GestureTapUpCallback? onSingleTapUp;

  final GestureTapDownCallback? onTapDown;

  final GestureTapDownCallback? onSecondaryTapDown;

  final GestureTapUpCallback? onSecondaryTapUp;

  final GestureTapDownCallback? onTertiaryTapDown;

  final GestureTapUpCallback? onTertiaryTapUp;

  final bool readOnly;

  @override
  State<CockpitTerminalGestureHandler> createState() =>
      _CockpitTerminalGestureHandlerState();
}

class _CockpitTerminalGestureHandlerState
    extends State<CockpitTerminalGestureHandler> {
  CockpitTerminalState get terminalView => widget.terminalView;

  CockpitTerminalRender get renderTerminal => terminalView.renderTerminal;

  DragStartDetails? _lastDragStartDetails;

  LongPressStartDetails? _lastLongPressStartDetails;

  @override
  Widget build(BuildContext context) {
    return TerminalGestureDetector(
      onTapUp: widget.onTapUp,
      onSingleTapUp: onSingleTapUp,
      onTapDown: onTapDown,
      onSecondaryTapDown: onSecondaryTapDown,
      onSecondaryTapUp: onSecondaryTapUp,
      onTertiaryTapDown: onSecondaryTapDown,
      onTertiaryTapUp: onSecondaryTapUp,
      onLongPressStart: onLongPressStart,
      onLongPressMoveUpdate: onLongPressMoveUpdate,
      onDragStart: onDragStart,
      onDragUpdate: onDragUpdate,
      onDoubleTapDown: onDoubleTapDown,
      child: widget.child,
    );
  }

  /// Seleção local (overlay do nosso renderer) só é permitida quando a app
  /// **não** dona o mouse, ou quando ⌥ está segurado (escape hatch pra copiar,
  /// igual iTerm). Com a app no comando (claude/vim), os cliques vão pra ela e a
  /// seleção é dela — não pintamos uma segunda por cima.
  bool get _localSelectionAllowed =>
      terminalView.widget.terminal.mouseMode == MouseMode.none ||
      HardwareKeyboard.instance.isAltPressed;

  // O forward de mouse pra TUI (down/motion/up) é feito pelo [TerminalPane], que
  // é a única autoridade — ele vê os eventos crus de ponteiro e sabe encaminhar
  // o arraste como motion. Aqui NÃO encaminhamos tap (evita reportar o clique
  // duas vezes pra app). Mantemos só o callback de foco no onTapDown.
  static const bool _shouldSendTapEvent = false;

  void _tapDown(
    GestureTapDownCallback? callback,
    TapDownDetails details,
    TerminalMouseButton button, {
    bool forceCallback = false,
  }) {
    var handled = false;
    if (_shouldSendTapEvent) {
      handled = renderTerminal.mouseEvent(
        button,
        TerminalMouseButtonState.down,
        details.localPosition,
      );
    }
    if (!handled || forceCallback) {
      callback?.call(details);
    }
  }

  void _tapUp(
    GestureTapUpCallback? callback,
    TapUpDetails details,
    TerminalMouseButton button, {
    bool forceCallback = false,
  }) {
    var handled = false;
    if (_shouldSendTapEvent) {
      handled = renderTerminal.mouseEvent(
        button,
        TerminalMouseButtonState.up,
        details.localPosition,
      );
    }
    if (!handled || forceCallback) {
      callback?.call(details);
    }
  }

  void onTapDown(TapDownDetails details) {
    // onTapDown is special, as it will always call the supplied callback.
    // The CockpitTerminal depends on it to bring the terminal into focus.
    _tapDown(
      widget.onTapDown,
      details,
      TerminalMouseButton.left,
      forceCallback: true,
    );
  }

  void onSingleTapUp(TapUpDetails details) {
    _tapUp(widget.onSingleTapUp, details, TerminalMouseButton.left);
  }

  void onSecondaryTapDown(TapDownDetails details) {
    _tapDown(widget.onSecondaryTapDown, details, TerminalMouseButton.right);
  }

  void onSecondaryTapUp(TapUpDetails details) {
    _tapUp(widget.onSecondaryTapUp, details, TerminalMouseButton.right);
  }

  void onTertiaryTapDown(TapDownDetails details) {
    _tapDown(widget.onTertiaryTapDown, details, TerminalMouseButton.middle);
  }

  void onTertiaryTapUp(TapUpDetails details) {
    _tapUp(widget.onTertiaryTapUp, details, TerminalMouseButton.right);
  }

  void onDoubleTapDown(TapDownDetails details) {
    // Com a app no comando do mouse, o duplo-clique vira seleção de palavra DELA
    // (via taps encaminhados) — não pintamos uma local por cima.
    if (!_localSelectionAllowed) return;
    renderTerminal.selectWord(details.localPosition);
  }

  void onLongPressStart(LongPressStartDetails details) {
    if (!_localSelectionAllowed) return;
    _lastLongPressStartDetails = details;
    renderTerminal.selectWord(details.localPosition);
  }

  void onLongPressMoveUpdate(LongPressMoveUpdateDetails details) {
    if (!_localSelectionAllowed) return;
    renderTerminal.selectWord(
      _lastLongPressStartDetails!.localPosition,
      details.localPosition,
    );
  }

  void onDragStart(DragStartDetails details) {
    if (!_localSelectionAllowed) return;
    _lastDragStartDetails = details;

    details.kind == PointerDeviceKind.mouse
        ? renderTerminal.selectCharacters(details.localPosition)
        : renderTerminal.selectWord(details.localPosition);
  }

  void onDragUpdate(DragUpdateDetails details) {
    if (!_localSelectionAllowed || _lastDragStartDetails == null) return;
    renderTerminal.selectCharacters(
      _lastDragStartDetails!.localPosition,
      details.localPosition,
    );
  }
}
