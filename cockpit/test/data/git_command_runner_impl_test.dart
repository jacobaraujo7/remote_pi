import 'dart:io';

import 'package:cockpit/app/cockpit/data/filesystem/git_binary.dart';
import 'package:cockpit/app/cockpit/data/filesystem/git_command_runner_impl.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final runner = GitCommandRunnerImpl(GitBinary());
  late Directory repo;

  Future<ProcessResult> git(List<String> args) =>
      Process.run('git', args, workingDirectory: repo.path);

  Future<bool> gitAvailable() async {
    try {
      return (await Process.run('git', ['--version'])).exitCode == 0;
    } catch (_) {
      return false;
    }
  }

  setUp(() async {
    repo = await Directory.systemTemp.createTemp('cockpit_runner_test_');
    await git(['init']);
    await git(['config', 'user.email', 'test@example.com']);
    await git(['config', 'user.name', 'Test']);
    await File('${repo.path}/a.txt').writeAsString('x\n');
    await git(['add', '.']);
    await git(['commit', '-m', 'init']);
  });

  tearDown(() async {
    if (await repo.exists()) await repo.delete(recursive: true);
  });

  test('run(status) → exit 0 e stream com saída', () async {
    if (!await gitAvailable()) {
      markTestSkipped('git não disponível');
      return;
    }
    final run = runner.run(repo.path, const ['status']);
    final lines = await run.output.toList();
    expect(await run.exitCode, 0);
    expect(lines, isNotEmpty);
  });

  test('syncPullPush sem upstream → falha no pull e NÃO tenta push', () async {
    if (!await gitAvailable()) {
      markTestSkipped('git não disponível');
      return;
    }
    final run = runner.syncPullPush(repo.path);
    final lines = await run.output.toList();
    final exit = await run.exitCode;
    expect(exit, isNot(0)); // pull sem upstream falha
    expect(lines.any((l) => l.contains(r'$ git pull')), isTrue);
    // Push nunca é iniciado quando o pull falha.
    expect(lines.any((l) => l.contains(r'$ git push')), isFalse);
  });
}
