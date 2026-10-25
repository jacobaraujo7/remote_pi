import 'package:cockpit/app/core/terminal/terminal_find.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('findTerminalMatches', () {
    test('empty query yields no matches', () {
      expect(findTerminalMatches(['hello world'], ''), isEmpty);
    });

    test('no occurrence yields no matches', () {
      expect(findTerminalMatches(['hello world'], 'xyz'), isEmpty);
    });

    test('reports line, column and length of a single match', () {
      final matches = findTerminalMatches(['the quick brown fox'], 'quick');
      expect(matches, hasLength(1));
      expect(matches.single.line, 0);
      expect(matches.single.column, 4);
      expect(matches.single.length, 5);
    });

    test('is case-insensitive', () {
      final matches = findTerminalMatches(['Error: ERROR error'], 'error');
      expect(matches.map((m) => m.column), [0, 7, 13]);
    });

    test('finds multiple non-overlapping matches per line', () {
      // "aaa" with needle "aa" matches once (non-overlapping), then stops.
      final matches = findTerminalMatches(['aaaa'], 'aa');
      expect(matches.map((m) => m.column), [0, 2]);
    });

    test('returns matches top-to-bottom across lines', () {
      final matches = findTerminalMatches([
        'foo',
        'bar',
        'foobar',
      ], 'foo');
      expect(matches.map((m) => m.line), [0, 2]);
      expect(matches.map((m) => m.column), [0, 0]);
    });
  });
}
