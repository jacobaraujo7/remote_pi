import 'dart:io';

import 'package:cockpit/app/cockpit/ui/session/browser_session.dart';
import 'package:cockpit/app/core/ui/themes/themes.dart';
import 'package:cockpit/app/core/ui/widgets/app_tooltip.dart';
import 'package:cockpit/app/core/ui/widgets/hover_tap.dart';
import 'package:cockpit/app/core/ui/widgets/unzoomed_native_view.dart';
import 'package:cockpit/i18n/strings.g.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';

/// Pane de navegador (plano 58): toolbar compacta (voltar / avançar / reload /
/// URL, uma linha só) + webview inline. Histórico vive no webview; a sessão
/// guarda apenas a URL corrente e o título da página.
class BrowserPane extends StatefulWidget {
  const BrowserPane({super.key, required this.session, required this.active});

  final BrowserSession session;

  /// Aba ativa da pane (o IndexedStack mantém todas montadas).
  final bool active;

  @override
  State<BrowserPane> createState() => _BrowserPaneState();
}

/// Página inicial das abas de navegador novas (sem URL/seed).
const String _kHomeUrl = 'https://google.com';

/// Token apendado ao User-Agent **só onde o motor é WebKit** (macOS/iOS).
///
/// Sem ele o UA de um `WKWebView` embutido não traz `Version/<x> Safari/...`,
/// e sites que fazem sniffing (Google à frente) classificam a aba como
/// navegador desconhecido e servem a interface legada. Com o token, o UA fica
/// indistinguível do Safari — que é literalmente o mesmo motor rodando aqui.
///
/// No Windows (WebView2) e no Android (WebView do sistema) o motor é Chromium:
/// o UA de lá já termina em `Safari/537.36` e os sites servem a versão moderna.
/// Apendar um token de Safari ali produziria um UA híbrido incoerente — por
/// isso [_safariUaToken] devolve `null` fora do WebKit.
String? get _safariUaToken =>
    Platform.isMacOS || Platform.isIOS ? 'Version/26.6 Safari/605.1.15' : null;

class _BrowserPaneState extends State<BrowserPane> {
  InAppWebViewController? _web;
  late final TextEditingController _urlCtrl;
  final FocusNode _urlFocus = FocusNode();
  bool _canBack = false;
  bool _canForward = false;

  /// Seed chegando antes de o webview existir (CLI logo após abrir a aba).
  String? _pendingUrl;

  @override
  void initState() {
    super.initState();
    _urlCtrl = TextEditingController(text: widget.session.url);
    widget.session.addListener(_onSession);
    final seed = widget.session.takeSeedUrl();
    if (seed != null) _pendingUrl = seed;
    // Aba nova em branco não foca mais o campo de URL: agora carrega a home
    // (Google), então mostramos a página em vez de abrir o teclado por cima.
  }

  @override
  void dispose() {
    widget.session.removeListener(_onSession);
    // Só limpa se ainda for o nosso controller — evita corrida de dispose
    // fora de ordem sobrescrevendo um controller mais novo.
    if (identical(widget.session.controller, _web)) {
      widget.session.controller = null;
    }
    _urlCtrl.dispose();
    _urlFocus.dispose();
    super.dispose();
  }

  void _onSession() {
    final seed = widget.session.takeSeedUrl();
    if (seed != null) _go(seed);
  }

  Future<void> _go(String input) async {
    final url = normalizeBrowserUrl(input);
    if (url.isEmpty) return;
    _urlCtrl.text = url;
    final web = _web;
    if (web == null) {
      _pendingUrl = url;
      return;
    }
    await web.loadUrl(urlRequest: URLRequest(url: WebUri(url)));
  }

  Future<void> _syncNavState() async {
    final web = _web;
    if (web == null) return;
    final back = await web.canGoBack();
    final fwd = await web.canGoForward();
    if (!mounted) return;
    if (back != _canBack || fwd != _canForward) {
      setState(() {
        _canBack = back;
        _canForward = fwd;
      });
    }
  }

  void _onLoadStop(InAppWebViewController web, WebUri? url) {
    final u = url?.toString();
    if (u != null && u != 'about:blank') {
      widget.session.reportNavigation(url: u);
      if (!_urlFocus.hasFocus) _urlCtrl.text = u;
    }
    _syncNavState();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final typo = context.typo;
    final tr = context.t.cockpit.browserPane;

    Widget navBtn(IconData icon, String tip, bool enabled, VoidCallback fn) =>
        AppTooltip(
          message: tip,
          child: HoverTap(
            borderRadius: BorderRadius.circular(5),
            onTap: enabled ? fn : null,
            child: SizedBox(
              width: 24,
              height: 24,
              child: Icon(
                icon,
                size: 15,
                color: enabled ? colors.text3 : colors.text4,
              ),
            ),
          ),
        );

    // Aba nova (sem URL e sem seed) abre no Google por padrão.
    final initial = widget.session.url.isEmpty
        ? (_pendingUrl ?? _kHomeUrl)
        : widget.session.url;

    return ColoredBox(
      color: colors.panel,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(6, 4, 6, 4),
            child: Row(
              children: [
                navBtn(
                  Icons.arrow_back,
                  tr.back,
                  _canBack,
                  () => _web?.goBack(),
                ),
                navBtn(
                  Icons.arrow_forward,
                  tr.forward,
                  _canForward,
                  () => _web?.goForward(),
                ),
                navBtn(Icons.refresh, tr.reload, true, () => _web?.reload()),
                const SizedBox(width: 6),
                Expanded(
                  // `onSubmitted` (Enter) é o caminho confiável: o CallbackShortcuts
                  // em volta não pegava o Enter (a TextField do shadcn consome a
                  // tecla internamente) e a página não abria.
                  child: TextField(
                    controller: _urlCtrl,
                    focusNode: _urlFocus,
                    onSubmitted: (value) => _go(value),
                    placeholder: Text(
                      tr.urlHint,
                      style: typo.body.copyWith(
                        fontSize: 12,
                        color: colors.text4,
                      ),
                    ),
                    style: typo.body.copyWith(fontSize: 12, color: colors.text),
                    border: Border.all(color: colors.border),
                    borderRadius: BorderRadius.circular(6),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 3,
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                // Botão "Ir": abre a URL digitada (à direita da barra).
                HoverTap(
                  borderRadius: BorderRadius.circular(6),
                  color: colors.accentSoft,
                  onTap: () => _go(_urlCtrl.text),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 5,
                    ),
                    child: Text(
                      tr.go,
                      style: typo.label.copyWith(
                        fontSize: 12,
                        color: colors.accentText,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            // Fora do zoom do app: platform view recebe evento de mouse direto
            // do sistema e o clique cairia deslocado. Ver [UnzoomedNativeView].
            child: UnzoomedNativeView(
              builder: (context, contentZoom) => InAppWebView(
                initialUrlRequest: URLRequest(url: WebUri(initial)),
                initialSettings: InAppWebViewSettings(
                  // Navegador de verdade: JS ligado. O preview de markdown (CSP
                  // restritiva) usa outro widget com settings próprios.
                  javaScriptEnabled: true,
                  isInspectable: false,
                  applicationNameForUserAgent: _safariUaToken,
                  // O zoom do app volta por dentro do WebKit (a view em si roda
                  // em escala 1) — mesmo tamanho aparente, hit-test alinhado.
                  pageZoom: contentZoom,
                ),
                onWebViewCreated: (web) {
                  _web = web;
                  widget.session.controller = web;
                  final pending = _pendingUrl;
                  _pendingUrl = null;
                  if (pending != null && pending != initial) {
                    web.loadUrl(urlRequest: URLRequest(url: WebUri(pending)));
                  }
                },
                onLoadStop: _onLoadStop,
                onTitleChanged: (web, title) =>
                    widget.session.reportNavigation(title: title),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
