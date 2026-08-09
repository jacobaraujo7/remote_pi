import 'package:cockpit/app/core/domain/entities/app_settings.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('AppSettings · terminal typography', () {
    test('defaults: size inherits code, weight is auto', () {
      const settings = AppSettings();

      expect(settings.terminalSize, isNull);
      expect(settings.terminalFontWeight, TerminalFontWeight.auto);
    });

    test('settings saved before these fields existed keep inheriting', () {
      // Um JSON antigo não tem as chaves novas: o tamanho tem que seguir o do
      // código, que era o comportamento anterior.
      final legacy = AppSettings.fromJson(const <String, dynamic>{
        'codeSize': 15.0,
        'terminalFont': 'Menlo',
      });

      expect(legacy.terminalSize, isNull);
      expect(legacy.terminalFontWeight, TerminalFontWeight.auto);
      expect(legacy.codeSize, 15.0);
    });

    test('round-trips an explicit size', () {
      const settings = AppSettings(terminalSize: 17);

      expect(AppSettings.fromJson(settings.toJson()).terminalSize, 17);
    });

    test('round-trips every weight', () {
      for (final weight in TerminalFontWeight.values) {
        final settings = AppSettings(terminalFontWeight: weight);
        expect(
          AppSettings.fromJson(settings.toJson()).terminalFontWeight,
          weight,
          reason: weight.name,
        );
      }
    });

    test('an unknown persisted weight falls back to auto', () {
      final settings = AppSettings.fromJson(const <String, dynamic>{
        'terminalFontWeight': 'ultraBlack',
      });

      expect(settings.terminalFontWeight, TerminalFontWeight.auto);
    });

    test('clearTerminalSize goes back to inheriting', () {
      const settings = AppSettings(terminalSize: 17, codeSize: 13);

      expect(settings.copyWith(clearTerminalSize: true).terminalSize, isNull);
      // Sem a flag, copyWith não apaga (o padrão do resto da classe).
      expect(settings.copyWith().terminalSize, 17);
    });

    test('changing the terminal size leaves the code size alone', () {
      const settings = AppSettings(codeSize: 13);
      final changed = settings.copyWith(terminalSize: 18);

      expect(changed.terminalSize, 18);
      expect(changed.codeSize, 13);
    });
  });
}
