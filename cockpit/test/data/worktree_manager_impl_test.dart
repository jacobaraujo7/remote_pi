import 'dart:io';

import 'package:cockpit/app/cockpit/data/filesystem/git_binary.dart';
import 'package:cockpit/app/cockpit/data/filesystem/worktree_manager_impl.dart';
import 'package:cockpit/app/cockpit/domain/contracts/worktree_manager.dart';
import 'package:cockpit/app/cockpit/domain/entities/worktree.dart';
import 'package:cockpit/app/core/domain/result.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final manager = WorktreeManagerImpl(GitBinary());
  late Directory repo;
  late String mainBranch;

  Future<ProcessResult> git(List<String> args, {String? cwd}) =>
      Process.run('git', args, workingDirectory: cwd ?? repo.path);

  Future<bool> gitAvailable() async {
    try {
      return (await Process.run('git', ['--version'])).exitCode == 0;
    } catch (_) {
      return false;
    }
  }

  setUp(() async {
    repo = await Directory.systemTemp.createTemp('cockpit_wt_test_');
    await git(['init']);
    await git(['config', 'user.email', 'test@example.com']);
    await git(['config', 'user.name', 'Test']);
    await File('${repo.path}/README.md').writeAsString('hello');
    await git(['add', '.']);
    await git(['commit', '-m', 'init']);
    mainBranch = (await git([
      'rev-parse',
      '--abbrev-ref',
      'HEAD',
    ])).stdout.toString().trim();
  });

  tearDown(() async {
    if (await repo.exists()) await repo.delete(recursive: true);
  });

  test('add → list → namespace → remove (ciclo completo)', () async {
    if (!await gitAvailable()) {
      markTestSkipped('git não disponível no ambiente');
      return;
    }

    // add: cria worktree aninhada + branch nova a partir do HEAD.
    final added = await manager.add(repo.path, 'feat/sso');
    expect(
      added.isSuccess,
      isTrue,
      reason: added.fold((_) => '', (e) => e.message),
    );
    final wt = (added as Success<Worktree, WorktreeOpError>).value;
    expect(Directory(wt.path).existsSync(), isTrue);
    expect(wt.path, endsWith('/.pi/remote/worktrees/feat/sso'));
    expect(wt.branch, 'feat/sso');
    expect(wt.isDetached, isFalse);

    // list: exclui a raiz, inclui o novo fork.
    final list = await manager.list(repo.path);
    expect(list.length, 1);
    expect(list.single.branch, 'feat/sso');

    // namespace: branch base + branch do worktree + basename do worktree.
    final ns = await manager.namespace(repo.path);
    expect(ns.branches, containsAll(<String>[mainBranch, 'feat/sso']));
    expect(ns.worktreeNames, contains('sso'));

    // remove: apaga pasta E branch (decisão 6).
    final removed = await manager.remove(repo.path, wt.path, 'feat/sso');
    expect(
      removed.isSuccess,
      isTrue,
      reason: removed.fold((_) => '', (e) => e.message),
    );
    expect(Directory(wt.path).existsSync(), isFalse);
    expect(await manager.list(repo.path), isEmpty);
    expect(
      (await manager.namespace(repo.path)).branches,
      isNot(contains('feat/sso')),
    );
  });

  test('add falha (Failure com mensagem) em branch já existente', () async {
    if (!await gitAvailable()) {
      markTestSkipped('git não disponível no ambiente');
      return;
    }
    final dup = await manager.add(repo.path, mainBranch);
    expect(dup.isFailure, isTrue);
    expect(
      (dup as Failure<Worktree, WorktreeOpError>).error.message,
      isNotEmpty,
    );
  });

  test('list/namespace de pasta não-git devolvem vazio', () async {
    final tmp = await Directory.systemTemp.createTemp('cockpit_nogit_');
    addTearDown(() async {
      if (await tmp.exists()) await tmp.delete(recursive: true);
    });
    expect(await manager.list(tmp.path), isEmpty);
    expect((await manager.namespace(tmp.path)).branches, isEmpty);
  });

  test(
    'isBranchMerged: true sem commits novos, false após commit no fork',
    () async {
      if (!await gitAvailable()) {
        markTestSkipped('git não disponível no ambiente');
        return;
      }
      final added = await manager.add(repo.path, 'feat/x');
      final wt = (added as Success<Worktree, WorktreeOpError>).value;

      // Recém-criada do HEAD, sem commits → mergeada (tip alcançável do HEAD).
      expect(await manager.isBranchMerged(repo.path, 'feat/x'), isTrue);

      // Commit novo no worktree → o tip deixa de ser alcançável do HEAD principal.
      await File('${wt.path}/new.txt').writeAsString('x');
      await git(['add', '.'], cwd: wt.path);
      await git(['commit', '-m', 'work'], cwd: wt.path);
      expect(await manager.isBranchMerged(repo.path, 'feat/x'), isFalse);

      // Branch vazia / inexistente → false (mostra o aviso por segurança).
      expect(await manager.isBranchMerged(repo.path, ''), isFalse);
      expect(await manager.isBranchMerged(repo.path, 'nao/existe'), isFalse);
    },
  );
}
