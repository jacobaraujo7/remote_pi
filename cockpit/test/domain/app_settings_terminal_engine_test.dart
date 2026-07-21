import 'package:cockpit/app/core/domain/entities/app_settings.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('AppSettings · terminal.engine', () {
    test('Ghostty is the default for new terminals', () {
      expect(const AppSettings().terminalEngine, TerminalEngine.ghostty);
      expect(
        AppSettings.fromJson(const <String, dynamic>{}).terminalEngine,
        TerminalEngine.ghostty,
      );
    });

    test('round-trips both engines', () {
      for (final engine in TerminalEngine.values) {
        final settings = AppSettings(terminalEngine: engine);
        expect(AppSettings.fromJson(settings.toJson()).terminalEngine, engine);
      }
    });

    test('copyWith changes only the default engine', () {
      const settings = AppSettings(terminalFont: 'Menlo');
      final changed = settings.copyWith(terminalEngine: TerminalEngine.xterm);

      expect(changed.terminalEngine, TerminalEngine.xterm);
      expect(changed.terminalFont, 'Menlo');
    });
  });
}
