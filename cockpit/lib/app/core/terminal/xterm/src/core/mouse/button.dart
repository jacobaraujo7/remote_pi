enum TerminalMouseButton {
  left(id: 0),

  middle(id: 1),

  right(id: 2),

  wheelUp(id: 64, isWheel: true),

  wheelDown(id: 65, isWheel: true),

  wheelLeft(id: 66, isWheel: true),

  wheelRight(id: 67, isWheel: true);

  /// The id that is used to report a button press or release to the terminal.
  ///
  /// Mouse wheel buttons are 4–7. In the X10/SGR mouse encoding those are
  /// reported with bit 6 (value 64) set and the low two bits holding
  /// `button - 4`, i.e. wheel up=64, down=65, left=66, right=67.
  ///
  /// NB: it must be `64 + (button - 4)`, not `64 + button`. Adding 64 to the
  /// raw button number (4–7) also sets bit 2 (value 4) — the **Shift**
  /// modifier — so the app reads the event as Shift+wheel and ignores it for
  /// scrolling. That bug made the Claude Code TUI (alt-buffer + SGR mouse)
  /// unscrollable.
  final int id;

  /// Whether this button is a mouse wheel button.
  final bool isWheel;

  const TerminalMouseButton({required this.id, this.isWheel = false});
}
