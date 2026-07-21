import 'package:cockpit/app/core/terminal/ghostty_sgr_weight_normalizer.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late GhosttySgrWeightNormalizer normalizer;

  setUp(() => normalizer = GhosttySgrWeightNormalizer());

  test('demotes SGR bold while preserving other attributes', () {
    expect(
      normalizer.add('\x1b[1;31mBold red\x1b[0m'),
      '\x1b[22;31mBold red\x1b[0m',
    );
  });

  test('handles an SGR sequence split across PTY chunks', () {
    expect(normalizer.add('before\x1b[1;'), 'before');
    expect(normalizer.add('36mafter'), '\x1b[22;36mafter');
  });

  test('does not change non-SGR control sequences', () {
    expect(normalizer.add('\x1b[2K\x1b[4H'), '\x1b[2K\x1b[4H');
  });
}
