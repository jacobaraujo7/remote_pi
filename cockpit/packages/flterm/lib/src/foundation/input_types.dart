/// Controls when the mouse cursor hides during terminal interaction.
///
/// Passed to [TerminalView.mouseAutoHide] to configure cursor visibility
/// behavior.
enum MouseAutoHide {
  /// Keeps the system cursor visible at all times.
  never,

  /// Hides the cursor after a keystroke and restores it on mouse movement.
  onInput,
}
