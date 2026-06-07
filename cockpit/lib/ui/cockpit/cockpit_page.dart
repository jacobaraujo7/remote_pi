import 'dart:async' show unawaited;

import 'package:cockpit/domain/entities/project.dart';
import 'package:cockpit/routing/routes.dart';
import 'package:cockpit/ui/cockpit/session/agent_session.dart';
import 'package:cockpit/ui/cockpit/states/pane_node.dart';
import 'package:cockpit/ui/cockpit/viewmodels/cockpit_viewmodel.dart';
import 'package:cockpit/ui/cockpit/widgets/widgets.dart';
import 'package:cockpit/ui/core/themes/themes.dart';
import 'package:cockpit/ui/settings/settings_controller.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

/// Shell do Cockpit: top bar + rail de projetos + multiplexador (árvore de
/// splits). Cada folha é uma [PaneView] com abas; cada aba é um agente.
class CockpitPage extends StatefulWidget {
  const CockpitPage({super.key});

  @override
  State<CockpitPage> createState() => _CockpitPageState();
}

class _CockpitPageState extends State<CockpitPage> {
  CockpitViewModel get _vm => context.read<CockpitViewModel>();

  /// Larguras dos painéis laterais (arrastáveis). **Não** são persistidas —
  /// estado só da sessão da janela.
  double _treeWidth = 300;
  static const double _treeMin = 220;
  static const double _treeMax = 620;

  double _railWidth = 252;
  static const double _railMin = 190;
  static const double _railMax = 420;

  /// Garante um projeto selecionado (pede uma pasta se não houver). Retorna
  /// `true` se há projeto pronto para uso.
  Future<bool> _ensureProject() async {
    if (_vm.selectedProject != null) return true;
    return _addProject();
  }

  Future<bool> _addProject() async {
    final vm = _vm;
    final path = await FilePicker.platform.getDirectoryPath(
      dialogTitle: 'Escolha a pasta do projeto',
    );
    if (path == null) return false;
    await vm.addProject(path);
    return true;
  }

  /// Fluxo "Criar Workspace": escolhe a pasta, abre o dialog de configurações
  /// (nome pré-preenchido com o da pasta + cor sugerida, ambos editáveis) e cria.
  Future<bool> _createWorkspace() async {
    final vm = _vm;
    final path = await FilePicker.platform.getDirectoryPath(
      dialogTitle: 'Escolha a pasta do workspace',
    );
    if (path == null || !mounted) return false;
    final suggestedName = path
        .split('/')
        .where((p) => p.isNotEmpty)
        .lastOrNull;
    final suggestedColor =
        kWorkspacePalette[vm.projects.length % kWorkspacePalette.length];
    final result = await showWorkspaceSettingsDialog(
      context,
      name: suggestedName ?? path,
      colorValue: suggestedColor,
      path: path,
    );
    if (result == null) return false;
    await vm.addProject(
      path,
      name: result.name,
      colorValue: result.colorValue,
    );
    return true;
  }

  /// "Configurações" do workspace: editar nome + cor do avatar.
  Future<void> _configureProject(Project project) async {
    final vm = _vm;
    final result = await showWorkspaceSettingsDialog(
      context,
      name: project.name,
      colorValue: project.colorValue,
      path: project.path,
    );
    if (result == null) return;
    await vm.updateProject(
      project.id,
      name: result.name,
      colorValue: result.colorValue,
    );
    if (!mounted) return;
    if (result.name != project.name) {
      await showInfoDialog(
        context,
        title: 'Workspace renomeado',
        message:
            'O novo nome "${result.name}" será enviado aos agentes somente '
            'após reiniciar o workspace ou a aplicação.',
      );
    }
  }

  /// "Deletar" o workspace (confirma → remove da base local + encerra agentes).
  Future<void> _deleteProject(Project project) async {
    final vm = _vm;
    final ok = await showConfirmDialog(
      context,
      title: 'Deletar workspace',
      message:
          'Remover "${project.name}"? Os agentes deste workspace serão '
          'encerrados. A pasta no disco não é apagada.',
      confirmLabel: 'Deletar',
      danger: true,
    );
    if (!ok) return;
    await vm.removeProject(project.id);
  }

  /// Pede a subpasta onde o agente vai atuar e dispara [action] com o caminho
  /// relativo escolhido (`''` = raiz do projeto).
  Future<void> _pickSubfolderThen(void Function(String sub) action) async {
    final vm = _vm;
    if (!await _ensureProject()) return;
    final project = vm.selectedProject;
    if (project == null) return;
    final subfolders = await vm.subfolders();
    if (!mounted) return;
    final chosen = await showSubfolderDialog(
      context,
      projectName: project.name,
      subfolders: subfolders,
    );
    if (chosen == null) return;
    action(chosen);
  }

  /// "Histórico": lista as sessões salvas do pi para a pasta do agente ativo e,
  /// ao escolher, substitui o transcript pela sessão carregada.
  Future<void> _openHistory(String agentId) async {
    final vm = _vm;
    final session = vm.session(agentId);
    if (session is! AgentSession || !session.isAlive) return; // agente vivo
    final sessions = await vm.historyFor(session.workingDirectory);
    if (!mounted) return;
    final picked = await showHistoryDialog(context, sessions: sessions);
    if (picked == null) return;
    await session.loadHistory(picked.path);
  }

  /// "Editar": dialog com infos + config do agente (nome + relay).
  Future<void> _openEdit(String agentId) async {
    final vm = _vm;
    final session = vm.session(agentId);
    if (session is! AgentSession) return;
    final edited = await showAgentEditDialog(context, session: session);
    if (!mounted || edited == null) return;
    unawaited(
      vm.saveAgentConfig(
        agentId,
        agentName: edited.agentName,
        autoStartRelay: edited.autoStartRelay,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final vm = context.watch<CockpitViewModel>();
    final colors = context.colors;

    if (!vm.ready) {
      return Scaffold(
        backgroundColor: colors.bg,
        body: const Center(child: CircularProgressIndicator(strokeWidth: 2)),
      );
    }

    return Scaffold(
      backgroundColor: colors.bg,
      body: Column(
        children: [
          CockpitTopbar(
            projectName: vm.selectedProject?.name ?? 'Cockpit',
            railVisible: vm.railVisible,
            treeVisible: vm.treeVisible,
            openEnabled: vm.selectedProject != null,
            onToggleRail: vm.toggleRail,
            onToggleTree: vm.toggleTree,
            availableApps: vm.availableApps,
            lastOpenAppId: context
                .select<SettingsController, String?>(
                  (c) => c.settings.lastOpenAppId,
                ),
            onOpenInApp: (id) {
              final app = vm.availableApps.where((a) => a.id == id).firstOrNull;
              if (app == null) return;
              context.read<SettingsController>().setLastOpenApp(id);
              unawaited(vm.openProjectInApp(app));
            },
          ),
          Expanded(
            child: Row(
              children: [
                if (vm.railVisible)
                  Stack(
                    children: [
                      ProjectsRail(
                        width: _railWidth,
                        projects: vm.projects,
                        selectedId: vm.selectedProjectId,
                        notificationCount: vm.notificationCount,
                        gitInfo: vm.gitInfo,
                        onSelect: vm.selectProject,
                        onAdd: _createWorkspace,
                        onConfigure: _configureProject,
                        onDelete: _deleteProject,
                        onOpenSettings: () => context.push(RoutePaths.settings),
                      ),
                      // Alça de arraste na borda direita (direita = alarga).
                      Positioned(
                        right: 0,
                        top: 0,
                        bottom: 0,
                        child: _ResizeHandle(
                          onDelta: (dx) => setState(() {
                            _railWidth = (_railWidth + dx).clamp(
                              _railMin,
                              _railMax,
                            );
                          }),
                        ),
                      ),
                    ],
                  ),
                Expanded(
                  child: vm.selectedProjectId == null
                      ? OnboardingView(onCreateWorkspace: _createWorkspace)
                      : IndexedStack(
                          index: _activeIndex(vm),
                          sizing: StackFit.expand,
                          children: [
                            // Um multiplexador por projeto — todos montados, só
                            // o ativo pintado → estado preservado ao trocar.
                            for (final project in vm.projects)
                              KeyedSubtree(
                                key: ValueKey(project.id),
                                child: ColoredBox(
                                  color: colors.border,
                                  child: _multiplexer(vm, project.id),
                                ),
                              ),
                          ],
                        ),
                ),
                if (vm.treeVisible)
                  Stack(
                    children: [
                      FileTreePanel(
                        // Pasta do workspace; reseta ao trocar de workspace.
                        key: ValueKey(vm.selectedProject?.path ?? ''),
                        width: _treeWidth,
                        rootPath: vm.selectedProject?.path ?? '',
                        listChildren: vm.listChildren,
                        onOpenFile: vm.openFile,
                      ),
                      // Alça de arraste sobre a borda esquerda do painel
                      // (esquerda = alarga; direita = estreita).
                      Positioned(
                        left: 0,
                        top: 0,
                        bottom: 0,
                        child: _ResizeHandle(
                          onDelta: (dx) => setState(() {
                            _treeWidth = (_treeWidth - dx).clamp(
                              _treeMin,
                              _treeMax,
                            );
                          }),
                        ),
                      ),
                    ],
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  int _activeIndex(CockpitViewModel vm) {
    final index = vm.projects.indexWhere(
      (p) => p.id == vm.selectedProjectId,
    );
    return index < 0 ? 0 : index;
  }

  Widget _multiplexer(CockpitViewModel vm, String projectId) {
    final tree = vm.tree(projectId);
    if (tree == null) return const SizedBox.shrink();
    return _renderNode(vm, projectId, tree);
  }

  Widget _renderNode(CockpitViewModel vm, String projectId, PaneNode node) {
    if (node is LeafPane) {
      return PaneDropZone(
        key: ValueKey('drop-${node.id}'),
        paneId: node.id,
        vm: vm,
        child: PaneView(
          key: ValueKey(node.id),
          pane: node,
          vm: vm,
          focused: node.id == vm.focusedPaneId(projectId),
          onCreateTab: () => vm.newEmptyTab(node.id),
          onSplit: (dir) =>
              _pickSubfolderThen((sub) => vm.splitPane(node.id, dir, sub)),
          onFillEmpty: (emptyId, terminal) => _pickSubfolderThen(
            (sub) => vm.fillEmpty(node.id, emptyId, sub, terminal: terminal),
          ),
          onHistoryAgent: _openHistory,
          onEditAgent: _openEdit,
        ),
      );
    }
    final split = node as SplitPane;
    final isRow = split.dir == SplitDir.vertical;
    // Largura da região de arraste (a linha visual continua 1px, centralizada).
    const handle = 12.0;

    return LayoutBuilder(
      builder: (context, constraints) {
        final total = isRow ? constraints.maxWidth : constraints.maxHeight;
        final aSize = total * split.frac;
        final bSize = total - aSize;
        final first = SizedBox(
          width: isRow ? aSize : null,
          height: isRow ? null : aSize,
          child: _renderNode(vm, projectId, split.a),
        );
        final second = SizedBox(
          width: isRow ? bSize : null,
          height: isRow ? null : bSize,
          child: _renderNode(vm, projectId, split.b),
        );
        final divider = PaneDivider(
          dir: split.dir,
          onDelta: (delta) {
            if (total <= 0) return;
            vm.resizeSplit(split.id, (aSize + delta) / total);
          },
        );
        return Stack(
          children: [
            // Base: as duas panes adjacentes (a linha vem do handle por cima).
            isRow
                ? Row(children: [first, second])
                : Column(children: [first, second]),
            // Overlay: handle largo centralizado na divisória (hit-test real).
            if (isRow)
              Positioned(
                left: aSize - handle / 2,
                width: handle,
                top: 0,
                bottom: 0,
                child: divider,
              )
            else
              Positioned(
                top: aSize - handle / 2,
                height: handle,
                left: 0,
                right: 0,
                child: divider,
              ),
          ],
        );
      },
    );
  }
}

/// Alça fina pra redimensionar um painel lateral. Hit-area de 8px (cursor de
/// resize); o visual fica por conta da borda do próprio painel. Quem usa decide
/// o sinal do delta (borda esquerda vs direita).
class _ResizeHandle extends StatelessWidget {
  const _ResizeHandle({required this.onDelta});

  /// Delta horizontal do arraste (px).
  final ValueChanged<double> onDelta;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.resizeLeftRight,
      child: GestureDetector(
        behavior: HitTestBehavior.translucent,
        onHorizontalDragUpdate: (d) => onDelta(d.delta.dx),
        child: const SizedBox(width: 8),
      ),
    );
  }
}
