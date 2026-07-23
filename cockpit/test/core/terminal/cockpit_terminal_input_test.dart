import 'package:cockpit/app/core/terminal/cockpit_terminal.dart';
import 'package:cockpit/app/core/terminal/xterm/xterm.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('commits an IME character only once', (tester) async {
    final output = <String>[];
    final terminal = Terminal(onOutput: output.add);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: CockpitTerminal(terminal, autofocus: true)),
      ),
    );
    await tester.pump();

    final textInput = tester.binding.testTextInput;
    for (final character in ['~', '´', 'á', 'í']) {
      final committed = TextEditingValue(
        text: character,
        selection: TextSelection.collapsed(offset: character.length),
      );
      textInput.updateEditingValue(committed);
      textInput.updateEditingValue(committed);
      textInput.updateEditingValue(committed);
      textInput.updateEditingValue(TextEditingValue.empty);
    }
    await tester.pump();

    expect(output, ['~', '´', 'á', 'í']);
  });

  testWidgets('types a doubled letter without swallowing the repeat', (
    tester,
  ) async {
    final output = <String>[];
    final terminal = Terminal(onOutput: output.add);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: CockpitTerminal(terminal, autofocus: true)),
      ),
    );
    await tester.pump();

    // Typing "esse": the platform never echoes the hidden-buffer reset back, so
    // each keystroke arrives as a lone commit carrying the same delta as the
    // one before it. Both `s` must reach the PTY — the IME de-duplication is
    // only meant to collapse a *re-sent* commit, which has no key event.
    final textInput = tester.binding.testTextInput;
    const keys = {'e': LogicalKeyboardKey.keyE, 's': LogicalKeyboardKey.keyS};
    for (final character in ['e', 's', 's', 'e']) {
      await tester.sendKeyEvent(keys[character]!);
      textInput.updateEditingValue(
        TextEditingValue(
          text: character,
          selection: TextSelection.collapsed(offset: character.length),
        ),
      );
    }
    await tester.pump();

    expect(output.join(), 'esse');
  });
}
