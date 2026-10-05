import 'package:cockpit/app/core/domain/entities/app_settings.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('AppSettings · closeTabOnShellExit', () {
    test('defaults to false (shell tab stays, historic behavior)', () {
      expect(const AppSettings().closeTabOnShellExit, isFalse);
      expect(
        AppSettings.fromJson(const <String, dynamic>{}).closeTabOnShellExit,
        isFalse,
      );
    });

    test('round-trips both values', () {
      for (final value in [true, false]) {
        final settings = AppSettings(closeTabOnShellExit: value);
        expect(
          AppSettings.fromJson(settings.toJson()).closeTabOnShellExit,
          value,
        );
      }
    });

    test('is omitted from JSON when false, present when true', () {
      expect(
        const AppSettings().toJson().containsKey('closeTabOnShellExit'),
        isFalse,
      );
      expect(
        const AppSettings(closeTabOnShellExit: true).toJson(),
        containsPair('closeTabOnShellExit', true),
      );
    });

    test('copyWith changes only this flag', () {
      const settings = AppSettings(terminalFont: 'Menlo');
      final changed = settings.copyWith(closeTabOnShellExit: true);

      expect(changed.closeTabOnShellExit, isTrue);
      expect(changed.terminalFont, 'Menlo');
    });
  });
}
