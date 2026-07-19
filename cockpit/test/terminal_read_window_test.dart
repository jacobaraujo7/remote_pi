import 'dart:convert';

import 'package:cockpit/app/cockpit/ui/session/terminal_read_window.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:cockpit/app/core/terminal/xterm/xterm.dart';

/// Sobe um Terminal e escreve N linhas numeradas (`L1`..`Ln`).
Terminal _filled(int n) {
  final term = Terminal(maxLines: 10000);
  term.resize(80, 24);
  for (var i = 1; i <= n; i++) {
    term.write('L$i\r\n');
  }
  return term;
}

List<String> _linesOf(Map<String, dynamic> r) {
  final text = utf8.decode(base64.decode(r['text'] as String));
  return text.isEmpty ? const [] : text.split('\n');
}

void main() {
  test('tail default: last 100 lines, chronological', () {
    final r = readTerminalWindow(_filled(300), const {});
    final lines = _linesOf(r);
    expect(r['lines'], 100);
    expect(lines.first, 'L201');
    expect(lines.last, 'L300');
  });

  test('--lines caps the window', () {
    final r = readTerminalWindow(_filled(50), const {'lines': 10});
    final lines = _linesOf(r);
    expect(lines, [
      'L41',
      'L42',
      'L43',
      'L44',
      'L45',
      'L46',
      'L47',
      'L48',
      'L49',
      'L50',
    ]);
  });

  test('from-start anchors at the beginning', () {
    final r = readTerminalWindow(_filled(50), const {
      'lines': 3,
      'fromStart': true,
    });
    expect(_linesOf(r), ['L1', 'L2', 'L3']);
  });

  test('offset pages backwards from the tail', () {
    final r = readTerminalWindow(_filled(50), const {'lines': 5, 'offset': 5});
    expect(_linesOf(r), ['L41', 'L42', 'L43', 'L44', 'L45']);
  });

  test('offset with from-start pages forward', () {
    final r = readTerminalWindow(_filled(50), const {
      'lines': 2,
      'offset': 3,
      'fromStart': true,
    });
    expect(_linesOf(r), ['L4', 'L5']);
  });

  test('trailing blank viewport lines are ignored in total', () {
    final r = readTerminalWindow(_filled(5), const {});
    expect(r['total'], 5);
    expect(_linesOf(r).last, 'L5');
  });

  test('window larger than buffer returns everything', () {
    final r = readTerminalWindow(_filled(3), const {'lines': 500});
    expect(_linesOf(r), ['L1', 'L2', 'L3']);
    expect(r['truncated'], false);
  });

  test('lines above the 2000 cap flag truncated', () {
    final r = readTerminalWindow(_filled(3), const {'lines': 5000});
    expect(r['truncated'], true);
  });

  test('offset beyond buffer yields empty window', () {
    final r = readTerminalWindow(_filled(5), const {
      'lines': 3,
      'offset': 50,
      'fromStart': true,
    });
    expect(r['lines'], 0);
    expect(_linesOf(r), const <String>[]);
  });
}
