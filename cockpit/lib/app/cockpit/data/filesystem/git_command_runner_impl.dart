import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:cockpit/app/cockpit/data/filesystem/git_binary.dart';
import 'package:cockpit/app/cockpit/domain/contracts/git_command_runner.dart';

/// Roda comandos `git` via `Process.start` pra **streaming ao vivo** (stdout e
/// stderr mesclados por linha). O caminho do `git` vem do [GitBinary]
/// compartilhado. Não remove worktrees — em um merge bem-sucedido, o
/// `CockpitViewModel` faz a limpeza (reusa `removeWorktree`).
class GitCommandRunnerImpl implements GitCommandRunner {
  GitCommandRunnerImpl(this._gitBinary);

  final GitBinary _gitBinary;

  @override
  GitRun run(String repoPath, List<String> args) {
    final controller = StreamController<String>();
    final exitCompleter = Completer<int>();
    _spawn(repoPath, args, controller, header: null).then((code) {
      exitCompleter.complete(code);
      if (!controller.isClosed) controller.close();
    });
    return GitRun(output: controller.stream, exitCode: exitCompleter.future);
  }

  @override
  GitRun syncPullPush(String repoPath) {
    final controller = StreamController<String>();
    final exitCompleter = Completer<int>();
    () async {
      final pull = await _spawn(
        repoPath,
        const ['pull'],
        controller,
        header: r'$ git pull',
      );
      if (pull != 0) {
        exitCompleter.complete(pull);
        if (!controller.isClosed) controller.close();
        return;
      }
      if (!controller.isClosed) controller.add('');
      final push = await _spawn(
        repoPath,
        const ['push'],
        controller,
        header: r'$ git push',
      );
      exitCompleter.complete(push);
      if (!controller.isClosed) controller.close();
    }();
    return GitRun(output: controller.stream, exitCode: exitCompleter.future);
  }

  @override
  GitMergeOutcome mergeIntoParent(
    String parentPath,
    String worktreePath,
    String worktreeBranch,
  ) {
    final controller = StreamController<String>();
    final statusCompleter = Completer<GitMergeStatus>();

    Future<void> add(String line) async {
      if (!controller.isClosed) controller.add(line);
    }

    () async {
      try {
        // 1. Pré-check: worktree sujo → não faz nada (evita perda de dados).
        if (await _isDirty(worktreePath)) {
          await add(
            'Worktree has uncommitted changes. '
            'Commit or discard changes in this worktree first.',
          );
          statusCompleter.complete(GitMergeStatus.dirtyWorktree);
          return;
        }

        // 2. Merge no checkout do pai (que já está na branch dele).
        final merge = await _spawn(
          parentPath,
          ['merge', worktreeBranch],
          controller,
          header: '\$ git merge $worktreeBranch',
        );
        if (merge != 0) {
          // Conflito → aborta pra deixar o pai intocado.
          await add('');
          await _spawn(
            parentPath,
            const ['merge', '--abort'],
            controller,
            header: r'$ git merge --abort',
          );
          await add('');
          await add('Merge aborted — parent branch untouched.');
          statusCompleter.complete(GitMergeStatus.conflict);
          return;
        }

        // 3. Sucesso — a limpeza do worktree fica a cargo do ViewModel.
        await add('');
        await add('Merge complete.');
        statusCompleter.complete(GitMergeStatus.merged);
      } catch (e) {
        await add('Unexpected error: $e');
        if (!statusCompleter.isCompleted) {
          statusCompleter.complete(GitMergeStatus.error);
        }
      } finally {
        if (!controller.isClosed) await controller.close();
      }
    }();

    return GitMergeOutcome(
      status: statusCompleter.future,
      output: controller.stream,
    );
  }

  /// `true` se o working tree em [path] tem mudanças (staged ou não).
  Future<bool> _isDirty(String path) async {
    final git = await _gitBinary.resolve();
    final res = await Process.run(git, ['-C', path, 'status', '--porcelain']);
    if (res.exitCode != 0) return false; // não-git → nada a bloquear
    return (res.stdout as String).trim().isNotEmpty;
  }

  /// Spawna `git -C <repoPath> <args>`, encaminha stdout+stderr (por linha) para
  /// [controller] e devolve o exit code. [header] (opcional) é emitido antes da
  /// saída pra marcar a fronteira entre comandos numa sequência.
  Future<int> _spawn(
    String repoPath,
    List<String> args,
    StreamController<String> controller, {
    required String? header,
  }) async {
    if (header != null && !controller.isClosed) controller.add(header);
    try {
      final git = await _gitBinary.resolve();
      final proc = await Process.start(git, ['-C', repoPath, ...args]);
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
      if (!controller.isClosed) controller.add('Failed to run git: $e');
      return -1;
    }
  }
}
