import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:libghostty/libghostty.dart' show TerminalScreen;

part 'terminal_scroll_position.dart';
part 'terminal_viewport_coordinator.dart';

void setTerminalScrollControllerActiveScreen(
  TerminalScrollController controller,
  TerminalScreen activeScreen,
) => controller._setActiveScreen(activeScreen);

/// Scroll controller for [TerminalView].
///
/// On the primary screen, scrolls through the scrollback buffer like
/// a normal [ScrollController]. On the alternate screen, [TerminalView]
/// forwards scroll gestures as mouse reports or alternate-scroll key input.
///
/// Created internally by [TerminalView] when not provided. Supply your
/// own to observe or control the scroll position programmatically.
///
/// ```dart
/// final scrollController = TerminalScrollController();
///
/// TerminalView(
///   controller: controller,
///   scrollController: scrollController,
/// );
///
/// // Jump to the top of scrollback.
/// scrollController.jumpTo(0);
/// ```
class TerminalScrollController extends ScrollController {
  TerminalScreen _activeScreen = .primary;

  TerminalScrollController();

  /// The active terminal screen.
  TerminalScreen get activeScreen => _activeScreen;

  @override
  ScrollPosition createScrollPosition(
    ScrollPhysics physics,
    ScrollContext context,
    ScrollPosition? oldPosition,
  ) {
    return _TerminalScrollPosition(
      physics: physics,
      context: context,
      oldPosition: oldPosition,
      activeScreen: _activeScreen,
    );
  }

  void _setActiveScreen(TerminalScreen value) {
    if (_activeScreen == value) return;
    _activeScreen = value;
    for (final position in positions) {
      (position as _TerminalScrollPosition)._setActiveScreen(value);
    }
  }
}
