// ignore_for_file: implementation_imports, invalid_use_of_internal_member

import 'package:cockpit/app/core/domain/entities/app_settings.dart';
import 'package:cockpit/app/core/terminal/ghostty_font_family.dart';
import 'package:cockpit/app/core/terminal/terminal_context_menu.dart';
import 'package:cockpit/app/core/terminal/terminal_controller.dart';
import 'package:cockpit/app/core/terminal/terminal_font_weight.dart';
import 'package:cockpit/app/core/terminal/terminal_zoom.dart';
import 'package:cockpit/app/core/terminal/xterm/xterm.dart' as xterm;
import 'package:cockpit/app/core/ui/settings_controller.dart';
import 'package:flterm/flterm.dart' as ghost;
import 'package:flterm/src/controller/terminal_controller.dart'
    as ghost_internal;
import 'package:flterm/src/links/logical_line.dart' as ghost_internal;
import 'package:flterm/src/rendering/font/measure_cell_metrics.dart'
    as ghost_internal;
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_modular/flutter_modular.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:libghostty/libghostty.dart' as native;
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
    this.enableLineHover = false,
    this.onContextMenu,
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
  final bool enableLineHover;
  final TerminalContextMenuCallback? onContextMenu;

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
      enableLineHover: enableLineHover,
      onContextMenu: onContextMenu,
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
      enableLineHover: enableLineHover,
      onContextMenu: onContextMenu,
    ),
  };
}

final class _CockpitPasteIntent extends Intent {
  const _CockpitPasteIntent();
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
    required this.enableLineHover,
    required this.onContextMenu,
  });

  final GhosttyTerminalController terminal;
  final bool active;
  final FocusNode focusNode;
  final xterm.TerminalStyle textStyle;
  final xterm.TerminalTheme theme;
  final VoidCallback? onPaste;
  final void Function(String path, {int? line})? onOpenFile;
  final bool readOnly;
  final bool enableLineHover;
  final TerminalContextMenuCallback? onContextMenu;

  @override
  State<_GhosttyPane> createState() => _GhosttyPaneState();
}

class _GhosttyPaneState extends State<_GhosttyPane> {
  late final ghost.TerminalScrollController _scrollController;
  late final native.RenderState _renderState;
  TerminalLineHit? _hoverLine;
  Offset? _lastHoverLocal;
  Size? _lastSize;
  double _visibleCellHeight = 0;

  static const _lineHoverOpacity = 0.12;

  @override
  void initState() {
    super.initState();
    _scrollController = ghost.TerminalScrollController()
      ..addListener(_refreshHover);
    _renderState = native.RenderState();
  }

  @override
  void dispose() {
    _scrollController
      ..removeListener(_refreshHover)
      ..dispose();
    _renderState.dispose();
    super.dispose();
  }

  void _refreshHover() {
    final local = _lastHoverLocal;
    final size = _lastSize;
    if (local != null && size != null) _setHover(_lineAt(local, size));
  }

  TerminalLineHit? _lineAt(Offset local, Size size) {
    if (!widget.enableLineHover || size.isEmpty) return null;
    final controller = widget.terminal.controller;
    final impl = controller as ghost_internal.TerminalControllerImpl;
    _renderState.update(impl.terminal);
    final rows = _renderState.rows;
    final cols = _renderState.cols;
    if (rows <= 0 || cols <= 0) return null;
    if (_visibleCellHeight <= 0) return null;
    final row = (local.dy / _visibleCellHeight).floor();
    if (row < 0 || row >= rows) return null;
    ghost_internal.LogicalLine? line;
    for (final candidate in ghost_internal.LogicalLine.visible(
      impl.terminal,
      rows: rows,
      cols: cols,
    )) {
      if (candidate.cells.any((cell) => cell.row == row)) {
        line = candidate;
        break;
      }
    }
    if (line == null || line.cells.isEmpty) {
      return TerminalLineHit(
        text: '',
        firstViewportRow: row,
        lastViewportRow: row,
      );
    }
    final occupiedRows = line.cells.map((cell) => cell.row);
    return TerminalLineHit(
      text: line.text,
      firstViewportRow: occupiedRows.reduce((a, b) => a < b ? a : b),
      lastViewportRow: occupiedRows.reduce((a, b) => a > b ? a : b),
    );
  }

  void _setHover(TerminalLineHit? value) {
    if (value?.firstViewportRow == _hoverLine?.firstViewportRow &&
        value?.lastViewportRow == _hoverLine?.lastViewportRow &&
        value?.text == _hoverLine?.text) {
      return;
    }
    setState(() => _hoverLine = value);
  }

  @override
  Widget build(BuildContext context) {
    final shortcuts = <ShortcutActivator, Intent>{};
    if (!widget.readOnly && widget.onPaste != null) {
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
    final metrics = ghost_internal.measureCellMetrics(
      fontSize: ghosttyTheme.fontSize,
      fontWeight: ghosttyTheme.fontWeight,
      fontFamily: ghosttyTheme.fontFamily,
      fontFamilyFallback: ghosttyTheme.fontFamilyFallback,
      devicePixelRatio: View.of(context).devicePixelRatio,
    );
    // O TerminalView e layoutado em uiScale e pintado reduzido pelo
    // TerminalUnzoomBox. Esta e a altura exata da celula nas coordenadas do
    // overlay; usar altura-do-painel / linhas acumulava a sobra do grid.
    _visibleCellHeight = metrics.cellHeight / uiScale;

    final Widget terminalView = ghost.TerminalView(
      // IDENTIDADE GLOBAL e estável por sessão (o controller é único por aba).
      // Quando a árvore de panes reestrutura (split envolve a folha num
      // SplitPane, fechar um pane remove um nó), a subárvore da TerminalView
      // MUDA de posição na árvore de widgets. Sem GlobalKey o Flutter RE-INFLA
      // a TerminalView na posição nova (novo initState → attachView) antes do
      // dispose/detach da antiga → "already has an active view", e no mount
      // simultâneo do restore cruza a State entre panes → espelho. Com a
      // GlobalKey o Flutter MOVE o mesmo Element (preserva o ViewAttachment/
      // lease do controller) em vez de recriar. Junto ao [TerminalUnzoomBox]
      // sem LayoutBuilder, mata crash e espelho.
      key: GlobalObjectKey(widget.terminal.controller),
      controller: widget.terminal.controller,
      focusNode: widget.focusNode,
      showKeyboard: !widget.readOnly,
      padding: EdgeInsets.zero,
      scrollPhysics: const ClampingScrollPhysics(),
      scrollController: _scrollController,
      shortcuts: shortcuts,
      theme: ghosttyTheme,
      linkSettings: ghost.LinkSettings(onActivate: (link) => _openLink(link)),
    );

    final view = TerminalUnzoomBox(scale: uiScale, child: terminalView);

    // Aba inativa: a TerminalView fica MONTADA, só não é pintada. Antes ela era
    // trocada por um `SizedBox` e cada volta pra aba pagava um `initState`
    // completo do flterm (ViewAttachment novo, métricas de fonte, atlas,
    // resize) — era o delay visível na troca de aba. `Offstage` mantém o
    // Element/State (nada de re-attach), pula paint e hit-test, e o
    // `TickerMode` desliga o blink do cursor enquanto oculta. O parser e o
    // scrollback seguem no controller, como antes; o que muda é que a view
    // não é destruída. `Offstage` ainda faz layout do filho, mas só quando as
    // constraints mudam, não por batch de output.
    return Offstage(
      offstage: !widget.active,
      child: TickerMode(
        enabled: widget.active,
        child: Actions(
          actions: <Type, Action<Intent>>{
            _CockpitPasteIntent: CallbackAction<_CockpitPasteIntent>(
              onInvoke: (_) {
                widget.onPaste?.call();
                return null;
              },
            ),
          },
          child: Builder(
            builder: (hoverContext) => MouseRegion(
              onHover: (event) {
                final size = hoverContext.size;
                if (size == null) return;
                _lastHoverLocal = event.localPosition;
                _lastSize = size;
                _setHover(_lineAt(event.localPosition, size));
              },
              onExit: (_) {
                _lastHoverLocal = null;
                _lastSize = null;
                _setHover(null);
              },
              child: GestureDetector(
                behavior: HitTestBehavior.translucent,
                onSecondaryTapUp: widget.onContextMenu == null
                    ? null
                    : (details) {
                        final size = hoverContext.size;
                        final line = size == null
                            ? _hoverLine
                            : _lineAt(details.localPosition, size);
                        widget.onContextMenu!(
                          TerminalContextMenuRequest(
                            globalPosition: details.globalPosition,
                            selectedText: widget.terminal.selectedText(),
                            line: line,
                          ),
                        );
                      },
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    view,
                    if (_hoverLine != null && _lastSize != null)
                      Positioned(
                        left: 0,
                        right: 0,
                        top: _hoverLine!.firstViewportRow * _visibleCellHeight,
                        height:
                            (_hoverLine!.lastViewportRow -
                                _hoverLine!.firstViewportRow +
                                1) *
                            _visibleCellHeight,
                        child: IgnorePointer(
                          child: ColoredBox(
                            color: widget.theme.selection.withValues(
                              alpha: _lineHoverOpacity,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  void _openLink(ghost.ActivatedLink link) {
    final file = link.file;
    if (file != null && widget.onOpenFile != null) {
      widget.onOpenFile!(file.path, line: file.line);
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
