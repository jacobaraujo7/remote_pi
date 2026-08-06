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

  /// Aguarda o [WorktreeAddRun] e devolve o resultado (descarta o stream).
  Future<Result<Worktree, WorktreeOpError>> addResult(
    String name, {
    String? baseRef,
  }) {
    final run = manager.add(repo.path, name, baseRef: baseRef);
    // Drena o stream pra não vazar o controller.
    run.output.drain<void>();
    return run.result;
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
    final added = await addResult('feat/sso');
    expect(
      added.isSuccess,
      isTrue,
      reason: added.fold((_) => '', (e) => e.message),
    );
    final wt = (added as Success<Worktree, WorktreeOpError>).value;
    expect(Directory(wt.path).existsSync(), isTrue);
    expect(wt.path, endsWith('/.cockpit/worktrees/feat/sso'));
    expect(wt.branch, 'feat/sso');
    expect(wt.isDetached, isFalse);

    // Guard rail: o subdir das worktrees entrou no .gitignore da raiz e o
    // repo principal não vê a pasta aninhada como untracked.
    final gitignore = File('${repo.path}/.gitignore');
    expect(gitignore.existsSync(), isTrue);
    expect(
      gitignore.readAsStringSync().split('\n'),
      contains('.cockpit/worktrees/'),
    );
    final status = await git(['status', '--porcelain']);
    expect(status.stdout.toString(), isNot(contains('.cockpit')));

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
    final dup = await addResult(mainBranch);
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
      final added = await addResult('feat/x');
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

  test('hasPostCheckoutHook: false sem hook, true com arquivo', () async {
    if (!await gitAvailable()) {
      markTestSkipped('git não disponível no ambiente');
      return;
    }
    expect(await manager.hasPostCheckoutHook(repo.path), isFalse);

    final hooksDir = (await git([
      'rev-parse',
      '--git-path',
      'hooks',
    ])).stdout.toString().trim();
    final hookPath = hooksDir.startsWith('/')
        ? '$hooksDir/post-checkout'
        : '${repo.path}/$hooksDir/post-checkout';
    await File(hookPath).writeAsString('#!/bin/sh\necho hook-ok\n');
    // Não precisa ser executável pra detecção — só existência do arquivo.
    expect(await manager.hasPostCheckoutHook(repo.path), isTrue);
  });

  test('add com post-checkout: stream contém saída do hook', () async {
    if (!await gitAvailable()) {
      markTestSkipped('git não disponível no ambiente');
      return;
    }
    final hooksDir = (await git([
      'rev-parse',
      '--git-path',
      'hooks',
    ])).stdout.toString().trim();
    final hookPath = hooksDir.startsWith('/')
        ? '$hooksDir/post-checkout'
        : '${repo.path}/$hooksDir/post-checkout';
    await File(
      hookPath,
    ).writeAsString('#!/bin/sh\necho post-checkout-marker\n');
    await Process.run('chmod', ['+x', hookPath]);

    final run = manager.add(repo.path, 'feat/hooked');
    final lines = <String>[];
    final sub = run.output.listen(lines.add);
    final added = await run.result;
    await sub.cancel();

    expect(added.isSuccess, isTrue, reason: lines.join('\n'));
    expect(
      lines.any((l) => l.contains('post-checkout-marker')),
      isTrue,
      reason: 'stream should include hook stdout; got:\n${lines.join('\n')}',
    );
  });

  test('add com copyIgnored e copyUntracked copia os arquivos corretos', () async {
    if (!await gitAvailable()) {
      markTestSkipped('git não disponível no ambiente');
      return;
    }

    // 1. Cria um arquivo ignorado
    await File('${repo.path}/.gitignore').writeAsString('.env\n');
    await git(['add', '.gitignore']);
    await git(['commit', '-m', 'ignore env']);
    final ignoredFile = File('${repo.path}/.env');
    await ignoredFile.writeAsString('SECRET=123');

    // 2. Cria um arquivo não rastreado
    final untrackedFile = File('${repo.path}/untracked.txt');
    await untrackedFile.writeAsString('untracked content');

    // 3. Cria worktree com cópia ativada
    final run = manager.add(
      repo.path,
      'feat/copy-enabled',
      copyIgnored: true,
      copyUntracked: true,
    );
    final lines = <String>[];
    final sub = run.output.listen(lines.add);
    final added = await run.result;
    await sub.cancel();

    expect(added.isSuccess, isTrue);
    final wt = (added as Success<Worktree, WorktreeOpError>).value;

    expect(File('${wt.path}/.env').existsSync(), isTrue);
    expect(File('${wt.path}/.env').readAsStringSync(), 'SECRET=123');
    expect(File('${wt.path}/untracked.txt').existsSync(), isTrue);
    expect(File('${wt.path}/untracked.txt').readAsStringSync(), 'untracked content');

    // 4. Cria outra worktree com cópias desativadas
    final runDisabled = manager.add(
      repo.path,
      'feat/copy-disabled',
      copyIgnored: false,
      copyUntracked: false,
    );
    final lines2 = <String>[];
    final sub2 = runDisabled.output.listen(lines2.add);
    final addedDisabled = await runDisabled.result;
    await sub2.cancel();

    expect(addedDisabled.isSuccess, isTrue);
    final wtDisabled = (addedDisabled as Success<Worktree, WorktreeOpError>).value;

    expect(File('${wtDisabled.path}/.env').existsSync(), isFalse);
    expect(File('${wtDisabled.path}/untracked.txt').existsSync(), isFalse);
  });
}
