import 'dart:async' show StreamSubscription, unawaited;
import 'dart:io';

import 'package:cockpit/app/core/app_intents.dart';
import 'package:cockpit/app/cockpit/domain/entities/project.dart';
import 'package:cockpit/app/core/routes.dart';
import 'package:cockpit/app/core/ui/menu/workspace_menu_bridge.dart';
import 'package:cockpit/app/cockpit/ui/session/agent_session.dart';
import 'package:cockpit/app/cockpit/ui/states/pane_node.dart';
import 'package:cockpit/app/cockpit/ui/viewmodels/cockpit_viewmodel.dart';
import 'package:cockpit/app/cockpit/ui/viewmodels/update_viewmodel.dart';
import 'package:cockpit/app/cockpit/domain/contracts/git_command_runner.dart';
import 'package:cockpit/app/cockpit/ui/widgets/git_process_dialog.dart';
import 'package:cockpit/app/cockpit/ui/widgets/widgets.dart';
import 'package:cockpit/app/core/ui/themes/themes.dart';
import 'package:cockpit/app/core/ui/settings_controller.dart';
import 'package:cockpit/app/core/ui/widgets/hover_tap.dart';
import 'package:cockpit/app/core/utils/native_folder_picker.dart';
import 'package:flutter/services.dart'
    show
        HardwareKeyboard,
        KeyDownEvent,
        KeyEvent,
        KeyRepeatEvent,
        LogicalKeyboardKey,
        PhysicalKeyboardKey;
import 'package:cockpit/app/core/ui/widgets/app_tooltip.dart';
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

  /// Sobe a cada Cmd+Shift+F → o [ContentSearchPanel] foca o campo de busca.
  final ValueNotifier<int> _searchFocusSignal = ValueNotifier<int>(0);

  /// Altura (arrastável + persistida) da lista de Tasks.
  double _tasksHeight = 200;
  static const double _tasksMin = 100;
  static const double _tasksMax = 520;

  @override
  void initState() {
    super.initState();
    // Registra a ponte do ⌘L global (handler em main.dart) → foca o input do
    // agente focado, mesmo quando o foco caiu num espaço vazio do shell.
    requestFocusActiveComposer = _focusActiveComposer;
    // Pontes do menu nativo (PlatformMenuBar vive acima da rota, sem acesso aos
    // ViewModels page-scoped): abrir projeto e verificar atualizações.
    requestOpenProject = () => unawaited(_addProject());
    // `checkNow()` (não `check()`): o menu é uma checagem pedida pelo usuário →
    // foreground, com resposta visível e ignorando "Skip this version".
    requestCheckForUpdates = () =>
        unawaited(context.read<UpdateViewModel>().checkNow());
    requestOpenSettings = () {
      if (!mounted) return;
      context.pushNamed(RoutePaths.settings);
    };
    // O motor/perfil precisam chegar antes do init: ele já pode restaurar ou
    // criar terminais, e a preferência do usuário deve valer desde o 1º buffer.
    final initialSettings = context.read<SettingsController>().settings;
    context.read<CockpitViewModel>()
      ..setDefaultTerminalProfileId(initialSettings.defaultTerminalProfileId)
      ..setDefaultTerminalEngine(initialSettings.terminalEngine);
    // Dispara o carregamento inicial dos ViewModels page-scoped ao montar a rota.
    // Os módulos provêm via `.new`, então não encadeiam mais `..init()`/`..check()`.
    context.read<CockpitViewModel>().init();
    context.read<UpdateViewModel>().check();
    // Publica o estado do workspace no menu File (New Agent / New Terminal): só
    // habilitam quando há workspace ativo. Re-sincroniza a cada mudança da VM.
    _workspaceMenu = context.read<WorkspaceMenuBridge>();
    _menuVm = context.read<CockpitViewModel>()..addListener(_syncWorkspaceMenu);
    _syncWorkspaceMenu();
    // Navegação direcional entre panes (⌘⌥ + setas). Vai por um handler global
    // do HardwareKeyboard — e NÃO pelo menu — porque no macOS as setas não
    // funcionam como *key equivalent* de menu (o campo/terminal focado consome a
    // seta antes do menu). O handler global vê o evento antes da distribuição por
    // foco, então pega mesmo com um terminal focado. Ver [_handlePaneNavKey].
    HardwareKeyboard.instance.addHandler(_handlePaneNavKey);
    HardwareKeyboard.instance.addHandler(_realmKeyHandler);
    // Mantém os overrides de comando do LSP (tela "Language") em sync com o pool:
    // empurra o estado atual e re-empurra a cada mudança das Configurações.
    _settings = context.read<SettingsController>()
      ..addListener(_syncLspCommands)
      ..addListener(_syncNotifications)
      ..addListener(_syncCockpit);
    _syncLspCommands();
    _syncNotifications();
    _syncCockpit();
    // Restaura a visibilidade dos painéis (rail/árvore) salva na sessão anterior
    // e persiste de volta a cada toggle. A VM é a fonte de verdade em runtime.
    final vm = context.read<CockpitViewModel>();
    vm.restorePanelVisibility(
      rail: _settings!.settings.railVisible,
      tree: _settings!.settings.treeVisible,
    );
    vm.onPanelVisibilityChanged = (rail, tree) =>
        _settings!.setPanelVisibility(rail: rail, tree: tree);
    _tasksHeight = _settings!.settings.tasksPanelHeight.clamp(
      _tasksMin,
      _tasksMax,
    );
  }

  SettingsController? _settings;
  Map<String, String> _lastLspCommands = const <String, String>{};

  /// Bridge do menu File (New Agent/Terminal) + a VM que observamos pra saber se
  /// há workspace ativo. Capturados no [initState] pra uso seguro no [dispose].
  WorkspaceMenuBridge? _workspaceMenu;
  CockpitViewModel? _menuVm;

  /// Espelha "há workspace ativo?" no menu; os callbacks abrem uma aba nova no
  /// workspace ativo (root do projeto). `setWorkspace` só notifica quando o
  /// booleano muda, então chamar a cada evento da VM é barato.
  void _syncWorkspaceMenu() {
    final vm = _menuVm;
    if (vm == null) return;
    _workspaceMenu?.setWorkspace(
      hasWorkspace: vm.selectedProject != null,
      agentTabsInUse: vm.hasAgentTabsInUse,
      // Cockpit é terminal-only → sem "New Agent" no menu File.
      agentsAllowed: !vm.isSystemTerminal(vm.selectedProjectId),
      // Agente pergunta a subpasta onde vai atuar (igual ao fluxo direto de
      // criar agente); terminal abre direto na raiz do workspace.
      onNewAgent: () => unawaited(
        _pickSubfolderThen((sub) => vm.newTabIn(sub, terminal: false)),
      ),
      onNewTerminal: () => vm.newTabIn('', terminal: true),
      onSplitRight: () => _splitFocused(SplitDir.vertical),
      onSplitDown: () => _splitFocused(SplitDir.horizontal),
      onToggleRail: vm.toggleRail,
      onToggleFiles: vm.toggleTree,
      onSelectTab: vm.selectTabByIndex,
      onSelectLastTab: vm.selectLastTab,
      onFocusPaneLeft: () => vm.focusPaneToward(PaneMove.left),
      onFocusPaneRight: () => vm.focusPaneToward(PaneMove.right),
      onFocusPaneUp: () => vm.focusPaneToward(PaneMove.up),
      onFocusPaneDown: () => vm.focusPaneToward(PaneMove.down),
    );
  }

  /// Divide a pane **focada** na direção [dir]. Terminal abre direto na raiz;
  /// agente pergunta a subpasta — mesma regra do menu de split da pane.
  void _splitFocused(SplitDir dir) {
    final vm = _vm;
    final projectId = vm.selectedProject?.id;
    if (projectId == null) return;
    final paneId = vm.focusedPaneId(projectId);
    if (paneId == null) return;
    if (vm.paneActiveIsTerminal(paneId)) {
      vm.splitPane(paneId, dir, '');
    } else {
      unawaited(_pickSubfolderThen((sub) => vm.splitPane(paneId, dir, sub)));
    }
  }

  /// Espelha o toggle de Notificações (aba das Configurações) para a VM, que
  /// gateia o disparo de fim de turno. A VM é page-scoped e não vê o
  /// `SettingsController` app-scoped, então a página empurra o valor.
  void _syncNotifications() {
    _vm.setNotificationsEnabled(_settings!.settings.notificationsEnabled);
    _vm.setSoundEnabled(_settings!.settings.soundEnabled);
    // Plano 50: perfil de terminal padrão do `+` — mesmo motivo (app-scoped →
    // VM page-scoped). Vale pra abas criadas daqui pra frente.
    _vm.setDefaultTerminalProfileId(
      _settings!.settings.defaultTerminalProfileId,
    );
    _vm.setDefaultTerminalEngine(_settings!.settings.terminalEngine);
  }

  /// Espelha o toggle "Show Cockpit terminal" (Configurações › General) para a
  /// VM, que injeta/remove o workspace de sistema em runtime (matando os PTYs no
  /// desligar). A VM é page-scoped e não vê o `SettingsController` app-scoped.
  void _syncCockpit() {
    _vm.setCockpitEnabled(_settings!.settings.showCockpit);
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

  /// Handler global de teclado pra navegação direcional entre panes. Roda antes
  /// da distribuição por foco (por isso pega ⌘⌥+seta mesmo com terminal focado,
  /// onde o menu nativo do macOS falharia). Consome (retorna `true`) só o combo
  /// exato ⌘⌥ (macOS) / Ctrl+⌥ (Win/Linux) + seta; qualquer outra tecla passa.
  bool _handlePaneNavKey(KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) return false;
    final move = switch (event.logicalKey) {
      LogicalKeyboardKey.arrowLeft => PaneMove.left,
      LogicalKeyboardKey.arrowRight => PaneMove.right,
      LogicalKeyboardKey.arrowUp => PaneMove.up,
      LogicalKeyboardKey.arrowDown => PaneMove.down,
      _ => null,
    };
    if (move == null) return false;
    final pressed = HardwareKeyboard.instance.logicalKeysPressed;
    final primary =
        pressed.contains(LogicalKeyboardKey.metaLeft) ||
        pressed.contains(LogicalKeyboardKey.metaRight) ||
        pressed.contains(LogicalKeyboardKey.controlLeft) ||
        pressed.contains(LogicalKeyboardKey.controlRight);
    final alt =
        pressed.contains(LogicalKeyboardKey.altLeft) ||
        pressed.contains(LogicalKeyboardKey.altRight);
    if (!primary || !alt) return false;
    _menuVm?.focusPaneToward(move);
    return true;
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_handlePaneNavKey);
    HardwareKeyboard.instance.removeHandler(_realmKeyHandler);
    _settings?.removeListener(_syncLspCommands);
    _settings?.removeListener(_syncNotifications);
    _settings?.removeListener(_syncCockpit);
    _menuVm?.removeListener(_syncWorkspaceMenu);
    _workspaceMenu?.setWorkspace(hasWorkspace: false);
    if (requestFocusActiveComposer == _focusActiveComposer) {
      requestFocusActiveComposer = null;
    }
    requestOpenProject = null;
    requestCheckForUpdates = null;
    requestOpenSettings = null;
    _searchFocusSignal.dispose();
    super.dispose();
  }

  /// Cmd+P / Ctrl+P: abre a palette de busca por **nome** de arquivo (quick
  /// open), reusando o índice do `FileSearcher` da VM.
  void _openFileFinder() {
    final vm = _vm;
    final project = vm.selectedProject;
    if (project == null) return;
    showFileFinderPalette(
      context,
      search: (query) => vm.searchFiles(project.path, query),
      onPick: vm.openProjectFile,
    );
  }

  /// Cmd+Shift+F / Ctrl+Shift+F: revela o painel de arquivos e foca a busca por
  /// **conteúdo** (find-in-files).
  void _focusContentSearch() {
    if (_vm.selectedProject == null) return;
    _vm.showTree();
    _searchFocusSignal.value++;
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
    final path = await NativeFolderPicker.pick(
      dialogTitle: 'Choose the project folder',
      initialDirectory: vm.selectedProject?.path,
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
    final path = await NativeFolderPicker.pick(
      dialogTitle: 'Choose the workspace folder',
      initialDirectory: vm.selectedProject?.path,
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

  /// Rótulo da operação git: nome do workspace em single-root; basename da
  /// root em multi-root (a root já veio escolhida do submenu do kebab).
  String _gitOpLabel(Project project, String rootPath) =>
      rootPath == project.path ? project.name : rootPath.split('/').last;

  /// "Criar worktree": busca o namespace (branches + worktrees) pra validação ao
  /// vivo e abre o dialog. O dialog roda o `git worktree add` via `onCreate` e a
  /// VM auto-seleciona o fork novo (decisões 14, 21).
  /// Sync (pull → push) do workspace, com o processo ao vivo num dialog.
  Future<void> _syncProject(Project project, String rootPath) async {
    final run = _vm.gitSync(rootPath);
    await showGitProcessDialog(
      context,
      title: 'Sync — ${_gitOpLabel(project, rootPath)}',
      output: run.output,
      success: run.exitCode.then((c) => c == 0),
    );
  }

  Future<void> _pullProject(Project project, String rootPath) async {
    final run = _vm.gitPull(rootPath);
    await showGitProcessDialog(
      context,
      title: 'Pull — ${_gitOpLabel(project, rootPath)}',
      output: run.output,
      success: run.exitCode.then((c) => c == 0),
    );
  }

  Future<void> _pushProject(Project project, String rootPath) async {
    final run = _vm.gitPush(rootPath);
    await showGitProcessDialog(
      context,
      title: 'Push — ${_gitOpLabel(project, rootPath)}',
      output: run.output,
      success: run.exitCode.then((c) => c == 0),
    );
  }

  /// "Fork Worktree": nova worktree ramificada da branch do fork [base] —
  /// mesmo dialog do criar, validando contra o namespace do repo de origem.
  Future<void> _forkWorktree(Project base) async {
    final vm = _vm;
    final namespace = await vm.forkWorktreeNamespace(base.id);
    if (!mounted) return;
    await showWorktreeCreateDialog(
      context,
      rootName: base.name,
      namespace: namespace,
      fork: true,
      onCreate: (name) async {
        final res = await vm.forkWorktree(base.id, name);
        return res.fold((_) => null, (e) => e.message);
      },
    );
  }

  /// "Update from Parent": mergeia a branch do pai (root de origem) no
  /// worktree — o inverso do merge. Conflito fica no worktree pro usuário
  /// resolver (o dialog mostra a saída do git).
  Future<void> _updateWorktree(Project fork) async {
    final run = _vm.updateWorktreeFromParent(fork);
    await showGitProcessDialog(
      context,
      title: 'Update from Parent — ${fork.name}',
      output: run.output,
      success: run.exitCode.then((c) => c == 0),
    );
  }

  /// "Merge to Parent": mergeia a branch do worktree no pai. Bloqueia se o
  /// worktree tem mudanças não commitadas; conflito → aborta e mostra o erro;
  /// sucesso → o VM remove o worktree e volta pro pai. Processo ao vivo no dialog.
  Future<void> _mergeWorktree(Project fork) async {
    final outcome = _vm.mergeWorktreeToParent(fork);
    await showGitProcessDialog(
      context,
      title: 'Merge to Parent — ${fork.name}',
      output: outcome.output,
      success: outcome.status.then((s) => s == GitMergeStatus.merged),
      finalMessage: (ok) =>
          ok ? 'Worktree merged and removed.' : 'Nothing was changed.',
    );
  }

  Future<void> _createWorktree(Project root, String rootPath) async {
    final vm = _vm;
    // Multi-root: a worktree é de UMA root — a escolha já veio do submenu do
    // kebab (o fork nasce como filho single-root apontando pro checkout dela).
    final namespace = await vm.worktreeNamespace(root.id, rootPath: rootPath);
    if (!mounted) return;
    await showWorktreeCreateDialog(
      context,
      rootName: _gitOpLabel(root, rootPath),
      namespace: namespace,
      onCreate: (name) async {
        final res = await vm.createWorktree(root.id, name, rootPath: rootPath);
        return res.fold((_) => null, (e) => e.message);
      },
    );
  }

  /// Destinos de "Move to realm" do kebab: todos os realms menos o atual do
  /// workspace; destino que já tem o mesmo path vem desabilitado. Com um realm
  /// só, lista vazia → item nem aparece.
  List<RealmTarget> _moveTargets(CockpitViewModel vm, String projectId) {
    if (vm.realms.length < 2) return const [];
    final matches = vm.projects.where((p) => p.id == projectId);
    if (matches.isEmpty) return const [];
    final project = matches.first;
    return [
      for (final realm in vm.realms)
        if (realm.id != project.realmId)
          (
            id: realm.id,
            name: realm.name,
            enabled: !vm.pathExistsInRealm(project.path, realm.id),
          ),
    ];
  }

  /// "New realm…" do dropdown do footer: pede o nome e já troca pro realm novo
  /// (nasce vazio — o rail mostra o estado vazio pra adicionar workspaces).
  Future<void> _createRealm() async {
    final vm = _vm;
    final name = await showRealmNameDialog(
      context,
      title: 'New realm',
      confirmLabel: 'Create',
      takenNames: vm.realms.map((r) => r.name).toSet(),
    );
    if (name == null) return;
    final realm = await vm.createRealm(name);
    await vm.switchRealm(realm.id);
  }

  Future<void> _manageRealms() => showRealmManagerDialog(context, vm: _vm);

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
  Map<ShortcutActivator, VoidCallback>
  _focusComposerBindings() => <ShortcutActivator, VoidCallback>{
    const SingleActivator(LogicalKeyboardKey.keyL, meta: true):
        _focusActiveComposer,
    const SingleActivator(LogicalKeyboardKey.keyL, control: true):
        _focusActiveComposer,
    const SingleActivator(LogicalKeyboardKey.keyP, meta: true): _openFileFinder,
    const SingleActivator(LogicalKeyboardKey.keyP, control: true):
        _openFileFinder,
    const SingleActivator(LogicalKeyboardKey.keyF, meta: true, shift: true):
        _focusContentSearch,
    const SingleActivator(LogicalKeyboardKey.keyF, control: true, shift: true):
        _focusContentSearch,
  };

  /// ⌘`/Ctrl+` próximo realm; com Shift, anterior. Handler **global** no
  /// [HardwareKeyboard] (registrado no initState), não um `CallbackShortcuts`:
  ///
  /// - `CallbackShortcuts` só recebe teclas com o foco primário DENTRO da
  ///   subtree — ciclar o realm destrói o nó focado (terminal/agente da árvore
  ///   antiga), o foco cai pro scope raiz e o atalho morria após o 1º uso;
  /// - casa pela **physical key**: a logical de ⇧` no macOS vira `~` (e a
  ///   combinação ⌘⇧ não batia com backquote nem tilde de forma confiável) —
  ///   pela física, Shift só decide a direção.
  ///
  /// Só `KeyDownEvent` (repeat não re-dispara); com Alt junto, ignora.
  bool _realmKeyHandler(KeyEvent event) {
    if (event is! KeyDownEvent ||
        event.physicalKey != PhysicalKeyboardKey.backquote) {
      return false;
    }
    final keys = HardwareKeyboard.instance;
    if ((!keys.isMetaPressed && !keys.isControlPressed) || keys.isAltPressed) {
      return false;
    }
    unawaited(_vm.cycleRealm(keys.isShiftPressed ? -1 : 1));
    return true;
  }

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
                onToggleRail: vm.toggleRail,
                onToggleTree: vm.toggleTree,
                filesEnabled: !vm.isSystemTerminal(vm.selectedProjectId),
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
                            rootsSummary: vm.rootsGitSummary,
                            forkOriginName: vm.forkOriginName,
                            rootsOf: (id) => [
                              for (final r in vm.rootsOf(id))
                                (
                                  path: r,
                                  name: r.split('/').last,
                                  git: vm.gitInfoForRoot(r),
                                ),
                            ],
                            onSelect: vm.selectProject,
                            onAdd: _createWorkspace,
                            onConfigure: _configureProject,
                            onDelete: _deleteProject,
                            onCreateWorktree: _createWorktree,
                            onRemoveWorktree: _removeWorktree,
                            onUpdateWorktree: _updateWorktree,
                            onForkWorktree: _forkWorktree,
                            onMergeWorktree: _mergeWorktree,
                            onSync: _syncProject,
                            onPull: _pullProject,
                            onPush: _pushProject,
                            onReorder: (moved, target, before) =>
                                vm.reorderWorkspace(
                                  moved,
                                  target,
                                  before: before,
                                ),
                            onOpenSettings: () =>
                                context.pushNamed(RoutePaths.settings),
                            realms: vm.realms,
                            activeRealm: vm.activeRealm,
                            onSwitchRealm: (id) =>
                                unawaited(vm.switchRealm(id)),
                            onCreateRealm: _createRealm,
                            onManageRealms: _manageRealms,
                            moveTargetsOf: (projectId) =>
                                _moveTargets(vm, projectId),
                            onMoveToRealm: (projectId, realmId) => unawaited(
                              vm.moveWorkspaceToRealm(projectId, realmId),
                            ),
                            cockpit: vm.cockpitWorkspace,
                            onSelectCockpit: () =>
                                vm.selectProject(Project.cockpitId),
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
                    // Cockpit (sem pasta) nunca mostra a árvore/tasks/busca,
                    // mesmo com `treeVisible` persistido de outro workspace.
                    if (vm.treeVisible &&
                        !vm.isSystemTerminal(vm.selectedProjectId))
                      Stack(
                        children: [
                          FileTreePanel(
                            // Pasta do workspace; reseta ao trocar de workspace.
                            key: ValueKey(vm.selectedProject?.path ?? ''),
                            width: _treeWidth,
                            rootPath: vm.selectedProject?.path ?? '',
                            // Roots derivadas (multi-root = seções por repo).
                            roots: [
                              for (final r
                                  in vm.selectedProject == null
                                      ? const <String>[]
                                      : vm.rootsOf(vm.selectedProject!.id))
                                WorkspaceRoot(
                                  path: r,
                                  name: r.split('/').last,
                                  git: vm.gitInfoForRoot(r),
                                ),
                            ],
                            onUnstageFile: vm.unstageFile,
                            onDiscardFile: vm.discardFile,
                            onCommitFile: vm.commitFile,
                            revision: vm.fileTreeRevision,
                            selectedPath: vm.selectedFileInTree,
                            listChildren: vm.listChildren,
                            gitStatusOf: vm.gitStatusForPath,
                            onOpenFile: (path) =>
                                vm.openFile(path, isPreview: false),
                            onTapFile: vm.openFile, // clique único = preview
                            onSelectFile:
                                vm.selectFileInTree, // atualiza highlight
                            onClearSelection: vm.clearFileSelection,
                            revealPath: vm.treeRevealPath,
                            revealGen: vm.treeRevealGen,
                            onOpenDiff: (path) =>
                                vm.openDiff(path, isPreview: false),
                            onTapDiff: vm.openDiff, // clique único = preview
                            isGitRepo:
                                vm.selectedProject != null &&
                                vm.isGitRepo(vm.selectedProject!.id),
                            changedPaths: vm.changedAbsolutePaths(),
                            onOpenWith: vm.openWithDefaultApp,
                            onCreateInFolder: (sub, terminal) =>
                                vm.newTabIn(sub, terminal: terminal),
                            onCreate: (parentDir, name, isFolder) => isFolder
                                ? vm.createDirIn(parentDir, name)
                                : vm.createFileIn(parentDir, name),
                            onRename: vm.renamePath,
                            onDelete: vm.deletePath,
                            onMove: vm.movePath,
                            onCopy: vm.copyToClipboard,
                            onCut: vm.cutToClipboard,
                            onPaste: vm.pasteInto,
                            canPaste: vm.canPaste,
                            searchPanel: vm.selectedProject == null
                                ? null
                                : ContentSearchPanel(
                                    fill: true,
                                    search: vm.searchContent,
                                    onOpenResult: vm.openSearchResult,
                                    focusSignal: _searchFocusSignal,
                                  ),
                            searchFocusSignal: _searchFocusSignal,
                            databasePanel: vm.selectedProject == null
                                ? null
                                : DbPanel(
                                    workspaceId: vm.selectedProject!.id,
                                    workspaceRoot: vm.selectedProject!.path,
                                  ),
                            tasksPanel: vm.selectedProject == null
                                ? null
                                : TasksPanel(
                                    cwd: vm.selectedProject!.path,
                                    listHeight: _tasksHeight,
                                    onResizeDelta: (dy) => setState(() {
                                      _tasksHeight = (_tasksHeight - dy).clamp(
                                        _tasksMin,
                                        _tasksMax,
                                      );
                                    }),
                                    onResizeEnd: () => context
                                        .read<SettingsController>()
                                        .setTasksPanelHeight(_tasksHeight),
                                  ),
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
          // Aba placeholder "Novo" (nem agente nem terminal): o novo pane vira
          // outro placeholder com o seletor Agent/Terminal (ou terminal direto
          // se `enableAgent` está off). Terminal abre na raiz; agente pergunta
          // a subpasta.
          onSplit: (dir) {
            if (vm.paneActiveIsEmpty(node.id)) {
              vm.splitPaneEmpty(node.id, dir);
            } else if (vm.paneActiveIsTerminal(node.id)) {
              vm.splitPane(node.id, dir, '');
            } else {
              _pickSubfolderThen((sub) => vm.splitPane(node.id, dir, sub));
            }
          },
          onFillEmpty: (emptyId, terminal) => terminal
              ? vm.fillEmpty(node.id, emptyId, '', terminal: true)
              : _pickSubfolderThen(
                  (sub) => vm.fillEmpty(node.id, emptyId, sub, terminal: false),
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
            // Delta incremental → fração; acumula sobre o frac ATUAL da árvore
            // (não o `aSize` do build, que fica velho entre eventos do mesmo
            // frame e fazia o divisor atrasar em relação ao mouse). `total` é
            // estável durante o arraste (o container não muda de tamanho).
            vm.resizeSplitBy(split.id, delta / total);
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
                AppTooltip(
                  message: 'Restart server',
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

/// Ações do menu de contexto do cabeçalho de uma root (multi-root).
