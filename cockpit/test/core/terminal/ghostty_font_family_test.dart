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

    test('uses the registered bundled JetBrains Mono family', () {
      expect(
        resolveGhosttyFontFamily(
          'JetBrains Mono',
          bundledJetBrainsMonoResolver: () => 'JetBrainsMono_bundled',
        ),
        'JetBrainsMono_bundled',
      );
    });

    test(
      'maps a system monospace resolved as JetBrains Mono to the bundle',
      () {
        expect(
          resolveGhosttyFontFamily(
            'monospace',
            systemMonospaceResolver: () => 'JetBrains Mono',
            bundledJetBrainsMonoResolver: () => 'JetBrainsMono_bundled',
          ),
          'JetBrainsMono_bundled',
        );
      },
    );

    test('keeps JetBrains Mono when the bundled resolver is unavailable', () {
      expect(
        resolveGhosttyFontFamily(
          'JetBrains Mono',
          bundledJetBrainsMonoResolver: () => null,
        ),
        'JetBrains Mono',
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
