import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data' show Uint8List;

import 'package:cockpit/app/cockpit/domain/entities/browser_capability.dart';
import 'package:cockpit/app/cockpit/domain/entities/file_view.dart';
import 'package:cockpit/app/cockpit/domain/entities/panel_document.dart';
import 'package:cockpit/app/cockpit/ui/session/file_viewer_session.dart';
import 'package:cockpit/app/cockpit/ui/widgets/webview_chrome.dart';

import 'package:cockpit/app/core/ui/themes/themes.dart';
import 'package:cockpit/app/core/ui/widgets/unzoomed_native_view.dart';
import 'package:cockpit/i18n/strings.g.dart';
import 'package:flutter/foundation.dart' show FlutterError, mapEquals;
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';
import 'package:url_launcher/url_launcher.dart' as launcher;

/// Aba de um arquivo `.panel` (plano 67): o HTML do arquivo numa webview viva,
/// com `window.cockpit(line)` injetado no início do documento. Cada chamada
/// vira `cockpit <line>` na máquina (via [onCall], que a VM resolve spawnando
/// a CLI interna) e a Promise recebe `{ok, code, stdout, stderr, json}`.
///
/// Recursos relativos (`<img src="a.png">`, `<script src="app.js">`) saem pelo
/// scheme `ckp-panel://<sessão>/`, servido só de dentro da pasta do arquivo.
/// O tema do app entra como CSS variables `--ckp-*` no `:root`, re-injetadas
/// na troca de tema; a página as usa se quiser.
/// Prefixo reservado da URL virtual das libs embarcadas (`/__cockpit__/x.js`).
const kPanelLibPrefix = '__cockpit__/';

class PanelView extends StatefulWidget {
  const PanelView({super.key, required this.session, required this.onCall});

  final FileViewerSession session;

  /// Executa `cockpit <line>` com cwd [cwd] e devolve o mapa que a página vê.
  final Future<Map<String, Object?>> Function(String line, String cwd) onCall;

  @override
  State<PanelView> createState() => _PanelViewState();
}

class _PanelViewState extends State<PanelView> {
  static final bool _inline = BrowserCapability.resolve().isInline;

  /// Script da ponte, lido uma vez por processo.
  static String? _bridge;

  InAppWebViewController? _web;
  bool _loaded = false;
  PanelDocument? _doc;
  Map<String, String>? _pushedTheme;

  /// Pasta do arquivo `.panel`: cwd default do `exec`/CLI e raiz dos recursos
  /// relativos. Via `File.parent`, não cortando no `/`: no Windows o path vem
  /// com `\` e o corte devolvia o próprio arquivo como "pasta" — o spawn da
  /// CLI morria com "O nome do diretório é inválido".
  String get _docDir => File(widget.session.path).parent.path;

  /// cwd do `exec`/CLI: `cwd:` do front-matter relativo à pasta do arquivo.
  String get _cwd {
    final rel = _doc?.cwd;
    if (rel == null || rel.isEmpty) return _docDir;
    if (rel.startsWith('/') || RegExp(r'^[A-Za-z]:[\\/]').hasMatch(rel)) {
      return rel;
    }
    return File('$_docDir/$rel').absolute.path;
  }

  String get _baseUrl => 'ckp-panel://${widget.session.id}/';

  @override
  void initState() {
    super.initState();
    _parse();
    widget.session.addListener(_onSession);
    if (_bridge == null) {
      rootBundle.loadString('assets/panel/bridge.js').then((js) {
        _bridge = js;
        if (mounted) setState(() {});
      });
    }
  }

  @override
  void didUpdateWidget(PanelView old) {
    super.didUpdateWidget(old);
    if (old.session != widget.session) {
      old.session.removeListener(_onSession);
      widget.session.addListener(_onSession);
      _parse();
    }
  }

  @override
  void dispose() {
    // Só o listener: a sessão pode já ter sido descartada pela VM (fechar a
    // aba descarta a sessão antes do widget), e o título do documento vale
    // também para a mesma aba em "Open as HTML" (caso e_7b16 da Telemetria).
    widget.session.removeListener(_onSession);
    super.dispose();
  }

  String get _rawText => switch (widget.session.view) {
    FileViewText(:final text) => text,
    FileViewMarkdown(:final text) => text,
    FileViewSvg(:final text) => text,
    _ => '',
  };

  void _parse() {
    final doc = PanelDocument.parse(_rawText);
    _doc = doc;
    // A sessão notifica a barra de abas; do `initState`/`didUpdateWidget` isso
    // cai durante o build (casos e_0f0a e e_f743 da Telemetria): adia.
    final session = widget.session;
    final title = doc.title;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      session.setDocumentTitle(title);
    });
  }

  /// Conteúdo relido do disco (watcher) → recarrega a página, se o documento
  /// pede (`reload: true`, o default).
  void _onSession() {
    final before = _doc?.body;
    _parse();
    final doc = _doc!;
    if (!doc.reload || doc.body == before) return;
    final web = _web;
    if (web == null || !_loaded) return;
    if (Platform.isWindows) {
      // Mesma razão do `initialUrlRequest` no build: a página é servida pelo
      // scheme, então recarregar é navegar de novo pra URL base.
      unawaited(web.loadUrl(urlRequest: URLRequest(url: WebUri(_baseUrl))));
      return;
    }
    unawaited(
      web.loadData(
        data: doc.body,
        baseUrl: WebUri(_baseUrl),
        mimeType: 'text/html',
        encoding: 'utf-8',
      ),
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final vars = _themeVars(context);
    if (mapEquals(vars, _pushedTheme)) return;
    _pushedTheme = vars;
    unawaited(_pushTheme(vars));
  }

  Future<void> _pushTheme(Map<String, String> vars) async {
    final web = _web;
    if (web == null || !_loaded || !mounted) return;
    await web.evaluateJavascript(
      source:
          'window.cockpit && window.cockpit.__setTheme(${jsonEncode(vars)});',
    );
  }

  Map<String, String> _themeVars(BuildContext context) {
    final colors = context.colors;
    String hex(Color c) =>
        '#${(c.toARGB32() & 0xFFFFFF).toRadixString(16).padLeft(6, '0')}';
    return {
      '--ckp-bg': hex(colors.panel),
      '--ckp-bg-raised': hex(colors.panel2),
      '--ckp-text': hex(colors.text),
      '--ckp-text-secondary': hex(colors.text2),
      '--ckp-text-muted': hex(colors.text3),
      '--ckp-border': hex(colors.border),
      '--ckp-border-strong': hex(colors.border2),
      '--ckp-code-bg': hex(colors.panel3),
      '--ckp-link': hex(colors.accent),
      '--ckp-accent': hex(colors.accent),
      '--ckp-accent-soft': hex(colors.accentSoft),
      '--ckp-accent-text': hex(colors.accentText),
      '--ckp-ok': hex(colors.ok),
      '--ckp-warn': hex(colors.warn),
      '--ckp-error': hex(colors.error),
    };
  }

  /// Serve `ckp-panel://<sessão>/<path relativo>` — só arquivos dentro da
  /// pasta do `.panel` (caminho canônico, sem `..` escapando).
  Future<CustomSchemeResponse?> _serveLocal(
    InAppWebViewController web,
    WebResourceRequest request,
  ) async {
    final uri = request.url;
    if (uri.scheme != 'ckp-panel') return null;
    final rel = Uri.decodeComponent(uri.path).replaceFirst(RegExp(r'^/+'), '');
    // A raiz é o próprio documento: no Windows a página é carregada por esta
    // URL (ver `initialUrlRequest` no build), não por `loadData`.
    if (rel.isEmpty) return _serveDocument();
    if (rel.startsWith(kPanelLibPrefix)) return _serveBundled(rel);
    final root = Directory(_docDir).absolute.path;
    final file = File('$root/$rel').absolute;
    final canonical = file.path;
    if (!canonical.startsWith('$root${Platform.pathSeparator}')) return null;
    if (!await file.exists()) return null;
    final bytes = await file.readAsBytes();
    return CustomSchemeResponse(
      data: bytes,
      contentType: _mimeOf(canonical),
      contentEncoding: webViewTextEncoding,
    );
  }

  /// O HTML do `.panel` (sem o front-matter), servido como documento principal
  /// de `ckp-panel://<sessão>/`.
  CustomSchemeResponse? _serveDocument() {
    final doc = _doc;
    if (doc == null) return null;
    return CustomSchemeResponse(
      data: Uint8List.fromList(utf8.encode(doc.body)),
      contentType: 'text/html; charset=utf-8',
      contentEncoding: webViewTextEncoding,
    );
  }

  /// Serve `/__cockpit__/<lib>` a partir dos assets do app (`assets/panel/lib/`):
  /// libs embarcadas (petite-vue, chart.js, marked, tailwind, cockpit.css)
  /// para o `.panel` funcionar sem rede e com versão única por release. O
  /// prefixo é reservado: ganha de qualquer pasta homônima ao lado do arquivo.
  Future<CustomSchemeResponse?> _serveBundled(String rel) async {
    final name = rel.substring(kPanelLibPrefix.length);
    if (name.isEmpty || name.contains('/') || name.contains('..')) return null;
    try {
      final data = await rootBundle.load('assets/panel/lib/$name');
      return CustomSchemeResponse(
        data: data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
        contentType: _mimeOf(name),
        contentEncoding: webViewTextEncoding,
      );
    } on FlutterError {
      return null;
    }
  }

  static String _mimeOf(String path) {
    final ext = path.split('.').last.toLowerCase();
    return switch (ext) {
      'html' || 'htm' => 'text/html',
      'js' || 'mjs' => 'text/javascript',
      'css' => 'text/css',
      'json' => 'application/json',
      'svg' => 'image/svg+xml',
      'png' => 'image/png',
      'jpg' || 'jpeg' => 'image/jpeg',
      'gif' => 'image/gif',
      'webp' => 'image/webp',
      'ico' => 'image/x-icon',
      'woff' => 'font/woff',
      'woff2' => 'font/woff2',
      'txt' || 'md' || 'csv' => 'text/plain',
      _ => 'application/octet-stream',
    };
  }

  Future<Object?> _handleCall(List<dynamic> args) async {
    final line = args.isEmpty ? '' : args.first.toString();
    return widget.onCall(line, _cwd);
  }

  @override
  Widget build(BuildContext context) {
    final tr = context.t.cockpit.panelView;
    if (!_inline) {
      return _Unavailable(
        message: tr.unavailable,
        openInBrowser: tr.openInBrowser,
        openAsHtml: tr.openAsHtml,
        path: widget.session.path,
        onOpenAsHtml: widget.session.toggleRawSource,
      );
    }
    final bridge = _bridge;
    final doc = _doc;
    if (bridge == null || doc == null) {
      return ColoredBox(color: context.colors.panel);
    }
    // No Windows o plugin ignora o `baseUrl` do `initialData` (vira
    // `NavigateToString`, origem `about:blank`): `/__cockpit__/x.js` e
    // `<img src="a.png">` não resolvem pra lugar nenhum. Lá a página é
    // carregada pela própria URL do scheme e [_serveLocal] entrega o corpo na
    // raiz — base real, recursos relativos funcionam. No macOS o `loadHTMLString`
    // honra o `baseUrl` e segue como estava.
    final initialData = Platform.isWindows
        ? null
        : InAppWebViewInitialData(
            data: doc.body,
            baseUrl: WebUri(_baseUrl),
            mimeType: 'text/html',
            encoding: 'utf-8',
          );
    final initialUrlRequest = Platform.isWindows
        ? URLRequest(url: WebUri(_baseUrl))
        : null;
    return WebViewCover(
      loaded: _loaded,
      child: WebViewEnvironmentGate(
        builder: (context, environment) => UnzoomedNativeView(
          builder: (context, contentZoom) => InAppWebView(
            key: ValueKey('panel:${widget.session.id}'),
            webViewEnvironment: environment,
            initialData: initialData,
            initialUrlRequest: initialUrlRequest,
            initialUserScripts: UnmodifiableListView<UserScript>([
              ...kWebViewUserScripts,
              UserScript(
                source: bridge,
                injectionTime: UserScriptInjectionTime.AT_DOCUMENT_START,
              ),
            ]),
            initialSettings: InAppWebViewSettings(
              javaScriptEnabled: true,
              resourceCustomSchemes: ['ckp-panel'],
              // Playground de desenvolvedor: o inspetor do Safari/Edge ajuda a
              // depurar o painel.
              isInspectable: true,
              underPageBackgroundColor: webViewBackground(context),
              pageZoom: contentZoom,
            ),
            onWebViewCreated: (web) {
              _web = web;
              web.addJavaScriptHandler(
                handlerName: 'cockpit',
                callback: _handleCall,
              );
              WebViewPointerRelay.register(web, context, contentZoom);
            },
            onLoadStop: (web, _) {
              if (mounted) setState(() => _loaded = true);
              final vars = _themeVars(context);
              _pushedTheme = vars;
              unawaited(_pushTheme(vars));
            },
            onLoadResourceWithCustomScheme: _serveLocal,
            // Links externos abrem no browser do SO — a aba não navega pra fora.
            shouldOverrideUrlLoading: (web, action) async {
              final url = action.request.url;
              if (url == null ||
                  url.scheme == 'about' ||
                  url.scheme == 'data' ||
                  url.scheme == 'ckp-panel') {
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
    );
  }
}

/// Linux (sem webview inline): explica e oferece o navegador do SO ou o HTML.
class _Unavailable extends StatelessWidget {
  const _Unavailable({
    required this.message,
    required this.openInBrowser,
    required this.openAsHtml,
    required this.path,
    required this.onOpenAsHtml,
  });

  final String message;
  final String openInBrowser;
  final String openAsHtml;
  final String path;
  final VoidCallback onOpenAsHtml;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: context.colors.panel,
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                message,
                textAlign: TextAlign.center,
                style: context.typo.body.copyWith(color: context.colors.text3),
              ),
              const SizedBox(height: 16),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  OutlineButton(
                    onPressed: () =>
                        unawaited(launcher.launchUrl(Uri.file(path))),
                    child: Text(openInBrowser),
                  ),
                  const SizedBox(width: 8),
                  OutlineButton(
                    onPressed: onOpenAsHtml,
                    child: Text(openAsHtml),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
