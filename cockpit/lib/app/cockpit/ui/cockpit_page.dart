import 'dart:async' show StreamSubscription, unawaited;
import 'dart:io';

import 'package:cockpit/app/core/app_intents.dart';
import 'package:cockpit/app/cockpit/domain/entities/project.dart';
import 'package:cockpit/app/core/routes.dart';
import 'package:cockpit/app/cockpit/ui/session/agent_session.dart';
import 'package:cockpit/app/cockpit/ui/states/pane_node.dart';
import 'package:cockpit/app/cockpit/ui/viewmodels/cockpit_viewmodel.dart';
import 'package:cockpit/app/cockpit/ui/viewmodels/update_viewmodel.dart';
import 'package:cockpit/app/cockpit/ui/widgets/widgets.dart';
import 'package:cockpit/app/core/ui/themes/themes.dart';
import 'package:cockpit/app/core/ui/settings_controller.dart';
import 'package:cockpit/app/core/ui/widgets/hover_tap.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/services.dart' show LogicalKeyboardKey;
import 'package:shadcn_flutter/shadcn_flutter.dart';
import 'package:flutter_modular/flutter_modular.dart';

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

  @override
  void initState() {
    super.initState();
    // Registra a ponte do ⌘L global (handler em main.dart) → foca o input do
    // agente focado, mesmo quando o foco caiu num espaço vazio do shell.
    requestFocusActiveComposer = _focusActiveComposer;
    // Dispara o carregamento inicial dos ViewModels page-scoped ao montar a rota.
    // Os módulos provêm via `.new`, então não encadeiam mais `..init()`/`..check()`.
    context.read<CockpitViewModel>().init();
    context.read<UpdateViewModel>().check();
    // Mantém os overrides de comando do LSP (tela "Language") em sync com o pool:
    // empurra o estado atual e re-empurra a cada mudança das Configurações.
    _settings = context.read<SettingsController>()
      ..addListener(_syncLspCommands)
      ..addListener(_syncNotifications);
    _syncLspCommands();
    _syncNotifications();
  }

  SettingsController? _settings;
  Map<String, String> _lastLspCommands = const <String, String>{};

  /// Espelha o toggle de Notificações (aba das Configurações) para a VM, que
  /// gateia o disparo de fim de turno. A VM é page-scoped e não vê o
  /// `SettingsController` app-scoped, então a página empurra o valor.
  void _syncNotifications() {
    _vm.setNotificationsEnabled(_settings!.settings.notificationsEnabled);
  }

  void _syncLspCommands() {
    final next = _settings!.settings.lspCommands;
    _vm.applyLspCommands(next);
    // Reinicia os servidores das linguagens cujo comando mudou (efetiva o novo
    // comando nos já vivos). Na 1ª sincronização não há o que reiniciar.
    final langs = <String>{..._lastLspCommands.keys, ...next.keys};
    for (final id in langs) {
      if (_lastLspCommands[id] != next[id]) {
        unawaited(_vm.restartLspLanguage(id));
      }
    }
    _lastLspCommands = Map<String, String>.of(next);
  }

  @override
  void dispose() {
    _settings?.removeListener(_syncLspCommands);
    _settings?.removeListener(_syncNotifications);
    if (requestFocusActiveComposer == _focusActiveComposer) {
      requestFocusActiveComposer = null;
    }
    super.dispose();
  }

  /// Foca o input do agente focado (no-op se a aba ativa não for um agente).
  void _focusActiveComposer() {
    final agent = _vm.focusedAgent;
    if (agent is AgentSession) agent.requestComposerFocus?.call();
  }

  /// Garante um projeto selecionado (pede uma pasta se não houver). Retorna
  /// `true` se há projeto pronto para uso.
  Future<bool> _ensureProject() async {
    if (_vm.selectedProject != null) return true;
    return _addProject();
  }

  Future<bool> _addProject() async {
    final vm = _vm;
    final path = await FilePicker.platform.getDirectoryPath(
      dialogTitle: 'Choose the project folder',
    );
    if (path == null) return false;
    await vm.addProject(path);
    return true;
  }

  /// Fluxo "Criar Workspace": escolhe a pasta, abre o dialog de configurações
  /// (nome pré-preenchido com o da pasta + cor sugerida, ambos editáveis) e cria.
  // DEBUG (temporário): marcadores síncronos pra localizar o segfault no
  // Windows. Escrita síncrona+flush sobrevive a um crash nativo (print não).
  // Arquivo: <temp>/ck_trace.log
  void _mark(String m) {
    try {
      File(
        '${Directory.systemTemp.path}/ck_trace.log',
      ).writeAsStringSync('$m\n', mode: FileMode.append, flush: true);
    } catch (_) {}
  }

  Future<bool> _createWorkspace() async {
    final vm = _vm;
    _mark('picker:start');
    final path = await FilePicker.platform.getDirectoryPath(
      dialogTitle: 'Choose the workspace folder',
    );
    _mark('picker:done path=$path mounted=$mounted');
    if (path == null || !mounted) return false;
    final suggestedName = path.split('/').where((p) => p.isNotEmpty).lastOrNull;
    final suggestedColor =
        kWorkspacePalette[vm.rootProjects.length % kWorkspacePalette.length];
    _mark('dialog:show');
    final result = await showWorkspaceSettingsDialog(
      context,
      name: suggestedName ?? path,
      colorValue: suggestedColor,
      path: path,
    );
    _mark('dialog:done result=$result');
    if (result == null) return false;
    _mark('addProject:start');
    await vm.addProject(
      path,
      name: result.name,
      colorValue: result.colorValue,
      imagePath: result.imagePath,
    );
    _mark('addProject:done');
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
      imagePath: project.imagePath,
    );
    if (result == null) return;
    await vm.updateProject(
      project.id,
      name: result.name,
      colorValue: result.colorValue,
      imagePath: result.imagePath,
    );
    if (!mounted) return;
    if (result.name != project.name) {
      await showInfoDialog(
        context,
        title: 'Workspace renamed',
        message:
            'The new name "${result.name}" will only be sent to agents '
            'after restarting the workspace or the application.',
      );
    }
  }

  /// "Criar worktree": busca o namespace (branches + worktrees) pra validação ao
  /// vivo e abre o dialog. O dialog roda o `git worktree add` via `onCreate` e a
  /// VM auto-seleciona o fork novo (decisões 14, 21).
  Future<void> _createWorktree(Project root) async {
    final vm = _vm;
    final namespace = await vm.worktreeNamespace(root.id);
    if (!mounted) return;
    await showWorktreeCreateDialog(
      context,
      rootName: root.name,
      namespace: namespace,
      onCreate: (name) async {
        final res = await vm.createWorktree(root.id, name);
        return res.fold((_) => null, (e) => e.message);
      },
    );
  }

  /// "Fechar" o workspace (confirma → remove da lista local + encerra agentes).
  /// **Não deleta** a pasta no disco — só sai do cockpit.
  Future<void> _deleteProject(Project project) async {
    final vm = _vm;
    final ok = await showConfirmDialog(
      context,
      title: 'Close workspace',
      message:
          'Close "${project.name}"? The agents in this workspace will be '
          'terminated. The folder on disk is kept.',
      confirmLabel: 'Close',
      danger: true,
    );
    if (!ok) return;
    await vm.removeProject(project.id);
  }

  /// "Remover" a worktree (fork): confirma (aviso reforçado se a branch ainda
  /// não foi mergeada) → `git worktree remove` + `git branch -D`, encerra os
  /// agentes do fork e volta a seleção pro pai (decisões 6, 9). Erro do git →
  /// dialog de informação.
  Future<void> _removeWorktree(Project fork) async {
    final vm = _vm;
    final merged = await vm.isWorktreeBranchMerged(fork.id);
    if (!mounted) return;
    final warn = merged
        ? ''
        : '\n\nWarning: the branch "${fork.name}" has not been merged yet — '
              'removing it (git branch -D) discards the unmerged work.';
    final ok = await showConfirmDialog(
      context,
      title: 'Remove worktree',
      message:
          'Remove "${fork.name}"? The worktree folder and the branch will be '
          'deleted and the agents in this fork will be terminated.$warn',
      confirmLabel: 'Remove',
      danger: true,
    );
    if (!ok) return;
    final res = await vm.removeWorktree(fork.id);
    if (!mounted) return;
    final err = res.fold<String?>((_) => null, (e) => e.message);
    if (err != null) {
      await showInfoDialog(
        context,
        title: 'Failed to remove worktree',
        message: err,
      );
    }
  }

  /// Pede a subpasta onde o agente vai atuar e dispara [action] com o caminho
  /// relativo escolhido (`''` = raiz do projeto).
  Future<void> _pickSubfolderThen(void Function(String sub) action) async {
    final vm = _vm;
    if (!await _ensureProject()) return;
    if (!mounted) return;
    final project = vm.selectedProject;
    if (project == null) return;
    final chosen = await showSubfolderDialog(
      context,
      projectName: project.name,
      loadSubfolders: vm.subfolders,
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

  void _renameAgent(String agentId, String name) {
    final vm = _vm;
    final session = vm.session(agentId);
    if (session is! AgentSession) return;
    unawaited(
      vm.saveAgentConfig(
        agentId,
        agentName: name,
        autoStartRelay: session.autoStartRelay,
      ),
    );
  }

  void _toggleRelayAgent(String agentId) {
    final vm = _vm;
    final session = vm.session(agentId);
    if (session is! AgentSession) return;
    unawaited(
      vm.saveAgentConfig(
        agentId,
        agentName: session.title,
        autoStartRelay: !session.autoStartRelay,
      ),
    );
  }

  /// ⌘L (macOS) / Ctrl+L (Win/Linux): foca o input do agente focado quando o
  /// foco está dentro do shell. (Fora dele — clique no vazio — quem dispara é a
  /// ponte global de `main.dart`; ver [requestFocusActiveComposer].)
  Map<ShortcutActivator, VoidCallback> _focusComposerBindings() =>
      <ShortcutActivator, VoidCallback>{
        const SingleActivator(LogicalKeyboardKey.keyL, meta: true):
            _focusActiveComposer,
        const SingleActivator(LogicalKeyboardKey.keyL, control: true):
            _focusActiveComposer,
      };

  @override
  Widget build(BuildContext context) {
    final vm = context.watch<CockpitViewModel>();
    final colors = context.colors;

    if (!vm.ready) {
      return Scaffold(
        backgroundColor: colors.bg,
        child: const Center(child: CircularProgressIndicator(size: 20)),
      );
    }

    return CallbackShortcuts(
      bindings: _focusComposerBindings(),
      // Focus(autofocus) garante que a página esteja na cadeia de foco mesmo
      // antes de clicar em algo — senão o atalho ⌘L não dispara num agente
      // recém-aberto (nada focado ainda).
      child: Focus(
        autofocus: true,
        child: Scaffold(
          backgroundColor: colors.bg,
          child: Column(
            children: [
              CockpitTopbar(
                projectName: vm.selectedDisplayTitle ?? 'Cockpit',
                railVisible: vm.railVisible,
                treeVisible: vm.treeVisible,
                openEnabled: vm.selectedProject != null,
                onToggleRail: vm.toggleRail,
                onToggleTree: vm.toggleTree,
                availableApps: vm.availableApps,
                lastOpenAppId: context.select<SettingsController, String?>(
                  (c) => c.settings.lastOpenAppId,
                ),
                onOpenInApp: (id) {
                  final app = vm.availableApps
                      .where((a) => a.id == id)
                      .firstOrNull;
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
                            projects: vm.rootProjects,
                            worktreesOf: vm.worktreesOf,
                            selectedId: vm.selectedProjectId,
                            notificationCount: vm.notificationCount,
                            gitInfo: vm.gitInfo,
                            onSelect: vm.selectProject,
                            onAdd: _createWorkspace,
                            onConfigure: _configureProject,
                            onDelete: _deleteProject,
                            onCreateWorktree: _createWorktree,
                            onRemoveWorktree: _removeWorktree,
                            onReorder: (moved, target, before) =>
                                vm.reorderWorkspace(
                                  moved,
                                  target,
                                  before: before,
                                ),
                            onOpenSettings: () =>
                                context.pushNamed(RoutePaths.settings),
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
                          ? WelcomeView(onCreateWorkspace: _createWorkspace)
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
                            revision: vm.fileTreeRevision,
                            selectedPath: vm.selectedFileInTree,
                            listChildren: vm.listChildren,
                            gitStatusOf: vm.gitStatusForPath,
                            onOpenFile: (path) =>
                                vm.openFile(path, isPreview: false),
                            onTapFile: vm.openFile, // clique único = preview
                            onSelectFile:
                                vm.selectFileInTree, // atualiza highlight
                            onOpenWith: vm.openWithDefaultApp,
                            onCreateInFolder: (sub, terminal) =>
                                vm.newTabIn(sub, terminal: terminal),
                            onCreate: (parentDir, name, isFolder) => isFolder
                                ? vm.createDirIn(parentDir, name)
                                : vm.createFileIn(parentDir, name),
                            onRename: vm.renamePath,
                            onDelete: vm.deletePath,
                            footer: const _LspStatusBar(),
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
        ),
      ),
    );
  }

  int _activeIndex(CockpitViewModel vm) {
    final index = vm.projects.indexWhere((p) => p.id == vm.selectedProjectId);
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
          onRenameAgent: _renameAgent,
          onToggleRelayAgent: _toggleRelayAgent,
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

/// Barra de status do LSP no rodapé do pane de Files. Reflete o servidor da aba
/// **focada**: linguagem + rodando/parado + botão de reiniciar. Quando a aba não
/// é um arquivo de código (agente/terminal/sem aba), fica vazia — mas mantém a
/// altura, pra não pular o layout. Reage a mudança de aba (watch da VM) e a
/// subida/queda de servidor (stream `lspStatusChanges`).
class _LspStatusBar extends StatefulWidget {
  const _LspStatusBar();

  @override
  State<_LspStatusBar> createState() => _LspStatusBarState();
}

class _LspStatusBarState extends State<_LspStatusBar> {
  StreamSubscription<void>? _sub;
  bool _restarting = false;

  @override
  void initState() {
    super.initState();
    _sub = context.read<CockpitViewModel>().lspStatusChanges.listen((_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  Future<void> _restart(CockpitViewModel vm) async {
    setState(() => _restarting = true);
    await vm.restartFocusedLsp();
    if (mounted) setState(() => _restarting = false);
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final vm = context.watch<CockpitViewModel>();
    final status = vm.focusedLspStatus;

    return Container(
      height: 34,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: colors.border)),
      ),
      child: status == null
          ? Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'No LSP available',
                style: context.typo.label.copyWith(color: colors.text4),
              ),
            )
          : Row(
              children: [
                Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    color: status.running
                        ? const Color(0xFF22C55E)
                        : colors.text4,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '${status.label} LSP · ${status.running ? "running" : "stopped"}',
                    overflow: TextOverflow.ellipsis,
                    style: context.typo.label.copyWith(color: colors.text2),
                  ),
                ),
                Tooltip(
                  tooltip: (context) =>
                      const TooltipContainer(child: Text('Restart server')),
                  child: HoverTap(
                    borderRadius: BorderRadius.circular(6),
                    onTap: _restarting ? () {} : () => _restart(vm),
                    child: SizedBox(
                      width: 26,
                      height: 26,
                      child: Icon(
                        Icons.refresh,
                        size: 15,
                        color: _restarting ? colors.text4 : colors.text2,
                      ),
                    ),
                  ),
                ),
              ],
            ),
    );
  }
}
