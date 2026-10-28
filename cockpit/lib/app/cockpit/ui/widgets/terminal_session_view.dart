import 'dart:async';

import 'package:flutter_modular/flutter_modular.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';
import 'package:window_manager/window_manager.dart';

import '../../../core/terminal/xterm/xterm.dart';
import '../../../core/ui/settings_controller.dart';
import '../../../core/ui/themes/themes.dart';
import '../../../core/utils/platform_kind.dart';
import '../session/terminal_session.dart';
import 'adaptive_terminal_pane.dart';
import 'terminal_attachment_drop_target.dart';

/// Shared presentation for normal docks and an owned multiplexer. All focus
/// and file actions are supplied by the owner; no global VM is accessed here.
class TerminalSessionView extends StatefulWidget {
  const TerminalSessionView({
    super.key,
    required this.session,
    required this.active,
    required this.focused,
    required this.focusRevision,
    required this.onFocus,
    required this.onOpenFile,
    this.ownerShortcuts = const {},
  });
  final TerminalSession session;
  final bool active;
  final bool focused;
  final int focusRevision;
  final VoidCallback onFocus;
  final Map<ShortcutActivator, VoidCallback> ownerShortcuts;
  final void Function(String path, {int? line}) onOpenFile;
  @override
  State<TerminalSessionView> createState() => _TerminalSessionViewState();
}

class _TerminalSessionViewState extends State<TerminalSessionView> {
  final FocusNode _focus = FocusNode();
  @override
  void initState() {
    super.initState();
    widget.session.setVisible(widget.active);
    if (widget.focused) _requestFocusSoon();
  }

  @override
  void didUpdateWidget(TerminalSessionView old) {
    super.didUpdateWidget(old);
    if (old.session != widget.session) old.session.setVisible(false);
    if (old.session != widget.session || old.active != widget.active) {
      widget.session.setVisible(widget.active);
    }
    if (widget.focused &&
        (!old.focused || old.focusRevision != widget.focusRevision)) {
      _requestFocusSoon();
    } else if (!widget.focused && old.focused) {
      _focus.unfocus();
    }
  }

  void _requestFocusSoon() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !widget.active || !widget.focused) return;
      _focus.requestFocus();
    });
  }

  void _onFileDropped() {
    if (!isMobilePlatform) unawaited(windowManager.focus());
    widget.onFocus();
    _requestFocusSoon();
  }

  @override
  void dispose() {
    widget.session.setVisible(false);
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsController>().settings;
    final font = settings.terminalFont;
    final size = settings.terminalSize ?? settings.codeSize;
    final style = (font == null || font.isEmpty)
        ? TerminalStyle(fontSize: size)
        : TerminalStyle(fontSize: size, fontFamily: font);
    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: (_) {
        widget.onFocus();
        if (widget.focused && !_focus.hasFocus) _requestFocusSoon();
      },
      child: TerminalAttachmentDropTarget(
        session: widget.session,
        active: widget.active,
        onDropped: _onFileDropped,
        child: ColoredBox(
          color: context.colors.panel,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(10, 8, 0, 8),
            child: AdaptiveTerminalPane(
              terminal: widget.session.terminal,
              ownerShortcuts: widget.ownerShortcuts,
              active: widget.active,
              focusNode: _focus,
              onPaste: widget.session.pasteFromClipboard,
              onOpenFile: widget.onOpenFile,
              theme: context.terminalTheme,
              textStyle: style,
            ),
          ),
        ),
      ),
    );
  }
}
