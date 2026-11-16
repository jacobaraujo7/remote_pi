import 'dart:math' as math;

import 'package:flutter/services.dart';

/// Resultado de [cutLine]: o texto que vai para a área de transferência e o
/// valor do editor sem a linha.
class LineCut {
  const LineCut(this.clipboard, this.value);

  /// A linha recortada **com** a quebra que saiu junto (`\n` ou `\r\n`). Só
  /// fica sem quebra quando o arquivo tinha uma linha só.
  final String clipboard;
  final TextEditingValue value;
}

/// Recorte da linha inteira (VS Code: Cmd/Ctrl+X sem seleção).
///
/// Só age com o cursor colapsado; seleção não vazia devolve `null` e o recorte
/// normal do campo segue. Remove a linha do cursor com a quebra que a termina
/// e põe o cursor na mesma coluna da linha que subiu, limitada ao tamanho
/// dela. Na última linha (sem quebra depois) sai a quebra de **antes**, para
/// não sobrar linha vazia no fim, e o cursor vai para o fim do texto. `\r\n`
/// é tratado como uma quebra só: sai inteiro e vai inteiro para o clipboard.
/// Arquivo vazio devolve `null` (nada a recortar).
LineCut? cutLine(TextEditingValue value) {
  final sel = value.selection;
  if (!sel.isValid || !sel.isCollapsed) return null;
  final text = value.text;
  if (text.isEmpty) return null;
  final offset = sel.baseOffset.clamp(0, text.length);
  final start = _lineStart(text, offset);
  final nl = text.indexOf('\n', start);

  if (nl >= 0) {
    // Linha com quebra depois: sai [start, nl], a seguinte sobe para `start`.
    final end = nl + 1;
    final col = offset - start;
    final rest = text.substring(0, start) + text.substring(end);
    final nextLen = _contentLength(rest, start);
    return LineCut(
      text.substring(start, end),
      TextEditingValue(
        text: rest,
        selection: TextSelection.collapsed(
          offset: start + math.min(col, nextLen),
        ),
      ),
    );
  }

  // Última linha, sem quebra depois.
  final content = text.substring(start);
  if (start == 0) {
    // Arquivo de uma linha: o texto todo sai e não há quebra para levar.
    return LineCut(
      content,
      const TextEditingValue(selection: TextSelection.collapsed(offset: 0)),
    );
  }
  final breakLen = start >= 2 && text.codeUnitAt(start - 2) == 0x0D ? 2 : 1;
  final cutFrom = start - breakLen;
  final rest = text.substring(0, cutFrom);
  return LineCut(
    content + text.substring(cutFrom, start),
    TextEditingValue(
      text: rest,
      selection: TextSelection.collapsed(offset: rest.length),
    ),
  );
}

/// Colar de linha inteira (VS Code): com o cursor colapsado, [line] entra
/// **acima** da linha do cursor, no começo dela, e o cursor desce junto com a
/// própria linha (mesma coluna). Se [line] não termina em quebra (veio de um
/// arquivo de uma linha), ganha a quebra do documento: `\r\n` quando o texto
/// já usa, senão `\n`. Seleção não vazia devolve [value] intacto.
TextEditingValue pasteLineAbove(TextEditingValue value, String line) {
  final sel = value.selection;
  if (!sel.isValid || !sel.isCollapsed || line.isEmpty) return value;
  final text = value.text;
  final offset = sel.baseOffset.clamp(0, text.length);
  final start = _lineStart(text, offset);
  final insert = line.endsWith('\n')
      ? line
      : line + (text.contains('\r\n') ? '\r\n' : '\n');
  return TextEditingValue(
    text: text.substring(0, start) + insert + text.substring(start),
    selection: TextSelection.collapsed(offset: offset + insert.length),
  );
}

int _lineStart(String text, int offset) =>
    offset == 0 ? 0 : text.lastIndexOf('\n', offset - 1) + 1;

/// Tamanho do conteúdo da linha que começa em [start], sem a quebra (nem o
/// `\r` de um `\r\n`): é até onde o cursor pode ir nela.
int _contentLength(String text, int start) {
  final nl = text.indexOf('\n', start);
  var end = nl < 0 ? text.length : nl;
  if (end > start && text.codeUnitAt(end - 1) == 0x0D) end--;
  return end - start;
}
