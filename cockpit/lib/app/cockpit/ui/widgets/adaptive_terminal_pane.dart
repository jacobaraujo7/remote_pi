import 'package:cockpit/app/core/terminal/ghostty_font_family.dart';
import 'package:cockpit/app/core/terminal/terminal_controller.dart';
import 'package:cockpit/app/core/terminal/xterm/xterm.dart' as xterm;
import 'package:flterm/flterm.dart' as ghost;
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:url_launcher/url_launcher.dart';

import 'terminal_pane.dart';

/// Renderiza o controller com a view nativa do motor que o criou.
class AdaptiveTerminalPane extends StatelessWidget {
  const AdaptiveTerminalPane({
    super.key,
    required this.terminal,
    required this.focusNode,
    required this.textStyle,
    required this.theme,
    this.onKeyEvent,
    this.onPaste,
    this.onOpenFile,
    this.readOnly = false,
  });

  final CockpitTerminalController terminal;
  final FocusNode focusNode;
  final xterm.TerminalStyle textStyle;
  final xterm.TerminalTheme theme;
  final KeyEventResult Function(KeyEvent event)? onKeyEvent;
  final VoidCallback? onPaste;
  final void Function(String path, {int? line})? onOpenFile;
  final bool readOnly;

  @override
  Widget build(BuildContext context) => switch (terminal) {
    final XtermTerminalController value => TerminalPane(
      terminal: value.terminal,
      focusNode: focusNode,
      textStyle: textStyle,
      theme: theme,
      hardwareKeyboardOnly: readOnly,
      onKeyEvent: onKeyEvent ?? (_) => KeyEventResult.ignored,
      onOpenFile: onOpenFile,
    ),
    final GhosttyTerminalController value => _GhosttyPane(
      terminal: value,
      focusNode: focusNode,
      textStyle: textStyle,
      theme: theme,
      onPaste: onPaste,
      onOpenFile: onOpenFile,
      readOnly: readOnly,
    ),
  };
}

final class _CockpitPasteIntent extends Intent {
  const _CockpitPasteIntent();
}

class _GhosttyPane extends StatelessWidget {
  const _GhosttyPane({
    required this.terminal,
    required this.focusNode,
    required this.textStyle,
    required this.theme,
    required this.onPaste,
    required this.onOpenFile,
    required this.readOnly,
  });

  final GhosttyTerminalController terminal;
  final FocusNode focusNode;
  final xterm.TerminalStyle textStyle;
  final xterm.TerminalTheme theme;
  final VoidCallback? onPaste;
  final void Function(String path, {int? line})? onOpenFile;
  final bool readOnly;

  @override
  Widget build(BuildContext context) {
    final shortcuts = <ShortcutActivator, Intent>{};
    if (!readOnly && onPaste != null) {
      shortcuts[const SingleActivator(LogicalKeyboardKey.keyV, meta: true)] =
          const _CockpitPasteIntent();
      shortcuts[const SingleActivator(LogicalKeyboardKey.keyV, control: true)] =
          const _CockpitPasteIntent();
    }

    return Actions(
      actions: <Type, Action<Intent>>{
        _CockpitPasteIntent: CallbackAction<_CockpitPasteIntent>(
          onInvoke: (_) {
            onPaste?.call();
            return null;
          },
        ),
      },
      child: ghost.TerminalView(
        controller: terminal.controller,
        focusNode: focusNode,
        showKeyboard: !readOnly,
        padding: EdgeInsets.zero,
        scrollPhysics: const ClampingScrollPhysics(),
        shortcuts: shortcuts,
        theme: _ghosttyTheme(theme, textStyle),
        linkSettings: ghost.LinkSettings(onActivate: (link) => _openLink(link)),
      ),
    );
  }

  void _openLink(ghost.ActivatedLink link) {
    final file = link.file;
    if (file != null && onOpenFile != null) {
      onOpenFile!(file.path, line: file.line);
      return;
    }
    final uri = link.uri;
    if (uri != null) {
      launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }
}

ghost.TerminalTheme _ghosttyTheme(
  xterm.TerminalTheme source,
  xterm.TerminalStyle style,
) => ghost.TerminalTheme(
  palette: ghost.ColorPalette(
    ansiColors: [
      source.black,
      source.red,
      source.green,
      source.yellow,
      source.blue,
      source.magenta,
      source.cyan,
      source.white,
      source.brightBlack,
      source.brightRed,
      source.brightGreen,
      source.brightYellow,
      source.brightBlue,
      source.brightMagenta,
      source.brightCyan,
      source.brightWhite,
    ],
    background: source.background,
    foreground: source.foreground,
  ),
  cursor: ghost.CursorTheme(color: ghost.DynamicColor.fixed(source.cursor)),
  selection: ghost.SelectionTheme(
    background: ghost.DynamicColor.fixed(source.selection),
  ),
  fontFamily: resolveGhosttyFontFamily(style.fontFamily),
  fontFamilyFallback: style.fontFamilyFallback,
  fontSize: style.fontSize,
);
