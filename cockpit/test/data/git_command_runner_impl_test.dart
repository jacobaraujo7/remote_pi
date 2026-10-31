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

  test('clone de repo local → exit 0 e pasta criada', () async {
    if (!await gitAvailable()) {
      markTestSkipped('git não disponível');
      return;
    }
    final dest = Directory(
      '${repo.parent.path}/${repo.uri.pathSegments[repo.uri.pathSegments.length - 2]}_clone',
    );
    addTearDown(() async {
      if (await dest.exists()) await dest.delete(recursive: true);
    });
    final run = runner.clone(repo.path, dest.path);
    final lines = await run.output.toList();
    expect(await run.exitCode, 0);
    expect(lines.first, startsWith(r'$ git clone'));
    expect(File('${dest.path}/a.txt').existsSync(), isTrue);
  });

  test('clone pra pasta não vazia → falha sem pendurar', () async {
    if (!await gitAvailable()) {
      markTestSkipped('git não disponível');
      return;
    }
    final run = runner.clone(repo.path, repo.path);
    await run.output.toList();
    expect(await run.exitCode, isNot(0));
  });

  test('GitProgressThrottle passa 1 linha por dezena e a final', () {
    final t = GitProgressThrottle();
    final lines = [
      'Cloning into \'repo\'...',
      for (var i = 0; i <= 100; i++) 'Receiving objects:  $i% ($i/100)',
      'Receiving objects: 100% (100/100), done.',
    ];
    final kept = lines.where(t.accept).toList();
    expect(kept.first, startsWith('Cloning into'));
    expect(kept.last, endsWith('done.'));
    // 0..9 dezenas + 100% + done + "Cloning into".
    expect(kept.length, 13);
  });

  group('cloneProcessEnvironment', () {
    test('sem SSH do usuário: desliga prompts e usa SSH em BatchMode', () {
      final env = cloneProcessEnvironment({'PATH': '/usr/bin'});
      expect(env['GIT_TERMINAL_PROMPT'], '0');
      expect(env['GIT_SSH_COMMAND'], kCloneSshCommand);
      expect(env['PATH'], '/usr/bin');
    });

    test('respeita GIT_SSH_COMMAND do usuário', () {
      final env = cloneProcessEnvironment({'GIT_SSH_COMMAND': 'ssh -i k'});
      expect(env['GIT_SSH_COMMAND'], 'ssh -i k');
    });

    test('Windows com plink (GIT_SSH): não sobrescreve', () {
      final env = cloneProcessEnvironment({
        'GIT_SSH': r'C:\Program Files\PuTTY\plink.exe',
      });
      expect(env.containsKey('GIT_SSH_COMMAND'), isFalse);
      expect(env['GIT_SSH'], r'C:\Program Files\PuTTY\plink.exe');
    });

    test(
      'core.sshCommand configurado (ex.: OpenSSH do Windows): não sobrescreve',
      () {
        final env = cloneProcessEnvironment(
          const {},
          configuredSshCommand: r'C:/Windows/System32/OpenSSH/ssh.exe',
        );
        expect(env.containsKey('GIT_SSH_COMMAND'), isFalse);
        expect(env['GIT_TERMINAL_PROMPT'], '0');
      },
    );
  });
}
