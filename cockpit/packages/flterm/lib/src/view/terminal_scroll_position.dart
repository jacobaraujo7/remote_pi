part of 'terminal_scroll_controller.dart';

final class _TerminalScrollPosition extends ScrollPositionWithSingleContext {
  late final TerminalViewportCoordinator _viewport;
  TerminalScreen _activeScreen;

  factory _TerminalScrollPosition({
    required ScrollPhysics physics,
    required ScrollContext context,
    required TerminalScreen activeScreen,
    ScrollPosition? oldPosition,
  }) {
    return _TerminalScrollPosition._(
      physics: physics,
      context: context,
      activeScreen: activeScreen,
      oldPosition: oldPosition,
      previous: oldPosition is _TerminalScrollPosition
          ? oldPosition._viewport
          : null,
    );
  }

  _TerminalScrollPosition._({
    required super.physics,
    required super.context,
    required this._activeScreen,
    super.oldPosition,
    required TerminalViewportCoordinator? previous,
  }) {
    _viewport = TerminalViewportCoordinator(this, correctPixels);
    if (previous != null) {
      _viewport
        ..absorb(previous)
        ..setScreen(_activeScreen);
    } else {
      _viewport.setScreen(_activeScreen);
    }
    addListener(_viewport.handlePixelsChanged);
  }

  @override
  bool applyContentDimensions(double minScrollExtent, double maxScrollExtent) {
    if (_activeScreen == .alternate) {
      return super.applyContentDimensions(.negativeInfinity, .infinity);
    }
    return super.applyContentDimensions(minScrollExtent, maxScrollExtent);
  }

  @override
  void dispose() {
    removeListener(_viewport.handlePixelsChanged);
    super.dispose();
  }

  void _setActiveScreen(TerminalScreen value) {
    if (_activeScreen == value) return;
    goIdle();
    _activeScreen = value;
    _viewport.setScreen(value);
  }
}
