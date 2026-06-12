import 'dart:io' show Platform;

import 'package:cockpit/domain/entities/git_info.dart';
import 'package:cockpit/domain/entities/project.dart';
import 'package:cockpit/ui/cockpit/widgets/app_menu.dart';
import 'package:cockpit/ui/cockpit/widgets/update_card.dart';
import 'package:cockpit/ui/core/themes/themes.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Rail esquerda (~252px): cabeçalho "Sessions", lista de projetos (avatar +
/// nome + git + contador de notificações), rodapé com a máquina.
class ProjectsRail extends StatefulWidget {
  const ProjectsRail({
    super.key,
    required this.projects,
    required this.worktreesOf,
    required this.selectedId,
    required this.notificationCount,
    required this.gitInfo,
    required this.onSelect,
    required this.onAdd,
    required this.onConfigure,
    required this.onDelete,
    required this.onCreateWorktree,
    required this.onRemoveWorktree,
    required this.onOpenSettings,
    this.width = 252,
  });

  /// Largura do painel (arrastável pela página — não persistida).
  final double width;

  /// Só os workspaces raiz; as worktrees vêm por [worktreesOf].
  final List<Project> projects;

  /// Worktrees (forks) de um workspace raiz, na ordem do git.
  final List<Project> Function(String rootId) worktreesOf;

  final String? selectedId;
  final int Function(String projectId) notificationCount;
  final GitInfo? Function(String projectId) gitInfo;
  final ValueChanged<String> onSelect;
  final Future<bool> Function() onAdd;
  final ValueChanged<Project> onConfigure;
  final ValueChanged<Project> onDelete;

  /// Abre o fluxo de criar worktree para um workspace (só raízes com git).
  final ValueChanged<Project> onCreateWorktree;

  /// Abre o fluxo de remover uma worktree (fork). A confirmação fica na page.
  final ValueChanged<Project> onRemoveWorktree;

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

  /// Os forks de um workspace, com `isLast` marcado pra linha de árvore fechar
  /// em "└" no último (a vertical dos demais segue até emendar com o próximo).
  List<Widget> _forkItems(Project project) {
    final forks = widget.worktreesOf(project.id);
    return [
      for (var i = 0; i < forks.length; i++)
        _WorktreeItem(
          worktree: forks[i],
          isLast: i == forks.length - 1,
          selected: forks[i].id == widget.selectedId,
          notifications: widget.notificationCount(forks[i].id),
          git: widget.gitInfo(forks[i].id),
          onTap: () => widget.onSelect(forks[i].id),
          onRemove: () => widget.onRemoveWorktree(forks[i]),
        ),
    ];
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
                    tooltip: 'New workspace',
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
                          for (final project in projects) ...[
                            _ProjectItem(
                              project: project,
                              selected: project.id == widget.selectedId,
                              notifications: widget.notificationCount(
                                project.id,
                              ),
                              git: widget.gitInfo(project.id),
                              // "Criar worktree" só faz sentido em repo git.
                              canCreateWorktree:
                                  widget.gitInfo(project.id) != null,
                              onTap: () => widget.onSelect(project.id),
                              onConfigure: () => widget.onConfigure(project),
                              onDelete: () => widget.onDelete(project),
                              onCreateWorktree: () =>
                                  widget.onCreateWorktree(project),
                            ),
                            // Worktrees (forks) penduradas abaixo do workspace,
                            // sempre expandidas (plan/42, decisões 5, 12).
                            ..._forkItems(project),
                          ],
                        ],
                      ),
                    ),
                  ),
          ),
          // Aviso de atualização in-app — acima do nome da máquina (passo 7).
          const UpdateCard(),
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
                    Platform.localHostname,
                    overflow: TextOverflow.ellipsis,
                    style: context.typo.label.copyWith(color: colors.text2),
                  ),
                ),
                _SmallIcon(
                  icon: Icons.settings_outlined,
                  tooltip: 'Settings',
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
    required this.canCreateWorktree,
    required this.onTap,
    required this.onConfigure,
    required this.onDelete,
    required this.onCreateWorktree,
  });

  final Project project;
  final bool selected;
  final int notifications;
  final GitInfo? git;
  final bool canCreateWorktree;
  final VoidCallback onTap;
  final VoidCallback onConfigure;
  final VoidCallback onDelete;
  final VoidCallback onCreateWorktree;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final gitInfo = git;
    return Tooltip(
      message: '${project.name}\n${project.path}',
      waitDuration: const Duration(milliseconds: 500),
      child: Padding(
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
                  _MenuButton(
                    canCreateWorktree: canCreateWorktree,
                    onConfigure: onConfigure,
                    onDelete: onDelete,
                    onCreateWorktree: onCreateWorktree,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Item de uma worktree (fork): pendurado abaixo do workspace pai por uma
/// **linha de árvore** (vertical contínua nos forks do meio, "└" no último),
/// sem avatar (o branch é a identidade). À direita, o sinal combinado de
/// dirtyCount + notificação (decisões 8, 16, 19) e o menu ⋮ "Remover". Hover
/// mostra tooltip com branch + path. A linha fica **fora** do realce do item.
class _WorktreeItem extends StatelessWidget {
  const _WorktreeItem({
    required this.worktree,
    required this.isLast,
    required this.selected,
    required this.notifications,
    required this.git,
    required this.onTap,
    required this.onRemove,
  });

  final Project worktree;

  /// `true` quando é a última worktree do pai → a linha vira "└" (vertical para
  /// no tick); nos do meio a vertical segue até o fim pra emendar com a próxima.
  final bool isLast;
  final bool selected;
  final int notifications;
  final GitInfo? git;
  final VoidCallback onTap;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Tooltip(
      message: '${worktree.name}\n${worktree.path}',
      waitDuration: const Duration(milliseconds: 500),
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Linha de árvore (fora do realce): preenche a altura do item, então
            // verticais de forks consecutivos se encostam → espinha contínua.
            SizedBox(
              width: 30,
              child: CustomPaint(
                painter: _ForkLinePainter(color: colors.border, isLast: isLast),
              ),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.only(bottom: 2),
                child: Material(
                  color: selected ? colors.panel2 : Colors.transparent,
                  borderRadius: BorderRadius.circular(7),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(7),
                    onTap: onTap,
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(0, 5, 7, 5),
                      child: Row(
                        children: [
                          Icon(Icons.call_split, size: 12, color: colors.text3),
                          const SizedBox(width: 7),
                          Expanded(
                            child: Text(
                              worktree.name,
                              overflow: TextOverflow.ellipsis,
                              style: context.typo.mono.copyWith(
                                fontSize: 12,
                                color: selected ? colors.text : colors.text2,
                                fontWeight: selected
                                    ? FontWeight.w500
                                    : FontWeight.w400,
                              ),
                            ),
                          ),
                          const SizedBox(width: 6),
                          _WorktreeSignal(
                            dirtyCount: git?.dirtyCount ?? 0,
                            hasNotification: notifications > 0,
                          ),
                          const SizedBox(width: 2),
                          _ForkMenuButton(
                            branch: worktree.name,
                            onRemove: onRemove,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Menu ⋮ compacto do fork — só "Remover" (plan/42, decisão 13).
class _ForkMenuButton extends StatelessWidget {
  const _ForkMenuButton({required this.branch, required this.onRemove});

  final String branch;
  final VoidCallback onRemove;

  Future<void> _show(BuildContext context) async {
    final pick = await showAppMenu<String>(
      context,
      items: const [
        AppMenuItem(
          value: 'copy',
          label: 'Copy branch',
          icon: Icons.content_copy,
        ),
        AppMenuItem(
          value: 'remove',
          label: 'Remove',
          icon: Icons.delete_outline,
          danger: true,
        ),
      ],
    );
    if (pick == 'copy') {
      await Clipboard.setData(ClipboardData(text: branch));
      if (context.mounted) {
        ScaffoldMessenger.maybeOf(context)?.showSnackBar(
          SnackBar(
            content: Text('Branch "$branch" copied'),
            duration: const Duration(seconds: 2),
          ),
        );
      }
    }
    if (pick == 'remove') onRemove();
  }

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: 'Options',
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapUp: (_) => _show(context),
          child: SizedBox(
            width: 22,
            height: 22,
            child: Icon(Icons.more_vert, size: 14, color: context.colors.text3),
          ),
        ),
      ),
    );
  }
}

/// Sinal à direita do fork. Sujo → badge âmbar com contador; limpo → ponto.
/// A notificação (agente terminou) se sobrepõe: no limpo, o ponto vira accent;
/// no sujo, ganha um dot accent no canto do badge.
class _WorktreeSignal extends StatelessWidget {
  const _WorktreeSignal({
    required this.dirtyCount,
    required this.hasNotification,
  });

  final int dirtyCount;
  final bool hasNotification;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final typo = context.typo;
    if (dirtyCount > 0) {
      return Stack(
        clipBehavior: Clip.none,
        children: [
          Container(
            constraints: const BoxConstraints(minWidth: 16),
            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
            decoration: BoxDecoration(
              color: colors.editedBg,
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(
              '$dirtyCount',
              textAlign: TextAlign.center,
              style: typo.mono.copyWith(
                fontSize: 10.5,
                color: colors.edited,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          if (hasNotification)
            Positioned(
              right: -2,
              top: -2,
              child: Container(
                width: 7,
                height: 7,
                decoration: BoxDecoration(
                  color: colors.accent,
                  shape: BoxShape.circle,
                  border: Border.all(color: colors.bg, width: 1.2),
                ),
              ),
            ),
        ],
      );
    }
    // Limpo: um ponto — accent quando há notificação, cinza caso contrário.
    return Container(
      width: 7,
      height: 7,
      margin: const EdgeInsets.only(right: 4),
      decoration: BoxDecoration(
        color: hasNotification ? colors.accent : colors.text3,
        shape: BoxShape.circle,
      ),
    );
  }
}

/// Linha de árvore ligando a worktree ao workspace pai (estética do mockup).
/// Preenche a altura do item (via `IntrinsicHeight` + `stretch`): a vertical em
/// [_x] vai até o fim nos forks do meio (emenda com o próximo → espinha
/// contínua) e para no centro ("└") no último; o tick horizontal liga ao item.
class _ForkLinePainter extends CustomPainter {
  _ForkLinePainter({required this.color, required this.isLast});
  final Color color;
  final bool isLast;

  /// Posição da espinha vertical (alinhada sob o workspace pai).
  static const double _x = 20;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1;
    final midY = size.height / 2;
    canvas.drawLine(
      Offset(_x, 0),
      Offset(_x, isLast ? midY : size.height),
      paint,
    );
    canvas.drawLine(Offset(_x, midY), Offset(size.width, midY), paint);
  }

  @override
  bool shouldRepaint(covariant _ForkLinePainter old) =>
      old.color != color || old.isLast != isLast;
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

/// Botão ⋮ compacto (26px, encostado na borda) com menu Criar worktree (só em
/// repo git) / Configurações / Deletar.
class _MenuButton extends StatelessWidget {
  const _MenuButton({
    required this.canCreateWorktree,
    required this.onConfigure,
    required this.onDelete,
    required this.onCreateWorktree,
  });

  final bool canCreateWorktree;
  final VoidCallback onConfigure;
  final VoidCallback onDelete;
  final VoidCallback onCreateWorktree;

  Future<void> _show(BuildContext context) async {
    final pick = await showAppMenu<String>(
      context,
      items: [
        // "Criar worktree" só aparece quando o workspace é um repo git.
        if (canCreateWorktree)
          const AppMenuItem(
            value: 'worktree',
            label: 'Create worktree',
            icon: Icons.call_split,
          ),
        const AppMenuItem(
          value: 'config',
          label: 'Settings',
          icon: Icons.settings_outlined,
        ),
        const AppMenuItem(
          value: 'delete',
          label: 'Delete',
          icon: Icons.delete_outline,
          danger: true,
        ),
      ],
    );
    if (pick == 'worktree') onCreateWorktree();
    if (pick == 'config') onConfigure();
    if (pick == 'delete') onDelete();
  }

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: 'Options',
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapUp: (_) => _show(context),
          child: SizedBox(
            width: 26,
            height: 26,
            child: Icon(Icons.more_vert, size: 16, color: context.colors.text3),
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
          'No workspaces yet.',
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
        mouseCursor: SystemMouseCursors.click,
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
