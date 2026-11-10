import 'package:flutter/services.dart';

/// Fecha `< {%`/`> {%` e indenta Enter dentro de um bloco de script HTTP.
/// A transformação passa pelo TextField para participar do undo/redo normal.
class HttpScriptEditingFormatter extends TextInputFormatter {
  const HttpScriptEditingFormatter();

  static final _openLine = RegExp(r'^[ \t]*[<>][ \t]*\{%$');
  static final _open = RegExp(r'^[ \t]*[<>][ \t]*\{%', multiLine: true);

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    if (!oldValue.selection.isValid ||
        !oldValue.selection.isCollapsed ||
        !newValue.selection.isValid ||
        !newValue.selection.isCollapsed ||
        newValue.composing.isValid) {
      return newValue;
    }
    final offset = oldValue.selection.baseOffset;
    final caret = newValue.selection.baseOffset;
    if (caret != offset + 1 ||
        newValue.text.length != oldValue.text.length + 1 ||
        newValue.text.substring(0, offset) !=
            oldValue.text.substring(0, offset) ||
        newValue.text.substring(caret) != oldValue.text.substring(offset)) {
      return newValue;
    }

    final inserted = newValue.text[offset];
    final lineStart = newValue.text.lastIndexOf('\n', offset - 1) + 1;
    final before = newValue.text.substring(lineStart, caret);
    if (inserted == '%' &&
        _openLine.hasMatch(before) &&
        !newValue.text.substring(caret).startsWith('%}')) {
      return TextEditingValue(
        text: newValue.text.replaceRange(caret, caret, '%}'),
        selection: TextSelection.collapsed(offset: caret),
      );
    }

    if (inserted != '\n' || !_insideScript(oldValue.text, offset)) {
      return newValue;
    }
    final oldLineStart = oldValue.text.lastIndexOf('\n', offset - 1) + 1;
    final lineBefore = oldValue.text.substring(oldLineStart, offset);
    final lineEnd = oldValue.text.indexOf('\n', offset);
    final lineAfter = oldValue.text.substring(
      offset,
      lineEnd < 0 ? oldValue.text.length : lineEnd,
    );
    final baseIndent = RegExp(r'^[ \t]*').firstMatch(lineBefore)!.group(0)!;
    final trimmed = lineBefore.trimRight();
    final extra =
        trimmed.endsWith('{%') ||
            trimmed.endsWith('{') ||
            trimmed.endsWith('(') ||
            trimmed.endsWith('[')
        ? '  '
        : '';
    final indent = '$baseIndent$extra';
    final closingOnLine = lineAfter.trimLeft().startsWith('%}');
    final suffix = closingOnLine ? '$indent\n$baseIndent' : indent;
    return TextEditingValue(
      text: newValue.text.replaceRange(caret, caret, suffix),
      selection: TextSelection.collapsed(offset: caret + indent.length),
    );
  }

  static bool _insideScript(String source, int offset) {
    var cursor = 0;
    var active = false;
    while (cursor < offset) {
      if (!active) {
        final matches = _open.allMatches(source, cursor).iterator;
        if (!matches.moveNext() || matches.current.start >= offset) break;
        active = true;
        cursor = matches.current.end;
      } else {
        final close = source.indexOf('%}', cursor);
        if (close < 0 || close >= offset) break;
        active = false;
        cursor = close + 2;
      }
    }
    return active;
  }
}
