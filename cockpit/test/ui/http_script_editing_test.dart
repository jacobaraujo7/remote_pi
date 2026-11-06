import 'package:cockpit/app/cockpit/ui/widgets/code_editor.dart';
import 'package:cockpit/app/cockpit/ui/widgets/http_script_editing.dart';
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
  });
}
