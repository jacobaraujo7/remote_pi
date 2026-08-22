import 'package:cockpit/app/core/ui/themes/themes.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';

/// Um item de [showAppMenu]: ícone (opcional) à esquerda + rótulo, com check à
/// direita quando [selected] e cor de erro quando [danger] (ação destrutiva).
class AppMenuItem<T> {
  const AppMenuItem({
    required T this.value,
    required this.label,
    this.icon,
    this.leading,
    this.labelWidget,
    this.selected = false,
    this.danger = false,
    this.enabled = true,
    this.children,
  }) : isDivider = false;

  /// Separador visual entre grupos de itens ([MenuDivider] do shadcn). Nunca é
  /// clicável nem devolve valor.
  const AppMenuItem.divider()
    : value = null,
      label = '',
      icon = null,
      leading = null,
      labelWidget = null,
      selected = false,
      danger = false,
      enabled = false,
      children = null,
      isDivider = true;

  /// Nulo apenas em [AppMenuItem.divider] — o construtor padrão exige `T`.
  final T? value;
  final String label;
  final IconData? icon;

  /// Widget de ícone à esquerda (ex.: logo SVG). Vence [icon] quando presente.
  final Widget? leading;

  /// Rótulo rico opcional. Quando presente, substitui [label].
  final Widget? labelWidget;
  final bool selected;
  final bool danger;

  /// `false` → item cinza, não clicável (não devolve o `value`).
  final bool enabled;

  /// Submenu: o item vira um cabeçalho `›` que abre estes filhos ao lado
  /// (nativo do shadcn). O `value` do PRÓPRIO item nunca é devolvido — só o
  /// dos filhos escolhidos.
  final List<AppMenuItem<T>>? children;

  final bool isDivider;
}

/// Popover de menu atualmente aberto. O `showPopover` do shadcn **não** fecha
/// sozinho quando outro abre (um clique-direito num segundo item dispara o
/// `onSecondaryTapUp` antes do barrier dismissar o primeiro), então rastreamos o
/// menu ativo e fechamos o anterior antes de abrir o novo — só um por vez.
OverlayCompleter<dynamic>? _activeMenu;

/// Registra [overlay] como o menu ativo, fechando o anterior se ainda estiver
/// aberto. Usado por [showAppMenu] e por outros popovers de menu do app (ex.: o
/// dropdown de "Open" da topbar) para garantir um único menu aberto por vez.
void trackMenuOverlay(OverlayCompleter<dynamic> overlay) {
  if (_activeMenu?.isCompleted == false) _activeMenu!.remove();
  _activeMenu = overlay;
}

/// Menu popup **compacto** (shadcn). Por padrão ancora no widget que chamou (via
/// [context]): abre logo **abaixo** do trigger — ideal pra botões. Passando
/// [globalPosition] (ex.: `onSecondaryTapUp(d).globalPosition`), abre no **ponto
/// do clique** — ideal pra menu de contexto (botão direito). O popover do shadcn
/// inverte sozinho se não couber. Ícone à esquerda, check à direita do
/// selecionado. Devolve o `value` escolhido (ou `null`).
///
/// Componente único do app — todos os menus passam por aqui.
Future<T?> showAppMenu<T>(
  BuildContext context, {
  required List<AppMenuItem<T>> items,
  double minWidth = 200,
  Offset? globalPosition,
  String? searchHint,
  int searchThreshold = 12,
  int? collapsedLimit,
}) {
  final colors = context.colors;
  final anchored = globalPosition == null;

  // Mesmo TapRegion group pro menu raiz e pro submenu: clique no submenu não
  // conta como "fora" do menu raiz (senão o barrier dismissaria antes do item
  // do submenu processar o clique).
  final groupId = Object();

  // Submenu aberto (no máximo um) — abrimos nós mesmos pra controlar o
  // TapRegion group e o fechamento junto com o menu raiz.
  OverlayCompleter<void>? subMenu;
  void closeSubMenu() {
    if (subMenu?.isCompleted == false) subMenu!.remove();
    subMenu = null;
  }

  // Ponto do clique em coordenadas de janela — o handler do app converte pro
  // espaço do overlay (ver [AppPopoverOverlayHandler]).
  final Offset? position = globalPosition;

  /// Abre os filhos de [item] ao lado do próprio item ([itemContext]).
  /// A escolha de um filho resolve o future do MENU raiz ([menuContext]).
  void openSubMenu(
    BuildContext menuContext,
    BuildContext itemContext,
    AppMenuItem<T> item,
  ) {
    closeSubMenu();
    final box = itemContext.findRenderObject();
    if (box is! RenderBox) return;
    // Top-right do item + respiro.
    final anchor = box.localToGlobal(Offset(box.size.width, 0));
    subMenu = showPopover<void>(
      context: itemContext,
      position: anchor + const Offset(4, -6),
      follow: false,
      alignment: Alignment.topLeft,
      modal: false,
      consumeOutsideTaps: false,
      dismissBackdropFocus: false,
      regionGroupId: groupId,
      builder: (subContext) => ConstrainedBox(
        constraints: const BoxConstraints(minWidth: 180, maxWidth: 320),
        child: DropdownMenu(
          children: [
            for (final child in item.children!)
              MenuButton(
                enabled: child.enabled,
                leading: child.icon != null
                    ? Icon(
                        child.icon,
                        size: 15,
                        color: !child.enabled ? colors.text4 : colors.text3,
                      )
                    : null,
                onPressed: (_) {
                  closeSubMenu();
                  closeOverlay<T>(menuContext, child.value);
                },
                child: Text(
                  child.label,
                  overflow: TextOverflow.ellipsis,
                  style: subContext.typo.body.copyWith(
                    fontSize: 13,
                    color: !child.enabled ? colors.text4 : colors.text,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  final overlay = showPopover<T>(
    context: context,
    // Ponto do clique (menu de contexto) ou âncora no trigger (dropdown).
    position: position,
    // Com posição explícita, `follow` precisa ser false: o default (true)
    // liga um ticker que recalcula a posição A PARTIR DO WIDGET âncora a cada
    // frame, sobrescrevendo o ponto do clique — o menu "grudava" no top-left
    // do item em vez de abrir no cursor.
    follow: anchored,
    alignment: Alignment.topLeft,
    anchorAlignment: anchored ? Alignment.bottomLeft : Alignment.topLeft,
    offset: anchored ? const Offset(0, 4) : null,
    regionGroupId: groupId,
    builder: (menuContext) {
      // DropdownMenu embrulha os MenuButton num MenuGroup (exigido) + MenuPopup.
      Widget buildMenu(List<AppMenuItem<T>> visible) => DropdownMenu(
        children: [
          for (final item in visible)
            if (item.isDivider)
              const MenuDivider()
            else
              // Wrapper hover-aware (o DropdownMenu só aceita MenuItem): o
              // context do wrapper é a âncora do submenu, e o hover replica o
              // comportamento nativo — item com filhos abre o submenu, item
              // comum fecha o que estiver aberto.
              _AppMenuEntry(
                hasLeading: item.leading != null || item.icon != null,
                onEnter: (itemContext) => item.children != null && item.enabled
                    ? openSubMenu(menuContext, itemContext, item)
                    : closeSubMenu(),
                child: MenuButton(
                  enabled: item.enabled,
                  leading:
                      item.leading ??
                      (item.icon != null
                          ? Icon(
                              item.icon,
                              size: 15,
                              color: !item.enabled
                                  ? colors.text4
                                  : (item.danger ? colors.error : colors.text3),
                            )
                          : null),
                  trailing: item.selected
                      ? Icon(Icons.check, size: 14, color: colors.accentText)
                      : (item.children != null
                            ? Icon(
                                Icons.chevron_right,
                                size: 14,
                                color: colors.text3,
                              )
                            : null),
                  // Com filhos, o clique no pai não escolhe nada — só abre o
                  // submenu (redundante com o hover, cobre toque/teclado).
                  onPressed: item.children != null
                      ? (ctx) => openSubMenu(menuContext, ctx, item)
                      : (ctx) {
                          closeOverlay<T>(ctx, item.value);
                        },
                  child:
                      item.labelWidget ??
                      Text(
                        item.label,
                        overflow: TextOverflow.ellipsis,
                        style: menuContext.typo.body.copyWith(
                          fontSize: 13,
                          color: !item.enabled
                              ? colors.text4
                              : (item.danger ? colors.error : colors.text),
                        ),
                      ),
                ),
              ),
        ],
      );

      // Lista longa (catálogo de modelos de um harness, por exemplo) ganha um
      // campo de filtro no topo: sem ele o usuário rola dezenas de itens.
      final searchable = searchHint != null && items.length > searchThreshold;
      return ConstrainedBox(
        // maxHeight: sem teto o menu crescia além da tela e as últimas opções
        // ficavam inalcançáveis (comum no mobile/tela pequena). O MenuPopup do
        // shadcn tem SingleChildScrollView interno, então limitar a altura já
        // liga o scroll. ~78% da tela deixa margem pro trigger/bordas.
        constraints: BoxConstraints(
          minWidth: minWidth,
          maxWidth: 320,
          maxHeight: MediaQuery.sizeOf(menuContext).height * 0.78,
        ),
        child: searchable
            ? _SearchableMenu<T>(
                items: items,
                hint: searchHint,
                collapsedLimit: collapsedLimit,
                buildMenu: buildMenu,
              )
            : buildMenu(items),
      );
    },
  );
  // Fechar o menu raiz (escolha, ESC, clique fora ou outro menu abrindo via
  // trackMenuOverlay) derruba o submenu junto.
  overlay.future.whenComplete(closeSubMenu);
  trackMenuOverlay(overlay);
  return overlay.future;
}

/// Entrada do [showAppMenu]: um [MenuButton] com hover observável. Implementa
/// [MenuItem] porque o `DropdownMenu` só aceita filhos dessa interface; o
/// [onEnter] recebe o context DESTE widget (mesmo RenderBox do item), usado
/// como âncora do submenu.
class _AppMenuEntry extends StatelessWidget implements MenuItem {
  const _AppMenuEntry({
    required this.hasLeading,
    required this.onEnter,
    required this.child,
  });

  @override
  final bool hasLeading;

  final void Function(BuildContext itemContext) onEnter;
  final Widget child;

  @override
  PopoverController? get popoverController => null;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(onEnter: (_) => onEnter(context), child: child);
  }
}

/// Menu com filtro por texto. O campo fica acima do popup (mesma pilha visual
/// de um command palette) e casa por substring no rótulo e no `value` — em
/// catálogo de modelo o id costuma ser o que a pessoa lembra, não o label.
class _SearchableMenu<T> extends StatefulWidget {
  const _SearchableMenu({
    required this.items,
    required this.hint,
    required this.buildMenu,
    this.collapsedLimit,
  });

  final List<AppMenuItem<T>> items;
  final String hint;

  /// Quantos itens mostrar antes de o usuário digitar. Catálogo de modelo do
  /// cursor-agent passa de 200 entradas — rolar tudo é pior que buscar. A
  /// busca continua alcançando a lista inteira.
  final int? collapsedLimit;

  final Widget Function(List<AppMenuItem<T>> visible) buildMenu;

  @override
  State<_SearchableMenu<T>> createState() => _SearchableMenuState<T>();
}

class _SearchableMenuState<T> extends State<_SearchableMenu<T>> {
  final TextEditingController _controller = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  List<AppMenuItem<T>> get _visible {
    final query = _query.trim().toLowerCase();
    if (query.isEmpty) {
      final limit = widget.collapsedLimit;
      return limit == null || widget.items.length <= limit
          ? widget.items
          : widget.items.take(limit).toList();
    }
    return [
      for (final item in widget.items)
        if (!item.isDivider &&
            (item.label.toLowerCase().contains(query) ||
                '${item.value}'.toLowerCase().contains(query)))
          item,
    ];
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          margin: const EdgeInsets.only(bottom: 4),
          decoration: BoxDecoration(
            color: colors.panel,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: colors.border),
          ),
          padding: const EdgeInsets.all(6),
          child: TextField(
            controller: _controller,
            autofocus: true,
            placeholder: Text(
              widget.hint,
              style: context.typo.body.copyWith(
                fontSize: 13,
                color: colors.text4,
              ),
            ),
            style: context.typo.body.copyWith(fontSize: 13, color: colors.text),
            border: Border.all(color: colors.border),
            borderRadius: BorderRadius.circular(6),
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            onChanged: (value) => setState(() => _query = value),
          ),
        ),
        Flexible(child: widget.buildMenu(_visible)),
      ],
    );
  }
}
