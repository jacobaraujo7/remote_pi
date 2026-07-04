import 'dart:io' show Platform;

import 'package:cockpit/app/core/app_intents.dart';
import 'package:cockpit/app/core/ui/menu/editor_menu_bridge.dart';
import 'package:cockpit/app/core/ui/menu/menu_model.dart';
import 'package:cockpit/app/core/ui/menu/workspace_menu_bridge.dart';
import 'package:cockpit/app/core/ui/settings_controller.dart';
import 'package:cockpit/app/core/ui/themes/themes.dart';
import 'package:flutter/services.dart' show LogicalKeyboardKey;
import 'package:shadcn_flutter/shadcn_flutter.dart';
import 'package:window_manager/window_manager.dart';

// ===========================================================================
// Definição única do menu do app (fonte de verdade para os dois renderers).
// ===========================================================================

/// Monta a árvore de menus do app. Referencia só o `core`: o [controller]
/// (zoom/tamanho da interface) e as pontes globais de `app_intents.dart` (abrir
/// configurações/projeto, checar updates) — resolvidas pelo `CockpitPage`, então
/// `null`-safe enquanto o shell não montou.
List<MenuBarMenu> buildAppMenus(
  SettingsController controller,
  EditorMenuBridge editor,
  WorkspaceMenuBridge workspace,
) {
  void zoom(double delta) => controller.setInterfaceSize(
    (controller.settings.interfaceSize + delta).clamp(11.0, 22.0),
  );

  return <MenuBarMenu>[
    // 1ª entrada = menu do app (no macOS o SO rotula com o nome do app).
    MenuBarMenu('Cockpit', <MenuNode>[
      const MenuRole(MenuBarRole.about),
      const MenuSeparator(),
      MenuAction(
        'Settings…',
        accelerator: const MenuAccelerator(LogicalKeyboardKey.comma),
        onSelected: () => requestOpenSettings?.call(),
      ),
      MenuAction(
        'Check for Updates…',
        onSelected: () => requestCheckForUpdates?.call(),
      ),
      const MenuSeparator(),
      const MenuRole(MenuBarRole.services),
      const MenuSeparator(),
      const MenuRole(MenuBarRole.hide),
      const MenuRole(MenuBarRole.hideOthers),
      const MenuRole(MenuBarRole.showAll),
      const MenuSeparator(),
      const MenuRole(MenuBarRole.quit),
    ]),
    MenuBarMenu('File', <MenuNode>[
      // New Agent/Terminal abrem uma aba no workspace ativo (via CockpitPage →
      // newTabIn). Só habilitam quando há workspace selecionado. "New Agent" só
      // aparece quando o suporte a agentes está ligado (Settings → General) e o
      // workspace ativo permite agentes (o Cockpit terminal-only não permite).
      if (controller.settings.enableAgent && workspace.agentsAllowed)
        MenuAction(
          'New Agent',
          onSelected: workspace.hasWorkspace ? workspace.newAgent : null,
        ),
      MenuAction(
        'New Terminal',
        onSelected: workspace.hasWorkspace ? workspace.newTerminal : null,
      ),
      const MenuSeparator(),
      MenuAction(
        'Open Workspace',
        accelerator: const MenuAccelerator(LogicalKeyboardKey.keyO),
        onSelected: () => requestOpenProject?.call(),
      ),
      const MenuSeparator(),
      // Save/Discard/Format só ficam ativos quando há uma aba de edição focada
      // que **de fato** pode a ação (dirty p/ Save/Discard; editável p/ Format) —
      // estado publicado pelo `FileViewer` focado via [EditorMenuBridge]. Sem
      // acelerador aqui: o próprio editor já trata ⌘S/⇧⌘F em todas as plataformas
      // (evita disparo duplo). `onSelected` null = item cinza/desabilitado.
      MenuAction(
        'Save',
        accelerator: const MenuAccelerator(LogicalKeyboardKey.keyS),
        shortcutHandledExternally: true,
        onSelected: editor.canSave ? editor.save : null,
      ),
      MenuAction(
        'Discard',
        onSelected: editor.canDiscard ? editor.discard : null,
      ),
      MenuAction(
        'Format',
        accelerator: const MenuAccelerator(
          LogicalKeyboardKey.keyF,
          shift: true,
        ),
        shortcutHandledExternally: true,
        onSelected: editor.canFormat ? editor.format : null,
      ),
    ]),
    // Zoom: aceleradores só EXIBIDOS (hint) — a tecla já é tratada pelo
    // `_zoomBindings` do `AppRoot` em todas as plataformas. `shortcutHandledExternally`
    // impede o `menuShortcuts` de registrar de novo fora do macOS (disparo duplo).
    MenuBarMenu('View', <MenuNode>[
      // Layout do workspace (ativos só com workspace aberto). Aceleradores reais:
      // no macOS o menu nativo dispara; fora dele o `menuShortcuts` registra.
      MenuAction(
        'Toggle Workspace Panel',
        accelerator: const MenuAccelerator(LogicalKeyboardKey.keyB),
        onSelected: workspace.hasWorkspace ? workspace.toggleRail : null,
      ),
      MenuAction(
        'Toggle Files',
        accelerator: const MenuAccelerator(
          LogicalKeyboardKey.keyB,
          shift: true,
        ),
        onSelected: workspace.hasWorkspace ? workspace.toggleFiles : null,
      ),
      const MenuSeparator(),
      MenuAction(
        'Split Right',
        accelerator: const MenuAccelerator(LogicalKeyboardKey.keyD),
        onSelected: workspace.hasWorkspace ? workspace.splitRight : null,
      ),
      MenuAction(
        'Split Down',
        accelerator: const MenuAccelerator(
          LogicalKeyboardKey.keyD,
          shift: true,
        ),
        onSelected: workspace.hasWorkspace ? workspace.splitDown : null,
      ),
      const MenuSeparator(),
      MenuAction(
        'Zoom In',
        accelerator: const MenuAccelerator(LogicalKeyboardKey.equal),
        shortcutHandledExternally: true,
        onSelected: () => zoom(1),
      ),
      MenuAction(
        'Zoom Out',
        accelerator: const MenuAccelerator(LogicalKeyboardKey.minus),
        shortcutHandledExternally: true,
        onSelected: () => zoom(-1),
      ),
      MenuAction(
        'Actual Size',
        accelerator: const MenuAccelerator(LogicalKeyboardKey.digit0),
        shortcutHandledExternally: true,
        onSelected: () => controller.setInterfaceSize(14),
      ),
    ]),
    const MenuBarMenu('Window', <MenuNode>[
      MenuRole(MenuBarRole.minimizeWindow),
      MenuRole(MenuBarRole.zoomWindow),
    ]),
  ];
}

// ===========================================================================
// AppMenuBar — envelope macOS (barra nativa do SO).
// ===========================================================================

/// Instala a barra de menu **nativa** no macOS envolvendo [child] com um
/// `PlatformMenuBar`. Fora do macOS é no-op (repassa [child]) — lá a barra é
/// desenhada dentro da janela pelo [WindowMenuBar], embutido na barra de título.
class AppMenuBar extends StatelessWidget {
  const AppMenuBar({super.key, required this.menus, required this.child});

  final List<MenuBarMenu> menus;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (!Platform.isMacOS) return child;
    return PlatformMenuBar(
      menus: menus.map(_toPlatformMenu).toList(growable: false),
      child: child,
    );
  }
}

PlatformMenuItem _toPlatformMenu(MenuBarMenu menu) =>
    PlatformMenu(label: menu.label, menus: _toPlatformItems(menu.items));

/// Converte os itens agrupando por [MenuSeparator] em `PlatformMenuItemGroup`
/// (que é como o macOS desenha divisórias). Um único grupo dispensa o wrapper.
List<PlatformMenuItem> _toPlatformItems(List<MenuNode> items) {
  final groups = <List<PlatformMenuItem>>[<PlatformMenuItem>[]];
  for (final node in items) {
    switch (node) {
      case MenuSeparator():
        groups.add(<PlatformMenuItem>[]);
      case MenuBarMenu():
        groups.last.add(_toPlatformMenu(node));
      case MenuAction():
        groups.last.add(
          PlatformMenuItem(
            label: node.label,
            shortcut: node.accelerator?.resolve(),
            onSelected: node.onSelected == null
                ? null
                : () => node.onSelected!.call(),
          ),
        );
      case MenuRole():
        final type = _providedType(node.role);
        if (type != null) {
          groups.last.add(PlatformProvidedMenuItem(type: type));
        }
    }
  }

  final nonEmpty = groups.where((g) => g.isNotEmpty).toList(growable: false);
  if (nonEmpty.length <= 1) {
    return nonEmpty.isEmpty ? const <PlatformMenuItem>[] : nonEmpty.first;
  }
  return nonEmpty
      .map((g) => PlatformMenuItemGroup(members: g))
      .toList(growable: false);
}

PlatformProvidedMenuItemType? _providedType(MenuBarRole role) => switch (role) {
  MenuBarRole.about => PlatformProvidedMenuItemType.about,
  MenuBarRole.services => PlatformProvidedMenuItemType.servicesSubmenu,
  MenuBarRole.hide => PlatformProvidedMenuItemType.hide,
  MenuBarRole.hideOthers => PlatformProvidedMenuItemType.hideOtherApplications,
  MenuBarRole.showAll => PlatformProvidedMenuItemType.showAllApplications,
  MenuBarRole.quit => PlatformProvidedMenuItemType.quit,
  MenuBarRole.minimizeWindow => PlatformProvidedMenuItemType.minimizeWindow,
  MenuBarRole.zoomWindow => PlatformProvidedMenuItemType.zoomWindow,
};

// ===========================================================================
// WindowMenuBar — barra desenhada na janela (Windows/Linux).
// ===========================================================================

/// Barra de menu **desenhada dentro da janela**, para Windows/Linux (que não têm
/// barra de menu do SO alcançável pelo Flutter). Usa o `Menubar` do design
/// system, então casa com o tema do app e com a janela sem moldura. No macOS
/// não renderiza nada — lá a barra é a nativa via [AppMenuBar]. Pensado para ir
/// **dentro da barra de título** (estilo VS Code), ao lado do título.
class WindowMenuBar extends StatelessWidget {
  const WindowMenuBar({super.key, required this.menus});

  final List<MenuBarMenu> menus;

  @override
  Widget build(BuildContext context) {
    if (Platform.isMacOS) return const SizedBox.shrink();
    return Menubar(
      border: false,
      children: menus
          .map((m) => _windowMenu(context, m))
          .toList(growable: false),
    );
  }
}

MenuButton _windowMenu(BuildContext context, MenuBarMenu menu) => MenuButton(
  subMenu: _windowItems(context, menu.items),
  child: Text(menu.label, style: context.typo.label.copyWith(fontSize: 13)),
);

List<MenuItem> _windowItems(BuildContext context, List<MenuNode> items) {
  final out = <MenuItem>[];
  for (final node in items) {
    switch (node) {
      case MenuSeparator():
        // Evita divisória inicial/duplicada (roles omitidos podem deixar buracos).
        if (out.isNotEmpty && out.last is! MenuDivider) {
          out.add(const MenuDivider());
        }
      case MenuBarMenu():
        out.add(_windowMenu(context, node));
      case MenuAction():
        out.add(
          MenuButton(
            enabled: node.onSelected != null,
            trailing: node.accelerator == null
                ? null
                : MenuShortcut(activator: node.accelerator!.resolve()),
            onPressed: node.onSelected == null
                ? null
                : (_) => node.onSelected!.call(),
            child: Text(node.label),
          ),
        );
      case MenuRole():
        final action = _windowRole(node.role);
        if (action != null) {
          out.add(
            MenuButton(
              onPressed: (_) => action(),
              child: Text(_roleLabel(node.role)),
            ),
          );
        }
    }
  }
  // Remove divisória final pendente.
  if (out.isNotEmpty && out.last is MenuDivider) out.removeLast();
  return out;
}

/// Equivalente de janela dos papéis do SO. `null` = sem equivalente fora do
/// macOS (about/services/hide/…) → item omitido.
void Function()? _windowRole(MenuBarRole role) => switch (role) {
  MenuBarRole.quit => () => windowManager.close(),
  MenuBarRole.minimizeWindow => () => windowManager.minimize(),
  MenuBarRole.zoomWindow => () async {
    if (await windowManager.isMaximized()) {
      await windowManager.unmaximize();
    } else {
      await windowManager.maximize();
    }
  },
  _ => null,
};

String _roleLabel(MenuBarRole role) => switch (role) {
  MenuBarRole.quit => 'Quit',
  MenuBarRole.minimizeWindow => 'Minimize',
  MenuBarRole.zoomWindow => 'Zoom',
  _ => '',
};
