import 'package:cockpit/app/core/domain/entities/app_settings.dart';
import 'package:cockpit/app/core/terminal/terminal_font_weight.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('auto compensa a densidade da tela', () {
    test('afina em DPR 1 (traço engrossado pelo antialiasing em cinza)', () {
      expect(
        resolveTerminalFontWeight(TerminalFontWeight.auto, 1.0),
        FontWeight.w300,
      );
    });

    test('mantém o peso normal em Retina', () {
      expect(
        resolveTerminalFontWeight(TerminalFontWeight.auto, 2.0),
        FontWeight.w400,
      );
    });

    test('DPR fracionário abaixo do limiar conta como baixa densidade', () {
      expect(
        resolveTerminalFontWeight(TerminalFontWeight.auto, 1.25),
        FontWeight.w300,
      );
    });
  });

  test('peso explícito ignora o DPR', () {
    for (final dpr in [1.0, 2.0, 3.0]) {
      expect(
        resolveTerminalFontWeight(TerminalFontWeight.normal, dpr),
        FontWeight.w400,
        reason: 'dpr $dpr',
      );
      expect(
        resolveTerminalFontWeight(TerminalFontWeight.semiBold, dpr),
        FontWeight.w600,
        reason: 'dpr $dpr',
      );
    }
  });

  test('cada preferência tem um peso distinto', () {
    final weights = {
      for (final p in TerminalFontWeight.values)
        if (p != TerminalFontWeight.auto) resolveTerminalFontWeight(p, 2.0),
    };
    expect(weights.length, TerminalFontWeight.values.length - 1);
  });
}
