import 'dart:io' show Platform;

import 'package:cockpit/app/settings/ui/shortcut_catalog.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  // What the Settings → Shortcuts tab renders comes from here (settings_page
  // iterates every section/item of buildShortcutCatalog), so asserting the
  // bindings are in the catalog asserts they appear on the page.
  AppShortcut find(String label) {
    final items = buildShortcutCatalog().expand((s) => s.items);
    return items.firstWhere((s) => s.label == label);
  }

  test('Next Tab / Previous Tab are in the Workspace section', () {
    final workspace = buildShortcutCatalog().firstWhere(
      (s) => s.title == 'Workspace',
    );
    final labels = workspace.items.map((s) => s.label);
    expect(labels, containsAll(<String>['Next Tab', 'Previous Tab']));
  });

  test('Ctrl+Tab does NOT become ⌘ on macOS — Control on every platform', () {
    final next = find('Next Tab');
    final prev = find('Previous Tab');
    if (Platform.isMacOS) {
      // Literal Control (⌃), never ⌘; Tab as ⇥.
      expect(next.keys, ['⌃', '⇥']);
      expect(prev.keys, ['⌃', '⇧', '⇥']);
      expect(next.keys, isNot(contains('⌘')));
    } else {
      expect(next.keys, ['Ctrl', 'Tab']);
      expect(prev.keys, ['Ctrl', 'Shift', 'Tab']);
    }
  });
}
