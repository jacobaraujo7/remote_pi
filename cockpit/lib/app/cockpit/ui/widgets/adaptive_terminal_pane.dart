import 'package:cockpit/app/core/terminal/ghostty_font_family.dart';
import 'package:cockpit/app/core/domain/entities/app_settings.dart';
import 'package:cockpit/app/core/terminal/terminal_controller.dart';
import 'package:cockpit/app/core/terminal/terminal_font_weight.dart';
import 'package:cockpit/app/core/terminal/terminal_zoom.dart';
import 'package:cockpit/app/core/terminal/xterm/xterm.dart' as xterm;
import 'package:cockpit/app/core/ui/settings_controller.dart';
import 'package:flterm/flterm.dart' as ghost;
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_modular/flutter_modular.dart';
import 'package:url_launcher/url_launcher.dart';

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

  @override
  Widget build(BuildContext context) => switch (terminal) {
    final XtermTerminalController value => TerminalPane(
      terminal: value.terminal,
      active: active,
      focusNode: focusNode,
      textStyle: textStyle,
      theme: theme,
      hardwareKeyboardOnly: readOnly,
      onKeyEvent: onKeyEvent ?? (_) => KeyEventResult.ignored,
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
    ),
  };
}

final class _CockpitPasteIntent extends Intent {
  const _CockpitPasteIntent();
}

class _GhosttyPane extends StatelessWidget {
  const _GhosttyPane({
    required this.terminal,
    required this.active,
    required this.focusNode,
    required this.textStyle,
    required this.theme,
    required this.onPaste,
    required this.onOpenFile,
    required this.readOnly,
  });

  final GhosttyTerminalController terminal;
  final bool active;
  final FocusNode focusNode;
  final xterm.TerminalStyle textStyle;
  final xterm.TerminalTheme theme;
  final VoidCallback? onPaste;
  final void Function(String path, {int? line})? onOpenFile;
  final bool readOnly;

  @override
  Widget build(BuildContext context) {
    // IndexedStack mantém a sessão e este widget montados. Remover somente a
    // view terminal inativa desanexa seus listeners/render objects; o parser e
    // o scrollback continuam vivos no controller, sem layout/paint invisível a
    // cada batch de output. Ao reativar, a view reconecta ao estado atual.
    if (!active) return const SizedBox.expand();

    final shortcuts = <ShortcutActivator, Intent>{};
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

    final ghosttyTheme = _ghosttyTheme(theme, textStyle, uiScale, fontWeight);

    final Widget terminalView = ghost.TerminalView(
      controller: terminal.controller,
      focusNode: focusNode,
      showKeyboard: !readOnly,
      padding: EdgeInsets.zero,
      scrollPhysics: const ClampingScrollPhysics(),
      shortcuts: shortcuts,
      theme: ghosttyTheme,
      linkSettings: ghost.LinkSettings(onActivate: (link) => _openLink(link)),
    );

    final view = TerminalUnzoomBox(scale: uiScale, child: terminalView);

    return Actions(
      actions: <Type, Action<Intent>>{
        _CockpitPasteIntent: CallbackAction<_CockpitPasteIntent>(
          onInvoke: (_) {
            onPaste?.call();
            return null;
          },
        ),
      },
      child: view,
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
  fontFamily: resolveGhosttyFontFamily(style.fontFamily),
  fontFamilyFallback: style.fontFamilyFallback,
  fontSize: style.fontSize * uiScale,
  fontWeight: fontWeight,
);
