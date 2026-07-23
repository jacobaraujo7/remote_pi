import 'dart:async' show Timer;

import 'package:shadcn_flutter/shadcn_flutter.dart';

/// Tooltip do app — substitui o `Tooltip` do shadcn onde a posição importa.
///
/// Por quê: os handlers de overlay do shadcn medem a âncora com
/// `localToGlobal` **global** (espaço da janela, já ampliado pelo `_AppZoom`),
/// mas inserem o balão no `Overlay` do Navigator, que vive **dentro** do zoom
/// (espaço lógico reduzido). Com zoom ≠ 1.0 o balão desloca proporcional à
/// distância do canto superior esquerdo. Aqui a âncora é convertida pro espaço
/// do próprio `Overlay` (`localToGlobal(..., ancestor: overlay)`) e passada
/// como `position` explícito → posição correta em qualquer escala.
class AppTooltip extends StatefulWidget {
  const AppTooltip({super.key, required this.message, required this.child});

  final String message;
  final Widget child;

  @override
  State<AppTooltip> createState() => _AppTooltipState();
}

class _AppTooltipState extends State<AppTooltip> {
  OverlayCompleter<void>? _entry;
  Timer? _wait;

  @override
  void dispose() {
    _wait?.cancel();
    _entry?.remove();
    _entry = null;
    super.dispose();
  }

  void _show() {
    if (!mounted) return;
    _entry?.remove();
    final box = context.findRenderObject();
    final overlayBox = Overlay.of(
      context,
      rootOverlay: true,
    ).context.findRenderObject();
    if (box is! RenderBox || overlayBox is! RenderBox) return;
    // Bottom-center do trigger, no espaço do Overlay (imune ao zoom).
    final anchor = box.localToGlobal(
      Offset(box.size.width / 2, box.size.height),
      ancestor: overlayBox,
    );
    _entry = showPopover<void>(
      context: context,
      position: anchor,
      // Balão logo abaixo do ponto de âncora, centralizado.
      alignment: Alignment.topCenter,
      anchorAlignment: Alignment.bottomCenter,
      modal: false,
      follow: false,
      consumeOutsideTaps: false,
      dismissBackdropFocus: false,
      builder: (context) => TooltipContainer(child: Text(widget.message)),
    );
  }

  void _hide() {
    _entry?.remove();
    _entry = null;
  }

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) {
        _wait?.cancel();
        _wait = Timer(const Duration(milliseconds: 500), _show);
      },
      onExit: (_) {
        _wait?.cancel();
        _hide();
      },
      child: widget.child,
    );
  }
}
