import 'dart:io' show Platform;

import 'package:cockpit/app/settings/ui/shortcut_catalog.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Settings → Shortcuts lists Toggle Word Wrap under Editor', () {
    final editor = buildShortcutCatalog().singleWhere(
      (s) => s.title == 'Editor',
    );
    final wrap = editor.items.singleWhere((i) => i.label == 'Toggle Word Wrap');

    expect(wrap.keys, [Platform.isMacOS ? '⌥' : 'Alt', 'Z']);
    expect(wrap.note, 'When a file editor is focused.');
  });
}
