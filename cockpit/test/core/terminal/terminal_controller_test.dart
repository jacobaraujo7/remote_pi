import 'dart:convert';

import 'package:cockpit/app/core/domain/entities/app_settings.dart';
import 'package:cockpit/app/core/terminal/terminal_controller.dart';
import 'package:flterm/flterm.dart' as ghost;
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  for (final engine in TerminalEngine.values) {
    group('${engine.name} terminal controller', () {
      late CockpitTerminalController terminal;

      setUp(() => terminal = createTerminalController(engine));
      tearDown(() => terminal.dispose());

      test('renders VT output as plain text', () {
        terminal.write('\x1b[31mhello\x1b[0m');

        expect(terminal.plainLines().join('\n'), contains('hello'));
      });

      test('paste emits bytes for the PTY', () {
        final output = <int>[];
        terminal.onOutput = output.addAll;

        terminal.paste('olá');

        expect(utf8.decode(output), 'olá');
      });

      test('reports OSC title changes', () {
        String? title;
        terminal.onTitleChanged = (value) => title = value;

        terminal.write('\x1b]0;workspace\x07');

        expect(title, 'workspace');
      });

      test('restores persisted output', () {
        terminal.restore('restored');

        if (terminal case final GhosttyTerminalController ghostty) {
          expect(terminal.plainLines().join('\n'), isNot(contains('restored')));
          ghostty.controller.onResize?.call(120, 40);
        }

        expect(terminal.plainLines().join('\n'), contains('restored'));
      });
    });
  }

  testWidgets('Ghostty restores OSC state after the initial layout', (
    tester,
  ) async {
    final terminal = GhosttyTerminalController();
    addTearDown(terminal.dispose);
    terminal.restore('\x1b]7;file:///tmp\x07restored');

    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: SizedBox(
          width: 800,
          height: 600,
          child: ghost.TerminalView(controller: terminal.controller),
        ),
      ),
    );

    expect(tester.takeException(), isNull);
    expect(terminal.controller.pwd, 'file:///tmp');
    expect(terminal.plainLines().join('\n'), contains('restored'));
  });
}
