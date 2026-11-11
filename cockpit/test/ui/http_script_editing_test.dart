import 'package:cockpit/app/cockpit/ui/widgets/code_editor.dart';
import 'package:cockpit/app/cockpit/ui/widgets/http_script_editing.dart';
import 'package:cockpit/app/cockpit/ui/widgets/http_variable_completion.dart';
import 'package:cockpit/app/core/ui/themes/themes.dart';
import 'package:cockpit/app/core/ui/widgets/code_editing_controller.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';

TextEditingValue _value(String text, int caret) => TextEditingValue(
  text: text,
  selection: TextSelection.collapsed(offset: caret),
);

void main() {
  const formatter = HttpScriptEditingFormatter();

  TextEditingValue type(TextEditingValue value, String character) {
    final next = TextEditingValue(
      text: value.text.replaceRange(
        value.selection.start,
        value.selection.end,
        character,
      ),
      selection: TextSelection.collapsed(
        offset: value.selection.start + character.length,
      ),
    );
    final variables = const HttpVariableBraceFormatter().formatEditUpdate(
      value,
      next,
    );
    return formatter.formatEditUpdate(value, variables);
  }

  test(
    'pares JavaScript fecham nos dois tipos de script e pulam o fechamento',
    () {
      for (final marker in ['<', '>']) {
        for (final pair in ['()', '[]', '{}', "''", '""', '``']) {
          final before = '$marker {%\n  ';
          final old = _value('$before\n%}', before.length);
          final result = type(old, pair[0]);
          expect(result.text, '$before$pair\n%}');
          expect(result.selection.baseOffset, before.length + 1);
          final closed = type(result, pair[1]);
          expect(closed.text, result.text);
          expect(closed.selection.baseOffset, before.length + 2);
        }
      }
    },
  );

  test('Backspace remove o par vazio e seleção pode ser envolvida', () {
    for (final pair in ['()', '[]', '{}', "''", '""', '``']) {
      const before = '> {%\n  ';
      final old = _value('$before$pair\n%}', before.length + 1);
      final result = formatter.formatEditUpdate(
        old,
        _value('$before${pair[1]}\n%}', before.length),
      );
      expect(result.text, '$before\n%}');
      expect(result.selection.baseOffset, before.length);

      final selected = TextEditingValue(
        text: '${before}name\n%}',
        selection: TextSelection(
          baseOffset: before.length,
          extentOffset: before.length + 4,
        ),
      );
      final wrapped = type(selected, pair[0]);
      expect(wrapped.text, '$before${pair[0]}name${pair[1]}\n%}');
      expect(wrapped.selection.textInside(wrapped.text), 'name');
    }
  });

  test('Enter entre pares cria linha indentada e fechamento alinhado', () {
    for (final pair in ['{}', '[]', '()']) {
      final before = '> {%\n  ${pair[0]}';
      final result = type(_value('$before${pair[1]}\n%}', before.length), '\n');
      expect(result.text, '$before\n    \n  ${pair[1]}\n%}');
      expect(result.selection.baseOffset, before.length + 5);
    }
  });

  test('não altera strings, escapes, comentários, headers ou body', () {
    for (final before in [
      'GET https://example.test/',
      'POST https://example.test/\n\n',
      '> {%\n// comment ',
      '> {%\n/* comment ',
      '> {%\nconst text = "hello ',
      "> {%\nconst text = 'hello ",
      '> {%\nconst text = `hello ',
      '> {%\n%}\nHeader: ',
    ]) {
      for (final character in ['{', '[', '(', '"', "'", '`']) {
        final result = type(_value(before, before.length), character);
        expect(result.text, '$before$character');
      }
    }
    const escaped = '> {%\nconst text = "hello \\';
    final result = type(_value('$escaped"\n%}', escaped.length), '"');
    expect(result.text, '$escaped""\n%}');
  });

  test('pares aninhados não ativam fechamento de variável HTTP', () {
    const before = '> {%\n';
    final first = type(_value(before, before.length), '{');
    final second = type(first, '{');
    expect(second.text, '$before{{}}');
    expect(second.selection.baseOffset, before.length + 2);
  });

  test('paste e composição ficam intactos', () {
    final old = _value('> {%\n', 5);
    final pasted = _value('> {%\nconst x = {', 16);
    expect(formatter.formatEditUpdate(old, pasted), pasted);
    final composing = _value(
      '> {%\n"',
      6,
    ).copyWith(composing: const TextRange(start: 5, end: 6));
    expect(formatter.formatEditUpdate(old, composing), composing);
  });

  test('fecha blocos pre e post sem repetir um fechamento existente', () {
    for (final marker in ['<', '>']) {
      final old = _value('$marker {', 3);
      final typed = _value('$marker {%', 4);
      final result = formatter.formatEditUpdate(old, typed);
      expect(result.text, '$marker {%%}');
      expect(result.selection.baseOffset, 4);
      expect(
        formatter
            .formatEditUpdate(
              _value('$marker {%}', 3),
              _value('$marker {%%}', 4),
            )
            .text,
        '$marker {%%}',
      );
    }
  });

  test('Enter abre linha indentada e mantém fechamento em linha própria', () {
    final old = _value('> {%%}', 4);
    final typed = _value('> {%\n%}', 5);
    final result = formatter.formatEditUpdate(old, typed);
    expect(result.text, '> {%\n  \n%}');
    expect(result.selection.baseOffset, 7);
  });

  test(
    'Enter preserva indentação dentro do script e fora dele não interfere',
    () {
      const before = '> {%\n  client.global.set(';
      final old = _value(before, before.length);
      final typed = _value('$before\n', before.length + 1);
      final result = formatter.formatEditUpdate(old, typed);
      expect(result.text, '$before\n    ');
      expect(result.selection.baseOffset, result.text.length);

      final outside = _value('GET https://example.com\n', 24);
      expect(
        formatter
            .formatEditUpdate(_value('GET https://example.com', 23), outside)
            .text,
        outside.text,
      );
    },
  );

  testWidgets('editor HTTP aplica fechamento ao digitar', (tester) async {
    final controller = CodeEditingController(text: '< {', language: 'http')
      ..selection = const TextSelection.collapsed(offset: 3);
    final focus = FocusNode();
    addTearDown(() {
      controller.dispose();
      focus.dispose();
    });
    await tester.pumpWidget(
      ShadcnApp(
        theme: buildTheme(brightness: Brightness.dark),
        home: Scaffold(
          child: SizedBox(
            width: 400,
            height: 200,
            child: CodeEditor(
              controller: controller,
              focusNode: focus,
              autoCloseHttpVariables: true,
              autoEditHttpScripts: true,
            ),
          ),
        ),
      ),
    );
    focus.requestFocus();
    await tester.pump();
    await tester.enterText(find.byType(EditableText), '< {%');
    expect(controller.text, '< {%%}');
    expect(controller.selection.baseOffset, 4);

    tester.testTextInput.updateEditingValue(_value('< {%\n%}', 5));
    await tester.pump();
    expect(controller.text, '< {%\n  \n%}');
    tester.testTextInput.updateEditingValue(_value('< {%\n  {\n%}', 8));
    await tester.pump();
    expect(controller.text, '< {%\n  {}\n%}');
    expect(controller.selection.baseOffset, 8);
    tester.testTextInput.updateEditingValue(_value('< {%\n  {{}\n%}', 9));
    await tester.pump();
    expect(controller.text, '< {%\n  {{}}\n%}');
    expect(controller.selection.baseOffset, 9);
  });
}
