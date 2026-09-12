import 'package:flutter_test/flutter_test.dart';
import 'package:cockpit/app/core/terminal/xterm/src/utils/unicode_v11.dart';

void main() {
  test('does not fail for BMP code points beyond a truncated table', () {
    expect(unicodeV11.wcwidth(0x0100), 1);
    expect(unicodeV11.wcwidth(0x0300), 0);
    expect(unicodeV11.wcwidth(0x1100), 2);
  });
}
