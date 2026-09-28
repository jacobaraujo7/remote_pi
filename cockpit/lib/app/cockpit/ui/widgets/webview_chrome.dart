import 'dart:collection';
import 'dart:io' show Platform;

import 'package:flutter/gestures.dart';

import 'package:cockpit/app/core/ui/themes/themes.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';

/// Ajustes comuns às webviews do app (preview de markdown/HTML, `.panel`,
/// navegador): sem rubber-band do macOS nas bordas do scroll e sem a piscada
/// preta do `WKWebView` antes da primeira pintura.
///
/// - O rubber-band é desligado por CSS `overscroll-behavior: none` no `html`
///   e no `body`, injetado como user script no início do documento. Vai por
///   CSSOM (não por `<style>`), então passa pela CSP com nonce do preview.
/// - A cor de fundo do `WKWebView` antes/entre pinturas
///   (`underPageBackgroundColor`) vira a cor do painel do tema, e
///   [WebViewCover] segura uma camada da mesma cor por cima até o `onLoadStop`.

/// User script que desliga o overscroll elástico nas duas pontas.
final UnmodifiableListView<UserScript> kNoRubberBandScripts =
    UnmodifiableListView<UserScript>([
      UserScript(
        source: r'''
(function () {
  function apply() {
    var r = document.documentElement;
    if (r) r.style.setProperty('overscroll-behavior', 'none', 'important');
    var b = document.body;
    if (b) b.style.setProperty('overscroll-behavior', 'none', 'important');
  }
  apply();
  document.addEventListener('DOMContentLoaded', apply);
})();
''',
        injectionTime: UserScriptInjectionTime.AT_DOCUMENT_START,
      ),
    ]);

/// User script que avisa o Flutter que o mouse está dentro da página (ver
/// [WebViewPointerRelay]). Throttle de 50 ms: é só pra manter o MouseTracker
/// do Flutter honesto, não precisa de cada pixel. **Não manda coordenadas**:
/// o `clientX/Y` do documento e a caixa do Flutter não compartilham origem
/// (inset da view nativa, zoom da página), e usar a posição real deslocava o
/// hover sintético alguns px pra cima, realçando aba/linha errada.
final UnmodifiableListView<UserScript> kPointerRelayScripts =
    UnmodifiableListView<UserScript>([
      UserScript(
        source: r'''
(function () {
  var last = 0;
  function send() {
    var now = Date.now();
    if (now - last < 50) return;
    last = now;
    var f = window.flutter_inappwebview;
    if (f && f.callHandler) f.callHandler('__cockpitPointer');
  }
  window.addEventListener('mousemove', send, { passive: true, capture: true });
  window.addEventListener('mouseenter', send, { passive: true, capture: true });
})();
''',
        injectionTime: UserScriptInjectionTime.AT_DOCUMENT_START,
      ),
    ]);

/// Todos os user scripts comuns às webviews do app.
final UnmodifiableListView<UserScript> kWebViewUserScripts =
    UnmodifiableListView<UserScript>([
      ...kNoRubberBandScripts,
      ...kPointerRelayScripts,
    ]);

/// Repasse de hover da webview pro Flutter.
///
/// No macOS a webview é um `AppKitView`: um `NSView` real por cima da
/// `FlutterView`, que recebe os eventos de mouse direto do AppKit. O Flutter
/// nunca vê o ponteiro ENTRAR na webview, então o último widget em hover
/// (uma aba, um botão com cursor de clique) fica "preso" nesse estado até o
/// mouse voltar pra área do Flutter. O sintoma é intermitente porque depende
/// de por onde o ponteiro cruzou a borda.
///
/// A correção: a página manda `mousemove` (via [kPointerRelayScripts]) e este
/// helper injeta um `PointerHoverEvent` sintético no mesmo device do mouse
/// real, **no centro da caixa da webview**. O MouseTracker então sai do widget
/// antigo e o cursor volta ao normal. O centro basta: o objetivo é só provar
/// que o ponteiro está sobre a webview (que não tem MouseRegion própria); a
/// posição exata não interessa e tentar reconstruí-la a partir do `clientX/Y`
/// do documento errava por alguns px (origens diferentes), fazendo o hover
/// cair na aba ou na linha acima do cursor.
class WebViewPointerRelay {
  WebViewPointerRelay._();

  static bool _routed = false;
  static int _mouseDevice = 0;

  /// Device id do mouse real: um hover sintético em OUTRO device não tira o
  /// widget do hover (qualquer device sobre ele o mantém). Observa a rota
  /// global uma vez por processo.
  static void _ensureRoute() {
    if (_routed) return;
    _routed = true;
    GestureBinding.instance.pointerRouter.addGlobalRoute((event) {
      if (event.kind == PointerDeviceKind.mouse && event is PointerHoverEvent) {
        _mouseDevice = event.device;
      }
    });
  }

  /// Registra o handler na [web]. [context] é o do widget que envolve a
  /// webview (mesma caixa da view nativa). [contentZoom] é aceito por
  /// compatibilidade com os call-sites e não entra na conta: a posição do
  /// hover sintético é o centro da caixa, independente de zoom.
  static void register(
    InAppWebViewController web,
    BuildContext context,
    double contentZoom,
  ) {
    if (!Platform.isMacOS) return;
    _ensureRoute();
    web.addJavaScriptHandler(
      handlerName: '__cockpitPointer',
      callback: (args) {
        if (!context.mounted) return null;
        final box = context.findRenderObject();
        if (box is! RenderBox || !box.hasSize) return null;
        final global = box.localToGlobal(box.size.center(Offset.zero));
        GestureBinding.instance.handlePointerEvent(
          PointerHoverEvent(
            timeStamp: DateTime.now().difference(_epoch),
            kind: PointerDeviceKind.mouse,
            device: _mouseDevice,
            position: global,
          ),
        );
        return null;
      },
    );
  }

  static final DateTime _epoch = DateTime.now();
}

/// Cor de fundo do webview enquanto a página não pintou.
Color webViewBackground(BuildContext context) => context.colors.panel;

/// Camada da cor do painel por cima do webview até [loaded]; some com fade
/// curto. Evita o frame preto do `NSView` entre montar e a primeira pintura.
class WebViewCover extends StatelessWidget {
  const WebViewCover({super.key, required this.loaded, required this.child});

  final bool loaded;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        child,
        IgnorePointer(
          child: AnimatedOpacity(
            opacity: loaded ? 0 : 1,
            duration: const Duration(milliseconds: 120),
            child: ColoredBox(color: webViewBackground(context)),
          ),
        ),
      ],
    );
  }
}
