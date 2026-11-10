import 'package:flutter/services.dart';

/// Par de chaves de variável sob o cursor, com offsets UTF-16 do conteúdo.
class HttpVariableSlot {
  const HttpVariableSlot(this.start, this.end, this.prefix);

  final int start;
  final int end;
  final String prefix;
}

class HttpVariableCompletion {
  static final _placeholder = RegExp(r'\{\{([^{}\n]*)\}\}');

  static HttpVariableSlot? slotAt(String text, int caret) {
    if (caret < 0 || caret > text.length) return null;
    for (final match in _placeholder.allMatches(text)) {
      final start = match.start + 2;
      final end = match.end - 2;
      if (caret >= start && caret <= end) {
        return HttpVariableSlot(
          start,
          end,
          text.substring(start, caret).trimLeft(),
        );
      }
    }
    return null;
  }

  static TextEditingValue complete(
    TextEditingValue value,
    HttpVariableSlot slot,
    String name,
  ) {
    final next = value.text.replaceRange(slot.start, slot.end, name);
    return TextEditingValue(
      text: next,
      selection: TextSelection.collapsed(offset: slot.start + name.length + 2),
    );
  }

  static TextEditingValue insertAt(
    TextEditingValue value,
    int offset,
    String name,
  ) {
    final token = '{{$name}}';
    return TextEditingValue(
      text: value.text.replaceRange(offset, offset, token),
      selection: TextSelection.collapsed(offset: offset + token.length),
    );
  }
}

/// Quando a segunda `{` é digitada, insere `}}` e deixa o caret no meio.
/// Roda no pipeline do TextField para manter a edição no undo/redo normal.
class HttpVariableBraceFormatter extends TextInputFormatter {
  const HttpVariableBraceFormatter();

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    if (!newValue.selection.isValid ||
        !newValue.selection.isCollapsed ||
        newValue.composing.isValid) {
      return newValue;
    }
    final caret = newValue.selection.baseOffset;
    final delta = newValue.text.length - oldValue.text.length;
    if (delta != 1 && delta != 2) return newValue;
    final insertedStart = caret - delta;
    if (insertedStart < 0 || caret > newValue.text.length) return newValue;
    final inserted = newValue.text.substring(insertedStart, caret);
    final opens =
        inserted == '{{' ||
        (inserted == '{' &&
            insertedStart > 0 &&
            newValue.text[insertedStart - 1] == '{' &&
            (insertedStart < 2 || newValue.text[insertedStart - 2] != '{'));
    if (!opens || newValue.text.substring(caret).startsWith('}}')) {
      return newValue;
    }
    return TextEditingValue(
      text: newValue.text.replaceRange(caret, caret, '}}'),
      selection: TextSelection.collapsed(offset: caret),
    );
  }
}
