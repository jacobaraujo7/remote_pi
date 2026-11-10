// AppFontScale stepping — drives the hardware volume-key shortcut.

import 'package:app/ui/core/themes/themes.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('stepping', () {
    test('larger walks up the scale and stops at XL', () {
      expect(AppFontScale.small.larger, AppFontScale.standard);
      expect(AppFontScale.standard.larger, AppFontScale.large);
      expect(AppFontScale.large.larger, AppFontScale.extraLarge);
      // The shortcut must not wrap around: the top of the scale stays put.
      expect(AppFontScale.extraLarge.larger, isNull);
    });

    test('smaller walks down the scale and stops at Small', () {
      expect(AppFontScale.extraLarge.smaller, AppFontScale.large);
      expect(AppFontScale.large.smaller, AppFontScale.standard);
      expect(AppFontScale.standard.smaller, AppFontScale.small);
      expect(AppFontScale.small.smaller, isNull);
    });

    test('a full walk up is reversible', () {
      var scale = AppFontScale.small;
      for (var i = 0; i < 3; i++) {
        scale = scale.larger!;
      }
      expect(scale, AppFontScale.extraLarge);
      for (var i = 0; i < 3; i++) {
        scale = scale.smaller!;
      }
      expect(scale, AppFontScale.small);
    });

    test('factors stay ordered so bigger steps really are bigger', () {
      final factors = AppFontScale.values.map((s) => s.factor).toList();
      for (var i = 1; i < factors.length; i++) {
        expect(factors[i], greaterThan(factors[i - 1]));
      }
    });
  });
}
