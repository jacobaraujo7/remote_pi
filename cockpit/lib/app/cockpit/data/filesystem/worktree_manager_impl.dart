import 'dart:io';

import 'package:cockpit/app/cockpit/data/filesystem/git_binary.dart';
import 'package:cockpit/app/cockpit/domain/contracts/worktree_manager.dart';
import 'package:cockpit/app/cockpit/domain/entities/worktree.dart';
import 'package:cockpit/app/core/domain/result.dart';

/// Roda o binário `git` pra listar/criar/remover worktrees. O caminho do `git`
/// vem do [GitBinary] compartilhado (o app macOS **não herda o PATH do shell**).
class WorktreeManagerImpl implements WorktreeManager {
  WorktreeManagerImpl(this._gitBinary);

  final GitBinary _gitBinary;

  /// Onde as worktrees criadas pelo Cockpit moram, relativo à raiz do repo
  /// (decisão 2). Migrado de `.pi/remote/worktrees` → `.cockpit/worktrees`;
  /// worktrees antigas seguem funcionando (a descoberta é via
  /// `git worktree list`, não por caminho).
  static const String worktreesSubdir = '.cockpit/worktrees';

  Future<String> _resolveGit() => _gitBinary.resolve();

  @override
  Future<List<Worktree>> list(String repoPath) async {
    try {
      final git = await _resolveGit();
      final res = await Process.run(git, [
        '-C',
        repoPath,
        'worktree',
        'list',
        '--porcelain',
      ]);
      if (res.exitCode != 0) return const <Worktree>[];
      return _parsePorcelain(res.stdout as String);
    } catch (_) {
      return const <Worktree>[];
    }
  }

  @override
  Future<WorktreeNamespace> namespace(String repoPath) async {
    try {
      final git = await _resolveGit();
      final branchRes = await Process.run(git, [
        '-C',
        repoPath,
        'branch',
        '--format=%(refname:short)',
      ]);
      if (branchRes.exitCode != 0) return const WorktreeNamespace.empty();
      final branches = (branchRes.stdout as String)
          .split('\n')
          .map((l) => l.trim())
          .where((l) => l.isNotEmpty)
          .toSet();
      final worktreeNames = (await list(
        repoPath,
      )).map((w) => _basename(w.path)).toSet();
      return WorktreeNamespace(
        branches: branches,
        worktreeNames: worktreeNames,
      );
    } catch (_) {
      return const WorktreeNamespace.empty();
    }
  }

  @override
  Future<Result<Worktree, WorktreeOpError>> add(
    String repoPath,
    String name,
  ) async {
    try {
      final git = await _resolveGit();
      // Regra cross-plataforma: só cria worktree quando a branch NÃO existe.
      // Sem isso, `worktree add -b` falha ("branch already exists") e/ou deixa
      // o repo num estado meio-criado.
      if (await _branchExists(git, repoPath, name)) {
        return const Failure(
          WorktreeOpError('A branch with that name already exists.'),
        );
      }
      // Guard rail: garante `.cockpit/worktrees/` no `.gitignore` do repo ANTES
      // de materializar a worktree. Sob `.pi/` a pasta era ignorada de graça
      // (repos pi já ignoram `.pi`); sob `.cockpit/` isso não vale, e sem o
      // ignore o checkout apareceria como `untracked` no status do usuário.
      await _ensureIgnored(repoPath);
      final target = '$repoPath/$worktreesSubdir/$name';
      // Branch nova a partir do HEAD atual do repo (sem ref explícito).
      final res = await Process.run(git, [
        '-C',
        repoPath,
        'worktree',
        'add',
        target,
        '-b',
        name,
      ]);
      if (res.exitCode != 0) {
        return Failure(WorktreeOpError(_errText(res)));
      }
      // Devolve o path **como o git lista** (separadores nativos do SO), não o
      // `target` que montamos com `/`. No Windows o git lista com `\`, então o
      // `target` com `/` não casaria com `list()` → o chamador não encontraria
      // o fork recém-criado ("não apareceu na lista") e o dialog não fecharia.
      final created = (await list(repoPath)).where((w) => w.branch == name);
      return Success(
        created.isNotEmpty
            ? created.first
            : Worktree(path: target, branch: name, isDetached: false),
      );
    } catch (e) {
      return Failure(WorktreeOpError('Failed to create worktree: $e'));
    }
  }

  /// Guard rail: garante que `.cockpit/worktrees/` está no `.gitignore` da
  /// raiz do repo ANTES de criar a worktree — sem isso a pasta aninhada
  /// apareceria como untracked no repo principal. Só o subdir de worktrees é
  /// ignorado (não `.cockpit/` inteiro: o `tasks.json` de lá é comitável).
  /// Append idempotente; falha de IO não bloqueia a criação (best-effort).
  Future<void> _ensureIgnored(String repoPath) async {
    const entry = '$worktreesSubdir/';
    try {
      final file = File('$repoPath/.gitignore');
      if (await file.exists()) {
        final lines = (await file.readAsString()).split('\n');
        final ignored = lines.any((l) {
          final t = l.trim();
          return t == entry || t == '/$entry' || t == worktreesSubdir;
        });
        if (ignored) return;
        final content = await file.readAsString();
        final sep = content.isEmpty || content.endsWith('\n') ? '' : '\n';
        await file.writeAsString(
          '$sep$entry\n',
          mode: FileMode.append,
          flush: true,
        );
      } else {
        await file.writeAsString('$entry\n', flush: true);
      }
    } on FileSystemException {
      // Best-effort: um .gitignore ilegível não deve impedir o worktree.
    }
  }

  /// `true` se a branch local [name] já existe no repo.
  Future<bool> _branchExists(String git, String repoPath, String name) async {
    final res = await Process.run(git, [
      '-C',
      repoPath,
      'show-ref',
      '--verify',
      '--quiet',
      'refs/heads/$name',
    ]);
    return res.exitCode == 0;
  }

  @override
  Future<Result<void, WorktreeOpError>> remove(
    String repoPath,
    String worktreePath,
    String branch,
  ) async {
    try {
      final git = await _resolveGit();
      // 1. Remove a worktree primeiro (--force: o usuário já confirmou; remove
      //    mesmo com working tree suja — decisões 6, 9).
      final rmRes = await Process.run(git, [
        '-C',
        repoPath,
        'worktree',
        'remove',
        '--force',
        worktreePath,
      ]);
      if (rmRes.exitCode != 0) {
        return Failure(WorktreeOpError(_errText(rmRes)));
      }
      // 2. Só então apaga a branch (git recusa apagar branch em uso por worktree).
      if (branch.isNotEmpty) {
        final brRes = await Process.run(git, [
          '-C',
          repoPath,
          'branch',
          '-D',
          branch,
        ]);
        if (brRes.exitCode != 0) {
          return Failure(WorktreeOpError(_errText(brRes)));
        }
      }
      return const Success(null);
    } catch (e) {
      return Failure(WorktreeOpError('Failed to remove worktree: $e'));
    }
  }

  @override
  Future<bool> isBranchMerged(String repoPath, String branch) async {
    if (branch.isEmpty) return false;
    try {
      final git = await _resolveGit();
      // Branches já mergeadas no HEAD do checkout principal. Se a branch do fork
      // aparece aqui, foi mergeada (decisão 6). Em dúvida/erro → false (aviso).
      //
      // NB: `--merged` aceita um `<commit>` opcional e engoliria um `--format`
      // seguinte como objeto ("malformed object name"), então parseamos o output
      // plano e tiramos o marcador de linha (`* ` atual, `+ ` em worktree, `  `).
      final res = await Process.run(git, [
        '-C',
        repoPath,
        'branch',
        '--merged',
      ]);
      if (res.exitCode != 0) return false;
      final merged = (res.stdout as String)
          .split('\n')
          .map((l) => l.replaceFirst(RegExp(r'^[*+]?\s+'), '').trim())
          .where((l) => l.isNotEmpty)
          .toSet();
      return merged.contains(branch);
    } catch (_) {
      return false;
    }
  }

  /// Parseia `git worktree list --porcelain`, **descartando a primeira entrada**
  /// (a worktree principal = o próprio workspace).
  List<Worktree> _parsePorcelain(String out) {
    final blocks = out.split('\n\n');
    final result = <Worktree>[];
    for (var i = 0; i < blocks.length; i++) {
      final block = blocks[i].trim();
      if (block.isEmpty) continue;
      String? path;
      String? head;
      String? branch;
      var detached = false;
      var bare = false;
      for (final line in block.split('\n')) {
        if (line.startsWith('worktree ')) {
          path = line.substring('worktree '.length).trim();
        } else if (line.startsWith('HEAD ')) {
          head = line.substring('HEAD '.length).trim();
        } else if (line.startsWith('branch ')) {
          final ref = line.substring('branch '.length).trim();
          branch = ref.startsWith('refs/heads/')
              ? ref.substring('refs/heads/'.length)
              : ref;
        } else if (line == 'detached') {
          detached = true;
        } else if (line == 'bare') {
          bare = true;
        }
      }
      // Primeira entrada (principal) e repos bare não viram fork.
      if (i == 0 || bare || path == null) continue;
      result.add(
        Worktree(
          path: path,
          branch: detached
              ? (head != null && head.length >= 7
                    ? head.substring(0, 7)
                    : 'HEAD')
              : (branch ?? 'HEAD'),
          isDetached: detached,
        ),
      );
    }
    return result;
  }

  String _basename(String path) {
    // Aceita separador `/` (POSIX) e `\` (Windows, como o git lista lá).
    var p = path;
    while ((p.endsWith('/') || p.endsWith(r'\')) && p.length > 1) {
      p = p.substring(0, p.length - 1);
    }
    final idx = p.lastIndexOf(RegExp(r'[/\\]'));
    return idx >= 0 ? p.substring(idx + 1) : p;
  }

  String _errText(ProcessResult res) {
    final err = (res.stderr as String).trim();
    if (err.isNotEmpty) return err;
    final out = (res.stdout as String).trim();
    return out.isNotEmpty ? out : 'git exited with code ${res.exitCode}';
  }
}
