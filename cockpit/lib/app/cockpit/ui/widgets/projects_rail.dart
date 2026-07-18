import 'package:cockpit/app/cockpit/domain/entities/git_info.dart';
import 'package:cockpit/app/cockpit/domain/entities/project.dart';
import 'package:cockpit/app/cockpit/domain/entities/realm.dart';
import 'package:cockpit/app/core/ui/widgets/app_menu.dart';
import 'package:cockpit/app/cockpit/ui/widgets/update_card.dart';
import 'package:cockpit/app/cockpit/ui/widgets/workspace_avatar.dart';
import 'package:cockpit/app/core/ui/themes/themes.dart';
import 'package:cockpit/app/core/ui/widgets/hover_tap.dart';
import 'package:flutter/services.dart' show Clipboard, ClipboardData;
import 'package:cockpit/app/core/ui/widgets/app_tooltip.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';

/// Root git de um workspace, pro kebab da rail: path absoluto + basename +
/// branch (`null` = pasta sem git). Multi-root tem 2+; single-root, 1.
typedef RailRoot = ({String path, String name, String? branch});

/// Destino possível de "Move to realm" no kebab: [enabled] = `false` quando o
/// path do workspace já existe no realm alvo (um path por realm).
typedef RealmTarget = ({String id, String name, bool enabled});

/// Rail esquerda (~252px): cabeçalho "Sessions", lista de projetos (avatar +
/// nome + git + contador de notificações), rodapé com o seletor de realm.
class ProjectsRail extends StatefulWidget {
  const ProjectsRail({
    super.key,
    required this.projects,
    required this.worktreesOf,
    required this.selectedId,
    required this.notificationCount,
    required this.gitInfo,
    required this.rootsSummary,
    required this.rootsOf,
    required this.forkOriginName,
    required this.onSelect,
    required this.onAdd,
    required this.onConfigure,
    required this.onDelete,
    required this.onCreateWorktree,
    required this.onRemoveWorktree,
    required this.onMergeWorktree,
    required this.onUpdateWorktree,
    required this.onForkWorktree,
    required this.onSync,
    required this.onPull,
    required this.onPush,
    required this.onOpenSettings,
    required this.onReorder,
    required this.realms,
    required this.activeRealm,
    required this.onSwitchRealm,
    required this.onCreateRealm,
    required this.onManageRealms,
    required this.moveTargetsOf,
    required this.onMoveToRealm,
    this.cockpit,
    required this.onSelectCockpit,
    this.width = 252,
  });

  /// Largura do painel (arrastável pela página — não persistida).
  final double width;

  /// Só os workspaces raiz; as worktrees vêm por [worktreesOf].
  final List<Project> projects;

  /// O workspace de sistema "Cockpit" (terminal-only), renderizado num slot
  /// fixo no topo, separado da lista de projetos. `null` quando desabilitado.
  final Project? cockpit;

  /// Seleciona o workspace de sistema "Cockpit".
  final VoidCallback onSelectCockpit;

  /// Worktrees (forks) de um workspace raiz, na ordem do git.
  final List<Project> Function(String rootId) worktreesOf;

  final String? selectedId;
  final int Function(String projectId) notificationCount;
  final GitInfo? Function(String projectId) gitInfo;

  /// Agregado multi-root: (nº de roots, roots sujas). Só é lido quando
  /// [gitInfo] devolve `null` e o workspace tem 2+ roots (multirepo).
  final (int, int) Function(String projectId) rootsSummary;

  /// Roots git do workspace (path, basename, branch|null) — alimenta os
  /// **submenus** das ações git do kebab em multi-root. Single-root: 1 item.
  final List<RailRoot> Function(String projectId) rootsOf;

  /// Basename da root que originou um fork (só em pai multi-root; senão
  /// `null`) — vira o sufixo `(backend)` no item da worktree.
  final String? Function(String forkId) forkOriginName;

  /// Realms na ordem do dropdown do footer; [activeRealm] é o recorte exibido.
  final List<Realm> realms;
  final Realm activeRealm;
  final void Function(String realmId) onSwitchRealm;
  final VoidCallback onCreateRealm;
  final VoidCallback onManageRealms;

  /// Destinos de "Move to realm" pro kebab do workspace (todos os realms menos
  /// o atual do projeto). Vazio (0 ou 1 realm) esconde o item do menu.
  final List<RealmTarget> Function(String projectId) moveTargetsOf;
  final void Function(String projectId, String realmId) onMoveToRealm;
  final ValueChanged<String> onSelect;
  final Future<bool> Function() onAdd;
  final ValueChanged<Project> onConfigure;
  final ValueChanged<Project> onDelete;

  /// Abre o fluxo de criar worktree para um workspace (só raízes com git).
  /// Abre o fluxo de criar worktree em [rootPath] (multi-root: a root escolhida
  /// no submenu; single-root: a própria raiz).
  final void Function(Project project, String rootPath) onCreateWorktree;

  /// Abre o fluxo de remover uma worktree (fork). A confirmação fica na page.
  final ValueChanged<Project> onRemoveWorktree;

  /// Mergeia a branch do worktree (fork) no workspace pai.
  final ValueChanged<Project> onMergeWorktree;

  /// "Update from Parent": mergeia a branch do pai no worktree (fork).
  final ValueChanged<Project> onUpdateWorktree;

  /// "Fork Worktree": nova worktree ramificada da branch deste fork.
  final ValueChanged<Project> onForkWorktree;

  /// Ações git no workspace, direcionadas a [rootPath] (multi-root: escolhida
  /// no submenu do kebab; single-root: a própria raiz, sem perguntar).
  final void Function(Project project, String rootPath) onSync;
  final void Function(Project project, String rootPath) onPull;
  final void Function(Project project, String rootPath) onPush;

  /// Abre a tela de Configurações (engrenagem no rodapé).
  final VoidCallback onOpenSettings;

  /// Reordena workspaces: move [movedId] para antes/depois de [targetId].
  final void Function(String movedId, String targetId, bool before) onReorder;

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
          originName: widget.forkOriginName(forks[i].id),
          isLast: i == forks.length - 1,
          selected: forks[i].id == widget.selectedId,
          notifications: widget.notificationCount(forks[i].id),
          git: widget.gitInfo(forks[i].id),
          onTap: () => widget.onSelect(forks[i].id),
          onRemove: () => widget.onRemoveWorktree(forks[i]),
          onMerge: () => widget.onMergeWorktree(forks[i]),
          onUpdate: () => widget.onUpdateWorktree(forks[i]),
          onFork: () => widget.onForkWorktree(forks[i]),
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
                // "+" sempre visível: com o Cockpit fixo no topo o rail nunca
                // fica realmente vazio, e criar workspace precisa estar à mão.
                _SmallIcon(
                  icon: Icons.add,
                  tooltip: 'New workspace',
                  onTap: () => onAdd(),
                ),
              ],
            ),
          ),
          // Slot fixo do workspace de sistema "Cockpit" (terminal-only), acima
          // e separado da lista de projetos. Sem avatar/imagem, sem menu ⋮.
          if (widget.cockpit != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 0, 8, 4),
              child: _CockpitSlot(
                selected: widget.cockpit!.id == widget.selectedId,
                onTap: widget.onSelectCockpit,
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
                            _WorkspaceReorderable(
                              projectId: project.id,
                              title: project.name,
                              colorValue: project.colorValue,
                              initial: project.initial,
                              imagePath: project.imagePath,
                              onReorder: widget.onReorder,
                              child: _ProjectItem(
                                project: project,
                                selected: project.id == widget.selectedId,
                                notifications: widget.notificationCount(
                                  project.id,
                                ),
                                git: widget.gitInfo(project.id),
                                rootsSummary: widget.rootsSummary(project.id),
                                // "Criar worktree" só faz sentido em repo git
                                // (single ou multi-root — na multi a page pede
                                // a root alvo antes).
                                canCreateWorktree:
                                    widget.gitInfo(project.id) != null ||
                                    widget.rootsSummary(project.id).$1 > 1,
                                onTap: () => widget.onSelect(project.id),
                                onConfigure: () => widget.onConfigure(project),
                                onDelete: () => widget.onDelete(project),
                                roots: widget.rootsOf(project.id),
                                onCreateWorktree: (r) =>
                                    widget.onCreateWorktree(project, r),
                                onSync: (r) => widget.onSync(project, r),
                                onPull: (r) => widget.onPull(project, r),
                                onPush: (r) => widget.onPush(project, r),
                                moveTargets: widget.moveTargetsOf(project.id),
                                onMoveToRealm: (realmId) =>
                                    widget.onMoveToRealm(project.id, realmId),
                              ),
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
            // Mesma altura do footer do file viewer (34) pra alinhar a base.
            height: 34,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            decoration: BoxDecoration(
              border: Border(top: BorderSide(color: colors.border)),
            ),
            child: Row(
              children: [
                Expanded(
                  child: _RealmSelector(
                    realms: widget.realms,
                    active: widget.activeRealm,
                    onSwitch: widget.onSwitchRealm,
                    onCreate: widget.onCreateRealm,
                    onManage: widget.onManageRealms,
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

/// Slot fixo do workspace de sistema "Cockpit": glifo de terminal + rótulo, sem
/// avatar/imagem, sem menu de contexto (não é um projeto — não pode ser
/// renomeado, excluído nem virar worktree). Selecionável como os demais.
class _CockpitSlot extends StatelessWidget {
  const _CockpitSlot({required this.selected, required this.onTap});

  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return HoverTap(
      color: selected ? colors.panel2 : Colors.transparent,
      borderRadius: BorderRadius.circular(7),
      onTap: onTap,
      padding: const EdgeInsets.fromLTRB(9, 7, 9, 7),
      child: Row(
        children: [
          Container(
            width: 30,
            height: 30,
            decoration: BoxDecoration(
              color: colors.panel,
              borderRadius: BorderRadius.circular(7),
              border: Border.all(color: colors.border),
            ),
            child: Icon(Icons.terminal, size: 17, color: colors.text2),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'Cockpit',
              overflow: TextOverflow.ellipsis,
              style: context.typo.body.copyWith(
                fontSize: 13.5,
                color: colors.text,
                fontWeight: selected ? FontWeight.w500 : FontWeight.w400,
              ),
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
    required this.rootsSummary,
    required this.roots,
    required this.canCreateWorktree,
    required this.onTap,
    required this.onConfigure,
    required this.onDelete,
    required this.onCreateWorktree,
    required this.onSync,
    required this.onPull,
    required this.onPush,
    required this.moveTargets,
    required this.onMoveToRealm,
  });

  final Project project;
  final bool selected;
  final int notifications;
  final GitInfo? git;

  /// Agregado multi-root (nº de roots, roots sujas) — usado no lugar do
  /// [_GitBadge] quando [git] é `null` e há 2+ roots.
  final (int, int) rootsSummary;

  /// Roots do workspace (submenu das ações git em multi-root).
  final List<RailRoot> roots;
  final bool canCreateWorktree;
  final VoidCallback onTap;
  final VoidCallback onConfigure;
  final VoidCallback onDelete;
  final void Function(String rootPath) onCreateWorktree;
  final void Function(String rootPath) onSync;
  final void Function(String rootPath) onPull;
  final void Function(String rootPath) onPush;

  /// Realms de destino do "Move to realm" (vazio esconde o item).
  final List<RealmTarget> moveTargets;
  final void Function(String realmId) onMoveToRealm;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final gitInfo = git;
    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: HoverTap(
        color: selected ? colors.panel2 : Colors.transparent,
        borderRadius: BorderRadius.circular(7),
        onTap: onTap,
        padding: const EdgeInsets.fromLTRB(9, 7, 5, 7),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            WorkspaceAvatar(
              imagePath: project.imagePath,
              colorValue: project.colorValue,
              initial: project.initial,
              size: 30,
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
                      fontWeight: selected ? FontWeight.w500 : FontWeight.w400,
                    ),
                  ),
                  // Linha do git — repo git (branch) ou multi-root (agregado);
                  // pasta comum não mostra nada.
                  if (gitInfo != null) ...[
                    const SizedBox(height: 4),
                    _GitBadge(info: gitInfo),
                  ] else if (rootsSummary.$1 > 1) ...[
                    const SizedBox(height: 4),
                    _MultiRootBadge(
                      roots: rootsSummary.$1,
                      dirtyRoots: rootsSummary.$2,
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 6),
            if (notifications > 0) ...[
              Container(
                constraints: const BoxConstraints(minWidth: 18),
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
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
              workspaceId: project.id,
              canCreateWorktree: canCreateWorktree,
              roots: roots,
              onConfigure: onConfigure,
              onDelete: onDelete,
              onCreateWorktree: onCreateWorktree,
              onSync: onSync,
              onPull: onPull,
              onPush: onPush,
              moveTargets: moveTargets,
              onMoveToRealm: onMoveToRealm,
            ),
          ],
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
    required this.originName,
    required this.isLast,
    required this.selected,
    required this.notifications,
    required this.git,
    required this.onTap,
    required this.onRemove,
    required this.onMerge,
    required this.onUpdate,
    required this.onFork,
  });

  final Project worktree;

  /// Basename da root de origem (só em pai multi-root) → sufixo `(backend)`
  /// pra desambiguar forks de roots diferentes com a mesma branch.
  final String? originName;

  /// `true` quando é a última worktree do pai → a linha vira "└" (vertical para
  /// no tick); nos do meio a vertical segue até o fim pra emendar com a próxima.
  final bool isLast;
  final bool selected;
  final int notifications;
  final GitInfo? git;
  final VoidCallback onTap;
  final VoidCallback onRemove;
  final VoidCallback onMerge;
  final VoidCallback onUpdate;
  final VoidCallback onFork;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return IntrinsicHeight(
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
              child: HoverTap(
                color: selected ? colors.panel2 : Colors.transparent,
                borderRadius: BorderRadius.circular(7),
                onTap: onTap,
                padding: const EdgeInsets.fromLTRB(0, 5, 7, 5),
                child: Row(
                  children: [
                    Icon(Icons.call_split, size: 12, color: colors.text3),
                    const SizedBox(width: 7),
                    Expanded(
                      child: Text.rich(
                        TextSpan(
                          text: worktree.name,
                          children: [
                            // Sufixo `(root)` só em pai multi-root: diz de
                            // qual repo o fork nasceu (branch pode repetir).
                            if (originName != null)
                              TextSpan(
                                text: '  ($originName)',
                                style: context.typo.mono.copyWith(
                                  fontSize: 11,
                                  color: colors.text3,
                                ),
                              ),
                          ],
                        ),
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
                      onMerge: onMerge,
                      onUpdate: onUpdate,
                      onFork: onFork,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Menu ⋮ compacto do fork — só "Remover" (plan/42, decisão 13).
class _ForkMenuButton extends StatelessWidget {
  const _ForkMenuButton({
    required this.branch,
    required this.onRemove,
    required this.onMerge,
    required this.onUpdate,
    required this.onFork,
  });

  final String branch;
  final VoidCallback onRemove;
  final VoidCallback onMerge;
  final VoidCallback onUpdate;
  final VoidCallback onFork;

  Future<void> _show(BuildContext context) async {
    final pick = await showAppMenu<String>(
      context,
      items: const [
        AppMenuItem(
          value: 'merge',
          label: 'Merge to Parent',
          icon: Icons.merge_type,
        ),
        // Inverso do Merge to Parent: traz a branch do pai pro worktree
        // ("Update branch" do GitHub). Conflito fica no worktree.
        AppMenuItem(
          value: 'update',
          label: 'Update from Parent',
          icon: Icons.download_outlined,
        ),
        // Nova worktree ramificada da branch DESTE fork (não do HEAD do
        // pai) — vira irmão na lista, herdando o layout deste fork.
        AppMenuItem(
          value: 'fork',
          label: 'Fork Worktree',
          icon: Icons.call_split,
        ),
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
    if (pick == 'merge') onMerge();
    if (pick == 'update') onUpdate();
    if (pick == 'fork') onFork();
    if (pick == 'copy') {
      await Clipboard.setData(ClipboardData(text: branch));
    }
    if (pick == 'remove') onRemove();
  }

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
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
/// Chip agregado de um workspace **multi-root** (multirepo): nº de roots +
/// quantas estão sujas. As branches individuais moram na árvore de arquivos —
/// aqui só "esse projeto tem coisa pendente?". Mesma linguagem do [_GitBadge].
class _MultiRootBadge extends StatelessWidget {
  const _MultiRootBadge({required this.roots, required this.dirtyRoots});
  final int roots;
  final int dirtyRoots;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final typo = context.typo;
    final dirty = dirtyRoots > 0;
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
          Icon(Icons.account_tree_outlined, size: 9, color: fg),
          const SizedBox(width: 3),
          Text(
            dirty ? '$roots roots · $dirtyRoots' : '$roots roots',
            style: typo.mono.copyWith(
              fontSize: 9.5,
              color: fg,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}

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
          if (info.behind > 0) ...[
            const SizedBox(width: 4),
            _AheadBehind(glyph: '↓', count: info.behind, color: colors.warn),
          ],
          if (info.ahead > 0) ...[
            const SizedBox(width: 3),
            _AheadBehind(
              glyph: '↑',
              count: info.ahead,
              color: colors.accentText,
            ),
          ],
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

/// Indicador compacto de commits à frente (`↑`) / atrás (`↓`) do upstream.
class _AheadBehind extends StatelessWidget {
  const _AheadBehind({
    required this.glyph,
    required this.count,
    required this.color,
  });
  final String glyph;
  final int count;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Text(
      '$glyph$count',
      style: context.typo.mono.copyWith(
        fontSize: 9.5,
        color: color,
        fontWeight: FontWeight.w700,
      ),
    );
  }
}

/// Botão ⋮ compacto (26px, encostado na borda) com menu Criar worktree (só em
/// repo git) / Configurações / Deletar.
class _MenuButton extends StatelessWidget {
  const _MenuButton({
    required this.workspaceId,
    required this.canCreateWorktree,
    required this.roots,
    required this.onConfigure,
    required this.onDelete,
    required this.onCreateWorktree,
    required this.onSync,
    required this.onPull,
    required this.onPush,
    required this.moveTargets,
    required this.onMoveToRealm,
  });

  /// Id do workspace (`projectId`) — copiável pra usar na CLI `cockpit`
  /// (`--workspace-id` / filtros de `list-panes`).
  final String workspaceId;
  final bool canCreateWorktree;

  /// Roots git do workspace. 2+ → as ações git viram **submenu** (escolhe a
  /// root ali mesmo); 1 → executam direto nela (comportamento histórico).
  final List<RailRoot> roots;
  final VoidCallback onConfigure;
  final VoidCallback onDelete;
  final void Function(String rootPath) onCreateWorktree;
  final void Function(String rootPath) onSync;
  final void Function(String rootPath) onPull;
  final void Function(String rootPath) onPush;

  /// Realms de destino do "Move to realm" (vazio = 0/1 realm → item oculto).
  /// Destino com o mesmo path já presente vem desabilitado (um path por realm).
  final List<RealmTarget> moveTargets;
  final void Function(String realmId) onMoveToRealm;

  /// Item de ação git: single-root executa direto (`<ação>|<root>`); multi-root
  /// abre submenu com uma entrada por root (roots sem git desabilitadas).
  AppMenuItem<String> _gitItem(String action, String label, IconData icon) {
    final gitRoots = roots.where((r) => r.branch != null).toList();
    if (roots.length <= 1) {
      final path = roots.isEmpty ? '' : roots.first.path;
      return AppMenuItem(value: '$action|$path', label: label, icon: icon);
    }
    return AppMenuItem(
      value: action, // nunca devolvido — só os filhos
      label: label,
      icon: icon,
      children: [
        for (final r in gitRoots)
          AppMenuItem(
            value: '$action|${r.path}',
            label: '${r.name}  ⎇ ${r.branch}',
            icon: Icons.folder_outlined,
          ),
      ],
    );
  }

  Future<void> _show(BuildContext context) async {
    final pick = await showAppMenu<String>(
      context,
      items: [
        // Ações de sincronização só quando há git (single ou multi-root).
        if (canCreateWorktree) ...[
          _gitItem('sync', 'Sync', Icons.sync),
          _gitItem('pull', 'Pull', Icons.arrow_downward),
          _gitItem('push', 'Push', Icons.arrow_upward),
          _gitItem('worktree', 'Create worktree', Icons.call_split),
        ],
        if (moveTargets.isNotEmpty)
          AppMenuItem(
            value: 'realm', // nunca devolvido — só os filhos
            label: 'Move to realm',
            icon: Icons.public,
            children: [
              for (final t in moveTargets)
                AppMenuItem(
                  value: 'realm|${t.id}',
                  label: t.name,
                  enabled: t.enabled,
                ),
            ],
          ),
        const AppMenuItem(
          value: 'copy-id',
          label: 'Copy workspace id',
          icon: Icons.content_copy,
        ),
        const AppMenuItem(
          value: 'config',
          label: 'Settings',
          icon: Icons.settings_outlined,
        ),
        const AppMenuItem(
          value: 'delete',
          label: 'Close',
          icon: Icons.close,
          danger: true,
        ),
      ],
    );
    if (pick == null) return;
    final sep = pick.indexOf('|');
    if (sep > 0) {
      final action = pick.substring(0, sep);
      final arg = pick.substring(sep + 1); // root path (git) ou realm id
      if (arg.isEmpty) return;
      if (action == 'sync') onSync(arg);
      if (action == 'pull') onPull(arg);
      if (action == 'push') onPush(arg);
      if (action == 'worktree') onCreateWorktree(arg);
      if (action == 'realm') onMoveToRealm(arg);
      return;
    }
    if (pick == 'copy-id') {
      await Clipboard.setData(ClipboardData(text: workspaceId));
    }
    if (pick == 'config') onConfigure();
    if (pick == 'delete') onDelete();
  }

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
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
    return AppTooltip(
      message: tooltip,
      child: HoverTap(
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

/// Seletor de realm do rodapé: dot verde + nome do realm ativo + chevron.
/// Clique abre o dropdown com todos os realms (check no ativo), "New realm…"
/// e "Manage realms…". Substituiu o hostname da máquina (que virava lixo de
/// DHCP tipo `708cf2c41346`).
class _RealmSelector extends StatelessWidget {
  const _RealmSelector({
    required this.realms,
    required this.active,
    required this.onSwitch,
    required this.onCreate,
    required this.onManage,
  });

  final List<Realm> realms;
  final Realm active;
  final void Function(String realmId) onSwitch;
  final VoidCallback onCreate;
  final VoidCallback onManage;

  Future<void> _open(BuildContext context) async {
    final pick = await showAppMenu<String>(
      context,
      minWidth: 180,
      items: [
        for (final realm in realms)
          AppMenuItem(
            value: 'r|${realm.id}',
            label: realm.name,
            icon: Icons.public,
            selected: realm.id == active.id,
          ),
        const AppMenuItem.divider(),
        const AppMenuItem(
          value: '__new__',
          label: 'New realm…',
          icon: Icons.add,
        ),
        const AppMenuItem(
          value: '__manage__',
          label: 'Manage realms…',
          icon: Icons.tune,
        ),
      ],
    );
    if (pick == null) return;
    if (pick == '__new__') {
      onCreate();
    } else if (pick == '__manage__') {
      onManage();
    } else if (pick.startsWith('r|')) {
      onSwitch(pick.substring(2));
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Align(
      alignment: Alignment.centerLeft,
      child: HoverTap(
        borderRadius: BorderRadius.circular(5),
        onTap: () => _open(context),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
          child: Row(
            mainAxisSize: MainAxisSize.min,
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
              Flexible(
                child: Text(
                  active.name,
                  overflow: TextOverflow.ellipsis,
                  style: context.typo.label.copyWith(color: colors.text2),
                ),
              ),
              const SizedBox(width: 4),
              Icon(Icons.expand_more, size: 14, color: colors.text3),
            ],
          ),
        ),
      ),
    );
  }
}

/// Torna um item de workspace arrastável para **reordenar** os workspaces no
/// rail. Mostra um caret horizontal (acima/abaixo) sob o cursor enquanto outro
/// workspace é arrastado por cima e, ao soltar, dispara [onReorder]. Só vale
/// para workspaces raiz — worktrees não entram (têm `_forkItems` próprio).
class _WorkspaceReorderable extends StatefulWidget {
  const _WorkspaceReorderable({
    required this.projectId,
    required this.title,
    required this.colorValue,
    required this.initial,
    required this.imagePath,
    required this.onReorder,
    required this.child,
  });

  final String projectId;
  final String title;
  final int colorValue;
  final String initial;
  final String? imagePath;
  final void Function(String movedId, String targetId, bool before) onReorder;
  final Widget child;

  @override
  State<_WorkspaceReorderable> createState() => _WorkspaceReorderableState();
}

class _WorkspaceReorderableState extends State<_WorkspaceReorderable> {
  /// `null` = sem caret; `true` = caret acima (antes); `false` = abaixo (depois).
  bool? _before;

  void _update(Offset global) {
    final box = context.findRenderObject() as RenderBox?;
    if (box == null || !box.hasSize) return;
    final local = box.globalToLocal(global);
    final before = local.dy < box.size.height / 2;
    if (before != _before) setState(() => _before = before);
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return DragTarget<String>(
      onWillAcceptWithDetails: (d) => d.data != widget.projectId,
      onMove: (d) => _update(d.offset),
      onLeave: (_) {
        if (_before != null) setState(() => _before = null);
      },
      onAcceptWithDetails: (d) {
        final before = _before ?? true;
        setState(() => _before = null);
        widget.onReorder(d.data, widget.projectId, before);
      },
      builder: (context, candidate, rejected) {
        final caret = candidate.isNotEmpty ? _before : null;
        return Stack(
          children: [
            // Click-drag imediato pra reposicionar (sem segurar). No desktop a
            // rolagem do rail é via roda/trackpad (PointerScroll, não gesto de
            // arrasto), então o Draggable imediato não briga com o scroll; o tap
            // continua selecionando e o botão de menu continua abrindo.
            Draggable<String>(
              data: widget.projectId,
              dragAnchorStrategy: pointerDragAnchorStrategy,
              feedback: Transform.translate(
                offset: const Offset(10, 8),
                child: _WorkspaceDragChip(
                  title: widget.title,
                  colorValue: widget.colorValue,
                  initial: widget.initial,
                  imagePath: widget.imagePath,
                ),
              ),
              childWhenDragging: Opacity(opacity: 0.3, child: widget.child),
              child: widget.child,
            ),
            if (caret != null)
              Positioned(
                left: 8,
                right: 8,
                top: caret ? 0 : null,
                bottom: caret ? null : 2,
                child: Container(
                  height: 2.5,
                  decoration: BoxDecoration(
                    color: colors.accent,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}

/// Chip que segue o cursor ao arrastar um workspace (avatar + nome).
class _WorkspaceDragChip extends StatelessWidget {
  const _WorkspaceDragChip({
    required this.title,
    required this.colorValue,
    required this.initial,
    required this.imagePath,
  });

  final String title;
  final int colorValue;
  final String initial;
  final String? imagePath;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Container(
      constraints: const BoxConstraints(maxWidth: 220),
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 7),
      decoration: BoxDecoration(
        color: colors.panel2,
        borderRadius: BorderRadius.circular(7),
        border: Border.all(color: colors.accent),
        boxShadow: const [
          BoxShadow(
            color: Color(0x55000000),
            blurRadius: 12,
            offset: Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          WorkspaceAvatar(
            imagePath: imagePath,
            colorValue: colorValue,
            initial: initial,
            size: 22,
            radius: 6,
          ),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              title,
              overflow: TextOverflow.ellipsis,
              style: context.typo.label.copyWith(color: colors.text),
            ),
          ),
        ],
      ),
    );
  }
}
