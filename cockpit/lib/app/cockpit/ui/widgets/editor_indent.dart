import 'dart:math' as math;

import 'package:flutter/services.dart'
    show TextEditingValue, TextRange, TextSelection;

/// Unidade de indentação de um arquivo: tab real ou N espaços.
class IndentUnit {
  const IndentUnit.spaces(this.width) : useTabs = false;
  const IndentUnit.tabs({this.width = 4}) : useTabs = true;

  /// `true` = o arquivo indenta com `\t`.
  final bool useTabs;

  /// Largura do tab stop em colunas (com tabs, só orienta o cálculo de coluna).
  final int width;

  /// Texto inserido para subir um nível no início de linha.
  String get text => useTabs ? '\t' : ' ' * width;

  @override
  bool operator ==(Object other) =>
      other is IndentUnit && other.useTabs == useTabs && other.width == width;

  @override
  int get hashCode => Object.hash(useTabs, width);

  @override
  String toString() =>
      useTabs ? 'IndentUnit.tabs($width)' : 'IndentUnit.spaces($width)';
}

const _twoSpaceExtensions = {
  'dart',
  'yaml',
  'yml',
  'json',
  'js',
  'ts',
  'tsx',
  'jsx',
  'html',
  'css',
  'md',
};

/// Largura padrão de indentação pela extensão do arquivo (2 para linguagens de
/// convenção "2 espaços", 4 para o resto).
int fallbackIndentWidth(String? path) {
  if (path == null) return 4;
  final slash = path.lastIndexOf('/');
  final name = slash < 0 ? path : path.substring(slash + 1);
  final dot = name.lastIndexOf('.');
  if (dot < 0) return 4;
  final ext = name.substring(dot + 1).toLowerCase();
  return _twoSpaceExtensions.contains(ext) ? 2 : 4;
}

/// Infere a unidade de indentação a partir do conteúdo.
///
/// Se alguma linha indentada começa com `\t`, o arquivo usa tabs. Senão a
/// largura é o menor delta positivo de indentação entre linhas não vazias
/// consecutivas, olhando as primeiras [sampleLines] linhas indentadas. Sem
/// evidência, cai no padrão por extensão ([fallbackIndentWidth]).
IndentUnit detectIndentUnit(
  String text, {
  String? path,
  int sampleLines = 200,
}) {
  var sampled = 0;
  var previousIndent = 0;
  int? minDelta;
  var start = 0;
  final length = text.length;
  while (start <= length && sampled < sampleLines) {
    var end = text.indexOf('\n', start);
    if (end < 0) end = length;
    final line = text.substring(start, end);
    start = end + 1;
    if (line.trim().isEmpty) {
      if (end == length) break;
      continue;
    }
    var indent = 0;
    while (indent < line.length && line.codeUnitAt(indent) == 0x20) {
      indent++;
    }
    if (indent < line.length && line.codeUnitAt(indent) == 0x09) {
      return IndentUnit.tabs(width: fallbackIndentWidth(path));
    }
    if (indent > 0) sampled++;
    final delta = (indent - previousIndent).abs();
    if (delta > 0 && (minDelta == null || delta < minDelta)) minDelta = delta;
    previousIndent = indent;
    if (end == length) break;
  }
  return IndentUnit.spaces(minDelta ?? fallbackIndentWidth(path));
}

int _lineStartOf(String text, int offset) {
  if (offset <= 0) return 0;
  final nl = text.lastIndexOf('\n', offset - 1);
  return nl < 0 ? 0 : nl + 1;
}

/// Inícios das linhas cobertas pela seleção `[start, end]`. Uma seleção que
/// termina na coluna 0 de uma linha posterior não inclui essa linha (VS Code).
List<int> _selectedLineStarts(String text, int start, int end) {
  final starts = <int>[_lineStartOf(text, start)];
  var pos = starts.first;
  while (true) {
    final nl = text.indexOf('\n', pos);
    if (nl < 0 || nl + 1 >= end) break;
    if (nl + 1 == end && end > start) break;
    pos = nl + 1;
    starts.add(pos);
  }
  return starts;
}

/// Aplica Tab: com seleção numa única linha insere espaços até o próximo tab
/// stop (ou `\t`); com seleção multilinha, indenta cada linha coberta e mantém
/// a seleção cobrindo as mesmas linhas.
TextEditingValue applyIndent(TextEditingValue value, IndentUnit unit) {
  final text = value.text;
  final sel = value.selection;
  if (!sel.isValid) return value;
  final start = sel.start;
  final end = sel.end;
  final multiLine =
      !sel.isCollapsed && text.substring(start, end).contains('\n');

  if (!multiLine) {
    final String insert;
    if (unit.useTabs) {
      insert = '\t';
    } else {
      final column = start - _lineStartOf(text, start);
      insert = ' ' * (unit.width - column % unit.width);
    }
    final newText = text.replaceRange(start, end, insert);
    return value.copyWith(
      text: newText,
      selection: TextSelection.collapsed(offset: start + insert.length),
      composing: TextRange.empty,
    );
  }

  final unitText = unit.text;
  final starts = _selectedLineStarts(text, start, end);
  final buffer = StringBuffer();
  var cursor = 0;
  for (final lineStart in starts) {
    buffer.write(text.substring(cursor, lineStart));
    buffer.write(unitText);
    cursor = lineStart;
  }
  buffer.write(text.substring(cursor));
  final shift = unitText.length;
  final newStart = start == starts.first ? start : start + shift;
  final newEnd = end + shift * starts.length;
  return value.copyWith(
    text: buffer.toString(),
    selection: _rebuild(sel, newStart, newEnd),
    composing: TextRange.empty,
  );
}

/// Aplica Shift+Tab: remove até uma unidade de indentação do início de cada
/// linha coberta pela seleção (ou da linha do cursor), preservando a seleção
/// sobre as mesmas linhas.
TextEditingValue applyOutdent(TextEditingValue value, IndentUnit unit) {
  final text = value.text;
  final sel = value.selection;
  if (!sel.isValid) return value;
  final start = sel.start;
  final end = sel.end;
  final starts = _selectedLineStarts(text, start, end);
  final buffer = StringBuffer();
  var cursor = 0;
  var newStart = start;
  var newEnd = end;
  var changed = false;
  for (final lineStart in starts) {
    buffer.write(text.substring(cursor, lineStart));
    final removed = _leadingIndentToRemove(text, lineStart, unit);
    cursor = lineStart + removed;
    if (removed == 0) continue;
    changed = true;
    // Deslocamento de cada extremo da seleção: se o extremo está dentro do
    // trecho removido, gruda no início da linha.
    if (start > lineStart) {
      newStart -= math.min(removed, start - lineStart);
    }
    if (end > lineStart) {
      newEnd -= math.min(removed, end - lineStart);
    }
  }
  if (!changed) return value;
  buffer.write(text.substring(cursor));
  return value.copyWith(
    text: buffer.toString(),
    selection: _rebuild(sel, newStart, newEnd),
    composing: TextRange.empty,
  );
}

int _leadingIndentToRemove(String text, int lineStart, IndentUnit unit) {
  if (lineStart >= text.length) return 0;
  if (text.codeUnitAt(lineStart) == 0x09) return 1;
  var spaces = 0;
  while (lineStart + spaces < text.length &&
      spaces < unit.width &&
      text.codeUnitAt(lineStart + spaces) == 0x20) {
    spaces++;
  }
  return spaces;
}

TextSelection _rebuild(TextSelection sel, int start, int end) {
  final forward = sel.baseOffset <= sel.extentOffset;
  return TextSelection(
    baseOffset: forward ? start : end,
    extentOffset: forward ? end : start,
    affinity: sel.affinity,
    isDirectional: sel.isDirectional,
  );
}
