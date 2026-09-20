import 'dart:io' show Platform;

import 'package:cockpit/app/core/utils/platform_kind.dart';

import 'package:cockpit/app/core/app_intents.dart';
import 'package:cockpit/app/core/ui/menu/editor_menu_bridge.dart';
import 'package:cockpit/app/core/ui/menu/menu_model.dart';
import 'package:cockpit/app/core/ui/menu/workspace_menu_bridge.dart';
import 'package:cockpit/app/core/ui/settings_controller.dart';
import 'package:cockpit/app/core/ui/widgets/app_menu.dart';
import 'package:cockpit/app/core/ui/widgets/hover_tap.dart';
import 'package:cockpit/i18n/strings.g.dart';
import 'package:cockpit/app/core/ui/themes/themes.dart';
import 'package:flutter/services.dart' show LogicalKeyboardKey;
import 'package:shadcn_flutter/shadcn_flutter.dart';
import 'package:window_manager/window_manager.dart';

// ===========================================================================
// Definição única do menu do app (fonte de verdade para os dois renderers).
// ===========================================================================

/// Teclas 1…8 dos atalhos "Select Tab" (⌘1…⌘8). O ⌘9 é tratado à parte como
/// "Last Tab" (convenção de browsers/iTerm: pula pra última aba, não pra 9ª).
const List<LogicalKeyboardKey> _tabDigitKeys = <LogicalKeyboardKey>[
  LogicalKeyboardKey.digit1,
  LogicalKeyboardKey.digit2,
  LogicalKeyboardKey.digit3,
  LogicalKeyboardKey.digit4,
  LogicalKeyboardKey.digit5,
  LogicalKeyboardKey.digit6,
  LogicalKeyboardKey.digit7,
  LogicalKeyboardKey.digit8,
];

/// Monta a árvore de menus do app. Recebe [t] (as traduções) em vez de ler
/// `context.t`: a função é pura e roda fora de um `build`. Quem chama é o
/// `AppRoot`, dentro do `build`, então trocar de idioma remonta a barra.
/// Referencia só o `core`: o [controller]
/// (zoom/tamanho da interface) e as pontes globais de `app_intents.dart` (abrir
/// configurações/projeto, checar updates) — resolvidas pelo `CockpitPage`, então
/// `null`-safe enquanto o shell não montou.
List<MenuBarMenu> buildAppMenus(
  Translations t,
  SettingsController controller,
  EditorMenuBridge editor,
  WorkspaceMenuBridge workspace,
) {
  final tr = t.core.menu;
  void zoom(double delta) => controller.setInterfaceSize(
    (controller.settings.interfaceSize + delta).clamp(11.0, 22.0),
  );

  return <MenuBarMenu>[
    // 1ª entrada = menu do app (no macOS o SO rotula com o nome do app).
    MenuBarMenu('Cockpit', <MenuNode>[
      const MenuRole(MenuBarRole.about),
      const MenuSeparator(),
      MenuAction(
        tr.settings,
        accelerator: const MenuAccelerator(LogicalKeyboardKey.comma),
        onSelected: () => requestOpenSettings?.call(),
      ),
      MenuAction(
        tr.checkForUpdates,
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
    MenuBarMenu(tr.file, <MenuNode>[
      // New Terminal abre uma aba no workspace ativo (via CockpitPage →
      // newTabIn). Só habilita quando há workspace selecionado.
      // No mobile o "+" da aba cria terminal e o "+" do rail abre workspace —
      // esses itens de menu são redundantes (plano 60, Wave F).
      if (!isMobilePlatform)
        MenuAction(
          tr.newTerminal,
          onSelected: workspace.hasWorkspace ? workspace.newTerminal : null,
        ),
      if (!isMobilePlatform) const MenuSeparator(),
      if (!isMobilePlatform)
        MenuAction(
          tr.openWorkspace,
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
        tr.save,
        accelerator: const MenuAccelerator(LogicalKeyboardKey.keyS),
        shortcutHandledExternally: true,
        onSelected: editor.canSave ? editor.save : null,
      ),
      MenuAction(
        tr.discard,
        onSelected: editor.canDiscard ? editor.discard : null,
      ),
      MenuAction(
        tr.format,
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
    MenuBarMenu(tr.view, <MenuNode>[
      // Layout do workspace (ativos só com workspace aberto). Aceleradores reais:
      // no macOS o menu nativo dispara; fora dele o `menuShortcuts` registra.
      // No mobile os toggles viram os drawers (por largura) e o split fica no
      // kebab da pane — itens de menu redundantes.
      if (!isMobilePlatform)
        MenuAction(
          tr.toggleWorkspacePanel,
          accelerator: const MenuAccelerator(LogicalKeyboardKey.keyB),
          onSelected: workspace.hasWorkspace ? workspace.toggleRail : null,
        ),
      if (!isMobilePlatform)
        MenuAction(
          tr.toggleFiles,
          accelerator: const MenuAccelerator(
            LogicalKeyboardKey.keyB,
            shift: true,
          ),
          onSelected: workspace.hasWorkspace ? workspace.toggleFiles : null,
        ),
      if (!isMobilePlatform) const MenuSeparator(),
      if (!isMobilePlatform)
        MenuAction(
          tr.splitRight,
          accelerator: const MenuAccelerator(LogicalKeyboardKey.keyD),
          onSelected: workspace.hasWorkspace ? workspace.splitRight : null,
        ),
      if (!isMobilePlatform)
        MenuAction(
          tr.splitDown,
          accelerator: const MenuAccelerator(
            LogicalKeyboardKey.keyD,
            shift: true,
          ),
          onSelected: workspace.hasWorkspace ? workspace.splitDown : null,
        ),
      if (!isMobilePlatform) const MenuSeparator(),
      // Seleção de aba (⌘1…⌘9) vive no menu de propósito: no macOS só o menu
      // **nativo** captura atalho de forma confiável quando o terminal/campo tem
      // foco (um `CallbackShortcuts` de página é engolido pelo widget focado).
      // Já o "Focus Pane" (⌘⌥ + setas) NÃO leva acelerador de menu: setas não
      // funcionam como key equivalent no macOS (o campo focado consome a seta
      // antes do menu), então quem trata a tecla é um handler global do
      // HardwareKeyboard no `CockpitPage`. Aqui ficam só os itens clicáveis (com
      // o hint da tecla no rótulo, já que o menu não desenha acelerador nenhum).
      // Focar painel e Selecionar aba: só fazem sentido com teclado/atalho —
      // no mobile o toque já seleciona painel/aba direto.
      if (!isMobilePlatform)
        MenuBarMenu(tr.focusPane, <MenuNode>[
          MenuAction(
            tr.focusLeft,
            onSelected: workspace.hasWorkspace ? workspace.focusPaneLeft : null,
          ),
          MenuAction(
            tr.focusRight,
            onSelected: workspace.hasWorkspace
                ? workspace.focusPaneRight
                : null,
          ),
          MenuAction(
            tr.focusUp,
            onSelected: workspace.hasWorkspace ? workspace.focusPaneUp : null,
          ),
          MenuAction(
            tr.focusDown,
            onSelected: workspace.hasWorkspace ? workspace.focusPaneDown : null,
          ),
        ]),
      if (!isMobilePlatform)
        MenuBarMenu(tr.selectTab, <MenuNode>[
          for (var i = 0; i < _tabDigitKeys.length; i++)
            MenuAction(
              tr.tabN(n: i + 1),
              accelerator: MenuAccelerator(_tabDigitKeys[i]),
              onSelected: workspace.hasWorkspace
                  ? () => workspace.selectTab(i)
                  : null,
            ),
          MenuAction(
            tr.lastTab,
            accelerator: const MenuAccelerator(LogicalKeyboardKey.digit9),
            onSelected: workspace.hasWorkspace ? workspace.selectLastTab : null,
          ),
        ]),
      // Troca de workspace pelo teclado (⇧⌘N volta, ⇧⌘M avança): N e M são
      // vizinhas, esquerda/direita. Sem dígitos de propósito: o rail inclui
      // worktrees e a posição muda o tempo todo; anterior/próximo é estável.
      // Com Shift, a combinação nunca chega ao terminal (⌃N/⌃M sem Shift
      // continuam livres pra readline/vim/fzf).
      if (!isMobilePlatform) const MenuSeparator(),
      if (!isMobilePlatform)
        MenuAction(
          tr.previousWorkspace,
          accelerator: const MenuAccelerator(
            LogicalKeyboardKey.keyN,
            shift: true,
          ),
          onSelected: workspace.hasWorkspace
              ? workspace.previousWorkspace
              : null,
        ),
      if (!isMobilePlatform)
        MenuAction(
          tr.nextWorkspace,
          accelerator: const MenuAccelerator(
            LogicalKeyboardKey.keyM,
            shift: true,
          ),
          onSelected: workspace.hasWorkspace ? workspace.nextWorkspace : null,
        ),
      if (!isMobilePlatform) const MenuSeparator(),
      MenuAction(
        tr.zoomIn,
        accelerator: const MenuAccelerator(LogicalKeyboardKey.equal),
        shortcutHandledExternally: true,
        onSelected: () => zoom(1),
      ),
      MenuAction(
        tr.zoomOut,
        accelerator: const MenuAccelerator(LogicalKeyboardKey.minus),
        shortcutHandledExternally: true,
        onSelected: () => zoom(-1),
      ),
      MenuAction(
        tr.actualSize,
        accelerator: const MenuAccelerator(LogicalKeyboardKey.digit0),
        shortcutHandledExternally: true,
        onSelected: () => controller.setInterfaceSize(14),
      ),
    ]),
    MenuBarMenu(tr.window, const <MenuNode>[
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

/// Menu **desenhado dentro da janela**, para Windows/Linux (que não têm barra de
/// menu do SO alcançável pelo Flutter). Usa o `Menubar` do design system, então
/// casa com o tema do app e com a janela sem moldura. No macOS não renderiza
/// nada — lá a barra é a nativa via [AppMenuBar]. Vai **dentro da barra de
/// título**, ao lado do título.
///
/// **Um botão só (hambúrguer), não uma fileira de menus.** A barra de título do
/// Windows/Linux é disputada: os botões de janela (minimizar/maximizar/fechar)
/// moram nela, à direita, e `File`/`View`/`Window` lado a lado espremiam o
/// título e encostavam neles. O macOS não tem esse problema (a barra é do SO,
/// fora da janela) — por isso o aperto é só aqui. Então os menus de topo viram
/// **submenus** de um único botão: clique → popup com `Cockpit`/`File`/`View`/
/// `Window`, cada um abrindo os próprios itens.
///
/// O modelo ([MenuBarMenu]) não muda: só este renderer aninha um nível a mais.
/// A barra nativa do macOS segue plana, como o SO espera.
class WindowMenuBar extends StatefulWidget {
  const WindowMenuBar({
    super.key,
    required this.menus,
    this.renderOnMacOS = false,
  });

  final List<MenuBarMenu> menus;

  /// Só pros testes: força o desenho no macOS (a suíte roda em mac, e sem isto
  /// o widget seria um `SizedBox` e nada seria exercitado).
  @visibleForTesting
  final bool renderOnMacOS;

  @override
  State<WindowMenuBar> createState() => _WindowMenuBarState();
}

class _WindowMenuBarState extends State<WindowMenuBar> {
  bool _open = false;

  /// Momento em que o menu fechou por último. Se o MESMO toque que dismissou o
  /// barrier também atinge o botão, ele reabriria — este guard descarta o toque
  /// que chega logo após o fechamento (bug de "reabre em vez de fechar").
  DateTime? _closedAt;

  Future<void> _toggle(BuildContext anchor) async {
    // Já aberto: o barrier fecha o menu; não reabrimos.
    if (_open) return;
    final closed = _closedAt;
    if (closed != null &&
        DateTime.now().difference(closed) < const Duration(milliseconds: 300)) {
      return;
    }
    setState(() => _open = true);
    // ACHATADO (não submenus): no touch, submenu aninhado é ruim de acertar E
    // a escolha de uma folha de submenu se perde na corrida com o `closeAll` do
    // shadcn (a ação não dispararia). Os grupos (Cockpit/File/View/Window) viram
    // seções separadas por divisória, e cada item é folha de topo — que fecha o
    // menu raiz com o valor certo e executa a ação.
    final items = <AppMenuItem<VoidCallback>>[];
    for (final m in widget.menus) {
      final section = _toAppItems(context, m.items);
      if (section.isEmpty) continue;
      if (items.isNotEmpty && !items.last.isDivider) {
        items.add(const AppMenuItem<VoidCallback>.divider());
      }
      items.addAll(section);
    }
    final action = await showAppMenu<VoidCallback>(anchor, items: items);
    if (mounted) {
      setState(() {
        _open = false;
        _closedAt = DateTime.now();
      });
    }
    action?.call();
  }

  @override
  Widget build(BuildContext context) {
    if (Platform.isMacOS && !widget.renderOnMacOS) {
      return const SizedBox.shrink();
    }
    final colors = context.colors;
    // Builder pra o showAppMenu ancorar no PRÓPRIO botão (abre logo abaixo).
    return Builder(
      builder: (btnContext) => HoverTap(
        onTap: () => _toggle(btnContext),
        color: _open ? colors.accentSoft : null,
        hoverColor: colors.panel,
        borderRadius: BorderRadius.circular(5),
        child: SizedBox(
          width: 28,
          height: 28,
          child: Icon(
            Icons.menu,
            size: 16,
            color: _open ? colors.accentText : colors.text3,
          ),
        ),
      ),
    );
  }
}

void _noop() {}

/// Converte a árvore declarativa ([MenuNode]) pros itens do [showAppMenu] (nosso
/// menu, com toggle correto). Cada folha carrega sua ação como `value`
/// (VoidCallback), invocada quando o item é escolhido.
List<AppMenuItem<VoidCallback>> _toAppItems(
  BuildContext context,
  List<MenuNode> items,
) {
  final out = <AppMenuItem<VoidCallback>>[];
  for (final node in items) {
    switch (node) {
      case MenuSeparator():
        if (out.isNotEmpty && !out.last.isDivider) {
          out.add(const AppMenuItem<VoidCallback>.divider());
        }
      case MenuBarMenu():
        out.add(
          AppMenuItem<VoidCallback>(
            value: _noop,
            label: node.label,
            children: _toAppItems(context, node.items),
          ),
        );
      case MenuAction():
        out.add(
          AppMenuItem<VoidCallback>(
            value: node.onSelected ?? _noop,
            label: node.label,
            enabled: node.onSelected != null,
          ),
        );
      case MenuRole():
        final action = _windowRole(node.role);
        if (action != null) {
          out.add(
            AppMenuItem<VoidCallback>(
              value: action,
              label: _roleLabel(context, node.role),
            ),
          );
        }
    }
  }
  if (out.isNotEmpty && out.last.isDivider) out.removeLast();
  return out;
}

/// Equivalente de janela dos papéis do SO. `null` = sem equivalente fora do
/// macOS (about/services/hide/…) → item omitido. No mobile (iPad/Android) não
/// há janela nem `window_manager`: todos os papéis de janela são omitidos.
void Function()? _windowRole(MenuBarRole role) {
  if (isMobilePlatform) return null;
  return switch (role) {
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
}

/// Rótulo dos roles que a barra **desenhada** (Windows/Linux) renderiza. Os
/// demais roles são omitidos ali: só existem como item nativo no macOS.
String _roleLabel(BuildContext context, MenuBarRole role) => switch (role) {
  MenuBarRole.quit => context.t.core.menu.quit,
  MenuBarRole.minimizeWindow => context.t.core.menu.minimize,
  MenuBarRole.zoomWindow => context.t.core.menu.zoom,
  _ => '',
};
