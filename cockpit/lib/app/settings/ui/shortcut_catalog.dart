import 'dart:io' show Platform;

/// Catálogo **estático e read-only** dos atalhos de teclado do app, pra exibição
/// na aba Settings → Shortcuts. As teclas hoje estão declaradas em quatro
/// lugares (menu declarativo `buildAppMenus`, `CallbackShortcuts` do `AppRoot`,
/// `CallbackShortcuts` do `CockpitPage` e o handler `HardwareKeyboard` de
/// navegação de panes) — este arquivo só as **documenta**, resolvendo o
/// modificador por plataforma (⌘ no macOS, Ctrl fora). Quando os atalhos
/// virarem customizáveis, este catálogo é o candidato natural a virar o registry
/// central que as quatro camadas consultam.
class AppShortcut {
  const AppShortcut(this.label, this.keys, {this.note});

  final String label;

  /// Teclas já resolvidas pra plataforma corrente, uma por chip (ex.:
  /// `['⌘', '⇧', 'F']` no macOS, `['Ctrl', 'Shift', 'F']` no Windows/Linux).
  final List<String> keys;

  /// Contexto em que o atalho vale (ex.: "when a file editor is focused").
  final String? note;
}

class ShortcutSection {
  const ShortcutSection(this.title, this.items);

  final String title;
  final List<AppShortcut> items;
}

/// Monta o catálogo pra plataforma corrente.
List<ShortcutSection> buildShortcutCatalog() {
  final mac = Platform.isMacOS;
  final cmd = mac ? '⌘' : 'Ctrl';
  final shift = mac ? '⇧' : 'Shift';
  final alt = mac ? '⌥' : 'Alt';

  return <ShortcutSection>[
    ShortcutSection('Application', <AppShortcut>[
      AppShortcut('Open Settings', [cmd, ',']),
      AppShortcut('Open Workspace', [cmd, 'O']),
    ]),
    ShortcutSection('Workspace', <AppShortcut>[
      AppShortcut('Toggle Workspace Panel', [cmd, 'B']),
      AppShortcut('Toggle Files', [cmd, shift, 'B']),
      AppShortcut('Split Pane Right', [cmd, 'D']),
      AppShortcut('Split Pane Down', [cmd, shift, 'D']),
      AppShortcut(
        'Focus Pane',
        [cmd, alt, '← → ↑ ↓'],
        note: 'Moves focus to the pane in that direction.',
      ),
      AppShortcut('Select Tab 1–8', [cmd, '1–8']),
      AppShortcut('Select Last Tab', [cmd, '9']),
      AppShortcut('Next Realm', [cmd, '`']),
      AppShortcut('Previous Realm', [cmd, shift, '`']),
    ]),
    ShortcutSection('Navigation & Search', <AppShortcut>[
      AppShortcut('Go to File', [cmd, 'P']),
      AppShortcut(
        'Search in Files',
        [cmd, shift, 'F'],
        note: 'When no file editor is focused.',
      ),
      AppShortcut('Focus Composer', [cmd, 'L']),
    ]),
    ShortcutSection('Editor', <AppShortcut>[
      AppShortcut('Save File', [cmd, 'S']),
      AppShortcut(
        'Format File',
        [cmd, shift, 'F'],
        note: 'When a file editor is focused.',
      ),
    ]),
    ShortcutSection('View', <AppShortcut>[
      AppShortcut('Zoom In', [cmd, '=']),
      AppShortcut('Zoom Out', [cmd, '-']),
      AppShortcut('Actual Size', [cmd, '0']),
    ]),
  ];
}
