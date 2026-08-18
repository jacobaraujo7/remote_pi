import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:cockpit/app/cockpit/data/filesystem/git_binary.dart';
import 'package:cockpit/app/cockpit/domain/contracts/worktree_manager.dart';
import 'package:cockpit/app/cockpit/domain/entities/worktree.dart';
import 'package:cockpit/app/core/data/setup/remote_pi_resolver.dart';
import 'package:cockpit/app/core/domain/result.dart';
import 'package:cockpit/app/core/utils/path_utils.dart';
import 'package:path/path.dart' as p;

/// Roda o binário `git` pra listar/criar/remover worktrees. O caminho do `git`
/// vem do [GitBinary] compartilhado (o app macOS **não herda o PATH do shell**).
///
/// `add` usa [Process.start] com streaming (stdout∥stderr) e
/// [envWithNodeOnPath] pra hooks (ex.: post-checkout com `npx`/`node`) acharem
/// o binário — mesmo tratamento do [GitCommandRunnerImpl].
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

      final remoteBranchRes = await Process.run(git, [
        '-C',
        repoPath,
        'branch',
        '-r',
        '--format=%(refname:short)',
      ]);
      final remoteBranches = remoteBranchRes.exitCode == 0
          ? (remoteBranchRes.stdout as String)
                .split('\n')
                .map((l) => l.trim())
                .where((l) => l.isNotEmpty && !l.contains('->'))
                .toSet()
          : const <String>{};

      String? defaultBranch;
      final originHeadRes = await Process.run(git, [
        '-C',
        repoPath,
        'symbolic-ref',
        'refs/remotes/origin/HEAD',
        '--short',
      ]);
      if (originHeadRes.exitCode == 0) {
        final val = (originHeadRes.stdout as String).trim();
        if (val.isNotEmpty) {
          defaultBranch = val;
        }
      }
      if (defaultBranch == null || defaultBranch.isEmpty) {
        if (remoteBranches.contains('origin/main')) {
          defaultBranch = 'origin/main';
        } else if (remoteBranches.contains('origin/master')) {
          defaultBranch = 'origin/master';
        } else if (remoteBranches.isNotEmpty) {
          defaultBranch = remoteBranches.first;
        } else {
          final headRes = await Process.run(git, [
            '-C',
            repoPath,
            'rev-parse',
            '--abbrev-ref',
            'HEAD',
          ]);
          if (headRes.exitCode == 0) {
            final val = (headRes.stdout as String).trim();
            if (val.isNotEmpty) {
              defaultBranch = val;
            }
          }
        }
      }

      final worktreeNames = (await list(
        repoPath,
      )).map((w) => _basename(w.path)).toSet();
      return WorktreeNamespace(
        branches: branches,
        worktreeNames: worktreeNames,
        remoteBranches: remoteBranches,
        defaultBranch: defaultBranch,
      );
    } catch (_) {
      return const WorktreeNamespace.empty();
    }
  }

  @override
  Future<bool> hasPostCheckoutHook(String repoPath) async {
    try {
      final git = await _resolveGit();
      final res = await Process.run(git, [
        '-C',
        repoPath,
        'rev-parse',
        '--git-path',
        'hooks',
      ]);
      if (res.exitCode != 0) return false;
      final hooksDir = (res.stdout as String).trim();
      if (hooksDir.isEmpty) return false;
      // --git-path pode ser relativo ao repo.
      final resolved = p.isAbsolute(hooksDir)
          ? hooksDir
          : p.normalize(p.join(repoPath, hooksDir));
      return File(p.join(resolved, 'post-checkout')).existsSync();
    } catch (_) {
      return false;
    }
  }

  @override
  WorktreeAddRun<Worktree> add(
    String repoPath,
    String name, {
    String? baseRef,
    bool copyIgnored = false,
    bool copyUntracked = false,
    bool fetchRemote = true,
  }) {
    final controller = StreamController<String>();
    final resultCompleter = Completer<Result<Worktree, WorktreeOpError>>();

    () async {
      try {
        final git = await _resolveGit();
        if (fetchRemote) {
          await _emit(controller, 'Fetching remote branch updates...');
          try {
            final fetchRes = await Process.run(git, ['-C', repoPath, 'fetch']);
            if (fetchRes.exitCode != 0) {
              await _emit(
                controller,
                'Warning: git fetch failed. Attempting worktree creation anyway.',
              );
            }
          } catch (e) {
            await _emit(
              controller,
              'Warning: failed to run git fetch ($e). Attempting worktree creation anyway.',
            );
          }
        }
        // Regra cross-plataforma: só cria worktree quando a branch NÃO existe.
        // Sem isso, `worktree add -b` falha ("branch already exists") e/ou deixa
        // o repo num estado meio-criado.
        if (await _branchExists(git, repoPath, name)) {
          await _emit(controller, 'A branch with that name already exists.');
          resultCompleter.complete(
            const Failure(
              WorktreeOpError('A branch with that name already exists.'),
            ),
          );
          return;
        }
        // Guard rail: garante `.cockpit/worktrees/` no `.gitignore` do repo ANTES
        // de materializar a worktree. Sob `.pi/` a pasta era ignorada de graça
        // (repos pi já ignoram `.pi`); sob `.cockpit/` isso não vale, e sem o
        // ignore o checkout apareceria como `untracked` no status do usuário.
        await _ensureIgnored(repoPath);
        final target = '$repoPath/$worktreesSubdir/$name';
        final args = <String>['worktree', 'add', target, '-b', name, ?baseRef];
        await _emit(controller, '\$ git ${args.join(' ')}');
        final code = await _spawn(git, repoPath, args, controller);
        if (code != 0) {
          resultCompleter.complete(
            Failure(WorktreeOpError('git worktree add exited with code $code')),
          );
          return;
        }

        if (copyIgnored || copyUntracked) {
          await _emit(controller, 'Copying files to new worktree...');
          final filesToCopy = <String>{};
          if (copyIgnored) {
            final ignored = await _listGitFiles(git, repoPath, [
              'ls-files',
              '--others',
              '--ignored',
              '--exclude-standard',
            ]);
            for (final f in ignored) {
              if (!f.startsWith('$worktreesSubdir/') &&
                  !f.startsWith('.pi/remote/worktrees/') &&
                  !f.startsWith('.git/')) {
                filesToCopy.add(f);
              }
            }
          }
          if (copyUntracked) {
            final changed = await _listUntrackedAndModifiedFiles(git, repoPath);
            for (final f in changed) {
              if (!f.startsWith('$worktreesSubdir/') &&
                  !f.startsWith('.pi/remote/worktrees/') &&
                  !f.startsWith('.git/')) {
                filesToCopy.add(f);
              }
            }
          }
          if (filesToCopy.isNotEmpty) {
            await _copyFiles(
              repoPath,
              target,
              filesToCopy.toList(),
              controller,
            );
          } else {
            await _emit(controller, 'No files to copy.');
          }
        }

        // Devolve o path **como o git lista** (separadores nativos do SO), não o
        // `target` que montamos com `/`. No Windows o git lista com `\`, então o
        // `target` com `/` não casaria com `list()` → o chamador não encontraria
        // o fork recém-criado ("não apareceu na lista") e o dialog não fecharia.
        final created = (await list(repoPath)).where((w) => w.branch == name);
        resultCompleter.complete(
          Success(
            created.isNotEmpty
                ? created.first
                : Worktree(path: target, branch: name, isDetached: false),
          ),
        );
      } catch (e) {
        await _emit(controller, 'Failed to create worktree: $e');
        if (!resultCompleter.isCompleted) {
          resultCompleter.complete(
            Failure(WorktreeOpError('Failed to create worktree: $e')),
          );
        }
      } finally {
        if (!controller.isClosed) await controller.close();
      }
    }();

    return WorktreeAddRun<Worktree>(
      output: controller.stream,
      result: resultCompleter.future,
    );
  }

  Future<List<String>> _listUntrackedAndModifiedFiles(
    String git,
    String repoPath,
  ) async {
    try {
      final res = await Process.run(git, [
        '-C',
        repoPath,
        'status',
        '--porcelain=v1',
        '-z',
        '-uall',
      ]);
      if (res.exitCode != 0) return const [];
      final stdout = res.stdout as String;
      if (stdout.isEmpty) return const [];
      final tokens = stdout.split('\u0000');
      final result = <String>[];
      for (var i = 0; i < tokens.length; i++) {
        final token = tokens[i];
        if (token.length < 4) continue;
        final x = token[0];
        final y = token[1];
        var path = token.substring(3);
        // Rename/copy no index ou worktree tem o path anterior no próximo token NUL
        if (x == 'R' || x == 'C' || y == 'R' || y == 'C') {
          i++;
        }
        if (path.endsWith('/')) {
          path = path.substring(0, path.length - 1);
        }
        if (path.isNotEmpty) {
          result.add(path);
        }
      }
      return result;
    } catch (_) {
      return const [];
    }
  }

  Future<List<String>> _listGitFiles(
    String git,
    String repoPath,
    List<String> args,
  ) async {
    try {
      final res = await Process.run(git, ['-C', repoPath, ...args]);
      if (res.exitCode != 0) return const [];
      return (res.stdout as String)
          .split('\n')
          .map((l) => l.trim())
          .where((l) => l.isNotEmpty)
          .toList();
    } catch (_) {
      return const [];
    }
  }

  Future<void> _copyFiles(
    String repoPath,
    String targetPath,
    List<String> relativePaths,
    StreamController<String> controller,
  ) async {
    var count = 0;

    // Deduplicate target parent directories and create them in parallel
    final parentDirs = relativePaths
        .map((relPath) => p.dirname(p.join(targetPath, relPath)))
        .toSet();
    final dirFutures = parentDirs.map(
      (dir) => Directory(dir).create(recursive: true),
    );
    try {
      await Future.wait(dirFutures);
    } catch (e) {
      await _emit(controller, 'Warning: failed to create directories: $e');
    }

    // Copy files in parallel, suppressing individual file logs
    final copyFutures = relativePaths.map((relPath) async {
      final src = p.join(repoPath, relPath);
      final dest = p.join(targetPath, relPath);
      try {
        final srcFile = File(src);
        if (await srcFile.exists()) {
          await srcFile.copy(dest);
          count++;
        } else {
          final destFile = File(dest);
          if (await destFile.exists()) {
            await destFile.delete();
          }
        }
      } catch (e) {
        await _emit(controller, 'Warning: failed to copy $relPath: $e');
      }
    });

    await Future.wait(copyFutures);
    await _emit(controller, 'Copied $count file(s) to new worktree.');
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

  /// Spawna `git -C <repoPath> <args>`, encaminha stdout+stderr (por linha) e
  /// devolve o exit code.
  Future<int> _spawn(
    String git,
    String repoPath,
    List<String> args,
    StreamController<String> controller,
  ) async {
    try {
      final proc = await Process.start(git, [
        '-C',
        repoPath,
        ...args,
      ], environment: await envWithNodeOnPath());
      final done = <Future<void>>[];
      for (final stream in [proc.stdout, proc.stderr]) {
        done.add(
          stream
              .transform(utf8.decoder)
              .transform(const LineSplitter())
              .forEach((line) {
                if (!controller.isClosed) controller.add(line);
              }),
        );
      }
      await Future.wait(done);
      return await proc.exitCode;
    } catch (e) {
      await _emit(controller, 'Failed to run git: $e');
      return -1;
    }
  }

  Future<void> _emit(StreamController<String> controller, String line) async {
    if (!controller.isClosed) controller.add(line);
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
          // Fronteira: o git no Windows pode emitir o caminho do worktree com
          // separador nativo; o resto do app compara com `/`.
          path = normalizePath(line.substring('worktree '.length).trim());
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
