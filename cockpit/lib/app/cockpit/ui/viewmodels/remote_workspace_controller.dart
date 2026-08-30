import 'dart:async';

import 'package:cockpit/app/cockpit/data/remote/remote_git_adapter.dart';
import 'package:cockpit/app/cockpit/data/remote/remote_root_finder.dart';
import 'package:cockpit/app/cockpit/data/remote/remote_worktree_gateway.dart';
import 'package:cockpit/app/cockpit/domain/contracts/git_command_runner.dart';
import 'package:cockpit/app/cockpit/domain/contracts/worktree_manager.dart';
import 'package:cockpit/app/cockpit/domain/entities/git_file_status.dart';
import 'package:cockpit/app/cockpit/domain/entities/git_info.dart';
import 'package:cockpit/app/cockpit/domain/entities/project.dart';
import 'package:cockpit/app/cockpit/domain/entities/remote_host.dart';
import 'package:cockpit/app/cockpit/ui/remote/remote_hosts_controller.dart';
import 'package:cockpit/app/core/domain/result.dart';
import 'package:cockpit/app/core/utils/path_utils.dart';
import 'package:cockpit_core/cockpit_core.dart' show GitRunResult;
import 'package:cockpit_remote/cockpit_remote.dart' show RemoteGitService;
import 'package:flutter/foundation.dart';

/// Motor **remoto** do shell (plano 58), extraído do `CockpitViewModel`:
/// cache do `git status` por workspace de host, worktrees remotos e as ops de
/// git que rodam no host (`git.run` via SSH).
///
/// Segue o contrato do [GitController]: não conhece panes nem a lista de
/// projetos — o VM dono injeta os acessos que precisa pelos campos de callback
/// e é ele quem aplica a reconciliação de forks em `_projectList`/`_worktrees`.
class RemoteWorkspaceController extends ChangeNotifier {
  RemoteWorkspaceController(this._hosts);

  final RemoteHostsController _hosts;

  // ---- contexto injetado pelo VM dono (mesma vida page-scoped) -------------

  /// Projeto por id (inclui os workspaces remotos sintéticos), ou `null`.
  Project? Function(String? id)? resolveProject;

  /// Workspaces remotos top-level atualmente injetados no rail.
  List<Project> Function()? remoteWorkspaces;

  /// Workspace selecionado agora (guia o refresh do ativo).
  String? Function()? selectedId;

  /// Troca a seleção (após criar/remover um worktree remoto).
  void Function(String id)? selectProject;

  /// Root (pasta no host) que originou um fork remoto.
  String? Function(String forkId)? forkOrigin;

  /// Aplica a lista reconciliada de forks de [wsId] — o VM mexe em
  /// `_projectList`/`_worktrees`/`_forkOrigin` e encerra o runtime dos que
  /// sumiram (o controller não conhece sessões).
  ///
  /// [originOf] dá a root que originou **cada** fork: em multirepo os forks de
  /// um mesmo workspace vêm de repos diferentes, e a origem é o que decide
  /// contra quem o fork mergeia e de quem herda a branch.
  void Function(String wsId, List<Project> forks, Map<String, String> originOf)?
  applyForks;

  // ---- estado ---------------------------------------------------------------

  /// `git status` por workspace remoto **e por root**: `wsId → root → info`.
  /// O painel de Source Control lê os getters git do VM; quando o workspace é
  /// remoto, eles caem aqui.
  ///
  /// A chave é composta (e não só o path, como no [GitController] local)
  /// porque dois hosts diferentes têm caminhos iguais — `/home/jacob/app` no
  /// host A e no host B são repos distintos.
  final Map<String, Map<String, GitInfo>> _gitInfo =
      <String, Map<String, GitInfo>>{};

  /// Roots git de cada workspace remoto (multirepo por detecção implícita,
  /// igual ao local). Single-root = `[remotePath]`.
  final Map<String, List<String>> _roots = <String, List<String>>{};

  /// Workspaces cujo git está carregando agora (evita disparo duplicado do
  /// lazy-load do badge).
  final Set<String> _loading = <String>{};

  /// Descoberta de roots em voo, por workspace — dois caminhos pedem as roots
  /// do mesmo workspace na mesma janela e a varredura é cara.
  final Map<String, Future<List<String>?>> _rootsInFlight =
      <String, Future<List<String>?>>{};

  /// Workspaces com `refreshWorktrees` em voo (dedup).
  final Set<String> _refreshingWorktrees = <String>{};

  /// Token do último refresh de worktrees por workspace (anti-corrida).
  final Map<String, int> _worktreeToken = <String, int>{};

  Project? _project(String? id) => resolveProject?.call(id);

  /// O [RemoteHost] dono do workspace [workspaceId], ou `null` se local.
  RemoteHost? hostForWorkspace(String? workspaceId) {
    final project = _project(workspaceId);
    final hostId = project?.remoteHostId;
    if (project == null || !project.isRemoteTerminal || hostId == null) {
      return null;
    }
    for (final h in _hosts.hosts) {
      if (h.id == hostId) return h;
    }
    return null;
  }

  /// O [RemoteHost] do workspace ativo, ou `null` se o ativo é local.
  RemoteHost? get activeHost => hostForWorkspace(selectedId?.call());

  /// Roots git de um workspace remoto. Nunca vazio enquanto o workspace tem
  /// pasta: antes da descoberta terminar é `[remotePath]`, que é também a
  /// resposta certa para o caso single-root (monorepo).
  List<String> rootsOf(String wsId) {
    final derived = _roots[wsId];
    if (derived != null && derived.isNotEmpty) return derived;
    final path = _project(wsId)?.remotePath ?? '';
    return path.isEmpty ? const [] : [path];
  }

  /// `true` quando o workspace remoto é multirepo (pasta-mãe sem `.git` com
  /// 2+ repos filhos).
  bool isMultiRoot(String wsId) => rootsOf(wsId).length > 1;

  /// GitInfo de uma **root** específica de um workspace remoto.
  GitInfo? infoForRoot(String wsId, String rootPath) =>
      _gitInfo[wsId]?[rootPath];

  /// GitInfo remoto da pasta do workspace ativo (ou `null`).
  ///
  /// Em multirepo não existe "o" git do workspace — devolve `null`, como o
  /// [GitController] local faz, e quem precisa do estado usa [infoForRoot] ou
  /// [rootsSummary].
  GitInfo? get activeGitInfo {
    final id = selectedId?.call();
    return id == null ? null : gitInfoOf(id);
  }

  /// GitInfo remoto de um workspace (badge do rail). `null` enquanto o
  /// lazy-load não terminou, se a pasta não é repo git, ou se é multirepo.
  GitInfo? gitInfoOf(String wsId) {
    final roots = rootsOf(wsId);
    if (roots.length != 1) return null;
    return _gitInfo[wsId]?[roots.first];
  }

  /// Agregado do chip da rail em multirepo: (nº de roots, roots sujas). Conta
  /// só `isDirty`, como o local — divergência de upstream não acende o chip.
  (int roots, int dirtyRoots) rootsSummary(String wsId) {
    final roots = rootsOf(wsId);
    final byRoot = _gitInfo[wsId] ?? const <String, GitInfo>{};
    var dirty = 0;
    for (final r in roots) {
      if (byRoot[r]?.isDirty ?? false) dirty++;
    }
    return (roots.length, dirty);
  }

  /// `true` se alguma root do workspace remoto é repo git (habilita a aba
  /// Source Control).
  bool hasGit(String wsId) {
    final byRoot = _gitInfo[wsId];
    if (byRoot == null) return false;
    return rootsOf(wsId).any(byRoot.containsKey);
  }

  /// Root (path no host) que contém [absolutePath], ou `null` se o caminho
  /// está fora de todas (ex.: solto na pasta-mãe de um multirepo).
  String? rootContaining(String wsId, String absolutePath) {
    for (final r in rootsOf(wsId)) {
      if (absolutePath == r || isUnderPath(absolutePath, r)) return r;
    }
    return null;
  }

  /// Serviço git remoto do host ativo (para as mutações). Lança se não remoto.
  Future<RemoteGitService> activeGitService() =>
      _hosts.gitServiceFor(activeHost!);

  /// Status git (cor da árvore) de um caminho **absoluto no host**, relativo à
  /// pasta [rootPath] do workspace remoto ativo. Pasta agrega o status mais
  /// severo dos descendentes.
  GitFileStatus? statusForPath(String rootPath, String absolutePath) {
    final wsId = selectedId?.call();
    if (wsId == null) return null;
    // Em multirepo o caminho pertence a UMA root: o status e o caminho
    // relativo têm de ser calculados contra ela, não contra a pasta-mãe.
    // [rootPath] é a raiz da árvore que fez a pergunta e serve de fallback
    // (single-root, onde as duas coisas coincidem).
    final owner = rootContaining(wsId, absolutePath) ?? rootPath;
    final info = infoForRoot(wsId, owner);
    if (info == null) return null;
    if (absolutePath == owner) {
      return info.files.isEmpty ? null : GitFileStatus.modified;
    }
    final rel = relativeUnder(absolutePath, owner);
    final exact = info.files[rel];
    if (exact != null) return exact;
    GitFileStatus? agg;
    final prefix = '$rel/';
    for (final e in info.files.entries) {
      if (e.key.startsWith(prefix)) {
        agg = GitFileStatus.strongest(agg, e.value);
      }
    }
    if (agg != null) return agg;
    return info.isUntracked(rel) ? GitFileStatus.untracked : null;
  }

  /// Recarrega o `git status` remoto do workspace ativo (se remoto) e notifica.
  /// Chamado ao selecionar e após cada mutação.
  Future<void> refreshActive() async {
    final id = selectedId?.call();
    final p = _project(id);
    final host = activeHost;
    final path = p?.remotePath;
    if (p == null || host == null || path == null || path.isEmpty) return;
    await _readGit(p, host);
    notifyListeners();
  }

  /// Descobre as roots do workspace remoto e lê o `git status` de cada uma.
  /// Núcleo compartilhado por [refreshActive] e [_loadGitFor].
  Future<void> _readGit(Project p, RemoteHost host) async {
    final path = p.remotePath ?? '';
    if (path.isEmpty) return;
    // Fork (worktree remoto) é sempre um checkout único: não vale gastar
    // round-trips procurando repos filhos dentro dele.
    final roots = p.parentId != null
        ? [path]
        : await _rootsFor(p.id, path, host);
    final byRoot = <String, GitInfo>{};
    final service = await _hosts.gitServiceFor(host);
    for (final root in roots) {
      try {
        byRoot[root] = remoteGitInfo(await service.status(root));
      } on Object {
        // Root que não é repo git (ou conexão caiu) → fica de fora, sem
        // derrubar as irmãs.
      }
    }
    if (byRoot.isEmpty) {
      _gitInfo.remove(p.id);
    } else {
      _gitInfo[p.id] = byRoot;
    }
  }

  /// Roots do workspace, descobertas uma vez e cacheadas. A descoberta custa
  /// listagens SSH, e a topologia de um workspace praticamente não muda —
  /// quem quiser reavaliar chama [forgetRoots].
  Future<List<String>> _rootsFor(String wsId, String path, RemoteHost host) {
    final cached = _roots[wsId];
    if (cached != null && cached.isNotEmpty) return Future.value(cached);
    // Um mesmo workspace é descoberto por dois caminhos na mesma janela
    // (`_loadGitFor` e `refreshWorktrees`, ambos disparados por
    // [ensureLoaded]). Sem compartilhar o future em voo, a varredura — dezenas
    // de listagens SSH — rodaria duas vezes por boot.
    final running = _rootsInFlight[wsId];
    if (running != null) return running.then((r) => r ?? [path]);
    final future = _discoverRoots(path, host);
    _rootsInFlight[wsId] = future;
    unawaited(
      future
          .then((roots) {
            // Só cacheia descoberta de verdade: host offline devolve o
            // fallback single-root, que não pode virar topologia definitiva.
            if (roots != null && roots.isNotEmpty) _roots[wsId] = roots;
          })
          .catchError((_) {})
          .whenComplete(() {
            if (identical(_rootsInFlight[wsId], future)) {
              _rootsInFlight.remove(wsId);
            }
          }),
    );
    return future.then((r) => r ?? [path]);
  }

  /// `null` = a descoberta falhou (host offline) — o chamador segue
  /// single-root, mas nada é cacheado.
  Future<List<String>?> _discoverRoots(String path, RemoteHost host) async {
    try {
      final finder = RemoteRootFinder(await _hosts.fileServiceFor(host));
      final roots = await finder.deriveRoots(path);
      return roots.isEmpty ? null : roots;
    } on Object {
      return null; // host offline → segue single-root, sem cachear
    }
  }

  /// Esquece as roots descobertas de [wsId] (repo clonado/removido na pasta
  /// do workspace) — a próxima leitura redescobre.
  void forgetRoots(String wsId) {
    _roots.remove(wsId);
    _rootsInFlight.remove(wsId);
  }

  /// Injeta o resultado de uma descoberta + leitura, sem tocar a rede — é o
  /// que permite testar o roteamento por root (a parte onde um erro manda o
  /// comando para o repositório errado).
  @visibleForTesting
  void seedGit(String wsId, List<String> roots, Map<String, GitInfo> byRoot) {
    _roots[wsId] = roots;
    _gitInfo[wsId] = byRoot;
  }

  /// Carrega o `git status` de UM workspace remoto (background, best-effort) e
  /// cacheia — é o que preenche o badge dos slots que não são o ativo. Host
  /// offline apenas não mostra badge (sem travar).
  Future<void> _loadGitFor(Project p) async {
    if (!p.isRemoteTerminal || _loading.contains(p.id)) return;
    final host = hostForWorkspace(p.id);
    final root = p.remotePath;
    if (host == null || root == null || root.isEmpty) return;
    _loading.add(p.id);
    try {
      await _readGit(p, host);
    } catch (_) {
      _gitInfo.remove(p.id);
    } finally {
      _loading.remove(p.id);
      notifyListeners();
    }
  }

  /// Dispara o lazy-load do git de todos os workspaces remotos ainda sem info
  /// (badge) e lista os worktrees de cada um, na mesma janela.
  void ensureLoaded() {
    final workspaces = remoteWorkspaces?.call() ?? const <Project>[];
    for (final p in workspaces) {
      if (_gitInfo.containsKey(p.id) || _loading.contains(p.id)) continue;
      unawaited(_loadGitFor(p));
    }
    for (final p in workspaces) {
      unawaited(refreshWorktrees(p.id));
    }
  }

  /// Soma de arquivos sujos de todas as roots de [wsId].
  int _dirtyCountOf(String wsId) {
    final byRoot = _gitInfo[wsId] ?? const <String, GitInfo>{};
    var total = 0;
    for (final root in rootsOf(wsId)) {
      total += byRoot[root]?.dirtyCount ?? 0;
    }
    return total;
  }

  /// Descarta o cache de um workspace que saiu do rail.
  void forget(String wsId) {
    _gitInfo.remove(wsId);
    _roots.remove(wsId);
    _loading.remove(wsId);
    _worktreeToken.remove(wsId);
    _rootsInFlight.remove(wsId);
    _refreshingWorktrees.remove(wsId);
  }

  Future<GitRunResult> run(String wsId, List<String> args) async {
    final host = hostForWorkspace(wsId);
    if (host == null) {
      throw StateError('remoteGitRun em workspace não-remoto: $wsId');
    }
    final root = _project(wsId)?.remotePath ?? '';
    final service = await _hosts.gitServiceFor(host);
    return service.run(root, args);
  }

  // === Worktrees remotos (plano 58, Camada B) ==============================
  // Um worktree remoto é só mais um workspace remoto (isRemoteTerminal +
  // remoteHostId + remotePath) com parentId apontando pro workspace de origem,
  // derivado do `git worktree list` do host. Ops via `git.run` (sem RPC novo).

  Future<RemoteWorktreeGateway?> _gatewayFor(String wsId) async {
    final host = hostForWorkspace(wsId);
    if (host == null) return null;
    return RemoteWorktreeGateway(
      await _hosts.gitServiceFor(host),
      await _hosts.fileServiceFor(host),
    );
  }

  /// Lista e reconcilia os worktrees remotos de [wsId] (slots-fork do rail).
  /// Best-effort: host offline / pasta não-git → sem forks.
  Future<void> refreshWorktrees(String wsId) async {
    // Dedup de refresh em voo: [ensureLoaded] é chamado a CADA transição de
    // fase da conexão (e o reconnect faz backoff indefinido), então sem isto
    // uma rede instável empilha um `git worktree list` por root a cada ciclo,
    // todos na mesma conexão SSH. No mobile, onde o transporte roda no isolate
    // da UI, era rajada suficiente para congelar o app.
    if (_refreshingWorktrees.contains(wsId)) return;
    _refreshingWorktrees.add(wsId);
    try {
      await _refreshWorktrees(wsId);
    } finally {
      _refreshingWorktrees.remove(wsId);
    }
  }

  Future<void> _refreshWorktrees(String wsId) async {
    final parent = _project(wsId);
    final path = parent?.remotePath;
    if (parent == null ||
        !parent.isRemoteTerminal ||
        parent.parentId != null ||
        path == null ||
        path.isEmpty) {
      return;
    }
    final host = hostForWorkspace(wsId);
    if (host == null) return;
    final gw = await _gatewayFor(wsId);
    if (gw == null) return;
    // Token anti-corrida: a listagem SSH leva ~s. Um refresh disparado no boot
    // (lista vazia, antes do worktree existir) pode voltar DEPOIS do create e
    // sobrescrever, apagando o fork recém-criado. Só o resultado do refresh
    // mais recente por workspace é aplicado.
    final token = (_worktreeToken[wsId] ?? 0) + 1;
    _worktreeToken[wsId] = token;
    // Multirepo: `git worktree list` roda em CADA root — a pasta-mãe não é
    // repo nenhum, e era por isso que um workspace remoto multirepo aparecia
    // sem fork algum.
    final roots = await _rootsFor(wsId, path, host);
    final forks = <Project>[];
    final originOf = <String, String>{};
    for (final root in roots) {
      final List<RemoteWorktreeEntry> entries;
      try {
        entries = await gw.list(root);
      } catch (_) {
        // `gw.list` LANÇA em falha justamente para não confundir "sem
        // worktrees" com "não consegui listar" — se seguíssemos em frente, um
        // soluço de SSH viraria lista vazia, e [applyForks] apagaria os forks
        // existentes (jogando a seleção de volta no workspace pai). Aborta o
        // refresh inteiro e tenta de novo no próximo.
        return;
      }
      if (_worktreeToken[wsId] != token) return; // obsoleto → descarta
      for (final e in entries) {
        final id = '$wsId::${e.path}';
        originOf[id] = root;
        forks.add(
          Project(
            id: id,
            name: e.branch,
            path: '',
            colorValue: parent.colorValue,
            createdAt: parent.createdAt,
            realmId: parent.realmId,
            parentId: wsId,
            order: parent.order,
            kind: WorkspaceKind.remoteTerminal,
            remoteHostId: parent.remoteHostId,
            remotePath: e.path,
          ),
        );
      }
    }
    if (_worktreeToken[wsId] != token) return;
    applyForks?.call(wsId, forks, originOf);
    for (final f in forks) {
      if (!_gitInfo.containsKey(f.id) && !_loading.contains(f.id)) {
        unawaited(_loadGitFor(f));
      }
    }
    notifyListeners();
  }

  /// Namespace (branches/worktrees/base) do host — valida o dialog de criar.
  /// [root] escolhe o repo em multirepo; omitido = a pasta do pin.
  Future<WorktreeNamespace> worktreeNamespace(
    String wsId, {
    String? root,
  }) async {
    root = (root == null || root.isEmpty) ? _project(wsId)?.remotePath : root;
    if (root == null || root.isEmpty) return const WorktreeNamespace.empty();
    final gw = await _gatewayFor(wsId);
    if (gw == null) return const WorktreeNamespace.empty();
    try {
      return await gw.namespace(root);
    } catch (_) {
      return const WorktreeNamespace.empty();
    }
  }

  /// Cria um worktree no host de [wsId] (branch nova [name], de [baseRef] no
  /// fork-of-fork). Devolve o handle ao vivo (a saída do `git.run` sai de uma
  /// vez); em sucesso, reconcilia, auto-seleciona o fork e o devolve.
  WorktreeAddRun<Project> createWorktree(
    String wsId,
    String name, {
    String? baseRef,
    String? root,
  }) {
    final controller = StreamController<String>();
    final result = () async {
      try {
        // Root explícita (multirepo: o repo escolhido no kebab) ou a pasta do
        // pin. Variável local — reatribuir o parâmetro dentro do closure
        // impede a promoção de tipo.
        final target = (root == null || root.isEmpty)
            ? (_project(wsId)?.remotePath ?? '')
            : root;
        if (target.isEmpty) {
          return const Failure<Project, WorktreeOpError>(
            WorktreeOpError('Workspace not found.'),
          );
        }
        final gw = await _gatewayFor(wsId);
        if (gw == null) {
          return const Failure<Project, WorktreeOpError>(
            WorktreeOpError('Host unavailable.'),
          );
        }
        final r = await gw.add(target, name, baseRef: baseRef);
        if (r.stdout.isNotEmpty) controller.add(r.stdout);
        if (r.stderr.isNotEmpty) controller.add(r.stderr);
        if (r.code != 0) {
          return Failure<Project, WorktreeOpError>(
            WorktreeOpError(
              r.stderr.isEmpty ? 'git worktree add failed.' : r.stderr,
            ),
          );
        }
        await refreshWorktrees(wsId);
        final fork = _project(
          '$wsId::${RemoteWorktreeGateway.pathFor(target, name)}',
        );
        if (fork == null) {
          return const Failure<Project, WorktreeOpError>(
            WorktreeOpError('Worktree created, but did not appear.'),
          );
        }
        selectProject?.call(fork.id);
        return Success<Project, WorktreeOpError>(fork);
      } catch (e) {
        controller.add('$e');
        return Failure<Project, WorktreeOpError>(WorktreeOpError('$e'));
      } finally {
        await controller.close();
      }
    }();
    return WorktreeAddRun<Project>(output: controller.stream, result: result);
  }

  /// Remove um worktree remoto (`git worktree remove` + `git branch -D` no
  /// host) e reconcilia; se era o selecionado, volta pro pai.
  Future<Result<void, WorktreeOpError>> removeWorktree(String forkId) async {
    final fork = _project(forkId);
    final parentId = fork?.parentId;
    final origin = forkOrigin?.call(forkId);
    final path = fork?.remotePath;
    if (fork == null || parentId == null || origin == null || path == null) {
      return const Failure(WorktreeOpError('Worktree not found.'));
    }
    final gw = await _gatewayFor(parentId);
    if (gw == null) return const Failure(WorktreeOpError('Host unavailable.'));
    final r = await gw.remove(origin, path, fork.name);
    if (r.code != 0) {
      return Failure(
        WorktreeOpError(
          r.stderr.isEmpty ? 'git worktree remove failed.' : r.stderr,
        ),
      );
    }
    if (selectedId?.call() == forkId) selectProject?.call(parentId);
    await refreshWorktrees(parentId);
    return const Success(null);
  }

  /// `true` se a branch do fork remoto já foi mergeada — aviso antes de remover.
  Future<bool> isWorktreeBranchMerged(String forkId) async {
    final fork = _project(forkId);
    final parentId = fork?.parentId;
    final origin = forkOrigin?.call(forkId);
    if (fork == null || parentId == null || origin == null) return false;
    final gw = await _gatewayFor(parentId);
    if (gw == null) return false;
    try {
      return await gw.isMerged(origin, fork.name);
    } catch (_) {
      return false;
    }
  }

  /// Mergeia a branch do fork remoto no pai (no host). Em sucesso, remove o
  /// worktree e volta pro pai. Bloqueia se o pai tem mudanças não commitadas.
  GitMergeOutcome mergeWorktreeToParent(Project fork) {
    final controller = StreamController<String>();
    final status = () async {
      final parentId = fork.parentId;
      final origin = parentId == null ? null : forkOrigin?.call(fork.id);
      if (parentId == null || origin == null) {
        controller.add('Not a worktree.');
        await controller.close();
        return GitMergeStatus.error;
      }
      // Fork tem uma root só (o checkout do worktree); o pai pode ser
      // multirepo, e aí "sujo" é qualquer root suja.
      if (_dirtyCountOf(parentId) > 0) {
        controller.add('Parent has uncommitted changes.');
        await controller.close();
        return GitMergeStatus.dirtyWorktree;
      }
      final gw = await _gatewayFor(parentId);
      if (gw == null) {
        controller.add('Host unavailable.');
        await controller.close();
        return GitMergeStatus.error;
      }
      final r = await gw.merge(origin, fork.name);
      if (r.stdout.isNotEmpty) controller.add(r.stdout);
      if (r.stderr.isNotEmpty) controller.add(r.stderr);
      await controller.close();
      if (r.code != 0) return GitMergeStatus.conflict;
      await removeWorktree(fork.id);
      selectProject?.call(parentId);
      unawaited(refreshActive());
      return GitMergeStatus.merged;
    }();
    return GitMergeOutcome(status: status, output: controller.stream);
  }

  /// "Update from parent" remoto: mergeia a branch do pai no checkout do fork
  /// (no host). Conflito fica no fork (exit ≠ 0), o pai nunca é tocado.
  GitRun updateWorktreeFromParent(Project fork) {
    final controller = StreamController<String>();
    final exit = () async {
      final parentId = fork.parentId;
      // A branch do pai vem da root que **originou** o fork (em multirepo o
      // pai não tem uma branch só).
      final parentOrigin = parentId == null ? null : forkOrigin?.call(fork.id);
      final parentBranch = parentId == null
          ? null
          : (parentOrigin == null
                ? gitInfoOf(parentId)?.branch
                : infoForRoot(parentId, parentOrigin)?.branch);
      final root = fork.remotePath;
      final host = parentId == null ? null : hostForWorkspace(parentId);
      if (parentBranch == null ||
          parentBranch.isEmpty ||
          root == null ||
          host == null) {
        controller.add('Parent branch not found.');
        await controller.close();
        return 1;
      }
      try {
        final git = await _hosts.gitServiceFor(host);
        final r = await git.run(root, ['merge', '--no-edit', parentBranch]);
        if (r.stdout.isNotEmpty) controller.add(r.stdout);
        if (r.stderr.isNotEmpty) controller.add(r.stderr);
        await controller.close();
        if (r.code == 0) unawaited(refreshActive());
        return r.code;
      } catch (e) {
        controller.add('$e');
        await controller.close();
        return 1;
      }
    }();
    return GitRun(output: controller.stream, exitCode: exit);
  }
}
