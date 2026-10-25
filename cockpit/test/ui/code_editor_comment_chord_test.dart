import 'package:cockpit/app/cockpit/ui/widgets/code_editor.dart';
import 'package:cockpit/app/core/ui/themes/themes.dart';
import 'package:cockpit/app/core/ui/widgets/code_editing_controller.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';

void main() {
  Widget harness(CodeEditingController ctrl, FocusNode focus) {
    return ShadcnApp(
      theme: buildTheme(brightness: Brightness.dark),
      home: Scaffold(
        child: SizedBox(
          width: 300,
          height: 200,
          child: CodeEditor(
            controller: ctrl,
            focusNode: focus,
            filePath: 'main.dart',
          ),
        ),
      ),
    );
  }

  // O editor lê Meta no macOS e Control nas demais; o teste roda em qualquer
  // host, então usa o modificador que o host de teste enxerga.
  final mod = defaultTargetPlatform == TargetPlatform.macOS
      ? LogicalKeyboardKey.metaLeft
      : LogicalKeyboardKey.controlLeft;

  Future<void> chord(WidgetTester tester, LogicalKeyboardKey second) async {
    await tester.sendKeyDownEvent(mod);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.keyK);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.keyK);
    await tester.sendKeyDownEvent(second);
    await tester.sendKeyUpEvent(second);
    await tester.sendKeyUpEvent(mod);
    await tester.pump();
  }

  Future<(CodeEditingController, FocusNode)> mount(
    WidgetTester tester,
    String text,
    String language,
    TextSelection sel,
  ) async {
    final ctrl = CodeEditingController(text: text, language: language);
    final focus = FocusNode();
    addTearDown(() {
      ctrl.dispose();
      focus.dispose();
    });
    await tester.pumpWidget(harness(ctrl, focus));
    focus.requestFocus();
    await tester.pump();
    ctrl.selection = sel;
    await tester.pump();
    return (ctrl, focus);
  }

  testWidgets('Cmd+K Cmd+C comenta as linhas selecionadas', (tester) async {
    final (ctrl, _) = await mount(
      tester,
      'a\nb\nc',
      'dart',
      const TextSelection(baseOffset: 0, extentOffset: 3),
    );
    await chord(tester, LogicalKeyboardKey.keyC);
    expect(ctrl.text, '// a\n// b\nc');
  });

  testWidgets('Cmd+K Cmd+U descomenta', (tester) async {
    final (ctrl, _) = await mount(
      tester,
      '-- select 1',
      'sql',
      const TextSelection.collapsed(offset: 5),
    );
    await chord(tester, LogicalKeyboardKey.keyU);
    expect(ctrl.text, 'select 1');
  });

  testWidgets('Cmd+/ alterna', (tester) async {
    final (ctrl, _) = await mount(
      tester,
      'x = 1',
      'py',
      const TextSelection.collapsed(offset: 0),
    );
    await tester.sendKeyDownEvent(mod);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.slash);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.slash);
    await tester.sendKeyUpEvent(mod);
    await tester.pump();
    expect(ctrl.text, '# x = 1');
    await tester.sendKeyDownEvent(mod);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.slash);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.slash);
    await tester.sendKeyUpEvent(mod);
    await tester.pump();
    expect(ctrl.text, 'x = 1');
  });

  testWidgets('linguagem sem sintaxe conhecida não muda nada', (tester) async {
    final (ctrl, _) = await mount(
      tester,
      'data',
      'xyz',
      const TextSelection.collapsed(offset: 0),
    );
    await chord(tester, LogicalKeyboardKey.keyC);
    expect(ctrl.text, 'data');
  });
}
