/// Um arquivo `.panel` (plano 67): front-matter YAML opcional entre `---` no
/// topo + uma página HTML comum. O app abre o HTML numa webview viva com a
/// ponte `window.cockpit(line)` injetada; o front-matter só configura a aba.
///
/// Só o subconjunto `chave: valor` (uma linha por chave) é lido. Chaves
/// desconhecidas ficam em [fields] para quem quiser (a página não as vê).
class PanelDocument {
  const PanelDocument({
    required this.body,
    this.title,
    this.reload = true,
    this.cwd,
    this.fields = const {},
  });

  /// O HTML depois do front-matter (ou o arquivo inteiro, sem front-matter).
  final String body;

  /// Título da aba; `null` = nome do arquivo.
  final String? title;

  /// Recarregar a página quando o arquivo muda em disco. Default `true`.
  final bool reload;

  /// Diretório de trabalho do `exec` e das chamadas da CLI, relativo à pasta
  /// do arquivo (`null` = a própria pasta).
  final String? cwd;

  /// Todas as chaves do front-matter, cruas.
  final Map<String, String> fields;

  static final _fence = RegExp(r'^---\s*$');
  static final _kv = RegExp(r'^([A-Za-z_][\w-]*)\s*:\s*(.*?)\s*$');

  static PanelDocument parse(String raw) {
    var text = raw;
    if (text.startsWith('﻿')) text = text.substring(1);
    final lines = text.split('\n');
    if (lines.isEmpty || !_fence.hasMatch(lines.first.trimRight())) {
      return PanelDocument(body: text);
    }
    int? close;
    for (var i = 1; i < lines.length; i++) {
      final l = lines[i].trimRight();
      if (_fence.hasMatch(l) || l == '...') {
        close = i;
        break;
      }
    }
    // Sem fecho = não é front-matter, é uma linha `---` no HTML.
    if (close == null) return PanelDocument(body: text);
    final fields = <String, String>{};
    for (final line in lines.sublist(1, close)) {
      final trimmed = line.trim();
      if (trimmed.isEmpty || trimmed.startsWith('#')) continue;
      final m = _kv.firstMatch(line.trimRight());
      if (m == null) continue;
      fields[m.group(1)!] = _unquote(_stripComment(m.group(2)!));
    }
    final body = lines.sublist(close + 1).join('\n');
    final reloadRaw = fields['reload']?.toLowerCase();
    final title = fields['title'];
    final cwd = fields['cwd'];
    return PanelDocument(
      body: body,
      title: (title == null || title.isEmpty) ? null : title,
      reload: !const {'false', 'no', 'off', '0'}.contains(reloadRaw),
      cwd: (cwd == null || cwd.isEmpty) ? null : cwd,
      fields: fields,
    );
  }

  /// Corta um `# comentário` no fim do valor. Valor entre aspas termina na
  /// aspa de fecho (o que vier depois é comentário ou lixo).
  static String _stripComment(String v) {
    if (v.startsWith('"') || v.startsWith("'")) {
      final close = v.indexOf(v[0], 1);
      return close < 0 ? v : v.substring(0, close + 1);
    }
    final idx = v.indexOf(' #');
    return idx < 0 ? v : v.substring(0, idx).trimRight();
  }

  static String _unquote(String v) {
    if (v.length >= 2) {
      final a = v[0];
      final b = v[v.length - 1];
      if ((a == '"' && b == '"') || (a == "'" && b == "'")) {
        return v.substring(1, v.length - 1);
      }
    }
    return v;
  }
}
