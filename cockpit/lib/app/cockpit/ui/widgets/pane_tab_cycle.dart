import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

/// Ctrl+Tab (next, `1`) / Ctrl+Shift+Tab (previous, `-1`): cycle the tabs of
/// the pane that has the keyboard. Control on every platform (⌃ on macOS, not
/// ⌘), the OS tab-cycling convention. [SingleActivator] matches modifiers
/// exactly, so Alt/Meta combos are not the chord.
///
/// Handed to a terminal as `ownerShortcuts`, so the terminal resolves it before
/// encoding a key for the PTY (no `CSI 27;5;9~` leak, both engines). A
/// terminal that owns its own Ctrl+Tab (the `.orc` inner terminals) passes its
/// own map instead and keeps it: the event is handled there and never bubbles
/// to [PaneTabCycleScope].
Map<ShortcutActivator, VoidCallback> paneTabCycleShortcuts(
  void Function(int delta) onCycle,
) => {
  const SingleActivator(LogicalKeyboardKey.tab, control: true): () =>
      onCycle(1),
  const SingleActivator(
    LogicalKeyboardKey.tab,
    control: true,
    shift: true,
  ): () =>
      onCycle(-1),
};

/// Same chord for a pane tab whose focus is not in a terminal (editor,
/// viewer, the non-terminal parts of an `.orc`): the key bubbles up the focus
/// tree to here.
class PaneTabCycleScope extends StatelessWidget {
  const PaneTabCycleScope({
    super.key,
    required this.onCycle,
    required this.child,
  });

  final void Function(int delta) onCycle;
  final Widget child;

  @override
  Widget build(BuildContext context) =>
      CallbackShortcuts(bindings: paneTabCycleShortcuts(onCycle), child: child);
}
