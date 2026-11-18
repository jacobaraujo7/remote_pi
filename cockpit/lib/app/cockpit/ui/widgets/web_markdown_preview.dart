import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:cockpit/app/cockpit/domain/exceptions/pdf_export_error.dart';
import 'package:cockpit/app/cockpit/ui/widgets/webview_chrome.dart';
import 'package:cockpit/app/core/domain/result.dart';
import 'package:cockpit/app/core/ui/themes/themes.dart';
import 'package:cockpit/app/core/ui/widgets/unzoomed_native_view.dart';
import 'package:cockpit/i18n/strings.g.dart';
import 'package:flutter/foundation.dart' show mapEquals;
import 'package:flutter/gestures.dart' show PointerScrollEvent;
import 'package:flutter/services.dart' show PlatformException, rootBundle;
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';
import 'package:url_launcher/url_launcher.dart' as launcher;

/// Preview de markdown via webview (plano 58) — receita VS Code: markdown-it
/// (GFM + HTML embutido) → DOMPurify → morphdom (diff de DOM, preserva scroll).
/// Tema entra por CSS variables ([_themeVars]); troca de tema re-injeta sem
/// re-render. Imagens relativas do documento passam pelo scheme controlado
/// `ckp-res:`, que só serve arquivos dentro de [workspaceRoot].
///
/// Fences ```` ```mermaid ```` viram diagrama (plano 72). O motor (~3.5 MB) é
/// injetado **sob demanda**: o `setContent` da página devolve `true` quando o
/// documento tem diagrama e `window.mermaid` não existe, e só então o bundle
/// entra via `evaluateJavascript` (não passa pela CSP de `<script>` do
/// documento: WKWebView avalia direto no page world, WebView2 via CDP
/// `Runtime.evaluate`). `.md` sem diagrama nunca carrega o script.
class WebMarkdownPreview extends StatefulWidget {
  const WebMarkdownPreview({
    super.key,
    required this.text,
    required this.docDir,
    required this.workspaceRoot,
    this.controller,
  });

  /// Ações sobre a página já renderizada (exportar PDF, plano 73).
  final WebMarkdownPreviewController? controller;

  final String text;

  /// Diretório do arquivo `.md` — base das imagens relativas.
  final String docDir;

  /// Raiz permitida pro scheme `ckp-res:` (nada fora dela é servido).
  final String workspaceRoot;

  @override
  State<WebMarkdownPreview> createState() => _WebMarkdownPreviewState();
}

/// Ponte do dono do preview (o FileViewer) para ações sobre a página que está
/// na tela. Criado e descartado pelo dono; o preview se liga enquanto montado.
class WebMarkdownPreviewController {
  _WebMarkdownPreviewState? _state;

  /// Exportar PDF existe nesta plataforma? Só macOS: o WKWebView imprime via
  /// `NSPrintOperation` (paginado, texto selecionável). O fork Windows do
  /// plugin (`flutter_inappwebview_windows`) não implementa `createPdf` nem
  /// `printCurrentPage`, e não expõe o CDP (`Page.printToPDF`) ao Dart.
  static bool get supportsPdf => Platform.isMacOS;

  /// Gera o PDF do documento renderizado em [path] (A4, paleta clara de
  /// impressão, diagramas Mermaid incluídos).
  Future<Result<void, PdfExportError>> exportPdf(String path) async {
    final state = _state;
    if (state == null || !state.mounted) {
      return const Failure(PdfExportError(PdfExportErrorKind.notReady));
    }
    return state._exportPdf(path);
  }
}

class _WebMarkdownPreviewState extends State<WebMarkdownPreview> {
  InAppWebViewController? _web;
  bool _loaded = false;

  /// Paleta clara do PDF — a mesma do `@media print` do `preview.css`; aqui
  /// vai pros diagramas Mermaid, que embutem as cores no SVG.
  static const _printTheme = {
    '--ckp-bg': '#ffffff',
    '--ckp-text': '#1f2328',
    '--ckp-text-muted': '#59636e',
    '--ckp-border': '#d1d9e0',
    '--ckp-code-bg': '#f6f8fa',
    '--ckp-link': '#0969da',
  };

  /// Margem da página do PDF, em pontos (≈ 18 mm).
  static const _printMargin = 51.0;

  /// Esqueleto composto (ver [_composePage]), ainda com o placeholder do tema.
  String? _page;

  /// A página que o webview carrega: [_page] com as variáveis `--ckp-*` do
  /// tema **inlined** no `:root`. Sem isso o primeiro paint usava o fallback
  /// escuro do CSS (`#1e1e1e`) até o `setTheme` do `onLoadStop` chegar — a
  /// "tela preta" no começo do carregamento, gritante no tema claro. Montada
  /// uma vez (o `initialData` só vale na criação da view); troca de tema
  /// depois disso segue por JS.
  String? _html;

  /// Último tema injetado na página, pra não reinjetar igual a cada rebuild.
  Map<String, String>? _pushedTheme;

  /// Últimos rótulos traduzidos injetados (troca de idioma em runtime).
  Map<String, String>? _pushedStrings;

  /// Injeção do Mermaid nesta página, em curso ou feita (uma vez por load).
  Future<void>? _mermaidInjection;

  /// Bundle do Mermaid, lido do asset uma vez por processo e só quando algum
  /// documento precisa dele.
  static Future<String>? _mermaidJs;

  /// Página montada uma vez por processo: esqueleto + CSS + os três motores JS
  /// inlined sob nonce (a CSP não deixa a página pedir nada além de imagem).
  static String? _cachedPage;

  static Future<String> _composePage() async {
    final cached = _cachedPage;
    if (cached != null) return cached;
    const base = 'assets/md_preview';
    final results = await Future.wait([
      rootBundle.loadString('$base/preview.html'),
      rootBundle.loadString('$base/preview.css'),
      rootBundle.loadString('$base/markdown-it.min.js'),
      rootBundle.loadString('$base/purify.min.js'),
      rootBundle.loadString('$base/morphdom-umd.min.js'),
      rootBundle.loadString('$base/preview.js'),
    ]);
    final nonce = base64Url.encode(
      List<int>.generate(16, (_) => Random.secure().nextInt(256)),
    );
    // Um `</script>` literal dentro de um JS inlined fecha a tag no meio do
    // arquivo (o parser de HTML não conhece strings de JS): o resto vira
    // texto solto na página e o motor nunca define seu global. Escapar a
    // barra é neutro pra JS (dentro de string/regex `<\/script>` == `</script>`).
    String inline(String js) => js.replaceAll('</script', '<\\/script');
    final page = results[0]
        .replaceAll('__NONCE__', nonce)
        // replaceAll, não replaceFirst: qualquer outra ocorrência do token
        // (um comentário no HTML, por exemplo) roubava a substituição e o
        // <style> ficava com o literal — página sem estilo, fundo branco.
        .replaceAll('__CSS__', results[1])
        .replaceFirst('__JS_MARKDOWN_IT__;', inline(results[2]))
        .replaceFirst('__JS_PURIFY__;', inline(results[3]))
        .replaceFirst('__JS_MORPHDOM__;', inline(results[4]))
        .replaceFirst('__JS_PREVIEW__;', inline(results[5]));
    return _cachedPage = page;
  }

  @override
  void initState() {
    super.initState();
    widget.controller?._state = this;
    _composePage().then((page) {
      if (mounted) setState(() => _page = page);
    });
  }

  /// Windows: a rolagem é feita pela página, a partir dos deltas do Flutter.
  ///
  /// O plugin (`flutter_inappwebview_windows` 0.6.0) repassa roda e gesto de
  /// touchpad ao WebView2 como `SendMouseInput` de roda. O gesto chegava ao
  /// Flutter nos dois sentidos (medido: 38 gestos, 17 pra cima), mas pela
  /// injeção do plugin subia travado ou nem rolava. Aqui os mesmos eventos
  /// viram `window.scrollBy` na página, e a roda nativa é bloqueada nela
  /// (`captureScroll`) pra não rolar em dobro. macOS não passa por aqui: o
  /// WKWebView recebe o mouse direto do AppKit.
  Widget _windowsScroll(Widget child) {
    if (!Platform.isWindows) return child;
    return Listener(
      onPointerSignal: (e) {
        if (e is PointerScrollEvent) {
          _scrollBy(e.scrollDelta.dx, e.scrollDelta.dy);
        }
      },
      // Touchpad: o conteúdo acompanha os dedos (rolagem natural), então o
      // deslocamento da página é o inverso do pan.
      onPointerPanZoomUpdate: (e) => _scrollBy(-e.panDelta.dx, -e.panDelta.dy),
      child: child,
    );
  }

  void _scrollBy(double dx, double dy) {
    final web = _web;
    if (web == null || !_loaded || (dx == 0 && dy == 0)) return;
    unawaited(
      web.evaluateJavascript(
        source:
            'window.__cockpit.scrollBy && window.__cockpit.scrollBy($dx, $dy);',
      ),
    );
  }

  /// `--ckp-bg: #...; --ckp-text: #...;` pro `:root` do esqueleto.
  static String _themeCss(Map<String, String> vars) =>
      vars.entries.map((e) => '${e.key}: ${e.value};').join(' ');

  @override
  void dispose() {
    if (widget.controller?._state == this) widget.controller?._state = null;
    super.dispose();
  }

  @override
  void didUpdateWidget(WebMarkdownPreview old) {
    super.didUpdateWidget(old);
    if (old.controller != widget.controller) {
      if (old.controller?._state == this) old.controller?._state = null;
      widget.controller?._state = this;
    }
    if (old.text != widget.text || old.docDir != widget.docDir) _push();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Troca de tema chega POR AQUI: os parâmetros do widget não mudam, então
    // `didUpdateWidget` não dispara e o preview ficava com as cores do tema
    // anterior até ser reaberto.
    final vars = _themeVars(context);
    if (!mapEquals(vars, _pushedTheme)) {
      _pushedTheme = vars;
      unawaited(_pushTheme(vars));
    }
    // Troca de idioma também chega por aqui (TranslationProvider).
    final strings = _strings(context);
    if (!mapEquals(strings, _pushedStrings)) {
      _pushedStrings = strings;
      unawaited(_pushStrings(strings));
    }
  }

  /// Rótulos que a página exibe (a frase nasce aqui, via `context.t`; a
  /// mensagem de erro do Mermaid em si é texto de terceiro e vai crua).
  Map<String, String> _strings(BuildContext context) => {
    'mermaidError': context.t.cockpit.fileViewer.mermaidError,
  };

  Future<void> _pushStrings(Map<String, String> strings) async {
    final web = _web;
    if (web == null || !_loaded || !mounted) return;
    await web.evaluateJavascript(
      source: 'window.__cockpit.setStrings(${jsonEncode(strings)});',
    );
  }

  /// Injeta o `mermaid.min.js` na página atual (uma vez) e manda desenhar os
  /// diagramas que ficaram no placeholder.
  Future<void> _injectMermaid() => _mermaidInjection ??= () async {
    final js = await (_mermaidJs ??= rootBundle.loadString(
      'assets/md_preview/mermaid.min.js',
    ));
    final web = _web;
    if (web == null || !mounted) return;
    // O `;` antes protege contra o bundle terminar sem ponto e vírgula; o
    // retorno final é um bool (serializável), não o objeto do mermaid.
    await web.evaluateJavascript(
      source: '$js\n;window.__cockpit.mermaidLoaded();',
    );
  }();

  /// Só as variáveis de cor — o conteúdo não precisa ser reenviado numa troca
  /// de tema (o CSS reage sozinho às variáveis).
  Future<void> _pushTheme(Map<String, String> vars) async {
    final web = _web;
    if (web == null || !_loaded || !mounted) return;
    await web.evaluateJavascript(
      source: 'window.__cockpit.setTheme(${jsonEncode(vars)});',
    );
  }

  Map<String, String> _themeVars(BuildContext context) {
    final colors = context.colors;
    String hex(Color c) =>
        '#${(c.toARGB32() & 0xFFFFFF).toRadixString(16).padLeft(6, '0')}';
    return {
      '--ckp-bg': hex(colors.panel),
      '--ckp-text': hex(colors.text),
      '--ckp-text-muted': hex(colors.text3),
      '--ckp-border': hex(colors.border),
      '--ckp-code-bg': hex(colors.panel3),
      '--ckp-link': hex(colors.accent),
    };
  }

  Future<void> _push() async {
    final web = _web;
    if (web == null || !_loaded || !mounted) return;
    final vars = _themeVars(context);
    _pushedTheme = vars;
    final strings = _strings(context);
    _pushedStrings = strings;
    final theme = jsonEncode(vars);
    final text = jsonEncode(widget.text);
    final dir = jsonEncode(widget.docDir);
    final needsMermaid = await web.evaluateJavascript(
      source:
          'window.__cockpit.setTheme($theme);'
          'window.__cockpit.setStrings(${jsonEncode(strings)});'
          // Windows: rolagem pela página (ver [_windowsScroll]). Na mesma
          // chamada do conteúdo e com guarda: nunca pode impedir o render.
          '${Platform.isWindows ? 'if (window.__cockpit.captureScroll) window.__cockpit.captureScroll();' : ''}'
          // Por último: o valor da expressão é o retorno da chamada — `true`
          // quando há diagrama e o motor ainda não foi injetado.
          'window.__cockpit.setContent($text, $dir);',
    );
    if (needsMermaid == true && mounted) await _injectMermaid();
  }

  /// Exportação PDF (plano 73): espera os diagramas, troca-os pela versão na
  /// paleta de impressão (só no `@media print`, a tela não muda) e imprime a
  /// página num arquivo via `NSPrintOperation` (disposition `save`).
  ///
  /// Por que não `createPdf`: o `WKWebView.createPDF` gera **uma página
  /// longa** do tamanho do conteúdo, sem quebra. A operação de impressão
  /// pagina de verdade (A4 + margens), respeita `@media print` e
  /// `break-inside`, e o texto sai selecionável.
  Future<Result<void, PdfExportError>> _exportPdf(String path) async {
    final web = _web;
    if (web == null || !_loaded) {
      return const Failure(PdfExportError(PdfExportErrorKind.notReady));
    }
    try {
      // Documento com diagrama e motor ainda não injetado (o `_push` pode
      // estar no meio): injeta antes, senão o PDF sai com o código cru.
      final needsMermaid = await web.evaluateJavascript(
        source:
            '!!document.querySelector("#content .ckp-mermaid") && '
            '!window.mermaid',
      );
      if (needsMermaid == true) await _injectMermaid();
      if (!mounted) {
        return const Failure(PdfExportError(PdfExportErrorKind.notReady));
      }
      final prepared = await web.callAsyncJavaScript(
        functionBody: 'return await window.__cockpit.preparePrint(vars);',
        arguments: {'vars': _printTheme},
      );
      if (prepared == null || prepared.error != null) {
        return Failure(
          PdfExportError(
            PdfExportErrorKind.renderFailed,
            detail: prepared?.error,
          ),
        );
      }
      return await _printTo(web, path);
    } on PlatformException catch (e) {
      return Failure(
        PdfExportError(PdfExportErrorKind.writeFailed, detail: e.message),
      );
    } finally {
      if (mounted) {
        unawaited(
          web.evaluateJavascript(
            source:
                'window.__cockpit.finishPrint && window.__cockpit.finishPrint();',
          ),
        );
      }
    }
  }

  /// Imprime num temporário **na mesma pasta** do destino
  /// (`.<nome>.tmp-<rand>`) e só no sucesso faz `rename` por cima do destino:
  /// mesmo volume, então a troca é atômica e o arquivo antigo (sobrescrita
  /// confirmada no diálogo) fica intacto em qualquer falha ou timeout. O
  /// temporário é apagado em todo desfecho que não seja o rename.
  Future<Result<void, PdfExportError>> _printTo(
    InAppWebViewController web,
    String path,
  ) async {
    final target = File(path);
    final name = target.uri.pathSegments.last;
    final rand = List.generate(
      8,
      (_) => Random.secure().nextInt(36).toRadixString(36),
    ).join();
    final tmp = File(
      '${target.parent.path}${Platform.pathSeparator}.$name.tmp-$rand',
    );
    PrintJobController? job;
    try {
      job = await web.printCurrentPage(
        settings: PrintJobSettings(
          // Controller no Dart = callback de conclusão (onComplete).
          handledByClient: true,
          jobDisposition: PrintJobDisposition.SAVE,
          jobSavingURL: WebUri.uri(Uri.file(tmp.path)),
          showsPrintPanel: false,
          showsProgressPanel: false,
          paperName: 'iso-a4',
          orientation: PrintJobOrientation.PORTRAIT,
          headerAndFooter: false,
          margins: const EdgeInsets.all(_printMargin),
          jobName: name,
        ),
      );
      if (job == null) {
        return const Failure(PdfExportError(PdfExportErrorKind.writeFailed));
      }
      final done = Completer<(bool, String?)>();
      job.onComplete = (completed, error) async {
        if (!done.isCompleted) done.complete((completed, error));
      };
      final (completed, error) = await done.future.timeout(
        const Duration(minutes: 2),
        // Sem conclusão em 2 min = falha: o temporário pode estar pela metade.
        onTimeout: () => (false, 'timeout'),
      );
      if (!completed || !await tmp.exists()) {
        return Failure(
          PdfExportError(PdfExportErrorKind.writeFailed, detail: error),
        );
      }
      await tmp.rename(target.path);
      return const Success(null);
    } on FileSystemException catch (e) {
      return Failure(
        PdfExportError(PdfExportErrorKind.writeFailed, detail: e.message),
      );
    } finally {
      job?.dispose();
      // Depois do rename o temporário não existe mais; em qualquer outro
      // desfecho (falha, timeout, exceção da plataforma) ele sai daqui.
      try {
        if (await tmp.exists()) await tmp.delete();
      } on FileSystemException {
        // Melhor esforço: não mascara o resultado da exportação.
      }
    }
  }

  /// Serve `ckp-res://local/<path url-encoded>` — só arquivos dentro do
  /// workspace (path canônico, sem `..` escapando).
  Future<CustomSchemeResponse?> _serveLocal(
    InAppWebViewController web,
    WebResourceRequest request,
  ) async {
    final encoded = request.url.toString().replaceFirst('ckp-res://local/', '');
    final path = Uri.decodeComponent(encoded);
    final root = File(widget.workspaceRoot).absolute.path;
    final file = File(path).absolute;
    final canonical = file.path;
    if (root.isEmpty ||
        !canonical.startsWith('$root${Platform.pathSeparator}')) {
      return null;
    }
    if (!await file.exists()) return null;
    final bytes = await file.readAsBytes();
    return CustomSchemeResponse(
      data: bytes,
      contentType: _mimeOf(canonical),
      contentEncoding: webViewTextEncoding,
    );
  }

  static String _mimeOf(String path) {
    final ext = path.split('.').last.toLowerCase();
    return switch (ext) {
      'png' => 'image/png',
      'jpg' || 'jpeg' => 'image/jpeg',
      'gif' => 'image/gif',
      'webp' => 'image/webp',
      'svg' => 'image/svg+xml',
      'bmp' => 'image/bmp',
      'ico' => 'image/x-icon',
      _ => 'application/octet-stream',
    };
  }

  @override
  Widget build(BuildContext context) {
    final page = _page;
    if (page == null) {
      return ColoredBox(color: context.colors.panel);
    }
    final html = _html ??= page.replaceFirst(
      '__THEME__',
      _themeCss(_themeVars(context)),
    );
    // Fora do zoom do app (platform view recebe mouse direto do sistema): sem
    // isso a seleção de texto cai deslocada. Ver [UnzoomedNativeView].
    return WebViewCover(
      loaded: _loaded,
      child: _windowsScroll(
        WebViewEnvironmentGate(
          builder: (context, environment) => UnzoomedNativeView(
            builder: (context, contentZoom) => InAppWebView(
              webViewEnvironment: environment,
              initialData: InAppWebViewInitialData(data: html),
              initialUserScripts: kWebViewUserScripts,
              initialSettings: InAppWebViewSettings(
                javaScriptEnabled: true,
                resourceCustomSchemes: ['ckp-res'],
                isInspectable: false,
                underPageBackgroundColor: webViewBackground(context),
                pageZoom: contentZoom,
              ),
              onWebViewCreated: (web) {
                _web = web;
                WebViewPointerRelay.register(web, context, contentZoom);
              },
              onLoadStop: (web, _) {
                // Página (re)carregada = contexto JS novo, sem o mermaid.
                _mermaidInjection = null;
                if (mounted) setState(() => _loaded = true);
                _push();
              },
              onLoadResourceWithCustomScheme: _serveLocal,
              // Link clicado abre no browser do SO — o preview não navega pra fora.
              shouldOverrideUrlLoading: (web, action) async {
                final url = action.request.url;
                if (url == null ||
                    url.scheme == 'about' ||
                    url.scheme == 'data') {
                  return NavigationActionPolicy.ALLOW;
                }
                if (url.scheme == 'http' || url.scheme == 'https') {
                  await launcher.launchUrl(url);
                }
                return NavigationActionPolicy.CANCEL;
              },
            ),
          ),
        ),
      ),
    );
  }
}

/// Preview de arquivo `.html`/`.htm` (plano 58): carrega o arquivo direto no
/// webview, com leitura restrita à raiz do workspace (recursos relativos
/// funcionam; nada fora da raiz é legível). JS ligado, sem ponte com o app
/// (isso é o `.panel`).
///
/// Stateful por causa do **reload** (card k39): o webview carrega o arquivo uma
/// única vez, pelo `initialUrlRequest`, e o path não muda quando o conteúdo
/// muda no disco. Sem guardar o controller, o preview ficava eternamente na
/// primeira versão da página. [revision] é o gatilho: o dono muda o valor (o
/// watcher releu o arquivo, ou o usuário clicou em recarregar) e o webview
/// recarrega.
class WebHtmlPreview extends StatefulWidget {
  const WebHtmlPreview({
    super.key,
    required this.path,
    required this.workspaceRoot,
    this.revision = 0,
  });

  final String path;
  final String workspaceRoot;

  /// Muda a cada conteúdo novo em disco (ou clique em recarregar).
  final int revision;

  @override
  State<WebHtmlPreview> createState() => _WebHtmlPreviewState();
}

class _WebHtmlPreviewState extends State<WebHtmlPreview> {
  InAppWebViewController? _controller;
  bool _loaded = false;

  /// Recarga pedida antes de o webview existir (troca rápida de aba, arquivo
  /// que muda durante o load): fica pendente e roda no `onLoadStop`.
  bool _pending = false;

  @override
  void didUpdateWidget(WebHtmlPreview old) {
    super.didUpdateWidget(old);
    // Path novo = arquivo diferente: a key muda lá em cima e o webview é
    // recriado, não há o que recarregar.
    if (widget.path != old.path || widget.revision == old.revision) return;
    _reload();
  }

  void _reload() {
    final c = _controller;
    if (c == null) {
      _pending = true;
      return;
    }
    unawaited(c.reload());
  }

  @override
  Widget build(BuildContext context) {
    // Mesmo motivo do preview de markdown: platform view fora do zoom do app.
    return WebViewCover(
      loaded: _loaded,
      child: WebViewEnvironmentGate(
        builder: (context, environment) => UnzoomedNativeView(
          builder: (context, contentZoom) => InAppWebView(
            key: ValueKey('html:${widget.path}'),
            webViewEnvironment: environment,
            initialUrlRequest: URLRequest(
              url: WebUri.uri(Uri.file(widget.path)),
            ),
            // User script roda mesmo com JS da página desligado (é do host).
            initialUserScripts: kWebViewUserScripts,
            onWebViewCreated: (c) {
              _controller = c;
              WebViewPointerRelay.register(c, context, contentZoom);
              if (_pending) {
                _pending = false;
                unawaited(c.reload());
              }
            },
            onLoadStop: (_, _) {
              if (mounted) setState(() => _loaded = true);
            },
            initialSettings: InAppWebViewSettings(
              // JS ligado: o `javaScriptEnabled: false` do WebKit desliga TAMBÉM
              // os user scripts do host (sem rubber-band, repasse de hover), e
              // a página que o agente escreve costuma precisar de JS mesmo.
              javaScriptEnabled: true,
              isInspectable: false,
              underPageBackgroundColor: webViewBackground(context),
              pageZoom: contentZoom,
              // Leitura restrita à raiz do workspace (loadFileURL:allowingReadAccessTo:).
              allowingReadAccessTo: widget.workspaceRoot.isEmpty
                  ? null
                  : WebUri.uri(Uri.directory(widget.workspaceRoot)),
            ),
          ),
        ),
      ),
    );
  }
}
