import 'package:cockpit/app/cockpit/ui/widgets/http_pair_editing.dart';
import 'package:cockpit/app/cockpit/ui/widgets/http_script_completion.dart';
import 'package:flutter/services.dart';

/// Fecha delimitadores e pares JavaScript e indenta blocos de script HTTP.
/// A transformação passa pelo TextField para participar do undo/redo normal.
class HttpScriptEditingFormatter extends TextInputFormatter {
  const HttpScriptEditingFormatter() : memory = null;

  HttpScriptEditingFormatter.live() : memory = HttpAutocloseMemory();

  final HttpAutocloseMemory? memory;

  static final _openLine = RegExp(r'^[ \t]*[<>][ \t]*\{%$');
  static const _pairs = {
    '(': ')',
    '[': ']',
    '{': '}',
    "'": "'",
    '"': '"',
    '`': '`',
  };

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final retained = memory?.retain(oldValue, newValue);
    if (retained != null) return retained;
    final plain = newValue;
    oldValue = HttpPairEditing.beforeCommittedQuote(oldValue, newValue);
    if (!oldValue.selection.isValid ||
        !newValue.selection.isValid ||
        !newValue.selection.isCollapsed ||
        !newValue.composing.isCollapsed) {
      return newValue;
    }
    final offset = oldValue.selection.start;
    final end = oldValue.selection.end;
    final caret = newValue.selection.baseOffset;
    final context = HttpScriptCompletion.contextAt(oldValue.text, offset);
    if (context != null) {
      final paired = HttpPairEditing.pairs(
        oldValue,
        newValue,
        pairs: _pairs,
        context: context,
        allowSelection:
            HttpScriptCompletion.contextAt(oldValue.text, end) != null &&
            !oldValue.text.substring(offset, end).contains('%}'),
      );
      if (paired != null) {
        memory?.remember(plain, paired);
        return paired;
      }
    }

    if (!oldValue.selection.isCollapsed ||
        !HttpPairEditing.isInsertion(oldValue, newValue)) {
      return newValue;
    }

    final inserted = newValue.text[offset];
    final lineStart = offset == 0
        ? 0
        : newValue.text.lastIndexOf('\n', offset - 1) + 1;
    final before = newValue.text.substring(lineStart, caret);
    if (inserted == '%' &&
        _openLine.hasMatch(before) &&
        !newValue.text.substring(caret).startsWith('%}')) {
      return TextEditingValue(
        text: newValue.text.replaceRange(caret, caret, '%}'),
        selection: TextSelection.collapsed(offset: caret),
      );
    }

    if (context == null) return newValue;
    if (inserted != '\n' || context.quote != null || context.comment) {
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
    final closingBracket = trimmed.isEmpty
        ? null
        : _pairs[trimmed[trimmed.length - 1]];
    final closingOnLine =
        lineAfter.trimLeft().startsWith('%}') ||
        extra.isNotEmpty &&
            closingBracket != null &&
            lineAfter.trimLeft().startsWith(closingBracket);
    return HttpPairEditing.indent(
      newValue,
      baseIndent: baseIndent,
      increase: extra.isNotEmpty,
      splitClosing: closingOnLine,
    );
  }
}
