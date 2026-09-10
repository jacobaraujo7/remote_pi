import 'package:cockpit/app/core/utils/bounded_text_buffer.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('trims whole and partial chunks without exceeding the bound', () {
    final buffer = BoundedTextBuffer(maxLength: 10, retainedLength: 6)
      ..add('abcd')
      ..add('efgh')
      ..add('ijkl');
    expect(buffer.length, 6);
    expect(buffer.toString(), 'ghijkl');
  });

  test('trim never leaves a split UTF-16 surrogate pair', () {
    final buffer = BoundedTextBuffer(maxLength: 5, retainedLength: 3)
      ..add('ab😀')
      ..add('cd');
    expect(buffer.toString(), 'cd');
    expect(buffer.length, 2);
  });

  test('small appends do not require intermediate materialization', () {
    final buffer = BoundedTextBuffer(maxLength: 100, retainedLength: 75);
    for (var i = 0; i < 1000; i++) {
      buffer.add('x');
    }
    expect(buffer.length, lessThanOrEqualTo(100));
    expect(buffer.toString(), 'x' * buffer.length);
  });
}
