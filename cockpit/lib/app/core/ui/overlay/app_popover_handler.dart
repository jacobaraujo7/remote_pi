import 'dart:async';

import 'package:shadcn_flutter/shadcn_flutter.dart';

/// Handler de popover do app — substitui o `PopoverOverlayHandler` do shadcn em
/// **todos** os overlays ancorados (popover, menu, tooltip), instalado no
/// `ShadcnApp.router`.
///
/// ## Por que existe
///
/// O app inteiro é escalado pelo "Interface size" (`_AppZoom`, em
/// `app_widget.dart`): a árvore é medida num espaço lógico reduzido e ampliada
/// por um `FittedBox`. O `Overlay` do Navigator vive **dentro** desse zoom, mas
/// o handler do shadcn mede a âncora com `localToGlobal(Offset.zero)` — espaço
/// da **janela**, já ampliado. Com escala ≠ 1.0 os dois espaços divergem e todo
/// popover abre deslocado, proporcional à distância do canto superior esquerdo
/// (quanto mais longe do topo-esquerda, maior o erro).
///
/// Sintomas que isso causava: menu de contexto da aba, opções do workspace e os
/// `Select` das Configurações abrindo fora do lugar.
///
/// ## O que muda em relação ao original
///
/// 1. A âncora é medida **no espaço do próprio Overlay**
///    (`localToGlobal(..., ancestor: overlayBox)`) em vez do espaço da janela.
/// 2. Um [position] explícito (menu de contexto: ponto do clique, em
///    coordenadas de janela) é convertido com `globalToLocal` do Overlay.
/// 3. `follow` é forçado a `false`: o ticker de follow do shadcn recalcula a
///    posição a cada frame **no espaço da janela** (estado privado, não dá pra
///    corrigir de fora) e sobrescreveria o valor certo. Como passamos
///    `anchorSize` medido aqui, nada mais depende do ticker — só se perde o
///    acompanhamento de âncora que se move com o popover aberto (raro; menus
///    fecham na interação).
///
/// O resto é cópia fiel do `PopoverOverlayHandler` (shadcn_flutter 0.0.52) —
/// ao atualizar o pacote, revisar este arquivo.
class AppPopoverOverlayHandler extends OverlayHandler {
  const AppPopoverOverlayHandler();

  @override
  OverlayCompleter<T> show<T>({
    required BuildContext context,
    required AlignmentGeometry alignment,
    required WidgetBuilder builder,
    Offset? position,
    AlignmentGeometry? anchorAlignment,
    PopoverConstraint widthConstraint = PopoverConstraint.flexible,
    PopoverConstraint heightConstraint = PopoverConstraint.flexible,
    Key? key,
    bool rootOverlay = true,
    bool modal = true,
    bool barrierDismissable = true,
    Clip clipBehavior = Clip.none,
    Object? regionGroupId,
    Offset? offset,
    AlignmentGeometry? transitionAlignment,
    EdgeInsetsGeometry? margin,
    bool follow = true,
    bool consumeOutsideTaps = true,
    ValueChanged<PopoverOverlayWidgetState>? onTickFollow,
    bool allowInvertHorizontal = true,
    bool allowInvertVertical = true,
    bool dismissBackdropFocus = true,
    Duration? showDuration,
    Duration? dismissDuration,
    OverlayBarrier? overlayBarrier,
    LayerLink? layerLink,
  }) {
    final TextDirection textDirection = Directionality.of(context);
    final Alignment resolvedAlignment = alignment.resolve(textDirection);
    anchorAlignment ??= alignment * -1;
    final Alignment resolvedAnchorAlignment = anchorAlignment.resolve(
      textDirection,
    );
    final OverlayState overlay = Overlay.of(context, rootOverlay: rootOverlay);
    final themes = InheritedTheme.capture(from: context, to: overlay.context);
    final data = Data.capture(from: context, to: overlay.context);

    // Espaço em que o popover é posicionado (ver doc da classe).
    final overlayBox = overlay.context.findRenderObject();

    Size? anchorSize;
    if (position == null) {
      final renderBox = context.findRenderObject() as RenderBox;
      final Offset pos = overlayBox is RenderBox
          ? renderBox.localToGlobal(Offset.zero, ancestor: overlayBox)
          : renderBox.localToGlobal(Offset.zero);
      anchorSize ??= renderBox.size;
      position = Offset(
        pos.dx +
            anchorSize.width / 2 +
            anchorSize.width / 2 * resolvedAnchorAlignment.x,
        pos.dy +
            anchorSize.height / 2 +
            anchorSize.height / 2 * resolvedAnchorAlignment.y,
      );
    } else if (overlayBox is RenderBox) {
      // Ponto do clique vem em coordenadas de janela.
      position = overlayBox.globalToLocal(position);
    }
    // A posição já está resolvida no espaço do Overlay — o ticker de follow
    // desfaria isso (ver doc da classe).
    follow = false;

    final OverlayPopoverEntry<T> popoverEntry = OverlayPopoverEntry();
    final completer = popoverEntry.completer;
    final animationCompleter = popoverEntry.animationCompleter;
    final ValueNotifier<bool> isClosed = ValueNotifier(false);
    OverlayEntry? barrierEntry;
    late OverlayEntry overlayEntry;
    Timer? closeDeadline;
    var closeFinished = false;
    void finishClose() {
      if (closeFinished) return;
      closeFinished = true;
      closeDeadline?.cancel();
      popoverEntry.remove();
      popoverEntry.dispose();
      if (!animationCompleter.isCompleted) animationCompleter.complete();
    }

    isClosed.addListener(() {
      if (!isClosed.value || closeFinished) return;
      // A muted ticker must not leave an invisible modal barrier mounted.
      // Allow the normal fade to finish, then clean up independently of frames.
      closeDeadline ??= Timer(
        (showDuration ?? kDefaultDuration) + const Duration(milliseconds: 50),
        finishClose,
      );
    });
    if (modal) {
      if (consumeOutsideTaps) {
        barrierEntry = OverlayEntry(
          builder: (context) => GestureDetector(
            onTap: () {
              if (!barrierDismissable || isClosed.value) return;
              isClosed.value = true;
              completer.complete();
            },
          ),
        );
      } else {
        barrierEntry = OverlayEntry(
          builder: (context) => Listener(
            behavior: HitTestBehavior.translucent,
            onPointerDown: (event) {
              if (!barrierDismissable || isClosed.value) return;
              isClosed.value = true;
              completer.complete();
            },
          ),
        );
      }
    }

    overlayEntry = OverlayEntry(
      builder: (innerContext) {
        return RepaintBoundary(
          child: AnimatedBuilder(
            animation: isClosed,
            builder: (innerContext, child) {
              return FocusScope(
                autofocus: dismissBackdropFocus,
                canRequestFocus: !isClosed.value,
                child: AnimatedValueBuilder.animation(
                  value: isClosed.value ? 0.0 : 1.0,
                  initialValue: 0.0,
                  curve: isClosed.value
                      ? const Interval(0, 2 / 3)
                      : Curves.linear,
                  duration: isClosed.value
                      ? (showDuration ?? kDefaultDuration)
                      : (dismissDuration ?? const Duration(milliseconds: 100)),
                  onEnd: (value) {
                    if (value == 0.0 && isClosed.value) {
                      finishClose();
                    }
                  },
                  builder: (innerContext, animation) {
                    return PopoverOverlayWidget(
                      animation: animation,
                      onTapOutside: () {
                        if (isClosed.value) return;
                        if (!modal) {
                          isClosed.value = true;
                          completer.complete();
                        }
                      },
                      key: key,
                      anchorContext: context,
                      position: position!,
                      alignment: resolvedAlignment,
                      themes: themes,
                      builder: builder,
                      anchorSize: anchorSize,
                      anchorAlignment: resolvedAnchorAlignment,
                      widthConstraint: widthConstraint,
                      heightConstraint: heightConstraint,
                      regionGroupId: regionGroupId,
                      offset: offset,
                      transitionAlignment: transitionAlignment,
                      margin: margin,
                      follow: follow,
                      consumeOutsideTaps: consumeOutsideTaps,
                      onTickFollow: onTickFollow,
                      allowInvertHorizontal: allowInvertHorizontal,
                      allowInvertVertical: allowInvertVertical,
                      data: data,
                      onClose: () {
                        if (isClosed.value) return Future.value();
                        isClosed.value = true;
                        completer.complete();
                        return animationCompleter.future;
                      },
                      onImmediateClose: () {
                        finishClose();
                        if (!completer.isCompleted) completer.complete();
                      },
                      onCloseWithResult: (value) {
                        if (isClosed.value) return Future.value();
                        isClosed.value = true;
                        // `as T?` (não `as T`): em menus ANINHADOS, o `closeAll`
                        // do shadcn fecha a raiz com `value == null` enquanto o
                        // submenu leva o valor escolhido. Com um T não-nulável
                        // (ex.: VoidCallback do menubar) o `null as T` estourava
                        // "Null is not a subtype of () => void" e travava o menu.
                        completer.complete(value as T?);
                        return animationCompleter.future;
                      },
                    );
                  },
                ),
              );
            },
          ),
        );
      },
    );
    popoverEntry.initialize(overlayEntry, barrierEntry);
    if (barrierEntry != null) {
      overlay.insert(barrierEntry);
    }
    overlay.insert(overlayEntry);
    return popoverEntry;
  }
}
