import 'package:cockpit/ui/core/themes/themes.dart';
import 'package:flutter/material.dart';
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

/// Constrói os spans coloridos de [source] para a linguagem [language] (a
/// extensão do arquivo). Retorna `null` quando não vale a pena destacar (sem
/// linguagem, arquivo grande, ou parse vazio) — o chamador então renderiza o
/// texto puro com [baseStyle].
TextSpan? buildCodeSpan(
  BuildContext context, {
  required String source,
  required String? language,
  required TextStyle baseStyle,
}) {
  if (language == null || language.isEmpty) return null;
  if (source.length > _kMaxHighlightChars) return null;

  final lang = _extToLanguage[language.toLowerCase()] ?? language.toLowerCase();
  final nodes = hl.highlight.parse(source, language: lang).nodes;
  if (nodes == null || nodes.isEmpty) return null;

  final palette = context.syntax;
  return TextSpan(
    style: baseStyle,
    children: [for (final node in nodes) _spanOf(node, palette)],
  );
}

/// Converte um nó do highlight.js em [TextSpan]: folhas trazem `value`,
/// containers trazem `children` e (talvez) um `className` que dá o estilo.
TextSpan _spanOf(hl.Node node, SyntaxColors palette) {
  final style = node.className == null ? null : palette.styleFor(node.className!);
  if (node.value != null) {
    return TextSpan(text: node.value, style: style);
  }
  final children = node.children;
  return TextSpan(
    style: style,
    children: children == null
        ? const <TextSpan>[]
        : [for (final child in children) _spanOf(child, palette)],
  );
}
