import 'package:cockpit/app/cockpit/domain/entities/workspace_presentation.dart';
import 'dart:io';

import 'package:cockpit/app/core/ui/menu/app_menu_bar.dart';
import 'package:cockpit/app/core/ui/menu/editor_menu_bridge.dart';
import 'package:cockpit/app/core/ui/menu/workspace_menu_bridge.dart';
import 'package:cockpit/app/core/ui/settings_controller.dart';
import 'package:cockpit/app/core/ui/widgets/window_controls.dart';
import 'package:cockpit/app/core/ui/themes/themes.dart';
import 'package:cockpit/i18n/strings.g.dart';
import 'package:cockpit/app/core/ui/widgets/hover_tap.dart';
import 'package:flutter_modular/flutter_modular.dart';
import 'package:cockpit/app/core/ui/widgets/app_tooltip.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';

/// Top bar (~46px) customizada — substitui a barra nativa da janela. Semáforo
/// macOS **funcional** (fecha/minimiza/maximiza) · toggle da rail · nome do
/// projeto. A barra inteira arrasta a janela (via [WindowTitleBar]).
class CockpitTopbar extends StatelessWidget {
  const CockpitTopbar({
    super.key,
    required this.projectName,
    required this.railVisible,
    required this.treeVisible,
    required this.onToggleRail,
    required this.onToggleTree,
    this.viewMode = WorkspaceViewMode.terminals,
    this.onViewChanged,
    this.onNewTerminal,
    this.onConfigure,
    this.inspectorOpen = false,
    this.filesEnabled = true,
  });

  final String projectName;
  final bool railVisible;
  final bool treeVisible;
  final VoidCallback onToggleRail;
  final VoidCallback onToggleTree;
  final WorkspaceViewMode viewMode;
  final ValueChanged<WorkspaceViewMode>? onViewChanged;
  final VoidCallback? onNewTerminal;
  final VoidCallback? onConfigure;
  final bool inspectorOpen;

  /// Habilita o botão de árvore de arquivos. `false` no workspace de sistema
  /// "Cockpit" (sem pasta → sem árvore): o botão fica visível porém inerte.
  final bool filesEnabled;

  String _modeLabel(BuildContext context, WorkspaceViewMode mode) =>
      switch (mode) {
        WorkspaceViewMode.terminals => context.t.workspaceView.terminals,
        WorkspaceViewMode.boxes => context.t.workspaceView.boxes,
        WorkspaceViewMode.graph => context.t.workspaceView.graph,
      };

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return WindowTitleBar(
      children: [
        const WindowControls(),
        // Folga do semáforo — só onde ele existe. No Windows/Linux o
        // [WindowControls] é `SizedBox.shrink()`, então isto separaria o
        // primeiro item de coisa nenhuma.
        if (Platform.isMacOS) const SizedBox(width: 12),
        // Windows/Linux: barra de menu desenhada na janela (estilo VS Code), ao
        // lado do título. No macOS o [WindowMenuBar] é no-op (barra é a nativa).
        if (!Platform.isMacOS) ...[
          WindowMenuBar(
            menus: buildAppMenus(
              context.t,
              context.watch<SettingsController>(),
              context.watch<EditorMenuBridge>(),
              context.watch<WorkspaceMenuBridge>(),
            ),
          ),
          const SizedBox(width: 8),
        ],
        _IconBtn(
          icon: Icons.view_sidebar_outlined,
          tooltip: context.t.cockpit.topbar.collapseSidebar,
          active: !railVisible,
          onTap: onToggleRail,
        ),
        const SizedBox(width: 8),
        Flexible(
          child: Text(
            projectName,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: context.typo.title.copyWith(
              fontSize: 14,
              color: colors.text,
            ),
          ),
        ),
        const Spacer(),
        if (onViewChanged != null) ...[
          for (final mode in WorkspaceViewMode.values)
            Padding(
              padding: const EdgeInsets.only(right: 4),
              child: AppTooltip(
                message: _modeLabel(context, mode),
                child: Semantics(
                  button: true,
                  selected: mode == viewMode,
                  child: OutlineButton(
                    onPressed: () => onViewChanged!(mode),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          switch (mode) {
                            WorkspaceViewMode.terminals => Icons.terminal,
                            WorkspaceViewMode.boxes => Icons.list_alt,
                            WorkspaceViewMode.graph =>
                              Icons.account_tree_outlined,
                          },
                          size: 16,
                          color: mode == viewMode
                              ? colors.accent
                              : colors.text3,
                        ),
                        if (MediaQuery.sizeOf(context).width >= 1050) ...[
                          const SizedBox(width: 6),
                          Text(_modeLabel(context, mode)),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
            ),
          const SizedBox(width: 8),
        ],
        if (onNewTerminal != null) ...[
          AppTooltip(
            message: context.t.workspaceView.newTerminal,
            child: PrimaryButton(
              onPressed: onNewTerminal,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.add, size: 16),
                  if (MediaQuery.sizeOf(context).width >= 1200) ...[
                    const SizedBox(width: 6),
                    Text(context.t.workspaceView.newTerminal),
                  ],
                ],
              ),
            ),
          ),
          const SizedBox(width: 8),
        ],
        if (onConfigure != null) ...[
          _IconBtn(
            icon: Icons.tune,
            tooltip: context.t.workspaceView.configure,
            active: inspectorOpen,
            onTap: onConfigure!,
          ),
          const SizedBox(width: 4),
        ],
        _IconBtn(
          icon: Icons.view_sidebar_outlined,
          tooltip: filesEnabled
              ? context.t.cockpit.topbar.toggleFiles
              : context.t.cockpit.topbar.filesUnavailable,
          active: !treeVisible && filesEnabled,
          enabled: filesEnabled,
          onTap: onToggleTree,
        ),
        const WindowControlsTrailing(),
      ],
    );
  }
}

class _IconBtn extends StatelessWidget {
  const _IconBtn({
    required this.icon,
    required this.tooltip,
    required this.onTap,
    this.active = false,
    this.enabled = true,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;
  final bool active;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final iconColor = !enabled
        ? colors.text3.withValues(alpha: 0.35)
        : (active ? colors.accentText : colors.text3);
    return AppTooltip(
      message: tooltip,
      child: HoverTap(
        onTap: enabled ? onTap : () {},
        color: active ? colors.accentSoft : null,
        hoverColor: enabled ? colors.panel3 : null,
        borderRadius: BorderRadius.circular(5),
        child: SizedBox(
          width: 28,
          height: 28,
          child: Icon(icon, size: 17, color: iconColor),
        ),
      ),
    );
  }
}
