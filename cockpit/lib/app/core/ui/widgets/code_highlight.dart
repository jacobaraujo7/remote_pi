import 'package:cockpit/app/core/domain/entities/lsp_diagnostic.dart';
import 'package:cockpit/app/core/ui/themes/themes.dart';
import 'package:flutter/widgets.dart';
import 'package:highlight/highlight.dart' as hl;

/// Extensões cujo nome **não** bate com o id do highlight.js e cuja gramática
/// não declara alias — precisam ser mapeadas na mão. As demais (rs, yml, sh,
/// toml, rb, py, c, h, …) já são resolvidas pelos aliases das próprias
/// gramáticas; e qualquer extensão desconhecida cai em texto puro (plaintext).
const Map<String, String> _extToLanguage = {
  'ts': 'typescript',
  // `.tsx`/`.jsx` vão pro grammar **javascript** de propósito: o grammar
  // `typescript` do highlight.js **não** entende JSX — ao topar `<Tag/>` ele
  // aborta (regra `illegal`) e devolve um único nó plaintext (nodes=1,
  // relevance=0), ou seja, zero realce. O `javascript` traz o sub-idioma xml e
  // pinta as tags JSX; perde-se só uns keywords TS (interface/enum), troca que
  // compensa (highlight vs. nada). `.ts` puro (sem JSX) fica no `typescript`.
  'tsx': 'javascript',
  'mts': 'typescript',
  'cts': 'typescript',
  'js': 'javascript',
  'jsx': 'javascript',
  'mjs': 'javascript',
  'cjs': 'javascript',
  'kt': 'kotlin',
  'kts': 'kotlin',
  'html': 'xml',
  'htm': 'xml',
  'xhtml': 'xml',
};

/// Language id resolvido pelo **nome do arquivo**, para casos onde a extensão
/// sozinha não identifica a linguagem (dotfiles compostos): `.env` não tem
/// extensão e `.env.local`/`.env.qa` extraem `local`/`qa`. `null` quando o nome
/// não é especial — o caller cai no fluxo normal por extensão.
String? filenameLanguageOf(String path) {
  final name = path.split(RegExp(r'[/\\]')).last.toLowerCase();
  if (name == '.env' || name.startsWith('.env.')) return 'dotenv';
  // go.mod não tem grammar no package (ext `mod` cai em plaintext); go.sum
  // pega carona (versões/strings — o resto fica neutro).
  if (name == 'go.mod' || name == 'go.sum') return 'gomod';
  // O grammar `dockerfile` existe no package; o que falta é detecção —
  // `Dockerfile` não tem extensão e `Dockerfile.dev`/`app.Dockerfile` extraem
  // `dev`/`dockerfile` (este último até funcionaria, mas normaliza aqui).
  if (name == 'dockerfile' ||
      name == 'containerfile' ||
      name.startsWith('dockerfile.') ||
      name.endsWith('.dockerfile')) {
    return 'dockerfile';
  }
  return null;
}

/// Gramáticas próprias (fora do catálogo do package `highlight`), registradas
/// uma vez no singleton antes do primeiro parse.
bool _customLanguagesRegistered = false;

void _ensureCustomLanguages() {
  if (_customLanguagesRegistered) return;
  _customLanguagesRegistered = true;
  hl.highlight.registerLanguage('dotenv', _dotenvMode());
  hl.highlight.registerLanguage('gomod', _goModMode());
}

/// Gramática go.mod/go.sum: diretivas no começo da linha (`module`, `require`,
/// `replace`, …) como keyword, versões `vX.Y.Z` como number, strings, `=>` do
/// replace e comentário `//`. Mesma restrição do dotenv: sem lookahead em
/// `begin`.
hl.Mode _goModMode() {
  return hl.Mode(
    contains: [
      hl.Mode(className: 'comment', begin: r'//', end: r'$', relevance: 0),
      hl.Mode(
        className: 'keyword',
        begin:
            r'^[ \t]*(module|go|toolchain|require|replace|exclude|retract|use)\b',
        relevance: 0,
      ),
      hl.Mode(className: 'string', begin: '"', end: '"', relevance: 0),
      hl.Mode(className: 'number', begin: r'\bv\d+\.[^\s/]+', relevance: 0),
      hl.Mode(className: 'keyword', begin: r'=>', relevance: 0),
    ],
  );
}

/// Gramática dotenv: comentário `#`, `export` opcional, chave (`attr`) até o
/// `=`, valor até o fim da linha com strings aspadas e interpolação
/// `$VAR`/`${VAR}` (`variable`). Estrutura espelha o grammar `properties` do
/// package: o begin externo valida a linha `chave=` inteira, `returnBegin`
/// devolve o cursor e os modes internos consomem keyword/chave, com `starts`
/// encadeando separador → valor. **Atenção**: lookahead `(?=...)` em `begin`
/// não casa no port Dart do highlight.js — por isso os modes internos
/// consomem os tokens direto (sem lookahead), validados pelo begin externo.
hl.Mode _dotenvMode() {
  final interpolation = hl.Mode(
    className: 'variable',
    variants: [
      hl.Mode(begin: r'\$\{[A-Za-z_][A-Za-z0-9_]*\}'),
      hl.Mode(begin: r'\$[A-Za-z_][A-Za-z0-9_]*'),
    ],
    relevance: 0,
  );
  final comment = hl.Mode(
    className: 'comment',
    begin: r'#',
    end: r'$',
    relevance: 0,
  );
  final value = hl.Mode(
    end: r'$',
    relevance: 0,
    contains: [
      hl.Mode(
        className: 'string',
        begin: '"',
        end: '"',
        contains: [
          hl.Mode(begin: r'\\.'),
          interpolation,
        ],
      ),
      hl.Mode(className: 'string', begin: "'", end: "'"),
      interpolation,
      comment,
    ],
  );
  return hl.Mode(
    contains: [
      comment,
      hl.Mode(
        begin: r'^[ \t]*(export[ \t]+)?[A-Za-z_][A-Za-z0-9_.-]*[ \t]*=',
        returnBegin: true,
        relevance: 0,
        contains: [
          hl.Mode(className: 'keyword', begin: r'export[ \t]+', relevance: 0),
          hl.Mode(
            className: 'attr',
            begin: r'[A-Za-z_][A-Za-z0-9_.-]+',
            endsParent: true,
            relevance: 0,
          ),
        ],
        starts: hl.Mode(end: r'[ \t]*=[ \t]*', relevance: 0, starts: value),
      ),
    ],
  );
}

/// Teto pra ligar o highlight. Acima disso o parse + a árvore de spans não
/// compensam (e o reader já corta arquivos em 2MB); cai no texto puro.
const int _kMaxHighlightChars = 200 * 1024;

/// Um range de diagnostic já convertido para **offsets** lineares no texto
/// (code units UTF-16) — ver `CodeEditingController.offsetFor`. `[start, end)`.
class DiagnosticRange {
  const DiagnosticRange(this.start, this.end, this.severity);

  final int start;
  final int end;
  final LspSeverity severity;
}

/// Um intervalo casado pela busca **no arquivo** (Cmd+F), em offsets lineares
/// UTF-16 `[start, end)`. Pintado com fundo destacado sobre o syntax highlight.
class MatchSpan {
  const MatchSpan(this.start, this.end);

  final int start;
  final int end;
}

/// Converte diagnostics do LSP (posições `line`/`character`, base 0, UTF-16) em
/// [DiagnosticRange]s de offset linear sobre [text]. As code units UTF-16 do LSP
/// batem 1:1 com a `String` Dart — é só aritmética de offset (nunca
/// `.runes`/`.characters`). Posições defasadas são clampadas; ranges de largura
/// zero viram 1 caractere para terem um glifo a sublinhar. Reusada pelo editor
/// (via controller) e pelo viewer read-only.
List<DiagnosticRange> diagnosticRangesFor(
  String text,
  List<LspDiagnostic> diagnostics,
) {
  if (diagnostics.isEmpty) return const <DiagnosticRange>[];

  // Índice de início de cada linha (offset logo após cada '\n').
  final lineStarts = <int>[0];
  for (var i = 0; i < text.length; i++) {
    if (text.codeUnitAt(i) == 0x0A) lineStarts.add(i + 1);
  }

  int offsetFor(int line, int character) {
    if (line < 0) return 0;
    if (line >= lineStarts.length) return text.length;
    final base = lineStarts[line];
    final contentEnd = line + 1 < lineStarts.length
        ? lineStarts[line + 1] - 1
        : text.length;
    final offset = base + (character < 0 ? 0 : character);
    return offset.clamp(base, contentEnd);
  }

  final ranges = <DiagnosticRange>[];
  for (final d in diagnostics) {
    var start = offsetFor(d.range.start.line, d.range.start.character);
    var end = offsetFor(d.range.end.line, d.range.end.character);
    if (end < start) {
      final tmp = start;
      start = end;
      end = tmp;
    }
    if (end == start) end = (start + 1).clamp(0, text.length);
    if (end > start) ranges.add(DiagnosticRange(start, end, d.severity));
  }
  return ranges;
}

/// Constrói os spans coloridos de [source] para a linguagem [language] (a
/// extensão do arquivo), aplicando o sublinhado ondulado dos [diagnostics] nos
/// ranges cobertos. Retorna `null` apenas quando não há nada a pintar (sem
/// linguagem **e** sem diagnostics, arquivo grande sem diagnostics, ou parse
/// vazio sem diagnostics) — o chamador então renderiza o texto puro.
TextSpan? buildCodeSpan(
  BuildContext context, {
  required String source,
  required String? language,
  required TextStyle baseStyle,
  List<DiagnosticRange> diagnostics = const <DiagnosticRange>[],
  List<MatchSpan> matches = const <MatchSpan>[],
  int currentMatch = -1,
  Color? matchColor,
  Color? currentMatchColor,
}) {
  final palette = context.syntax;
  final leaves = _leavesOf(source, language, palette);
  final overlays = _Overlays(
    diagnostics,
    matches,
    currentMatch,
    matchColor,
    currentMatchColor,
  );
  if (leaves == null) {
    // Sem highlight possível. Só vale construir spans se houver overlays
    // (diagnostics ou matches de busca) a pintar; senão, deixa o chamador
    // renderizar o texto puro.
    if (!overlays.hasAny) return null;
    return TextSpan(
      style: baseStyle,
      children: _applyOverlays(<_Leaf>[_Leaf(source, null)], overlays),
    );
  }
  return TextSpan(style: baseStyle, children: _applyOverlays(leaves, overlays));
}

/// Sobreposições a fundir sobre os spans de syntax: sublinhado de diagnostics
/// (LSP) e fundo dos matches da busca no arquivo (Cmd+F).
class _Overlays {
  const _Overlays(
    this.diagnostics,
    this.matches,
    this.currentMatch,
    this.matchColor,
    this.currentMatchColor,
  );

  final List<DiagnosticRange> diagnostics;
  final List<MatchSpan> matches;
  final int currentMatch;
  final Color? matchColor;
  final Color? currentMatchColor;

  bool get hasAny => diagnostics.isNotEmpty || matches.isNotEmpty;

  /// Fundo do match que cobre `[a, b)` (o match atual tem cor mais forte), ou
  /// `null` se nenhum match cobre o trecho.
  Color? backgroundFor(int a, int b) {
    for (var i = 0; i < matches.length; i++) {
      final m = matches[i];
      if (m.start <= a && m.end >= b) {
        return i == currentMatch ? currentMatchColor : matchColor;
      }
    }
    return null;
  }
}

/// Folha achatada da árvore do highlight.js: um trecho de texto + seu estilo
/// (cor de syntax já resolvida). A ordem reconstrói o texto inteiro.
class _Leaf {
  _Leaf(this.text, this.style);
  final String text;
  final TextStyle? style;
}

/// Parseia [source] e achata a árvore do highlight.js em folhas. Retorna `null`
/// quando não dá pra destacar (sem linguagem, arquivo grande, parse vazio).
List<_Leaf>? _leavesOf(String source, String? language, SyntaxColors palette) {
  if (language == null || language.isEmpty) return null;
  if (source.length > _kMaxHighlightChars) return null;

  _ensureCustomLanguages();
  final lang = _extToLanguage[language.toLowerCase()] ?? language.toLowerCase();
  final nodes = hl.highlight.parse(source, language: lang).nodes;
  if (nodes == null || nodes.isEmpty) return null;

  final leaves = <_Leaf>[];
  for (final node in nodes) {
    _flatten(node, null, palette, leaves);
  }
  return leaves;
}

/// Recursão que acumula o estilo herdado (containers do highlight.js aplicam
/// `className` aos descendentes) e emite uma folha por `value`.
void _flatten(
  hl.Node node,
  TextStyle? inherited,
  SyntaxColors palette,
  List<_Leaf> out,
) {
  final own = node.className == null ? null : palette.styleFor(node.className!);
  final style = own == null
      ? inherited
      : (inherited ?? const TextStyle()).merge(own);
  if (node.value != null) {
    out.add(_Leaf(node.value!, style));
    return;
  }
  final children = node.children;
  if (children == null) return;
  for (final child in children) {
    _flatten(child, style, palette, out);
  }
}

/// Corta as folhas nos limites dos diagnostics **e** dos matches de busca, e
/// funde em cada sub-trecho o sublinhado ondulado (diagnostics) + o fundo do
/// match (busca), preservando a cor de syntax. Sem overlays, devolve 1:1.
List<InlineSpan> _applyOverlays(List<_Leaf> leaves, _Overlays overlays) {
  if (!overlays.hasAny) {
    return <InlineSpan>[
      for (final leaf in leaves) TextSpan(text: leaf.text, style: leaf.style),
    ];
  }
  final diagnostics = overlays.diagnostics;
  final matches = overlays.matches;
  final out = <InlineSpan>[];
  var pos = 0;
  for (final leaf in leaves) {
    final start = pos;
    final end = pos + leaf.text.length;
    pos = end;
    if (leaf.text.isEmpty) continue;

    // Pontos de corte = início/fim da folha + limites de overlays internos.
    final cuts = <int>{start, end};
    for (final d in diagnostics) {
      if (d.end <= start || d.start >= end) continue;
      if (d.start > start && d.start < end) cuts.add(d.start);
      if (d.end > start && d.end < end) cuts.add(d.end);
    }
    for (final m in matches) {
      if (m.end <= start || m.start >= end) continue;
      if (m.start > start && m.start < end) cuts.add(m.start);
      if (m.end > start && m.end < end) cuts.add(m.end);
    }
    final sorted = cuts.toList()..sort();
    for (var i = 0; i + 1 < sorted.length; i++) {
      final a = sorted[i];
      final b = sorted[i + 1];
      final sub = leaf.text.substring(a - start, b - start);
      var style = leaf.style;
      final severity = _coveringSeverity(diagnostics, a, b);
      if (severity != null) {
        style = (style ?? const TextStyle()).merge(
          SyntaxColors.underlineStyleFor(severity),
        );
      }
      final bg = overlays.backgroundFor(a, b);
      if (bg != null) {
        style = (style ?? const TextStyle()).copyWith(backgroundColor: bg);
      }
      out.add(TextSpan(text: sub, style: style));
    }
  }
  return out;
}

/// Severidade mais grave que cobre `[a, b)` (error > warning > info > hint), ou
/// `null` se nenhum diagnostic cobre o trecho.
LspSeverity? _coveringSeverity(
  List<DiagnosticRange> diagnostics,
  int a,
  int b,
) {
  LspSeverity? result;
  for (final d in diagnostics) {
    if (d.start <= a && d.end >= b) {
      // index menor = mais grave (error=0).
      if (result == null || d.severity.index < result.index) {
        result = d.severity;
      }
    }
  }
  return result;
}
