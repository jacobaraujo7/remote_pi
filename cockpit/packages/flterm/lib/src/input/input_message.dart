import 'package:flutter/foundation.dart' hide Key;
import 'package:libghostty/libghostty.dart';

/// Keyboard input normalized independently of Flutter key event types.
final class KeyInput {
  /// The terminal key action.
  final KeyAction action;

  /// The text associated with the key event, or null when it has none.
  final String? character;

  /// Whether a platform input method owns the key sequence.
  final bool composing;

  /// The modifiers consumed to produce [character].
  final Mods consumedMods;

  /// The physical key translated to the terminal engine's key vocabulary.
  final Key key;

  /// The effective modifier state presented to the terminal encoder.
  final Mods mods;

  /// The key's code point without modifiers, or zero when unavailable.
  final int unshiftedCodepoint;

  const KeyInput({
    required this.action,
    required this.character,
    required this.composing,
    required this.consumedMods,
    required this.key,
    required this.mods,
    required this.unshiftedCodepoint,
  });
}

/// Normalized mouse input for the terminal protocol.
final class MouseInput {
  /// The mouse action being reported.
  final MouseAction action;

  /// Whether any terminal-reportable pointer button remains pressed.
  final bool anyButtonPressed;

  /// The button associated with [action], or null for unbuttoned motion.
  final MouseButton? button;

  /// The complete physical and virtual modifier state for this event.
  final Mods mods;

  /// The logical horizontal offset from the terminal grid origin.
  final double pixelX;

  /// The logical vertical offset from the terminal grid origin.
  final double pixelY;

  const MouseInput({
    required this.action,
    required this.anyButtonPressed,
    required this.button,
    required this.mods,
    required this.pixelX,
    required this.pixelY,
  });
}

/// Quantized terminal scroll input captured for one gesture target.
final class ScrollInput {
  /// The modifier state captured when the scroll target was selected.
  final Mods mods;

  /// The target's logical horizontal offset from the terminal grid origin.
  final double pixelX;

  /// The target's logical vertical offset from the terminal grid origin.
  final double pixelY;

  /// Signed vertical cell steps. Negative values scroll up.
  final int vertical;

  /// Signed horizontal cell steps. Negative values scroll left.
  final int horizontal;

  /// Whether to encode mouse reports instead of alternate-scroll keys.
  final bool reportMouse;

  const ScrollInput({
    required this.mods,
    required this.pixelX,
    required this.pixelY,
    required this.vertical,
    required this.horizontal,
    required this.reportMouse,
  });
}

/// Terminal state used to route pointer and scroll input.
@immutable
@internal
final class TerminalInteractionState {
  final TerminalScreen activeScreen;
  final MouseTracking mouseTracking;
  final bool alternateScroll;

  const TerminalInteractionState({
    required this.activeScreen,
    required this.mouseTracking,
    required this.alternateScroll,
  });

  @override
  int get hashCode => Object.hash(activeScreen, mouseTracking, alternateScroll);

  @override
  bool operator ==(Object other) {
    return other is TerminalInteractionState &&
        other.activeScreen == activeScreen &&
        other.mouseTracking == mouseTracking &&
        other.alternateScroll == alternateScroll;
  }
}
