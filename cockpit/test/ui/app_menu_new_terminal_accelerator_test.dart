import 'dart:io' show Platform;

import 'package:cockpit/app/core/domain/contracts/settings_store.dart';
import 'package:cockpit/app/core/domain/entities/app_settings.dart';
import 'package:cockpit/app/core/ui/menu/app_menu_bar.dart';
import 'package:cockpit/app/core/ui/menu/editor_menu_bridge.dart';
import 'package:cockpit/app/core/ui/menu/menu_model.dart';
import 'package:cockpit/app/core/ui/menu/workspace_menu_bridge.dart';
import 'package:cockpit/app/core/ui/settings_controller.dart';
import 'package:cockpit/i18n/strings.g.dart';
import 'package:flutter/services.dart' show LogicalKeyboardKey;
import 'package:flutter_test/flutter_test.dart';

/// Store em memória: `buildAppMenus` nunca toca o store (só o captura no closure
/// de zoom), então o `load()` devolve os defaults e nada é persistido.
class _FakeSettingsStore implements SettingsStore {
  @override
  Future<AppSettings> load() async => const AppSettings();

  @override
  Future<void> save(AppSettings settings) async {}
}

/// Acha a primeira [MenuAction] com o rótulo [label], descendo nos submenus.
MenuAction? _findAction(Iterable<MenuNode> nodes, String label) {
  for (final node in nodes) {
    if (node is MenuAction && node.label == label) return node;
    if (node is MenuBarMenu) {
      final found = _findAction(node.items, label);
      if (found != null) return found;
    }
  }
  return null;
}

void main() {
  // `setWorkspace` notifies listeners via the scheduler, which needs a binding.
  TestWidgetsFlutterBinding.ensureInitialized();

  test('New Terminal carries the primary-modifier + T accelerator', () {
    final t = AppLocale.en.buildSync();
    final controller = SettingsController(_FakeSettingsStore());
    final editor = EditorMenuBridge();
    final workspace = WorkspaceMenuBridge()
      ..setWorkspace(hasWorkspace: true, onNewTerminal: () {});

    final menus = buildAppMenus(t, controller, editor, workspace);
    final newTerminal = _findAction(menus, t.core.menu.newTerminal);

    expect(newTerminal, isNotNull, reason: 'New Terminal item must exist');
    expect(
      newTerminal!.onSelected,
      isNotNull,
      reason: 'enabled while a workspace is active',
    );
    final accelerator = newTerminal.accelerator;
    expect(accelerator, isNotNull, reason: 'New Terminal must have a shortcut');
    expect(accelerator!.key, LogicalKeyboardKey.keyT);
    expect(accelerator.shift, isFalse);

    // The primary modifier resolves per platform: Cmd on macOS, Ctrl elsewhere.
    final activator = accelerator.resolve();
    expect(activator.trigger, LogicalKeyboardKey.keyT);
    expect(activator.meta, Platform.isMacOS);
    expect(activator.control, !Platform.isMacOS);
    expect(activator.shift, isFalse);
  });

  test('Go to File carries ⌘P/Ctrl+P and reaches the shell callback', () {
    final t = AppLocale.en.buildSync();
    final controller = SettingsController(_FakeSettingsStore());
    final editor = EditorMenuBridge();
    var opened = 0;
    final workspace = WorkspaceMenuBridge()
      ..setWorkspace(hasWorkspace: true, onGoToFile: () => opened++);

    final menus = buildAppMenus(t, controller, editor, workspace);
    final goToFile = _findAction(menus, t.core.menu.goToFile);

    expect(goToFile, isNotNull, reason: 'Go to File item must exist');
    expect(goToFile!.accelerator?.key, LogicalKeyboardKey.keyP);
    expect(goToFile.accelerator?.shift, isFalse);

    goToFile.onSelected!();
    expect(opened, 1);

    // The shell's CallbackShortcuts already binds the key outside macOS: the
    // menu must not register it again, or the palette would open twice.
    expect(goToFile.shortcutHandledExternally, isTrue);
    expect(
      menuShortcuts(
        menus,
      ).keys.any((a) => a.trigger == LogicalKeyboardKey.keyP),
      isFalse,
    );
  });

  test('Go to File is disabled without a workspace', () {
    final t = AppLocale.en.buildSync();
    final menus = buildAppMenus(
      t,
      SettingsController(_FakeSettingsStore()),
      EditorMenuBridge(),
      WorkspaceMenuBridge(),
    );

    expect(_findAction(menus, t.core.menu.goToFile)?.onSelected, isNull);
  });
}
