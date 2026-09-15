import 'package:cockpit/app/cockpit/ui/widgets/terminal_pane.dart';
import 'package:cockpit/app/core/terminal/terminal_context_menu.dart';
import 'package:cockpit/app/core/terminal/xterm/xterm.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('botão direito resolve toda a linha lógica quebrada', (
    tester,
  ) async {
    final terminal = Terminal(maxLines: 100);
    final focusNode = FocusNode();
    addTearDown(focusNode.dispose);
    final text = List.filled(120, 'x').join();
    terminal.write(text);
    TerminalContextMenuRequest? request;

    await tester.pumpWidget(
      MediaQuery(
        data: const MediaQueryData(size: Size(180, 160)),
        child: Directionality(
          textDirection: TextDirection.ltr,
          child: SizedBox(
            width: 180,
            height: 160,
            child: TerminalPane(
              terminal: terminal,
              active: true,
              focusNode: focusNode,
              textStyle: const TerminalStyle(fontSize: 14),
              theme: TerminalThemes.defaultTheme,
              onKeyEvent: (_) => KeyEventResult.ignored,
              enableLineHover: true,
              onContextMenu: (value) => request = value,
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    await tester.tapAt(const Offset(20, 12), buttons: kSecondaryMouseButton);
    await tester.pump();

    expect(request, isNotNull);
    expect(request!.selectedText, isEmpty);
    expect(request!.line!.text, text);
    expect(
      request!.line!.lastViewportRow,
      greaterThan(request!.line!.firstViewportRow),
    );
  });

  testWidgets('nao resolve linhas ainda nao preenchidas pelo console', (
    tester,
  ) async {
    final terminal = Terminal(maxLines: 100)..write('uma linha');
    final focusNode = FocusNode();
    addTearDown(focusNode.dispose);
    TerminalContextMenuRequest? request;

    await tester.pumpWidget(
      MediaQuery(
        data: const MediaQueryData(size: Size(180, 160)),
        child: Directionality(
          textDirection: TextDirection.ltr,
          child: SizedBox(
            width: 180,
            height: 160,
            child: TerminalPane(
              terminal: terminal,
              active: true,
              focusNode: focusNode,
              textStyle: const TerminalStyle(fontSize: 14),
              theme: TerminalThemes.defaultTheme,
              onKeyEvent: (_) => KeyEventResult.ignored,
              enableLineHover: true,
              onContextMenu: (value) => request = value,
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    await tester.tapAt(const Offset(20, 140), buttons: kSecondaryMouseButton);
    await tester.pump();

    expect(request, isNotNull);
    expect(request!.line, isNull);
  });
}
