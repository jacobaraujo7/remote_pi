import 'dart:async';
import 'dart:io';

import 'package:cockpit/app/core/ui/themes/themes.dart';
import 'package:flutter/gestures.dart' show PointerDeviceKind;
import 'package:cockpit/app/core/ui/widgets/app_tooltip.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';
import 'package:window_manager/window_manager.dart';

/// Botão verde do semáforo (macOS) e botão maximize (Win/Linux).
/// No macOS segue a convenção nativa: verde = tela cheia (Space próprio).
Future<void> _toggleMaximize() async {
  if (Platform.isMacOS) {
    final isFull = await windowManager.isFullScreen();
    await windowManager.setFullScreen(!isFull);
  } else if (await windowManager.isMaximized()) {
    await windowManager.unmaximize();
  } else {
    await windowManager.maximize();
  }
}

/// Duplo-clique na titlebar. No macOS o `maximize()` do window_manager é
/// `NSWindow.zoom` — estica pro máximo da tela SEM entrar em tela cheia (não
/// cria outra Mesa), que é o comportamento nativo do duplo-clique. No
/// Windows/Linux maximize/unmaximize é o esperado mesmo.
Future<void> _toggleZoom() async {
  if (Platform.isMacOS && await windowManager.isFullScreen()) {
    // Se já está em tela cheia (via botão verde), duplo-clique sai dela.
    await windowManager.setFullScreen(false);
    return;
  }
  if (await windowManager.isMaximized()) {
    await windowManager.unmaximize();
  } else {
    await windowManager.maximize();
  }
}

/// Barra de título customizada (~46px): arrasta a janela e maximiza no
/// duplo-clique, **sem atrasar o tap dos botões**.
///
/// O pulo do gato é manter o [DragToMoveArea] numa **camada de fundo** (atrás
/// dos [children]) em vez de envelopá-los. O `DragToMoveArea` usa `onDoubleTap`,
/// e o `DoubleTapGestureRecognizer` dele **segura a arena de gestos** por
/// `kDoubleTapTimeout` (300ms) esperando um segundo clique. Se os botões forem
/// descendentes dele, **todo** `onTap` herda esse atraso — o "input lag" de ~1s
/// percebido ao fechar/minimizar/maximizar e nos toggles de pane.
///
/// Com o drag no fundo, os botões capturam o tap na hora; vãos, `Spacer` e
/// textos da [Row] não absorvem o ponteiro e caem (translúcidos) pro fundo
/// arrastável — então arrastar a janela e o duplo-clique-maximiza continuam
/// funcionando em qualquer área vazia da barra.
class WindowTitleBar extends StatelessWidget {
  const WindowTitleBar({super.key, required this.children});

  /// Conteúdo da barra (semáforo, toggles, título, …). Vão direto numa [Row].
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Container(
      height: 46,
      decoration: BoxDecoration(
        color: colors.bg,
        border: Border(bottom: BorderSide(color: colors.border)),
      ),
      child: Stack(
        children: [
          // Fundo arrastável — ATRÁS dos botões (ver doc da classe).
          const Positioned.fill(child: _DragToMoveArea()),
          // Camada interativa — botões disparam o onTap sem o hold da arena.
          Positioned.fill(
            child: Padding(
              // O recuo à esquerda existe pro semáforo do macOS respirar longe
              // do canto arredondado da janela. No Windows/Linux não há controle
              // nenhum à esquerda (eles vão pra direita, via
              // [WindowControlsTrailing]), então o mesmo 18 vira espaço morto e
              // empurra o primeiro item pra dentro sem motivo.
              // Windows/Linux: caption cola no canto direito (sem padding).
              padding: EdgeInsets.only(
                left: Platform.isMacOS ? 18 : 8,
                right: Platform.isWindows || Platform.isLinux ? 0 : 12,
              ),
              child: Row(children: children),
            ),
          ),
        ],
      ),
    );
  }
}

/// Área que arrasta a janela — **inclusive no toque**.
///
/// Substitui o `DragToMoveArea` do window_manager, que é mouse-only no Windows:
/// ele chama `startDragging()`, que faz
/// `SendMessage(WM_SYSCOMMAND, SC_MOVE | HTCAPTION)` — o loop modal de mover do
/// Windows, que rastreia o **mouse**. O dedo é entregue como `WM_POINTER` para a
/// view do Flutter, então o loop nunca recebe movimento e a janela fica parada
/// (medido: arrastar a barra com o dedo não movia um pixel).
///
/// Por isso o caminho é escolhido pelo tipo do ponteiro:
///
/// - **mouse/stylus** → `startDragging()` nativo. Mais suave e integra com o
///   snap/aero do Windows; não dá pra reproduzir isso na mão.
/// - **toque** → arrasto manual: guarda o offset do dedo dentro da janela no
///   down e reposiciona a janela a cada move. Mantém o ponto sob o dedo.
///
/// O `onPanStart` do gesture detector é restrito a `supportedDevices` **sem**
/// toque de propósito: se o caminho nativo disparasse junto, o loop modal
/// entraria e brigaria com o reposicionamento manual.
class _DragToMoveArea extends StatefulWidget {
  const _DragToMoveArea();

  @override
  State<_DragToMoveArea> createState() => _DragToMoveAreaState();
}

class _DragToMoveAreaState extends State<_DragToMoveArea> {
  /// Posição do dedo (relativa à janela) no último reposicionamento, e a origem
  /// da janela naquele instante. Movemos a janela pelo delta entre elas, então o
  /// ponto tocado não escorrega.
  Offset? _grab;
  Offset? _origin;

  /// Um reposicionamento por vez: `setPosition` é chamada de plataforma e os
  /// moves de toque chegam mais rápido do que ela responde. Sem isso a fila
  /// cresce e a janela segue andando depois que o dedo já parou.
  bool _busy = false;

  Future<void> _onDown(PointerDownEvent e) async {
    if (e.kind != PointerDeviceKind.touch) return;
    // Maximizada não se arrasta — o Windows também não deixa, e `setPosition`
    // nela não faria nada de útil.
    if (await windowManager.isMaximized()) return;
    if (!mounted) return;
    _origin = await windowManager.getPosition();
    _grab = e.position;
  }

  Future<void> _onMove(PointerMoveEvent e) async {
    if (e.kind != PointerDeviceKind.touch) return;
    final grab = _grab;
    final origin = _origin;
    if (grab == null || origin == null) return;
    if (_busy) return; // descarta: o próximo move já traz a posição atual
    _busy = true;
    try {
      // `e.position` é relativo à janela; como a janela se move junto, o delta
      // contra o último ponto agarrado é o quanto ela deve andar.
      await windowManager.setPosition(origin + (e.position - grab));
      if (!mounted) return;
      _origin = await windowManager.getPosition();
      _grab = e.position;
    } finally {
      _busy = false;
    }
  }

  void _onUp(PointerEvent e) {
    _grab = null;
    _origin = null;
  }

  @override
  Widget build(BuildContext context) {
    // Duplo-toque continua valendo pra TODOS os dispositivos (inclusive dedo) —
    // por isso ele fica num detector próprio, fora do `supportedDevices` que
    // restringe só o arrasto nativo.
    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onDoubleTap: _toggleZoom,
      child: Listener(
        behavior: HitTestBehavior.translucent,
        onPointerDown: (e) => unawaited(_onDown(e)),
        onPointerMove: (e) => unawaited(_onMove(e)),
        onPointerUp: _onUp,
        onPointerCancel: _onUp,
        child: GestureDetector(
          behavior: HitTestBehavior.translucent,
          // SEM toque: o caminho nativo é mouse-only (ver doc da classe) e, se
          // disparasse no dedo, o loop modal brigaria com o arrasto manual.
          supportedDevices: const {
            PointerDeviceKind.mouse,
            PointerDeviceKind.stylus,
            PointerDeviceKind.invertedStylus,
            PointerDeviceKind.trackpad,
          },
          onPanStart: (_) => windowManager.startDragging(),
          child: const SizedBox.expand(),
        ),
      ),
    );
  }
}

/// Controles de janela **à esquerda** (convenção macOS): semáforo
/// fechar/minimizar/maximizar. Em plataformas não-macOS não renderiza nada —
/// no Windows os controles vão à direita via [WindowControlsTrailing].
class WindowControls extends StatefulWidget {
  const WindowControls({super.key});

  @override
  State<WindowControls> createState() => _WindowControlsState();
}

class _WindowControlsState extends State<WindowControls> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    if (!Platform.isMacOS) return const SizedBox.shrink();
    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: Row(
        children: [
          _light(const Color(0xFFFF5F57), Icons.close, windowManager.close),
          const SizedBox(width: 8),
          _light(const Color(0xFFFEBC2E), Icons.remove, windowManager.minimize),
          const SizedBox(width: 8),
          _light(const Color(0xFF28C840), Icons.add, _toggleMaximize),
        ],
      ),
    );
  }

  Widget _light(Color color, IconData icon, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: Container(
          width: 12,
          height: 12,
          alignment: Alignment.center,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          child: _hover
              ? Icon(icon, size: 8, color: Colors.black.withValues(alpha: 0.55))
              : null,
        ),
      ),
    );
  }
}

/// Controles de janela **à direita** (convenção Windows/Linux): botões quadrados
/// minimizar/maximizar/fechar, com hover de fundo (fechar fica vermelho). No
/// macOS não renderiza nada (lá o semáforo fica à esquerda via [WindowControls]).
/// Posicione no fim da topbar.
class WindowControlsTrailing extends StatelessWidget {
  const WindowControlsTrailing({super.key});

  @override
  Widget build(BuildContext context) {
    if (!Platform.isWindows && !Platform.isLinux) {
      return const SizedBox.shrink();
    }
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _WinButton(
          icon: Icons.remove,
          tooltip: 'Minimize',
          onTap: windowManager.minimize,
        ),
        _WinButton(
          icon: Icons.crop_square,
          tooltip: 'Maximize',
          onTap: _toggleMaximize,
        ),
        _WinButton(
          icon: Icons.close,
          tooltip: 'Close',
          onTap: windowManager.close,
          danger: true,
        ),
      ],
    );
  }
}

class _WinButton extends StatefulWidget {
  const _WinButton({
    required this.icon,
    required this.tooltip,
    required this.onTap,
    this.danger = false,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;
  final bool danger;

  @override
  State<_WinButton> createState() => _WinButtonState();
}

class _WinButtonState extends State<_WinButton> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final Color? bg = _hover
        ? (widget.danger ? const Color(0xFFE81123) : colors.panel3)
        : null;
    final Color fg = _hover && widget.danger ? Colors.white : colors.text2;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: AppTooltip(
        message: widget.tooltip,
        child: GestureDetector(
          onTap: widget.onTap,
          child: Container(
            width: 46,
            height: 46,
            color: bg ?? Colors.transparent,
            alignment: Alignment.center,
            child: Icon(widget.icon, size: 16, color: fg),
          ),
        ),
      ),
    );
  }
}
