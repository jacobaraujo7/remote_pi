import 'package:cockpit/app/cockpit/domain/entities/git_info.dart';
import 'package:cockpit/app/cockpit/domain/entities/project.dart';
import 'package:cockpit/app/cockpit/domain/entities/realm.dart';
import 'package:cockpit/app/core/ui/widgets/app_menu.dart';
import 'package:cockpit/app/cockpit/ui/widgets/update_card.dart';
import 'package:cockpit/app/cockpit/ui/widgets/workspace_avatar.dart';
import 'package:cockpit/app/core/ui/themes/themes.dart';
import 'package:cockpit/app/core/utils/platform_kind.dart';
import 'package:cockpit/i18n/strings.g.dart';
import 'package:cockpit/app/core/ui/widgets/hover_tap.dart';
import 'package:flutter/services.dart' show Clipboard, ClipboardData;
import 'package:cockpit/app/core/ui/widgets/app_tooltip.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';

/// Root git de um workspace, pra rail (kebab + popup do badge multi-root):
/// path absoluto + basename + estado git (`null` = pasta sem git). Multi-root
/// tem 2+; single-root, 1.
typedef RailRoot = ({String path, String name, GitInfo? git});

/// Destino possível de "Move to realm" no kebab: [enabled] = `false` quando o
/// path do workspace já existe no realm alvo (um path por realm).
typedef RealmTarget = ({String id, String name, bool enabled});

/// Branch da root em [rootPath], ou `null` se a root sumiu da lista ou não é
/// um repo git.
///
/// Existe separada porque é a única decisão real do "Copiar branch": em
/// multirepo o menu devolve `copy-branch|<root>` e alguém precisa traduzir esse
/// path de volta para a branch — sem inventar uma "branch do workspace", que
/// não existe quando cada root está numa.
@visibleForTesting
String? branchOfRoot(List<RailRoot> roots, String rootPath) {
  for (final root in roots) {
    if (root.path == rootPath) {
      final branch = root.git?.branch;
      return (branch == null || branch.isEmpty) ? null : branch;
    }
  }
  return null;
}

/// O que um clique no **card** do workspace faz (V37). `select` = selecionar o
/// workspace; `expand` = novo estado da lista de worktrees (`null` = não mexer,
/// caso do workspace sem fork nenhum — não há lista a alternar).
///
/// Não selecionado → seleciona e já deixa a lista aberta (uma ação, dois
/// resultados). Já selecionado → o clique só alterna a lista.
@visibleForTesting
({bool select, bool? expand}) workspaceCardTap({
  required bool selected,
  required bool expanded,
  required bool hasWorktrees,
}) {
  if (!hasWorktrees) return (select: !selected, expand: null);
  // Selecionar nunca recolhe: o clique que traz o workspace pra frente abre a
  // lista junto. Já selecionado, esse mesmo clique passa a ser só o toggle.
  return (select: !selected, expand: selected ? !expanded : true);
}

/// Tempo do toggle de worktrees: o chevron gira e a lista anima a altura nesta
/// duração. Só esses dois animam — o card/cabeçalho não se move.
const Duration _kToggleDuration = Duration(milliseconds: 150);

@visibleForTesting
IconData worktreeChevronIcon(bool expanded) =>
    expanded ? Icons.keyboard_arrow_down : Icons.chevron_right;

/// Rail esquerda (~252px): cabeçalho "Sessions", lista de projetos (avatar +
/// nome + git + contador de notificações), rodapé com o seletor de realm.
class ProjectsRail extends StatefulWidget {
  const ProjectsRail({
    super.key,
    required this.projects,
    required this.worktreesOf,
    required this.worktreesExpanded,
    required this.onWorktreesExpanded,
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
    required this.onNewWorkspace,
    required this.onSelectRemote,
    required this.onRemoveRemoteWorkspace,
    required this.remoteGitInfoOf,
    required this.onRemoteWorkspaceAction,
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

  /// Seleciona um host remoto (pelo id do workspace).
  final void Function(String workspaceId) onSelectRemote;

  /// "+": abre o menu Local vs Remoto, ancorado no [anchorContext] do botão.
  final void Function(BuildContext anchorContext) onNewWorkspace;

  /// Remove um workspace remoto (pin) pelo id do workspace.
  final void Function(String workspaceId) onRemoveRemoteWorkspace;

  /// Git status do workspace remoto (badge abaixo do nome + branch do menu);
  /// `null` = sem git ou ainda carregando (lazy).
  final GitInfo? Function(String workspaceId) remoteGitInfoOf;

  /// Ação do menu do workspace remoto (Camada A): 'pull'|'push'|'sync'|'rename'|
  /// 'close'. Copiar branch/id é resolvido no próprio slot.
  final void Function(String workspaceId, String action)
  onRemoteWorkspaceAction;

  /// Worktrees (forks) de um workspace raiz, na ordem do git.
  final List<Project> Function(String rootId) worktreesOf;

  /// `true` se a lista de worktrees do workspace raiz está expandida (V37).
  final bool Function(String rootId) worktreesExpanded;

  /// Expande/recolhe a lista de worktrees de um workspace raiz.
  final void Function(String rootId, bool expanded) onWorktreesExpanded;

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

  /// Clique no card do workspace [project] (V37): seleciona e/ou alterna a
  /// lista de worktrees, conforme [workspaceCardTap]. [onSelect] varia entre
  /// local e remoto — o resto da regra é o mesmo pros dois.
  void _onCardTap(Project project, VoidCallback onSelect) {
    final action = workspaceCardTap(
      selected: project.id == widget.selectedId,
      expanded: widget.worktreesExpanded(project.id),
      hasWorktrees: widget.worktreesOf(project.id).isNotEmpty,
    );
    if (action.select) onSelect();
    final expand = action.expand;
    if (expand != null) widget.onWorktreesExpanded(project.id, expand);
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

  /// Forks (worktrees) de um workspace remoto — mesmo `_WorktreeItem` do local,
  /// mas o git vem do cache remoto (lazy) e as ações roteiam pros handlers que
  /// já ramificam por `isRemoteTerminal`.
  List<Widget> _remoteForks(Project ws) {
    final forks = widget.worktreesOf(ws.id);
    return [
      for (var i = 0; i < forks.length; i++)
        _WorktreeItem(
          worktree: forks[i],
          originName: null,
          isLast: i == forks.length - 1,
          selected: forks[i].id == widget.selectedId,
          notifications: widget.notificationCount(forks[i].id),
          git: widget.remoteGitInfoOf(forks[i].id),
          onTap: () => widget.onSelectRemote(forks[i].id),
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
                  context.t.cockpit.projectsRail.workspaces,
                  style: context.typo.title.copyWith(color: colors.text),
                ),
                const Spacer(),
                // "+" abre um menu Local vs Remoto (plano 58). Builder pra
                // ancorar o popover no próprio botão.
                Builder(
                  builder: (btnContext) => _SmallIcon(
                    icon: Icons.add,
                    tooltip: context.t.cockpit.projectsRail.newWorkspace,
                    onTap: () => widget.onNewWorkspace(btnContext),
                  ),
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
          // Workspaces remotos (plano 58) NÃO têm mais um bloco fixo aqui: eles
          // entram na lista `projects` abaixo, no realm ativo, reordenáveis e
          // arrastáveis igual aos locais (o loop ramifica por isRemoteTerminal).
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
                            // Remoto (plano 58): mesmo lugar/realm/reorder que o
                            // local, mas com o slot SSH + forks remotos.
                            if (project.isRemoteTerminal) ...[
                              _WorkspaceReorderable(
                                projectId: project.id,
                                title: project.name,
                                colorValue: project.colorValue,
                                initial: project.initial,
                                imagePath: project.imagePath,
                                onReorder: widget.onReorder,
                                child: _RemoteSlot(
                                  workspaceId: project.id,
                                  name: project.name,
                                  colorValue: project.colorValue,
                                  imagePath: project.imagePath,
                                  selected: project.id == widget.selectedId,
                                  git: widget.remoteGitInfoOf(project.id),
                                  moveTargets: widget.moveTargetsOf(project.id),
                                  worktreeCount: widget
                                      .worktreesOf(project.id)
                                      .length,
                                  hasWorktrees: widget
                                      .worktreesOf(project.id)
                                      .isNotEmpty,
                                  expanded: widget.worktreesExpanded(
                                    project.id,
                                  ),
                                  onTap: () => _onCardTap(
                                    project,
                                    () => widget.onSelectRemote(project.id),
                                  ),
                                  onAction: (action) =>
                                      widget.onRemoteWorkspaceAction(
                                        project.id,
                                        action,
                                      ),
                                  onRemove: () => widget
                                      .onRemoveRemoteWorkspace(project.id),
                                ),
                              ),
                              _ForkList(
                                expanded: widget.worktreesExpanded(project.id),
                                children: _remoteForks(project),
                              ),
                            ] else ...[
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
                                  worktreeCount: widget
                                      .worktreesOf(project.id)
                                      .length,
                                  // "Criar worktree" só faz sentido em repo git
                                  // (single ou multi-root — na multi a page pede
                                  // a root alvo antes).
                                  canCreateWorktree:
                                      widget.gitInfo(project.id) != null ||
                                      widget.rootsSummary(project.id).$1 > 1,
                                  hasWorktrees: widget
                                      .worktreesOf(project.id)
                                      .isNotEmpty,
                                  expanded: widget.worktreesExpanded(
                                    project.id,
                                  ),
                                  onTap: () => _onCardTap(
                                    project,
                                    () => widget.onSelect(project.id),
                                  ),
                                  onConfigure: () =>
                                      widget.onConfigure(project),
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
                              // expandidas/recolhidas pelo toggle do card (V37;
                              // antes eram sempre visíveis — plan/42, dec. 5, 12).
                              _ForkList(
                                expanded: widget.worktreesExpanded(project.id),
                                children: _forkItems(project),
                              ),
                            ],
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
                  tooltip: context.t.cockpit.projectsRail.settings,
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

/// Lista de worktrees de um workspace, animada em **altura** ao expandir e
/// recolher (V37). Só ela anima: o card acima mantém a mesma altura o tempo
/// todo, então nada se desloca além da lista. Recolhida por completo, os itens
/// saem da árvore (não ficam com altura zero atrás de um clip).
class _ForkList extends StatelessWidget {
  const _ForkList({required this.expanded, required this.children});

  final bool expanded;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    if (children.isEmpty) return const SizedBox.shrink();
    return AnimatedSize(
      duration: _kToggleDuration,
      curve: Curves.easeOutCubic,
      alignment: Alignment.topCenter,
      child: expanded
          ? Column(mainAxisSize: MainAxisSize.min, children: children)
          : const SizedBox.shrink(),
    );
  }
}

class _WorktreeSummary extends StatelessWidget {
  const _WorktreeSummary({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Row(
      children: [
        Icon(Icons.call_split, size: 12, color: colors.text3),
        const SizedBox(width: 6),
        Text(
          context.t.cockpit.projectsRail.worktreeCount(n: count),
          style: context.typo.label.copyWith(color: colors.text2),
        ),
      ],
    );
  }
}

/// Chevron do card: usa glifos explícitos para garantir direita/recolhido e
/// baixo/expandido em todas as plataformas. Puramente indicativo — quem recebe
/// o clique é o card inteiro, então ele não intercepta ponteiro nenhum.
class _WorktreeChevron extends StatelessWidget {
  const _WorktreeChevron({required this.expanded});

  final bool expanded;

  @override
  Widget build(BuildContext context) {
    final tr = context.t.cockpit.projectsRail;
    return AppTooltip(
      message: expanded ? tr.collapseWorktrees : tr.expandWorktrees,
      child: AnimatedSwitcher(
        duration: _kToggleDuration,
        switchInCurve: Curves.easeOutCubic,
        switchOutCurve: Curves.easeInCubic,
        transitionBuilder: (child, animation) =>
            FadeTransition(opacity: animation, child: child),
        child: Icon(
          worktreeChevronIcon(expanded),
          key: ValueKey(expanded),
          size: 16,
          color: context.colors.text3,
        ),
      ),
    );
  }
}

/// Envolve um badge/chip informativo pra que o clique nele **pare** ali: sem
/// isto o toque cairia no card e alternaria a lista de worktrees, que não é o
/// que alguém mirando um indicador espera. Chips com ação própria
/// ([_MultiRootBadge]) já têm o gesto deles e não passam por aqui.
class _AbsorbCardTap extends StatelessWidget {
  const _AbsorbCardTap({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => GestureDetector(
    behavior: HitTestBehavior.opaque,
    onTap: () {},
    child: child,
  );
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

/// Slot de um host remoto: badge com o nome do host + glifo de nuvem/terminal.
/// Botão-direito (long-press no menu) remove o pin. Terminal-only via SSH.
class _RemoteSlot extends StatelessWidget {
  const _RemoteSlot({
    required this.workspaceId,
    required this.name,
    required this.colorValue,
    required this.imagePath,
    required this.selected,
    required this.git,
    required this.moveTargets,
    required this.worktreeCount,
    required this.hasWorktrees,
    required this.expanded,
    required this.onTap,
    required this.onAction,
    required this.onRemove,
  });

  /// `true` se o host tem forks pendurados — só então o chevron aparece.
  final bool hasWorktrees;

  /// Estado atual da lista de forks (V37).
  final bool expanded;

  final String workspaceId;
  final String name;
  final int colorValue;

  /// Realms de destino do "Move to realm" (vazio esconde o item).
  final List<RealmTarget> moveTargets;

  final int worktreeCount;

  /// Imagem de fundo do avatar (personalizada nas Configurações), ou `null`.
  final String? imagePath;
  final bool selected;

  /// Git status do workspace remoto (branch + sujeira), ou `null` se sem git /
  /// ainda carregando. Alimenta o badge abaixo do nome E o gate das ações de
  /// git no menu (a branch sai daqui).
  final GitInfo? git;

  String? get branch {
    final b = git?.branch;
    return (b == null || b.isEmpty) ? null : b;
  }

  final VoidCallback onTap;

  /// Ações roteadas pra página: 'pull' | 'push' | 'sync' | 'rename' | 'close'.
  final void Function(String action) onAction;
  final VoidCallback onRemove;

  Future<void> _showMenu(BuildContext context) async {
    final tr = context.t.cockpit.projectsRail;
    final hasGit = branch != null;
    final pick = await showAppMenu<String>(
      context,
      items: [
        if (hasGit) ...[
          AppMenuItem(value: 'sync', label: tr.sync, icon: Icons.sync),
          AppMenuItem(
            value: 'pull',
            label: tr.pull,
            icon: Icons.arrow_downward,
          ),
          AppMenuItem(value: 'push', label: tr.push, icon: Icons.arrow_upward),
          AppMenuItem(
            value: 'worktree',
            label: tr.createWorktree,
            icon: Icons.call_split,
          ),
          AppMenuItem(
            value: 'copy-branch',
            label: tr.copyBranch,
            icon: Icons.content_copy,
          ),
        ],
        AppMenuItem(
          value: 'copy-id',
          label: tr.copyWorkspaceId,
          icon: Icons.content_copy,
        ),
        if (moveTargets.isNotEmpty)
          AppMenuItem(
            value: 'realm', // nunca devolvido — só os filhos
            label: tr.moveToRealm,
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
        AppMenuItem(
          value: 'config',
          label: tr.settings,
          icon: Icons.settings_outlined,
        ),
        AppMenuItem(
          value: 'close',
          label: tr.close,
          icon: Icons.close,
          danger: true,
        ),
      ],
    );
    if (pick == null) return;
    // Copiar resolve aqui (dado já em mãos); o resto vai pra página.
    if (pick == 'copy-branch') {
      final b = branch;
      if (b != null) await Clipboard.setData(ClipboardData(text: b));
      return;
    }
    if (pick == 'copy-id') {
      await Clipboard.setData(ClipboardData(text: workspaceId));
      return;
    }
    onAction(pick);
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final accent = Color(colorValue);
    return GestureDetector(
      // Botão-direito remove o pin (o registro do host sai; nada apagado no
      // servidor). Tooltip via AppTooltip explica.
      onSecondaryTap: onRemove,
      child: HoverTap(
        color: selected ? colors.panel2 : Colors.transparent,
        borderRadius: BorderRadius.circular(7),
        onTap: onTap,
        padding: const EdgeInsets.fromLTRB(9, 7, 9, 7),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                // Mesmo avatar do workspace local: imagem de fundo quando houver,
                // senão a inicial sobre a cor. A afordância "remoto" fica no badge
                // "SSH" à direita.
                WorkspaceAvatar(
                  imagePath: imagePath,
                  colorValue: colorValue,
                  initial: name.isEmpty
                      ? '?'
                      : name.characters.first.toUpperCase(),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        name,
                        overflow: TextOverflow.ellipsis,
                        style: context.typo.body.copyWith(
                          fontSize: 13.5,
                          color: colors.text,
                          fontWeight: selected
                              ? FontWeight.w500
                              : FontWeight.w400,
                        ),
                      ),
                      // Mesmo badge do local: branch + contador de sujeira, quando
                      // o git remoto já foi lido (lazy). Sem git → nada.
                      if (git != null) ...[
                        const SizedBox(height: 4),
                        _AbsorbCardTap(child: _GitBadge(info: git!)),
                      ],
                    ],
                  ),
                ),
                _AbsorbCardTap(
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 5,
                      vertical: 1,
                    ),
                    decoration: BoxDecoration(
                      color: accent.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      'SSH',
                      style: context.typo.label.copyWith(
                        fontSize: 9,
                        color: accent,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
                if (hasWorktrees) ...[
                  const SizedBox(width: 4),
                  _WorktreeChevron(expanded: expanded),
                ],
                const SizedBox(width: 2),
                // Builder: o menu ancora no RenderBox do context passado a
                // showAppMenu. Sem isto, o context do slot inteiro faria o popup
                // abrir na largura toda (aparecia "embaixo"); com o Builder o
                // context é o do ícone, igual ao workspace local.
                Builder(
                  builder: (iconContext) => GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTapUp: (_) => _showMenu(iconContext),
                    child: SizedBox(
                      width: 22,
                      height: 22,
                      child: Icon(
                        Icons.more_vert,
                        size: 14,
                        color: context.colors.text3,
                      ),
                    ),
                  ),
                ),
              ],
            ),
            if (hasWorktrees)
              Padding(
                padding: const EdgeInsets.only(left: 38, top: 4),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: _WorktreeSummary(count: worktreeCount),
                ),
              ),
          ],
        ),
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
    required this.worktreeCount,
    required this.hasWorktrees,
    required this.expanded,
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

  final int worktreeCount;

  /// `true` se o workspace tem worktrees — só então o chevron aparece e o
  /// clique no card alterna a lista (V37).
  final bool hasWorktrees;

  /// Estado atual da lista de worktrees (V37).
  final bool expanded;
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
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
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
                          fontWeight: selected
                              ? FontWeight.w500
                              : FontWeight.w400,
                        ),
                      ),
                      // Linha do git — repo git (branch) ou multi-root (agregado);
                      // pasta comum não mostra nada.
                      if (gitInfo != null) ...[
                        const SizedBox(height: 4),
                        _AbsorbCardTap(child: _GitBadge(info: gitInfo)),
                      ] else if (rootsSummary.$1 > 1) ...[
                        const SizedBox(height: 4),
                        _MultiRootBadge(
                          roots: rootsSummary.$1,
                          dirtyRoots: rootsSummary.$2,
                          rootList: roots,
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(width: 6),
                if (notifications > 0) ...[
                  _AbsorbCardTap(
                    child: Container(
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
                          color: onColor(colors.accent),
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 4),
                ],
                if (hasWorktrees) ...[
                  _WorktreeChevron(expanded: expanded),
                  const SizedBox(width: 2),
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
            if (hasWorktrees)
              Padding(
                padding: const EdgeInsets.only(left: 40, top: 4),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: _WorktreeSummary(count: worktreeCount),
                ),
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
/// no nome mostra tooltip com o rótulo completo (ellipsis corta nomes longos).
/// A linha fica **fora** do realce do item.
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
    // Rótulo completo pro tooltip — igual ao texto renderizado (com sufixo de
    // root em multi-root), pra o hover revelar o que o ellipsis cortou.
    final fullLabel = originName != null
        ? '${worktree.name}  ($originName)'
        : worktree.name;
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
                      child: AppTooltip(
                        message: fullLabel,
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
      items: [
        AppMenuItem(
          value: 'merge',
          label: context.t.cockpit.projectsRail.mergeToParent,
          icon: Icons.merge_type,
        ),
        // Inverso do Merge to Parent: traz a branch do pai pro worktree
        // ("Update branch" do GitHub). Conflito fica no worktree.
        AppMenuItem(
          value: 'update',
          label: context.t.cockpit.projectsRail.updateFromParent,
          icon: Icons.download_outlined,
        ),
        // Nova worktree ramificada da branch DESTE fork (não do HEAD do
        // pai) — vira irmão na lista, herdando o layout deste fork.
        AppMenuItem(
          value: 'fork',
          label: context.t.cockpit.projectsRail.forkWorktree,
          icon: Icons.call_split,
        ),
        AppMenuItem(
          value: 'copy',
          label: context.t.cockpit.projectsRail.copyBranch,
          icon: Icons.content_copy,
        ),
        AppMenuItem(
          value: 'remove',
          label: context.t.cockpit.projectsRail.remove,
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
/// quantas estão sujas. Clicável: abre um popup com a branch e o estado
/// (↓behind ↑ahead + sujos) de cada root — a visão por repo, sem poluir a
/// árvore de arquivos. Mesma linguagem do [_GitBadge].
class _MultiRootBadge extends StatelessWidget {
  const _MultiRootBadge({
    required this.roots,
    required this.dirtyRoots,
    required this.rootList,
  });
  final int roots;
  final int dirtyRoots;
  final List<RailRoot> rootList;

  void _showPopup(BuildContext context) {
    final overlay = showPopover<void>(
      context: context,
      alignment: Alignment.topLeft,
      anchorAlignment: Alignment.bottomLeft,
      offset: const Offset(0, 4),
      builder: (popupContext) => ConstrainedBox(
        constraints: const BoxConstraints(minWidth: 180, maxWidth: 320),
        child: MenuPopup(
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [for (final r in rootList) _RootStatusRow(root: r)],
              ),
            ),
          ],
        ),
      ),
    );
    trackMenuOverlay(overlay);
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final typo = context.typo;
    final dirty = dirtyRoots > 0;
    final fg = dirty ? colors.warn : colors.text3;
    final bg = dirty ? colors.editedBg : colors.panel3;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      // GestureDetector (descendente) ganha a arena do HoverTap do item — o
      // clique no chip abre o popup, não seleciona o workspace.
      child: GestureDetector(
        onTap: () => _showPopup(context),
        child: Container(
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
        ),
      ),
    );
  }
}

/// Entrada do popup do [_MultiRootBadge], em **duas linhas**: nome da root em
/// cima, branch + estado (↓behind ↑ahead + nº de sujos) embaixo — nome longo
/// trunca sem roubar o espaço da branch. Root sem git mostra só o nome, apagado.
class _RootStatusRow extends StatelessWidget {
  const _RootStatusRow({required this.root});
  final RailRoot root;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final typo = context.typo;
    final git = root.git;
    final dirty = git != null && git.isDirty;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.folder_outlined,
                size: 13,
                color: git == null ? colors.text4 : colors.text3,
              ),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  root.name,
                  overflow: TextOverflow.ellipsis,
                  style: typo.body.copyWith(
                    fontSize: 12.5,
                    color: git == null ? colors.text4 : colors.text,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ],
          ),
          if (git != null)
            Padding(
              // Alinha com o texto acima (ícone 13 + gap 6).
              padding: const EdgeInsets.only(left: 19, top: 3),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.call_split,
                    size: 10,
                    color: dirty ? colors.warn : colors.text3,
                  ),
                  const SizedBox(width: 3),
                  Flexible(
                    child: Text(
                      git.branch,
                      overflow: TextOverflow.ellipsis,
                      style: typo.mono.copyWith(
                        fontSize: 11,
                        color: dirty ? colors.warn : colors.text3,
                      ),
                    ),
                  ),
                  if (git.behind > 0) ...[
                    const SizedBox(width: 6),
                    _AheadBehind(
                      glyph: '↓',
                      count: git.behind,
                      color: colors.warn,
                    ),
                  ],
                  if (git.ahead > 0) ...[
                    const SizedBox(width: 4),
                    _AheadBehind(
                      glyph: '↑',
                      count: git.ahead,
                      color: colors.accentText,
                    ),
                  ],
                  if (dirty) ...[
                    const SizedBox(width: 6),
                    Text(
                      '${git.dirtyCount}',
                      style: typo.mono.copyWith(
                        fontSize: 11,
                        color: colors.edited,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ],
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
    final gitRoots = roots.where((r) => r.git != null).toList();
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
            label: '${r.name}  ⎇ ${r.git?.branch}',
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
          _gitItem('sync', context.t.cockpit.projectsRail.sync, Icons.sync),
          _gitItem(
            'pull',
            context.t.cockpit.projectsRail.pull,
            Icons.arrow_downward,
          ),
          _gitItem(
            'push',
            context.t.cockpit.projectsRail.push,
            Icons.arrow_upward,
          ),
          _gitItem(
            'worktree',
            context.t.cockpit.projectsRail.createWorktree,
            Icons.call_split,
          ),
        ],
        if (moveTargets.isNotEmpty)
          AppMenuItem(
            value: 'realm', // nunca devolvido — só os filhos
            label: context.t.cockpit.projectsRail.moveToRealm,
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
        AppMenuItem(
          value: 'copy-id',
          label: context.t.cockpit.projectsRail.copyWorkspaceId,
          icon: Icons.content_copy,
        ),
        // Só com git: sem repo não há branch a copiar. Em multirepo vira
        // submenu por root, igual a pull/push — cada root está numa branch
        // diferente, então "a branch do workspace" não existe.
        //
        // Mesmo rótulo e mesmo ícone do "Copiar branch" que o menu de worktree
        // já tinha: é a mesma ação, só que na raiz.
        if (roots.any((r) => r.git != null))
          _gitItem(
            'copy-branch',
            context.t.cockpit.projectsRail.copyBranch,
            Icons.content_copy,
          ),
        AppMenuItem(
          value: 'config',
          label: context.t.cockpit.projectsRail.settings,
          icon: Icons.settings_outlined,
        ),
        AppMenuItem(
          value: 'delete',
          label: context.t.cockpit.projectsRail.close,
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
      if (action == 'copy-branch') {
        // Resolvido aqui, e não por callback: a branch já veio no [RailRoot]
        // que o menu recebeu, então pedir de volta à página só criaria caminho
        // para divergir do rótulo que o usuário acabou de ler no submenu.
        final branch = branchOfRoot(roots, arg);
        if (branch != null) {
          await Clipboard.setData(ClipboardData(text: branch));
        }
      }
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
          context.t.cockpit.projectsRail.noWorkspaces,
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
        AppMenuItem(
          value: '__new__',
          label: context.t.cockpit.projectsRail.newRealm,
          icon: Icons.add,
        ),
        AppMenuItem(
          value: '__manage__',
          label: context.t.cockpit.projectsRail.manageRealms,
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
        final feedback = Transform.translate(
          offset: const Offset(10, 8),
          child: _WorkspaceDragChip(
            title: widget.title,
            colorValue: widget.colorValue,
            initial: widget.initial,
            imagePath: widget.imagePath,
          ),
        );
        return Stack(
          children: [
            // No DESKTOP a rolagem do rail é via roda/trackpad (PointerScroll,
            // não gesto de arrasto), então o Draggable imediato no item inteiro
            // não briga com o scroll. No MOBILE (touch) isso brigaria: um swipe
            // vertical pra rolar viraria drag-drop. Por isso, no mobile o item
            // NÃO é arrastável — só rola/seleciona — e o reorder sai por um
            // handle dedicado (plano 60, Wave B1, decisão B).
            if (isMobilePlatform)
              widget.child
            else
              Draggable<String>(
                data: widget.projectId,
                dragAnchorStrategy: pointerDragAnchorStrategy,
                feedback: feedback,
                childWhenDragging: Opacity(opacity: 0.3, child: widget.child),
                child: widget.child,
              ),
            if (isMobilePlatform)
              Positioned(
                right: 0,
                top: 0,
                bottom: 0,
                child: Center(
                  child: Draggable<String>(
                    data: widget.projectId,
                    dragAnchorStrategy: pointerDragAnchorStrategy,
                    feedback: feedback,
                    child: _ReorderHandle(color: colors.text3),
                  ),
                ),
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

/// Handle de reordenação (só mobile): a única região que inicia o drag-drop do
/// workspace. Fica na borda direita do item; o resto rola/seleciona por toque.
class _ReorderHandle extends StatelessWidget {
  const _ReorderHandle({required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Icon(Icons.drag_indicator, size: 18, color: color),
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
        boxShadow: [
          BoxShadow(color: colors.shadow, blurRadius: 12, offset: Offset(0, 4)),
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
