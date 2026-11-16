import 'package:cockpit/app/core/terminal/terminal_controller.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late GhosttyTerminalController terminal;
  setUp(() => terminal = GhosttyTerminalController());
  tearDown(() => terminal.dispose());

  test('wrapped output resolves as one logical line from either row', () {
    final text = List.filled(120, 'x').join();
    terminal.write(text);
    final first = terminal.lineAtViewportRow(0)!;
    final second = terminal.lineAtViewportRow(1)!;
    expect(first.text, text);
    expect(first.firstViewportRow, 0);
    expect(first.lastViewportRow, 1);
    expect(identical(first, second), isTrue);
  });

  test('blank output lines are selectable but unused grid rows are not', () {
    terminal.write('first\r\n\r\nlast');
    expect(terminal.lineAtViewportRow(1)!.text, isEmpty);
    expect(terminal.lineAtViewportRow(2)!.text, 'last');
    expect(terminal.lineAtViewportRow(3), isNull);
    expect(terminal.lineAtViewportRow(-1), isNull);
    expect(terminal.lineAtViewportRow(1000), isNull);
  });

  test('output overwrites and clear invalidate the hovered line', () {
    terminal.write('before');
    expect(terminal.lineAtViewportRow(0)!.text, 'before');
    var changes = 0;
    terminal.viewportContentChanges.addListener(() => changes++);
    terminal.write('\r\x1b[2Kafter');
    expect(changes, greaterThan(0));
    expect(terminal.lineAtViewportRow(0)!.text, 'after');
    terminal.clearBuffer();
    expect(terminal.lineAtViewportRow(0)!.text, isEmpty);
    expect(terminal.lineAtViewportRow(1), isNull);
  });

  test('scrolling updates the same row to the visible history', () {
    terminal.write([for (var i = 0; i < 40; i++) 'line $i'].join('\r\n'));
    final bottom = terminal.lineAtViewportRow(0)!.text;
    terminal.controller.scrollToTop();
    expect(terminal.lineAtViewportRow(0)!.text, 'line 0');
    terminal.controller.scrollToBottom();
    expect(terminal.lineAtViewportRow(0)!.text, bottom);
  });
}
