import 'package:cockpit/app/cockpit/ui/widgets/terminal_pane.dart';
import 'package:cockpit/app/core/terminal/xterm/xterm.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('terminal invisível desanexa renderer e preserva o State', (
    tester,
  ) async {
    final terminal = Terminal(maxLines: 100);
    final focusNode = FocusNode();

    Widget app(bool active) => MediaQuery(
      data: const MediaQueryData(size: Size(800, 400)),
      child: Directionality(
        textDirection: TextDirection.ltr,
        child: SizedBox(
          width: 800,
          height: 400,
          child: TerminalPane(
            terminal: terminal,
            active: active,
            focusNode: focusNode,
            textStyle: const TerminalStyle(),
            theme: TerminalThemes.defaultTheme,
            onKeyEvent: (_) => KeyEventResult.ignored,
          ),
        ),
      ),
    );

    await tester.pumpWidget(app(true));
    await tester.pump();
    final originalState = tester.state(find.byType(TerminalPane));
    expect(terminal.listeners, isNotEmpty);

    await tester.pumpWidget(app(false));
    expect(tester.state(find.byType(TerminalPane)), same(originalState));
    expect(terminal.listeners, isEmpty);

    // O parser/modelo continua avançando sem uma superfície invisível pedir
    // layout ou paint.
    terminal.write('hidden output\r\n');
    await tester.pump();
    final lines = terminal.buffer.lines;
    expect(
      [for (var i = 0; i < lines.length; i++) lines[i].getText()].join('\n'),
      contains('hidden output'),
    );
    expect(terminal.listeners, isEmpty);

    await tester.pumpWidget(app(true));
    await tester.pump();
    expect(tester.state(find.byType(TerminalPane)), same(originalState));
    expect(terminal.listeners, isNotEmpty);

    await tester.pumpWidget(const SizedBox.shrink());
    focusNode.dispose();
  });
}
