import 'dart:async';
import 'dart:convert';
import 'dart:math' show max;

import 'package:cockpit/domain/contracts/app_launcher.dart';
import 'package:cockpit/domain/contracts/file_reader.dart';
import 'package:cockpit/domain/contracts/file_searcher.dart';
import 'package:cockpit/domain/contracts/file_system_reader.dart';
import 'package:cockpit/domain/contracts/folder_lister.dart';
import 'package:cockpit/domain/contracts/git_status_reader.dart';
import 'package:cockpit/domain/contracts/notifier.dart';
import 'package:cockpit/domain/contracts/project_repository.dart';
import 'package:cockpit/domain/contracts/rpc_gateway_factory.dart';
import 'package:cockpit/domain/contracts/session_history.dart';
import 'package:cockpit/domain/contracts/terminal_gateway_factory.dart';
import 'package:cockpit/domain/contracts/workspace_layout_store.dart';
import 'package:cockpit/domain/entities/file_node.dart';
import 'package:cockpit/domain/entities/file_view.dart';
import 'package:cockpit/domain/entities/git_info.dart';
import 'package:cockpit/domain/entities/launchable_app.dart';
import 'package:cockpit/domain/entities/project.dart';
import 'package:cockpit/domain/entities/session_info.dart';
import 'package:cockpit/domain/entities/thinking_level.dart';
import 'package:cockpit/ui/cockpit/session/agent_session.dart';
import 'package:cockpit/ui/cockpit/session/file_viewer_session.dart';
import 'package:cockpit/ui/cockpit/session/pane_item.dart';
import 'package:cockpit/ui/cockpit/session/terminal_session.dart';
import 'package:cockpit/ui/cockpit/states/pane_node.dart';
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
    this._fileReader,
    this._layoutStore,
    this._gitReader,
    this._fileSearcher,
    this._launcher,
  );

  final ProjectRepository _projects;
  final RpcGatewayFactory _factory;
  final FolderLister _folders;
  final SessionHistory _history;
  final Notifier _notifier;
  final FileSystemReader _fileSystem;
  final TerminalGatewayFactory _terminalFactory;
  final FileReader _fileReader;
  final WorkspaceLayoutStore _layoutStore;
  final GitStatusReader _gitReader;
  final FileSearcher _fileSearcher;
  final AppLauncherGateway _launcher;

  List<LaunchableApp> _availableApps = const [];

  final List<Project> _projectList = <Project>[];
  String? _selectedProjectId;
  final Map<String, PaneItem> _sessions = <String, PaneItem>{};

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

  /// Estado git por projeto (branch + sujos). `null` (ausente do mapa ou valor
  /// null) = não é repo git → a rail mostra só o título.
  final Map<String, GitInfo?> _gitInfo = <String, GitInfo?>{};

  bool _railVisible = true;
  bool _treeVisible = true;
  bool _ready = false;
  int _seq = 0;

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
  String? get selectedProjectId => _selectedProjectId;
  Project? get selectedProject => _projectById(_selectedProjectId);

  /// `false` até [init] terminar de carregar os projetos do Hive.
  bool get ready => _ready;
  bool get railVisible => _railVisible;
  bool get treeVisible => _treeVisible;
  List<LaunchableApp> get availableApps =>
      List<LaunchableApp>.unmodifiable(_availableApps);
  PaneItem? session(String id) => _sessions[id];

  /// Estado git do projeto (branch + sujos), ou `null` se não for repo git.
  GitInfo? gitInfo(String projectId) => _gitInfo[projectId];

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
  /// pane). Binário/vídeo/grande demais → não abre. Reusa a aba se já aberta.
  Future<void> openFile(String path, {String? inPane}) async {
    final projectId = _selectedProjectId;
    final tree = _activeTree;
    final paneId = inPane ?? (projectId == null ? null : _focused[projectId]);
    if (projectId == null || tree == null || paneId == null) return;
    final leaf = findLeaf(tree, paneId);
    if (leaf == null) return;
    // Soltar um arquivo numa pane específica também a foca.
    if (inPane != null) _focused[projectId] = inPane;

    // Já aberto na pane? só seleciona.
    for (final tabId in leaf.tabs) {
      final s = _sessions[tabId];
      if (s is FileViewerSession && s.path == path) {
        _trees[projectId] = updateLeaf(
          tree,
          paneId,
          (p) => p.copyWith(active: tabId),
        );
        notifyListeners();
        return;
      }
    }

    final view = await _fileReader.read(path);
    if (view is FileViewUnsupported) return; // binário/vídeo: não abre

    final viewer = FileViewerSession(
      id: _nid('v'),
      projectId: projectId,
      path: path,
      view: view,
    );
    _sessions[viewer.id] = viewer;

    // Se a pane só tem o placeholder vazio, substitui; senão adiciona aba.
    final current = _trees[projectId] ?? tree;
    final lf = findLeaf(current, paneId);
    final only = lf?.tabs.length == 1 ? _sessions[lf!.tabs.first] : null;
    if (only is AgentSession && only.status == AgentStatus.empty) {
      final emptyId = lf!.tabs.first;
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
    _projectList.addAll(await _projects.all());
    // Carrega os layouts salvos (mas não reconstrói nada ainda — lazy).
    for (final project in _projectList) {
      _savedLayouts[project.id] = await _layoutStore.load(project.id);
    }
    _selectedProjectId = _projectList.isEmpty ? null : _projectList.first.id;
    // Só o projeto selecionado é ativado (sobe os processos) no boot.
    final selected = _selectedProjectId;
    if (selected != null) await _activateProject(selected);
    _ready = true;
    notifyListeners();
    // Estado git de todos os projetos (assíncrono — a rail atualiza conforme chega).
    for (final project in _projectList) {
      unawaited(_refreshGit(project.id));
    }
    // Detecta IDEs instaladas (assíncrono — topbar atualiza ao chegar).
    unawaited(_launcher.probe().then((apps) {
      _availableApps = apps;
      notifyListeners();
    }));
  }

  /// Abre a pasta do projeto selecionado no [app] informado.
  Future<void> openProjectInApp(LaunchableApp app) async {
    final project = selectedProject;
    if (project == null) return;
    await _launcher.launch(app, project.path);
  }

  // ---- projects -------------------------------------------------------------
  /// Cria (ou seleciona, se já existir) um workspace pra [path]. [name] e
  /// [colorValue] permitem sobrescrever os defaults (fluxo "Criar Workspace",
  /// onde o usuário edita nome/cor antes de confirmar).
  Future<Project> addProject(String path, {String? name, int? colorValue}) async {
    for (final existing in _projectList) {
      if (existing.path == path) {
        _selectedProjectId = existing.id;
        notifyListeners();
        return existing;
      }
    }
    final basename = _basename(path);
    final resolvedName = (name != null && name.trim().isNotEmpty)
        ? name.trim()
        : (basename.isEmpty ? path : basename);
    final project = Project(
      id: path, // o caminho é único e estável entre reinícios
      name: resolvedName,
      path: path,
      colorValue:
          colorValue ?? _palette[_projectList.length % _palette.length],
      createdAt: DateTime.now(),
    );
    _projectList.add(project);
    _selectedProjectId = project.id;
    await _projects.save(project);
    await _activateProject(project.id); // sem layout salvo → pane vazia
    unawaited(_refreshGit(project.id));
    notifyListeners();
    return project;
  }

  /// Altera nome e/ou cor do projeto e persiste.
  Future<void> updateProject(String id, {String? name, int? colorValue}) async {
    final index = _projectList.indexWhere((p) => p.id == id);
    if (index < 0) return;
    final updated = _projectList[index].copyWith(
      name: name,
      colorValue: colorValue,
    );
    _projectList[index] = updated;
    await _projects.save(updated);
    notifyListeners();
  }

  Future<void> removeProject(String id) async {
    final tree = _trees.remove(id);
    if (tree != null) {
      for (final leaf in leaves(tree)) {
        for (final agentId in leaf.tabs) {
          _disposeSession(agentId);
        }
      }
    }
    _focused.remove(id);
    _savedLayouts.remove(id);
    _gitInfo.remove(id);
    _saveTimers.remove(id)?.cancel();
    _projectList.removeWhere((p) => p.id == id);
    if (_selectedProjectId == id) {
      _selectedProjectId = _projectList.isEmpty ? null : _projectList.first.id;
    }
    await _projects.remove(id);
    await _layoutStore.remove(id);
    final next = _selectedProjectId;
    if (next != null) await _activateProject(next);
    notifyListeners();
  }

  void selectProject(String id) {
    if (_selectedProjectId == id) return;
    _selectedProjectId = id;
    _clearFocusedNotification();
    unawaited(_activateProject(id)); // reconstrói (lazy) se ainda não ativo
    unawaited(_refreshGit(id)); // pode ter mudado desde a última vez
    notifyListeners();
  }

  /// Subpastas do projeto selecionado, para o seletor de "onde o agente atua".
  Future<List<String>> subfolders() async {
    final project = selectedProject;
    if (project == null) return const <String>[];
    return _folders.subfolders(project.path);
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
    notifyListeners();

    if (!s.isAlive) return;

    final project = _projectById(s.projectId);
    if (project == null) return;

    final sessionPath = s.sessionPath;
    await s.killForRestart();
    unawaited(_bootAgent(s, s.workingDirectory, project, sessionPath));
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
    notifyListeners();
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
        (p) => p.copyWith(tabs: remaining, active: _activeAfter(src, tabId, remaining)),
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
        (p) => p.copyWith(tabs: remaining, active: _activeAfter(src, tabId, remaining)),
      );
    }
    // 2. Divide o alvo, inserindo o novo pane.
    t = splitLeaf(t, targetPaneId, dir, newLeaf, splitId: _nid('sp'), before: before);
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
        updateLeaf(tree, srcPaneId, (p) => p.copyWith(tabs: tabs, active: tabId)),
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
        (p) => p.copyWith(tabs: remaining, active: _activeAfter(src, tabId, remaining)),
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

  void toggleRail() {
    _railVisible = !_railVisible;
    notifyListeners();
  }

  void toggleTree() {
    _treeVisible = !_treeVisible;
    notifyListeners();
  }

  // ---- helpers --------------------------------------------------------------
  Project? _projectById(String? id) {
    for (final project in _projectList) {
      if (project.id == id) return project;
    }
    return null;
  }

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

  PaneItem _spawn(String subRelative, {required bool terminal}) {
    final project = selectedProject!;
    final cwd = subRelative.isEmpty
        ? project.path
        : '${project.path}/$subRelative';
    final title = subRelative.isEmpty ? project.name : _basename(subRelative);
    return terminal
        ? _buildTerminal(_nid('t'), project.id, cwd, title: title)
        : _buildAgent(_nid('a'), project, cwd, title: title);
  }

  TerminalSession _buildTerminal(
    String id,
    String projectId,
    String cwd, {
    String? title,
  }) {
    final t = TerminalSession(
      id: id,
      projectId: projectId,
      workingDirectory: cwd,
      gateway: _terminalFactory.create(),
      title: title,
    );
    _sessions[t.id] = t;
    return t;
  }

  /// Cria e boota um agente. [restoreSessionPath] (restauração) faz reanexar a
  /// conversa salva via `switch_session`; senão, a VM captura o arquivo de
  /// sessão que o pi criar (no 1º fim de turno) pra poder restaurar depois.
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
    final s = AgentSession(
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
    s.sessionBaseline = (await _history.sessionsFor(cwd))
        .map((e) => e.path)
        .toSet();
    await s.boot(environment: _buildDirectConfig(s, project));
    if (restoreSessionPath != null) {
      s.sessionPath = restoreSessionPath;
      await s.loadHistory(restoreSessionPath);
    }
  }

  /// Serializa `agent_name`, `auto_start_relay` e `workspace` em
  /// `REMOTE_PI_DIRECT_CONFIG` para o processo filho.
  Map<String, String> _buildDirectConfig(AgentSession s, Project project) {
    return {
      'REMOTE_PI_DIRECT_CONFIG': jsonEncode(<String, dynamic>{
        'agent_name': s.title,
        'auto_start_relay': s.autoStartRelay,
        'workspace': project.name,
      }),
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

  void _onAgentTurnEnd(AgentSession s) {
    if (s.sessionPath == null) unawaited(_captureSessionPath(s));
    unawaited(_refreshGit(s.projectId));
    unawaited(_notifyIfNeeded(s));
  }

  /// Notifica e marca "unseen" apenas se o usuário não está ativamente vendo
  /// este agente — ou seja: aba diferente da focada **ou** janela sem foco
  /// no SO (usuário em outra app/espaço).
  Future<void> _notifyIfNeeded(AgentSession s) async {
    final isActiveTab = s.id == _focusedAgentId;
    final windowFocused = await windowManager.isFocused();
    if (isActiveTab && windowFocused) return;

    s.markUnseen();
    final workspace = _projectById(s.projectId)?.name ?? '';
    await _notifier.agentFinished(agentName: s.title, workspace: workspace);
    notifyListeners(); // atualiza o badge na rail
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
      title: 'Novo',
    );
    _sessions[s.id] = s;
    return s;
  }

  void _disposeSession(String id) {
    final s = _sessions.remove(id);
    s?.dispose();
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
    tree = _sanitizeTree(tree, created, id); // descarta abas que não restauraram
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
        _buildTerminal(
          id,
          project.id,
          cwdOf(),
          title: desc['title'] as String?,
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
      case 'empty':
        _makeEmptyWithId(id, project.id);
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

  Map<String, dynamic> _sessionToJson(PaneItem s, Project project) {
    if (s is TerminalSession) {
      return <String, dynamic>{
        'type': 'terminal',
        'sub': _subOf(s.workingDirectory, project.path),
        'title': s.title,
      };
    }
    if (s is FileViewerSession) {
      return <String, dynamic>{'type': 'viewer', 'path': s.path};
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

  /// Caminho de [cwd] relativo à raiz [root] do projeto ('' = raiz).
  String _subOf(String cwd, String root) {
    if (cwd == root) return '';
    final prefix = root.endsWith('/') ? root : '$root/';
    return cwd.startsWith(prefix) ? cwd.substring(prefix.length) : '';
  }

  void _scheduleSave(String projectId) {
    _saveTimers[projectId]?.cancel();
    _saveTimers[projectId] = Timer(const Duration(milliseconds: 500), () {
      _saveTimers.remove(projectId);
      final doc = _serializeLayout(projectId);
      if (doc.isNotEmpty) unawaited(_layoutStore.save(projectId, doc));
    });
  }

  /// (Re)lê o estado git de um projeto e atualiza a rail. Chamado no boot (todos),
  /// ao selecionar e no fim de turno do agente (que pode ter mexido em arquivos).
  Future<void> _refreshGit(String projectId) async {
    final project = _projectById(projectId);
    if (project == null) return;
    final info = await _gitReader.read(project.path);
    // Evita rebuild se nada mudou (branch + sujos iguais).
    final old = _gitInfo[projectId];
    if (old?.branch == info?.branch && old?.dirtyCount == info?.dirtyCount) {
      _gitInfo[projectId] = info; // garante a chave mesmo sem mudança visível
      return;
    }
    _gitInfo[projectId] = info;
    notifyListeners();
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
    for (final t in _saveTimers.values) {
      t.cancel();
    }
    _saveTimers.clear();
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
