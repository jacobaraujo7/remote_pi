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
  'tsx': 'typescript',
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
}) {
  final palette = context.syntax;
  final leaves = _leavesOf(source, language, palette);
  if (leaves == null) {
    // Sem highlight possível. Só vale construir spans se houver diagnostics
    // para sublinhar; senão, deixa o chamador pintar o texto puro.
    if (diagnostics.isEmpty) return null;
    return TextSpan(
      style: baseStyle,
      children: _applyDiagnostics(<_Leaf>[_Leaf(source, null)], diagnostics),
    );
  }
  return TextSpan(
    style: baseStyle,
    children: _applyDiagnostics(leaves, diagnostics),
  );
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

/// Corta as folhas nos limites dos diagnostics e funde o sublinhado ondulado nos
/// sub-trechos cobertos (preservando a cor de syntax). Sem diagnostics, devolve
/// os spans 1:1.
List<InlineSpan> _applyDiagnostics(
  List<_Leaf> leaves,
  List<DiagnosticRange> diagnostics,
) {
  if (diagnostics.isEmpty) {
    return <InlineSpan>[
      for (final leaf in leaves) TextSpan(text: leaf.text, style: leaf.style),
    ];
  }
  final out = <InlineSpan>[];
  var pos = 0;
  for (final leaf in leaves) {
    final start = pos;
    final end = pos + leaf.text.length;
    pos = end;
    if (leaf.text.isEmpty) continue;

    // Pontos de corte = início/fim da folha + limites de diagnostics internos.
    final cuts = <int>{start, end};
    for (final d in diagnostics) {
      if (d.end <= start || d.start >= end) continue;
      if (d.start > start && d.start < end) cuts.add(d.start);
      if (d.end > start && d.end < end) cuts.add(d.end);
    }
    final sorted = cuts.toList()..sort();
    for (var i = 0; i + 1 < sorted.length; i++) {
      final a = sorted[i];
      final b = sorted[i + 1];
      final sub = leaf.text.substring(a - start, b - start);
      final severity = _coveringSeverity(diagnostics, a, b);
      var style = leaf.style;
      if (severity != null) {
        style = (style ?? const TextStyle()).merge(
          SyntaxColors.underlineStyleFor(severity),
        );
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
