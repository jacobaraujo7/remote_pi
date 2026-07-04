import 'package:flutter/gestures.dart';
import 'package:flutter/scheduler.dart' show Ticker;
import 'package:flutter/services.dart' show HardwareKeyboard, KeyEvent;
import 'package:flutter/widgets.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:xterm/xterm.dart';

import 'cockpit_terminal.dart';
import 'cockpit_terminal_render.dart';
import 'terminal_link.dart';

/// Envólucro do [CockpitTerminal] que adiciona **auto-scroll durante a
/// seleção por arraste**: quando o mouse passa da borda superior/inferior do
/// terminal enquanto seleciona, a viewport rola na direção e a seleção
/// acompanha (como num editor/terminal nativo).
///
/// Por que existe: o xterm 4.0 só estende a seleção no `onDragUpdate` (que só
/// dispara quando o ponteiro se move) e **nunca rola a viewport**. Resultado: ao
/// arrastar pra baixo de um texto longo, a tela ficava parada. Aqui escutamos os
/// eventos crus do ponteiro, rolamos via [ScrollController] e dirigimos a
/// seleção a partir de uma âncora fixa — assim o início não "escorrega" quando a
/// viewport rola (o que aconteceria se reusássemos o cálculo por pixel do xterm,
/// que não compensa o scroll).
class TerminalPane extends StatefulWidget {
  const TerminalPane({
    super.key,
    required this.terminal,
    required this.focusNode,
    required this.textStyle,
    required this.theme,
    required this.onKeyEvent,
    this.hardwareKeyboardOnly = false,
    this.onOpenFile,
  });

  final Terminal terminal;
  final FocusNode focusNode;
  final TerminalStyle textStyle;
  final TerminalTheme theme;
  final KeyEventResult Function(KeyEvent event) onKeyEvent;
  final bool hardwareKeyboardOnly;

  /// Cmd+clique num caminho de arquivo do buffer → abre no FileViewer. `null`
  /// desliga a detecção de arquivos (mantém só URLs). [line] vem do sufixo
  /// `arquivo:42`, quando presente.
  final void Function(String path, {int? line})? onOpenFile;

  @override
  State<TerminalPane> createState() => _TerminalPaneState();
}

class _TerminalPaneState extends State<TerminalPane>
    with SingleTickerProviderStateMixin {
  final _viewKey = GlobalKey<CockpitTerminalState>();
  final _scroll = ScrollController();
  late final _SelectionGuardController _controller;
  late final Ticker _ticker;

  /// Quão próximo da borda (px) o arraste já dispara o auto-scroll.
  static const _edgeZone = 24.0;

  /// Distância além da borda (px) que satura a velocidade do auto-scroll.
  static const _maxOvershoot = 80.0;

  /// Passo máximo de rolagem por frame (px), atingido na saturação.
  static const _maxStep = 18.0;

  /// Movimento mínimo (px) com o botão pressionado pra contar como "arraste".
  /// Abaixo disso é clique/duplo-clique — esses seguem no gesto do xterm.
  static const _dragSlop = 3.0;

  Offset? _downLocal; // pointer-down em coords do RenderTerminal
  Offset? _pointer; // última posição do ponteiro (mesmas coords)
  CellAnchor? _anchor; // início fixo da seleção (acompanha o buffer)
  bool _selecting = false;

  /// Resto fracionário de linha acumulado ao encaminhar o wheel pra app (trackpad
  /// manda deltas pequenos e frequentes; sem acumular, arredondaríamos cada um
  /// pra 1 linha e o scroll ficaria rápido demais).
  double _wheelLineAccum = 0;

  /// Instante do último evento de wheel encaminhado. Se passou tempo suficiente
  /// desde o último, tratamos como **gesto novo** e zeramos o resíduo acumulado —
  /// senão a sobra do gesto anterior (às vezes de sinal contrário) faz os
  /// primeiros eventos do novo scroll serem engolidos ("tinha que rolar mais").
  DateTime? _lastWheelAt;

  /// Além dessa pausa, o próximo wheel conta como início de um gesto novo.
  static const _wheelGestureGap = Duration(milliseconds: 150);

  /// True enquanto um clique/arraste está sendo **encaminhado pra TUI** (claude/
  /// vim com mouse reporting). Nesse modo o `TerminalPane` é a única autoridade
  /// de mouse: manda botão down no toque, motion durante o arraste e up no
  /// soltar — o gesto interno do xterm não encaminha nada (evita duplicar).
  bool _forwardingMouse = false;
  CellOffset? _tuiLastCell; // última célula reportada (motion só em mudança)

  // --- Abrir URL com Cmd (hover → mãozinha + realce; Cmd+clique → abre) ---
  final _linkDetector = TerminalLinkDetector();
  MouseCursor _cursor = SystemMouseCursors.text;
  TerminalLink? _hoverLink; // link sob o ponteiro (só quando Cmd está segurado)
  TerminalHighlight? _linkHighlight; // realce do link (removível)
  Offset? _lastHoverGlobal; // pra reavaliar quando o Cmd muda sem mover o mouse

  @override
  void initState() {
    super.initState();
    _controller = _SelectionGuardController();
    _ticker = createTicker(_onTick);
    // Cmd pressionado/solto sem mover o mouse também atualiza o realce/cursor.
    HardwareKeyboard.instance.addHandler(_onKey);
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_onKey);
    _linkHighlight?.dispose();
    _ticker.dispose();
    _anchor?.dispose();
    _scroll.dispose();
    _controller.dispose();
    super.dispose();
  }

  bool _onKey(KeyEvent _) {
    _evaluateHover(_lastHoverGlobal); // reavalia com a última posição conhecida
    return false; // não consome — só observa o estado do Cmd
  }

  CockpitTerminalRender? get _render => _viewKey.currentState?.renderTerminal;

  bool get _isCmd => HardwareKeyboard.instance.isMetaPressed;

  /// ⌥ (Option) segurado força a seleção **local** mesmo quando a app dona o
  /// mouse — é o escape hatch pra copiar texto cru, igual iTerm/Terminal.app.
  bool get _isAlt => HardwareKeyboard.instance.isAltPressed;

  /// A app declarou mouse reporting (claude/vim): ela dona cliques e seleção.
  bool get _appOwnsMouse => widget.terminal.mouseMode != MouseMode.none;

  /// Reavalia o link sob [global] (coords globais). Só detecta com Cmd segurado:
  /// sem Cmd, o terminal opera normal (seleção / clique vai pro app).
  void _evaluateHover(Offset? global) {
    final r = _render;
    if (r == null || global == null) {
      _setHoverLink(null);
      return;
    }
    final link = _isCmd
        ? _linkDetector.linkAt(
            widget.terminal,
            r.getCellOffset(r.globalToLocal(global)),
            detectFiles: widget.onOpenFile != null,
          )
        : null;
    _setHoverLink(link);
  }

  void _setHoverLink(TerminalLink? link) {
    final same =
        link?.target == _hoverLink?.target &&
        link?.row == _hoverLink?.row &&
        link?.startCol == _hoverLink?.startCol;
    if (same) return;

    _linkHighlight?.dispose();
    _linkHighlight = null;
    _hoverLink = link;

    if (link != null) {
      final b = widget.terminal.buffer;
      _linkHighlight = _controller.highlight(
        p1: b.createAnchorFromOffset(CellOffset(link.startCol, link.row)),
        p2: b.createAnchorFromOffset(CellOffset(link.endCol, link.row)),
        color: widget.theme.selection,
      );
    }
    setState(() {
      _cursor = link != null
          ? SystemMouseCursors.click
          : SystemMouseCursors.text;
    });
  }

  void _openLink(String url) {
    final raw = url.startsWith('www.') ? 'https://$url' : url;
    final uri = Uri.tryParse(raw);
    if (uri != null && uri.hasScheme) {
      launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  void _onPointerDown(PointerDownEvent e) {
    // Toque não seleciona por arraste no desktop; só mouse/trackpad com botão.
    if (e.kind == PointerDeviceKind.touch) return;
    if ((e.buttons & kPrimaryButton) == 0) return;
    // Com Cmd, o clique é pra abrir link — não inicia seleção.
    if (_isCmd) return;
    final r = _render;
    if (r == null) return;
    // App dona o mouse (claude/vim): encaminhamos clique+arraste pra ela (ela faz
    // a própria seleção e rola junto). ⌥ segurado fura isso → seleção local pra
    // copiar texto cru (igual iTerm).
    if (_appOwnsMouse && !_isAlt) {
      final cell = r.getCellOffset(r.globalToLocal(e.position));
      _forwardingMouse = true;
      _tuiLastCell = cell;
      widget.terminal.mouseInput(
        TerminalMouseButton.left,
        TerminalMouseButtonState.down,
        cell,
      );
      return;
    }
    _downLocal = r.globalToLocal(e.position);
    _pointer = _downLocal;
    _selecting = false;
  }

  void _onPointerMove(PointerMoveEvent e) {
    if ((e.buttons & kPrimaryButton) == 0) return;
    final r = _render;
    if (r == null) return;
    // Encaminhando pra TUI: manda motion (botão segurado) a cada mudança de
    // célula — é isso que faz o arraste virar seleção dentro do claude/vim.
    if (_forwardingMouse) {
      final cell = r.getCellOffset(r.globalToLocal(e.position));
      if (_tuiLastCell != null &&
          cell.x == _tuiLastCell!.x &&
          cell.y == _tuiLastCell!.y) {
        return;
      }
      _tuiLastCell = cell;
      _sendMouseMotion(cell);
      return;
    }
    final down = _downLocal;
    if (down == null) return;
    final local = r.globalToLocal(e.position);
    _pointer = local;
    if (!_selecting) {
      if ((local - down).distance < _dragSlop) return;
      _beginSelecting(r, down);
    }
    _extendSelection(r);
    _syncAutoScroll(r);
  }

  void _onPointerUp(PointerUpEvent e) {
    // Fim do encaminhamento pra TUI: solta o botão na célula atual.
    if (_forwardingMouse) {
      final r = _render;
      if (r != null) {
        final cell = r.getCellOffset(r.globalToLocal(e.position));
        widget.terminal.mouseInput(
          TerminalMouseButton.left,
          TerminalMouseButtonState.up,
          cell,
        );
      }
      _forwardingMouse = false;
      _tuiLastCell = null;
      return;
    }
    // Cmd+clique (sem arraste) sobre um link → arquivo abre no FileViewer, URL
    // no navegador.
    if (_isCmd && !_selecting && _hoverLink != null) {
      final link = _hoverLink!;
      if (link.kind == TerminalLinkKind.file) {
        widget.onOpenFile?.call(link.target, line: link.line);
      } else {
        _openLink(link.target);
      }
    }
    _finishSelecting();
  }

  /// Encaminha um evento de **motion** (ponteiro movido com botão segurado) pra
  /// TUI. O `mouseInput` do xterm só sabe `down`/`up` — o protocolo de mouse
  /// (1002/1003) reporta motion com o **bit 32** somado ao id do botão. Como o
  /// reporter do xterm não expõe isso, montamos a sequência aqui e mandamos pelo
  /// mesmo `onOutput` que o `mouseInput` usaria. Só vale pros modos que rastreiam
  /// arraste/movimento — senão a app não espera motion.
  void _sendMouseMotion(CellOffset cell) {
    final mode = widget.terminal.mouseMode;
    if (mode != MouseMode.upDownScrollDrag &&
        mode != MouseMode.upDownScrollMove) {
      return;
    }
    final out = widget.terminal.onOutput;
    if (out == null) return;
    const motionLeft = 0 + 32; // botão esquerdo (0) + bit de motion (32)
    final x = cell.x + 1; // protocolo é 1-based
    final y = cell.y + 1;
    final seq = switch (widget.terminal.mouseReportMode) {
      MouseReportMode.sgr => '\x1b[<$motionLeft;$x;${y}M',
      MouseReportMode.urxvt => '\x1b[${32 + motionLeft};$x;${y}M',
      MouseReportMode.normal || MouseReportMode.utf =>
        '\x1b[M${String.fromCharCode(32 + motionLeft)}'
            '${String.fromCharCode(32 + x)}${String.fromCharCode(32 + y + 1)}',
    };
    out(seq);
  }

  void _onPointerSignal(PointerSignalEvent e) {
    if (e is! PointerScrollEvent) return;
    final term = widget.terminal;
    // "App dona o scroll" = declarou mouse reporting com scroll (claude/vim).
    // Nesse caso ela **repinta** as células ao rolar; a seleção ancorada não tem
    // como acompanhar (vira realce sobre texto trocado), então limpamos. O mesmo
    // vale pro alt-buffer puro (less etc.). No buffer normal sem mouse reporting
    // o scroll move o nosso scrollback e a seleção acompanha — não mexemos.
    final appOwnsScroll = term.mouseMode.reportScroll;
    final alt = term.buffer.isAltBuffer;
    if ((appOwnsScroll || alt) && _controller.selection != null) {
      _controller.clearSelection();
    }
    // App dona o scroll (claude/vim) → **nós** somos a única autoridade do wheel,
    // nos dois buffers. O nosso Scrollable interno vira NeverScrollable e o
    // TerminalScrollGestureHandler do xterm (que montaria um 2º Scrollable no
    // alt-buffer) é desligado nesse modo (ver cockpit_terminal.dart) — então não
    // há duplicação nem disputa de dois scrollables pelo mesmo pointer signal.
    // Antes o `!alt` delegava o alt-buffer pro xterm, e a disputa dos dois
    // scrollables fazia o scroll "morrer" quando claude entrava na UI full-screen.
    if (appOwnsScroll) {
      // Wheel de mouse é entrada **discreta** (um notch por evento); trackpad é
      // contínuo. A distinção decide se acumulamos a fração de linha (ver
      // [_forwardWheel]).
      _forwardWheel(
        e.scrollDelta.dy,
        e.position,
        discrete: e.kind == PointerDeviceKind.mouse,
      );
    }
  }

  // --- Trackpad como pan/zoom (resiliência a sleep/wake no macOS) -------------
  // No macOS o two-finger scroll normalmente chega como `PointerScrollEvent`
  // sintetizado (tratado no [_onPointerSignal]). Mas **depois de dormir/acordar**
  // o embedder às vezes passa a entregar o trackpad como eventos **pan/zoom** e
  // para de sintetizar o scroll. O `Scrollable` (terminal fora do harness)
  // consome pan/zoom nativamente e sobrevive; o nosso caminho `appOwnsScroll`
  // (claude/vim), que só escutava `onPointerSignal`, ficava mudo até reiniciar.
  // Tratando pan/zoom aqui, encaminhamos o wheel pro harness nos dois modos de
  // entrega — o scroll interno do claude volta a funcionar sem restart.

  /// Pan cumulativo do gesto pan/zoom em curso; usado pra derivar o delta por
  /// update ([PointerPanZoomUpdateEvent.pan] é acumulado desde o start).
  Offset _panZoomLast = Offset.zero;

  void _onPointerPanZoomStart(PointerPanZoomStartEvent e) {
    _panZoomLast = Offset.zero;
    // Início de gesto novo: zera o resíduo fracionário de linha.
    _wheelLineAccum = 0;
    _lastWheelAt = null;
  }

  void _onPointerPanZoomUpdate(PointerPanZoomUpdateEvent e) {
    final term = widget.terminal;
    // Só encaminhamos quando a app dona o scroll; fora disso o `Scrollable`
    // nativo já trata o pan/zoom (não duplicar).
    if (!term.mouseMode.reportScroll) return;
    final dy = e.pan.dy - _panZoomLast.dy;
    _panZoomLast = e.pan;
    if (_controller.selection != null) _controller.clearSelection();
    // O pan tem sinal oposto ao scrollDelta (dedo pra cima = pan.dy negativo =
    // ver conteúdo abaixo = scroll down); invertendo, reusamos a mesma convenção
    // de sinal do [_forwardWheel]. Trackpad → contínuo (discrete: false).
    _forwardWheel(-dy, e.position, discrete: false);
  }

  /// Encaminha `deltaY` (em px, convenção de `scrollDelta`) pro harness como
  /// eventos de wheel. [discrete] = mouse (um notch mínimo por evento, sem
  /// acumular); contínuo = trackpad (acumula a fração de linha).
  void _forwardWheel(
    double deltaY,
    Offset globalPosition, {
    required bool discrete,
  }) {
    final r = _render;
    if (r == null) return;
    final lineHeight = r.lineHeight;
    if (lineHeight <= 0) return;
    final lines = deltaY / lineHeight;
    if (lines == 0) return;
    final int steps;
    if (discrete) {
      // Giro lento (delta < 1 linha, espaçado) arredondaria pra 0 e não pegava;
      // garantimos ao menos 1 linha no sentido. Notches maiores rolam proporcional.
      final mag = lines.abs().round();
      steps = (mag < 1 ? 1 : mag) * (lines.isNegative ? -1 : 1);
    } else {
      // Deltas pequenos e frequentes — acumulamos pra não rolar rápido demais.
      // Reset por gesto (após pausa) evita arrastar o resíduo do gesto anterior;
      // `round` (não `truncate`) faz o primeiro delta já valer sem exigir uma
      // linha inteira.
      final now = DateTime.now();
      if (_lastWheelAt == null ||
          now.difference(_lastWheelAt!) > _wheelGestureGap) {
        _wheelLineAccum = 0;
      }
      _lastWheelAt = now;
      _wheelLineAccum += lines;
      steps = _wheelLineAccum.round();
      if (steps == 0) return;
      _wheelLineAccum -= steps;
    }
    final cell = r.getCellOffset(r.globalToLocal(globalPosition));
    final button = steps < 0
        ? TerminalMouseButton.wheelUp
        : TerminalMouseButton.wheelDown;
    for (var i = 0; i < steps.abs(); i++) {
      widget.terminal.mouseInput(button, TerminalMouseButtonState.down, cell);
    }
  }

  void _onPointerCancel(PointerCancelEvent e) {
    if (_forwardingMouse) {
      final r = _render;
      final cell = r?.getCellOffset(r.globalToLocal(e.position)) ?? _tuiLastCell;
      if (cell != null) {
        widget.terminal.mouseInput(
          TerminalMouseButton.left,
          TerminalMouseButtonState.up,
          cell,
        );
      }
      _forwardingMouse = false;
      _tuiLastCell = null;
    }
    _finishSelecting();
  }

  void _beginSelecting(CockpitTerminalRender r, Offset down) {
    _anchor?.dispose();
    _anchor = widget.terminal.buffer.createAnchorFromOffset(
      r.getCellOffset(down),
    );
    _selecting = true;
    // A partir daqui ignoramos a seleção do gesto interno do xterm — nós a
    // dirigimos por completo enquanto o arraste durar.
    _controller.suppressGestureSelection = true;
  }

  /// Estende a seleção da âncora fixa até o ponteiro, **clampando** o Y dentro
  /// da viewport: assim, com o ponteiro além da borda, o extremo acompanha a
  /// linha visível mais próxima — que avança no buffer conforme a viewport rola.
  void _extendSelection(CockpitTerminalRender r) {
    final anchor = _anchor;
    final p = _pointer;
    if (anchor == null || p == null || !anchor.attached) return;
    final h = r.size.height;
    final clampedY = p.dy.clamp(0.0, h - 1.0);
    final from = anchor.offset;
    var to = r.getCellOffset(Offset(p.dx, clampedY));
    // Mesma regra do xterm: ao arrastar pra frente, inclui a célula sob o
    // cursor pra seleção não ficar "uma célula curta".
    if (to.x >= from.x) {
      to = CellOffset(to.x + 1, to.y);
    }
    final buffer = widget.terminal.buffer;
    _controller.setSelectionFromGuard(
      buffer.createAnchorFromOffset(from),
      buffer.createAnchorFromOffset(to),
    );
  }

  void _syncAutoScroll(CockpitTerminalRender r) {
    if (_overshoot(r) == 0) {
      if (_ticker.isActive) _ticker.stop();
    } else if (!_ticker.isActive) {
      _ticker.start();
    }
  }

  /// Quanto o ponteiro passou da zona de borda. `< 0` = acima (rola pra cima),
  /// `> 0` = abaixo (rola pra baixo), `0` = dentro (sem auto-scroll).
  double _overshoot(CockpitTerminalRender r) {
    final p = _pointer;
    if (p == null) return 0;
    final h = r.size.height;
    if (p.dy < _edgeZone) return p.dy - _edgeZone;
    if (p.dy > h - _edgeZone) return p.dy - (h - _edgeZone);
    return 0;
  }

  void _onTick(Duration _) {
    final r = _render;
    if (r == null || !_selecting) {
      _ticker.stop();
      return;
    }
    final over = _overshoot(r);
    if (over == 0) {
      _ticker.stop();
      return;
    }
    if (_scroll.hasClients) {
      final pos = _scroll.position;
      final frac = (over.abs() / _maxOvershoot).clamp(0.0, 1.0);
      final step = over.sign * frac * _maxStep;
      final next = (pos.pixels + step).clamp(
        pos.minScrollExtent,
        pos.maxScrollExtent,
      );
      if (next != pos.pixels) {
        _scroll.jumpTo(next);
      }
    }
    // A viewport rolou → reestende a seleção até a nova borda visível.
    _extendSelection(r);
  }

  void _finishSelecting() {
    if (_ticker.isActive) _ticker.stop();
    if (_selecting) {
      _selecting = false;
      _controller.suppressGestureSelection = false;
    }
    _anchor?.dispose();
    _anchor = null;
    _downLocal = null;
    _pointer = null;
  }

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: _cursor,
      onHover: (e) {
        _lastHoverGlobal = e.position;
        _evaluateHover(e.position);
      },
      onExit: (_) {
        _lastHoverGlobal = null;
        _setHoverLink(null);
      },
      child: Listener(
        onPointerDown: _onPointerDown,
        onPointerMove: _onPointerMove,
        onPointerUp: _onPointerUp,
        onPointerCancel: _onPointerCancel,
        onPointerSignal: _onPointerSignal,
        // Trackpad entregue como pan/zoom (pós sleep/wake no macOS): encaminha o
        // scroll pro harness igual ao onPointerSignal. Ver [_onPointerPanZoomUpdate].
        onPointerPanZoomStart: _onPointerPanZoomStart,
        onPointerPanZoomUpdate: _onPointerPanZoomUpdate,
        // O cursor é decidido pelo MouseRegion acima (mãozinha sobre link com
        // Cmd, senão I-beam); o CockpitTerminal defere o dele pra cá.
        child: CockpitTerminal(
          widget.terminal,
          key: _viewKey,
          controller: _controller,
          scrollController: _scroll,
          focusNode: widget.focusNode,
          hardwareKeyboardOnly: widget.hardwareKeyboardOnly,
          onKeyEvent: (_, event) => widget.onKeyEvent(event),
          theme: widget.theme,
          textStyle: widget.textStyle,
          mouseCursor: MouseCursor.defer,
        ),
      ),
    );
  }
}

/// [TerminalController] que ignora as escritas de seleção do gesto **interno**
/// do xterm enquanto o [TerminalPane] está dirigindo a seleção (arraste com
/// auto-scroll). Sem isso, o `onDragUpdate` do xterm — que recalcula o início a
/// partir de um pixel fixo, sem compensar o scroll — brigaria com a nossa
/// seleção ancorada e a faria "pular".
class _SelectionGuardController extends TerminalController {
  bool suppressGestureSelection = false;
  bool _fromGuard = false;

  void setSelectionFromGuard(
    CellAnchor base,
    CellAnchor extent, {
    SelectionMode? mode,
  }) {
    _fromGuard = true;
    setSelection(base, extent, mode: mode);
    _fromGuard = false;
  }

  @override
  void setSelection(CellAnchor base, CellAnchor extent, {SelectionMode? mode}) {
    if (suppressGestureSelection && !_fromGuard) {
      // O xterm transfere a posse das âncoras esperando que sejam consumidas;
      // como vamos ignorá-las, liberamos pra não vazar.
      base.dispose();
      extent.dispose();
      return;
    }
    super.setSelection(base, extent, mode: mode);
  }
}
