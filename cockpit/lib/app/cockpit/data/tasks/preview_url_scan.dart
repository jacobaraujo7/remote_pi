// Primeira URL de dev server no output de uma task (plano 58). URLs que uma
// ferramenta marcou como sessão (DevTools, VM Service) não contam: o scan
// segue e ainda pode achar a URL do app.

/// Sequências ANSI (cores/cursor) — removidas antes de casar a URL.
final RegExp previewAnsiPattern = RegExp(r'\x1b\[[0-9;?]*[a-zA-Z]');

/// `http://localhost:5173/`, `127.0.0.1`, `0.0.0.0`. Path sem espaços, aspas
/// ou fechamentos. Para antes de `?` — a query do DevTools não entra aqui.
final RegExp localPreviewUrlPattern = RegExp(
  r'''https?://(?:localhost|127\.0\.0\.1|0\.0\.0\.0)(?::\d+)?(?:/[^\s"'`)\]]*)?''',
);

/// Quanto de output limpo o runner guarda entre chunks. Cobre uma linha de
/// DevTools (e a URL do app) partida no meio.
const int previewOutputTail = 512;

/// `true` quando [candidate] é a própria URL de sessão ou um pedaço dela
/// (o regex de preview corta em `?`, então `http://127.0.0.1:9100` casa com
/// `http://127.0.0.1:9100?uri=http://127.0.0.1:port/token=/`).
bool isConsumedPreviewUrl(String candidate, List<String> consumed) {
  for (final raw in consumed) {
    if (raw.isEmpty) continue;
    if (raw == candidate ||
        raw.contains(candidate) ||
        candidate.contains(raw)) {
      return true;
    }
  }
  return false;
}

/// Junta uma URL de serviço que o `flutter run` partiu na largura do terminal.
///
/// Uma URL sem espaços é cortada no meio da linha. No painel estreito o corte
/// cai no `=` do código de autenticação e o `/ws` vai para a linha seguinte.
/// Sem a junção, a sessão abre `ws://host:port/token` e o DevTools não conecta.
String joinWrappedPreviewLines(String text) {
  if (!text.contains('\n') && !text.contains('\r')) return text;
  final lines = text.split(RegExp(r'\r?\n|\r'));
  final out = StringBuffer();
  for (var i = 0; i < lines.length; i++) {
    var line = lines[i];
    while (i + 1 < lines.length && _wrapContinues(line, lines[i + 1])) {
      i++;
      line += lines[i].trimLeft();
    }
    if (out.isNotEmpty) out.write('\n');
    out.write(line);
  }
  return out.toString();
}

final RegExp _urlAtLineEnd = RegExp(r'https?://\S+$');

/// Resto de uma URL: sem espaço e sem começar outra frase ou outro endereço.
final RegExp _urlContinuation = RegExp(
  r'''^[A-Za-z0-9%._~:/?#\[\]@!$&'()*+,;=-]+$''',
);

bool _wrapContinues(String line, String next) {
  final match = _urlAtLineEnd.firstMatch(line);
  if (match == null || _serviceUrlFinished(match.group(0)!)) return false;
  final token = next.trimLeft();
  if (token.isEmpty || token.length > 180 || token.contains('://')) {
    return false;
  }
  if (RegExp(r'^[A-Z][a-z]').hasMatch(token)) return false;
  return _urlContinuation.hasMatch(token);
}

/// `true` quando o alvo (`?uri=` ou a própria URL) já tem o path fechado.
bool _serviceUrlFinished(String url) {
  final at = url.indexOf('uri=');
  final value = at < 0 ? url : url.substring(at + 4);
  if (value.startsWith('ws://') || value.startsWith('wss://')) {
    return value.endsWith('/ws');
  }
  if (value.startsWith('http://') || value.startsWith('https://')) {
    return value.endsWith('/');
  }
  return false;
}

/// Primeira URL local de [haystack] que não está em [consumed].
///
/// Null se não há URL, ou se a única candidata termina o texto — a porta ou
/// o path podem ter sido cortados no meio do chunk. O caller guarda a cauda
/// e tenta de novo com o próximo.
String? scanPreviewUrl(String haystack, {List<String> consumed = const []}) {
  var from = 0;
  while (from < haystack.length) {
    final match = localPreviewUrlPattern.firstMatch(haystack.substring(from));
    if (match == null) return null;
    final end = from + match.end;
    if (end == haystack.length) return null;
    final candidate = match.group(0)!;
    if (isConsumedPreviewUrl(candidate, consumed)) {
      from = end;
      continue;
    }
    return candidate;
  }
  return null;
}
