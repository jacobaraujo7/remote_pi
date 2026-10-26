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

  test('Toggle Word Wrap carries ⌥Z/Alt+Z with no primary modifier', () {
    final t = AppLocale.en.buildSync();
    final menus = buildAppMenus(
      t,
      SettingsController(_FakeSettingsStore()),
      EditorMenuBridge(),
      WorkspaceMenuBridge(),
    );
    final wrap = _findAction(menus, t.core.menu.toggleWordWrap);

    expect(wrap, isNotNull, reason: 'Toggle Word Wrap item must exist');
    final activator = wrap!.accelerator!.resolve();
    expect(activator.trigger, LogicalKeyboardKey.keyZ);
    expect(activator.alt, isTrue);
    expect(activator.meta, isFalse);
    expect(activator.control, isFalse);
    expect(activator.shift, isFalse);

    // The file editor binds the key itself: a global Alt+Z would take it away
    // from terminals outside macOS, so the menu must not register it.
    expect(wrap.shortcutHandledExternally, isTrue);
    expect(
      menuShortcuts(
        menus,
      ).keys.any((a) => a.trigger == LogicalKeyboardKey.keyZ),
      isFalse,
    );
  });

  test('Toggle Word Wrap is enabled only while a file editor publishes it', () {
    final t = AppLocale.en.buildSync();
    final controller = SettingsController(_FakeSettingsStore());
    final workspace = WorkspaceMenuBridge();
    final editor = EditorMenuBridge();
    final owner = Object();

    MenuAction? wrapItem() => _findAction(
      buildAppMenus(t, controller, editor, workspace),
      t.core.menu.toggleWordWrap,
    );

    expect(wrapItem()?.onSelected, isNull, reason: 'no editor focused');

    // `.http`/`.dbq` publish without a wrap callback: stays disabled.
    editor.publish(
      owner: owner,
      canSave: false,
      canDiscard: false,
      canFormat: true,
      onSave: () {},
      onDiscard: () {},
      onFormat: () {},
    );
    expect(wrapItem()?.onSelected, isNull);

    var toggled = 0;
    editor.publish(
      owner: owner,
      canSave: false,
      canDiscard: false,
      canFormat: true,
      onSave: () {},
      onDiscard: () {},
      onFormat: () {},
      onToggleWordWrap: () => toggled++,
    );
    wrapItem()!.onSelected!();
    expect(toggled, 1);

    editor.clear(owner);
    expect(wrapItem()?.onSelected, isNull);
  });
}
