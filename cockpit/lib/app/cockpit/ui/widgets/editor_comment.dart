import 'dart:math' as math;

import 'package:flutter/services.dart';

/// Sintaxe de comentário de uma linguagem, no que interessa ao editor: o
/// token de linha (`//`, `#`, `--`) ou, quando a linguagem só tem comentário
/// de bloco (HTML, CSS), o par que embrulha a linha.
class CommentSyntax {
  const CommentSyntax.line(this.line) : blockStart = null, blockEnd = null;
  const CommentSyntax.block(this.blockStart, this.blockEnd) : line = null;

  final String? line;
  final String? blockStart;
  final String? blockEnd;

  bool get isBlock => line == null;
}

/// Token por **id de linguagem** — que no `FileViewText` é a extensão do
/// arquivo (`dart`, `py`, `yml`...) e nos editores embutidos é o id fixo
/// (`sql` no `.dbq`, `http` na tab de request). Linguagem desconhecida devolve
/// `null` e o atalho não faz nada, em vez de chutar um token errado.
CommentSyntax? commentSyntaxFor(String? language) {
  if (language == null || language.isEmpty) return null;
  final id = language.toLowerCase();
  return _byLanguage[id];
}

const _slashes = CommentSyntax.line('//');
const _hash = CommentSyntax.line('#');
const _dashes = CommentSyntax.line('--');
const _html = CommentSyntax.block('<!--', '-->');
const _cBlock = CommentSyntax.block('/*', '*/');

const Map<String, CommentSyntax> _byLanguage = {
  // `//`
  'dart': _slashes, 'js': _slashes, 'mjs': _slashes, 'cjs': _slashes,
  'jsx': _slashes, 'ts': _slashes, 'tsx': _slashes, 'mts': _slashes,
  'cts': _slashes, 'typescript': _slashes, 'javascript': _slashes,
  'java': _slashes, 'kt': _slashes, 'kts': _slashes, 'scala': _slashes,
  'swift': _slashes, 'go': _slashes, 'rs': _slashes, 'rust': _slashes,
  'c': _slashes, 'h': _slashes, 'cc': _slashes, 'cpp': _slashes,
  'hpp': _slashes, 'cxx': _slashes, 'm': _slashes, 'mm': _slashes,
  'cs': _slashes, 'csharp': _slashes, 'php': _slashes, 'zig': _slashes,
  'jsonc': _slashes, 'json5': _slashes, 'proto': _slashes, 'gradle': _slashes,
  'groovy': _slashes, 'glsl': _slashes, 'metal': _slashes,
  // `#`
  'py': _hash, 'pyi': _hash, 'python': _hash, 'rb': _hash, 'sh': _hash,
  'bash': _hash, 'zsh': _hash, 'fish': _hash, 'yaml': _hash, 'yml': _hash,
  'toml': _hash, 'ini': _hash, 'cfg': _hash, 'conf': _hash, 'env': _hash,
  'dockerfile': _hash, 'makefile': _hash, 'mk': _hash, 'r': _hash,
  'pl': _hash, 'pm': _hash, 'ps1': _hash, 'psm1': _hash, 'nix': _hash,
  'tf': _hash, 'hcl': _hash, 'cmake': _hash, 'gitignore': _hash,
  'properties': _hash, 'http': _hash, 'rest': _hash, 'ckp': _hash,
  // `--`
  'sql': _dashes, 'dbq': _dashes, 'lua': _dashes, 'hs': _dashes,
  'elm': _dashes, 'ada': _dashes,
  // outros tokens de linha
  'vim': CommentSyntax.line('"'), 'tex': CommentSyntax.line('%'),
  'bat': CommentSyntax.line('REM'), 'cmd': CommentSyntax.line('REM'),
  'lisp': CommentSyntax.line(';'), 'clj': CommentSyntax.line(';'),
  'el': CommentSyntax.line(';'), 'asm': CommentSyntax.line(';'),
  'erl': CommentSyntax.line('%'), 'ex': _hash, 'exs': _hash,
  // só bloco
  'html': _html, 'htm': _html, 'xml': _html, 'svg': _html, 'vue': _html,
  'svelte': _html, 'md': _html, 'markdown': _html, 'mdx': _html,
  'panel': _html, 'xhtml': _html, 'plist': _html,
  'css': _cBlock, 'scss': _cBlock, 'less': _cBlock,
};

int _lineStartOf(String text, int offset) {
  if (offset <= 0) return 0;
  final nl = text.lastIndexOf('\n', offset - 1);
  return nl < 0 ? 0 : nl + 1;
}

int _lineEndOf(String text, int lineStart) {
  final nl = text.indexOf('\n', lineStart);
  return nl < 0 ? text.length : nl;
}

/// Mesma regra do indent (VS Code): seleção que termina na coluna 0 de uma
/// linha posterior não inclui essa linha.
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

int _indentLen(String line) {
  var i = 0;
  while (i < line.length &&
      (line.codeUnitAt(i) == 0x20 || line.codeUnitAt(i) == 0x09)) {
    i++;
  }
  return i;
}

bool _isCommented(String line, CommentSyntax syntax) {
  final body = line.substring(_indentLen(line));
  if (syntax.isBlock) {
    return body.startsWith(syntax.blockStart!) &&
        body.trimRight().endsWith(syntax.blockEnd!);
  }
  return body.startsWith(syntax.line!);
}

/// `Cmd+K Cmd+C` do VS Code: comenta cada linha coberta pela seleção. O token
/// vai na **menor indentação** entre as linhas não vazias (fica alinhado em
/// bloco, não colado no texto de cada linha), com um espaço depois. Linha
/// vazia é pulada. Linha já comentada ganha outra camada, como no VS Code.
TextEditingValue addLineComment(TextEditingValue value, CommentSyntax syntax) =>
    _rewriteLines(value, syntax, mode: _Mode.add);

/// `Cmd+K Cmd+U`: remove uma camada de comentário das linhas que têm.
TextEditingValue removeLineComment(
  TextEditingValue value,
  CommentSyntax syntax,
) => _rewriteLines(value, syntax, mode: _Mode.remove);

/// `Cmd+/`: se TODAS as linhas não vazias estão comentadas, descomenta;
/// senão comenta todas.
TextEditingValue toggleLineComment(
  TextEditingValue value,
  CommentSyntax syntax,
) {
  final text = value.text;
  final sel = value.selection;
  if (!sel.isValid) return value;
  final starts = _selectedLineStarts(text, sel.start, sel.end);
  var sawContent = false;
  var allCommented = true;
  for (final s in starts) {
    final line = text.substring(s, _lineEndOf(text, s));
    if (line.trim().isEmpty) continue;
    sawContent = true;
    if (!_isCommented(line, syntax)) allCommented = false;
  }
  if (!sawContent) {
    // Só linhas vazias: comenta a linha do cursor mesmo assim (VS Code).
    return _rewriteLines(value, syntax, mode: _Mode.addEvenEmpty);
  }
  return allCommented
      ? removeLineComment(value, syntax)
      : addLineComment(value, syntax);
}

enum _Mode { add, addEvenEmpty, remove }

TextEditingValue _rewriteLines(
  TextEditingValue value,
  CommentSyntax syntax, {
  required _Mode mode,
}) {
  final text = value.text;
  final sel = value.selection;
  if (!sel.isValid) return value;
  final start = sel.start;
  final end = sel.end;
  final starts = _selectedLineStarts(text, start, end);

  // Indentação mínima das linhas com conteúdo (pro token ficar alinhado).
  var minIndent = -1;
  for (final s in starts) {
    final line = text.substring(s, _lineEndOf(text, s));
    if (line.trim().isEmpty) continue;
    final ind = _indentLen(line);
    minIndent = minIndent < 0 ? ind : math.min(minIndent, ind);
  }
  if (minIndent < 0) minIndent = 0;

  final buffer = StringBuffer();
  var cursor = 0;
  var newStart = start;
  var newEnd = end;
  var changed = false;

  // Desloca os extremos da seleção que estão depois de [at] por [delta].
  void shift(int at, int delta) {
    if (start > at) newStart += delta;
    if (end > at || (end == at && delta > 0 && end > start)) newEnd += delta;
  }

  for (final s in starts) {
    final e = _lineEndOf(text, s);
    final line = text.substring(s, e);
    buffer.write(text.substring(cursor, s));
    cursor = e;
    switch (mode) {
      case _Mode.add:
      case _Mode.addEvenEmpty:
        if (mode == _Mode.add && line.trim().isEmpty) {
          buffer.write(line);
          continue;
        }
        final at = math.min(minIndent, line.length);
        if (syntax.isBlock) {
          final open = '${syntax.blockStart!} ';
          final close = ' ${syntax.blockEnd!}';
          buffer
            ..write(line.substring(0, at))
            ..write(open)
            ..write(line.substring(at))
            ..write(close);
          shift(s + at, open.length);
          // O fecho entra no fim da linha: só mexe num extremo que esteja
          // além dele (nunca, dentro da mesma linha) — nada a deslocar.
        } else {
          final token = '${syntax.line!} ';
          buffer
            ..write(line.substring(0, at))
            ..write(token)
            ..write(line.substring(at));
          shift(s + at, token.length);
        }
        changed = true;
      case _Mode.remove:
        if (!_isCommented(line, syntax)) {
          buffer.write(line);
          continue;
        }
        final ind = _indentLen(line);
        if (syntax.isBlock) {
          var body = line.substring(ind);
          final open = syntax.blockStart!;
          var openLen = open.length;
          if (body.startsWith('$open ')) openLen++;
          body = body.substring(openLen);
          final trimmedEnd = body.trimRight();
          final close = syntax.blockEnd!;
          var closeLen = close.length;
          var core = trimmedEnd.substring(0, trimmedEnd.length - closeLen);
          if (core.endsWith(' ')) {
            core = core.substring(0, core.length - 1);
            closeLen++;
          }
          buffer
            ..write(line.substring(0, ind))
            ..write(core)
            ..write(body.substring(trimmedEnd.length));
          shift(s + ind, -openLen);
          shift(s + ind + openLen + core.length, -closeLen);
        } else {
          final token = syntax.line!;
          var removed = token.length;
          if (line.length > ind + removed &&
              line.codeUnitAt(ind + removed) == 0x20) {
            removed++;
          }
          buffer
            ..write(line.substring(0, ind))
            ..write(line.substring(ind + removed));
          // Extremo dentro do trecho removido gruda no início do token.
          if (start > s + ind) {
            newStart -= math.min(removed, start - (s + ind));
          }
          if (end > s + ind) newEnd -= math.min(removed, end - (s + ind));
        }
        changed = true;
    }
  }
  if (!changed) return value;
  buffer.write(text.substring(cursor));
  final out = buffer.toString();
  newStart = newStart.clamp(0, out.length);
  newEnd = newEnd.clamp(0, out.length);
  final forward = sel.baseOffset <= sel.extentOffset;
  return value.copyWith(
    text: out,
    selection: TextSelection(
      baseOffset: forward ? newStart : newEnd,
      extentOffset: forward ? newEnd : newStart,
      affinity: sel.affinity,
      isDirectional: sel.isDirectional,
    ),
    composing: TextRange.empty,
  );
}
