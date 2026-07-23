import 'package:cockpit/app/core/terminal/ghostty_font_family.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('resolveGhosttyFontFamily', () {
    test('resolves the generic monospace alias through the platform', () {
      expect(
        resolveGhosttyFontFamily(
          'monospace',
          systemMonospaceResolver: () => 'Noto Sans Mono',
        ),
        'Noto Sans Mono',
      );
    });

    test('keeps an explicitly selected family unchanged', () {
      expect(
        resolveGhosttyFontFamily(
          'MesloLGS Nerd Font Mono',
          systemMonospaceResolver: () => 'Noto Sans Mono',
        ),
        'MesloLGS Nerd Font Mono',
      );
    });

    test('falls back to the generic alias when resolution is unavailable', () {
      expect(
        resolveGhosttyFontFamily(
          ' monospace ',
          systemMonospaceResolver: () => null,
        ),
        'monospace',
      );
    });
  });
}
