import 'package:cockpit/app/core/terminal/terminal_find.dart';
import 'package:cockpit/app/core/ui/themes/themes.dart';
import 'package:cockpit/app/core/ui/widgets/app_tooltip.dart';
import 'package:cockpit/app/core/ui/widgets/hover_tap.dart';
import 'package:cockpit/i18n/strings.g.dart';
import 'package:flutter/services.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';

/// Floating **find-in-terminal** bar (⌘F), anchored top-right of the terminal.
/// A dumb reflection of a [TerminalFind]; all state lives in the host pane.
///
/// Unlike the file find bar there are no case/word/regex toggles: flterm's
/// search is a plain case-insensitive substring match, and the xterm engine
/// mirrors that, so both engines behave identically.
class TerminalFindBar extends StatelessWidget {
  const TerminalFindBar({
    super.key,
    required this.controller,
    required this.focusNode,
    required this.matchCount,
    required this.currentIndex,
    required this.isSearching,
    required this.onChanged,
    required this.onNext,
    required this.onPrev,
    required this.onClose,
  });

  final TextEditingController controller;
  final FocusNode focusNode;

  /// Total matches and the 1-based index of the current one (0 = none).
  final int matchCount;
  final int currentIndex;
  final bool isSearching;

  final ValueChanged<String> onChanged;
  final VoidCallback onNext;
  final VoidCallback onPrev;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final typo = context.typo;
    final hasQuery = controller.text.isNotEmpty;
    final String counter;
    if (!hasQuery) {
      counter = '';
    } else if (matchCount == 0) {
      counter = isSearching ? '…' : context.t.cockpit.findBar.noResults;
    } else {
      counter = context.t.cockpit.findBar.counter(
        current: currentIndex,
        total: matchCount,
      );
    }

    return Container(
      padding: const EdgeInsets.fromLTRB(8, 6, 6, 6),
      decoration: BoxDecoration(
        color: colors.panel2,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: colors.border2),
        boxShadow: [
          BoxShadow(
            color: colors.shadow,
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 200,
            child: CallbackShortcuts(
              bindings: {
                const SingleActivator(LogicalKeyboardKey.enter): onNext,
                const SingleActivator(LogicalKeyboardKey.enter, shift: true):
                    onPrev,
                const SingleActivator(LogicalKeyboardKey.escape): onClose,
              },
              child: TextField(
                controller: controller,
                focusNode: focusNode,
                placeholder: Text(
                  context.t.cockpit.findBar.find,
                  style: typo.body.copyWith(fontSize: 13, color: colors.text4),
                ),
                style: typo.body.copyWith(fontSize: 13, color: colors.text),
                border: Border.all(color: colors.border),
                borderRadius: BorderRadius.circular(6),
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
                onChanged: onChanged,
              ),
            ),
          ),
          const SizedBox(width: 6),
          SizedBox(
            width: 66,
            child: Text(
              counter,
              textAlign: TextAlign.right,
              overflow: TextOverflow.ellipsis,
              style: typo.label.copyWith(fontSize: 11, color: colors.text3),
            ),
          ),
          const SizedBox(width: 4),
          _NavButton(
            icon: Icons.keyboard_arrow_up,
            tooltip: context.t.cockpit.findBar.previous,
            enabled: matchCount > 0,
            onTap: onPrev,
          ),
          _NavButton(
            icon: Icons.keyboard_arrow_down,
            tooltip: context.t.cockpit.findBar.next,
            enabled: matchCount > 0,
            onTap: onNext,
          ),
          _NavButton(
            icon: Icons.close,
            tooltip: context.t.cockpit.findBar.close,
            enabled: true,
            onTap: onClose,
          ),
        ],
      ),
    );
  }
}

class _NavButton extends StatelessWidget {
  const _NavButton({
    required this.icon,
    required this.tooltip,
    required this.enabled,
    required this.onTap,
  });

  final IconData icon;
  final String tooltip;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return AppTooltip(
      message: tooltip,
      child: HoverTap(
        borderRadius: BorderRadius.circular(5),
        onTap: enabled ? onTap : () {},
        child: Padding(
          padding: const EdgeInsets.all(4),
          child: Icon(
            icon,
            size: 16,
            color: enabled ? colors.text2 : colors.text4,
          ),
        ),
      ),
    );
  }
}

/// Mixin for a terminal pane's [State]: owns the find bar's open/closed state,
/// the query field, and the engine-specific [TerminalFind] lifecycle. The pane
/// supplies [createFind] (it has the engine controller) and [terminalFocusNode]
/// (focus returns there on close), calls [openFind] from its ⌘F binding, and
/// renders [buildFindOverlay] in a Stack over the terminal.
mixin TerminalFindHost<T extends StatefulWidget> on State<T> {
  final TextEditingController findQuery = TextEditingController();
  final FocusNode findFocus = FocusNode(debugLabel: 'terminal-find');
  TerminalFind? _find;

  bool get isFindOpen => _find != null;

  /// Builds the engine-specific find controller. Called with a live [context]
  /// (for theme colors) when the bar first opens.
  TerminalFind createFind();

  /// Focus node the terminal keyboard uses; focus returns here on close.
  FocusNode get terminalFocusNode;

  void openFind() {
    if (_find == null) {
      setState(() => _find = createFind());
    }
    findFocus.requestFocus();
    findQuery.selection = TextSelection(
      baseOffset: 0,
      extentOffset: findQuery.text.length,
    );
    if (findQuery.text.isNotEmpty) _find!.search(findQuery.text);
  }

  void closeFind() {
    final find = _find;
    if (find == null) return;
    find.clear();
    find.dispose();
    setState(() => _find = null);
    terminalFocusNode.requestFocus();
  }

  Widget buildFindOverlay() {
    final find = _find;
    if (find == null) return const SizedBox.shrink();
    // Align + Padding, NOT Positioned: this file imports shadcn_flutter, whose
    // `Positioned`/`StackParentData` differ from Flutter's, and the pane's Stack
    // is Flutter's. A shadcn Positioned in a Flutter Stack throws a parentData
    // type-cast error every layout (which then recurses through the app's error
    // widget). Align is parent-data-agnostic and works as a plain Stack child.
    return Align(
      alignment: Alignment.topRight,
      child: Padding(
        padding: const EdgeInsets.only(top: 8, right: 16),
        child: ListenableBuilder(
          listenable: find,
          builder: (_, _) => TerminalFindBar(
            controller: findQuery,
            focusNode: findFocus,
            matchCount: find.matchCount,
            currentIndex: find.currentIndex,
            isSearching: find.isSearching,
            onChanged: find.search,
            onNext: find.next,
            onPrev: find.previous,
            onClose: closeFind,
          ),
        ),
      ),
    );
  }

  /// Disposes the engine find controller. Call this from the pane's own
  /// `dispose` *before* tearing down the view controller / scroll controller the
  /// find paints into (the xterm engine removes its highlights here). Idempotent;
  /// the mixin's own [dispose] also calls it.
  void teardownFind() {
    _find?.dispose();
    _find = null;
  }

  @override
  void dispose() {
    teardownFind();
    findQuery.dispose();
    findFocus.dispose();
    super.dispose();
  }
}
