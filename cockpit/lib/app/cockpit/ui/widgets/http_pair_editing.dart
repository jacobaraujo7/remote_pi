import 'package:flutter/services.dart';

typedef HttpPairContext = ({String? quote, bool comment, bool escaped});

/// O GTK confirma a aspa e, no mesmo ciclo, reenvia o texto sem o fechamento
/// que o formatador acabou de inserir. A segunda foto não é uma tecla de
/// apagar: ela só repete o caractere confirmado.
class HttpAutocloseMemory {
  TextEditingValue? _plain;
  TextEditingValue? _paired;

  TextEditingValue? retain(TextEditingValue oldValue, TextEditingValue value) {
    final plain = _plain;
    final paired = _paired;
    if (plain == null || paired == null) return null;
    if (oldValue != paired || value != plain) {
      _plain = null;
      _paired = null;
      return null;
    }
    final keys = HardwareKeyboard.instance;
    final removing =
        keys.isLogicalKeyPressed(LogicalKeyboardKey.backspace) ||
        keys.isLogicalKeyPressed(LogicalKeyboardKey.delete);
    if (removing) {
      _plain = null;
      _paired = null;
      return null;
    }
    return paired;
  }

  void remember(TextEditingValue plain, TextEditingValue paired) {
    if (paired == plain) return;
    _plain = plain;
    _paired = paired;
  }
}

/// Edições de um caractere compartilhadas pelos scripts e pelo body HTTP.
class HttpPairEditing {
  /// A composição pode exibir um sinal provisório (`´`, `¨`) e só depois
  /// confirmá-lo como aspa. Reconstrói o texto anterior a esse sinal para que
  /// o par seja calculado sobre a aspa já confirmada. Enquanto a composição
  /// segue aberta, o editor não fecha nada. No GTK, o cursor pode ficar no
  /// início da pré-edição até o commit.
  static TextEditingValue beforeCommittedQuote(
    TextEditingValue oldValue,
    TextEditingValue value,
  ) {
    final range = oldValue.composing;
    if (!range.isValid ||
        range.end != range.start + 1 ||
        range.end > oldValue.text.length ||
        !value.composing.isCollapsed ||
        !oldValue.selection.isValid ||
        !oldValue.selection.isCollapsed ||
        oldValue.selection.start < range.start ||
        oldValue.selection.start > range.end ||
        !value.selection.isValid ||
        !value.selection.isCollapsed ||
        value.selection.start != range.start + 1 ||
        value.selection.start > value.text.length ||
        !const ["'", '"', '`'].contains(value.text[range.start]) ||
        oldValue.text.substring(0, range.start) !=
            value.text.substring(0, range.start) ||
        oldValue.text.substring(range.end) !=
            value.text.substring(range.start + 1)) {
      return oldValue;
    }
    return TextEditingValue(
      text: oldValue.text.replaceRange(range.start, range.end, ''),
      selection: TextSelection.collapsed(offset: range.start),
    );
  }

  static bool isInsertion(TextEditingValue oldValue, TextEditingValue value) {
    if (!oldValue.selection.isValid ||
        !oldValue.composing.isCollapsed ||
        !value.selection.isValid ||
        !value.selection.isCollapsed ||
        !value.composing.isCollapsed) {
      return false;
    }
    final start = oldValue.selection.start;
    final end = oldValue.selection.end;
    final caret = value.selection.start;
    return caret == start + 1 &&
        value.text.length == oldValue.text.length - (end - start) + 1 &&
        value.text.substring(0, start) == oldValue.text.substring(0, start) &&
        value.text.substring(caret) == oldValue.text.substring(end);
  }

  static TextEditingValue? pairs(
    TextEditingValue oldValue,
    TextEditingValue value, {
    required Map<String, String> pairs,
    required HttpPairContext context,
    bool allowSelection = true,
  }) {
    if (!oldValue.selection.isValid ||
        !oldValue.composing.isCollapsed ||
        !value.selection.isValid ||
        !value.selection.isCollapsed ||
        !value.composing.isCollapsed) {
      return null;
    }
    final start = oldValue.selection.start;
    final end = oldValue.selection.end;
    final caret = value.selection.start;
    final inCode = context.quote == null && !context.comment;
    if (start == end &&
        start > 0 &&
        start < oldValue.text.length &&
        caret == start - 1 &&
        value.text == oldValue.text.replaceRange(start - 1, start, '') &&
        pairs[oldValue.text[start - 1]] == oldValue.text[start] &&
        (inCode ||
            !context.comment &&
                !context.escaped &&
                context.quote == oldValue.text[start])) {
      return value.copyWith(
        text: value.text.replaceRange(caret, caret + 1, ''),
      );
    }
    if (!isInsertion(oldValue, value)) return null;
    final inserted = value.text[start];
    final closing = pairs[inserted];
    if (start != end) {
      if (!inCode || closing == null || !allowSelection) return null;
      final selected = oldValue.selection.textInside(oldValue.text);
      return TextEditingValue(
        text: value.text.replaceRange(caret, caret, '$selected$closing'),
        selection: TextSelection(
          baseOffset: caret,
          extentOffset: caret + selected.length,
        ),
      );
    }
    final existing = start < oldValue.text.length ? oldValue.text[start] : '';
    final closesQuote = context.quote == inserted && !context.escaped;
    if (!context.comment &&
        existing == inserted &&
        (closesQuote ||
            inCode && pairs.values.contains(inserted) && closing == null)) {
      return TextEditingValue(
        text: oldValue.text,
        selection: TextSelection.collapsed(offset: caret),
      );
    }
    final nextAllowsPair =
        existing.isEmpty || RegExp(r'[\s)\]}>,;:%]').hasMatch(existing);
    if (inCode && closing != null && nextAllowsPair) {
      return TextEditingValue(
        text: value.text.replaceRange(caret, caret, closing),
        selection: TextSelection.collapsed(offset: caret),
      );
    }
    return null;
  }

  static TextEditingValue indent(
    TextEditingValue value, {
    required String baseIndent,
    required bool increase,
    required bool splitClosing,
  }) {
    final caret = value.selection.start;
    final indent = '$baseIndent${increase ? '  ' : ''}';
    final suffix = splitClosing ? '$indent\n$baseIndent' : indent;
    final existingIndent = splitClosing
        ? RegExp(
            r'^[ \t]*',
          ).firstMatch(value.text.substring(caret))!.group(0)!.length
        : 0;
    return TextEditingValue(
      text: value.text.replaceRange(caret, caret + existingIndent, suffix),
      selection: TextSelection.collapsed(offset: caret + indent.length),
    );
  }
}
