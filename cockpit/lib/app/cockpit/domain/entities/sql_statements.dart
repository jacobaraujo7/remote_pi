/// Um statement SQL dentro de um buffer: texto executável (sem `;` final) e
/// os offsets [start, end) no buffer original (o `;` pertence ao range).
class SqlStatement {
  const SqlStatement(this.text, this.start, this.end);
  final String text;
  final int start;
  final int end;
}

/// Divide [source] em statements por `;`, ignorando `;` dentro de strings
/// (`'…'` com escape `''`, `"…"`, `` `…` ``), comentários de linha (`--`) e de
/// bloco (`/* */`). Chunks só de comentário/whitespace são descartados.
///
/// É o suficiente pro semântica de Run dos clients (DataGrip/DBeaver):
/// statement sob o cursor / statements tocados pela seleção.
List<SqlStatement> splitSqlStatements(String source) {
  final out = <SqlStatement>[];
  var stmtStart = 0;
  var i = 0;
  while (i < source.length) {
    final c = source[i];
    if (c == "'" || c == '"' || c == '`') {
      i = _skipQuoted(source, i, c);
      continue;
    }
    if (c == '-' && i + 1 < source.length && source[i + 1] == '-') {
      final nl = source.indexOf('\n', i);
      i = nl < 0 ? source.length : nl + 1;
      continue;
    }
    if (c == '/' && i + 1 < source.length && source[i + 1] == '*') {
      final close = source.indexOf('*/', i + 2);
      i = close < 0 ? source.length : close + 2;
      continue;
    }
    if (c == ';') {
      _addStatement(out, source, stmtStart, i + 1);
      stmtStart = i + 1;
    }
    i++;
  }
  _addStatement(out, source, stmtStart, source.length);
  return out;
}

/// Statement sob o [offset] do cursor: o primeiro cujo range ainda não acabou
/// no offset (cursor em whitespace entre statements pega o anterior — mesmo
/// comportamento do DataGrip com o caret depois do `;`). `null` só com lista
/// vazia.
SqlStatement? statementAt(List<SqlStatement> statements, int offset) {
  if (statements.isEmpty) return null;
  for (final s in statements) {
    if (offset <= s.end) return s;
  }
  return statements.last;
}

/// Statements que a seleção [start, end) toca (expandidos pro statement
/// inteiro). Seleção só em whitespace cai no [statementAt] do início.
List<SqlStatement> statementsInRange(
  List<SqlStatement> statements,
  int start,
  int end,
) {
  final hit = [
    for (final s in statements)
      if (s.start < end && s.end > start) s,
  ];
  if (hit.isNotEmpty) return hit;
  final at = statementAt(statements, start);
  return at == null ? const [] : [at];
}

int _skipQuoted(String src, int open, String quote) {
  var i = open + 1;
  while (i < src.length) {
    if (src[i] == quote) {
      // `''` dentro de string single-quote é escape, não fechamento.
      if (quote == "'" && i + 1 < src.length && src[i + 1] == "'") {
        i += 2;
        continue;
      }
      return i + 1;
    }
    i++;
  }
  return src.length;
}

void _addStatement(List<SqlStatement> out, String src, int start, int end) {
  final raw = src.substring(start, end).trim();
  final text = raw.endsWith(';')
      ? raw.substring(0, raw.length - 1).trim()
      : raw;
  if (text.isEmpty || _isOnlyComments(text)) return;
  out.add(SqlStatement(text, start, end));
}

/// `true` se [text] só tem comentários/whitespace (nada executável).
bool _isOnlyComments(String text) {
  var i = 0;
  while (i < text.length) {
    final c = text[i];
    if (c == ' ' || c == '\t' || c == '\n' || c == '\r') {
      i++;
      continue;
    }
    if (c == '-' && i + 1 < text.length && text[i + 1] == '-') {
      final nl = text.indexOf('\n', i);
      if (nl < 0) return true;
      i = nl + 1;
      continue;
    }
    if (c == '/' && i + 1 < text.length && text[i + 1] == '*') {
      final close = text.indexOf('*/', i + 2);
      if (close < 0) return true;
      i = close + 2;
      continue;
    }
    return false;
  }
  return true;
}
