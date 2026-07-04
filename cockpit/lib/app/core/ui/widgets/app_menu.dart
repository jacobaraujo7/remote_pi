import 'package:cockpit/app/core/ui/themes/themes.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';

/// Um item de [showAppMenu]: ícone (opcional) à esquerda + rótulo, com check à
/// direita quando [selected] e cor de erro quando [danger] (ação destrutiva).
class AppMenuItem<T> {
  const AppMenuItem({
    required this.value,
    required this.label,
    this.icon,
    this.selected = false,
    this.danger = false,
    this.enabled = true,
  });

  final T value;
  final String label;
  final IconData? icon;
  final bool selected;
  final bool danger;

  /// `false` → item cinza, não clicável (não devolve o `value`).
  final bool enabled;
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
}) {
  final colors = context.colors;
  final anchored = globalPosition == null;

  final overlay = showPopover<T>(
    context: context,
    // Ponto do clique (menu de contexto) ou âncora no trigger (dropdown).
    position: globalPosition,
    alignment: Alignment.topLeft,
    anchorAlignment: anchored ? Alignment.bottomLeft : Alignment.topLeft,
    offset: anchored ? const Offset(0, 4) : null,
    builder: (context) => ConstrainedBox(
      constraints: BoxConstraints(minWidth: minWidth, maxWidth: 320),
      // DropdownMenu embrulha os MenuButton num MenuGroup (exigido) + MenuPopup.
      child: DropdownMenu(
        children: [
          for (final item in items)
            MenuButton(
              enabled: item.enabled,
              leading: item.icon != null
                  ? Icon(
                      item.icon,
                      size: 15,
                      color: !item.enabled
                          ? colors.text4
                          : (item.danger ? colors.error : colors.text3),
                    )
                  : null,
              trailing: item.selected
                  ? Icon(Icons.check, size: 14, color: colors.accentText)
                  : null,
              onPressed: (ctx) {
                closeOverlay<T>(ctx, item.value);
              },
              child: Text(
                item.label,
                overflow: TextOverflow.ellipsis,
                style: context.typo.body.copyWith(
                  fontSize: 13,
                  color: !item.enabled
                      ? colors.text4
                      : (item.danger ? colors.error : colors.text),
                ),
              ),
            ),
        ],
      ),
    ),
  );
  trackMenuOverlay(overlay);
  return overlay.future;
}
