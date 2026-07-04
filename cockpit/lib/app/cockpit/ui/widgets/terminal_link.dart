import 'package:xterm/xterm.dart';

/// O que um link do terminal aponta: uma URL (abre no navegador) ou um arquivo
/// local (abre numa aba do FileViewer).
enum TerminalLinkKind { url, file }

/// Um link detectado no buffer do terminal: o alvo e o range de colunas (numa
/// linha) que ele ocupa, pra desenhar o realce e abrir no clique.
class TerminalLink {
  const TerminalLink({
    required this.kind,
    required this.target,
    required this.row,
    required this.startCol,
    required this.endCol, // exclusivo
    this.line,
  });

  final TerminalLinkKind kind;

  /// URL (kind url) ou caminho do arquivo sem o sufixo `:linha` (kind file).
  final String target;

  /// Linha alvo (base 1) quando o token traz `arquivo:42[:col]`; senão `null`.
  final int? line;

  final int row;
  final int startCol;
  final int endCol;

  bool contains(int col) => col >= startCol && col < endCol;
}

/// Acha a URL sob uma célula. Hoje por **regex** sobre o texto que o terminal
/// renderizou (território legítimo do terminal — todo emulador faz isso). O
/// gancho de OSC 8 (hyperlink explícito da app) entra no Slice 2: quando a
/// célula tiver um id de hyperlink, ele tem precedência sobre o regex.
class TerminalLinkDetector {
  // http(s):// e file://, mais www. — para em espaço e em fechamentos comuns
  // que não fazem parte de URL (aspas, parênteses, colchetes).
  static final _urlRegex = RegExp(
    r'''(?:https?://|file://|www\.)[^\s<>()\[\]{}"'`]+''',
    caseSensitive: false,
  );

  // Token com cara de caminho: sequência de segmentos separados por `/` (exige
  // ao menos uma barra), com sufixo opcional `:linha[:col]` (saída de grep/
  // compilador). Detecção puramente léxica — não toca o disco.
  static final _pathRegex = RegExp(
    r'''(?:~|\.{1,2})?/?(?:[\w@.+%-]+/)+[\w@.+%-]+(?::\d+(?::\d+)?)?''',
  );

  // Sufixo `:linha[:col]` no fim do token.
  static final _lineSuffix = RegExp(r':(\d+)(?::\d+)?$');

  // Pontuação de fim de frase que costuma grudar na URL mas não faz parte dela.
  static const _trailingTrim = '.,;:!?';

  // Igual, para caminhos — mas SEM `:` (usado no sufixo de linha) e incluindo
  // fechamentos comuns.
  static const _pathTrailingTrim = '.,;!?)]}';

  TerminalLink? linkAt(
    Terminal terminal,
    CellOffset pos, {
    bool detectFiles = false,
  }) {
    final lines = terminal.buffer.lines;
    if (pos.y < 0 || pos.y >= lines.length) return null;
    final line = lines[pos.y];
    final cols = line.length;
    if (cols <= 0 || pos.x < 0 || pos.x >= cols) return null;

    // OSC 8 (hyperlink explícito da app) tem precedência sobre o regex: é a URL
    // que a própria app marcou, não um palpite. O range é o trecho contíguo de
    // células com a mesma URL.
    if (line.getCodePoint(pos.x) != 0) {
      final url = terminal.hyperlinkUrl(line.getAttributes(pos.x));
      if (url != null && url.isNotEmpty) {
        var start = pos.x;
        var end = pos.x + 1;
        while (start > 0 &&
            terminal.hyperlinkUrl(line.getAttributes(start - 1)) == url) {
          start--;
        }
        while (end < cols &&
            terminal.hyperlinkUrl(line.getAttributes(end)) == url) {
          end++;
        }
        return TerminalLink(
          kind: TerminalLinkKind.url,
          target: url,
          row: pos.y,
          startCol: start,
          endCol: end,
        );
      }
    }

    // String indexada por COLUNA: célula vazia/spacer vira espaço (quebra a
    // URL), char real fica na sua coluna. URLs são ASCII (largura 1), então
    // coluna == índice no texto — match.start/end são colunas direto.
    final units = List<int>.filled(cols, 0x20);
    for (var c = 0; c < cols; c++) {
      final code = line.getCodePoint(c);
      if (code != 0) units[c] = code;
    }
    final text = String.fromCharCodes(units);

    for (final m in _urlRegex.allMatches(text)) {
      if (pos.x < m.start || pos.x >= m.end) continue;
      var end = m.end;
      // tira pontuação final que não é da URL (mas mantém se o ponteiro estiver
      // exatamente sobre ela)
      while (end - 1 > m.start &&
          end - 1 > pos.x &&
          _trailingTrim.contains(text[end - 1])) {
        end--;
      }
      return TerminalLink(
        kind: TerminalLinkKind.url,
        target: text.substring(m.start, end),
        row: pos.y,
        startCol: m.start,
        endCol: end,
      );
    }

    // Caminho de arquivo (só quando o consumidor sabe abrir): detecção léxica,
    // sem tocar o disco. Precisa parecer arquivo — ou ter extensão (um `.`) ou
    // vir ancorado (`/`, `./`, `../`, `~/`) — pra não realçar prosa como
    // "and/or". A URL tem precedência (loop acima retorna primeiro).
    if (detectFiles) {
      for (final m in _pathRegex.allMatches(text)) {
        if (pos.x < m.start || pos.x >= m.end) continue;
        var end = m.end;
        while (end - 1 > m.start &&
            end - 1 > pos.x &&
            _pathTrailingTrim.contains(text[end - 1])) {
          end--;
        }
        final raw = text.substring(m.start, end);
        final lineMatch = _lineSuffix.firstMatch(raw);
        final path = lineMatch != null ? raw.substring(0, lineMatch.start) : raw;
        final anchored = raw.startsWith('/') ||
            raw.startsWith('./') ||
            raw.startsWith('../') ||
            raw.startsWith('~/');
        if (!anchored && !path.contains('.')) continue;
        return TerminalLink(
          kind: TerminalLinkKind.file,
          target: path,
          line: lineMatch != null ? int.tryParse(lineMatch.group(1)!) : null,
          row: pos.y,
          startCol: m.start,
          endCol: end,
        );
      }
    }
    return null;
  }
}
