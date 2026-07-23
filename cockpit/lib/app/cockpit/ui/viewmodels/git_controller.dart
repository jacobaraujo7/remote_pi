import 'dart:async';
import 'dart:io'
    show
        Directory,
        File,
        FileSystemEntity,
        FileSystemEntityType,
        FileSystemEvent,
        Platform;

import 'package:cockpit/app/cockpit/domain/contracts/git_command_runner.dart';
import 'package:cockpit/app/cockpit/domain/contracts/git_status_reader.dart';
import 'package:cockpit/app/cockpit/domain/entities/git_file_status.dart';
import 'package:cockpit/app/cockpit/domain/entities/git_info.dart';
import 'package:flutter/foundation.dart';

typedef DirectoryWatch = Stream<FileSystemEvent> Function(String path);

/// Estado git do shell, extraído do `CockpitViewModel` (refactor 2026-07-19):
/// info/árvore por **root path**, roots derivadas por projeto, watcher de
/// filesystem do projeto selecionado, poll de segurança e comandos git.
///
/// Não conhece `Project` nem panes — o VM dono injeta o contexto que precisa
/// (path/gates/alvos de poll) pelos campos de callback abaixo, logo após a
/// construção. Worktrees e diff viewer seguem no VM (mexem em projeto/pane).
class GitController extends ChangeNotifier {
  GitController(
    this._reader,
    this._runner, {
    DirectoryWatch? directoryWatch,
    Duration watchRetryDelay = const Duration(milliseconds: 500),
  }) : _directoryWatch = directoryWatch ?? _defaultDirectoryWatch,
       _watchRetryDelay = watchRetryDelay;

  final GitStatusReader _reader;
  final GitCommandRunner _runner;
  final DirectoryWatch _directoryWatch;
  final Duration _watchRetryDelay;

  static Stream<FileSystemEvent> _defaultDirectoryWatch(String path) =>
      Directory(path).watch(recursive: true);

  // ---- contexto injetado pelo VM dono (mesma vida page-scoped) -------------

  /// Path do projeto, ou `null` se o projeto não existe.
  String? Function(String projectId)? resolvePath;

  /// `true` se o projeto é o workspace de sistema "Cockpit" (sem pasta).
  bool Function(String projectId)? isSystemTerminal;

  /// Projeto atualmente selecionado (guia watcher/poll).
  String? Function()? selectedProjectId;

  /// Ids a re-ler no poll (família visível: raiz do selecionado + forks).
  List<String> Function()? pollTargets;

  /// Evento **estrutural** (create/delete/move) fora do `.git/` no working
  /// tree observado — o VM bumpa a revisão da árvore de arquivos.
  VoidCallback? onStructuralFsChange;

  /// Disparado uma vez por tick do poll — o VM dono reconcilia as worktrees
  /// (que o GitController não conhece) contra o git. Só notifica se a lista mudou.
  VoidCallback? onPoll;

  // ---- estado ---------------------------------------------------------------

  /// Estado git por **root path** (branch + sujos). Para workspace single-root
  /// a chave coincide com o `Project.id` (id == path), então o comportamento é
  /// o histórico. Num multi-root há uma entrada por root; a pasta-mãe não tem
  /// entrada própria. `null` = a root não é repo git.
  final Map<String, GitInfo?> _gitInfo = <String, GitInfo?>{};

  /// Status git por **caminho relativo à root** (arquivos + pastas agregadas),
  /// por root path. Derivado de [_gitInfo]; alimenta a coloração da árvore de
  /// arquivos. Pasta agrega o estado mais forte dos descendentes
  /// ([GitFileStatus.strongest]).
  final Map<String, Map<String, GitFileStatus>> _gitTree =
      <String, Map<String, GitFileStatus>>{};

  /// Roots git derivadas por projeto (**runtime, nunca persistido** — a
  /// existência mora no filesystem, mesmo espírito das worktrees/plano 42).
  /// Regra implícita: raiz com `.git` → `[path]` (single-root, caso histórico);
  /// raiz sem `.git` → filhas imediatas com `.git` (multi-root/multirepo);
  /// nenhuma → `[path]` (pasta comum). Reavaliado a cada [refresh].
  final Map<String, List<String>> _rootsByProject = <String, List<String>>{};

  /// Watcher do working tree do projeto **selecionado** (filesystem ao vivo).
  /// Recriado ao trocar de projeto; debounce junta rajadas de eventos.
  StreamSubscription<FileSystemEvent>? _gitWatch;
  Timer? _gitWatchDebounce;
  Timer? _gitWatchRetry;
  String? _gitWatchPath;

  /// Debounce próprio da árvore de arquivos: eventos **estruturais**
  /// (create/delete/move) fora do `.git/` disparam [onStructuralFsChange] pra
  /// árvore reler as pastas abertas — cobre arquivos criados/removidos por
  /// fora (Finder, agente, scripts) sem exigir Refresh manual. Separado do
  /// [_gitWatchDebounce] pra um modify (que não muda a árvore) não segurar
  /// o bump nem vice-versa.
  Timer? _fileTreeWatchDebounce;

  /// Poll de segurança do git. O `_gitWatch` só cobre o projeto **selecionado**
  /// e o `Directory.watch(recursive:)` do macOS coalesce/perde eventos (e forks
  /// de worktree, cujo `index`/`HEAD` moram fora do working tree, nem sempre
  /// disparam evento). Sem isso a rail fica desatualizada até o usuário trocar
  /// de workspace e voltar. Relê o git dos [pollTargets] periodicamente;
  /// [refresh] só notifica quando algo mudou, então o custo em UI é nulo em
  /// repos parados.
  Timer? _gitPoll;
  static const Duration _gitPollInterval = Duration(seconds: 3);

  // ---- leitura --------------------------------------------------------------

  /// Roots git do projeto. Sempre não-vazio: single-root = `[path]`
  /// (comportamento histórico, N=1); multi-root = as filhas-repo derivadas.
  List<String> rootsOf(String projectId) {
    final derived = _rootsByProject[projectId];
    if (derived != null && derived.isNotEmpty) return derived;
    final p = resolvePath?.call(projectId);
    return p == null || p.isEmpty ? const [] : [p];
  }

  /// Estado git de uma **root** específica ([rootPath] absoluto).
  GitInfo? infoForRoot(String rootPath) => _gitInfo[rootPath];

  /// Estado git do projeto (branch + sujos), ou `null` se não for repo git.
  /// Em multi-root não existe "o" GitInfo do workspace — devolve `null` (a
  /// rail usa [rootsSummary] pro chip agregado).
  GitInfo? infoOf(String projectId) {
    final roots = rootsOf(projectId);
    if (roots.length != 1) return null;
    return _gitInfo[roots.first];
  }

  /// Agregado pro chip da rail em multi-root: (nº de roots, roots com
  /// **alteração de arquivo**). Conta só `isDirty` — divergência de upstream
  /// (ahead/behind) NÃO entra, senão o chip acende "· 1" numa root só com
  /// commits não enviados/não puxados, sem nenhuma mudança de arquivo.
  (int roots, int dirtyRoots) rootsSummary(String projectId) {
    final roots = rootsOf(projectId);
    var dirty = 0;
    for (final r in roots) {
      final info = _gitInfo[r];
      if (info != null && info.isDirty) dirty++;
    }
    return (roots.length, dirty);
  }

  /// `true` se o workspace [projectId] tem git — single-root: a raiz é repo;
  /// multi-root: qualquer root (habilita a aba Source Control).
  bool isGitRepo(String projectId) =>
      rootsOf(projectId).any((r) => _gitInfo[r] != null);

  /// Status git (relativo à **root**) dos arquivos com mudança de uma root.
  Map<String, GitFileStatus> changedFilesOfRoot(String rootPath) {
    final info = _gitInfo[rootPath];
    if (info == null) return const {};
    return info.files;
  }

  /// Estado agregado de uma **root inteira** — o mais forte entre os arquivos
  /// sujos dela (mesma regra de pasta, [GitFileStatus.strongest]). Colore a
  /// própria pasta da root na árvore de arquivos em multi-root, onde o `.git`
  /// mora dentro da pasta e o caminho relativo dela seria vazio. `null` =
  /// limpa ou sem git.
  GitFileStatus? statusForRoot(String rootPath) {
    final info = _gitInfo[rootPath];
    if (info == null) return null;
    GitFileStatus? out;
    for (final s in info.files.values) {
      out = GitFileStatus.strongest(out, s);
    }
    return out ??
        (info.untrackedDirs.isNotEmpty ? GitFileStatus.untracked : null);
  }

  /// Status (cor) do caminho [rel] (relativo à [root]): mudança real do mapa
  /// agregado vence; senão herda untracked/ignored da raiz colapsada.
  GitFileStatus? statusForRelPath(String root, String rel) {
    if (rel.isEmpty) return null;
    final dirty = _gitTree[root]?[rel];
    if (dirty != null) return dirty;
    final info = _gitInfo[root];
    if (info == null) return null;
    if (info.isUntracked(rel)) return GitFileStatus.untracked;
    if (info.isIgnored(rel)) return GitFileStatus.ignored;
    return null;
  }

  // ---- comandos -------------------------------------------------------------

  /// Sync = `git pull` e, se OK, `git push` no repo em [repoPath]. Stream ao vivo.
  GitRun sync(String repoPath) => _runner.syncPullPush(repoPath);

  /// `git pull` no repo em [repoPath].
  GitRun pull(String repoPath) => _runner.run(repoPath, const ['pull']);

  /// `git push` no repo em [repoPath].
  GitRun push(String repoPath) => _runner.run(repoPath, const ['push']);

  /// Roda um git rápido e devolve `null` (exit 0) ou a saída como erro.
  Future<String?> collect(String root, List<String> args) async {
    final run = _runner.run(root, args);
    final lines = <String>[];
    final sub = run.output.listen(lines.add);
    final code = await run.exitCode;
    await sub.cancel();
    return code == 0 ? null : lines.join('\n');
  }

  // ---- ciclo de vida --------------------------------------------------------

  /// (Re)lê o estado git de um projeto e notifica se mudou. Chamado no boot
  /// (todos), ao selecionar e no fim de turno do agente (que pode ter mexido
  /// em arquivos). Reavalia as **roots** (implícitas, do filesystem) e lê o
  /// git de cada uma — single-root é o caso N=1 e se comporta como sempre.
  Future<void> refresh(String projectId) async {
    final path = resolvePath?.call(projectId);
    // Sink único de git — barra o Cockpit (sem pasta) de uma vez: cobre o
    // watcher, o poll e o refresh manual/fim-de-turno.
    if (path == null || (isSystemTerminal?.call(projectId) ?? false)) return;

    final roots = deriveRoots(path);
    final oldRoots = _rootsByProject[projectId];
    final rootsChanged = !listEquals(oldRoots, roots);
    if (rootsChanged) {
      // Roots que sumiram (repo removido / .git criado na mãe) → limpa estado.
      for (final gone in (oldRoots ?? const <String>[]).where(
        (r) => !roots.contains(r),
      )) {
        _gitInfo.remove(gone);
        _gitTree.remove(gone);
      }
      _rootsByProject[projectId] = roots;
    }

    var changed = rootsChanged;
    for (final root in roots) {
      final info = await _reader.read(root);
      // Evita rebuild se nada mudou (branch + ahead/behind + mapa de arquivos).
      final old = _gitInfo[root];
      if (old == info) {
        _gitInfo[root] = info; // garante a chave mesmo sem mudança visível
        continue;
      }
      _gitInfo[root] = info;
      _gitTree[root] = _buildGitTree(info?.files);
      changed = true;
    }
    if (changed) notifyListeners();
  }

  /// Descarta o estado git de um projeto removido (chaveado por root path).
  void forget(String projectId) {
    for (final root in _rootsByProject[projectId] ?? [projectId]) {
      _gitInfo.remove(root);
      _gitTree.remove(root);
    }
    _rootsByProject.remove(projectId);
  }

  /// (Re)inicia o watcher de filesystem do projeto **selecionado** → mantém a
  /// árvore/branch atualizadas ao vivo conforme o disco muda (o agente edita
  /// arquivos, troca de branch, comita). No-op se já observa esse mesmo path.
  void watchProject(String? projectId) {
    // Cockpit não tem pasta → nunca observa (evita `Directory('').watch`).
    if (projectId != null && (isSystemTerminal?.call(projectId) ?? false)) {
      _gitWatch?.cancel();
      _gitWatchDebounce?.cancel();
      _gitWatchRetry?.cancel();
      _gitWatch = null;
      _gitWatchPath = null;
      return;
    }
    final path = projectId == null ? null : resolvePath?.call(projectId);
    if (path == _gitWatchPath) return; // já observando este projeto
    _gitWatch?.cancel();
    _gitWatchDebounce?.cancel();
    _gitWatchRetry?.cancel();
    _gitWatch = null;
    _gitWatchPath = path;
    if (path == null || projectId == null) return;
    try {
      _gitWatch = _directoryWatch(path).listen(
        (event) => _onFsEvent(projectId, event),
        // A subscription pode morrer sozinha (erro de FSEvents/inotify, limite
        // de FDs, dir recriada). O retry é atrasado: reabrir imediatamente uma
        // pasta removida cria um loop de erro/re-arm que monopoliza o event loop
        // (caso exato de remover a worktree selecionada no Linux release).
        onError: (_) => _scheduleWatchRetry(path),
        onDone: () => _scheduleWatchRetry(path),
        cancelOnError: true,
      );
    } catch (_) {
      _scheduleWatchRetry(path);
    }
  }

  /// Re-arma o watcher com backoff se a subscription do projeto [path] morreu.
  ///
  /// No Linux, observar uma pasta inexistente falha de forma assíncrona e
  /// imediata. Sem o atraso, `onError → watchProject → onError` vira um loop
  /// apertado que impede a UI e até a continuação de `git worktree remove` de
  /// rodarem. No disparo também recalculamos a seleção: durante o atraso a
  /// worktree removida pode ter devolvido o foco ao workspace pai.
  void _scheduleWatchRetry(String path) {
    if (_gitWatchPath != path) return; // já trocaram de projeto → ignora
    _gitWatch = null;
    _gitWatchRetry?.cancel();
    _gitWatchRetry = Timer(_watchRetryDelay, () {
      _gitWatchRetry = null;
      if (_gitWatchPath != path) return;
      final selected = selectedProjectId?.call();
      _gitWatchPath = null; // libera o guard de [watchProject]
      watchProject(selected);
    });
  }

  /// (Re)inicia o poll periódico de git dos [pollTargets]. Ver [_gitPoll].
  void startPoll() {
    _gitPoll?.cancel();
    _gitPoll = Timer.periodic(_gitPollInterval, (_) {
      for (final id in pollTargets?.call() ?? const <String>[]) {
        unawaited(refresh(id));
      }
      onPoll?.call();
    });
  }

  /// Evento de filesystem do watcher. Filtra o ruído interno do `.git/` (o
  /// próprio `git status` mexe em `index.lock` etc. → loop), exceto `HEAD` e
  /// `index`, que sinalizam checkout/commit/staging. Debounce junta rajadas.
  void _onFsEvent(String projectId, FileSystemEvent event) {
    final p = event.path.replaceAll('\\', '/');
    final gitIdx = p.indexOf('/.git/');
    if (gitIdx != -1) {
      final rest = p.substring(gitIdx + 6); // depois de '/.git/'
      if (rest != 'HEAD' && rest != 'index') return;
    } else if (event.type == FileSystemEvent.create ||
        event.type == FileSystemEvent.delete ||
        event.type == FileSystemEvent.move) {
      // Mudança estrutural no working tree → árvore de arquivos relê as
      // pastas abertas (modify não muda a estrutura, só o conteúdo).
      _fileTreeWatchDebounce?.cancel();
      _fileTreeWatchDebounce = Timer(
        const Duration(milliseconds: 400),
        () => onStructuralFsChange?.call(),
      );
    }
    _gitWatchDebounce?.cancel();
    _gitWatchDebounce = Timer(const Duration(milliseconds: 400), () {
      unawaited(refresh(projectId));
    });
  }

  /// Deriva as roots git de uma pasta (síncrono, raso — só `existsSync`):
  /// - `path/.git` existe (dir **ou arquivo** — worktrees usam arquivo) →
  ///   `[path]` (single-root; monorepo é isso, N=1).
  /// - senão, filhas imediatas com `.git` → multi-root (assinatura de multirepo).
  /// - nenhuma → `[path]` (pasta comum, sem git — comportamento atual).
  ///
  /// Filha que é **worktree linkada de um repo-irmão** NÃO vira root: ela já
  /// aparece como fork da irmã (via `git worktree list`); promovê-la a root
  /// fazia o mesmo worktree ser descoberto duas vezes e duplicava o fork na
  /// rail. Worktree de repo de **fora** do workspace segue sendo root (é a
  /// única presença daquele repo aqui).
  @visibleForTesting
  static List<String> deriveRoots(String path) {
    if (path.isEmpty) return const [];
    if (FileSystemEntity.typeSync('$path/.git') !=
        FileSystemEntityType.notFound) {
      return [path];
    }
    final roots = <String>[];
    try {
      for (final entry in Directory(path).listSync(followLinks: false)) {
        if (entry is! Directory) continue;
        final name = entry.path.split(Platform.pathSeparator).last;
        if (name.startsWith('.')) continue;
        if (FileSystemEntity.typeSync('${entry.path}/.git') !=
            FileSystemEntityType.notFound) {
          roots.add(entry.path.replaceAll('\\', '/'));
        }
      }
    } catch (_) {
      return [path]; // pasta ilegível → trata como comum
    }
    if (roots.isEmpty) return [path];
    final linked = roots.where((r) => _isWorktreeOfSibling(r, roots)).toSet();
    roots.removeWhere(linked.contains);
    roots.sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
    return roots;
  }

  /// `true` se [candidate] é worktree linkada de outra entrada de [candidates]:
  /// `.git` é **arquivo** (`gitdir: <path>`) e o `<path>` mora sob o `.git/`
  /// de uma irmã. Comparação textual sobre paths normalizados com `/` — cobre
  /// o layout que o próprio git escreve (gitdir absoluto por default).
  static bool _isWorktreeOfSibling(String candidate, List<String> candidates) {
    final gitPath = '$candidate/.git';
    if (FileSystemEntity.typeSync(gitPath) != FileSystemEntityType.file) {
      return false;
    }
    String content;
    try {
      content = File(gitPath).readAsStringSync();
    } catch (_) {
      return false;
    }
    final match = RegExp(
      r'^gitdir:\s*(.+)$',
      multiLine: true,
    ).firstMatch(content);
    if (match == null) return false;
    var gitdir = match.group(1)!.trim().replaceAll('\\', '/');
    final isAbsolute =
        gitdir.startsWith('/') || RegExp(r'^[A-Za-z]:/').hasMatch(gitdir);
    if (!isAbsolute) gitdir = _normalizePath('$candidate/$gitdir');
    for (final other in candidates) {
      if (other == candidate) continue;
      if (gitdir == '$other/.git' || gitdir.startsWith('$other/.git/')) {
        return true;
      }
    }
    return false;
  }

  /// Resolve `.`/`..` de um path com separador `/` (pro gitdir relativo do
  /// `--relative-paths`); não toca no filesystem.
  static String _normalizePath(String path) {
    final out = <String>[];
    for (final seg in path.split('/')) {
      if (seg == '.' || seg.isEmpty && out.isNotEmpty) continue;
      if (seg == '..' && out.isNotEmpty && out.last != '..') {
        out.removeLast();
      } else {
        out.add(seg);
      }
    }
    return out.join('/');
  }

  /// Expande o mapa path→status (só arquivos) num índice que também cobre as
  /// **pastas ancestrais**, cada uma com o estado mais forte dos descendentes.
  static Map<String, GitFileStatus> _buildGitTree(
    Map<String, GitFileStatus>? files,
  ) {
    if (files == null || files.isEmpty) return const <String, GitFileStatus>{};
    final tree = <String, GitFileStatus>{};
    for (final entry in files.entries) {
      final path = entry.key; // relativo, separador '/'
      tree[path] = GitFileStatus.strongest(tree[path], entry.value)!;
      // Propaga pros ancestrais: 'a/b/c.dart' → 'a/b', 'a'.
      var slash = path.lastIndexOf('/');
      while (slash > 0) {
        final dir = path.substring(0, slash);
        tree[dir] = GitFileStatus.strongest(tree[dir], entry.value)!;
        slash = dir.lastIndexOf('/');
      }
    }
    return tree;
  }

  @override
  void dispose() {
    _gitWatch?.cancel();
    _gitWatchDebounce?.cancel();
    _gitWatchRetry?.cancel();
    _fileTreeWatchDebounce?.cancel();
    _gitPoll?.cancel();
    super.dispose();
  }
}
