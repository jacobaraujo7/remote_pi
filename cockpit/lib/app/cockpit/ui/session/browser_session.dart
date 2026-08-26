import 'package:cockpit/app/cockpit/ui/session/pane_item.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

/// Completa o scheme de URLs digitadas/recebidas: alvo local ganha http, o
/// resto https. `0.0.0.0` (bind-address de dev server) vira `localhost`.
String normalizeBrowserUrl(String input) {
  var raw = input.trim();
  if (raw.isEmpty) return raw;
  raw = raw.replaceFirst('0.0.0.0', 'localhost');
  if (raw.contains('://') || raw.startsWith('about:')) return raw;
  final local = raw.startsWith('localhost') || raw.startsWith('127.');
  return local ? 'http://$raw' : 'https://$raw';
}

/// Aba de **navegador** (plano 58): webview inline com toolbar compacta
/// (voltar / avançar / reload / URL). O estado durável é só a [url] corrente —
/// histórico back/forward vive no próprio webview e morre com a aba.
class BrowserSession extends PaneItem {
  BrowserSession({
    required this.id,
    required this.projectId,
    required this.workingDirectory,
    this.url = '',
  });

  @override
  final String id;
  @override
  final String projectId;
  @override
  final String workingDirectory;

  /// Última URL efetivamente carregada (persistida no descritor da aba).
  /// Mutada pelo widget via [reportNavigation].
  String url;

  /// Título da página corrente (`<title>`), reportado pelo webview.
  String? pageTitle;

  @override
  String get title {
    final t = pageTitle;
    if (t != null && t.trim().isNotEmpty) return t;
    if (url.isEmpty) return 'Browser';
    return Uri.tryParse(url)?.host.ifEmpty(url) ?? url;
  }

  /// Webview reporta navegação/título — atualiza a aba sem rebuild do resto.
  void reportNavigation({String? url, String? title}) {
    var changed = false;
    if (url != null && url != this.url) {
      this.url = url;
      changed = true;
    }
    if (title != null && title != pageTitle) {
      pageTitle = title;
      changed = true;
    }
    if (changed) notifyListeners();
  }

  /// URL semeada de fora (CLI `cockpit browse`, auto-open de task): o widget
  /// montado escuta a sessão e navega; no mount, o initState consome via
  /// [takeSeedUrl]. Mesmo padrão do MongoBrowserSession.seedFilter.
  String? seedUrl;

  void requestUrl(String url) {
    seedUrl = url;
    notifyListeners();
  }

  /// Consome o seed pendente (uma vez).
  String? takeSeedUrl() {
    final u = seedUrl;
    seedUrl = null;
    return u;
  }

  /// Controller do webview vivo (plano 61, decisão C): setado por
  /// [BrowserPane] em `onWebViewCreated`, limpo no `dispose`. É a ponte que
  /// `CockpitCliHandler` usa pra injetar JS (`browser read/click/type/
  /// screenshot/eval`) — sem notificação, é lido sob demanda, não observado.
  /// `null` = aba nunca montou o webview, ou já foi fechada.
  InAppWebViewController? controller;
}

extension on String {
  String ifEmpty(String fallback) => isEmpty ? fallback : this;
}
