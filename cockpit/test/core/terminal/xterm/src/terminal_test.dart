import 'package:flutter_test/flutter_test.dart';
import 'package:cockpit/app/core/terminal/xterm/core.dart';

void main() {
  group('Terminal.inputHandler', () {
    test('can be set to null', () {
      final terminal = Terminal(inputHandler: null);
      expect(() => terminal.keyInput(TerminalKey.keyA), returnsNormally);
    });

    test('can be changed', () {
      final handler1 = _TestInputHandler();
      final handler2 = _TestInputHandler();
      final terminal = Terminal(inputHandler: handler1);

      terminal.keyInput(TerminalKey.keyA);
      expect(handler1.events, isNotEmpty);

      terminal.inputHandler = handler2;

      terminal.keyInput(TerminalKey.keyA);
      expect(handler2.events, isNotEmpty);
    });
  });

  group('Terminal.mouseInput', () {
    test('can handle mouse events', () {
      final output = <String>[];

      final terminal = Terminal(onOutput: output.add);

      terminal.mouseInput(
        TerminalMouseButton.left,
        TerminalMouseButtonState.down,
        CellOffset(10, 10),
      );

      expect(output, isEmpty);

      // enable mouse reporting
      terminal.write('\x1b[?1000h');

      terminal.mouseInput(
        TerminalMouseButton.left,
        TerminalMouseButtonState.down,
        CellOffset(10, 10),
      );

      expect(output, ['\x1B[M +,']);
    });
  });

  group('Terminal.reflowEnabled', () {
    test('prevents reflow when set to false', () {
      final terminal = Terminal(reflowEnabled: false);

      terminal.write('Hello World');
      terminal.resize(5, 5);

      expect(terminal.buffer.lines[0].toString(), 'Hello');
      expect(terminal.buffer.lines[1].toString(), isEmpty);
    });

    test('preserves hidden cells when reflow is disabled', () {
      final terminal = Terminal(reflowEnabled: false);

      terminal.write('Hello World');
      terminal.resize(5, 5);
      terminal.resize(20, 5);

      expect(terminal.buffer.lines[0].toString(), 'Hello World');
      expect(terminal.buffer.lines[1].toString(), isEmpty);
    });

    test('can be set at runtime', () {
      final terminal = Terminal(reflowEnabled: true);

      terminal.resize(5, 5);
      terminal.write('Hello World');
      terminal.reflowEnabled = false;
      terminal.resize(20, 5);

      expect(terminal.buffer.lines[0].toString(), 'Hello');
      expect(terminal.buffer.lines[1].toString(), ' Worl');
      expect(terminal.buffer.lines[2].toString(), 'd');
    });
  });

  group('Terminal.mouseInput', () {
    test('applys to the main buffer', () {
      final terminal = Terminal(wordSeparators: {'z'.codeUnitAt(0)});

      expect(terminal.mainBuffer.wordSeparators, contains('z'.codeUnitAt(0)));
    });

    test('applys to the alternate buffer', () {
      final terminal = Terminal(wordSeparators: {'z'.codeUnitAt(0)});

      expect(terminal.altBuffer.wordSeparators, contains('z'.codeUnitAt(0)));
    });
  });

  group('Terminal.onPrivateOSC', () {
    test(r'works with \a end', () {
      String? lastCode;
      List<String>? lastData;

      final terminal = Terminal(
        onPrivateOSC: (String code, List<String> data) {
          lastCode = code;
          lastData = data;
        },
      );

      terminal.write('\x1b]6\x07');

      expect(lastCode, '6');
      expect(lastData, []);

      terminal.write('\x1b]66;hello world\x07');

      expect(lastCode, '66');
      expect(lastData, ['hello world']);

      terminal.write('\x1b]666;hello;world\x07');

      expect(lastCode, '666');
      expect(lastData, ['hello', 'world']);

      terminal.write('\x1b]hello;world\x07');

      expect(lastCode, 'hello');
      expect(lastData, ['world']);
    });

    test(r'works with \x1b\ end', () {
      String? lastCode;
      List<String>? lastData;

      final terminal = Terminal(
        onPrivateOSC: (String code, List<String> data) {
          lastCode = code;
          lastData = data;
        },
      );

      terminal.write('\x1b]6\x1b\\');

      expect(lastCode, '6');
      expect(lastData, []);

      terminal.write('\x1b]66;hello world\x1b\\');

      expect(lastCode, '66');
      expect(lastData, ['hello world']);

      terminal.write('\x1b]666;hello;world\x1b\\');

      expect(lastCode, '666');
      expect(lastData, ['hello', 'world']);

      terminal.write('\x1b]hello;world\x1b\\');

      expect(lastCode, 'hello');
      expect(lastData, ['world']);
    });

    test('do not receive common osc', () {
      String? lastCode;
      List<String>? lastData;

      final terminal = Terminal(
        onPrivateOSC: (String code, List<String> data) {
          lastCode = code;
          lastData = data;
        },
      );

      terminal.write('\x1b]0;hello world\x07');

      expect(lastCode, isNull);
      expect(lastData, isNull);
    });
  });

  group('Terminal SGR', () {
    int fgOf(Terminal t, int col) {
      final line = t.buffer.lines[t.buffer.height - t.viewHeight];
      return line.getForeground(col);
    }

    int bgOf(Terminal t, int col) {
      final line = t.buffer.lines[t.buffer.height - t.viewHeight];
      return line.getBackground(col);
    }

    test('applies a normal SGR color sequence', () {
      final terminal = Terminal()..resize(80, 4);
      terminal.write('\x1b[38;5;161;48;5;236mA');
      expect(fgOf(terminal, 0), isNot(0));
      expect(bgOf(terminal, 0), isNot(0));
    });

    test('applies SGR with a leading empty parameter (fzf highlight)', () {
      // `CSI ; 1 ; 38;5;161 ; 48;5;236 m` — the empty first param must not be
      // mistaken for a private-marker prefix, else the whole SGR is dropped and
      // fzf's selection highlight never shows.
      final terminal = Terminal()..resize(80, 4);
      terminal.write('\x1b[;1;38;5;161;48;5;236mB');
      expect(fgOf(terminal, 0), isNot(0), reason: 'foreground must be applied');
      expect(bgOf(terminal, 0), isNot(0), reason: 'background must be applied');
    });

    test('applies SGR ";31" (leading empty param, plain color)', () {
      final terminal = Terminal()..resize(80, 4);
      terminal.write('\x1b[;31mC');
      expect(fgOf(terminal, 0), isNot(0));
    });
  });

  group('Terminal DSR', () {
    test('cursor position report (CPR) is 1-based', () {
      final output = <String>[];
      final terminal = Terminal(onOutput: output.add)..resize(80, 24);

      terminal.write('\x1b[H\x1b[6n'); // home, then query
      expect(output.last, '\x1b[1;1R');

      output.clear();
      terminal.write(
        '\x1b[5;10H\x1b[6n',
      ); // row 5, col 10 (1-based), then query
      expect(output.last, '\x1b[5;10R');
    });
  });
}

class _TestInputHandler implements TerminalInputHandler {
  final events = <TerminalKeyboardEvent>[];

  @override
  String? call(TerminalKeyboardEvent event) {
    events.add(event);
    return null;
  }
}
