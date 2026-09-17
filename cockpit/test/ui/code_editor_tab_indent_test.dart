import 'package:cockpit/app/cockpit/ui/widgets/code_editor.dart';
import 'package:cockpit/app/core/ui/themes/themes.dart';
import 'package:cockpit/app/core/ui/widgets/code_editing_controller.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';

void main() {
  Widget harness(CodeEditingController ctrl, FocusNode focus, FocusNode other) {
    return ShadcnApp(
      theme: buildTheme(brightness: Brightness.dark),
      home: Scaffold(
        child: Column(
          children: [
            SizedBox(
              width: 300,
              height: 200,
              child: CodeEditor(
                controller: ctrl,
                focusNode: focus,
                filePath: 'main.dart',
              ),
            ),
            Focus(
              focusNode: other,
              child: const SizedBox(width: 10, height: 10),
            ),
          ],
        ),
      ),
    );
  }

  testWidgets('Tab inserts indentation instead of moving focus', (
    tester,
  ) async {
    final ctrl = CodeEditingController(text: 'foo\nbar', language: 'dart');
    final focus = FocusNode();
    final other = FocusNode();
    addTearDown(() {
      ctrl.dispose();
      focus.dispose();
      other.dispose();
    });
    await tester.pumpWidget(harness(ctrl, focus, other));
    focus.requestFocus();
    await tester.pump();
    ctrl.selection = const TextSelection.collapsed(offset: 4);
    await tester.pump();

    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();

    expect(ctrl.text, 'foo\n  bar');
    expect(ctrl.selection.baseOffset, 6);
    expect(focus.hasFocus, isTrue);
    expect(other.hasFocus, isFalse);
  });

  testWidgets('Shift+Tab outdents the current line', (tester) async {
    final ctrl = CodeEditingController(text: '  foo', language: 'dart');
    final focus = FocusNode();
    final other = FocusNode();
    addTearDown(() {
      ctrl.dispose();
      focus.dispose();
      other.dispose();
    });
    await tester.pumpWidget(harness(ctrl, focus, other));
    focus.requestFocus();
    await tester.pump();
    ctrl.selection = const TextSelection.collapsed(offset: 5);
    await tester.pump();

    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    await tester.pump();

    expect(ctrl.text, 'foo');
    expect(ctrl.selection.baseOffset, 3);
    expect(focus.hasFocus, isTrue);
  });
}
