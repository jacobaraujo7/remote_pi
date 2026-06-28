/// Utilitário **JSONC** (JSON with Comments, igual ao VSCode): converte um texto
/// com comentários `//` e `/* */` e **vírgulas finais** em JSON estrito que o
/// `dart:convert` `jsonDecode` aceita.
///
/// É **string-aware**: não toca em `//`, `/*` ou `,` que aparecem **dentro** de
/// strings (ex.: uma URL `"https://x"` ou um regex `"a, b"`). Preserva quebras
/// de linha (offsets/linhas de erro ficam coerentes).
String stripJsonc(String input) => _stripTrailingCommas(_stripComments(input));

String _stripComments(String s) {
  final out = StringBuffer();
  var inString = false;
  var escaped = false;
  for (var i = 0; i < s.length; i++) {
    final c = s[i];
    if (inString) {
      out.write(c);
      if (escaped) {
        escaped = false;
      } else if (c == '\\') {
        escaped = true;
      } else if (c == '"') {
        inString = false;
      }
      continue;
    }
    if (c == '"') {
      inString = true;
      out.write(c);
      continue;
    }
    if (c == '/' && i + 1 < s.length) {
      final next = s[i + 1];
      if (next == '/') {
        i += 2;
        while (i < s.length && s[i] != '\n') {
          i++;
        }
        if (i < s.length) out.write('\n'); // preserva a linha
        continue;
      }
      if (next == '*') {
        i += 2;
        while (i + 1 < s.length && !(s[i] == '*' && s[i + 1] == '/')) {
          if (s[i] == '\n') out.write('\n'); // preserva linhas internas
          i++;
        }
        i += 1; // aponta para o '/'; o for faz o i++ final
        continue;
      }
    }
    out.write(c);
  }
  return out.toString();
}

String _stripTrailingCommas(String s) {
  final out = StringBuffer();
  var inString = false;
  var escaped = false;
  for (var i = 0; i < s.length; i++) {
    final c = s[i];
    if (inString) {
      out.write(c);
      if (escaped) {
        escaped = false;
      } else if (c == '\\') {
        escaped = true;
      } else if (c == '"') {
        inString = false;
      }
      continue;
    }
    if (c == '"') {
      inString = true;
      out.write(c);
      continue;
    }
    if (c == ',') {
      // Olha o próximo token significativo: se for `}` ou `]`, a vírgula é final.
      var j = i + 1;
      while (j < s.length && (s[j] == ' ' || s[j] == '\t' || s[j] == '\r' || s[j] == '\n')) {
        j++;
      }
      if (j < s.length && (s[j] == '}' || s[j] == ']')) {
        continue; // descarta a vírgula final
      }
    }
    out.write(c);
  }
  return out.toString();
}
