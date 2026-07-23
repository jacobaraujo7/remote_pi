import 'dart:async';
import 'dart:convert';
import 'dart:io' show File, FileSystemEntity, FileSystemEntityType, Platform;
import 'dart:math' show max;

import 'package:cockpit/app/core/data/setup/remote_pi_resolver.dart';

import 'package:cockpit/app/cockpit/domain/contracts/app_launcher.dart';
import 'package:cockpit/app/cockpit/domain/services/db_query_service.dart';
import 'package:cockpit/app/cockpit/domain/contracts/content_searcher.dart';
import 'package:cockpit/app/cockpit/domain/contracts/file_reader.dart';
import 'package:cockpit/app/cockpit/domain/contracts/file_searcher.dart';
import 'package:cockpit/app/cockpit/domain/contracts/file_system_mutator.dart';
import 'package:cockpit/app/cockpit/domain/contracts/file_system_reader.dart';
import 'package:cockpit/app/cockpit/domain/contracts/folder_lister.dart';
import 'package:cockpit/app/cockpit/domain/contracts/git_command_runner.dart';
import 'package:cockpit/app/cockpit/domain/contracts/git_diff_reader.dart';
import 'package:cockpit/app/cockpit/domain/contracts/notifier.dart';
import 'package:cockpit/app/cockpit/domain/contracts/project_repository.dart';
import 'package:cockpit/app/cockpit/domain/contracts/rpc_gateway_factory.dart';
import 'package:cockpit/app/cockpit/domain/contracts/session_history.dart';
import 'package:cockpit/app/cockpit/domain/contracts/terminal_gateway_factory.dart';
import 'package:cockpit/app/core/domain/contracts/terminal_profile_resolver.dart';
import 'package:cockpit/app/core/domain/entities/terminal_profile.dart';
import 'package:cockpit/app/core/domain/entities/app_settings.dart';
import 'package:cockpit/app/cockpit/domain/contracts/terminal_status_server.dart';
import 'package:cockpit/app/cockpit/domain/contracts/workspace_layout_store.dart';
import 'package:cockpit/app/cockpit/domain/contracts/worktree_manager.dart';
import 'package:cockpit/app/cockpit/domain/entities/content_search.dart';
import 'package:cockpit/app/cockpit/domain/entities/file_node.dart';
import 'package:cockpit/app/cockpit/domain/entities/file_view.dart';
import 'package:cockpit/app/cockpit/domain/entities/git_file_status.dart';
import 'package:cockpit/app/cockpit/domain/entities/git_info.dart';
import 'package:cockpit/app/cockpit/domain/entities/launchable_app.dart';
import 'package:cockpit/app/cockpit/domain/entities/project.dart';
import 'package:cockpit/app/cockpit/domain/entities/realm.dart';
import 'package:cockpit/app/cockpit/domain/value_objects/uid.dart';
import 'package:cockpit/app/cockpit/domain/entities/session_info.dart';
import 'package:cockpit/app/cockpit/domain/entities/thinking_level.dart';
import 'package:cockpit/app/cockpit/domain/entities/worktree.dart';
import 'package:cockpit/app/core/data/lsp/lsp_server_pool.dart';
import 'package:cockpit/app/core/data/lsp/lsp_text_edit.dart';
import 'package:cockpit/app/core/domain/entities/lsp_diagnostic.dart';
import 'package:cockpit/app/core/domain/result.dart';
import 'package:cockpit/app/core/utils/user_home.dart';
import 'package:cockpit/app/cockpit/ui/session/agent_session.dart';
import 'package:cockpit/app/cockpit/ui/session/diff_viewer_session.dart';
import 'package:cockpit/app/cockpit/ui/session/file_viewer_session.dart';
import 'package:cockpit/app/cockpit/ui/session/mongo_browser_session.dart';
import 'package:cockpit/app/cockpit/ui/session/pane_item.dart';
import 'package:cockpit/app/cockpit/ui/session/redis_browser_session.dart';
import 'package:cockpit/app/cockpit/domain/contracts/task_discovery.dart';
import 'package:cockpit/app/cockpit/domain/contracts/task_runner_gateway.dart';
import 'package:cockpit/app/cockpit/ui/session/task_output_session.dart';
import 'package:cockpit/app/cockpit/ui/session/task_terminal_store.dart';
import 'package:cockpit/app/cockpit/domain/contracts/terminal_scrollback_store.dart';
import 'package:cockpit/app/cockpit/ui/session/terminal_session.dart';
import 'package:cockpit/app/cockpit/ui/states/pane_node.dart';
import 'package:cockpit/app/cockpit/ui/viewmodels/cockpit_cli_handler.dart';
import 'package:cockpit/app/cockpit/ui/viewmodels/git_controller.dart';
import 'package:cockpit/app/cockpit/ui/viewmodels/realm_controller.dart';
import 'package:flutter/foundation.dart';
import 'package:window_manager/window_manager.dart';

/// Controlador do shell: projetos, árvore de splits **por projeto**, sessões de
/// agente, foco.
///
/// Cada projeto (workspace) tem o seu próprio multiplexador ([PaneNode] em
/// [_trees]); trocar de projeto só troca qual árvore é exibida (o `IndexedStack`
/// na página mantém todas montadas → estado preservado). As sessões (processos
/// `pi`) vivem em [_sessions] e seguem rodando independente da UI.
///
/// As operações de pane agem no **projeto ativo** ([_selectedProjectId]) — o
/// `IndexedStack` garante que só o projeto ativo é interativo.
class CockpitViewModel extends ChangeNotifier {
  CockpitViewModel(
    this._projects,
    this._factory,
    this._folders,
    this._history,
    this._notifier,
    this._fileSystem,
    this._terminalFactory,
    this._terminalProfiles,
    this._fileReader,
    this._layoutStore,
    this.git,
    this._fileSearcher,
    this._launcher,
    this._worktreeMgr,
    this._fileMutator,
    this._lsp,
    this._statusServer,
    this._contentSearcher,
    this._taskTerminals,
    this._scrollback,
    this._gitRunner,
    this._gitDiff,
    this.realmCtrl,
    this._taskDiscovery,
    this._taskRunner,
    this._dbService,
  ) {
    // Contexto do shell que o GitController precisa (page-scoped, mesma vida).
    git
      ..resolvePath = ((id) => _projectById(id)?.path)
      ..isSystemTerminal = isSystemTerminal
      ..selectedProjectId = (() => _selectedProjectId)
      ..pollTargets = _gitPollTargets
      ..onStructuralFsChange = _bumpFileTree
      ..onPoll = _reconcileOpenWorktrees;
    git.addListener(notifyListeners);
    realmCtrl.addListener(notifyListeners);
  }

  /// Alvos do poll de git: a família visível na rail (raiz do projeto
  /// selecionado + seus forks); vazio quando nada/Cockpit selecionado.
  List<String> _gitPollTargets() {
    final selected = _selectedProjectId;
    if (selected == null || isSystemTerminal(selected)) return const [];
    final rootId = _rootOf(selected);
    return [
      rootId,
      for (final fork in _worktrees[rootId] ?? const <Project>[]) fork.id,
    ];
  }

  final ProjectRepository _projects;

  /// Coleção de realms + ativo, extraída (ver [RealmController]). O VM delega
  /// o estado e mantém aqui só a orquestração de troca/exclusão.
  final RealmController realmCtrl;

  /// Descoberta e estado de tasks — usados só pelo comando `list-tasks` da CLI
  /// interna (mesmos binds do painel Tasks → mesma lista que a UI mostra).
  final TaskDiscovery _taskDiscovery;
  final TaskRunnerGateway _taskRunner;

  /// Motor de queries da DB tab — compartilhado com a CLI `cockpit db`
  /// (plano 51): mesma resolução de conexão/senha, mesma serialização.
  final DbQueryService _dbService;
  final RpcGatewayFactory _factory;
  final FolderLister _folders;
  final SessionHistory _history;
  final Notifier _notifier;
  final FileSystemReader _fileSystem;
  final TerminalGatewayFactory _terminalFactory;
  final TerminalProfileResolver _terminalProfiles;
  final FileReader _fileReader;
  final WorkspaceLayoutStore _layoutStore;

  /// Estado git extraído (info/roots/watcher/poll/comandos). O VM delega as
  /// leituras pra manter a API pública da UI e re-emite os notify dele.
  final GitController git;
  final FileSearcher _fileSearcher;
  final AppLauncherGateway _launcher;
  final WorktreeManager _worktreeMgr;
  final FileSystemMutator _fileMutator;
  final LspServerPool _lsp;
  final TerminalStatusServer _statusServer;
  final ContentSearcher _contentSearcher;
  final TaskTerminalStore _taskTerminals;
  final TerminalScrollbackStore _scrollback;
  final GitCommandRunner _gitRunner;
  final GitDiffReader _gitDiff;

  List<LaunchableApp> _availableApps = const [];

  final List<Project> _projectList = <Project>[];
  String? _selectedProjectId;
  final Map<String, PaneItem> _sessions = <String, PaneItem>{};

  /// Realms (conjuntos de workspaces) e o recorte ativo. [_projectList] guarda
  /// os workspaces de TODOS os realms (sessões de realms ocultos seguem vivas);
  /// só o filtro de exibição ([rootProjects]) muda com [realmCtrl.activeId].

  /// Espelha `AppSettings.showCockpit` (app-scoped, empurrado pela `CockpitPage`).
  /// Governa se o workspace de sistema "Cockpit" é injetado. Default `true`;
  /// antes de [init] terminar só guarda a flag (a injeção acontece no [init]).
  bool _cockpitEnabled = true;

  /// Watcher por aba de arquivo: relê o conteúdo ao vivo quando o disco muda
  /// (o agente edita o arquivo). Chaveado pelo id da sessão; cancelado no
  /// `_disposeSession`. O [_fileWatchDebounce] junta rajadas de eventos do editor.
  final Map<String, StreamSubscription<void>> _fileWatchers =
      <String, StreamSubscription<void>>{};
  final Map<String, Timer> _fileWatchDebounce = <String, Timer>{};

  /// Árvore de splits por projeto (workspace).
  final Map<String, PaneNode> _trees = <String, PaneNode>{};

  /// Pane focada por projeto.
  final Map<String, String> _focused = <String, String>{};

  /// Documentos de layout carregados do Hive no boot (lazy: o projeto só é
  /// reconstruído quando selecionado). `null` = projeto sem layout salvo.
  final Map<String, Map<String, dynamic>?> _savedLayouts =
      <String, Map<String, dynamic>?>{};

  /// Debounce de gravação por projeto (o resize é arrasto contínuo).
  final Map<String, Timer> _saveTimers = <String, Timer>{};

  /// `true` enquanto reconstruímos um projeto — evita gravar layout meio-feito.
  bool _restoring = false;

  /// Worktrees (forks) por workspace raiz, na ordem do `git worktree list`
  /// (decisão 20). Reconciliado contra o git nos ganchos de refresh; a
  /// existência mora no git, não no Hive (decisões 4, 17). Os mesmos `Project`s
  /// também entram em [_projectList] (pro IndexedStack e o lookup).
  final Map<String, List<Project>> _worktrees = <String, List<Project>>{};

  /// Root (path absoluto) que **originou** cada fork (fork.id → root path).
  /// Em single-root é o próprio path do pai; em multi-root, o repo filho de
  /// onde o `git worktree add` partiu — as ops de worktree (remove/merge/
  /// namespace) rodam contra ela, nunca contra a pasta-mãe.
  final Map<String, String> _forkOrigin = <String, String>{};

  /// Sobe a cada mutação na árvore (criar/renomear/deletar) — a `FileTreePanel`
  /// lê isso como token de refresh pra reler as pastas abertas (passo 3 da UI).
  int _fileTreeRevision = 0;
  int get fileTreeRevision => _fileTreeRevision;

  /// Caminho do arquivo atualmente selecionado no FileTreePanel (para highlight).
  String? _selectedFileInTree;
  String? get selectedFileInTree => _selectedFileInTree;

  /// Sinal de "revelar na árvore": path-alvo + geração. Sobe quando o usuário
  /// seleciona uma tab de FileView → a árvore destaca o arquivo e expande a root
  /// e os folders ancestrais **uma vez** (o usuário pode colapsar depois; a
  /// geração garante que só um tick novo re-expande). O highlight vai por
  /// [selectedFileInTree]; estes dois guiam a expansão.
  String? _treeRevealPath;
  String? get treeRevealPath => _treeRevealPath;
  int _treeRevealGen = 0;
  int get treeRevealGen => _treeRevealGen;

  bool _railVisible = false;
  bool _treeVisible = false;
  bool _ready = false;

  /// Persiste a visibilidade dos painéis (rail/árvore). A `CockpitPage` injeta o
  /// callback que grava no `SettingsController` app-scoped (a VM é page-scoped e
  /// não o enxerga). Chamado a cada mudança de visibilidade.
  void Function(bool rail, bool tree)? onPanelVisibilityChanged;

  /// Restaura a visibilidade dos painéis a partir das preferências salvas.
  /// Chamado uma vez pela página no `initState`, sem persistir de volta. **Não**
  /// notifica: roda antes do primeiro build (que já lê os campos frescos), e
  /// notificar aqui dispara `markNeedsBuild` no `_VMInherited` durante o build
  /// ("setState() called during build").
  void restorePanelVisibility({required bool rail, required bool tree}) {
    _railVisible = rail;
    _treeVisible = tree;
  }

  void _persistPanels() =>
      onPanelVisibilityChanged?.call(_railVisible, _treeVisible);
  int _seq = 0;

  /// Espelha `AppSettings.notificationsEnabled` (app-scoped, fora do grafo desta
  /// VM page-scoped). A `CockpitPage` empurra o valor do `SettingsController`.
  /// Gateia o disparo de notificação de fim de turno.
  bool _notificationsEnabled = true;
  void setNotificationsEnabled(bool value) => _notificationsEnabled = value;

  /// Espelha `AppSettings.soundEnabled`. Gateia o chime de fim de turno (tocado
  /// com a janela focada). A `CockpitPage` empurra o valor do controller.
  bool _soundEnabled = true;
  void setSoundEnabled(bool value) => _soundEnabled = value;

  /// Espelha `AppSettings.defaultTerminalProfileId` (plano 50). A `CockpitPage`
  /// empurra o valor do controller app-scoped. `null` = sem escolha → o resolver
  /// cai no fallback de plataforma (comportamento atual).
  String? _defaultTerminalProfileId;
  void setDefaultTerminalProfileId(String? id) =>
      _defaultTerminalProfileId = id;

  /// Perfil que o `+` abre agora: o configurado (se ainda existe) ou o fallback
  /// de plataforma. Síncrono — o cache do resolver é aquecido no boot (`main`).
  TerminalProfile get defaultTerminalProfile =>
      _terminalProfiles.effectiveDefault(_defaultTerminalProfileId);

  TerminalEngine _defaultTerminalEngine = TerminalEngine.ghostty;

  void setDefaultTerminalEngine(TerminalEngine engine) {
    _defaultTerminalEngine = engine;
    _taskTerminals.setDefaultEngine(engine);
  }

  /// Perfis descobertos, para o seletor ao lado do `+`. Já aquecidos no boot.
  List<TerminalProfile> get terminalProfiles =>
      _terminalProfiles.cachedProfiles;

  /// O seletor de terminal deve aparecer? **Só no Windows** — é lá que existe
  /// escolha real (PowerShell/cmd/WSL). No POSIX o perfil é o login shell do
  /// usuário: um item só, escolher não significa nada. Também exige 2+ perfis,
  /// senão o menu teria uma opção única.
  bool get showTerminalProfilePicker =>
      Platform.isWindows && terminalProfiles.length > 1;

  /// Paleta dos avatares de projeto (cores do design).
  static const List<int> _palette = <int>[
    0xFF6E56CF,
    0xFFE5484D,
    0xFF1AA5A0,
    0xFF3FB868,
    0xFFE0A33A,
    0xFF2F6FF0,
  ];

  String _nid(String prefix) => '$prefix${_seq++}';

  // ---- getters --------------------------------------------------------------
  List<Project> get projects => List<Project>.unmodifiable(_projectList);

  /// Realms na ordem de exibição do dropdown do footer.
  List<Realm> get realms => realmCtrl.realms;

  String get activeRealmId => realmCtrl.activeId;

  Realm get activeRealm => realmCtrl.active;

  /// Só os workspaces raiz **reais do realm ativo** (sem worktrees e sem o
  /// Cockpit sintético) — o nível de topo da lista de projetos do rail. O
  /// Cockpit é renderizado num slot próprio via [cockpitWorkspace] e fica de
  /// fora de reorder/menu/persist. Workspaces de outros realms permanecem em
  /// [_projectList] (sessões vivas), só saem do recorte exibido.
  List<Project> get rootProjects {
    final roots = _projectList
        .where(
          (p) =>
              p.parentId == null &&
              !p.isSystemTerminal &&
              p.realmId == realmCtrl.activeId,
        )
        .toList();
    // Ordem manual do usuário (drag-drop); createdAt como desempate/fallback.
    roots.sort((a, b) {
      final byOrder = a.order.compareTo(b.order);
      return byOrder != 0 ? byOrder : a.createdAt.compareTo(b.createdAt);
    });
    return List<Project>.unmodifiable(roots);
  }

  /// O workspace de sistema "Cockpit" (terminal-only), se estiver habilitado e
  /// injetado; `null` caso contrário. Renderizado num slot próprio no rail.
  Project? get cockpitWorkspace => _projectById(Project.cockpitId);

  /// `true` se [id] é o workspace de sistema "Cockpit". Chokepoint usado pelos
  /// gates de serviços de path (git/árvore/tasks) e pela UI (Files desabilitado,
  /// agente off).
  bool isSystemTerminal(String? id) =>
      _projectById(id)?.isSystemTerminal ?? false;

  /// Worktrees (forks) de um workspace raiz, na ordem do git (vazio se nenhuma).
  List<Project> worktreesOf(String rootId) =>
      _worktrees[rootId] ?? const <Project>[];

  String? get selectedProjectId => _selectedProjectId;
  Project? get selectedProject => _projectById(_selectedProjectId);

  /// Título pro topbar: `"<workspace> · <worktree>"` quando um fork está
  /// selecionado (separador middle-dot U+00B7); só o nome do workspace caso
  /// contrário. `null` quando nada está selecionado.
  String? get selectedDisplayTitle {
    final p = selectedProject;
    if (p == null) return null;
    final parentId = p.parentId;
    if (parentId == null) return p.name;
    final root = _projectById(parentId);
    return root == null ? p.name : '${root.name} · ${p.name}';
  }

  /// `false` até [init] terminar de carregar os projetos do Hive.
  bool get ready => _ready;
  bool get railVisible => _railVisible;
  bool get treeVisible => _treeVisible;
  List<LaunchableApp> get availableApps =>
      List<LaunchableApp>.unmodifiable(_availableApps);
  PaneItem? session(String id) => _sessions[id];

  /// Todas as sessões abertas (qualquer workspace) — usado pela CLI interna
  /// ([CockpitCliHandler]) pra list-panes/resolução por label.
  Iterable<PaneItem> get allSessions => _sessions.values;

  /// Lookup público de projeto por id (CLI interna e colaboradores).
  Project? projectById(String? id) => _projectById(id);

  /// Id da folha (coluna de splits) que contém a aba [tabId] no projeto
  /// [projectId], ou `null` se não achar. Usado pra abrir o arquivo ao lado do
  /// terminal que emitiu o `cockpit open`.
  String? leafOfTab(String projectId, String tabId) {
    final tree = _trees[projectId];
    if (tree == null) return null;
    for (final leaf in leaves(tree)) {
      if (leaf.tabs.contains(tabId)) return leaf.id;
    }
    return null;
  }

  /// Handler da CLI interna `cockpit` — colaborador extraído; criado aqui
  /// (e não no módulo) porque referencia o próprio VM.
  late final CockpitCliHandler _cli = CockpitCliHandler(
    this,
    _dbService,
    _taskDiscovery,
    _taskRunner,
    _taskTerminals,
  );

  /// `true` se existe ao menos uma aba de agente **real** (não o placeholder
  /// vazio `AgentStatus.empty`). Usado pra impedir desligar `enableAgent` com
  /// agentes em uso.
  bool get hasAgentTabsInUse => _sessions.values.whereType<AgentSession>().any(
    (a) => a.status != AgentStatus.empty,
  );

  /// Roots git do projeto. Sempre não-vazio: single-root = `[path]`
  /// (comportamento histórico, N=1); multi-root = as filhas-repo derivadas.
  List<String> rootsOf(String projectId) => git.rootsOf(projectId);

  /// `true` quando o workspace é multi-root (pasta-mãe sem `.git` com 2+
  /// repos filhos). Toda a UI multi-root é gateada por isto — N=1 nunca muda.
  bool isMultiRoot(String projectId) => rootsOf(projectId).length > 1;

  /// Estado git de uma **root** específica ([rootPath] absoluto).
  GitInfo? gitInfoForRoot(String rootPath) => git.infoForRoot(rootPath);

  /// Estado git do projeto (branch + sujos), ou `null` se não for repo git.
  /// Em multi-root não existe "o" GitInfo do workspace — devolve `null` (a
  /// rail usa [rootsGitSummary] pro chip agregado).
  GitInfo? gitInfo(String projectId) => git.infoOf(projectId);

  /// Agregado pro chip da rail em multi-root: (nº de roots, roots com
  /// **alteração de arquivo**). Ver [GitController.rootsSummary].
  (int roots, int dirtyRoots) rootsGitSummary(String projectId) =>
      git.rootsSummary(projectId);

  /// Root (path absoluto) que contém [absolutePath] no projeto [projectId],
  /// ou `null` se o caminho está fora de todas (ex.: solto na pasta-mãe).
  String? rootContaining(String projectId, String absolutePath) {
    for (final r in rootsOf(projectId)) {
      if (absolutePath == r || absolutePath.startsWith('$r/')) return r;
    }
    return null;
  }

  /// Status git (cor) de um caminho **absoluto** dentro do projeto selecionado —
  /// arquivo ou pasta (agregada). `null` = limpo/fora de repo. Usado pela árvore
  /// de arquivos pra colorir cada linha. Resolve a **root** dona do caminho
  /// (single-root: a própria raiz, como sempre).
  GitFileStatus? gitStatusForPath(String absolutePath) {
    final pid = _selectedProjectId;
    if (pid == null) return null;
    final root = rootContaining(pid, absolutePath);
    if (root == null) return null;
    // A própria pasta da root (multi-root): o rel seria vazio e sumiria — usa
    // o agregado da root inteira pra pasta acender visto de fora.
    if (absolutePath == root) return git.statusForRoot(root);
    return git.statusForRelPath(root, _subOf(absolutePath, root));
  }

  /// Aba que o usuário está olhando.
  PaneItem? get focusedAgent {
    final id = _focusedAgentId;
    return id == null ? null : _sessions[id];
  }

  /// Filhos de uma pasta (lazy-load da árvore de arquivos).
  Future<List<FileNode>> listChildren(String path) =>
      _fileSystem.children(path);

  /// Arquivos de [cwd] que casam com [query] (autocomplete do `@`). Caminhos
  /// relativos a [cwd].
  Future<List<String>> searchFiles(String cwd, String query) =>
      _fileSearcher.search(cwd, query);

  /// Abre um arquivo num viewer. Sem [inPane], usa a pane focada (duplo-clique
  /// na árvore); com [inPane], abre naquela pane e a foca (arrastar arquivo →
  /// pane). Binário/vídeo/grande demais → não abre.
  ///
  /// Se [isPreview] for `true` (padrão), usa o comportamento VSCode:
  /// - Se já existe um preview aberto na pane, substitui o conteúdo
  /// - Se a aba ativa é um preview, substitui em vez de criar nova aba
  /// - Duplo-clique deve passar `isPreview: false` para criar aba normal
  /// Abre (ou foca, se já aberta) a aba read-only de output da task [taskId] na
  /// pane focada. O buffer vive no `TaskTerminalStore` — fechar a aba não perde
  /// nada e não mexe na task.
  void openTaskOutput(String taskId, String label) {
    final projectId = _selectedProjectId;
    final tree = _activeTree;
    final paneId = projectId == null ? null : _focused[projectId];
    if (projectId == null || tree == null || paneId == null) return;

    // Já aberta nesta pane? só foca.
    for (final entry in _sessions.entries) {
      final s = entry.value;
      if (s is TaskOutputSession &&
          s.taskId == taskId &&
          s.projectId == projectId) {
        _trees[projectId] = updateLeaf(
          tree,
          paneId,
          (p) => p.copyWith(active: entry.key),
        );
        notifyListeners();
        return;
      }
    }

    final session = TaskOutputSession(
      id: _nid('t'),
      projectId: projectId,
      taskId: taskId,
      label: label,
      terminal: _taskTerminals.terminalFor(taskId),
      workingDirectory: selectedProject?.path ?? '',
    );
    _sessions[session.id] = session;

    final lf = findLeaf(tree, paneId);
    final only = lf?.tabs.length == 1 ? _sessions[lf!.tabs.first] : null;
    if (lf != null &&
        only is AgentSession &&
        only.status == AgentStatus.empty) {
      // Pane só com placeholder vazio → substitui.
      final emptyId = lf.tabs.first;
      _trees[projectId] = updateLeaf(
        tree,
        paneId,
        (p) => p.copyWith(tabs: [session.id], active: session.id),
      );
      _disposeSession(emptyId);
    } else {
      _trees[projectId] = updateLeaf(
        tree,
        paneId,
        (p) => p.copyWith(tabs: [...p.tabs, session.id], active: session.id),
      );
    }
    notifyListeners();
  }

  Future<void> openFile(
    String path, {
    String? inPane,
    bool isPreview = true,
  }) async {
    final projectId = _selectedProjectId;
    final tree = _activeTree;
    final paneId = inPane ?? (projectId == null ? null : _focused[projectId]);
    if (projectId == null || tree == null || paneId == null) return;
    final leaf = findLeaf(tree, paneId);
    if (leaf == null) return;
    // Soltar um arquivo numa pane específica também a foca.
    if (inPane != null) _focused[projectId] = inPane;

    // Se isPreview, tenta reutilizar a aba de preview existente ou substituir a ativa.
    // Se não é preview, cria uma aba normal (comportamento original).
    FileViewerSession? previewCandidate;
    for (final tabId in leaf.tabs) {
      final s = _sessions[tabId];
      if (s is FileViewerSession) {
        // Se já aberto, só seleciona (mas transforma preview em normal se não é preview).
        if (s.path == path) {
          if (!isPreview && s.isPreview) s.pin();
          _trees[projectId] = updateLeaf(
            tree,
            paneId,
            (p) => p.copyWith(active: tabId),
          );
          notifyListeners();
          return;
        }
        // Guarda o primeiro preview encontrado para possível reutilização.
        if (isPreview && s.isPreview && previewCandidate == null) {
          previewCandidate = s;
        }
      }
    }

    final view = await _fileReader.read(path);
    if (view is FileViewUnsupported) return; // binário/vídeo: não abre

    // Se é preview e temos um candidato, reutiliza (substitui conteúdo).
    if (isPreview && previewCandidate != null) {
      previewCandidate.path = path;
      previewCandidate.view = view;
      previewCandidate.dirty = false;
      previewCandidate.notifyListeners(); // Força rebuild do FileViewer
      _trees[projectId] = updateLeaf(
        tree,
        paneId,
        (p) => p.copyWith(active: previewCandidate!.id),
      );
      notifyListeners();
      return;
    }

    // Cria nova aba (preview ou normal).
    final viewer = FileViewerSession(
      id: _nid('v'),
      projectId: projectId,
      path: path,
      view: view,
      isPreview: isPreview,
    );
    _sessions[viewer.id] = viewer;
    _watchFileViewer(viewer);

    // Se a pane só tem o placeholder vazio, substitui; senão adiciona aba.
    // Se é preview e a aba ativa é um FileViewer, substitui em vez de adicionar.
    final current = _trees[projectId] ?? tree;
    final lf = findLeaf(current, paneId);
    final activeTabId = lf?.active;
    final activeTab = activeTabId != null ? _sessions[activeTabId] : null;
    final only = lf?.tabs.length == 1 ? _sessions[lf!.tabs.first] : null;

    if (isPreview && activeTab is FileViewerSession && !activeTab.isPreview) {
      // Preview substituiria aba normal → adiciona ao lado.
      _trees[projectId] = updateLeaf(
        current,
        paneId,
        (p) => p.copyWith(tabs: [...p.tabs, viewer.id], active: viewer.id),
      );
    } else if (isPreview &&
        activeTab is FileViewerSession &&
        activeTab.isPreview) {
      // Preview substituir outro preview → substitui a aba ativa.
      final oldId = activeTabId;
      _trees[projectId] = updateLeaf(
        current,
        paneId,
        (p) => p.copyWith(
          tabs: [...p.tabs.where((t) => t != oldId), viewer.id],
          active: viewer.id,
        ),
      );
      _disposeSession(oldId!);
    } else if (lf != null &&
        only is AgentSession &&
        only.status == AgentStatus.empty) {
      // Placeholder vazio → substitui.
      final emptyId = lf.tabs.first;
      _trees[projectId] = updateLeaf(
        current,
        paneId,
        (p) => p.copyWith(tabs: [viewer.id], active: viewer.id),
      );
      _disposeSession(emptyId);
    } else {
      // Adiciona nova aba.
      _trees[projectId] = updateLeaf(
        current,
        paneId,
        (p) => p.copyWith(tabs: [...p.tabs, viewer.id], active: viewer.id),
      );
    }
    notifyListeners();
  }

  /// Abre uma tab `.dbq` **untitled** (scratch, VSCode-style): buffer em
  /// memória, sem arquivo no disco até o primeiro save. [connName] pré-seleciona
  /// a conexão no frontmatter. Plano 51.
  void openScratchDbq({String? connName, String? sql}) {
    final projectId = _selectedProjectId;
    final tree = _activeTree;
    final paneId = projectId == null ? null : _focused[projectId];
    if (projectId == null || tree == null || paneId == null) return;

    // Numeração sequencial dos untitled abertos.
    final used = _sessions.values
        .whereType<FileViewerSession>()
        .where((s) => s.scratch)
        .length;
    final body = sql ?? 'SELECT 1;';
    final content = connName == null ? '$body\n' : '-- db: $connName\n$body\n';
    final scratch = FileViewerSession(
      id: _nid('v'),
      projectId: projectId,
      path: '', // sintético — sem arquivo até salvar
      view: FileViewText(content, language: 'dbq'),
      scratch: true,
      scratchTitle: 'Untitled-${used + 1}.dbq',
    );
    _sessions[scratch.id] = scratch;
    _addLeafTab(projectId, paneId, scratch.id);
    notifyListeners();
  }

  /// Abre (ou foca) a tabela Redis da conexão [connName] (plano 52). Uma tab
  /// por conexão+projeto: reabrir foca a existente em vez de duplicar.
  /// [pattern] (CLI `redis browse`, plano 53) semeia o campo de busca — na tab
  /// já aberta ele SUBSTITUI o filtro atual (decisão E).
  /// [projectId] default = projeto selecionado. `false` = workspace sem tab
  /// aberta pra receber o browser.
  bool openRedisBrowser(String connName, {String? projectId, String? pattern}) {
    final session = _openBrowserTab(
      projectId,
      matches: (s) => s is RedisBrowserSession && s.connName == connName,
      make: (id, pid, path) => RedisBrowserSession(
        id: id,
        projectId: pid,
        connName: connName,
        workingDirectory: path,
      ),
    );
    if (session == null) return false;
    if (pattern != null) {
      (session as RedisBrowserSession).requestPattern(pattern);
    }
    return true;
  }

  /// Abre (ou foca) o collection browser Mongo (plano 53). Uma tab por
  /// conexão+collection+projeto. [filter] semeia a filter bar (substitui na
  /// tab já aberta — decisão E).
  bool openMongoBrowser(
    String connName,
    String collection, {
    String? projectId,
    String? filter,
  }) {
    final session = _openBrowserTab(
      projectId,
      matches: (s) =>
          s is MongoBrowserSession &&
          s.connName == connName &&
          s.collection == collection,
      make: (id, pid, path) => MongoBrowserSession(
        id: id,
        projectId: pid,
        connName: connName,
        collection: collection,
        workingDirectory: path,
      ),
    );
    if (session == null) return false;
    if (filter != null) (session as MongoBrowserSession).requestFilter(filter);
    return true;
  }

  /// Núcleo comum dos browsers de banco: foca a tab existente que [matches]
  /// no projeto alvo, ou cria via [make] na pane focada. Devolve a sessão
  /// (existente ou nova), ou `null` se o projeto não tem árvore montada.
  PaneItem? _openBrowserTab(
    String? projectId, {
    required bool Function(PaneItem) matches,
    required PaneItem Function(String id, String projectId, String path) make,
  }) {
    final pid = projectId ?? _selectedProjectId;
    final tree = pid == null ? null : _trees[pid];
    if (pid == null || tree == null) return null;
    final paneId = _focused[pid] ?? leaves(tree).firstOrNull?.id;
    if (paneId == null) return null;

    for (final s in _sessions.values) {
      if (s.projectId == pid && matches(s)) {
        for (final leaf in leaves(tree)) {
          if (leaf.tabs.contains(s.id)) {
            if (pid == _selectedProjectId) selectTab(leaf.id, s.id);
            return s;
          }
        }
      }
    }

    final session = make(_nid('v'), pid, _projectById(pid)?.path ?? '');
    _sessions[session.id] = session;
    _addLeafTab(pid, paneId, session.id);
    notifyListeners();
    return session;
  }

  /// Salva um buffer scratch como arquivo real [fileName] na raiz do workspace
  /// (o `.dbq` é anexado se faltar). Retarga a sessão, arma o watcher e limpa
  /// o flag scratch → daí vira uma tab de arquivo normal. Plano 51.
  Future<Result<void, String>> saveScratchAs(
    String sessionId,
    String fileName,
    String content,
  ) async {
    final s = _sessions[sessionId];
    if (s is! FileViewerSession || !s.scratch) {
      return const Failure('not a scratch tab');
    }
    var name = fileName.trim();
    if (name.isEmpty) return const Failure('empty name');
    if (!name.toLowerCase().endsWith('.dbq')) name = '$name.dbq';
    final invalid = _validateName(name);
    if (invalid != null) return Failure(invalid);
    final root = _projectById(s.projectId)?.path;
    if (root == null) return const Failure('no workspace');
    final path = _join(root, name);
    if (await File(path).exists()) return Failure('"$name" already exists');

    if (!await _fileReader.write(path, content)) {
      return const Failure('could not write file');
    }
    s
      ..path = path
      ..scratch = false
      ..scratchTitle = null
      ..view = await _fileReader.read(path)
      ..dirty = false;
    _watchFileViewer(s);
    _bumpFileTree();
    s.notifyListeners();
    notifyListeners();
    return const Success(null);
  }

  /// Enxerta [tabId] como aba nova no leaf [paneId] (substituindo o placeholder
  /// vazio se for o único). Extraído de [openFile] para reuso pelo scratch.
  void _addLeafTab(String projectId, String paneId, String tabId) {
    final current = _trees[projectId];
    if (current == null) return;
    final lf = findLeaf(current, paneId);
    final only = lf?.tabs.length == 1 ? _sessions[lf!.tabs.first] : null;
    if (lf != null &&
        only is AgentSession &&
        only.status == AgentStatus.empty) {
      final emptyId = lf.tabs.first;
      _trees[projectId] = updateLeaf(
        current,
        paneId,
        (p) => p.copyWith(tabs: [tabId], active: tabId),
      );
      _disposeSession(emptyId);
    } else {
      _trees[projectId] = updateLeaf(
        current,
        paneId,
        (p) => p.copyWith(tabs: [...p.tabs, tabId], active: tabId),
      );
    }
  }

  // === Git diff viewer (feature "more git") ===

  /// `true` se o workspace [projectId] tem git — single-root: a raiz é repo;
  /// multi-root: qualquer root (habilita a aba Source Control).
  bool isGitRepo(String projectId) => git.isGitRepo(projectId);

  /// Status git (relativo à **root**) dos arquivos com mudança de uma root.
  Map<String, GitFileStatus> changedFilesOfRoot(String rootPath) =>
      git.changedFilesOfRoot(rootPath);

  /// Caminhos **absolutos** com mudança git do projeto selecionado (exclui
  /// ignorados), varrendo **todas as roots** — alimenta a árvore podada do
  /// modo Source Control (que agrupa por root quando multi-root).
  List<String> changedAbsolutePaths() {
    final project = selectedProject;
    if (project == null) return const [];
    final out = <String>[];
    for (var root in rootsOf(project.id)) {
      if (root.endsWith('/')) root = root.substring(0, root.length - 1);
      changedFilesOfRoot(root).forEach((rel, status) {
        if (status == GitFileStatus.ignored) return;
        out.add('$root/$rel');
      });
    }
    return out;
  }

  /// Abre o **diff** de um arquivo contra o HEAD numa aba de viewer (split, só
  /// leitura). Espelha [openFile]: reutiliza a aba de preview quando possível.
  Future<void> openDiff(String path, {bool isPreview = true}) async {
    final projectId = _selectedProjectId;
    final tree = _activeTree;
    final paneId = projectId == null ? null : _focused[projectId];
    if (projectId == null || tree == null || paneId == null) return;
    final leaf = findLeaf(tree, paneId);
    if (leaf == null) return;
    // Diff roda contra a root que contém o arquivo (multi-root: o repo filho).
    final root = rootContaining(projectId, path);
    if (root == null) return;

    // Já aberto? Seleciona (e fixa se não é preview).
    DiffViewerSession? previewCandidate;
    for (final tabId in leaf.tabs) {
      final s = _sessions[tabId];
      if (s is DiffViewerSession) {
        if (s.path == path) {
          if (!isPreview && s.isPreview) s.pin();
          _trees[projectId] = updateLeaf(
            tree,
            paneId,
            (p) => p.copyWith(active: tabId),
          );
          notifyListeners();
          return;
        }
        if (isPreview && s.isPreview && previewCandidate == null) {
          previewCandidate = s;
        }
      }
    }

    final diff = await _gitDiff.read(root, path);

    // Reutiliza a aba de preview de diff, se houver.
    if (isPreview && previewCandidate != null) {
      previewCandidate
        ..path = path
        ..diff = diff
        ..notifyListeners();
      _trees[projectId] = updateLeaf(
        tree,
        paneId,
        (p) => p.copyWith(active: previewCandidate!.id),
      );
      notifyListeners();
      return;
    }

    final viewer = DiffViewerSession(
      id: _nid('d'),
      projectId: projectId,
      path: path,
      diff: diff,
      isPreview: isPreview,
    );
    _sessions[viewer.id] = viewer;

    final current = _trees[projectId] ?? tree;
    final lf = findLeaf(current, paneId);
    final activeTabId = lf?.active;
    final activeTab = activeTabId != null ? _sessions[activeTabId] : null;
    final only = lf?.tabs.length == 1 ? _sessions[lf!.tabs.first] : null;

    if (isPreview && activeTab is DiffViewerSession && activeTab.isPreview) {
      // Preview substitui preview.
      final oldId = activeTabId;
      _trees[projectId] = updateLeaf(
        current,
        paneId,
        (p) => p.copyWith(
          tabs: [...p.tabs.where((t) => t != oldId), viewer.id],
          active: viewer.id,
        ),
      );
      _disposeSession(oldId!);
    } else if (lf != null &&
        only is AgentSession &&
        only.status == AgentStatus.empty) {
      // Placeholder vazio → substitui.
      final emptyId = lf.tabs.first;
      _trees[projectId] = updateLeaf(
        current,
        paneId,
        (p) => p.copyWith(tabs: [viewer.id], active: viewer.id),
      );
      _disposeSession(emptyId);
    } else {
      _trees[projectId] = updateLeaf(
        current,
        paneId,
        (p) => p.copyWith(tabs: [...p.tabs, viewer.id], active: viewer.id),
      );
    }
    notifyListeners();
  }

  /// Seleciona um arquivo no FileTreePanel (atualiza o highlight).
  void selectFileInTree(String path) {
    _selectedFileInTree = path;
    notifyListeners();
  }

  /// Limpa a seleção do FileTreePanel (clicar em área vazia da árvore) — some
  /// o highlight e o New file/folder do header volta a mirar a raiz.
  void clearFileSelection() {
    if (_selectedFileInTree == null) return;
    _selectedFileInTree = null;
    notifyListeners();
  }

  // ---- busca (find-in-files + abrir resultado) ------------------------------

  /// Busca por **conteúdo** na pasta do projeto selecionado (painel Cmd+Shift+F).
  /// Stream incremental por arquivo; vazio se não há projeto. Ver [ContentSearcher].
  Stream<FileMatches> searchContent(
    String term, {
    bool caseSensitive = false,
    bool wholeWord = false,
    bool regex = false,
  }) {
    final root = selectedProject?.path;
    if (root == null) return const Stream<FileMatches>.empty();
    return _contentSearcher.search(
      ContentQuery(
        root: root,
        term: term,
        caseSensitive: caseSensitive,
        wholeWord: wholeWord,
        regex: regex,
      ),
    );
  }

  /// Caminho absoluto de um [relative] (relativo ao root do projeto), ou `null`
  /// se não há projeto selecionado.
  String? _absoluteOf(String relative) {
    final root = selectedProject?.path;
    if (root == null) return null;
    return '$root/$relative';
  }

  /// Abre um arquivo referenciado no **terminal** (Cmd+clique). [token] pode ser
  /// absoluto, relativo ao [cwd] vivo do shell (OSC 7) ou começar com `~`. Abre
  /// aba normal e revela [line] (base 1) quando informada. Sem-op se o token não
  /// resolve. O FileViewer trata caminho inexistente por conta própria.
  Future<void> openTerminalPath(String token, {String? cwd, int? line}) async {
    final abs = _resolveTerminalPath(token, cwd);
    if (abs == null) return;
    await openFile(abs, isPreview: false);
    if (line != null) {
      for (final s in _sessions.values) {
        if (s is FileViewerSession && s.path == abs) s.reveal(line);
      }
    }
  }

  /// Resolve um token de caminho do terminal para absoluto: expande `~`, junta
  /// com [cwd] se relativo, e normaliza `.`/`..`. `null` se não dá pra resolver.
  String? _resolveTerminalPath(String token, String? cwd) {
    var t = token.trim();
    if (t.isEmpty) return null;
    if (t == '~' || t.startsWith('~/')) {
      final home = userHome();
      if (home == null) return null;
      t = t == '~' ? home : '$home/${t.substring(2)}';
    }
    final isAbsolute =
        t.startsWith('/') ||
        (Platform.isWindows && RegExp(r'^[a-zA-Z]:[\\/]').hasMatch(t));
    if (!isAbsolute) {
      if (cwd == null || cwd.isEmpty) return null;
      t = '$cwd/$t';
    }
    return _normalizePath(t);
  }

  /// Colapsa segmentos `.` e `..` de um caminho POSIX-ish (mantém a raiz `/`).
  String _normalizePath(String path) {
    final isAbs = path.startsWith('/');
    final out = <String>[];
    for (final part in path.split('/')) {
      if (part.isEmpty || part == '.') continue;
      if (part == '..') {
        if (out.isNotEmpty && out.last != '..') {
          out.removeLast();
        } else if (!isAbs) {
          out.add('..');
        }
      } else {
        out.add(part);
      }
    }
    final joined = out.join('/');
    return isAbs ? '/$joined' : joined;
  }

  /// Abre um arquivo do projeto **por caminho relativo** (palette Cmd+P). Aba
  /// normal (não preview).
  Future<void> openProjectFile(String relative) async {
    final abs = _absoluteOf(relative);
    if (abs != null) await openFile(abs, isPreview: false);
  }

  /// Abre o resultado de busca (caminho relativo) e revela a [line] (base 1),
  /// rolando e destacando-a no viewer.
  Future<void> openSearchResult(String relative, int line) async {
    final abs = _absoluteOf(relative);
    if (abs == null) return;
    await openFile(abs);
    for (final s in _sessions.values) {
      if (s is FileViewerSession && s.path == abs) s.reveal(line);
    }
  }

  /// `true` se [path] está **dentro** do workspace [projectId] (ele mesmo ou
  /// descendente). Usado pra desligar o LSP em arquivos externos abertos por
  /// drag&drop do SO (fora do workspace → sem language server).
  bool isInsideProject(String projectId, String path) {
    final root = _projectById(projectId)?.path;
    if (root == null) return false;
    return _isUnder(path, root);
  }

  /// Caminho a exibir no breadcrumb do viewer: **relativo** à raiz do workspace
  /// quando o arquivo está dentro dele; **absoluto** quando é externo (drop do
  /// SO). Sem barra inicial — a UI fatia por `/`.
  String displayPath(String projectId, String absolutePath) {
    final root = _projectById(projectId)?.path;
    if (root != null && _isUnder(absolutePath, root)) {
      return absolutePath == root
          ? absolutePath.split('/').last
          : absolutePath.substring(root.length + 1);
    }
    return absolutePath;
  }

  /// Garante o painel de arquivos visível (Cmd+Shift+F abre a busca, que vive
  /// nele). No-op se já visível.
  void showTree() {
    if (_treeVisible) return;
    _treeVisible = true;
    _persistPanels();
    notifyListeners();
  }

  /// Grava o conteúdo editado de uma aba de viewer em disco e reclassifica o
  /// `view` (markdown/texto/linguagem) com o conteúdo salvo. Retorna `true` no
  /// sucesso. Sem trava: escrita concorrente do agente é last-write-wins (MVP).
  Future<bool> saveFile(String sessionId, String content) async {
    final s = _sessions[sessionId];
    if (s is! FileViewerSession) return false;
    final ok = await _fileReader.write(s.path, content);
    if (!ok) return false;
    final fresh = await _fileReader.read(s.path);
    final cur = _sessions[sessionId];
    if (cur is FileViewerSession && fresh is! FileViewUnsupported) {
      cur.view = fresh;
      notifyListeners();
    }
    return true;
  }

  // ---- LSP (diagnostics + formatação) ---------------------------------------

  /// Diagnostics de todos os language servers (mesclados). O `FileViewer` filtra
  /// pelo `uri` do seu documento. Ver [LspServerPool].
  Stream<LspDiagnosticsBatch> get lspDiagnostics => _lsp.diagnostics;

  /// Abre [path] no LSP (didOpen). O fallback de raiz é o caminho do projeto —
  /// usado quando o walk-up de marcadores não acha raiz (ex.: arquivo solto).
  Future<void> lspOpenDocument(String path, String text, String projectId) =>
      _lsp.openDocument(
        path: path,
        text: text,
        fallbackRoot: _projectById(projectId)?.path,
      );

  /// Notifica edição (didChange, full sync).
  Future<void> lspChangeDocument(String path, String text) =>
      _lsp.changeDocument(path: path, text: text);

  /// Fecha o documento no LSP (didClose + refcount).
  Future<void> lspCloseDocument(String path) => _lsp.closeDocument(path);

  /// Aplica os overrides de comando do LSP (da tela "Language") no pool. Vale
  /// para os próximos servidores spawnados; os já vivos seguem com o comando
  /// anterior até reiniciarem.
  void applyLspCommands(Map<String, String> commands) {
    _lsp.commandOverrides = commands;
  }

  /// Pulsos de mudança de estado de servidores LSP (subiu/caiu/reiniciou). A
  /// barra de status escuta isto pra atualizar ao vivo.
  Stream<void> get lspStatusChanges => _lsp.statusChanges;

  /// Caminho do arquivo da aba focada, se for um viewer; senão `null` (a aba é
  /// agente/terminal). Usado pela barra de status do LSP.
  String? get focusedFilePath {
    final s = focusedAgent;
    return s is FileViewerSession ? s.path : null;
  }

  /// Estado do LSP do arquivo focado (linguagem + rodando), ou `null` se a aba
  /// não é um arquivo de código suportado → a barra fica vazia.
  LspDocStatus? get focusedLspStatus {
    final path = focusedFilePath;
    return path == null ? null : _lsp.statusForPath(path);
  }

  /// Reinicia o servidor LSP do arquivo focado.
  Future<void> restartFocusedLsp() async {
    final path = focusedFilePath;
    if (path == null) return;
    await _lsp.restartForPath(path);
    notifyListeners();
  }

  /// Reinicia os servidores de uma linguagem (após salvar novo comando na tela
  /// "Language") — aplica a mudança nos servidores já vivos.
  Future<void> restartLspLanguage(String languageId) async {
    await _lsp.restartLanguage(languageId);
    notifyListeners();
  }

  /// Formata [path] via LSP. Faz um `didChange` com [text] antes (flush do
  /// debounce) pra o servidor formatar o conteúdo mais recente, e devolve os
  /// edits a aplicar no buffer. Lista vazia = sem servidor / sem suporte / erro.
  Future<List<LspTextEdit>> lspFormat(String path, String text) async {
    await _lsp.changeDocument(path: path, text: text);
    return _lsp.formatDocument(path);
  }

  // ---- mutação de arquivos (criar / renomear / deletar) ---------------------

  /// Cria um arquivo vazio chamado [name] dentro de [dirPath] e o abre no pane
  /// (quando [open]). Valida o nome (não-vazio, sem `/`). Devolve a falha
  /// (mensagem) pra UI mostrar inline. Refaz a árvore no sucesso.
  Future<Result<void, String>> createFileIn(
    String dirPath,
    String name, {
    bool open = true,
  }) async {
    final invalid = _validateName(name);
    if (invalid != null) return Failure(invalid);
    final path = _join(dirPath, name.trim());
    final r = await _fileMutator.createFile(path);
    if (r.isSuccess) {
      _bumpFileTree();
      if (open) await openFile(path);
    }
    return r;
  }

  /// Cria uma pasta [name] dentro de [dirPath]. Refaz a árvore no sucesso.
  Future<Result<void, String>> createDirIn(String dirPath, String name) async {
    final invalid = _validateName(name);
    if (invalid != null) return Failure(invalid);
    final r = await _fileMutator.createDirectory(_join(dirPath, name.trim()));
    if (r.isSuccess) _bumpFileTree();
    return r;
  }

  /// Renomeia [path] para [newName] (mesma pasta). As abas abertas do arquivo
  /// (ou de descendentes, se for pasta) **seguem** o novo caminho.
  Future<Result<void, String>> renamePath(String path, String newName) async {
    final invalid = _validateName(newName);
    if (invalid != null) return Failure(invalid);
    final to = _join(_parentOf(path), newName.trim());
    final r = await _fileMutator.rename(path, to);
    if (r.isSuccess) {
      await _retargetSessions(path, to);
      _bumpFileTree();
    }
    return r;
  }

  /// Move [path] pra **dentro** de [targetDir] (drag-and-drop na árvore),
  /// mantendo o nome. As abas abertas seguem o novo caminho, como no rename.
  Future<Result<void, String>> movePath(String path, String targetDir) async {
    final name = path.split('/').where((p) => p.isNotEmpty).lastOrNull;
    if (name == null) return const Failure('Invalid path.');
    if (_parentOf(path) == targetDir) return const Success(null); // já está lá
    if (_isUnder(targetDir, path)) {
      return const Failure('Cannot move a folder into itself.');
    }
    final to = _join(targetDir, name);
    final r = await _fileMutator.rename(path, to);
    if (r.isSuccess) {
      await _retargetSessions(path, to);
      _bumpFileTree();
    }
    return r;
  }

  /// Manda [path] pra lixeira. **Fecha antes** as abas do arquivo (ou de tudo
  /// dentro da pasta), sem prompt de salvar — a deleção sobrepõe.
  Future<Result<void, String>> deletePath(String path) async {
    _closeSessionsUnder(path);
    final r = await _fileMutator.moveToTrash(path);
    if (r.isSuccess) _bumpFileTree();
    return r;
  }

  // ---- clipboard da árvore (copiar / recortar / colar) ----------------------

  /// Caminho no clipboard interno da árvore (`null` = vazio). Set por
  /// [copyToClipboard] / [cutToClipboard], consumido por [pasteInto].
  String? _clipboardPath;

  /// `true` = recortar (move no paste), `false` = copiar (duplica no paste).
  bool _clipboardCut = false;

  /// Há algo pronto pra colar? Usado pra habilitar o item "Paste" no menu.
  bool get canPaste => _clipboardPath != null;

  /// Marca [path] pra **copiar** (o paste duplica).
  void copyToClipboard(String path) {
    _clipboardPath = path;
    _clipboardCut = false;
    notifyListeners();
  }

  /// Marca [path] pra **recortar** (o paste move e limpa o clipboard).
  void cutToClipboard(String path) {
    _clipboardPath = path;
    _clipboardCut = true;
    notifyListeners();
  }

  /// Cola o item do clipboard **dentro** de [targetDir]. Copia ou move conforme
  /// o modo. Se o nome colidir no destino, gera um sufixo (`nome copy`,
  /// `nome copy 2`, ...). Recorte limpa o clipboard no sucesso; cópia mantém
  /// (permite colar várias vezes). Abas abertas seguem no move, como no rename.
  Future<Result<void, String>> pasteInto(String targetDir) async {
    final from = _clipboardPath;
    if (from == null) return const Failure('Clipboard is empty.');
    final name = from.split('/').where((p) => p.isNotEmpty).lastOrNull;
    if (name == null) return const Failure('Invalid path.');
    if (_clipboardCut && _isUnder(targetDir, from)) {
      return const Failure('Cannot move a folder into itself.');
    }
    final to = await _uniqueDest(targetDir, name);
    final r = _clipboardCut
        ? await _fileMutator.rename(from, to)
        : await _fileMutator.copy(from, to);
    if (r.isSuccess) {
      if (_clipboardCut) {
        await _retargetSessions(from, to);
        _clipboardPath = null;
      }
      _bumpFileTree();
    }
    return r;
  }

  /// Caminho livre em [dir] pra [name]: devolve `dir/name` se não existir, senão
  /// insere ` copy`, ` copy 2`, ... antes da extensão até achar um livre.
  Future<String> _uniqueDest(String dir, String name) async {
    var candidate = _join(dir, name);
    if (!await _pathExists(candidate)) return candidate;
    final dot = name.lastIndexOf('.');
    final hasExt = dot > 0;
    final stem = hasExt ? name.substring(0, dot) : name;
    final ext = hasExt ? name.substring(dot) : '';
    for (var i = 1;; i++) {
      final suffix = i == 1 ? ' copy' : ' copy $i';
      candidate = _join(dir, '$stem$suffix$ext');
      if (!await _pathExists(candidate)) return candidate;
    }
  }

  Future<bool> _pathExists(String path) async =>
      await FileSystemEntity.type(path, followLinks: false) !=
      FileSystemEntityType.notFound;

  void _bumpFileTree() {
    _fileTreeRevision++;
    notifyListeners();
  }

  /// `null` se válido; senão a mensagem do erro. Nesta fase: sem aninhar (`/`).
  String? _validateName(String name) {
    final n = name.trim();
    if (n.isEmpty) return 'Name cannot be empty.';
    if (n.contains('/')) return 'Name cannot contain “/”.';
    if (n == '.' || n == '..') return 'Invalid name.';
    return null;
  }

  String _join(String dir, String name) {
    final base = dir.endsWith('/') ? dir.substring(0, dir.length - 1) : dir;
    return '$base/$name';
  }

  String _parentOf(String path) {
    final i = path.lastIndexOf('/');
    return i <= 0 ? path : path.substring(0, i);
  }

  /// Um caminho é "sob" [root] se for ele mesmo ou um descendente (`root/...`).
  bool _isUnder(String path, String root) =>
      path == root || path.startsWith('$root/');

  /// Reaponta as abas de viewer afetadas por um rename de [from] → [to]: o
  /// próprio arquivo e, se [from] for pasta, todos os descendentes (troca de
  /// prefixo). Re-lê o conteúdo e re-arma o watcher no novo caminho.
  Future<void> _retargetSessions(String from, String to) async {
    for (final s in _sessions.values) {
      if (s is! FileViewerSession || !_isUnder(s.path, from)) continue;
      final newPath = s.path == from
          ? to
          : '$to${s.path.substring(from.length)}';
      s.retarget(newPath);
      final fresh = await _fileReader.read(newPath);
      if (fresh is! FileViewUnsupported) s.view = fresh;
      _fileWatchers.remove(s.id)?.cancel();
      _watchFileViewer(s);
    }
    notifyListeners();
  }

  /// Fecha (no projeto ativo) toda aba de viewer cujo arquivo está em/sob [path].
  /// Coleta os pares (pane, aba) antes de fechar pra não mutar a árvore durante
  /// a varredura. (Multi-projeto fica pra depois — a árvore opera no ativo.)
  void _closeSessionsUnder(String path) {
    final tree = _activeTree;
    if (tree == null) return;
    final targets = <(String, String)>[];
    for (final leaf in leaves(tree)) {
      for (final tabId in leaf.tabs) {
        final s = _sessions[tabId];
        if (s is FileViewerSession && _isUnder(s.path, path)) {
          targets.add((leaf.id, tabId));
        }
      }
    }
    for (final (paneId, tabId) in targets) {
      closeTab(paneId, tabId);
    }
  }

  /// Árvore do projeto (para renderizar cada folha do `IndexedStack`).
  PaneNode? tree(String projectId) => _trees[projectId];

  /// Pane focada do projeto.
  String? focusedPaneId(String projectId) => _focused[projectId];

  /// Nº de agentes do workspace que terminaram um turno e ainda não foram
  /// vistos (badge de notificações).
  int notificationCount(String projectId) => _sessions.values
      .where((s) => s.projectId == projectId && s.unseenFinish)
      .length;

  // ---- init -----------------------------------------------------------------
  Future<void> init() async {
    // Servidor de status do `cockpit-hook` (claude nas abas reporta turno aqui).
    // Await: no Windows o `hookEnv` depende da porta ligada antes de spawnar abas.
    // O mesmo socket atende a CLI interna `cockpit` (`_onCockpitCommand`).
    await _statusServer.start(_onClaudeStatus, onCommand: _cli.handle);
    // Realms antes dos projetos: o filtro do rail e a seleção inicial dependem
    // do realm ativo. `all()` garante o Default.
    await realmCtrl.load();
    _projectList.addAll(await _projects.all());
    // Carrega os layouts salvos (mas não reconstrói nada ainda — lazy).
    for (final project in _projectList) {
      _savedLayouts[project.id] = await _layoutStore.load(project.id);
    }
    // GC do scrollback: apaga arquivos de sessões de terminal que sumiram de
    // TODOS os layouts. Varre todos os layouts salvos (não só o ativo: a
    // reconstrução é lazy), senão apagaria o scrollback de projetos não-ativados.
    unawaited(_scrollback.pruneExcept(_persistedTerminalIds()));
    // Injeta o workspace de sistema "Cockpit" (terminal-only), se habilitado.
    // Depois do carregamento de layouts (ele não tem layout salvo) e antes da
    // seleção inicial (que pode cair nele no 1º boot).
    if (_cockpitEnabled) _injectCockpit();
    _selectedProjectId = await _initialSelection();
    // Só o projeto selecionado é ativado (sobe os processos) no boot.
    final selected = _selectedProjectId;
    if (selected != null) await _activateProject(selected);
    git.watchProject(selected); // watcher ao vivo do projeto inicial
    _ready = true;
    notifyListeners();
    // Estado git + worktrees de todos os projetos (assíncrono — a rail atualiza
    // conforme chega). Só há raízes no boot; os forks entram pela reconciliação.
    for (final project in _projectList) {
      unawaited(git.refresh(project.id));
      unawaited(_refreshWorktrees(project.id));
    }
    git.startPoll(); // safety net contra eventos de FS perdidos (bug: rail stale)
    // Detecta IDEs instaladas (assíncrono — topbar atualiza ao chegar).
    unawaited(
      _launcher.probe().then((apps) {
        _availableApps = apps;
        notifyListeners();
      }),
    );
  }

  /// Workspace a pré-selecionar no boot (dentro do **realm ativo**):
  /// 1. o último selecionado do realm, se ainda existir e seguir no realm
  ///    (inclui o próprio Cockpit);
  /// 2. senão, o Cockpit (1º boot de instalação nova: sem `lastSelected`);
  /// 3. senão, o primeiro workspace do realm; `null` se não houver nenhum.
  Future<String?> _initialSelection() async {
    try {
      final last = await _projects.loadLastSelected(realmCtrl.activeId);
      if (last != null && _visibleInActiveRealm(last)) return last;
    } catch (_) {
      // erro ao ler a preferência → segue pro fallback.
    }
    if (cockpitWorkspace != null) return Project.cockpitId;
    final roots = rootProjects;
    return roots.isEmpty ? null : roots.first.id;
  }

  /// `true` se [id] pode ser selecionado com o realm ativo atual: o Cockpit
  /// sintético (presente em todos os realms) ou um workspace/fork cuja raiz
  /// pertence ao realm ativo.
  bool _visibleInActiveRealm(String id) {
    final p = _projectById(id);
    if (p == null) return false;
    if (p.isSystemTerminal) return true;
    final root = p.parentId == null ? p : _projectById(p.parentId!);
    return root != null && root.realmId == realmCtrl.activeId;
  }

  /// Adiciona o workspace de sistema "Cockpit" a [_projectList] (runtime, nunca
  /// persistido). Idempotente: no-op se já presente. Entra no fim da lista — sua
  /// posição é irrelevante (fica de fora de [rootProjects]; o rail o renderiza
  /// num slot próprio via [cockpitWorkspace]).
  void _injectCockpit() {
    if (_projectById(Project.cockpitId) != null) return;
    _projectList.add(Project.systemTerminal());
  }

  /// Liga/desliga o workspace de sistema "Cockpit" em runtime (empurrado pela
  /// `CockpitPage` a partir de `AppSettings.showCockpit`).
  ///
  /// Antes de [init] terminar (`!_ready`), só guarda a flag — o [init] faz a
  /// injeção. Já habilitado o app:
  /// - **ON**: injeta o slot (sem roubar a seleção atual).
  /// - **OFF**: mata os PTYs do Cockpit e remove o slot; se estava selecionado,
  ///   cai no primeiro workspace real (ou `null` → `WelcomeView`). Sem diálogo.
  void setCockpitEnabled(bool value) {
    if (_cockpitEnabled == value) return;
    _cockpitEnabled = value;
    if (!_ready) return; // init() cuidará da injeção conforme a flag
    if (value) {
      _injectCockpit();
      notifyListeners();
      return;
    }
    // OFF: encerra runtime (mata PTYs/sessões/timers) e remove o sintético.
    final wasSelected = _selectedProjectId == Project.cockpitId;
    _disposeProjectRuntime(Project.cockpitId);
    _projectList.removeWhere((p) => p.isSystemTerminal);
    if (wasSelected) {
      final roots = rootProjects;
      _selectedProjectId = roots.isEmpty ? null : roots.first.id;
      final next = _selectedProjectId;
      if (next != null) {
        unawaited(_activateProject(next));
        git.watchProject(next);
      } else {
        git.watchProject(null);
      }
    }
    notifyListeners();
  }

  /// Abre a pasta do projeto selecionado no [app] informado.
  Future<void> openProjectInApp(LaunchableApp app) async {
    final project = selectedProject;
    if (project == null) return;
    await _launcher.launch(app, project.path);
  }

  /// Abre [path] no app padrão do SO ("Open with" do menu do file tree).
  Future<void> openWithDefaultApp(String path) =>
      _launcher.openWithDefaultApp(path);

  // ---- realms ---------------------------------------------------------------
  /// Troca o recorte do rail pro realm [id], **sem reiniciar nada**: sessões de
  /// workspaces do realm anterior seguem vivas (notificações inclusas); só a
  /// lista exibida e a seleção mudam. Restaura a última seleção do realm novo
  /// (fallback: Cockpit → primeiro workspace → nenhum).
  Future<void> switchRealm(String id) async {
    if (!realmCtrl.setActive(id)) return;
    String? next;
    try {
      final last = await _projects.loadLastSelected(id);
      if (last != null && _visibleInActiveRealm(last)) next = last;
    } catch (_) {
      // preferência ilegível → fallback abaixo.
    }
    if (next == null && cockpitWorkspace != null) next = Project.cockpitId;
    if (next == null) {
      final roots = rootProjects;
      next = roots.isEmpty ? null : roots.first.id;
    }
    if (next == null) {
      _selectedProjectId = null;
      git.watchProject(null);
    } else if (next != _selectedProjectId) {
      _selectedProjectId = next;
      _clearFocusedNotification();
      unawaited(_activateProject(next));
      git.watchProject(next);
      unawaited(git.refresh(next));
      unawaited(_refreshWorktrees(_rootOf(next)));
    }
    notifyListeners();
  }

  /// Troca pro realm vizinho na ordem do seletor (⌘` / ⌘⇧`): [delta] +1 avança,
  /// -1 volta, com wrap-around. No-op com 0–1 realms.
  Future<void> cycleRealm(int delta) async {
    final next = realmCtrl.neighbor(delta);
    if (next != null) await switchRealm(next.id);
  }

  /// Cria um realm novo (não troca o ativo — a UI decide se troca em seguida).
  Future<Realm> createRealm(String name) => realmCtrl.create(name);

  Future<void> renameRealm(String id, String name) =>
      realmCtrl.rename(id, name);

  /// Exclui o realm [id]. Workspaces dele **nunca são apagados**: migram pro
  /// Default. O Default em si é indelével. Se o realm ativo for o excluído,
  /// troca pro Default antes.
  Future<void> deleteRealm(String id) async {
    if (id == Realm.defaultId || !realmCtrl.exists(id)) return;
    for (var i = 0; i < _projectList.length; i++) {
      final p = _projectList[i];
      if (p.realmId != id) continue;
      final moved = p.copyWith(realmId: Realm.defaultId);
      _projectList[i] = moved;
      if (p.parentId == null && !p.isSystemTerminal) {
        await _projects.save(moved); // forks são runtime, não persistem
      }
    }
    if (realmCtrl.activeId == id) await switchRealm(Realm.defaultId);
    await realmCtrl.remove(id);
    await _projects.saveLastSelected(id, null); // limpa ponteiro órfão
    notifyListeners();
  }

  /// Move um workspace raiz pra outro realm. Bloqueia se o path já existir por
  /// lá (invariante: um path por realm). Se o movido era o selecionado, a
  /// seleção cai pro fallback do realm atual.
  Future<void> moveWorkspaceToRealm(String workspaceId, String realmId) async {
    if (!realmCtrl.exists(realmId)) return;
    final idx = _projectList.indexWhere((p) => p.id == workspaceId);
    if (idx < 0) return;
    final p = _projectList[idx];
    if (p.parentId != null || p.isSystemTerminal || p.realmId == realmId) {
      return;
    }
    if (pathExistsInRealm(p.path, realmId)) return;
    _projectList[idx] = p.copyWith(realmId: realmId);
    await _projects.save(_projectList[idx]);
    // Forks acompanham a raiz (runtime; a reconciliação também os refaria).
    for (var i = 0; i < _projectList.length; i++) {
      final f = _projectList[i];
      if (f.parentId == workspaceId) {
        _projectList[i] = f.copyWith(realmId: realmId);
      }
    }
    // Sumiu do recorte atual e estava selecionado (ou um fork dele)?
    final sel = _selectedProjectId;
    if (realmId != realmCtrl.activeId &&
        sel != null &&
        _rootOf(sel) == workspaceId) {
      final roots = rootProjects;
      final next = cockpitWorkspace != null
          ? Project.cockpitId
          : (roots.isEmpty ? null : roots.first.id);
      _selectedProjectId = next;
      if (next != null) {
        unawaited(_activateProject(next));
        git.watchProject(next);
      } else {
        git.watchProject(null);
      }
    }
    notifyListeners();
  }

  /// `true` se [path] já é um workspace raiz do realm [realmId] — usado pelo
  /// guard do move e pra UI desabilitar o destino no submenu.
  bool pathExistsInRealm(String path, String realmId) => _projectList.any(
    (o) =>
        o.parentId == null &&
        !o.isSystemTerminal &&
        o.realmId == realmId &&
        o.path == path,
  );

  /// Nº de workspaces raiz do realm — mostrado no dialog de gerenciar.
  int workspaceCountInRealm(String realmId) => _projectList
      .where(
        (p) =>
            p.parentId == null && !p.isSystemTerminal && p.realmId == realmId,
      )
      .length;

  // ---- projects -------------------------------------------------------------
  /// Cria (ou seleciona, se já existir) um workspace pra [path]. [name] e
  /// [colorValue] permitem sobrescrever os defaults (fluxo "Criar Workspace",
  /// onde o usuário edita nome/cor antes de confirmar).
  Future<Project> addProject(
    String path, {
    String? name,
    int? colorValue,
    String? imagePath,
  }) async {
    // Dedup **dentro do realm ativo** — o mesmo path pode existir como
    // workspaces distintos em realms diferentes (ids são UUIDs).
    for (final existing in _projectList) {
      if (existing.path == path && existing.realmId == realmCtrl.activeId) {
        _selectedProjectId = existing.id;
        unawaited(_projects.saveLastSelected(realmCtrl.activeId, existing.id));
        notifyListeners();
        return existing;
      }
    }
    final basename = _basename(path);
    final resolvedName = (name != null && name.trim().isNotEmpty)
        ? name.trim()
        : (basename.isEmpty ? path : basename);
    // Cor pela contagem de raízes (forks e o Cockpit sintético não entram no
    // rodízio da paleta nem na numeração de `order`).
    final roots = _projectList.where(
      (p) => p.parentId == null && !p.isSystemTerminal,
    );
    final rootCount = roots.length;
    // Entra no fim da lista (maior order + 1).
    final nextOrder = roots.isEmpty
        ? 0
        : roots.map((p) => p.order).reduce(max) + 1;
    final project = Project(
      id: newUid(), // opaco e estável; o vínculo com o disco é o `path`
      name: resolvedName,
      path: path,
      colorValue: colorValue ?? _palette[rootCount % _palette.length],
      createdAt: DateTime.now(),
      order: nextOrder,
      imagePath: imagePath,
      realmId: realmCtrl.activeId,
    );
    _projectList.add(project);
    _selectedProjectId = project.id;
    await _projects.save(project);
    unawaited(_projects.saveLastSelected(realmCtrl.activeId, project.id));
    await _activateProject(project.id); // sem layout salvo → pane vazia
    unawaited(git.refresh(project.id));
    unawaited(_refreshWorktrees(project.id)); // pode já ter worktrees no disco
    notifyListeners();
    return project;
  }

  /// Altera nome, cor e/ou imagem do projeto e persiste. [imagePath] usa o
  /// sentinel [Project.unchanged] como default — passe `null` para **remover** a
  /// imagem, ou um caminho para defini-la.
  Future<void> updateProject(
    String id, {
    String? name,
    int? colorValue,
    Object? imagePath = Project.unchanged,
  }) async {
    final index = _projectList.indexWhere((p) => p.id == id);
    if (index < 0) return;
    final updated = _projectList[index].copyWith(
      name: name,
      colorValue: colorValue,
      imagePath: imagePath,
    );
    _projectList[index] = updated;
    await _projects.save(updated);
    notifyListeners();
  }

  /// Reordena os workspaces raiz (drag-drop no rail): move [movedId] para antes
  /// ou depois de [targetId] e persiste a nova sequência no campo `order`. As
  /// worktrees acompanham o pai (herdam o `order` na reconciliação).
  Future<void> reorderWorkspace(
    String movedId,
    String targetId, {
    required bool before,
  }) async {
    if (movedId == targetId) return;
    final roots = rootProjects.toList(); // já ordenado por order
    final from = roots.indexWhere((p) => p.id == movedId);
    if (from < 0 || roots.indexWhere((p) => p.id == targetId) < 0) return;
    final moved = roots.removeAt(from);
    var insertAt = roots.indexWhere((p) => p.id == targetId);
    if (!before) insertAt += 1;
    roots.insert(insertAt, moved);
    // Reatribui order sequencial (0..n) e persiste cada raiz.
    for (var i = 0; i < roots.length; i++) {
      final updated = roots[i].copyWith(order: i);
      final idx = _projectList.indexWhere((p) => p.id == updated.id);
      if (idx >= 0) _projectList[idx] = updated;
      await _projects.save(updated);
    }
    notifyListeners();
  }

  Future<void> removeProject(String id) async {
    // Encerra as worktrees do workspace junto (não deixa fork órfão).
    for (final fork in _worktrees.remove(id) ?? const <Project>[]) {
      _disposeProjectRuntime(fork.id);
      _projectList.removeWhere((p) => p.id == fork.id);
    }
    _disposeProjectRuntime(id);
    _projectList.removeWhere((p) => p.id == id);
    if (_selectedProjectId == id || _projectById(_selectedProjectId) == null) {
      _selectedProjectId = rootProjects.isEmpty ? null : rootProjects.first.id;
    }
    await _projects.remove(id);
    await _layoutStore.remove(id);
    final next = _selectedProjectId;
    if (next != null) await _activateProject(next);
    notifyListeners();
  }

  /// Encerra o runtime de um projeto (árvore de panes + sessões + foco + caches),
  /// **sem** mexer em persistência. Usado ao remover um workspace e ao detectar
  /// que uma worktree sumiu (mata `pi` + fecha panes — decisão 9).
  void _disposeProjectRuntime(String id) {
    final tree = _trees.remove(id);
    if (tree != null) {
      for (final leaf in leaves(tree)) {
        for (final sid in leaf.tabs) {
          _disposeSession(sid);
        }
      }
    }
    _focused.remove(id);
    _savedLayouts.remove(id);
    git.forget(id);
    _saveTimers.remove(id)?.cancel();
  }

  /// Cria uma worktree [name] no workspace [rootId] (decisões 2, 3, 14, 15). Em
  /// sucesso, reconcilia, **auto-seleciona** o fork (pane vazia) e o devolve; em
  /// falha, devolve o erro do git pra mostrar inline no dialog (decisão 21).
  Future<Result<Project, WorktreeOpError>> createWorktree(
    String rootId,
    String name, {
    String? rootPath,
    String? baseRef,
    String? layoutSourceId,
  }) async {
    final root = _projectById(rootId);
    if (root == null) {
      return const Failure(WorktreeOpError('Workspace not found.'));
    }
    // Multi-root: o `git worktree add` parte da root escolhida, não da mãe.
    // [baseRef] ("Fork Worktree"): ramifica da branch de outro fork, mas a
    // pasta nasce sempre no repo de origem.
    final res = await _worktreeMgr.add(
      rootPath ?? root.path,
      name,
      baseRef: baseRef,
    );
    switch (res) {
      case Failure(:final error):
        return Failure<Project, WorktreeOpError>(error);
      case Success(:final value):
        // Clona a estrutura (panes/abas/posições) pro fork: do pai por padrão,
        // ou do fork de origem no "Fork Worktree" (mesma organização, pasta
        // nova, sessões do zero — ver _cloneLayoutForWorktree).
        final clonedLayout = _cloneLayoutForWorktree(layoutSourceId ?? rootId);
        await _refreshWorktrees(rootId); // insere o fork em _projectList
        // Id de fork é namespaced pela raiz (ver _refreshWorktrees) — o path
        // cru deixou de ser o id na migração dos Realms.
        final fork = _projectById('$rootId::${value.path}');
        if (fork == null) {
          return const Failure(
            WorktreeOpError(
              'Worktree created, but did not appear in the list.',
            ),
          );
        }
        if (clonedLayout != null) {
          // Vira o layout salvo do fork → _activateProject reconstrói a estrutura
          // apontando pra fork.path. Persiste pra sobreviver a reload.
          _savedLayouts[fork.id] = clonedLayout;
          unawaited(_layoutStore.save(fork.id, clonedLayout));
        }
        selectProject(
          fork.id,
        ); // auto-select → activate → reconstrói a estrutura
        return Success<Project, WorktreeOpError>(fork);
    }
  }

  /// Branches locais + worktrees de [rootId], pra validação ao vivo do dialog
  /// de criar (decisão 11).
  /// "Fork Worktree": cria uma worktree nova ramificada da **branch do fork**
  /// [forkId], materializada no repo de origem (nunca aninhada). O fork novo
  /// entra como irmão na lista (mesmo pai), herdando o layout do fork base.
  Future<Result<Project, WorktreeOpError>> forkWorktree(
    String forkId,
    String name,
  ) async {
    final fork = _projectById(forkId);
    if (fork == null || fork.parentId == null) {
      return const Failure(WorktreeOpError('Worktree not found.'));
    }
    final origin = _forkOriginPath(fork);
    if (origin == null) {
      return const Failure(WorktreeOpError('Origin root not found.'));
    }
    return createWorktree(
      fork.parentId!,
      name,
      rootPath: origin,
      baseRef: fork.name,
      layoutSourceId: forkId,
    );
  }

  /// Namespace pra validação do "Fork Worktree" — o do repo de origem do fork.
  Future<WorktreeNamespace> forkWorktreeNamespace(String forkId) async {
    final fork = _projectById(forkId);
    final origin = fork == null ? null : _forkOriginPath(fork);
    if (origin == null) return const WorktreeNamespace.empty();
    return _worktreeMgr.namespace(origin);
  }

  Future<WorktreeNamespace> worktreeNamespace(
    String rootId, {
    String? rootPath,
  }) async {
    final root = _projectById(rootId);
    if (root == null) return const WorktreeNamespace.empty();
    return _worktreeMgr.namespace(rootPath ?? root.path);
  }

  /// Root que originou o fork — as ops de worktree rodam contra ela. Fallback:
  /// o path do pai (single-root, comportamento histórico).
  String? _forkOriginPath(Project fork) {
    final parent = fork.parentId == null ? null : _projectById(fork.parentId);
    return _forkOrigin[fork.id] ?? parent?.path;
  }

  /// Basename da root que originou o fork, **só em pai multi-root** — a rail
  /// usa como sufixo (`test (backend)`) pra desambiguar forks de roots
  /// diferentes. Single-root devolve `null` (sufixo seria redundante).
  String? forkOriginName(String forkId) {
    final fork = _projectById(forkId);
    if (fork == null || fork.parentId == null) return null;
    if (!isMultiRoot(fork.parentId!)) return null;
    final origin = _forkOrigin[forkId];
    return origin?.split('/').last;
  }

  /// Remove o fork [forkId] (decisão 6): `git worktree remove` + `git branch -D`
  /// via [WorktreeManager.remove]; em sucesso, reconcilia com `_refreshWorktrees`
  /// — a **mesma** rotina do someço externo, que mata os `pi`, fecha as panes e
  /// devolve a seleção pro pai (decisão 9). Em falha, devolve o erro do git pra
  /// mostrar inline.
  Future<Result<void, WorktreeOpError>> removeWorktree(String forkId) async {
    final fork = _projectById(forkId);
    if (fork == null || fork.parentId == null) {
      return const Failure(WorktreeOpError('Worktree not found.'));
    }
    final origin = _forkOriginPath(fork);
    if (origin == null) {
      return const Failure(WorktreeOpError('Parent workspace not found.'));
    }
    final res = await _worktreeMgr.remove(origin, fork.path, fork.name);
    if (res.isSuccess) {
      // O fork sai do `git worktree list` → a reconciliação detecta o someço e
      // dispara kill+close+volta-pro-pai (não duplicamos a rotina).
      await _refreshWorktrees(fork.parentId!);
    }
    return res;
  }

  /// `true` se a branch do fork [forkId] já foi mergeada — alimenta o aviso forte
  /// de remoção (decisão 6). Em dúvida/erro, `false` (mostra o aviso por segurança).
  Future<bool> isWorktreeBranchMerged(String forkId) async {
    final fork = _projectById(forkId);
    if (fork == null || fork.parentId == null) return false;
    final origin = _forkOriginPath(fork);
    if (origin == null) return false;
    return _worktreeMgr.isBranchMerged(origin, fork.name);
  }

  /// Unstage (Source Control): `git restore --staged -- <arquivo>` na root
  /// dona do caminho. `null` = sucesso; senão a saída de erro do git.
  Future<String?> unstageFile(String absPath) =>
      _restoreFile(absPath, staged: true);

  /// Discard (Source Control): joga fora a mudança do working tree —
  /// `git restore -- <arquivo>`; untracked não tem "restore", então vai pra
  /// lixeira via [deletePath] (reversível no macOS). `null` = sucesso.
  Future<String?> discardFile(String absPath) async {
    if (gitStatusForPath(absPath) == GitFileStatus.untracked) {
      final res = await deletePath(absPath);
      return res.fold((_) => null, (e) => e);
    }
    return _restoreFile(absPath, staged: false);
  }

  /// Commit (Source Control): comita **só** [absPath] com [message], na root
  /// dona do caminho. Untracked precisa de `git add` antes (pathspec de commit
  /// não casa com arquivo não-rastreado); nos demais o
  /// `git commit -m <msg> -- <arquivo>` já auto-stageia a mudança do working
  /// tree. `null` = sucesso; senão a saída de erro do git.
  Future<String?> commitFile(String absPath, String message) async {
    final pid = _selectedProjectId;
    if (pid == null) return 'No workspace selected.';
    final root = rootContaining(pid, absPath);
    if (root == null) return 'File is outside the workspace roots.';
    final rel = _subOf(absPath, root);
    if (gitStatusForPath(absPath) == GitFileStatus.untracked) {
      final err = await git.collect(root, ['add', '--', rel]);
      if (err != null) return err;
    }
    final err = await git.collect(root, ['commit', '-m', message, '--', rel]);
    unawaited(git.refresh(pid));
    return err;
  }

  Future<String?> _restoreFile(String absPath, {required bool staged}) async {
    final pid = _selectedProjectId;
    if (pid == null) return 'No workspace selected.';
    final root = rootContaining(pid, absPath);
    if (root == null) return 'File is outside the workspace roots.';
    final rel = _subOf(absPath, root);
    final err = await git.collect(root, [
      'restore',
      if (staged) '--staged',
      '--',
      rel,
    ]);
    unawaited(git.refresh(pid));
    _fileTreeRevision++; // conteúdo em disco pode ter mudado (restore)
    notifyListeners();
    return err;
  }

  // === Git commands (Sync / Pull / Push) — feature "more git" ===

  /// Sync = `git pull` e, se OK, `git push` no repo em [repoPath]. Stream ao vivo.
  GitRun gitSync(String repoPath) => git.sync(repoPath);

  /// `git pull` no repo em [repoPath].
  GitRun gitPull(String repoPath) => git.pull(repoPath);

  /// `git push` no repo em [repoPath].
  GitRun gitPush(String repoPath) => git.push(repoPath);

  /// "Update from parent": mergeia a branch **do pai** (root de origem) no
  /// checkout do worktree [fork] — o inverso do [mergeWorktreeToParent].
  /// Conflito fica no worktree pro usuário resolver (exit ≠ 0 no dialog);
  /// o pai nunca é tocado.
  GitRun updateWorktreeFromParent(Project fork) {
    final origin = _forkOriginPath(fork);
    final parentBranch = origin == null
        ? null
        : git.infoForRoot(origin)?.branch;
    if (parentBranch == null) {
      final controller = StreamController<String>()
        ..add('Parent branch not found.');
      unawaited(controller.close());
      return GitRun(output: controller.stream, exitCode: Future.value(1));
    }
    return _gitRunner.run(fork.path, ['merge', parentBranch]);
  }

  /// Mergeia a branch do worktree [fork] no checkout do workspace pai. Em
  /// sucesso, remove o worktree (reusa [removeWorktree] → kill+close) e seleciona
  /// o pai. Devolve o handle ao vivo pro dialog de processo.
  GitMergeOutcome mergeWorktreeToParent(Project fork) {
    final parentId = fork.parentId;
    if (parentId == null) return _mergeError('Not a worktree.');
    final root = _projectById(parentId);
    if (root == null) return _mergeError('Parent workspace not found.');
    final origin = _forkOriginPath(fork);
    if (origin == null) return _mergeError('Origin root not found.');

    final outcome = _gitRunner.mergeIntoParent(origin, fork.path, fork.name);
    // Ao terminar com sucesso, limpa o worktree e volta pro pai. A remoção passa
    // pela reconciliação de [removeWorktree] (mata processos, fecha panes).
    outcome.status.then((status) async {
      if (status != GitMergeStatus.merged) return;
      await removeWorktree(fork.id);
      selectProject(root.id);
    });
    return outcome;
  }

  /// Handle de merge já finalizado em erro, com uma linha explicativa — pro
  /// dialog quando nem chegamos a rodar o git (pai/worktree ausente).
  GitMergeOutcome _mergeError(String message) {
    final controller = StreamController<String>()..add(message);
    unawaited(controller.close());
    return GitMergeOutcome(
      status: Future.value(GitMergeStatus.error),
      output: controller.stream,
    );
  }

  void selectProject(String id) {
    if (_selectedProjectId == id) return;
    // Seleção vinda de fora do recorte atual (clique em notificação, CLI
    // `cockpit open`, restauração): troca o realm ativo junto — selecionar um
    // workspace de outro realm sem trazê-lo deixaria o rail "sem seleção".
    final target = _projectById(id);
    if (target != null && !target.isSystemTerminal) {
      final root = target.parentId == null
          ? target
          : _projectById(target.parentId!);
      if (root != null && root.realmId != realmCtrl.activeId) {
        realmCtrl.setActive(root.realmId);
      }
    }
    _selectedProjectId = id;
    // Persiste o workspace (raiz) pra pré-selecionar na próxima abertura —
    // por realm: cada realm lembra a própria última seleção.
    unawaited(_projects.saveLastSelected(realmCtrl.activeId, _rootOf(id)));
    _clearFocusedNotification();
    unawaited(_activateProject(id)); // reconstrói (lazy) se ainda não ativo
    git.watchProject(id); // segue o working tree do novo projeto ao vivo
    unawaited(git.refresh(id)); // pode ter mudado desde a última vez
    unawaited(_refreshWorktrees(_rootOf(id))); // reflete worktrees externas
    notifyListeners();
  }

  /// Subpastas do projeto selecionado em [relativePath] (vazio = raiz), para o
  /// seletor navegável de "onde o agente atua". [relativePath] usa `/` e fica
  /// sempre **dentro** do root do projeto (o dialog não sobe acima dele).
  Future<List<String>> subfolders([String relativePath = '']) async {
    final project = selectedProject;
    if (project == null) return const <String>[];
    final base = relativePath.isEmpty
        ? project.path
        : '${project.path}/$relativePath';
    return _folders.subfolders(base);
  }

  /// Sessões salvas do pi para uma pasta (histórico), mais recentes primeiro.
  Future<List<SessionInfo>> historyFor(String cwd) =>
      _history.sessionsFor(cwd, withTitle: true);

  /// Aplica nome e relay ao agente. Se houver mudança real e o processo estiver
  /// rodando, reinicia com a nova config (preservando `sessionPath`).
  Future<void> saveAgentConfig(
    String sessionId, {
    required String agentName,
    required bool autoStartRelay,
  }) async {
    final s = _sessions[sessionId];
    if (s is! AgentSession) return;

    final nameChanged = agentName.trim() != s.title;
    final relayChanged = autoStartRelay != s.autoStartRelay;
    if (!nameChanged && !relayChanged) return;

    s.rename(agentName.trim());
    s.autoStartRelay = autoStartRelay;
    if (nameChanged && s.isAlive) {
      unawaited(s.sendRelayControl('rename:${agentName.trim()}'));
    }
    notifyListeners();
  }

  /// Define o rótulo manual (nome estável) de uma aba e persiste o layout.
  /// Diferente de [saveAgentConfig]: não mexe na identidade do agente/harness —
  /// só no nome exibido/CLI, travando-o contra o título automático (OSC etc).
  void setPaneLabel(String sessionId, String label) {
    final s = _sessions[sessionId];
    if (s == null) return;
    s.setManualLabel(label);
    _scheduleSave(s.projectId);
    notifyListeners();
  }

  /// Restaura o título automático de uma aba (descarta o rótulo manual).
  void resetPaneLabel(String sessionId) {
    final s = _sessions[sessionId];
    if (s == null) return;
    s.clearManualLabel();
    _scheduleSave(s.projectId);
    notifyListeners();
  }

  // ---- agent / tab / split operations (projeto ativo) -----------------------
  void focus(String paneId) {
    final id = _selectedProjectId;
    if (id == null || _focused[id] == paneId) return;
    _focused[id] = paneId;
    _clearFocusedNotification();
    notifyListeners();
  }

  void selectTab(String paneId, String agentId) {
    final tree = _activeTree;
    if (tree == null) return;
    _setActiveTree(
      updateLeaf(tree, paneId, (p) => p.copyWith(active: agentId)),
    );
    _focused[_selectedProjectId!] = paneId;
    _clearFocusedNotification();
    // Selecionar uma tab de FileView revela o arquivo na árvore: destaca +
    // expande a root e os pais (uma vez, via a geração). Só quando o arquivo é
    // do projeto ativo (fora dele não há árvore pra revelar).
    final sel = _sessions[agentId];
    if (sel is FileViewerSession && isInsideProject(sel.projectId, sel.path)) {
      _selectedFileInTree = sel.path;
      _treeRevealPath = sel.path;
      _treeRevealGen++;
    }
    notifyListeners();
  }

  /// Pane focada do projeto ativo + seu leaf, ou `null` se não há projeto ativo
  /// nem pane. Se nada está explicitamente focado, cai na primeira pane da árvore.
  (String, LeafPane)? _focusedLeaf() {
    final projectId = _selectedProjectId;
    final tree = _activeTree;
    if (projectId == null || tree == null) return null;
    final panes = leaves(tree);
    if (panes.isEmpty) return null;
    final paneId = _focused[projectId] ?? panes.first.id;
    final leaf = findLeaf(tree, paneId);
    return leaf == null ? null : (paneId, leaf);
  }

  /// Seleciona a aba de índice [index] (0-based) na pane focada — o atalho
  /// ⌘1…⌘8. No-op se o índice está fora do range (⌘5 numa pane de 3 abas não
  /// faz nada) ou se não há pane focada.
  void selectTabByIndex(int index) {
    final focused = _focusedLeaf();
    if (focused == null) return;
    final (paneId, leaf) = focused;
    if (index < 0 || index >= leaf.tabs.length) return;
    selectTab(paneId, leaf.tabs[index]);
  }

  /// Seleciona a **última** aba da pane focada — o atalho ⌘9, na convenção de
  /// browsers/iTerm ("pula pra última", não pra 9ª). No-op se a pane não tem aba.
  void selectLastTab() {
    final focused = _focusedLeaf();
    if (focused == null) return;
    final (paneId, leaf) = focused;
    if (leaf.tabs.isEmpty) return;
    selectTab(paneId, leaf.tabs.last);
  }

  /// Move o foco pra pane vizinha na direção [move] — os atalhos ⌘⌥ + setas.
  /// No-op se há só uma pane ou não existe vizinha naquela direção (fica onde
  /// está, sem ciclar). Deriva a vizinhança da árvore via [neighborLeaf].
  void focusPaneToward(PaneMove move) {
    final projectId = _selectedProjectId;
    final tree = _activeTree;
    if (projectId == null || tree == null) return;
    final panes = leaves(tree);
    if (panes.length < 2) return;
    final current = _focused[projectId] ?? panes.first.id;
    final target = neighborLeaf(tree, current, move);
    if (target == null || target == current) return;
    focus(target);
  }

  /// Abre uma aba "Novo" (placeholder vazio) na pane — o usuário escolhe ali
  /// dentro se quer um agente ou um terminal (via [fillEmpty]). Mesma cara da
  /// aba inicial de um workspace recém-aberto.
  void newEmptyTab(String paneId) {
    final projectId = _selectedProjectId;
    final tree = _activeTree;
    if (projectId == null || tree == null) return;
    final empty = _makeEmpty(projectId);
    _setActiveTree(
      updateLeaf(
        tree,
        paneId,
        (p) => p.copyWith(tabs: [...p.tabs, empty.id], active: empty.id),
      ),
    );
    _focused[projectId] = paneId;
    notifyListeners();
  }

  /// Cria uma aba (agente ou terminal) direto na subpasta [subRelative] do
  /// projeto ativo, na pane focada — **sem dialog**. Usada pelo menu de contexto
  /// da árvore de arquivos. Se a pane focada está num placeholder "Novo" vazio,
  /// substitui-o; senão, anexa uma aba nova e a ativa.
  void newTabIn(
    String subRelative, {
    required bool terminal,
    // Plano 50: perfil específico (seletor ao lado do `+`). `null` = padrão
    // efetivo. Ignorado quando `terminal` é `false`.
    TerminalProfile? profile,
  }) {
    final projectId = _selectedProjectId;
    final tree = _activeTree;
    if (projectId == null || tree == null) return;
    final paneId = _focused[projectId] ?? leaves(tree).first.id;
    final leaf = findLeaf(tree, paneId) ?? leaves(tree).first;
    final s = _spawn(subRelative, terminal: terminal, profile: profile);

    final active = _sessions[leaf.active];
    final replaceEmpty =
        active is AgentSession && active.status == AgentStatus.empty;

    _setActiveTree(
      updateLeaf(tree, leaf.id, (p) {
        if (replaceEmpty) {
          final tabs = p.tabs.map((t) => t == leaf.active ? s.id : t).toList();
          return p.copyWith(tabs: tabs, active: s.id);
        }
        return p.copyWith(tabs: [...p.tabs, s.id], active: s.id);
      }),
    );
    if (replaceEmpty) _disposeSession(leaf.active);
    _focused[projectId] = leaf.id;
    notifyListeners();
  }

  /// Cria uma aba de **terminal** com [cwd] absoluto — usada pela CLI interna
  /// (`cockpit new-tab`), que não passa pelo dialog nem por subpasta relativa.
  /// [inPane] ancora a criação numa folha específica (a da tab emissora);
  /// `null` = pane focada. [splitDir] `null` = nova aba na mesma pane; senão
  /// divide a pane âncora naquela direção. [title] vira o rótulo manual
  /// (estável, endereçável por `read-tab <label>`); sem título, a aba segue o
  /// título automático. Devolve o id da tab criada, ou a mensagem de erro.
  Result<String, String> newTerminalTab({
    required String cwd,
    String? title,
    String? inPane,
    SplitDir? splitDir,
  }) {
    final projectId = _selectedProjectId;
    final tree = _activeTree;
    if (projectId == null || tree == null) {
      return const Failure('no active workspace to create the terminal in');
    }
    final anchorId = inPane ?? _focused[projectId] ?? leaves(tree).first.id;
    final leaf = findLeaf(tree, anchorId) ?? leaves(tree).first;

    final s = _buildTerminal(
      _nid('t'),
      projectId,
      cwd,
      title: title ?? _sanitizeName(_basename(cwd)),
    );
    if (title != null && title.trim().isNotEmpty) {
      s.setManualLabel(title);
    }

    if (splitDir == null) {
      // Mesma pane: anexa como aba nova (substituindo o placeholder "Novo",
      // se for a aba ativa — mesma regra do `newTabIn`).
      final active = _sessions[leaf.active];
      final replaceEmpty =
          active is AgentSession && active.status == AgentStatus.empty;
      _setActiveTree(
        updateLeaf(tree, leaf.id, (p) {
          if (replaceEmpty) {
            final tabs = p.tabs
                .map((t) => t == leaf.active ? s.id : t)
                .toList();
            return p.copyWith(tabs: tabs, active: s.id);
          }
          return p.copyWith(tabs: [...p.tabs, s.id], active: s.id);
        }),
      );
      if (replaceEmpty) _disposeSession(leaf.active);
      _focused[projectId] = leaf.id;
    } else {
      final newLeaf = LeafPane(id: _nid('pane'), tabs: [s.id], active: s.id);
      _setActiveTree(
        splitLeaf(tree, leaf.id, splitDir, newLeaf, splitId: _nid('sp')),
      );
      _focused[projectId] = newLeaf.id;
    }
    notifyListeners();
    return Success(s.id);
  }

  /// `true` se a aba ativa da pane [paneId] é um terminal. O split espelha esse
  /// tipo (terminal→terminal), então o call site usa isso pra decidir se pergunta
  /// a subpasta (agente) ou abre direto na raiz (terminal).
  bool paneActiveIsTerminal(String paneId) {
    final tree = _activeTree;
    if (tree == null) return false;
    final leaf = findLeaf(tree, paneId);
    final active = leaf == null ? null : _sessions[leaf.active];
    return active is TerminalSession;
  }

  /// `true` se a aba ativa da pane [paneId] é um placeholder "Novo" (ainda não
  /// virou agente nem terminal). O split usa isso pra criar outro placeholder
  /// — que mostra o seletor Agent/Terminal — em vez de espelhar um tipo que
  /// ainda não existe (o que hoje spawaria um agente indevidamente).
  bool paneActiveIsEmpty(String paneId) {
    final tree = _activeTree;
    if (tree == null) return false;
    final leaf = findLeaf(tree, paneId);
    final active = leaf == null ? null : _sessions[leaf.active];
    return active is AgentSession && active.status == AgentStatus.empty;
  }

  /// Divide a pane criando uma aba "Novo" (placeholder vazio) ao lado/abaixo.
  /// Usada quando a aba ativa da pane de origem ainda é um placeholder (não é
  /// agente nem terminal): o novo pane mostra o mesmo seletor Agent/Terminal
  /// do "+" — ou cai direto em terminal quando `enableAgent` está off (a
  /// conversão automática vive no [EmptyPane], então não precisa decidir aqui).
  void splitPaneEmpty(String paneId, SplitDir dir) {
    final projectId = _selectedProjectId;
    final tree = _activeTree;
    if (projectId == null || tree == null) return;
    final empty = _makeEmpty(projectId);
    final newLeaf = LeafPane(
      id: _nid('pane'),
      tabs: [empty.id],
      active: empty.id,
    );
    _setActiveTree(splitLeaf(tree, paneId, dir, newLeaf, splitId: _nid('sp')));
    _focused[projectId] = newLeaf.id;
    notifyListeners();
  }

  /// Divide a pane criando um agente novo ao lado/abaixo.
  void splitPane(String paneId, SplitDir dir, String subRelative) {
    final tree = _activeTree;
    if (tree == null) return;
    // O novo pane espelha o tipo da aba ativa: terminal → terminal, agente → agente.
    final leaf = findLeaf(tree, paneId);
    final active = leaf == null ? null : _sessions[leaf.active];
    final terminal = active is TerminalSession;
    final s = _spawn(subRelative, terminal: terminal);
    final newLeaf = LeafPane(id: _nid('pane'), tabs: [s.id], active: s.id);
    _setActiveTree(splitLeaf(tree, paneId, dir, newLeaf, splitId: _nid('sp')));
    _focused[_selectedProjectId!] = newLeaf.id;
    notifyListeners();
  }

  // ---- drag & drop de abas --------------------------------------------------

  /// Move a aba [tabId] (de [srcPaneId]) pra dentro de [targetPaneId] como mais
  /// uma aba (acoplar). A sessão **não** é morta — só muda de lugar.
  void moveTabToPane(String srcPaneId, String tabId, String targetPaneId) {
    final projectId = _selectedProjectId;
    final tree = _activeTree;
    if (projectId == null || tree == null) return;
    if (srcPaneId == targetPaneId) return; // já está aqui
    final src = findLeaf(tree, srcPaneId);
    final tgt = findLeaf(tree, targetPaneId);
    if (src == null || tgt == null || !src.tabs.contains(tabId)) return;

    final remaining = src.tabs.where((t) => t != tabId).toList();
    // Acopla no destino…
    var t = updateLeaf(
      tree,
      targetPaneId,
      (p) => p.copyWith(tabs: [...p.tabs, tabId], active: tabId),
    );
    // …e tira da origem. src != target ⇒ há ≥2 folhas, então removeLeaf é seguro.
    if (remaining.isEmpty) {
      t = removeLeaf(t, srcPaneId);
    } else {
      t = updateLeaf(
        t,
        srcPaneId,
        (p) => p.copyWith(
          tabs: remaining,
          active: _activeAfter(src, tabId, remaining),
        ),
      );
    }
    _setActiveTree(t);
    _focused[projectId] = targetPaneId;
    _ensureFocusValid();
    notifyListeners();
  }

  /// Move a aba [tabId] (de [srcPaneId]) pra um **novo pane** criado dividindo
  /// [targetPaneId] em [dir]. [before] = novo pane antes (esquerda/cima) ou
  /// depois (direita/baixo). A sessão só muda de lugar (não é morta).
  void moveTabToNewSplit(
    String srcPaneId,
    String tabId,
    String targetPaneId,
    SplitDir dir, {
    required bool before,
  }) {
    final projectId = _selectedProjectId;
    final tree = _activeTree;
    if (projectId == null || tree == null) return;
    final src = findLeaf(tree, srcPaneId);
    final tgt = findLeaf(tree, targetPaneId);
    if (src == null || tgt == null || !src.tabs.contains(tabId)) return;

    final remaining = src.tabs.where((t) => t != tabId).toList();
    // Dividir o próprio pane que só tem essa aba contra si mesmo: no-op.
    if (srcPaneId == targetPaneId && remaining.isEmpty) return;

    final newLeaf = LeafPane(id: _nid('pane'), tabs: [tabId], active: tabId);
    var t = tree;
    // 1. Tira a aba da origem (se ainda sobra algo nela).
    if (remaining.isNotEmpty) {
      t = updateLeaf(
        t,
        srcPaneId,
        (p) => p.copyWith(
          tabs: remaining,
          active: _activeAfter(src, tabId, remaining),
        ),
      );
    }
    // 2. Divide o alvo, inserindo o novo pane.
    t = splitLeaf(
      t,
      targetPaneId,
      dir,
      newLeaf,
      splitId: _nid('sp'),
      before: before,
    );
    // 3. Origem ficou vazia → remove (o irmão expande).
    if (remaining.isEmpty) {
      t = removeLeaf(t, srcPaneId);
    }
    _setActiveTree(t);
    _focused[projectId] = newLeaf.id;
    _ensureFocusValid();
    notifyListeners();
  }

  /// Reordena a aba [tabId] dentro do **mesmo** pane, ou a insere numa posição
  /// específica de **outro** pane. [index] é o slot desejado na lista de abas do
  /// destino (0..len). A sessão só muda de lugar (não é morta).
  void moveTabToIndex(
    String srcPaneId,
    String tabId,
    String targetPaneId,
    int index,
  ) {
    final projectId = _selectedProjectId;
    final tree = _activeTree;
    if (projectId == null || tree == null) return;
    final src = findLeaf(tree, srcPaneId);
    final tgt = findLeaf(tree, targetPaneId);
    if (src == null || tgt == null || !src.tabs.contains(tabId)) return;

    // Reordenação dentro da mesma folha.
    if (srcPaneId == targetPaneId) {
      final tabs = reorderTabs(src.tabs, tabId, index);
      _setActiveTree(
        updateLeaf(
          tree,
          srcPaneId,
          (p) => p.copyWith(tabs: tabs, active: tabId),
        ),
      );
      _focused[projectId] = srcPaneId;
      notifyListeners();
      return;
    }

    // Cross-pane: insere na posição pedida do destino e tira da origem.
    final remaining = src.tabs.where((t) => t != tabId).toList();
    final tgtTabs = [...tgt.tabs];
    tgtTabs.insert(index.clamp(0, tgtTabs.length), tabId);
    var t = updateLeaf(
      tree,
      targetPaneId,
      (p) => p.copyWith(tabs: tgtTabs, active: tabId),
    );
    if (remaining.isEmpty) {
      t = removeLeaf(t, srcPaneId);
    } else {
      t = updateLeaf(
        t,
        srcPaneId,
        (p) => p.copyWith(
          tabs: remaining,
          active: _activeAfter(src, tabId, remaining),
        ),
      );
    }
    _setActiveTree(t);
    _focused[projectId] = targetPaneId;
    _ensureFocusValid();
    notifyListeners();
  }

  /// Qual aba fica ativa numa folha após [removedId] sair (mantém a ativa se não
  /// for a removida; senão pega a anterior).
  String _activeAfter(LeafPane leaf, String removedId, List<String> remaining) {
    if (leaf.active != removedId) return leaf.active;
    final idx = leaf.tabs.indexOf(removedId);
    return remaining[(idx - 1).clamp(0, remaining.length - 1)];
  }

  /// Preenche uma pane vazia: troca o placeholder por um agente ou terminal.
  void fillEmpty(
    String paneId,
    String emptyId,
    String subRelative, {
    bool terminal = false,
  }) {
    final tree = _activeTree;
    if (tree == null) return;
    final s = _spawn(subRelative, terminal: terminal);
    _setActiveTree(
      updateLeaf(tree, paneId, (p) {
        final tabs = p.tabs.map((t) => t == emptyId ? s.id : t).toList();
        return p.copyWith(tabs: tabs, active: s.id);
      }),
    );
    _disposeSession(emptyId);
    _focused[_selectedProjectId!] = paneId;
    notifyListeners();
  }

  void closeTab(String paneId, String agentId) {
    final projectId = _selectedProjectId;
    final tree = _activeTree;
    if (projectId == null || tree == null) return;
    final leaf = findLeaf(tree, paneId);
    if (leaf == null) return;
    final tabs = leaf.tabs.where((t) => t != agentId).toList();
    if (tabs.isEmpty) {
      if (leaves(tree).length == 1) {
        final empty = _makeEmpty(projectId);
        _setActiveTree(
          updateLeaf(
            tree,
            paneId,
            (p) => p.copyWith(tabs: [empty.id], active: empty.id),
          ),
        );
      } else {
        _setActiveTree(removeLeaf(tree, paneId));
      }
    } else {
      var active = leaf.active;
      if (active == agentId) {
        final idx = leaf.tabs.indexOf(agentId);
        active = tabs[(idx - 1).clamp(0, tabs.length - 1)];
      }
      _setActiveTree(
        updateLeaf(tree, paneId, (p) => p.copyWith(tabs: tabs, active: active)),
      );
    }
    _disposeSession(agentId);
    _ensureFocusValid();
    notifyListeners();
  }

  void closePane(String paneId) {
    final projectId = _selectedProjectId;
    final tree = _activeTree;
    if (projectId == null || tree == null) return;
    final leaf = findLeaf(tree, paneId);
    if (leaf == null) return;
    final ids = [...leaf.tabs];
    if (leaves(tree).length == 1) {
      final empty = _makeEmpty(projectId);
      _setActiveTree(
        updateLeaf(
          tree,
          paneId,
          (p) => p.copyWith(tabs: [empty.id], active: empty.id),
        ),
      );
    } else {
      _setActiveTree(removeLeaf(tree, paneId));
    }
    for (final id in ids) {
      _disposeSession(id);
    }
    _ensureFocusValid();
    notifyListeners();
  }

  void resizeSplit(String splitId, double frac) {
    final tree = _activeTree;
    if (tree == null) return;
    _setActiveTree(setFrac(tree, splitId, frac.clamp(0.16, 0.84)));
    notifyListeners();
  }

  /// Soma [dFrac] ao `frac` ATUAL do split (drag do divisor). Diferente de
  /// [resizeSplit] (valor absoluto), lê o frac corrente da árvore — que é
  /// atualizado síncrono a cada evento — e acumula. Isso evita o divisor
  /// "ficar pra trás" do mouse: vários `onPanUpdate` podem chegar antes do
  /// rebuild, e cada um traz só um delta incremental; somar sobre um `aSize`
  /// capturado no build descartava os deltas do mesmo frame.
  void resizeSplitBy(String splitId, double dFrac) {
    final tree = _activeTree;
    if (tree == null) return;
    final split = findSplit(tree, splitId);
    if (split == null) return;
    _setActiveTree(
      setFrac(tree, splitId, (split.frac + dFrac).clamp(0.16, 0.84)),
    );
    notifyListeners();
  }

  void toggleRail() {
    _railVisible = !_railVisible;
    _persistPanels();
    notifyListeners();
  }

  void toggleTree() {
    _treeVisible = !_treeVisible;
    _persistPanels();
    notifyListeners();
  }

  // ---- helpers --------------------------------------------------------------

  /// Raiz (path) do workspace [projectId] — usada pela tab `.dbq` pra
  /// resolver conexões/paths relativos (plano 51).
  String? projectRootOf(String projectId) => _projectById(projectId)?.path;

  Project? _projectById(String? id) {
    for (final project in _projectList) {
      if (project.id == id) return project;
    }
    return null;
  }

  /// Id do workspace raiz dono de [id] (ele mesmo, se já for raiz).
  String _rootOf(String id) => _projectById(id)?.parentId ?? id;

  PaneNode? get _activeTree =>
      _selectedProjectId == null ? null : _trees[_selectedProjectId];

  void _setActiveTree(PaneNode tree) {
    final id = _selectedProjectId;
    if (id != null) _trees[id] = tree;
  }

  void _initTree(String projectId) {
    if (_trees.containsKey(projectId)) return;
    final empty = _makeEmpty(projectId);
    final leaf = LeafPane(id: _nid('pane'), tabs: [empty.id], active: empty.id);
    _trees[projectId] = leaf;
    _focused[projectId] = leaf.id;
  }

  PaneItem _spawn(
    String subRelative, {
    required bool terminal,
    TerminalProfile? profile,
  }) {
    final project = selectedProject!;
    // Cockpit (terminal-only, sem pasta): shell sempre no HOME do usuário,
    // ignorando `subRelative`. Nunca spawna agente aqui (a UI força terminal).
    if (project.isSystemTerminal) {
      return _buildTerminal(
        _nid('t'),
        project.id,
        userHome() ?? '',
        title: 'Terminal',
        profile: profile,
      );
    }
    final cwd = subRelative.isEmpty
        ? project.path
        : '${project.path}/$subRelative';
    final title = _sanitizeName(
      subRelative.isEmpty ? project.name : _basename(subRelative),
    );
    return terminal
        ? _buildTerminal(
            _nid('t'),
            project.id,
            cwd,
            title: title,
            profile: profile,
          )
        : _buildAgent(_nid('a'), project, cwd, title: title);
  }

  TerminalSession _buildTerminal(
    String id,
    String projectId,
    String cwd, {
    String? title,
    String? replay,
    String? startupCommand,
    String? manualLabel,
    // Plano 50: `null` = o padrão efetivo (o que o `+` abre hoje). A fatia 3
    // (dropdown do `+`) passa um perfil específico sem mexer no padrão global.
    TerminalProfile? profile,
    TerminalEngine? engine,
  }) {
    final t = TerminalSession(
      id: id,
      projectId: projectId,
      workingDirectory: cwd,
      gateway: _terminalFactory.create(),
      profile: profile ?? defaultTerminalProfile,
      engine: engine ?? _defaultTerminalEngine,
      title: title,
      // Persistência do scrollback: grava a saída pra replay no próximo boot.
      scrollbackStore: _scrollback,
      // Restauração: histórico salvo a reproduzir antes do shell novo (null em
      // abas criadas do zero).
      replay: replay,
      // Restauração: comando a digitar no shell novo (ex.: `claude --resume`).
      startupCommand: startupCommand,
      // Injeta no env da PTY: roteamento (id da tab) + transporte (socket/porta).
      // O `cockpit-hook` do claude herda e reporta status de turno de volta.
      // `COCKPIT_TAB_ID` é o nome correto (o que a CLI endereça é uma tab);
      // `COCKPIT_PANE_ID` fica como alias legado (hook + binários antigos).
      spawnEnv: <String, String>{
        'COCKPIT_TAB_ID': id,
        'COCKPIT_PANE_ID': id,
        ..._statusServer.hookEnv,
        // PATH escopado → o binário `cockpit` (CLI interna) resolve só nas abas.
        ..._cliPathEnv(),
      },
    );
    // claude rodando na aba reporta fim de turno via socket → mesma notificação
    // do agente (badge se não for a aba ativa; OS notification se desfocado).
    t.onTurnFinished = () => unawaited(_notifyIfNeeded(t));
    // cwd vivo (OSC 7) mudou → persiste o layout pra restaurar o shell ali.
    t.onCwdChanged = () => _scheduleSave(projectId);
    // Restauração: re-arma a trava de nome sem notificar (aba ainda não montada).
    if (manualLabel != null) t.restoreManualLabel(manualLabel);
    _sessions[t.id] = t;
    return t;
  }

  /// Cria e boota um agente. [restoreSessionPath] (restauração) faz reanexar a
  /// conversa salva via `switch_session`; senão, a VM captura o arquivo de
  /// sessão que o pi criar (no 1º fim de turno) pra poder restaurar depois.
  /// O nome final é atribuído pelo broker via evento `remote-pi:name-assigned`
  /// quando houver colisão de mesh — [AgentSession] trata o evento e persiste.
  AgentSession _buildAgent(
    String id,
    Project project,
    String cwd, {
    String? title,
    bool autoStartRelay = false,
    String? restoreSessionPath,
    String? preferredModelId,
    ThinkingLevel preferredThinking = ThinkingLevel.off,
  }) {
    final s =
        AgentSession(
            id: id,
            projectId: project.id,
            workingDirectory: cwd,
            factory: _factory,
            title: title,
            autoStartRelay: autoStartRelay,
          )
          ..preferredModelId = preferredModelId
          ..preferredThinking = preferredThinking;
    s.onTurnEnd = () => _onAgentTurnEnd(s);
    s.onPreferenceChanged = () => _scheduleSave(project.id);
    _sessions[s.id] = s;
    unawaited(_bootAgent(s, cwd, project, restoreSessionPath));
    return s;
  }

  Future<void> _bootAgent(
    AgentSession s,
    String cwd,
    Project project,
    String? restoreSessionPath,
  ) async {
    s.sessionBaseline = (await _history.sessionsFor(
      cwd,
    )).map((e) => e.path).toSet();
    await s.boot(
      environment: _buildDirectConfig(s, project),
      restoreSessionPath: restoreSessionPath,
    );
  }

  /// Serializa `agent_name`, `auto_start_relay` e `workspace` em
  /// `REMOTE_PI_DIRECT_CONFIG` para o processo filho.
  Map<String, String> _buildDirectConfig(AgentSession s, Project project) {
    return {
      'REMOTE_PI_DIRECT_CONFIG': jsonEncode(<String, dynamic>{
        'agent_name': s.title,
        'workspace': project.name,
        'auto_start_relay': s.autoStartRelay,
      }),
      'REMOTE_PI_DAEMON': '1',
    };
  }

  // ---- notificações ---------------------------------------------------------

  /// Id do agente que o usuário está olhando (aba ativa da pane focada do
  /// projeto selecionado).
  String? get _focusedAgentId {
    final pid = _selectedProjectId;
    if (pid == null) return null;
    final tree = _trees[pid];
    if (tree == null) return null;
    final paneId = _focused[pid];
    final leaf = paneId == null ? null : findLeaf(tree, paneId);
    if (leaf != null) return leaf.active;
    final ls = leaves(tree);
    return ls.isEmpty ? null : ls.first.active;
  }

  /// Status reportado por um `claude` rodando numa aba de terminal (via o
  /// socket do [TerminalStatusServer]). Roteia pela [ClaudeStatusUpdate.paneId].
  void _onClaudeStatus(ClaudeStatusUpdate u) {
    final s = _sessions[u.paneId];
    if (s is! TerminalSession) return;
    final hadSid = s.claudeSessionId;
    s.applyClaudeStatus(
      status: switch (u.status) {
        'working' => TerminalStatus.working,
        'waiting' => TerminalStatus.waiting,
        _ => TerminalStatus.idle,
      },
      // `UserPromptSubmit` marca o INÍCIO de um turno novo — o único `working`
      // que sempre vale, mesmo logo após um `idle` (ex.: mensagem enfileirada).
      // Os demais `working` (Pre/PostToolUse) são atividade mid-turn e podem ser
      // descartados se chegarem fora de ordem depois do fim do turno.
      isTurnStart: u.event == 'UserPromptSubmit',
      sessionId: u.sessionId,
      transcriptPath: u.transcriptPath,
    );
    // O session-id do claude chega assíncrono pelo hook (não numa mutação de
    // layout), então persiste o layout quando ele MUDA — senão `claude_sid`
    // nunca chega ao disco e o restore não consegue dar `claude --resume`.
    if (s.claudeSessionId != hadSid && s.claudeSessionId != null) {
      _scheduleSave(s.projectId);
    }
  }

  /// Env de PATH escopado: prepend `~/.cockpit/bin` (onde o binário `cockpit` é
  /// materializado no boot) ao PATH **só dos terminais do Cockpit** — a CLI fica
  /// visível dentro das abas e invisível fora, sem poluir o PATH global.
  Map<String, String> _cliPathEnv() {
    final home = remotePiHome();
    if (home == null) return const <String, String>{};
    final binDir = '$home/.cockpit/bin';
    final sep = Platform.isWindows ? ';' : ':';
    final existing = Platform.environment['PATH'] ?? '';
    return <String, String>{
      'PATH': existing.isEmpty ? binDir : '$binDir$sep$existing',
    };
  }

  void _onAgentTurnEnd(AgentSession s) {
    if (s.sessionPath == null) unawaited(_captureSessionPath(s));
    unawaited(git.refresh(s.projectId));
    unawaited(_refreshWorktrees(_rootOf(s.projectId)));
    unawaited(_notifyIfNeeded(s));
  }

  /// Badge (ponto na aba) → só se o agente NÃO for a aba ativa.
  /// OS notification → só se a janela não estiver focada.
  /// Separar as duas responsabilidades evita badge preso: se o usuário já está
  /// na aba, não há nada a marcar — ele verá a resposta ao olhar para a janela.
  Future<void> _notifyIfNeeded(PaneItem s) async {
    final isActiveTab = s.id == _focusedAgentId;

    if (!isActiveTab) {
      s.markUnseen();
      notifyListeners();
    }

    final windowFocused = await windowManager.isFocused();
    if (!windowFocused) {
      // Janela em outro app → notificação do SO (tem som próprio).
      if (_notificationsEnabled) {
        final workspace = _projectById(s.projectId)?.name ?? '';
        await _notifier.agentFinished(agentName: s.title, workspace: workspace);
      }
    } else if (_soundEnabled) {
      // Janela focada → chime curto pra chamar atenção (inclusive na aba ativa).
      // Nunca junto da notificação → não se confunde com o som dela.
      await _notifier.playTurnChime();
    }
  }

  /// Limpa a notificação do agente que acabou de virar o focado.
  void _clearFocusedNotification() {
    final id = _focusedAgentId;
    final s = id == null ? null : _sessions[id];
    if (s != null && s.unseenFinish) s.clearUnseen();
  }

  AgentSession _makeEmpty(String projectId) =>
      _makeEmptyWithId(_nid('a'), projectId);

  AgentSession _makeEmptyWithId(String id, String projectId) {
    final s = AgentSession(
      id: id,
      projectId: projectId,
      workingDirectory: '',
      factory: _factory,
      title: 'New',
    );
    _sessions[s.id] = s;
    return s;
  }

  /// Chaves de scrollback a preservar no GC do boot: o `id` de cada sessão
  /// `terminal` e o `taskId` de cada `task_output` presentes em QUALQUER layout
  /// salvo. (O store de scrollback é compartilhado — logs de terminal sob o
  /// `projectId` real, logs de task sob `__tasks__/<taskId>` —, mas o prune casa
  /// por nome de arquivo, então o keep-set é a união das duas chaves.) Lê os
  /// descritores `sessions` dos docs já carregados em [_savedLayouts].
  Set<String> _persistedTerminalIds() {
    final ids = <String>{};
    for (final doc in _savedLayouts.values) {
      if (doc == null) continue;
      final sessions = doc['sessions'];
      if (sessions is! Map) continue;
      sessions.forEach((key, desc) {
        if (desc is! Map) return;
        if (desc['type'] == 'terminal' && key is String) {
          ids.add(key);
        } else if (desc['type'] == 'task_output' && desc['taskId'] is String) {
          ids.add(desc['taskId'] as String);
        }
      });
    }
    return ids;
  }

  void _disposeSession(String id) {
    _fileWatchers.remove(id)?.cancel();
    _fileWatchDebounce.remove(id)?.cancel();
    final s = _sessions.remove(id);
    // Aba fechada explicitamente → descarta o scrollback persistido (só abas de
    // terminal têm). O app-quit NÃO passa por aqui (chama `s.dispose()` direto em
    // `dispose()`), então o registro sobrevive pra restaurar — que é o objetivo.
    if (s is TerminalSession) {
      unawaited(_scrollback.delete(projectId: s.projectId, sessionId: id));
    }
    s?.dispose();
  }

  /// Observa o arquivo de uma aba de viewer e relê o conteúdo ao vivo quando ele
  /// muda no disco (decisão de UX — antes a aba congelava até fechar/reabrir). O
  /// debounce junta a rajada de eventos que um editor dispara num save; o re-read
  /// que volta `FileViewUnsupported` (sumiu/binário transitório) é ignorado pra
  /// não piscar. Tudo guardado por id de sessão e cancelado no `_disposeSession`.
  void _watchFileViewer(FileViewerSession viewer) {
    // A/V: live-reload desligado (plano 46). Recarregar recriaria o player no
    // meio da reprodução; mídia raramente é reescrita em disco.
    if (viewer.view is FileViewAudio || viewer.view is FileViewVideo) return;
    final id = viewer.id;
    _fileWatchers.remove(id)?.cancel();
    _fileWatchers[id] = _fileReader.watch(viewer.path).listen(
      (_) {
        _fileWatchDebounce[id]?.cancel();
        _fileWatchDebounce[id] = Timer(
          const Duration(milliseconds: 120),
          () async {
            _fileWatchDebounce.remove(id);
            if (_sessions[id] is! FileViewerSession) return; // aba fechou
            final fresh = await _fileReader.read(viewer.path);
            if (fresh is FileViewUnsupported) return;
            final s = _sessions[id];
            if (s is! FileViewerSession) return; // fechou durante o read
            s.view = fresh;
            notifyListeners();
          },
        );
      },
      onError: (_) {}, // watch falhou (sandbox, rename) → sem live-reload
    );
  }

  // ---- persistência do layout ----------------------------------------------

  /// Ativa um projeto (sobe os processos). Se há layout salvo, reconstrói a
  /// árvore + sessões; senão, abre uma pane vazia. Idempotente: já-ativo é no-op.
  Future<void> _activateProject(String id) async {
    if (_trees.containsKey(id)) return;
    final doc = _savedLayouts[id];
    if (doc == null) {
      _initTree(id); // síncrono — pane vazia padrão
      return;
    }
    _restoring = true;
    try {
      await _restoreProject(id, doc);
    } finally {
      _restoring = false;
    }
    notifyListeners();
  }

  Future<void> _restoreProject(String id, Map<String, dynamic> doc) async {
    final project = _projectById(id);
    final treeJson = doc['tree'];
    if (project == null || treeJson is! Map) {
      _initTree(id);
      return;
    }
    final sessionsJson =
        (doc['sessions'] as Map?)?.cast<String, dynamic>() ??
        const <String, dynamic>{};

    // Recria cada sessão (agente boota e reanexa; viewer re-lê o arquivo).
    final created = <String>{};
    for (final entry in sessionsJson.entries) {
      final desc = (entry.value as Map).cast<String, dynamic>();
      if (await _restoreSession(entry.key, desc, project)) {
        created.add(entry.key);
      }
    }

    var tree = paneNodeFromJson(treeJson.cast<String, dynamic>());
    _bumpSeqPast(sessionsJson.keys, tree); // antes do sanitize criar ids novos
    tree = _sanitizeTree(
      tree,
      created,
      id,
    ); // descarta abas que não restauraram
    _trees[id] = tree;
    final focused = doc['focused'] as String?;
    _focused[id] = (focused != null && findLeaf(tree, focused) != null)
        ? focused
        : leaves(tree).first.id;
  }

  /// Recria uma sessão a partir do descritor. `false` = não deu pra restaurar
  /// (ex.: viewer de arquivo que sumiu) → a aba é descartada no sanitize.
  Future<bool> _restoreSession(
    String id,
    Map<String, dynamic> desc,
    Project project,
  ) async {
    String cwdOf() {
      final sub = desc['sub'] as String? ?? '';
      return sub.isEmpty ? project.path : '${project.path}/$sub';
    }

    switch (desc['type']) {
      case 'terminal':
        // Carrega o scrollback salvo e o reproduz no terminal restaurado. O
        // `\x1bc` (RIS) prepended limpa qualquer modo residual (alt-screen) em
        // que o processo morreu; o `\r\n` final põe o prompt novo numa linha
        // fresca abaixo do histórico.
        final raw = await _scrollback.load(
          projectId: project.id,
          sessionId: id,
        );
        // Se a aba rodava um `claude`, re-executa `claude --resume <sid>` no
        // shell novo (reanexa a conversa). O replay mostra o histórico até o
        // claude redesenhar; nas demais abas (shell puro) só há o replay.
        final claudeSid = desc['claude_sid'] as String?;
        // cwd vivo salvo (OSC 7, absoluto) vence o `sub` — restaura onde o
        // usuário parou, mesmo fora do projeto.
        final termCwd = desc['cwd'] as String? ?? cwdOf();
        _buildTerminal(
          id,
          project.id,
          termCwd,
          title: desc['title'] as String?,
          replay: raw == null ? null : 'c$raw\r\n',
          startupCommand: claudeSid == null || claudeSid.isEmpty
              ? null
              : 'claude --resume $claudeSid',
          // Re-arma a trava ANTES de o shell subir e re-emitir OSC-title: o nome
          // manual continua vencendo o título dinâmico após o reinício.
          manualLabel: desc['label'] as String?,
          engine: _enumByName(
            TerminalEngine.values,
            desc['engine'],
            TerminalEngine.xterm,
          ),
        );
        return true;
      case 'viewer':
        final path = desc['path'] as String?;
        if (path == null) return false;
        final view = await _fileReader.read(path);
        if (view is FileViewUnsupported) return false;
        _sessions[id] = FileViewerSession(
          id: id,
          projectId: project.id,
          path: path,
          view: view,
        );
        return true;
      case 'diff':
        final path = desc['path'] as String?;
        if (path == null) return false;
        final diff = await _gitDiff.read(project.path, path);
        _sessions[id] = DiffViewerSession(
          id: id,
          projectId: project.id,
          path: path,
          diff: diff,
        );
        return true;
      case 'redis':
        final conn = desc['conn'] as String?;
        if (conn == null || conn.isEmpty) return false;
        _sessions[id] = RedisBrowserSession(
          id: id,
          projectId: project.id,
          connName: conn,
          workingDirectory: project.path,
        );
        return true;
      case 'mongo':
        final mConn = desc['conn'] as String?;
        final mColl = desc['collection'] as String?;
        if (mConn == null || mConn.isEmpty || mColl == null || mColl.isEmpty) {
          return false;
        }
        _sessions[id] = MongoBrowserSession(
          id: id,
          projectId: project.id,
          connName: mConn,
          collection: mColl,
          workingDirectory: project.path,
        );
        return true;
      case 'empty':
        _makeEmptyWithId(id, project.id);
        return true;
      case 'task_output':
        // A task em si não roda de novo, mas o output foi persistido pelo
        // `TaskTerminalStore`. Recria a aba read-only: `terminalFor` semeia o
        // último output salvo no terminal. Sem `taskId` (descritor antigo) →
        // descarta no `_sanitizeTree`.
        final taskId = desc['taskId'] as String?;
        if (taskId == null || taskId.isEmpty) return false;
        _sessions[id] = TaskOutputSession(
          id: id,
          projectId: project.id,
          taskId: taskId,
          label: desc['label'] as String? ?? taskId,
          terminal: _taskTerminals.terminalFor(
            taskId,
            engine: _enumByName(
              TerminalEngine.values,
              desc['engine'],
              TerminalEngine.xterm,
            ),
          ),
          workingDirectory: project.path,
        );
        return true;
      case 'agent':
      default:
        _buildAgent(
          id,
          project,
          cwdOf(),
          title: desc['title'] as String?,
          autoStartRelay: desc['auto_start_relay'] == true,
          restoreSessionPath: desc['sessionPath'] as String?,
          preferredModelId: desc['preferred_model'] as String?,
          preferredThinking: _enumByName(
            ThinkingLevel.values,
            desc['preferred_thinking'],
            ThinkingLevel.off,
          ),
        );
        return true;
    }
  }

  /// Limpa a árvore restaurada: filtra abas cuja sessão não foi recriada e, se
  /// uma folha ficar vazia, põe um placeholder (preserva o layout).
  PaneNode _sanitizeTree(PaneNode node, Set<String> present, String projectId) {
    switch (node) {
      case LeafPane():
        final tabs = node.tabs.where(present.contains).toList();
        if (tabs.isEmpty) {
          final e = _makeEmpty(projectId);
          return LeafPane(id: node.id, tabs: [e.id], active: e.id);
        }
        final active = tabs.contains(node.active) ? node.active : tabs.first;
        return LeafPane(id: node.id, tabs: tabs, active: active);
      case SplitPane():
        return node.copyWith(
          a: _sanitizeTree(node.a, present, projectId),
          b: _sanitizeTree(node.b, present, projectId),
        );
    }
  }

  /// Avança `_seq` além de qualquer sufixo numérico dos ids restaurados, pra
  /// `_nid` não colidir com ids reaproveitados.
  void _bumpSeqPast(Iterable<String> sessionIds, PaneNode tree) {
    var maxN = _seq;
    void scan(String id) {
      final m = RegExp(r'(\d+)$').firstMatch(id);
      if (m != null) maxN = max(maxN, int.parse(m.group(1)!) + 1);
    }

    sessionIds.forEach(scan);
    void walk(PaneNode n) {
      scan(n.id);
      switch (n) {
        case LeafPane():
          n.tabs.forEach(scan);
        case SplitPane():
          walk(n.a);
          walk(n.b);
      }
    }

    walk(tree);
    _seq = maxN;
  }

  /// Descobre, por diferença com a [AgentSession.sessionBaseline], qual arquivo
  /// de sessão o pi criou pra este agente, e o guarda pra restaurar depois.
  Future<void> _captureSessionPath(AgentSession s) async {
    final baseline = s.sessionBaseline;
    if (baseline == null || s.sessionPath != null) return;
    final now = await _history.sessionsFor(s.workingDirectory);
    final fresh = now.where((e) => !baseline.contains(e.path)).toList();
    if (fresh.isEmpty) return;
    fresh.sort((a, b) => b.modifiedAt.compareTo(a.modifiedAt));
    s.sessionPath = fresh.first.path;
    notifyListeners(); // persiste o path
  }

  Map<String, dynamic> _serializeLayout(String projectId) {
    final tree = _trees[projectId];
    final project = _projectById(projectId);
    if (tree == null || project == null) return const <String, dynamic>{};
    final sessions = <String, dynamic>{};
    for (final leaf in leaves(tree)) {
      for (final id in leaf.tabs) {
        final s = _sessions[id];
        if (s != null) sessions[id] = _sessionToJson(s, project);
      }
    }
    return <String, dynamic>{
      'v': 1,
      'focused': _focused[projectId],
      'tree': paneNodeToJson(tree),
      'sessions': sessions,
    };
  }

  /// Clona a estrutura de panes/abas do projeto [rootId] num doc de layout novo:
  /// **ids frescos**, **sem `sessionPath`** (sessões começam do zero) e **sem
  /// viewers**. A árvore (splits/posições/frac) e o `sub` relativo de cada
  /// agente/terminal são preservados — ao restaurar no fork, o `cwd` vira
  /// `fork.path + sub`, ou seja, a mesma estrutura na pasta do worktree.
  /// `null` se o root não tem layout (ou só tinha viewers).
  Map<String, dynamic>? _cloneLayoutForWorktree(String rootId) {
    final doc = _trees.containsKey(rootId)
        ? _serializeLayout(rootId)
        : _savedLayouts[rootId];
    if (doc == null || doc.isEmpty) return null;
    final treeJson = doc['tree'];
    final sessionsJson = doc['sessions'];
    if (treeJson is! Map || sessionsJson is! Map) return null;

    // 1. Remapeia sessões: dropa viewers, remove sessionPath, id novo por tipo.
    final tabIdMap = <String, String>{};
    final newSessions = <String, dynamic>{};
    for (final entry in sessionsJson.entries) {
      final desc = Map<String, dynamic>.from(entry.value as Map);
      // worktree não replica viewers nem diffs (efêmeros)
      if (desc['type'] == 'viewer' || desc['type'] == 'diff') continue;
      // Zera qualquer estado de continuação — o worktree é um workspace novo,
      // sessões começam do zero. `sessionPath` (agente) e `claude_sid`
      // (terminal: dispararia `claude --resume <sid>` do pai) reanexariam a
      // conversa do root; `cwd` (OSC 7 absoluto do pai) subiria o shell na
      // pasta do root em vez de `fork.path + sub`.
      desc
        ..remove('sessionPath')
        ..remove('claude_sid')
        ..remove('cwd');
      final newId = _nid(desc['type'] == 'terminal' ? 't' : 'a');
      tabIdMap[entry.key as String] = newId;
      newSessions[newId] = desc;
    }
    if (newSessions.isEmpty) return null;

    // 2. Remapeia a árvore (ids de folha/split novos; abas via tabIdMap).
    final nodeIdMap = <String, String>{};
    final newTree = _remapTreeForClone(
      paneNodeFromJson(treeJson.cast<String, dynamic>()),
      tabIdMap,
      nodeIdMap,
    );
    final focused = doc['focused'];
    return <String, dynamic>{
      'v': 1,
      'focused': focused is String ? nodeIdMap[focused] : null,
      'tree': paneNodeToJson(newTree),
      'sessions': newSessions,
    };
  }

  PaneNode _remapTreeForClone(
    PaneNode node,
    Map<String, String> tabIdMap,
    Map<String, String> nodeIdMap,
  ) {
    switch (node) {
      case LeafPane():
        final newId = nodeIdMap.putIfAbsent(node.id, () => _nid('pane'));
        final tabs = <String>[
          for (final t in node.tabs)
            if (tabIdMap[t] != null) tabIdMap[t]!,
        ];
        // Folha que só tinha viewers fica vazia → o sanitize do restore põe um
        // placeholder. `active` aqui é só um fallback inofensivo nesse caso.
        final active =
            tabIdMap[node.active] ?? (tabs.isNotEmpty ? tabs.first : newId);
        return LeafPane(id: newId, tabs: tabs, active: active);
      case SplitPane():
        final newId = nodeIdMap.putIfAbsent(node.id, () => _nid('sp'));
        return SplitPane(
          id: newId,
          dir: node.dir,
          frac: node.frac,
          a: _remapTreeForClone(node.a, tabIdMap, nodeIdMap),
          b: _remapTreeForClone(node.b, tabIdMap, nodeIdMap),
        );
    }
  }

  Map<String, dynamic> _sessionToJson(PaneItem s, Project project) {
    if (s is TerminalSession) {
      return <String, dynamic>{
        'type': 'terminal',
        'sub': _subOf(s.workingDirectory, project.path),
        'title': s.title,
        'engine': s.terminal.engine.name,
        // Rótulo manual travado (se houver): persiste com o descritor da aba,
        // que no restore é re-hidratado pela mesma chave de sessão → o nome
        // estável sobrevive ao reinício e à re-emissão de OSC-title do shell.
        if (s.manualLabel != null) 'label': s.manualLabel,
        // cwd vivo do shell (OSC 7), absoluto — o restore sobe o shell aqui (o
        // usuário pode ter dado `cd` pra fora do projeto). `sub` segue como
        // fallback pra abas que nunca emitiram OSC 7.
        if (s.currentDirectory != null) 'cwd': s.currentDirectory,
        // Se um `claude` rodava nesta aba, guarda o session-id (capturado pelo
        // hook) pra re-executar `claude --resume <sid>` no restore.
        if (s.claudeSessionId != null) 'claude_sid': s.claudeSessionId,
      };
    }
    if (s is FileViewerSession) {
      return <String, dynamic>{'type': 'viewer', 'path': s.path};
    }
    if (s is DiffViewerSession) {
      return <String, dynamic>{'type': 'diff', 'path': s.path};
    }
    if (s is RedisBrowserSession) {
      return <String, dynamic>{'type': 'redis', 'conn': s.connName};
    }
    if (s is MongoBrowserSession) {
      return <String, dynamic>{
        'type': 'mongo',
        'conn': s.connName,
        'collection': s.collection,
      };
    }
    if (s is TaskOutputSession) {
      // A task não roda de novo no restart, mas o output persiste: guarda o
      // `taskId` (chave do log no `TaskTerminalStore`) + label pra recriar a aba
      // read-only mostrando o último output (ver `_restoreSession`).
      return <String, dynamic>{
        'type': 'task_output',
        'taskId': s.taskId,
        'label': s.label,
        'engine': s.terminal.engine.name,
      };
    }
    final a = s as AgentSession;
    if (a.status == AgentStatus.empty) {
      return <String, dynamic>{'type': 'empty', 'title': a.title};
    }
    return <String, dynamic>{
      'type': 'agent',
      'sub': _subOf(a.workingDirectory, project.path),
      'title': a.title,
      if (a.sessionPath != null) 'sessionPath': a.sessionPath,
      if (a.autoStartRelay) 'auto_start_relay': true,
      if (a.preferredModelId != null) 'preferred_model': a.preferredModelId,
      if (a.preferredThinking != ThinkingLevel.off)
        'preferred_thinking': a.preferredThinking.name,
    };
  }

  /// Caminho de [cwd] relativo à raiz [root] do projeto ('' = raiz). Devolve
  /// sempre com separador `/` (forma canônica interna).
  ///
  /// Normaliza `\`→`/` antes de comparar: no Windows os paths podem misturar
  /// separadores (ex.: a pasta do worktree vem do git com `\`, enquanto os cwds
  /// internos são montados com `/`). Sem isso o prefixo não casaria e o `sub`
  /// sairia vazio — quebrando o posicionamento por subpasta (e a clonagem de
  /// layout pro worktree).
  String _subOf(String cwd, String root) {
    final c = cwd.replaceAll('\\', '/');
    final r = root.replaceAll('\\', '/');
    if (c == r) return '';
    final prefix = r.endsWith('/') ? r : '$r/';
    return c.startsWith(prefix) ? c.substring(prefix.length) : '';
  }

  void _scheduleSave(String projectId) {
    // O Cockpit é efêmero (sessão só enquanto o app vive) — nunca persiste
    // layout. Chokepoint único: cobre resize, cwd, criação/fechamento de aba.
    if (isSystemTerminal(projectId)) return;
    _saveTimers[projectId]?.cancel();
    _saveTimers[projectId] = Timer(const Duration(milliseconds: 500), () {
      _saveTimers.remove(projectId);
      final doc = _serializeLayout(projectId);
      if (doc.isNotEmpty) unawaited(_layoutStore.save(projectId, doc));
    });
  }

  /// Reconcilia as worktrees de TODOS os workspaces raiz abertos contra o git —
  /// disparado a cada tick do poll do [GitController]. Pega worktrees criadas ou
  /// removidas por fora (outro terminal, o terminal do próprio fork) sem exigir
  /// reabrir o workspace. [_refreshWorktrees] deduplica e só notifica se a lista
  /// mudou, então o custo em repos parados é nulo.
  void _reconcileOpenWorktrees() {
    // Snapshot: [_refreshWorktrees] muda [_projectList] (após um await), então
    // não iteramos a lista viva.
    final roots = _projectList
        .where((p) => p.parentId == null && !p.isSystemTerminal)
        .map((p) => p.id)
        .toList();
    for (final rootId in roots) {
      unawaited(_refreshWorktrees(rootId));
    }
  }

  /// Reconcilia as worktrees de um workspace raiz contra o git (decisões 4, 5,
  /// 17, 20). Forks novos entram em [_projectList]; forks sumidos (por fora ou
  /// via remove) têm o runtime encerrado (mata `pi` + fecha panes — decisão 9) e,
  /// se selecionados, a seleção volta pro pai. Só notifica quando a lista muda.
  Future<void> _refreshWorktrees(String rootId) async {
    final root = _projectById(rootId);
    if (root == null || root.parentId != null || root.isSystemTerminal) return;

    // Multi-root: worktrees são **por root** — varre cada repo filho e anota a
    // origem (as ops de remove/merge/namespace rodam contra ela). Single-root
    // é o caso N=1: uma passada, comportamento histórico.
    final forks = <Project>[];
    final seenForkIds = <String>{};
    for (final rootPath in rootsOf(rootId)) {
      final wts = await _worktreeMgr.list(rootPath);
      for (final Worktree w in wts) {
        // Id namespaced pela raiz: o mesmo repo pode ser workspace em 2+
        // realms (paths iguais), e cada cópia reconcilia os próprios forks —
        // `w.path` cru colidiria entre elas. Estável entre reboots (rootId é
        // UUID persistido; w.path vem do git).
        final forkId = '$rootId::${w.path}';
        // Duas roots podem enxergar o mesmo worktree (ex.: worktree que também
        // é root do workspace) — o primeiro avistamento vence, com a origem da
        // root que o listou primeiro (ordem de rootsOf, alfabética).
        if (!seenForkIds.add(forkId)) continue;
        _forkOrigin[forkId] = rootPath;
        forks.add(
          Project(
            id: forkId,
            name: w.branch,
            path: w.path,
            colorValue: root.colorValue,
            createdAt: root.createdAt,
            realmId: root.realmId, // segue o realm da raiz
            parentId: rootId,
            order: root.order, // aninha junto do pai
          ),
        );
      }
    }

    final old = _worktrees[rootId] ?? const <Project>[];
    final oldSig = old.map((f) => '${f.id}|${f.name}').toList();
    final newSig = forks.map((f) => '${f.id}|${f.name}').toList();
    final newIds = forks.map((f) => f.id).toSet();
    final oldIds = old.map((f) => f.id).toSet();

    // Forks que sumiram → encerra runtime e tira de _projectList.
    var switched = false;
    for (final gone in old.where((f) => !newIds.contains(f.id))) {
      _disposeProjectRuntime(gone.id);
      _forkOrigin.remove(gone.id);
      _projectList.removeWhere((p) => p.id == gone.id);
      if (_selectedProjectId == gone.id) {
        _selectedProjectId = rootId; // pai assume
        switched = true;
      }
    }
    // Forks novos → entram em _projectList + carregam layout salvo (decisão 18).
    for (final fresh in forks.where((f) => !oldIds.contains(f.id))) {
      // Guarda contra refreshes concorrentes do mesmo root (vários call-sites
      // disparam unawaited): o id pode já ter entrado por outra passada.
      if (_projectList.any((p) => p.id == fresh.id)) continue;
      _projectList.add(fresh);
      var layout = await _layoutStore.load(fresh.id);
      // Layout de fork pré-realm era keyed pelo path cru do worktree (o id
      // antigo). Adota e re-keya on-the-fly — migração lazy, uma vez por fork.
      if (layout == null) {
        layout = await _layoutStore.load(fresh.path);
        if (layout != null) {
          await _layoutStore.save(fresh.id, layout);
          await _layoutStore.remove(fresh.path);
        }
      }
      _savedLayouts[fresh.id] = layout;
    }
    _worktrees[rootId] = forks;

    // dirtyCount por fork (decisão 8) — cada um notifica se mudou.
    for (final f in forks) {
      unawaited(git.refresh(f.id));
    }

    if (switched) {
      // O watcher Linux da worktree recebe onDone assim que o `git worktree
      // remove` apaga a pasta. Move-o explicitamente pro pai antes de qualquer
      // restauração assíncrona; deixá-lo apontado pro path sumido fazia o
      // recovery tentar observar a mesma pasta indefinidamente no build AOT.
      git.watchProject(_selectedProjectId);
      await _activateProject(_selectedProjectId!);
    }
    if (switched || !listEquals(oldSig, newSig)) notifyListeners();
  }

  void _ensureFocusValid() {
    final id = _selectedProjectId;
    if (id == null) return;
    final tree = _trees[id];
    if (tree == null) return;
    final ls = leaves(tree);
    if (ls.any((l) => l.id == _focused[id])) return;
    if (ls.isNotEmpty) _focused[id] = ls.first.id;
  }

  String _basename(String path) {
    final parts = path.split('/').where((p) => p.isNotEmpty).toList();
    return parts.isEmpty ? path : parts.last;
  }

  String _sanitizeName(String name) => name.replaceAll(' ', '-');

  /// Toda mudança estrutural passa por aqui → agenda (debounced) a gravação do
  /// layout do projeto ativo. Pulado durante a restauração (layout meio-feito).
  @override
  void notifyListeners() {
    super.notifyListeners();
    if (_restoring) return;
    final id = _selectedProjectId;
    if (id != null && _trees.containsKey(id)) _scheduleSave(id);
  }

  @override
  void dispose() {
    unawaited(_statusServer.stop());
    // O GitController é dono dos próprios timers/watchers; o módulo o
    // descarta junto com a rota. Aqui só desligamos o repasse de notify.
    git.removeListener(notifyListeners);
    realmCtrl.removeListener(notifyListeners);
    for (final t in _saveTimers.values) {
      t.cancel();
    }
    _saveTimers.clear();
    for (final w in _fileWatchers.values) {
      w.cancel();
    }
    _fileWatchers.clear();
    for (final t in _fileWatchDebounce.values) {
      t.cancel();
    }
    _fileWatchDebounce.clear();
    // Grava o output pendente das tasks antes de sair (o debounce de 1s do
    // `TaskTerminalStore` pode não ter disparado) → o restore reabre a aba.
    unawaited(_taskTerminals.flushAll());
    for (final s in _sessions.values) {
      s.dispose();
    }
    _sessions.clear();
    super.dispose();
  }
}

T _enumByName<T extends Enum>(List<T> values, Object? raw, T fallback) {
  if (raw is! String) return fallback;
  for (final v in values) {
    if (v.name == raw) return v;
  }
  return fallback;
}
