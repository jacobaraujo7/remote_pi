import 'package:cockpit/app/core/domain/entities/lsp_diagnostic.dart';

/// Um `TextEdit` do LSP: substitui o trecho em [range] por [newText]. É o que
/// `textDocument/formatting` devolve — uma lista a aplicar no buffer.
class LspTextEdit {
  const LspTextEdit({required this.range, required this.newText});

  final LspRange range;
  final String newText;

  factory LspTextEdit.fromJson(Map<String, dynamic> json) => LspTextEdit(
    range: LspRange.fromJson((json['range'] as Map).cast<String, dynamic>()),
    newText: json['newText'] as String? ?? '',
  );
}

/// Parseia o resultado de `textDocument/formatting` (lista de TextEdit) numa
/// lista tipada. Resultado nulo/vazio → lista vazia.
List<LspTextEdit> parseTextEdits(Object? result) {
  if (result is! List) return const <LspTextEdit>[];
  return <LspTextEdit>[
    for (final e in result)
      if (e is Map<String, dynamic>) LspTextEdit.fromJson(e),
  ];
}

/// Aplica os [edits] (posições `line`/`character`, base 0, UTF-16) sobre [text]
/// e devolve o texto formatado. Aplica de trás pra frente (por offset de início
/// decrescente) pra que os offsets dos edits anteriores não desloquem.
///
/// As code units UTF-16 do LSP batem 1:1 com a `String` Dart — só aritmética de
/// offset (nunca `.runes`/`.characters`).
String applyTextEdits(String text, List<LspTextEdit> edits) {
  if (edits.isEmpty) return text;

  // Índice de início de cada linha (offset logo após cada '\n').
  final lineStarts = <int>[0];
  for (var i = 0; i < text.length; i++) {
    if (text.codeUnitAt(i) == 0x0A) lineStarts.add(i + 1);
  }
  int offsetFor(LspPosition p) {
    if (p.line < 0) return 0;
    if (p.line >= lineStarts.length) return text.length;
    final base = lineStarts[p.line];
    final lineEnd = p.line + 1 < lineStarts.length
        ? lineStarts[p.line + 1] - 1
        : text.length;
    return (base + (p.character < 0 ? 0 : p.character)).clamp(base, lineEnd);
  }

  // Resolve os edits para (start, end, newText) e ordena por start decrescente.
  final resolved = <({int start, int end, String newText})>[
    for (final e in edits)
      (
        start: offsetFor(e.range.start),
        end: offsetFor(e.range.end),
        newText: e.newText,
      ),
  ]..sort((a, b) => b.start.compareTo(a.start));

  var result = text;
  for (final e in resolved) {
    final start = e.start.clamp(0, result.length);
    final end = e.end.clamp(start, result.length);
    result = result.replaceRange(start, end, e.newText);
  }
  return result;
}
