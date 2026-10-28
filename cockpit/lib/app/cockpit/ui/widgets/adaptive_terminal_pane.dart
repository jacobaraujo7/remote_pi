import 'dart:io' show Platform;

import 'package:cockpit/app/core/terminal/ghostty_font_family.dart';
import 'package:cockpit/app/core/domain/entities/app_settings.dart';
import 'package:cockpit/app/core/terminal/terminal_controller.dart';
import 'package:cockpit/app/core/terminal/terminal_find.dart';
import 'package:cockpit/app/core/terminal/terminal_font_weight.dart';
import 'package:cockpit/app/core/terminal/terminal_zoom.dart';
import 'package:cockpit/app/core/terminal/xterm/xterm.dart' as xterm;
import 'package:cockpit/app/core/ui/settings_controller.dart';
import 'package:flterm/flterm.dart' as ghost;
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_modular/flutter_modular.dart';
import 'package:google_fonts/google_fonts.dart';

import 'link_context_menu.dart';
import 'terminal_find_bar.dart';
import 'terminal_pane.dart';

/// Renderiza o controller com a view nativa do motor que o criou.
class AdaptiveTerminalPane extends StatelessWidget {
  const AdaptiveTerminalPane({
    super.key,
    required this.terminal,
    required this.active,
    required this.focusNode,
    required this.textStyle,
    required this.theme,
    this.onKeyEvent,
    this.onPaste,
    this.onOpenFile,
    this.readOnly = false,
    this.ownerShortcuts = const {},
  });

  final CockpitTerminalController terminal;
  final bool active;
  final FocusNode focusNode;
  final xterm.TerminalStyle textStyle;
  final xterm.TerminalTheme theme;
  final KeyEventResult Function(KeyEvent event)? onKeyEvent;
  final VoidCallback? onPaste;
  final void Function(String path, {int? line})? onOpenFile;
  final bool readOnly;
  final Map<ShortcutActivator, VoidCallback> ownerShortcuts;

  @override
  Widget build(BuildContext context) => switch (terminal) {
    final XtermTerminalController value => TerminalPane(
      terminal: value.terminal,
      active: active,
      focusNode: focusNode,
      textStyle: textStyle,
      theme: theme,
      hardwareKeyboardOnly: readOnly,
      onKeyEvent: (event) {
        if (event is KeyDownEvent || event is KeyRepeatEvent) {
          for (final entry in ownerShortcuts.entries) {
            if (entry.key.accepts(event, HardwareKeyboard.instance)) {
              entry.value();
              return KeyEventResult.handled;
            }
          }
        }
        if (!readOnly && onPaste != null && isTerminalPasteEvent(event)) {
          onPaste!();
          return KeyEventResult.handled;
        }
        return onKeyEvent?.call(event) ?? KeyEventResult.ignored;
      },
      onOpenFile: onOpenFile,
    ),
    final GhosttyTerminalController value => _GhosttyPane(
      terminal: value,
      active: active,
      focusNode: focusNode,
      textStyle: textStyle,
      theme: theme,
      onPaste: onPaste,
      onOpenFile: onOpenFile,
      readOnly: readOnly,
      ownerShortcuts: ownerShortcuts,
    ),
  };
}

final class _CockpitOwnerShortcutIntent extends Intent {
  const _CockpitOwnerShortcutIntent(this.invoke);
  final VoidCallback invoke;
}

final class _CockpitPasteIntent extends Intent {
  const _CockpitPasteIntent();
}

final class _CockpitFindIntent extends Intent {
  const _CockpitFindIntent();
}

class _GhosttyPane extends StatefulWidget {
  const _GhosttyPane({
    required this.terminal,
    required this.active,
    required this.focusNode,
    required this.textStyle,
    required this.theme,
    required this.onPaste,
    required this.onOpenFile,
    required this.readOnly,
    required this.ownerShortcuts,
  });

  final GhosttyTerminalController terminal;
  final bool active;
  final FocusNode focusNode;
  final xterm.TerminalStyle textStyle;
  final xterm.TerminalTheme theme;
  final VoidCallback? onPaste;
  final void Function(String path, {int? line})? onOpenFile;
  final bool readOnly;
  final Map<ShortcutActivator, VoidCallback> ownerShortcuts;

  @override
  State<_GhosttyPane> createState() => _GhosttyPaneState();
}

class _GhosttyPaneState extends State<_GhosttyPane>
    with TerminalFindHost<_GhosttyPane> {
  @override
  FocusNode get terminalFocusNode => widget.focusNode;

  // flterm's search controller does the matching, match painting and
  // scroll-to-match itself; we only drive it from the find bar.
  @override
  TerminalFind createFind() =>
      GhosttyTerminalFind(widget.terminal.controller.search);

  @override
  Widget build(BuildContext context) {
    final readOnly = widget.readOnly;
    final onPaste = widget.onPaste;
    final shortcuts = <ShortcutActivator, Intent>{
      for (final entry in widget.ownerShortcuts.entries)
        entry.key: _CockpitOwnerShortcutIntent(entry.value),
      // ⌘F / Ctrl-F opens the find bar (works even read-only — searching a
      // frozen buffer is fine). Resolved by the Actions scope below, where
      // flterm dispatches the shortcuts it receives. Ctrl-F only off macOS:
      // in a shell it is readline's forward-char / page-down in vim and less.
      const SingleActivator(LogicalKeyboardKey.keyF, meta: true):
          const _CockpitFindIntent(),
      if (!Platform.isMacOS)
        const SingleActivator(LogicalKeyboardKey.keyF, control: true):
            const _CockpitFindIntent(),
    };
    if (!readOnly && onPaste != null) {
      shortcuts[const SingleActivator(LogicalKeyboardKey.keyV, meta: true)] =
          const _CockpitPasteIntent();
      shortcuts[const SingleActivator(LogicalKeyboardKey.keyV, control: true)] =
          const _CockpitPasteIntent();
    }

    // Zoom da interface. O app inteiro é ampliado por um `FittedBox`
    // (`_AppZoom`, em app_widget.dart), o que é inofensivo para texto e ícones
    // (vetor, re-rasterizado) mas degrada o terminal: o flterm pinta a partir
    // de um atlas de glifos já rasterizado, então ampliar é ampliar bitmap.
    // Aqui o zoom é DESFEITO e reaplicado como tamanho de fonte — ver
    // [TerminalUnzoomBox]. Resultado: o mesmo tamanho na tela, com glifos rasterizados
    // na resolução física real.
    final uiScale = context.select<SettingsController, double>(
      (c) => c.settings.interfaceSize / 14.0,
    );

    // Peso do traço: compensa o antialiasing em cinza do Skia, que engorda os
    // glifos em telas de baixa densidade. Depende do DPR, então é resolvido
    // aqui e não nas settings — a mesma preferência dá pesos diferentes no
    // Retina e no monitor comum, que é exatamente o ponto.
    final fontWeight = resolveTerminalFontWeight(
      context.select<SettingsController, TerminalFontWeight>(
        (c) => c.settings.terminalFontWeight,
      ),
      MediaQuery.devicePixelRatioOf(context),
    );

    final ghosttyTheme = _ghosttyTheme(
      widget.theme,
      widget.textStyle,
      uiScale,
      fontWeight,
    );

    final Widget terminalView = ghost.TerminalView(
      // Identity is per session. StablePaneHost keeps this subtree under the
      // same parent even when its tab moves to another dock.
      key: ObjectKey(widget.terminal.controller),
      controller: widget.terminal.controller,
      scrollController: widget.terminal.scrollController,
      presentationActive: widget.active,
      focusNode: widget.focusNode,
      showKeyboard: !readOnly,
      padding: EdgeInsets.zero,
      scrollPhysics: const ClampingScrollPhysics(),
      shortcuts: shortcuts,
      theme: ghosttyTheme,
      linkSettings: ghost.LinkSettings(
        // Hover e abertura seguem exigindo ⌘/Ctrl (default do flterm): num
        // terminal cheio de caminhos, clique simples continua só posicionando o
        // foco. ⌘-clique abre direto; botão direito num link abre o menu
        // (Open / Reveal / Copy), checado antes do mouse tracking da TUI.
        onActivateAt: (link, position) => _openLink(link),
        onSecondaryActivate: (link, position) {
          _showLinkMenu(context, link, position);
        },
      ),
    );

    final view = TerminalUnzoomBox(scale: uiScale, child: terminalView);

    // Aba inativa: a TerminalView fica MONTADA, só não é pintada. Antes ela era
    // trocada por um `SizedBox` e cada volta pra aba pagava um `initState`
    // completo do flterm (ViewAttachment novo, métricas de fonte, atlas,
    // resize) — era o delay visível na troca de aba. `Offstage` mantém o
    // Element/State (nada de re-attach), pula paint e hit-test, e o
    // `TickerMode` desliga o blink do cursor enquanto oculta. O parser e o
    // scrollback seguem no controller; presentationActive suspende apenas as
    // invalidacoes visuais e faz um layout completo ao reabrir.
    // StackFit.expand hands the (non-positioned) terminal TIGHT full-size
    // constraints — same as the old direct return. Without it the Stack's
    // default loose fit gives flterm's TerminalView slack, and its
    // performLayout->onResize->setState grid report oscillates into an infinite
    // relayout (100% CPU). The find bar is a Positioned child, unaffected.
    return Stack(
      fit: StackFit.expand,
      children: [
        Offstage(
          offstage: !widget.active,
          child: TickerMode(
            enabled: widget.active,
            child: Actions(
              actions: <Type, Action<Intent>>{
                _CockpitOwnerShortcutIntent:
                    CallbackAction<_CockpitOwnerShortcutIntent>(
                      onInvoke: (intent) {
                        intent.invoke();
                        return null;
                      },
                    ),
                _CockpitPasteIntent: CallbackAction<_CockpitPasteIntent>(
                  onInvoke: (_) {
                    onPaste?.call();
                    return null;
                  },
                ),
                _CockpitFindIntent: CallbackAction<_CockpitFindIntent>(
                  onInvoke: (_) {
                    openFind();
                    return null;
                  },
                ),
              },
              child: view,
            ),
          ),
        ),
        if (widget.active) buildFindOverlay(),
      ],
    );
  }

  void _openLink(ghost.ActivatedLink link) {
    final file = link.file;
    openTerminalLink(
      filePath: file?.path,
      fileLine: file?.line,
      resolvedFilePath: file?.resolvedPath,
      uri: file == null ? link.uri : null,
      onOpenFile: widget.onOpenFile,
    );
  }

  void _showLinkMenu(
    BuildContext context,
    ghost.ActivatedLink link,
    Offset globalPosition,
  ) {
    final file = link.file;
    showTerminalLinkMenu(
      context,
      globalPosition,
      filePath: file?.path,
      fileLine: file?.line,
      resolvedFilePath: file?.resolvedPath,
      uri: file == null ? link.uri : null,
      onOpenFile: widget.onOpenFile,
    );
  }
}

/// Traduz o tema do xterm para o do flterm. [uiScale] multiplica **só** o
/// tamanho da fonte: o [TerminalUnzoomBox] desfaz o zoom geométrico do `_AppZoom`, e
/// é este tamanho maior que o repõe. Com zoom em 1.0x é identidade.
ghost.TerminalTheme _ghosttyTheme(
  xterm.TerminalTheme source,
  xterm.TerminalStyle style,
  double uiScale,
  FontWeight fontWeight,
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
  // Use a mesma familia interna registrada por google_fonts para medir as
  // celulas e rasterizar o atlas. Usar apenas o nome humano "JetBrains Mono"
  // pode cair em fontes diferentes no Flutter Linux e alargar cada celula.
  fontFamily: resolveGhosttyFontFamily(
    style.fontFamily,
    bundledJetBrainsMonoResolver: () =>
        GoogleFonts.jetBrainsMono(fontWeight: fontWeight).fontFamily,
  ),
  fontFamilyFallback: style.fontFamilyFallback,
  fontSize: style.fontSize * uiScale,
  fontWeight: fontWeight,
);

/// The xterm callback and Ghostty shortcut map accept the same gestures.
bool isTerminalPasteEvent(KeyEvent event) {
  if (event is! KeyDownEvent || event.logicalKey != LogicalKeyboardKey.keyV) {
    return false;
  }
  final keyboard = HardwareKeyboard.instance;
  return !keyboard.isAltPressed &&
      !keyboard.isShiftPressed &&
      (keyboard.isControlPressed != keyboard.isMetaPressed);
}
