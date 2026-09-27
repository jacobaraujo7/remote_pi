import 'package:cockpit/app/core/terminal/terminal_line_ending_normalizer.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('normalizes LF and preserves CRLF', () {
    final normalizer = TerminalLineEndingNormalizer();
    expect(normalizer.add('one\ntwo\r\nthree'), 'one\r\ntwo\r\nthree');
    expect(normalizer.close(), isEmpty);
  });

  test('recognizes CRLF split across chunks', () {
    final normalizer = TerminalLineEndingNormalizer();
    expect(normalizer.add('one\r'), 'one');
    expect(normalizer.add('\ntwo\n'), '\r\ntwo\r\n');
    expect(normalizer.close(), isEmpty);
  });

  test('preserves bare CR used by progress output', () {
    final normalizer = TerminalLineEndingNormalizer();
    expect(normalizer.add('10%\r20%'), '10%\r20%');
    expect(normalizer.add('\r'), isEmpty);
    expect(normalizer.close(), '\r');
  });

  test('does not buffer long continuous lines', () {
    final normalizer = TerminalLineEndingNormalizer();
    final long = 'x' * (256 * 1024);
    expect(normalizer.add(long), long);
    expect(normalizer.close(), isEmpty);
  });
}
