import 'package:cockpit/domain/entities/git_info.dart';
import 'package:cockpit/domain/entities/project.dart';
import 'package:cockpit/ui/cockpit/widgets/app_menu.dart';
import 'package:cockpit/ui/core/themes/themes.dart';
import 'package:flutter/material.dart';

/// Rail esquerda (~252px): cabeçalho "Sessions", lista de projetos (avatar +
/// nome + git + contador de notificações), rodapé com a máquina.
class ProjectsRail extends StatefulWidget {
  const ProjectsRail({
    super.key,
    required this.projects,
    required this.selectedId,
    required this.notificationCount,
    required this.gitInfo,
    required this.onSelect,
    required this.onAdd,
    required this.onConfigure,
    required this.onDelete,
    required this.onOpenSettings,
    this.width = 252,
  });

  /// Largura do painel (arrastável pela página — não persistida).
  final double width;

  final List<Project> projects;
  final String? selectedId;
  final int Function(String projectId) notificationCount;
  final GitInfo? Function(String projectId) gitInfo;
  final ValueChanged<String> onSelect;
  final Future<bool> Function() onAdd;
  final ValueChanged<Project> onConfigure;
  final ValueChanged<Project> onDelete;

  /// Abre a tela de Configurações (engrenagem no rodapé).
  final VoidCallback onOpenSettings;

  @override
  State<ProjectsRail> createState() => _ProjectsRailState();
}

class _ProjectsRailState extends State<ProjectsRail> {
  final ScrollController _scroll = ScrollController();

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final projects = widget.projects;
    final onAdd = widget.onAdd;
    return Container(
      width: widget.width,
      decoration: BoxDecoration(
        color: colors.bg,
        border: Border(right: BorderSide(color: colors.border)),
      ),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 12, 12),
            child: Row(
              children: [
                Icon(Icons.layers_outlined, size: 16, color: colors.text2),
                const SizedBox(width: 9),
                Text(
                  'Workspaces',
                  style: context.typo.title.copyWith(color: colors.text),
                ),
                const Spacer(),
                // Sem "+" quando não há workspace: a criação fica centralizada
                // no onboarding da tela vazia.
                if (projects.isNotEmpty)
                  _SmallIcon(
                    icon: Icons.add,
                    tooltip: 'Novo workspace',
                    onTap: () => onAdd(),
                  ),
              ],
            ),
          ),
          Expanded(
            child: projects.isEmpty
                ? const _EmptyRail()
                : Scrollbar(
                    controller: _scroll,
                    thumbVisibility: true,
                    child: ScrollConfiguration(
                      behavior: ScrollConfiguration.of(
                        context,
                      ).copyWith(scrollbars: false),
                      child: ListView(
                        controller: _scroll,
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                        children: [
                          for (final project in projects)
                            _ProjectItem(
                              project: project,
                              selected: project.id == widget.selectedId,
                              notifications: widget.notificationCount(project.id),
                              git: widget.gitInfo(project.id),
                              onTap: () => widget.onSelect(project.id),
                              onConfigure: () => widget.onConfigure(project),
                              onDelete: () => widget.onDelete(project),
                            ),
                        ],
                      ),
                    ),
                  ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              border: Border(top: BorderSide(color: colors.border)),
            ),
            child: Row(
              children: [
                Container(
                  width: 7,
                  height: 7,
                  decoration: BoxDecoration(
                    color: colors.online,
                    shape: BoxShape.circle,
                    boxShadow: [BoxShadow(color: colors.online, blurRadius: 8)],
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'MBP-de-jacob',
                    overflow: TextOverflow.ellipsis,
                    style: context.typo.label.copyWith(color: colors.text2),
                  ),
                ),
                _SmallIcon(
                  icon: Icons.settings_outlined,
                  tooltip: 'Configurações',
                  onTap: widget.onOpenSettings,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ProjectItem extends StatelessWidget {
  const _ProjectItem({
    required this.project,
    required this.selected,
    required this.notifications,
    required this.git,
    required this.onTap,
    required this.onConfigure,
    required this.onDelete,
  });

  final Project project;
  final bool selected;
  final int notifications;
  final GitInfo? git;
  final VoidCallback onTap;
  final VoidCallback onConfigure;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final gitInfo = git;
    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: Material(
        color: selected ? colors.panel2 : Colors.transparent,
        borderRadius: BorderRadius.circular(7),
        child: InkWell(
          borderRadius: BorderRadius.circular(7),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(9, 7, 5, 7),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Container(
                  width: 30,
                  height: 30,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: Color(project.colorValue),
                    borderRadius: BorderRadius.circular(7),
                  ),
                  child: Text(
                    project.initial,
                    style: context.typo.title.copyWith(
                      fontSize: 13,
                      color: Colors.white,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        project.name,
                        overflow: TextOverflow.ellipsis,
                        style: context.typo.body.copyWith(
                          fontSize: 13.5,
                          color: colors.text,
                          fontWeight: selected
                              ? FontWeight.w500
                              : FontWeight.w400,
                        ),
                      ),
                      // Linha do git — só quando é repo git (senão, só o título).
                      if (gitInfo != null) ...[
                        const SizedBox(height: 4),
                        _GitBadge(info: gitInfo),
                      ],
                    ],
                  ),
                ),
                const SizedBox(width: 6),
                if (notifications > 0) ...[
                  Container(
                    constraints: const BoxConstraints(minWidth: 18),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 1,
                    ),
                    decoration: BoxDecoration(
                      color: colors.accent,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      '$notifications',
                      textAlign: TextAlign.center,
                      style: context.typo.mono.copyWith(
                        fontSize: 11,
                        color: Colors.white,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  const SizedBox(width: 4),
                ],
                _MenuButton(onConfigure: onConfigure, onDelete: onDelete),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Pílula de git: ícone de branch + nome do branch + nº de arquivos sujos.
/// Sujo → âmbar com contador; limpo → cinza, sem número.
class _GitBadge extends StatelessWidget {
  const _GitBadge({required this.info});
  final GitInfo info;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final typo = context.typo;
    final dirty = info.isDirty;
    final fg = dirty ? colors.warn : colors.text3;
    final bg = dirty ? colors.editedBg : colors.panel3;
    return Container(
      padding: const EdgeInsets.fromLTRB(4, 1, 5, 1),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.call_split, size: 9, color: fg),
          const SizedBox(width: 3),
          Flexible(
            child: Text(
              info.branch,
              overflow: TextOverflow.ellipsis,
              style: typo.mono.copyWith(
                fontSize: 9.5,
                color: fg,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          if (dirty) ...[
            const SizedBox(width: 4),
            Text(
              '${info.dirtyCount}',
              style: typo.mono.copyWith(
                fontSize: 9.5,
                color: colors.edited,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Botão ⋮ compacto (26px, encostado na borda) com menu Configurações/Deletar.
class _MenuButton extends StatelessWidget {
  const _MenuButton({required this.onConfigure, required this.onDelete});

  final VoidCallback onConfigure;
  final VoidCallback onDelete;

  Future<void> _show(BuildContext context) async {
    final pick = await showAppMenu<String>(
      context,
      items: const [
        AppMenuItem(
          value: 'config',
          label: 'Configurações',
          icon: Icons.settings_outlined,
        ),
        AppMenuItem(
          value: 'delete',
          label: 'Deletar',
          icon: Icons.delete_outline,
          danger: true,
        ),
      ],
    );
    if (pick == 'config') onConfigure();
    if (pick == 'delete') onDelete();
  }

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: 'Opções',
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapUp: (_) => _show(context),
          child: SizedBox(
            width: 26,
            height: 26,
            child: Icon(
              Icons.more_vert,
              size: 16,
              color: context.colors.text3,
            ),
          ),
        ),
      ),
    );
  }
}

class _EmptyRail extends StatelessWidget {
  const _EmptyRail();

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Text(
          'Nenhum workspace ainda.',
          textAlign: TextAlign.center,
          style: context.typo.label.copyWith(color: colors.text3),
        ),
      ),
    );
  }
}

class _SmallIcon extends StatelessWidget {
  const _SmallIcon({
    required this.icon,
    required this.tooltip,
    required this.onTap,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Tooltip(
      message: tooltip,
      child: InkWell(
        borderRadius: BorderRadius.circular(5),
        onTap: onTap,
        child: SizedBox(
          width: 26,
          height: 26,
          child: Icon(icon, size: 16, color: colors.text3),
        ),
      ),
    );
  }
}
